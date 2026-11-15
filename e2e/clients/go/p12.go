//go:build extras

package main

// Client certificate from an existing PKCS#12 keystore (client.p12: OpenSSL 3 default format, AES-256/PBKDF2/SHA-256
// MAC, password changeit). Go tab case C: sslmate go-pkcs12 reads it; the frozen x/crypto/pkcs12 does not.

import (
	"crypto/tls"
	"os"
	"path/filepath"

	xpkcs12 "golang.org/x/crypto/pkcs12"
	sslpkcs12 "software.sslmate.com/src/go-pkcs12"
)

func init() {
	clientCertLoaders["p12-sslmate"] = func(certs string) (tls.Certificate, error) {
		b, err := os.ReadFile(filepath.Join(certs, "client.p12"))
		if err != nil {
			return tls.Certificate{}, err
		}
		key, leaf, chain, err := sslpkcs12.DecodeChain(b, env("PQC_GO_P12_PASS", "changeit"))
		if err != nil {
			return tls.Certificate{}, err
		}
		c := tls.Certificate{PrivateKey: key, Leaf: leaf, Certificate: [][]byte{leaf.Raw}}
		for _, ca := range chain {
			c.Certificate = append(c.Certificate, ca.Raw)
		}
		return c, nil
	}
	clientCertLoaders["p12-xcrypto"] = func(certs string) (tls.Certificate, error) {
		b, err := os.ReadFile(filepath.Join(certs, "client.p12"))
		if err != nil {
			return tls.Certificate{}, err
		}
		key, leaf, err := xpkcs12.Decode(b, env("PQC_GO_P12_PASS", "changeit")) //nolint:staticcheck
		if err != nil {
			return tls.Certificate{}, err
		}
		return tls.Certificate{PrivateKey: key, Leaf: leaf, Certificate: [][]byte{leaf.Raw}}, nil
	}
}
