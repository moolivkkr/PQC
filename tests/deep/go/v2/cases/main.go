// cases: Go TLS case tests C, D, E, F with the standard library only.
// Compiles on Go 1.23+ (no tls.X25519MLKEM768 constant, no ConnectionState.CurveID needed).
//
//	cases client-default   D: nil RootCAs (system roots; runner sets SSL_CERT_FILE / SSL_CERT_DIR)
//	cases client           D, E, F client cases against the OpenSSL servers
//	cases server           C, E, F server cases on :9443..:9455 (probed with openssl s_client)
package main

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"log"
	"net"
	"os"
	"strings"
	"time"
)

const x25519mlkem768 = tls.CurveID(4588) // tls.X25519MLKEM768 from Go 1.24

var extraModes = map[string]func(){}

func p(f string) string { return "/certs/" + f }

func must[T any](v T, err error) T {
	if err != nil {
		log.Fatal(err)
	}
	return v
}

func caPool() *x509.CertPool {
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(must(os.ReadFile(p("ca.pem")))) {
		log.Fatal("no CA")
	}
	return pool
}

func pair(name string) tls.Certificate { return must(tls.LoadX509KeyPair(p(name+".pem"), p(name+".key"))) }

// Targets: OpenSSL 3.5 s_server instances started by the runner.
const (
	pqOnly       = "localhost:8443" // -tls1_3 -groups X25519MLKEM768
	classical    = "localhost:8444" // -groups X25519 (TLS 1.2 and 1.3)
	pqOnlyMTLS   = "localhost:8445" // PQ-only + -Verify 1 -CAfile ca.pem
	classicalMTL = "localhost:8446" // X25519 + -Verify 1 -CAfile ca.pem
)

func try(caseID, label, addr string, cfg *tls.Config) {
	if cfg.ServerName == "" {
		cfg.ServerName = "localhost"
	}
	c, err := tls.DialWithDialer(&net.Dialer{Timeout: 5 * time.Second}, "tcp", addr, cfg)
	if err != nil {
		e := err.Error()
		if len(e) > 110 {
			e = e[:110]
		}
		fmt.Printf("%s | %-44s | %-15s | FAIL | %s\n", caseID, label, addr, e)
		return
	}
	defer c.Close()
	// mTLS failures surface on first read in TLS 1.3, so read the -www reply.
	c.SetDeadline(time.Now().Add(5 * time.Second))
	fmt.Fprintf(c, "GET / HTTP/1.0\r\n\r\n")
	buf := make([]byte, 64)
	_, rerr := c.Read(buf)
	cs := c.ConnectionState()
	res := "OK  "
	extra := ""
	if rerr != nil && !strings.Contains(rerr.Error(), "EOF") {
		res, extra = "FAIL", " read: "+rerr.Error()
	}
	fmt.Printf("%s | %-44s | %-15s | %s | %s group=%s%s\n", caseID, label, addr, res, ver(cs.Version), curveName(cs), extra)
}

func ver(v uint16) string {
	switch v {
	case tls.VersionTLS13:
		return "TLS1.3"
	case tls.VersionTLS12:
		return "TLS1.2"
	}
	return fmt.Sprintf("%x", v)
}

func clientDefault() {
	label := os.Getenv("TRUST_LABEL")
	for _, a := range []string{pqOnly, classical} {
		try("D", "default RootCAs ("+label+")", a, &tls.Config{})
	}
}

func clientCases() {
	both := []string{pqOnly, classical}
	// D: custom trust
	for _, a := range both {
		pool, err := x509.SystemCertPool()
		if err != nil {
			pool = x509.NewCertPool()
		}
		pool.AppendCertsFromPEM(must(os.ReadFile(p("ca.pem"))))
		try("D", "SystemCertPool()+AppendCertsFromPEM(ca)", a, &tls.Config{RootCAs: pool})
		try("D", "RootCAs = NewCertPool with private CA only", a, &tls.Config{RootCAs: caPool()})
		try("D", "RootCAs = empty pool (negative)", a, &tls.Config{RootCAs: x509.NewCertPool()})
	}
	// E: mutual TLS
	rsaCli, ecCli := pair("cli-rsa"), pair("cli-ec")
	for _, a := range []string{pqOnlyMTLS, classicalMTL} {
		try("E", "Certificates=[client RSA]", a, &tls.Config{RootCAs: caPool(), Certificates: []tls.Certificate{rsaCli}})
		try("E", "GetClientCertificate -> client EC", a, &tls.Config{RootCAs: caPool(),
			GetClientCertificate: func(*tls.CertificateRequestInfo) (*tls.Certificate, error) { return &ecCli, nil }})
		try("E", "no client cert (negative)", a, &tls.Config{RootCAs: caPool()})
	}
	// F: explicit settings
	for _, a := range both {
		try("F", "CurvePreferences={X25519,P256}", a, &tls.Config{RootCAs: caPool(),
			CurvePreferences: []tls.CurveID{tls.X25519, tls.CurveP256}})
		try("F", "CurvePreferences={X25519MLKEM768,X25519,P256}", a, &tls.Config{RootCAs: caPool(),
			CurvePreferences: []tls.CurveID{x25519mlkem768, tls.X25519, tls.CurveP256}})
		try("F", "MaxVersion=TLS1.2", a, &tls.Config{RootCAs: caPool(), MaxVersion: tls.VersionTLS12})
		try("F", "MinVersion=TLS1.3", a, &tls.Config{RootCAs: caPool(), MinVersion: tls.VersionTLS13})
		try("F", "CipherSuites=2 ECDHE-GCM (TLS1.2 list)", a, &tls.Config{RootCAs: caPool(),
			CipherSuites: []uint16{tls.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256, tls.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256}})
	}
}

