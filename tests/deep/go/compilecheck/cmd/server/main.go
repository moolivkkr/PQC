package main

import (
	"context"
	"crypto/tls"
	"log"
	"net"
	"net/http"
	"os"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/health"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/grpc/peer"
)

func tlsConfig() *tls.Config {
	cert, err := tls.LoadX509KeyPair("/etc/tls/tls.crt", "/etc/tls/tls.key")
	if err != nil {
		log.Fatal(err)
	}
	cfg := &tls.Config{Certificates: []tls.Certificate{cert}, MinVersion: tls.VersionTLS12}
	if os.Getenv("TLS_PQ_ONLY") == "1" { // enforcement mode, after every client is PQ
		cfg.MinVersion = tls.VersionTLS13
		cfg.CurvePreferences = []tls.CurveID{tls.X25519MLKEM768, tls.SecP256r1MLKEM768}
	}
	return cfg
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		log.Printf("path=%s tls_version=%x tls_group=%v", r.URL.Path, r.TLS.Version, r.TLS.CurveID)
		w.Write([]byte("ok\n"))
	})
	go func() {
		srv := &http.Server{Addr: ":8443", Handler: mux, TLSConfig: tlsConfig()}
		log.Fatal(srv.ListenAndServeTLS("", ""))
	}()

	lis, err := net.Listen("tcp", ":9443")
	if err != nil {
		log.Fatal(err)
	}
	gs := grpc.NewServer(grpc.Creds(credentials.NewTLS(tlsConfig())),
		grpc.UnaryInterceptor(func(ctx context.Context, req any, info *grpc.UnaryServerInfo, h grpc.UnaryHandler) (any, error) {
			if p, ok := peer.FromContext(ctx); ok {
				if ti, ok := p.AuthInfo.(credentials.TLSInfo); ok {
					log.Printf("grpc method=%s tls_group=%v", info.FullMethod, ti.State.CurveID)
				}
			}
			return h(ctx, req)
		}))
	healthpb.RegisterHealthServer(gs, health.NewServer())
	log.Fatal(gs.Serve(lis))
}
