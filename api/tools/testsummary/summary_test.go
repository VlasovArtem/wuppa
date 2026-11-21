package main

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func run(t *testing.T, fixture string) (out string, code int, logPath string) {
	t.Helper()
	f, err := os.Open(filepath.Join("testdata", fixture+".jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	logPath = filepath.Join(t.TempDir(), "test-unit.log")
	out, code = Summarize(f, "test-unit", logPath)
	return out, code, logPath
}

func lines(out string) []string {
	return strings.Split(strings.TrimRight(out, "\n"), "\n")
}

func lastLine(out string) string {
	l := lines(out)
	return l[len(l)-1]
}

func TestSummary(t *testing.T) {
	t.Run("all_pass", func(t *testing.T) {
		out, code, _ := run(t, "all_pass")
		if code != 0 {
			t.Errorf("exit code = %d, want 0", code)
		}
		ls := lines(out)
		if len(ls) != 1 {
			t.Fatalf("want only the RESULT line, got %q", out)
		}
		re := regexp.MustCompile(`^RESULT: PASS test-unit tests=3 skipped=1 duration=[0-9]+(\.[0-9]+)?s$`)
		if !re.MatchString(ls[0]) {
			t.Errorf("RESULT line = %q", ls[0])
		}
	})

	t.Run("one_failure", func(t *testing.T) {
		out, code, logPath := run(t, "one_failure")
		if code != 1 {
			t.Errorf("exit code = %d, want 1", code)
		}
		if !strings.Contains(out, "FAIL github.com/VlasovArtem/wuppa/api/internal/onefail.TestX (foo_test.go:6)") {
			t.Errorf("missing FAIL line in %q", out)
		}
		if !strings.Contains(out, "want 1 got 2") {
			t.Errorf("missing message line in %q", out)
		}
		if strings.Contains(out, "TestOK") {
			t.Errorf("passing test listed in %q", out)
		}
		want := "RESULT: FAIL test-unit failed=1 log=" + logPath
		if got := lastLine(out); got != want {
			t.Errorf("last line = %q, want %q", got, want)
		}
	})

	t.Run("subtest_failure", func(t *testing.T) {
		out, code, _ := run(t, "subtest_failure")
		if code != 1 {
			t.Errorf("exit code = %d, want 1", code)
		}
		if n := strings.Count(out, "TestX/case_b"); n != 1 {
			t.Errorf("TestX/case_b listed %d times, want 1 in %q", n, out)
		}
		n := 0
		for _, l := range lines(out) {
			if strings.HasPrefix(l, "FAIL ") {
				n++
			}
		}
		if n != 1 {
			t.Errorf("%d FAIL lines, want 1 (parent must not be listed) in %q", n, out)
		}
		if strings.Contains(out, "case_a") {
			t.Errorf("passing subtest listed in %q", out)
		}
	})

	t.Run("panic", func(t *testing.T) {
		out, code, _ := run(t, "panic")
		if code != 1 {
			t.Errorf("exit code = %d, want 1", code)
		}
		if !strings.Contains(out, "panicky.TestP") {
			t.Errorf("TestP not listed in %q", out)
		}
		if !strings.Contains(out, "panic: kaboom") {
			t.Errorf("missing panic line in %q", out)
		}
		if !strings.Contains(out, "a_test.go:3") {
			t.Errorf("missing first in-module stack frame (a_test.go:3) in %q", out)
		}
		if strings.Contains(out, "testing.go") {
			t.Errorf("stdlib frames must not be shown: %q", out)
		}
	})

	t.Run("build_error", func(t *testing.T) {
		out, code, _ := run(t, "build_error")
		if code != 1 {
			t.Errorf("exit code = %d, want 1", code)
		}
		re := regexp.MustCompile(`(?m)^BUILD FAIL github.com/VlasovArtem/wuppa/api/internal/broken: internal/broken/a_test.go:3:\d+: .+$`)
		if !re.MatchString(out) {
			t.Errorf("missing BUILD FAIL line in %q", out)
		}
		if got := lastLine(out); !strings.HasPrefix(got, "RESULT: FAIL test-unit failed=1 ") {
			t.Errorf("last line = %q", got)
		}
	})

	t.Run("line_cap", func(t *testing.T) {
		out, code, logPath := run(t, "line_cap")
		if code != 1 {
			t.Errorf("exit code = %d, want 1", code)
		}
		ls := lines(out)
		if len(ls) > 60 {
			t.Errorf("%d lines, want at most 60", len(ls))
		}
		more := regexp.MustCompile(`^\.\.\. [0-9]+ more lines in ` + regexp.QuoteMeta(logPath) + `$`)
		found := false
		for _, l := range ls {
			if more.MatchString(l) {
				found = true
			}
		}
		if !found {
			t.Errorf("missing '... <k> more lines in <log>' line in %q", out)
		}
		if got := lastLine(out); got != "RESULT: FAIL test-unit failed=100 log="+logPath {
			t.Errorf("last line = %q", got)
		}
	})

	t.Run("writes_log", func(t *testing.T) {
		_, _, logPath := run(t, "one_failure")
		b, err := os.ReadFile(logPath)
		if err != nil {
			t.Fatal(err)
		}
		want := "=== RUN   TestX\n    foo_test.go:5: start\n    foo_test.go:6: want 1 got 2\n    foo_test.go:7: end\n--- FAIL: TestX (0.00s)\n"
		if !strings.Contains(string(b), want) {
			t.Errorf("log does not contain test output in order:\n%s", b)
		}
	})

	t.Run("no_events", func(t *testing.T) {
		out, code, _ := run(t, "empty")
		if code != 2 {
			t.Errorf("exit code = %d, want 2", code)
		}
		if got := lastLine(out); got != "RESULT: ERROR test-unit no test events" {
			t.Errorf("last line = %q", got)
		}
	})

	t.Run("no_test_files", func(t *testing.T) {
		out, code, _ := run(t, "no_test_files")
		if code != 0 {
			t.Errorf("exit code = %d, want 0", code)
		}
		if !strings.HasPrefix(lastLine(out), "RESULT: PASS test-unit tests=0 skipped=0 duration=") {
			t.Errorf("last line = %q", lastLine(out))
		}
	})
}
