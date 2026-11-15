//go:build extras

package main

// Go tab case H: aws-sdk-go-v2's BuildableClient as the HTTP client (the SDK's own transport, including its
// FIPS-mode CurvePreferences override). Build: go build -modfile=go.extras.mod -tags extras.

import (
	"crypto/fips140"
	"crypto/tls"
	"net/http"

	awshttp "github.com/aws/aws-sdk-go-v2/aws/transport/http"
)

func init() {
	stacks["awssdk"] = func(cfg *tls.Config) (*http.Client, string) {
		// Your private CA and client cert on the SDK's transport; the SDK's own TLS defaults are kept.
		hc := awshttp.NewBuildableClient().WithTransportOptions(func(t *http.Transport) {
			if t.TLSClientConfig == nil {
				t.TLSClientConfig = &tls.Config{}
			}
			t.TLSClientConfig.RootCAs = cfg.RootCAs
			t.TLSClientConfig.Certificates = cfg.Certificates
		})
		return &http.Client{Transport: hc.GetTransport(), Timeout: 10e9}, "aws-sdk-go-v2 BuildableClient"
	}
	stacks["awssdk-fipsfix"] = func(cfg *tls.Config) (*http.Client, string) {
		// The tab's fix (case H / cmd/client/main.go): put the FIPS-approved hybrids back in FIPS mode.
		hc := awshttp.NewBuildableClient().WithTransportOptions(func(t *http.Transport) {
			if t.TLSClientConfig == nil {
				t.TLSClientConfig = &tls.Config{}
			}
			t.TLSClientConfig.RootCAs = cfg.RootCAs
			t.TLSClientConfig.Certificates = cfg.Certificates
			if fips140.Enabled() {
				t.TLSClientConfig.CurvePreferences = []tls.CurveID{
					tls.SecP256r1MLKEM768, tls.X25519MLKEM768, tls.CurveP256, tls.CurveP384}
			}
		})
		return &http.Client{Transport: hc.GetTransport(), Timeout: 10e9}, "aws-sdk-go-v2 BuildableClient + FIPS hybrid fix"
	}
}
