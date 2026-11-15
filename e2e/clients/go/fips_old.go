//go:build !go1.24

package main

func fipsStatus() string { return "n/a(<go1.24)" }
