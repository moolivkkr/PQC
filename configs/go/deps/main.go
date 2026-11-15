// deps: Go TLS cases that need third-party modules.
//
//	deps server     C: PKCS#12 (sslmate go-pkcs12, x/crypto/pkcs12) and encrypted PKCS#8 (youmark/pkcs8) on :9460..:9463
//	deps h          H: AWS SDK Go v2, grpc-go and pgx with a custom tls.Config (private CA + client cert)
//	deps h-awsenv   H: AWS SDK default client with AWS_CA_BUNDLE set by the runner
//
// Observers (in-process Go servers, PQ-only, mTLS required) log the negotiated group and client CN,
// so each library's handshake can be seen from the server side.
package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awshttp "github.com/aws/aws-sdk-go-v2/aws/transport/http"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/sts"
	"github.com/jackc/pgx/v5"
	"github.com/youmark/pkcs8"
	xpkcs12 "golang.org/x/crypto/pkcs12"
	"google.golang.org/grpc"
	grpccreds "google.golang.org/grpc/credentials"
	"google.golang.org/grpc/health"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/grpc/peer"
	sslpkcs12 "software.sslmate.com/src/go-pkcs12"
)

func p(f string) string { return "/certs/" + f }

func must[T any](v T, err error) T {
	if err != nil {
		log.Fatal(err)
	}
	return v
}

func caPool() *x509.CertPool {
	pool := x509.NewCertPool()
	pool.AppendCertsFromPEM(must(os.ReadFile(p("ca.pem"))))
	return pool
}

func pass() string { return os.Getenv("TLS_KEY_PASS") }

// ---------- C: PKCS#12 and encrypted PKCS#8 on the server ----------

func serve(port int, label string, cfg *tls.Config) {
	ln := must(tls.Listen("tcp", fmt.Sprintf(":%d", port), cfg))
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func(tc *tls.Conn) {
				defer tc.Close()
				tc.SetDeadline(time.Now().Add(5 * time.Second))
				if err := tc.Handshake(); err != nil {
					log.Printf("port=%d case=%q handshake_error=%v", port, label, err)
					return
				}
				cs := tc.ConnectionState()
				log.Printf("port=%d case=%q group=%s leaf=%s", port, label, cs.CurveID, cfg.Certificates[0].Leaf.Subject.CommonName)
				tc.Write([]byte("HTTP/1.0 200 OK\r\n\r\nok\n"))
			}(c.(*tls.Conn))
		}
	}()
}

func certFrom(key any, leaf *x509.Certificate, chain []*x509.Certificate) tls.Certificate {
	c := tls.Certificate{PrivateKey: key, Leaf: leaf, Certificate: [][]byte{leaf.Raw}}
	for _, ca := range chain {
		c.Certificate = append(c.Certificate, ca.Raw)
	}
	return c
}

func serverMain() {
	// 1. sslmate go-pkcs12: modern OpenSSL 3 PKCS#12 (AES-256-CBC, PBKDF2, SHA-256 MAC) with chain
	k, leaf, chain, err := sslpkcs12.DecodeChain(must(os.ReadFile(p("srv-ec-modern.p12"))), pass())
	if err != nil {
		log.Fatalf("sslmate modern: %v", err)
	}
	serve(9460, "C PKCS#12 modern via sslmate DecodeChain", &tls.Config{Certificates: []tls.Certificate{certFrom(k, leaf, chain)}})

	// 2. x/crypto/pkcs12 (frozen): legacy 3DES/SHA1 PKCS#12 works
	k2, leaf2, err := xpkcs12.Decode(must(os.ReadFile(p("srv-rsa-legacy.p12"))), pass())
	if err != nil {
		log.Fatalf("x/crypto legacy: %v", err)
	}
	serve(9461, "C PKCS#12 legacy via x/crypto Decode", &tls.Config{Certificates: []tls.Certificate{certFrom(k2, leaf2, nil)}})

	// 3. x/crypto/pkcs12 on the modern file: expected to fail at load time
	if _, _, err := xpkcs12.Decode(must(os.ReadFile(p("srv-ec-modern.p12"))), pass()); err != nil {
		log.Printf("case=%q load_error=%v", "C x/crypto Decode on modern PKCS#12", err)
	} else {
		log.Printf("case=%q loaded", "C x/crypto Decode on modern PKCS#12")
	}

	// 4. encrypted PKCS#8 ("BEGIN ENCRYPTED PRIVATE KEY") via youmark/pkcs8
	blk, _ := pem.Decode(must(os.ReadFile(p("srv-ec-pkcs8enc.key"))))
	k4 := must(pkcs8.ParsePKCS8PrivateKey(blk.Bytes, []byte(pass())))
	certBlk, _ := pem.Decode(must(os.ReadFile(p("srv-ec.pem"))))
	leaf4 := must(x509.ParseCertificate(certBlk.Bytes))
	serve(9462, "C encrypted PKCS#8 via youmark/pkcs8", &tls.Config{Certificates: []tls.Certificate{certFrom(k4, leaf4, nil)}})
	log.Printf("servers-up")
	select {}
}

