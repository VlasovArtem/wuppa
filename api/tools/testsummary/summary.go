// Package main summarises `go test -json` output in the agent-friendly format.
package main

import "io"

// Summarize reads a go test -json stream, writes the readable log to logPath
// and returns the short stdout text (last line is the RESULT line) and the exit code.
func Summarize(r io.Reader, target, logPath string) (out string, code int) {
	return "", 0
}
