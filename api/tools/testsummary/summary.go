// Package main summarises `go test -json` output in the agent-friendly format.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const maxLines = 60

type event struct {
	Time        time.Time
	Action      string
	Package     string
	Test        string
	Output      string
	OutputType  string
	ImportPath  string
	FailedBuild string
}

type outLine struct {
	text string
	kind string
}

type testState struct {
	pkg, name string
	action    string
	out       []outLine
}

var (
	fileLineRe  = regexp.MustCompile(`^\s+(\S+\.go):(\d+):(?:\d+:)? `)
	buildLineRe = regexp.MustCompile(`^(\S+\.go:\d+:\d+: .*)$`)
	frameFileRe = regexp.MustCompile(`^\t(\S+\.go):(\d+)`)
)

// Summarize reads a go test -json stream, writes the readable log to logPath
// and returns the short stdout text (last line is the RESULT line) and the exit code.
func Summarize(r io.Reader, target, logPath string) (out string, code int) {
	var (
		logBuf     strings.Builder
		tests      = map[string]*testState{}
		order      []string
		pkgFailed  = map[string]bool{}
		pkgOrder   []string
		buildFail  = map[string]bool{}
		buildOrder []string
		buildLines = map[string][]string{}
		events     int
		first      time.Time
		last       time.Time
	)

	br := bufio.NewReaderSize(r, 1<<20)
	for {
		line, err := br.ReadString('\n')
		if len(line) > 0 {
			var ev event
			if jerr := json.Unmarshal([]byte(line), &ev); jerr != nil || ev.Action == "" {
				logBuf.WriteString(line)
			} else {
				events++
				if !ev.Time.IsZero() {
					if first.IsZero() || ev.Time.Before(first) {
						first = ev.Time
					}
					if ev.Time.After(last) {
						last = ev.Time
					}
				}
				switch ev.Action {
				case "build-output":
					logBuf.WriteString(ev.Output)
					p := cleanImportPath(ev.ImportPath)
					if m := buildLineRe.FindStringSubmatch(strings.TrimRight(ev.Output, "\n")); m != nil {
						buildLines[p] = append(buildLines[p], m[1])
					}
				case "build-fail":
					p := cleanImportPath(ev.ImportPath)
					if !buildFail[p] {
						buildFail[p] = true
						buildOrder = append(buildOrder, p)
					}
				case "output":
					logBuf.WriteString(ev.Output)
					if ev.Test != "" {
						ts := state(tests, &order, ev.Package, ev.Test)
						ts.out = append(ts.out, outLine{ev.Output, ev.OutputType})
					}
				case "pass", "fail", "skip":
					if ev.Test != "" {
						ts := state(tests, &order, ev.Package, ev.Test)
						ts.action = ev.Action
					} else if ev.Action == "fail" {
						if ev.FailedBuild != "" {
							p := cleanImportPath(ev.FailedBuild)
							if !buildFail[p] {
								buildFail[p] = true
								buildOrder = append(buildOrder, p)
							}
						}
						if !pkgFailed[ev.Package] {
							pkgFailed[ev.Package] = true
							pkgOrder = append(pkgOrder, ev.Package)
						}
					}
				}
			}
		}
		if err != nil {
			break
		}
	}

	if events == 0 {
		return fmt.Sprintf("RESULT: ERROR %s no test events\n", target), 2
	}

	if dir := filepath.Dir(logPath); dir != "." {
		_ = os.MkdirAll(dir, 0o750)
	}
	_ = os.WriteFile(logPath, []byte(logBuf.String()), 0o600)

	// A parent is reported through its subtests, unless it failed on its own:
	// a failed test is reported when none of its descendants failed.
	isParent := map[string]bool{}
	failedDesc := map[string]bool{}
	for _, k := range order {
		ts := tests[k]
		for name := ts.name; strings.Contains(name, "/"); {
			name = name[:strings.LastIndex(name, "/")]
			isParent[ts.pkg+"."+name] = true
			if ts.action == "fail" {
				failedDesc[ts.pkg+"."+name] = true
			}
		}
	}
	reported := map[string]bool{}

	var body []string
	passed, skipped, failed := 0, 0, 0
	for _, k := range order {
		ts := tests[k]
		switch ts.action {
		case "pass":
			if !isParent[k] {
				passed++
			}
		case "skip":
			if !isParent[k] {
				skipped++
			}
		case "fail":
			if failedDesc[k] {
				continue
			}
			failed++
			reported[ts.pkg] = true
			body = append(body, failBlock(ts)...)
		}
	}

	// packages that failed without a failing test or a build error (TestMain, panic outside a test, ...).
	for _, p := range pkgOrder {
		if reported[p] || buildFail[p] {
			continue
		}
		failed++
		body = append(body, "FAIL "+p+" (package failed, see log)")
	}

	for _, p := range buildOrder {
		failed++
		if ls := buildLines[p]; len(ls) > 0 {
			for _, l := range ls {
				body = append(body, "BUILD FAIL "+p+": "+l)
			}
		} else {
			body = append(body, "BUILD FAIL "+p+": see log")
		}
	}

	var sb strings.Builder
	if len(body) > maxLines-1 {
		keep := maxLines - 2
		fmt.Fprintf(&sb, "%s\n", strings.Join(body[:keep], "\n"))
		fmt.Fprintf(&sb, "... %d more lines in %s\n", len(body)-keep, logPath)
	} else if len(body) > 0 {
		fmt.Fprintf(&sb, "%s\n", strings.Join(body, "\n"))
	}

	if failed > 0 {
		fmt.Fprintf(&sb, "RESULT: FAIL %s failed=%d log=%s\n", target, failed, logPath)
		return sb.String(), 1
	}
	dur := 0.0
	if !first.IsZero() {
		dur = last.Sub(first).Seconds()
	}
	fmt.Fprintf(&sb, "RESULT: PASS %s tests=%d skipped=%d duration=%.1fs\n", target, passed, skipped, dur)
	return sb.String(), 0
}

