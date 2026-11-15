// PQ TLS probe - Go. One source, one static binary per toolchain, used unchanged on every compute type:
//   - Lambda (provided.al2023 / provided.al2 custom runtime, or a container image): when AWS_LAMBDA_RUNTIME_API is
//     set the binary runs as the function's bootstrap (github.com/aws/aws-lambda-go) and returns the result object.
//   - ECS, EC2: CLI, prints one tls_handshake line per target and "PQC_RESULT <json>".
//
// Default path: net/http, http.DefaultTransport.Clone() with a tls.Config that holds only RootCAs (test CA) and, for
// the mtls target, the client certificate from tls.LoadX509KeyPair. No CurvePreferences, no versions: what the
// toolchain, the main module's go line (DefaultGODEBUG), run-time GODEBUG and FIPS mode give is what is measured.
//
// Variants (env, unset = default) reproduce the Go tab's "settings that block PQ" and existing-config cases:
//
//	PQC_GO_CURVES     classical {X25519,P256} | hybrid {4588 by number,X25519,P256} | mlkem1024 {0x0202,4588,X25519}
//	PQC_GO_VERSION    max12 (MaxVersion TLS1.2) | min13 (MinVersion TLS1.3)
//	PQC_GO_CIPHERS    tls12 (CipherSuites = 2 ECDHE-GCM suites)
//	PQC_GO_TRUST      ca (default: NewCertPool + ca.crt) | system+ca (SystemCertPool + AppendCertsFromPEM)
//	                  | env (RootCAs nil: SSL_CERT_FILE / SSL_CERT_DIR) | empty (empty pool, negative)
//	PQC_GO_CLIENTCERT pem (default, LoadX509KeyPair) | callback (GetClientCertificate) | env-pem (X509KeyPair from
//	                  PQC_GO_CERT_PEM / PQC_GO_KEY_PEM) | none (negative) | p12-sslmate | p12-xcrypto (extras build)
//	PQC_GO_PIN        ca (VerifyConnection: chain must contain the test CA's SPKI) | wrong (pin = client cert SPKI)
//	PQC_GO_STACK      nethttp (default) | awssdk | awssdk-fipsfix (extras build: aws-sdk-go-v2 BuildableClient)
//	PQC_EGRESS_PORT   extension mode: plain HTTP to the pq-egress extension, which originates the TLS
//
// "probe -wrap <binary>" runs another probe binary and, if it dies before printing PQC_RESULT (e.g. the boringcrypto
// + fips140=on start-up panic), prints a PQC_RESULT whose every target failed with the crash message.
package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"runtime/debug"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/lambda"
)

// goLine is the main module's go line this binary was built with (set by build/go.sh with -X main.goLine=...).
var goLine = "unknown"

var targetPorts = map[string]int{"hybrid": 8443, "pqonly": 8444, "mtls": 8445, "eccert": 8446, "tls12": 8447}
var targetOrder = []string{"hybrid", "pqonly", "mtls", "eccert", "tls12"}

// stacks adds HTTP client stacks from optional files (awssdk.go, extras build).
var stacks = map[string]func(cfg *tls.Config) (*http.Client, string){}

// clientCertLoaders adds client-certificate loaders from optional files (p12.go, extras build).
var clientCertLoaders = map[string]func(certs string) (tls.Certificate, error){}

