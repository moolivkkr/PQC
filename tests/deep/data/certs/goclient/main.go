// Go client: (1) offline x509 verification of the ML-DSA chain, (2) TLS dial to the
// dual-cert nginx and report which certificate the server chose.
package main

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"os"
	"runtime"
)

func load(path string) *x509.Certificate {
	b, _ := os.ReadFile(path)
	blk, _ := pem.Decode(b)
	c, err := x509.ParseCertificate(blk.Bytes)
	if err != nil {
		fmt.Println("parse", path, "error:", err)
		os.Exit(0)
	}
	return c
}

func main() {
	fmt.Println("go", runtime.Version())
	root, inter, leaf := load("/work/mldsa-root.crt"), load("/work/mldsa-int.crt"), load("/work/mldsa-leaf.crt")
	fmt.Println("leaf PublicKeyAlgorithm:", leaf.PublicKeyAlgorithm, "SignatureAlgorithm:", leaf.SignatureAlgorithm)
	rp, ip := x509.NewCertPool(), x509.NewCertPool()
	rp.AddCert(root)
	ip.AddCert(inter)
	_, err := leaf.Verify(x509.VerifyOptions{Roots: rp, Intermediates: ip, DNSName: "web"})
	fmt.Println("offline ML-DSA chain verify error:", err)

	pool := x509.NewCertPool()
	pemBytes, _ := os.ReadFile("/work/roots-both.crt")
	pool.AppendCertsFromPEM(pemBytes)
	conn, err := tls.Dial("tcp", "web:443", &tls.Config{RootCAs: pool, ServerName: "web"})
	if err != nil {
		fmt.Println("tls dial error:", err)
		return
	}
	defer conn.Close()
	st := conn.ConnectionState()
	fmt.Printf("tls ok: version=%x group=%v leafKey=%v\n", st.Version, st.CurveID, st.PeerCertificates[0].PublicKeyAlgorithm)
}
