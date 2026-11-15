//go:build !go1.25

package main

import "crypto/tls"

// ConnectionState.CurveID was added in Go 1.25; the PQ-only peer proves the group instead.
func curveName(tls.ConnectionState) string { return "n/a(<go1.25)" }
