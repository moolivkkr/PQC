// srv: Go TLS servers for the server-side tests, plus a gRPC client mode.
//   srv serve   -> :9443 net/http default tls.Config
//                  :9444 net/http CurvePreferences [X25519, P256] (pitfall)
//                  :9445 net/http PQ-only (TLS 1.3, CurvePreferences [X25519MLKEM768])
//                  :9446 gRPC, credentials.NewTLS(default config)
//                  :9447 gRPC, PQ-only (to test the gRPC client)
//   srv grpcclient <addr> -> gRPC health check with default client TLS config
package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"fmt"
	"log"
	"math/big"
	"net"
	"net/http"
	"os"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/health"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/grpc/peer"
)

func selfSigned() tls.Certificate {
	k, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	t := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "gosrv"},
		DNSNames: []string{"gosrv"}, NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(48 * time.Hour)}
	der, _ := x509.CreateCertificate(rand.Reader, t, t, &k.PublicKey, k)
	return tls.Certificate{Certificate: [][]byte{der}, PrivateKey: k}
}

func httpsServer(addr string, cfg *tls.Config) {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		// Observed signal: log the negotiated group per request (ConnectionState.CurveID, Go 1.25+).
		log.Printf("addr=%s tls_version=%x tls_group=%v", addr, r.TLS.Version, r.TLS.CurveID)
		fmt.Fprintf(w, "group=%v\n", r.TLS.CurveID)
	})
	s := &http.Server{Addr: addr, Handler: mux, TLSConfig: cfg}
	go func() { log.Println(s.ListenAndServeTLS("", "")) }()
}

func grpcServer(addr string, cfg *tls.Config) {
	lis, err := net.Listen("tcp", addr)
	if err != nil {
		log.Fatal(err)
	}
	s := grpc.NewServer(grpc.Creds(credentials.NewTLS(cfg)),
		grpc.UnaryInterceptor(func(ctx context.Context, req any, info *grpc.UnaryServerInfo, h grpc.UnaryHandler) (any, error) {
			if p, ok := peer.FromContext(ctx); ok {
				if ti, ok := p.AuthInfo.(credentials.TLSInfo); ok {
					log.Printf("grpc addr=%s tls_group=%v", addr, ti.State.CurveID)
				}
			}
			return h(ctx, req)
		}))
	healthpb.RegisterHealthServer(s, health.NewServer())
	go s.Serve(lis)
}

// rawServer: protocol-agnostic TLS listener for library tests. Completes the handshake,
// logs the client's group (or the handshake error), then closes the connection.
func rawServer(addr string, cfg *tls.Config) {
	lis, err := tls.Listen("tcp", addr, cfg)
	if err != nil {
		log.Fatal(err)
	}
	go func() {
		for {
			c, err := lis.Accept()
			if err != nil {
				continue
			}
			go func(c net.Conn) {
				defer c.Close()
				tc := c.(*tls.Conn)
				c.SetDeadline(time.Now().Add(5 * time.Second))
				if err := tc.Handshake(); err != nil {
					log.Printf("raw addr=%s from=%s handshake_error=%v", addr, c.RemoteAddr(), err)
					return
				}
				log.Printf("raw addr=%s from=%s tls_group=%v", addr, c.RemoteAddr(), tc.ConnectionState().CurveID)
			}(c)
		}
	}()
}

func main() {
	if len(os.Args) > 2 && os.Args[1] == "grpcclient" {
		creds := credentials.NewTLS(&tls.Config{InsecureSkipVerify: true}) // no CurvePreferences: Go defaults
		conn, err := grpc.NewClient(os.Args[2], grpc.WithTransportCredentials(creds))
		if err != nil {
			fmt.Println("grpc client FAIL", err)
			return
		}
		defer conn.Close()
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		r, err := healthpb.NewHealthClient(conn).Check(ctx, &healthpb.HealthCheckRequest{})
		fmt.Println("grpc client", os.Args[2], r.GetStatus(), err)
		return
	}
	cert := selfSigned()
	base := func() *tls.Config { return &tls.Config{Certificates: []tls.Certificate{cert}} }
	httpsServer(":9443", base())
	pitfall := base()
	pitfall.CurvePreferences = []tls.CurveID{tls.X25519, tls.CurveP256}
	httpsServer(":9444", pitfall)
	pqOnly := base()
	pqOnly.MinVersion = tls.VersionTLS13
	pqOnly.CurvePreferences = []tls.CurveID{tls.X25519MLKEM768}
	httpsServer(":9445", pqOnly)
	grpcServer(":9446", base())
	grpcServer(":9447", pqOnly.Clone())
	rawServer(":9448", pqOnly.Clone())
	classic := base()
	classic.CurvePreferences = []tls.CurveID{tls.X25519}
	rawServer(":9449", classic)
	log.Println("go-servers-up")
	select {}
}
