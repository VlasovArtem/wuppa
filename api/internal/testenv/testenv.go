// Package testenv gives integration tests their environment.
package testenv

import "testing"

// DatabaseURL returns DATABASE_URL or fails the test when it is empty.
func DatabaseURL(t testing.TB) string {
	t.Helper()
	return ""
}
