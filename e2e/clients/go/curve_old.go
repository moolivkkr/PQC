//go:build !go1.25

package main

import "crypto/tls"

func clientGroup(*tls.ConnectionState) string { return "" }
