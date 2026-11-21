// Package testenv gives integration tests their environment.
package testenv

import (
	"os"
	"testing"
)

// DatabaseURL returns DATABASE_URL or fails the test when it is empty.
func DatabaseURL(t testing.TB) string {
	t.Helper()
	url := os.Getenv("DATABASE_URL")
	if url == "" {
		t.Fatal("DATABASE_URL is empty: run the test through `make test-integration` or set DATABASE_URL")
	}
	return url
}
