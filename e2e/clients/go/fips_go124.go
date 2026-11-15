//go:build go1.24

package main

import "crypto/fips140"

func fipsStatus() string {
	if fips140.Enabled() {
		return "on"
	}
	return "off"
}
