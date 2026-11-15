//go:build go1.25

package main

import "crypto/tls"

// ConnectionState.CurveID exists from Go 1.25 (the tab's "log r.TLS.CurveID" signal).
func clientGroup(cs *tls.ConnectionState) string {
	if cs == nil {
		return ""
	}
	return cs.CurveID.String()
}
