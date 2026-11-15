// pq-observer: TLS endpoints that report, per handshake, what the client offered and what was negotiated.
//
// Listeners (all serve GET /probe?id=<case-id>, which answers with the JSON record for that connection):
//
//	:8443 hybrid   TLS 1.2-1.3, PQ preferred, classical accepted   -> "what does this client negotiate?"
//	:8444 pqonly   TLS 1.3 only, X25519MLKEM768 only               -> "does this client still work after PQ enforcement?"
//	:8445 mtls     like hybrid, client certificate required        -> existing keystore / client cert case
//	:8446 eccert   like hybrid, ECDSA P-256 server certificate     -> EC certificate chains
//	:8447 tls12    TLS 1.2 only, classical                         -> legacy server: client must not break, visibility flags it
//
// Every ClientHello is logged (even if the handshake later fails) with the offered groups, so a client that
// fails against :8444 is still visible as "did not offer PQ". Records are kept in memory and served on
// http://:8080/events?id=<case-id> for the test runner; each record is also written to stdout as JSON.
package main

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"sync"
	"time"
)

type Event struct {
	Time            string   `json:"time"`
	Kind            string   `json:"kind"` // hello | request
	Listener        string   `json:"listener"`
	Remote          string   `json:"remote"`
	SNI             string   `json:"sni,omitempty"`
	CaseID          string   `json:"case_id,omitempty"`
	OfferedGroups   []string `json:"offered_groups,omitempty"`
	OfferedVersions []string `json:"offered_versions,omitempty"`
	OfferedPQ       bool     `json:"offered_pq"`
	TLSVersion      string   `json:"tls_version,omitempty"`
	Group           string   `json:"group,omitempty"`
	PQ              bool     `json:"pq"`
	CipherSuite     string   `json:"cipher_suite,omitempty"`
	ClientCertCN    string   `json:"client_cert_cn,omitempty"`
	UserAgent       string   `json:"user_agent,omitempty"`
}

var (
	mu      sync.Mutex
	events  []Event
	hellos  sync.Map // remote addr -> *tls.ClientHelloInfo
	results = map[string][]string{}
)

var pqGroups = map[tls.CurveID]bool{
	tls.X25519MLKEM768: true, tls.SecP256r1MLKEM768: true, tls.SecP384r1MLKEM1024: true,
}

func groupName(c tls.CurveID) string {
	switch c {
	case 0x6399:
		return "X25519Kyber768Draft00"
	case 30:
		return "X448"
	case 256, 257, 258, 259, 260:
		return fmt.Sprintf("ffdhe%d", map[tls.CurveID]int{256: 2048, 257: 3072, 258: 4096, 259: 6144, 260: 8192}[c])
	case 0x0200:
		return "MLKEM512"
	case 0x0201:
		return "MLKEM768"
	case 0x0202:
		return "MLKEM1024"
	case 0:
		return ""
	}
	return c.String()
}

func versionName(v uint16) string {
	switch v {
	case tls.VersionTLS10:
		return "TLSv1.0"
	case tls.VersionTLS11:
		return "TLSv1.1"
	case tls.VersionTLS12:
		return "TLSv1.2"
	case tls.VersionTLS13:
		return "TLSv1.3"
	}
	return fmt.Sprintf("0x%04x", v)
}

func record(e Event) {
	e.Time = time.Now().UTC().Format(time.RFC3339Nano)
	mu.Lock()
	events = append(events, e)
	if len(events) > 20000 {
		events = events[len(events)-20000:]
	}
	mu.Unlock()
	b, _ := json.Marshal(e)
	fmt.Println(string(b))
}

func helloEvent(listener string, h *tls.ClientHelloInfo) Event {
	e := Event{Kind: "hello", Listener: listener, Remote: h.Conn.RemoteAddr().String(), SNI: h.ServerName}
	for _, c := range h.SupportedCurves {
		e.OfferedGroups = append(e.OfferedGroups, groupName(c))
		if pqGroups[c] {
			e.OfferedPQ = true
		}
	}
	for _, v := range h.SupportedVersions {
		if v&0x0f0f == 0x0a0a { // GREASE
			continue
		}
		e.OfferedVersions = append(e.OfferedVersions, versionName(v))
	}
	return e
}

func handler(listener string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		e := Event{Kind: "request", Listener: listener, Remote: r.RemoteAddr, CaseID: r.URL.Query().Get("id"),
			UserAgent: r.UserAgent()}
		if h, ok := hellos.Load(r.RemoteAddr); ok {
			he := helloEvent(listener, h.(*tls.ClientHelloInfo))
			e.SNI, e.OfferedGroups, e.OfferedVersions, e.OfferedPQ = he.SNI, he.OfferedGroups, he.OfferedVersions, he.OfferedPQ
		}
		if cs := r.TLS; cs != nil {
			e.TLSVersion = versionName(cs.Version)
			e.Group = groupName(cs.CurveID)
			e.PQ = pqGroups[cs.CurveID]
			e.CipherSuite = tls.CipherSuiteName(cs.CipherSuite)
			if len(cs.PeerCertificates) > 0 {
				e.ClientCertCN = cs.PeerCertificates[0].Subject.CommonName
			}
		}
		record(e)
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(e)
	}
}

