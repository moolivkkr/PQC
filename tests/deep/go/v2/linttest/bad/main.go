package main
import "crypto/tls"
var c = &tls.Config{
	CurvePreferences: []tls.CurveID{tls.X25519},
	MaxVersion: tls.VersionTLS12,
}