// ---------- server side ----------

func serve(port int, label string, cfg *tls.Config) {
	ln, err := tls.Listen("tcp", fmt.Sprintf(":%d", port), cfg)
	if err != nil {
		log.Printf("port=%d case=%q LISTEN-ERROR %v", port, label, err)
		return
	}
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func(c net.Conn) {
				defer c.Close()
				tc := c.(*tls.Conn)
				tc.SetDeadline(time.Now().Add(5 * time.Second))
				if err := tc.Handshake(); err != nil {
					log.Printf("port=%d case=%q handshake_error=%v", port, label, err)
					return
				}
				cs := tc.ConnectionState()
				cn := "-"
				if len(cs.PeerCertificates) > 0 {
					cn = cs.PeerCertificates[0].Subject.CommonName
				}
				log.Printf("port=%d case=%q %s group=%s sni=%q client_cn=%s", port, label, ver(cs.Version), curveName(cs), cs.ServerName, cn)
				tc.Write([]byte("HTTP/1.0 200 OK\r\n\r\nok\n"))
			}(c)
		}
	}()
}

// decryptLegacyPEM handles only RFC 1423 "Proc-Type: 4,ENCRYPTED" keys (deprecated API, still in stdlib).
func decryptLegacyPEM(keyFile, pass string) []byte {
	block, _ := pem.Decode(must(os.ReadFile(keyFile)))
	if block == nil || !x509.IsEncryptedPEMBlock(block) { //nolint:staticcheck
		log.Fatalf("%s: not a legacy encrypted PEM block", keyFile)
	}
	der := must(x509.DecryptPEMBlock(block, []byte(pass))) //nolint:staticcheck
	return pem.EncodeToMemory(&pem.Block{Type: block.Type, Bytes: der})
}

func serverMain() {
	rsa, ec := pair("srv-rsa"), pair("srv-ec")
	a, b := pair("a.test"), pair("b.test")
	certs := func(c ...tls.Certificate) *tls.Config { return &tls.Config{Certificates: c} }

	serve(9443, "C rsa LoadX509KeyPair", certs(rsa))
	serve(9444, "C ec LoadX509KeyPair", certs(ec))
	serve(9445, "C Certificates=[rsa,ec]", certs(rsa, ec))
	serve(9446, "C Certificates=[ec,rsa]", certs(ec, rsa))
	serve(9447, "C SNI Certificates=[a.test,b.test]", certs(a, b))
	byName := map[string]*tls.Certificate{"a.test": &a, "b.test": &b}
	serve(9448, "C GetCertificate by SNI", &tls.Config{GetCertificate: func(h *tls.ClientHelloInfo) (*tls.Certificate, error) {
		if c, ok := byName[h.ServerName]; ok {
			return c, nil
		}
		return &ec, nil
	}})
	legacy := must(tls.X509KeyPair(must(os.ReadFile(p("srv-rsa.pem"))), decryptLegacyPEM(p("srv-rsa-legacyenc.key"), os.Getenv("TLS_KEY_PASS"))))
	serve(9449, "C encrypted legacy PEM key", certs(legacy))
	serve(9450, "E RequireAndVerifyClientCert", &tls.Config{Certificates: []tls.Certificate{ec},
		ClientAuth: tls.RequireAndVerifyClientCert, ClientCAs: caPool()})
	serve(9451, "F CurvePreferences={X25519,P256}", &tls.Config{Certificates: []tls.Certificate{ec},
		CurvePreferences: []tls.CurveID{tls.X25519, tls.CurveP256}})
	serve(9452, "F MaxVersion=TLS1.2", &tls.Config{Certificates: []tls.Certificate{ec}, MaxVersion: tls.VersionTLS12})
	serve(9453, "F CipherSuites=TLS1.2 ECDHE-GCM", &tls.Config{Certificates: []tls.Certificate{ec},
		CipherSuites: []uint16{tls.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256, tls.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256}})
	serve(9454, "F PQ-only MinVersion1.3+{X25519MLKEM768}", &tls.Config{Certificates: []tls.Certificate{ec},
		MinVersion: tls.VersionTLS13, CurvePreferences: []tls.CurveID{x25519mlkem768}})
	envPair := must(tls.X509KeyPair([]byte(os.Getenv("TLS_CERT_PEM")), []byte(os.Getenv("TLS_KEY_PEM"))))
	serve(9455, "C cert+key PEM from env vars", certs(envPair))
	log.Printf("servers-up")
	select {}
}

func main() {
	log.SetFlags(0)
	log.SetOutput(os.Stdout)
	if f, ok := extraModes[os.Args[1]]; ok {
		f()
		return
	}
	switch os.Args[1] {
	case "client-default":
		clientDefault()
	case "client":
		clientCases()
	case "server":
		serverMain()
	}
}
