// pq-egress: Lambda external extension (and plain sidecar) that originates outbound TLS with hybrid
// post-quantum key exchange on behalf of a function whose own runtime cannot (Python 3.9-3.11 stdlib ssl,
// Node 18/20, .NET on Amazon Linux 2, Java 8-21 without an agent, ...).
//
// The function sends plain HTTP to the extension on loopback; the extension makes the TLS connection:
//
//	GET http://127.0.0.1:2779/<route>/<path>   route from PQ_EGRESS_ROUTES ("name=host:port[;mtls],...")
//	GET http://127.0.0.1:2779/https/<host:port>/<path>
//
// Same pattern as the AWS Parameters and Secrets Lambda Extension (localhost:2773). It does not count against
// the 5-layer limit if bundled into a layer the function already has. The loopback hop is plain HTTP inside
// the execution environment only.
//
// Env: PQ_EGRESS_PORT (2779), PQ_EGRESS_ROUTES, PQ_EGRESS_CA (PEM file; system roots if unset),
// PQ_EGRESS_CERT / PQ_EGRESS_KEY (client certificate for ;mtls routes), PQ_EGRESS_GROUPS ("pq-only" = refuse
// classical upstreams).
package main

import (
	"bytes"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const name = "pq-egress"

type route struct {
	addr string
	mtls bool
}

func main() {
	log.SetFlags(0)
	log.SetPrefix(name + ": ")
	port := env("PQ_EGRESS_PORT", "2779")
	routes := map[string]route{}
	for _, r := range strings.Split(os.Getenv("PQ_EGRESS_ROUTES"), ",") {
		if k, v, ok := strings.Cut(strings.TrimSpace(r), "="); ok {
			addr, opt, _ := strings.Cut(v, ";")
			routes[k] = route{addr: addr, mtls: opt == "mtls"}
		}
	}
	base := &tls.Config{MinVersion: tls.VersionTLS12}
	if os.Getenv("PQ_EGRESS_GROUPS") == "pq-only" {
		base.MinVersion = tls.VersionTLS13
		base.CurvePreferences = []tls.CurveID{tls.X25519MLKEM768}
	} // else: Go 1.27 defaults, X25519MLKEM768 first, classical fallback
	if ca := os.Getenv("PQ_EGRESS_CA"); ca != "" {
		pem, err := os.ReadFile(ca)
		if err != nil {
			log.Fatalf("PQ_EGRESS_CA: %v", err)
		}
		pool := x509.NewCertPool()
		pool.AppendCertsFromPEM(pem)
		base.RootCAs = pool
	}
	withCert := base.Clone()
	if c, k := os.Getenv("PQ_EGRESS_CERT"), os.Getenv("PQ_EGRESS_KEY"); c != "" && k != "" {
		kp, err := tls.LoadX509KeyPair(c, k)
		if err != nil {
			log.Fatalf("client cert: %v", err)
		}
		withCert.Certificates = []tls.Certificate{kp}
	}
	clients := map[bool]*http.Client{
		false: {Timeout: 15 * time.Second, Transport: &http.Transport{TLSClientConfig: base, ForceAttemptHTTP2: false}},
		true:  {Timeout: 15 * time.Second, Transport: &http.Transport{TLSClientConfig: withCert, ForceAttemptHTTP2: false}},
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		parts := strings.SplitN(strings.TrimPrefix(r.URL.Path, "/"), "/", 3)
		var rt route
		rest := ""
		switch {
		case len(parts) >= 2 && parts[0] == "https":
			rt = route{addr: parts[1]}
			if len(parts) == 3 {
				rest = parts[2]
			}
		default:
			var ok bool
			if rt, ok = routes[parts[0]]; !ok {
				http.Error(w, "unknown route "+parts[0], http.StatusNotFound)
				return
			}
			rest = strings.Join(parts[1:], "/")
		}
		url := "https://" + rt.addr + "/" + rest
		if r.URL.RawQuery != "" {
			url += "?" + r.URL.RawQuery
		}
		req, _ := http.NewRequestWithContext(r.Context(), r.Method, url, r.Body)
		req.Header = r.Header.Clone()
		resp, err := clients[rt.mtls].Do(req)
		if err != nil {
			log.Printf("%s -> FAIL %v", url, err)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadGateway)
			json.NewEncoder(w).Encode(map[string]any{"pq_egress_error": err.Error()})
			return
		}
		defer resp.Body.Close()
		if cs := resp.TLS; cs != nil {
			log.Printf("%s -> %s %s", url, tls.VersionName(cs.Version), cs.CurveID)
			w.Header().Set("X-PQ-Egress-Group", cs.CurveID.String())
			w.Header().Set("X-PQ-Egress-TLS", tls.VersionName(cs.Version))
		}
		for k, v := range resp.Header {
			w.Header()[k] = v
		}
		w.WriteHeader(resp.StatusCode)
		io.Copy(w, resp.Body)
	})
	go func() { log.Fatal(http.ListenAndServe("127.0.0.1:"+port, nil)) }()
	log.Printf("listening 127.0.0.1:%s, %d routes", port, len(routes))

	api := os.Getenv("AWS_LAMBDA_RUNTIME_API")
	if api == "" { // sidecar / local mode
		select {}
	}
	id := register(api)
	for { // INVOKE / SHUTDOWN loop
		req, _ := http.NewRequest("GET", "http://"+api+"/2020-01-01/extension/event/next", nil)
		req.Header.Set("Lambda-Extension-Identifier", id)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			log.Fatalf("next: %v", err)
		}
		var ev struct{ EventType string }
		json.NewDecoder(resp.Body).Decode(&ev)
		resp.Body.Close()
		if ev.EventType == "SHUTDOWN" {
			return
		}
	}
}

func register(api string) string {
	body, _ := json.Marshal(map[string][]string{"events": {"INVOKE", "SHUTDOWN"}})
	req, _ := http.NewRequest("POST", "http://"+api+"/2020-01-01/extension/register", bytes.NewReader(body))
	req.Header.Set("Lambda-Extension-Name", filepath.Base(os.Args[0]))
	resp, err := http.DefaultClient.Do(req)
	if err != nil || resp.StatusCode != 200 {
		log.Fatalf("register: %v %v", err, resp)
	}
	defer resp.Body.Close()
	id := resp.Header.Get("Lambda-Extension-Identifier")
	log.Printf("registered %s", id)
	return id
}

func env(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

var _ = fmt.Sprintf
