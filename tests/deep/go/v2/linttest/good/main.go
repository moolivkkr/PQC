package main
import "crypto/tls"
var c = &tls.Config{CurvePreferences: []tls.CurveID{tls.X25519MLKEM768, tls.X25519}}