func serve(addr, listener string, cfg *tls.Config) {
	base := cfg.Clone()
	cfg.GetConfigForClient = func(h *tls.ClientHelloInfo) (*tls.Config, error) {
		hellos.Store(h.Conn.RemoteAddr().String(), h)
		record(helloEvent(listener, h))
		return base, nil
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/", handler(listener))
	srv := &http.Server{Addr: addr, Handler: mux, TLSConfig: cfg, ReadHeaderTimeout: 10 * time.Second,
		ErrorLog: log.New(os.Stderr, listener+": ", 0),
		ConnState: func(c net.Conn, s http.ConnState) {
			if s == http.StateClosed {
				hellos.Delete(c.RemoteAddr().String())
			}
		}}
	log.Printf("listening %s (%s)", addr, listener)
	log.Fatal(srv.ListenAndServeTLS("", ""))
}

func mustCert(cert, key string) tls.Certificate {
	c, err := tls.LoadX509KeyPair(cert, key)
	if err != nil {
		log.Fatal(err)
	}
	return c
}

func main() {
	dir := envOr("CERT_DIR", "/certs")
	rsa := mustCert(dir+"/server-rsa.crt", dir+"/server-rsa.key")
	ec := mustCert(dir+"/server-ec.crt", dir+"/server-ec.key")
	caPEM, err := os.ReadFile(dir + "/ca.crt")
	if err != nil {
		log.Fatal(err)
	}
	pool := x509.NewCertPool()
	pool.AppendCertsFromPEM(caPEM)

	// hybrid: Go 1.27 defaults put X25519MLKEM768 first; listed explicitly so the test does not depend on defaults.
	hybridCurves := []tls.CurveID{tls.X25519MLKEM768, tls.SecP256r1MLKEM768, tls.SecP384r1MLKEM1024, tls.X25519, tls.CurveP256, tls.CurveP384}
	go serve(":8443", "hybrid", &tls.Config{Certificates: []tls.Certificate{rsa}, MinVersion: tls.VersionTLS12, CurvePreferences: hybridCurves})
	go serve(":8444", "pqonly", &tls.Config{Certificates: []tls.Certificate{rsa}, MinVersion: tls.VersionTLS13, CurvePreferences: []tls.CurveID{tls.X25519MLKEM768}})
	go serve(":8445", "mtls", &tls.Config{Certificates: []tls.Certificate{rsa}, MinVersion: tls.VersionTLS12, CurvePreferences: hybridCurves,
		ClientAuth: tls.RequireAndVerifyClientCert, ClientCAs: pool})
	go serve(":8446", "eccert", &tls.Config{Certificates: []tls.Certificate{ec}, MinVersion: tls.VersionTLS12, CurvePreferences: hybridCurves})
	go serve(":8447", "tls12", &tls.Config{Certificates: []tls.Certificate{rsa}, MinVersion: tls.VersionTLS12, MaxVersion: tls.VersionTLS12,
		CurvePreferences: []tls.CurveID{tls.X25519, tls.CurveP256}})

	admin := http.NewServeMux()
	// EC2 instances (whose console output LocalStack mocks) POST their probe output here: /results?id=<case>.
	admin.HandleFunc("/results", func(w http.ResponseWriter, r *http.Request) {
		id := r.URL.Query().Get("id")
		if r.Method == http.MethodPost {
			b, _ := io.ReadAll(io.LimitReader(r.Body, 1<<20))
			mu.Lock()
			results[id] = append(results[id], string(b))
			mu.Unlock()
			w.WriteHeader(http.StatusNoContent)
			return
		}
		mu.Lock()
		out := results[id]
		mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(out)
	})
	admin.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })
	admin.HandleFunc("/events", func(w http.ResponseWriter, r *http.Request) {
		// ?id=<case>: requests carrying that case id, plus every ClientHello from the same client IPs within
		// 120 s of those requests - this is how a failed handshake (no request) is tied to its case.
		id := r.URL.Query().Get("id")
		mu.Lock()
		out := []Event{}
		if id == "" {
			out = append(out, events...)
		} else {
			ips := map[string][]time.Time{}
			for _, e := range events {
				if e.CaseID == id {
					t, _ := time.Parse(time.RFC3339Nano, e.Time)
					ips[hostOf(e.Remote)] = append(ips[hostOf(e.Remote)], t)
				}
			}
			for _, e := range events {
				if e.CaseID == id {
					out = append(out, e)
					continue
				}
				if e.Kind != "hello" {
					continue
				}
				t, _ := time.Parse(time.RFC3339Nano, e.Time)
				for _, rt := range ips[hostOf(e.Remote)] {
					if d := t.Sub(rt); d > -120*time.Second && d < 120*time.Second {
						out = append(out, e)
						break
					}
				}
			}
		}
		mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(out)
	})
	log.Fatal(http.ListenAndServe(":8080", admin))
}

func envOr(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

func hostOf(addr string) string {
	h, _, err := net.SplitHostPort(addr)
	if err != nil {
		return addr
	}
	return h
}