func state(m map[string]*testState, order *[]string, pkg, name string) *testState {
	k := pkg + "." + name
	ts, ok := m[k]
	if !ok {
		ts = &testState{pkg: pkg, name: name}
		m[k] = ts
		*order = append(*order, k)
	}
	return ts
}

func cleanImportPath(p string) string {
	if i := strings.Index(p, " ["); i >= 0 {
		p = p[:i]
	}
	return strings.TrimSuffix(p, ".test")
}

// failBlock renders one failed leaf test: the FAIL line and its message lines.
func failBlock(ts *testState) []string {
	var msgs []string
	where := ""
	inErr := false
	panicking := false
	for _, o := range ts.out {
		text := strings.TrimRight(o.text, "\n")
		if o.kind == "frame" {
			inErr = false
			continue
		}
		if strings.HasPrefix(text, "panic: ") {
			panicking = true
			msgs = append(msgs, text)
			continue
		}
		if panicking {
			continue
		}
		switch {
		case o.kind == "error":
			inErr = true
			if where == "" {
				if m := fileLineRe.FindStringSubmatch(text); m != nil {
					where = filepath.Base(m[1]) + ":" + m[2]
				}
			}
			msgs = append(msgs, strings.TrimSpace(text))
		case fileLineRe.MatchString(text):
			inErr = false
		case inErr && text != "":
			msgs = append(msgs, strings.TrimSpace(text))
		}
	}
	if panicking {
		if loc := firstModuleFrame(ts.out); loc != "" {
			if where == "" {
				where = filepath.Base(loc)
			}
			msgs = append(msgs, "at "+relPath(loc))
		}
	}
	if len(msgs) > 10 {
		msgs = append(msgs[:10], "...")
	}
	head := "FAIL " + ts.pkg + "." + ts.name
	if where != "" {
		head += " (" + where + ")"
	}
	res := []string{head}
	for _, m := range msgs {
		res = append(res, "    "+m)
	}
	return res
}

// firstModuleFrame returns "file:line" of the first stack frame whose function
// belongs to a module path (first path element contains a dot), after the panic line.
func firstModuleFrame(out []outLine) string {
	seenPanic := false
	fn := ""
	for _, o := range out {
		text := strings.TrimRight(o.text, "\n")
		if strings.HasPrefix(text, "panic: ") {
			seenPanic = true
			continue
		}
		if !seenPanic {
			continue
		}
		if m := frameFileRe.FindStringSubmatch(text); m != nil {
			if isModuleFunc(fn) {
				return m[1] + ":" + m[2]
			}
			continue
		}
		fn = text
	}
	return ""
}

func isModuleFunc(fn string) bool {
	i := strings.Index(fn, "/")
	return i > 0 && strings.Contains(fn[:i], ".")
}

func relPath(loc string) string {
	if wd, err := os.Getwd(); err == nil {
		if rel, err := filepath.Rel(wd, loc); err == nil && !strings.HasPrefix(rel, "..") {
			return rel
		}
	}
	return loc
}
