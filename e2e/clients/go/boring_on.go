//go:build boringcrypto

package main

import "crypto/boring"

func boringStatus() string {
	if boring.Enabled() {
		return "on"
	}
	return "built-in,off"
}