func env(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

func exeDir() string {
	if p, err := os.Executable(); err == nil {
		if r, err := filepath.EvalSymlinks(p); err == nil {
			p = r
		}
		return filepath.Dir(p)
	}
	return "."
}

func certsDir() (string, error) {
	for _, d := range []string{os.Getenv("PQC_CERTS"), filepath.Join(exeDir(), "certs"), "/opt/pqc-certs", "/etc/pqc/certs"} {
		if d == "" {
			continue
		}
		if _, err := os.Stat(filepath.Join(d, "ca.crt")); err == nil {
			return d, nil
		}
	}
	return "", errors.New("test CA not found (set PQC_CERTS)")
}

// buildInfo: the posture `go version -m` shows (DefaultGODEBUG, GOFIPS140, GOEXPERIMENT, CGO).
func buildInfo() map[string]string {
	out := map[string]string{}
	bi, ok := debug.ReadBuildInfo()
	if !ok {
		return out
	}
	out["toolchain"] = bi.GoVersion
	out["go_line"] = goLine
	for _, s := range bi.Settings {
		switch s.Key {
		case "DefaultGODEBUG", "GOFIPS140", "GOEXPERIMENT", "CGO_ENABLED", "-tags":
			out[s.Key] = s.Value
		}
	}
	for _, d := range bi.Deps {
		if d.Path == "github.com/aws/aws-lambda-go" || d.Path == "github.com/aws/aws-sdk-go-v2" {
			out[d.Path] = d.Version
		}
	}
	return out
}

func osRelease() string {
	b, err := os.ReadFile("/etc/os-release")
	if err != nil {
		return "none (" + strings.SplitN(err.Error(), ":", 2)[0] + ")"
	}
	for _, l := range strings.Split(string(b), "\n") {
		if v, ok := strings.CutPrefix(l, "PRETTY_NAME="); ok {
			return strings.Trim(v, `"`)
		}
	}
	return "unknown"
}

func tlsLib() string {
	s := "go-crypto/tls fips140=" + fipsStatus() + " boringcrypto=" + boringStatus()
	if fipsOnlyImported {
		s += " crypto/tls/fipsonly"
	}
	return s
}

func readPool(certs string) (*x509.CertPool, []byte, error) {
	caPEM, err := os.ReadFile(filepath.Join(certs, "ca.crt"))
	if err != nil {
		return nil, nil, err
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(caPEM) {
		return nil, nil, errors.New("no CA in ca.crt")
	}
	return pool, caPEM, nil
}

func spki(pemFile string) ([]byte, error) {
	b, err := os.ReadFile(pemFile)
	if err != nil {
		return nil, err
	}
	blk, _ := pem.Decode(b)
	if blk == nil {
		return nil, errors.New("no PEM in " + pemFile)
	}
	c, err := x509.ParseCertificate(blk.Bytes)
	if err != nil {
		return nil, err
	}
	h := sha256.Sum256(c.RawSubjectPublicKeyInfo)
	return h[:], nil
}

func loadClientCert(certs string) (tls.Certificate, error) {
	mode := env("PQC_GO_CLIENTCERT", "pem")
	switch mode {
	case "pem", "callback":
		return tls.LoadX509KeyPair(filepath.Join(certs, "client.crt"), filepath.Join(certs, "client.key"))
	case "env-pem":
		return tls.X509KeyPair([]byte(os.Getenv("PQC_GO_CERT_PEM")), []byte(os.Getenv("PQC_GO_KEY_PEM")))
	}
	if f, ok := clientCertLoaders[mode]; ok {
		return f(certs)
	}
	return tls.Certificate{}, fmt.Errorf("PQC_GO_CLIENTCERT=%s not supported by this build", mode)
}

// tlsConfig builds the client tls.Config for one target. Only the variant env vars add settings.
func tlsConfig(target, certs string) (*tls.Config, error) {
	cfg := &tls.Config{}
	pool, _, err := readPool(certs)
	if err != nil {
		return nil, err
	}
	switch env("PQC_GO_TRUST", "ca") {
	case "ca":
		cfg.RootCAs = pool
	case "system+ca":
		sys, err := x509.SystemCertPool()
		if err != nil {
			sys = x509.NewCertPool()
		}
		caPEM, _ := os.ReadFile(filepath.Join(certs, "ca.crt"))
		sys.AppendCertsFromPEM(caPEM)
		cfg.RootCAs = sys
	case "env": // RootCAs nil: system pool from SSL_CERT_FILE / SSL_CERT_DIR
	case "empty":
		cfg.RootCAs = x509.NewCertPool()
	default:
		return nil, errors.New("unknown PQC_GO_TRUST")
	}
	if target == "mtls" {
		switch mode := env("PQC_GO_CLIENTCERT", "pem"); mode {
		case "none":
		case "callback":
			kp, err := loadClientCert(certs)
			if err != nil {
				return nil, fmt.Errorf("client cert: %w", err)
			}
			cfg.GetClientCertificate = func(*tls.CertificateRequestInfo) (*tls.Certificate, error) { return &kp, nil }
		default:
			kp, err := loadClientCert(certs)
			if err != nil {
				return nil, fmt.Errorf("client cert: %w", err)
			}
			cfg.Certificates = []tls.Certificate{kp}
		}
	}
	switch os.Getenv("PQC_GO_CURVES") {
	case "":
	case "classical":
		cfg.CurvePreferences = []tls.CurveID{tls.X25519, tls.CurveP256}
	case "hybrid": // X25519MLKEM768 by number: compiles on Go 1.23 too (tab case F, last row)
		cfg.CurvePreferences = []tls.CurveID{tls.CurveID(4588), tls.X25519, tls.CurveP256}
	case "mlkem1024": // pure MLKEM1024 (0x0202) is opt-in on Go 1.27
		cfg.CurvePreferences = []tls.CurveID{tls.CurveID(0x0202), tls.CurveID(4588), tls.X25519}
	default:
		return nil, errors.New("unknown PQC_GO_CURVES")
	}
	switch os.Getenv("PQC_GO_VERSION") {
	case "":
	case "max12":
		cfg.MaxVersion = tls.VersionTLS12
	case "min13":
		cfg.MinVersion = tls.VersionTLS13
	default:
		return nil, errors.New("unknown PQC_GO_VERSION")
	}
	if os.Getenv("PQC_GO_CIPHERS") == "tls12" {
		cfg.CipherSuites = []uint16{tls.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256, tls.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256}
	}
	switch os.Getenv("PQC_GO_PIN") {
	case "":
	case "ca", "wrong":
		f := "ca.crt"
		if os.Getenv("PQC_GO_PIN") == "wrong" {
			f = "client.crt"
		}
		pin, err := spki(filepath.Join(certs, f))
		if err != nil {
			return nil, err
		}
		cfg.VerifyConnection = func(cs tls.ConnectionState) error {
			for _, ch := range cs.VerifiedChains {
				for _, c := range ch {
					h := sha256.Sum256(c.RawSubjectPublicKeyInfo)
					if bytes.Equal(h[:], pin) {
						return nil
					}
				}
			}
			return errors.New("SPKI pin mismatch")
		}
	}
	return cfg, nil
}

func netHTTP(cfg *tls.Config) (*http.Client, string) {
	tr := http.DefaultTransport.(*http.Transport).Clone()
	tr.TLSClientConfig = cfg
	return &http.Client{Transport: tr, Timeout: 10 * time.Second}, "net/http DefaultTransport.Clone()"
}

func getJSON(c *http.Client, url string) (map[string]any, *tls.ConnectionState, error) {
	resp, err := c.Get(url)
	if err != nil {
		return nil, nil, err
	}
	defer resp.Body.Close()
	b, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, resp.TLS, err
	}
	if resp.StatusCode != 200 {
		return nil, resp.TLS, fmt.Errorf("HTTP %d: %.200s", resp.StatusCode, b)
	}
	var m map[string]any
	if err := json.Unmarshal(b, &m); err != nil {
		return nil, resp.TLS, fmt.Errorf("bad JSON: %v: %.200s", err, b)
	}
	return m, resp.TLS, nil
}

func probeOne(host, name, caseID, certs string) map[string]any {
	t0 := time.Now()
	res := map[string]any{}
	var obs map[string]any
	var cs *tls.ConnectionState
	var stack string
	err := func() error {
		if p := os.Getenv("PQC_EGRESS_PORT"); p != "" {
			stack = "extension:pq-egress"
			var e error
			obs, _, e = getJSON(&http.Client{Timeout: 15 * time.Second},
				fmt.Sprintf("http://127.0.0.1:%s/%s/probe?id=%s", p, name, caseID))
			return e
		}
		cfg, e := tlsConfig(name, certs)
		if e != nil {
			return e
		}
		mk := netHTTP
		if s := env("PQC_GO_STACK", "nethttp"); s != "nethttp" {
			f, ok := stacks[s]
			if !ok {
				return fmt.Errorf("PQC_GO_STACK=%s not supported by this build", s)
			}
			mk = f
		}
		var c *http.Client
		c, stack = mk(cfg)
		obs, cs, e = getJSON(c, fmt.Sprintf("https://%s:%d/probe?id=%s", host, targetPorts[name], caseID))
		return e
	}()
	if err != nil {
		res["ok"] = false
		res["error"] = trunc(errText(err), 400)
	} else {
		res["ok"] = true
		for _, k := range []string{"tls_version", "group", "offered_groups", "cipher_suite", "client_cert_cn"} {
			if v, ok := obs[k]; ok {
				res[k] = v
			}
		}
		res["pq"], _ = obs["pq"].(bool)
		res["offered_pq"], _ = obs["offered_pq"].(bool)
		res["stack"] = stack
		if g := clientGroup(cs); g != "" {
			res["client_group"] = g // Go 1.25+: ConnectionState.CurveID, the app-side signal the tab recommends logging
		}
	}
	res["ms"] = time.Since(t0).Milliseconds()
	status := "failed"
	if res["ok"] == true {
		status = "classical"
		if res["pq"] == true {
			status = "pq"
		}
	}
	res["pq_status"] = status // string field for log filters (LocalStack has no boolean JSON comparisons)
	return res
}

// errText: "<innermost error type>: <message>", like the Python probe's "<Exception>: <msg>".
func errText(err error) string {
	inner := err
	for u := errors.Unwrap(inner); u != nil; u = errors.Unwrap(inner) {
		inner = u
	}
	return fmt.Sprintf("%T: %v", inner, err)
}

func trunc(s string, n int) string {
	if len(s) > n {
		return s[:n]
	}
	return s
}

func targetsFrom(list []string) []string {
	if len(list) == 0 {
		for _, t := range strings.Split(env("PQC_TARGETS", strings.Join(targetOrder, ",")), ",") {
			if t = strings.TrimSpace(t); t != "" {
				list = append(list, t)
			}
		}
	}
	return list
}

func run(caseID string, targets []string) map[string]any {
	if caseID == "" {
		caseID = env("PQC_CASE_ID", "adhoc")
	}
	host := env("PQC_OBSERVER", "pq-observer")
	out := map[string]any{"case_id": caseID, "lang": "go", "runtime": runtime.Version(), "tls_lib": tlsLib(),
		"compute": env("PQC_COMPUTE", "unknown"), "mode": env("PQC_MODE", "baseline"),
		"build": buildInfo(), "godebug_env": os.Getenv("GODEBUG"), "os": osRelease(),
		"arch": runtime.GOOS + "/" + runtime.GOARCH}
	results := map[string]any{}
	certs, cerr := certsDir()
	for _, name := range targetsFrom(targets) {
		var res map[string]any
		if cerr != nil && os.Getenv("PQC_EGRESS_PORT") == "" {
			res = map[string]any{"ok": false, "error": cerr.Error(), "pq_status": "failed"}
		} else {
			res = probeOne(host, name, caseID, certs)
		}
		results[name] = res
		line := map[string]any{"event": "tls_handshake", "case_id": caseID, "lang": "go", "runtime": out["runtime"],
			"compute": out["compute"], "mode": out["mode"], "target": name}
		for k, v := range res {
			line[k] = v
		}
		b, _ := json.Marshal(line)
		fmt.Println(string(b))
	}
	out["results"] = results
	return out
}

type event struct {
	CaseID  string   `json:"case_id"`
	Targets []string `json:"targets"`
}

func handler(_ context.Context, ev event) (map[string]any, error) {
	return run(ev.CaseID, ev.Targets), nil
}

// wrap runs another probe binary; a start-up crash (no PQC_RESULT) becomes a result with every target failed.
func wrap(bin string, args []string) int {
	cmd := exec.Command(bin, args...)
	var errBuf bytes.Buffer
	cmd.Stderr = io.MultiWriter(os.Stderr, &errBuf)
	stdout, _ := cmd.StdoutPipe()
	if err := cmd.Start(); err != nil {
		fmt.Fprintln(os.Stderr, "wrap:", err)
		return 1
	}
	seen := false
	sc := bufio.NewScanner(stdout)
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	for sc.Scan() {
		if strings.HasPrefix(sc.Text(), "PQC_RESULT ") {
			seen = true
		}
		fmt.Println(sc.Text())
	}
	err := cmd.Wait()
	if seen {
		return 0
	}
	msg := strings.TrimSpace(errBuf.String())
	if i := strings.Index(msg, "\n\ngoroutine"); i > 0 {
		msg = msg[:i]
	}
	msg = fmt.Sprintf("process %s exited (%v) before any request: %s", filepath.Base(bin), err, trunc(msg, 300))
	results := map[string]any{}
	for _, t := range targetsFrom(nil) {
		results[t] = map[string]any{"ok": false, "error": msg, "pq_status": "failed", "stack": "wrap"}
	}
	out := map[string]any{"case_id": env("PQC_CASE_ID", "adhoc"), "lang": "go", "runtime": "unknown (crashed: " + filepath.Base(bin) + ")",
		"tls_lib": "go-crypto/tls (process crashed at start)", "compute": env("PQC_COMPUTE", "unknown"),
		"mode": env("PQC_MODE", "baseline"), "results": results, "os": osRelease()}
	b, _ := json.Marshal(out)
	fmt.Println("PQC_RESULT " + string(b))
	return 0
}

func main() {
	if len(os.Args) > 2 && os.Args[1] == "-wrap" {
		os.Exit(wrap(os.Args[2], os.Args[3:]))
	}
	if os.Getenv("AWS_LAMBDA_RUNTIME_API") != "" {
		lambda.Start(handler)
		return
	}
	caseID := ""
	if len(os.Args) > 1 {
		caseID = os.Args[1]
	}
	b, _ := json.Marshal(run(caseID, nil))
	fmt.Println("PQC_RESULT " + string(b))
}
