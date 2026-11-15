//go:build go1.25

package main

import "crypto/tls"

func curveName(cs tls.ConnectionState) string { return cs.CurveID.String() }