// ---------- H: libraries with a custom tls.Config ----------

func clientCert() tls.Certificate { return must(tls.LoadX509KeyPair(p("cli-ec.pem"), p("cli-ec.key"))) }

func custom() *tls.Config {
	return &tls.Config{RootCAs: caPool(), Certificates: []tls.Certificate{clientCert()}, MinVersion: tls.VersionTLS12}
}
func customBlocked() *tls.Config { // same, plus a classical-only curve list: proves the config is passed through
	c := custom()
	c.CurvePreferences = []tls.CurveID{tls.X25519, tls.CurveP256}
	return c
}

func observerCfg() *tls.Config {
	return &tls.Config{Certificates: []tls.Certificate{must(tls.LoadX509KeyPair(p("srv-ec.pem"), p("srv-ec.key")))},
		MinVersion: tls.VersionTLS13, CurvePreferences: []tls.CurveID{tls.X25519MLKEM768},
		ClientAuth: tls.RequireAndVerifyClientCert, ClientCAs: caPool()}
}

func cn(cs *tls.ConnectionState) string {
	if len(cs.PeerCertificates) == 0 {
		return "-"
	}
	return cs.PeerCertificates[0].Subject.CommonName
}

func startObservers() {
	// HTTPS observer for the AWS SDK
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		log.Printf("observer=https group=%s client_cn=%s ua=%.40s", r.TLS.CurveID, cn(r.TLS), r.UserAgent())
		w.WriteHeader(400)
	})
	hs := &http.Server{Addr: ":9470", Handler: mux, TLSConfig: observerCfg(), ErrorLog: log.New(os.Stdout, "observer=https ", 0)}
	go hs.ListenAndServeTLS("", "")

	// raw TLS observer for pgx (direct SSL negotiation)
	ln := must(tls.Listen("tcp", ":9471", observerCfg()))
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func(tc *tls.Conn) {
				defer tc.Close()
				tc.SetDeadline(time.Now().Add(5 * time.Second))
				if err := tc.Handshake(); err != nil {
					log.Printf("observer=raw handshake_error=%v", err)
					return
				}
				cs := tc.ConnectionState()
				log.Printf("observer=raw group=%s client_cn=%s alpn=%q", cs.CurveID, cn(&cs), cs.NegotiatedProtocol)
			}(c.(*tls.Conn))
		}
	}()

	// gRPC observer: PQ-only + mTLS
	glis := must(net.Listen("tcp", ":9472"))
	gs := grpc.NewServer(grpc.Creds(grpccreds.NewTLS(observerCfg())),
		grpc.UnaryInterceptor(func(ctx context.Context, req any, info *grpc.UnaryServerInfo, h grpc.UnaryHandler) (any, error) {
			if pr, ok := peer.FromContext(ctx); ok {
				if ti, ok := pr.AuthInfo.(grpccreds.TLSInfo); ok {
					log.Printf("observer=grpc method=%s group=%s client_cn=%s", info.FullMethod, ti.State.CurveID, cn(&ti.State))
				}
			}
			return h(ctx, req)
		}))
	healthpb.RegisterHealthServer(gs, health.NewServer())
	go gs.Serve(glis)

	// gRPC observer without mTLS, for NewClientTLSFromFile
	glis2 := must(net.Listen("tcp", ":9473"))
	oc := observerCfg()
	oc.ClientAuth = tls.NoClientCert
	gs2 := grpc.NewServer(grpc.Creds(grpccreds.NewTLS(oc)))
	healthpb.RegisterHealthServer(gs2, health.NewServer())
	go gs2.Serve(glis2)
	time.Sleep(300 * time.Millisecond)
}

func verdict(err error) string {
	if err == nil {
		return "TLS-OK"
	}
	s := err.Error()
	if len(s) > 150 {
		s = s[len(s)-150:]
	}
	if strings.Contains(s, "tls:") || strings.Contains(s, "handshake") || strings.Contains(s, "remote error") || strings.Contains(s, "x509:") {
		return "TLS-FAIL: " + s
	}
	return "TLS-OK, then protocol error: " + s
}

func short() context.Context { c, _ := context.WithTimeout(context.Background(), 6*time.Second); return c }

func awsCall(hc config.HTTPClient, endpoint string, extra ...func(*config.LoadOptions) error) error {
	opts := []func(*config.LoadOptions) error{config.WithRegion("us-east-1"),
		config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider("AKIDEXAMPLE", "secret", "")),
		config.WithRetryMaxAttempts(1)}
	if hc != nil {
		opts = append(opts, config.WithHTTPClient(hc))
	}
	opts = append(opts, extra...)
	ac, err := config.LoadDefaultConfig(context.Background(), opts...)
	if err != nil {
		return fmt.Errorf("config: %w", err)
	}
	cl := sts.NewFromConfig(ac, func(o *sts.Options) { o.BaseEndpoint = aws.String(endpoint) })
	_, err = cl.GetCallerIdentity(short(), &sts.GetCallerIdentityInput{})
	return err
}

