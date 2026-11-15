// probe: dials every test server with one tls.Config variant and prints a JSON line.
// CFG=default | classical-curves | pq-curves | http (net/http DefaultTransport-style client)
package main

import (
	"crypto/tls"
	"fmt"
	"io"
	"net/http"
	"os"
	"reflect"
	"runtime"
	"strings"
	"time"
)

var targets = []struct{ name, addr string }{
	{"X25519MLKEM768", "pqsrv:8443"},
	{"X25519", "pqsrv:8444"},
	{"SecP256r1MLKEM768", "pqsrv:8445"},
	{"P-256", "pqsrv:8446"},
	{"SecP384r1MLKEM1024", "pqsrv:8447"},
	{"MLKEM1024", "pqsrv:8448"},
}

func cfg() *tls.Config {
	c := &tls.Config{InsecureSkipVerify: true}
	switch os.Getenv("CFG") {
	case "classical-curves": // the pitfall: an explicit list without a PQ group
		c.CurvePreferences = []tls.CurveID{tls.X25519, tls.CurveP256}
	case "pq-curves": // explicit list that keeps PQ (uses the numeric id so it compiles on 1.23)
		c.CurvePreferences = []tls.CurveID{tls.CurveID(4588), tls.X25519, tls.CurveP256}
	}
	return c
}

// curve reads ConnectionState.CurveID by reflection (field exists from Go 1.25).
func curve(cs tls.ConnectionState) string {
	f := reflect.ValueOf(cs).FieldByName("CurveID")
	if !f.IsValid() {
		return "?"
	}
	return fmt.Sprint(f.Interface())
}

func try(addr string) string {
	if os.Getenv("CFG") == "http" {
		tr := http.DefaultTransport.(*http.Transport).Clone()
		tr.TLSClientConfig = &tls.Config{InsecureSkipVerify: true}
		cl := &http.Client{Transport: tr, Timeout: 5 * time.Second}
		r, err := cl.Get("https://" + addr + "/")
		if err != nil {
			return "FAIL"
		}
		defer r.Body.Close()
		io.Copy(io.Discard, r.Body)
		return "OK " + curve(*r.TLS)
	}
	d := &tls.Dialer{Config: cfg()}
	c, err := d.Dial("tcp", addr)
	if err != nil {
		return "FAIL"
	}
	defer c.Close()
	return "OK " + curve(c.(*tls.Conn).ConnectionState())
}

func main() {
	var parts []string
	for _, t := range targets {
		parts = append(parts, fmt.Sprintf("%q:%q", t.name, try(t.addr)))
	}
	fmt.Printf("{\"go\":%q,\"cfg\":%q,\"godebug\":%q,%s}\n", runtime.Version(), os.Getenv("CFG"), os.Getenv("GODEBUG"), strings.Join(parts, ","))
}
