package main

import (
	"flag"
	"fmt"
	"os"
)

func main() {
	target := flag.String("target", "test-unit", "target name for the RESULT line")
	logPath := flag.String("log", ".out/test-unit.log", "path of the readable log")
	flag.Parse()
	out, code := Summarize(os.Stdin, *target, *logPath)
	fmt.Print(out)
	os.Exit(code)
}