func pgxCall(dsn string, cfg *tls.Config) error {
	pc, err := pgx.ParseConfig(dsn)
	if err != nil {
		return fmt.Errorf("parse: %w", err)
	}
	if cfg != nil {
		cfg.ServerName = pc.Host
		pc.TLSConfig = cfg
		pc.Fallbacks = nil
	}
	c, err := pgx.ConnectConfig(short(), pc)
	if c != nil {
		c.Close(context.Background())
	}
	return err
}

func grpcCall(addr string, creds grpccreds.TransportCredentials) error {
	conn, err := grpc.NewClient(addr, grpc.WithTransportCredentials(creds))
	if err != nil {
		return err
	}
	defer conn.Close()
	_, err = healthpb.NewHealthClient(conn).Check(short(), &healthpb.HealthCheckRequest{})
	return err
}

func h() {
	startObservers()
	pr := func(lib, label, target string, err error) {
		fmt.Printf("H | %-8s | %-52s | %-22s | %s\n", lib, label, target, verdict(err))
	}
	// AWS SDK for Go v2
	buildable := func(cfg func() *tls.Config) *awshttp.BuildableClient {
		return awshttp.NewBuildableClient().WithTransportOptions(func(t *http.Transport) { t.TLSClientConfig = cfg() })
	}
	plain := &http.Client{Transport: &http.Transport{TLSClientConfig: custom()}}
	for _, ep := range []string{"https://localhost:9470", "https://localhost:8445", "https://localhost:8446"} {
		pr("aws-sdk", "BuildableClient, TLSClientConfig=custom", ep, awsCall(buildable(custom), ep))
		pr("aws-sdk", "plain *http.Client{Transport: TLSClientConfig=custom}", ep, awsCall(plain, ep))
		pr("aws-sdk", "BuildableClient, custom + CurvePreferences{X25519,P256}", ep, awsCall(buildable(customBlocked), ep))
	}
	pr("aws-sdk", "default client + WithCustomCABundle (no client cert)", "https://localhost:8443",
		awsCall(nil, "https://localhost:8443", config.WithCustomCABundle(must(os.Open(p("ca.pem"))))))
	pr("aws-sdk", "plain *http.Client + WithCustomCABundle", "https://localhost:8443",
		awsCall(&http.Client{Transport: &http.Transport{}}, "https://localhost:8443", config.WithCustomCABundle(must(os.Open(p("ca.pem"))))))

	// grpc-go
	pr("grpc", "credentials.NewTLS(custom)", "localhost:9472", grpcCall("localhost:9472", grpccreds.NewTLS(custom())))
	pr("grpc", "credentials.NewTLS(custom + CurvePreferences{X25519,P256})", "localhost:9472", grpcCall("localhost:9472", grpccreds.NewTLS(customBlocked())))
	pr("grpc", "credentials.NewClientTLSFromFile(ca.pem)", "localhost:9473", grpcCall("localhost:9473", must(grpccreds.NewClientTLSFromFile(p("ca.pem"), "localhost"))))

	// pgx v5 (direct SSL negotiation so the TLS handshake is the first thing on the wire)
	for _, port := range []string{"9471", "8445", "8446"} {
		base := "postgres://app@localhost:" + port + "/app?sslnegotiation=direct&connect_timeout=5&sslmode=verify-full"
		pr("pgx", "ConnConfig.TLSConfig=custom", "localhost:"+port, pgxCall(base, custom()))
		pr("pgx", "DSN sslrootcert+sslcert+sslkey", "localhost:"+port,
			pgxCall(base+"&sslrootcert=/certs/ca.pem&sslcert=/certs/cli-ec.pem&sslkey=/certs/cli-ec.key", nil))
		pr("pgx", "ConnConfig.TLSConfig=custom + CurvePreferences{X25519,P256}", "localhost:"+port, pgxCall(base, customBlocked()))
	}
	time.Sleep(300 * time.Millisecond)
}

func hAwsEnv() {
	// AWS_CA_BUNDLE is read by LoadDefaultConfig.
	pr := func(label string, err error) {
		fmt.Printf("H | aws-sdk  | %-52s | %-22s | %s\n", label, "https://localhost:8443", verdict(err))
	}
	pr("default client + AWS_CA_BUNDLE env", awsCall(nil, "https://localhost:8443"))
	pr("plain *http.Client + AWS_CA_BUNDLE env", awsCall(&http.Client{Transport: &http.Transport{}}, "https://localhost:8443"))
}

func main() {
	log.SetFlags(0)
	log.SetOutput(os.Stdout)
	switch os.Args[1] {
	case "server":
		serverMain()
	case "h":
		h()
	case "h-awsenv":
		hAwsEnv()
	}
}
