package main

// Case I: public-key pinning and a non-exportable signing key (crypto.Signer, as KMS/PKCS#11 wrappers expose).

import (
	"bytes"
	"crypto"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"io"
	"log"
	"sync/atomic"
)

// opaqueSigner hides the concrete key type, like a KMS or PKCS#11 signer: only Public() and Sign().
type opaqueSigner struct {
	inner crypto.Signer
	calls atomic.Int32
}

func (s *opaqueSigner) Public() crypto.PublicKey { return s.inner.Public() }
func (s *opaqueSigner) Sign(r io.Reader, d []byte, o crypto.SignerOpts) ([]byte, error) {
	n := s.calls.Add(1)
	log.Printf("opaqueSigner.Sign call=%d key=%T hash=%v", n, s.inner, o.HashFunc())
	return s.inner.Sign(r, d, o)
}

var signer *opaqueSigner

func startCaseIServer() {
	for _, n := range []string{"srv-ec", "srv-rsa"} {
		c := pair(n)
		s := &opaqueSigner{inner: c.PrivateKey.(crypto.Signer)}
		c.PrivateKey = s
		port := 9456
		if n == "srv-rsa" {
			port = 9457
		}
		serve(port, "I crypto.Signer wrapper ("+n+")", &tls.Config{Certificates: []tls.Certificate{c}})
		if signer == nil {
			signer = s
		}
	}
}

func spkiPin(file string) []byte {
	c := pair(file)
	leaf, err := x509.ParseCertificate(c.Certificate[0])
	if err != nil {
		log.Fatal(err)
	}
	h := sha256.Sum256(leaf.RawSubjectPublicKeyInfo)
	return h[:]
}

func pinned(pin []byte) *tls.Config {
	return &tls.Config{RootCAs: caPool(), VerifyConnection: func(cs tls.ConnectionState) error {
		h := sha256.Sum256(cs.PeerCertificates[0].RawSubjectPublicKeyInfo)
		if !bytes.Equal(h[:], pin) {
			return errors.New("SPKI pin mismatch")
		}
		return nil
	}}
}

func caseIClient() {
	good, bad := spkiPin("srv-ec"), spkiPin("srv-rsa") // OpenSSL servers use srv-ec
	for _, a := range []string{pqOnly, classical} {
		try("I", "VerifyConnection SPKI pin (correct)", a, pinned(good))
		try("I", "VerifyConnection SPKI pin (wrong, negative)", a, pinned(bad))
	}
}

func init() {
	extraModes["client-i"] = caseIClient
	extraModes["server-i"] = func() { startCaseIServer(); log.Printf("servers-up"); select {} }
	extraModes["signer-calls"] = func() { fmt.Println("n/a") }
}
