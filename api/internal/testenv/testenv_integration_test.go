//go:build integration

package testenv_test

import (
	"net"
	"net/url"
	"testing"
	"time"

	"github.com/VlasovArtem/wuppa/api/internal/testenv"
)

func TestDatabaseReachable(t *testing.T) {
	raw := testenv.DatabaseURL(t)
	u, err := url.Parse(raw)
	if err != nil {
		t.Fatalf("parse DATABASE_URL: %v", err)
	}
	host := u.Host
	if u.Port() == "" {
		host = net.JoinHostPort(u.Hostname(), "5432")
	}
	conn, err := net.DialTimeout("tcp", host, 5*time.Second)
	if err != nil {
		t.Fatalf("database at %s is not reachable: %v", host, err)
	}
	_ = conn.Close()
}
