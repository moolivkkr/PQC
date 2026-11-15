## What decides PQ here

Go's own `crypto/tls` decides, not OpenSSL, so the base image and OS make no difference. Five inputs set the result: the toolchain version, the `go` line in `go.mod` (it sets `DefaultGODEBUG`), `GODEBUG` at run time, any `tls.Config.CurvePreferences` in your code or a library, and FIPS 140-3 mode. Build with Go 1.26 or 1.27, set `go 1.26` or later in `go.mod`, and don't set `CurvePreferences`. Then clients offer X25519MLKEM768 first and servers accept it, with classical fallback (Tested).

Out of scope here: the Microsoft build of Go and Red Hat's Go toolset, which can route crypto to OpenSSL in FIPS mode. Their PQ behaviour was not tested.

## Status matrix

Client with default `tls.Config`, against one server per group (OpenSSL 3.5.7). Tested 2026-11-14, `golang` images pinned by digest, linux/arm64.

| Toolchain | `go` line in go.mod | X25519MLKEM768 | SecP256r1MLKEM768, SecP384r1MLKEM1024 | Classical server still works | Evidence |
| --- | --- | --- | --- | --- | --- |
| 1.27.4 | 1.27 | Yes | Yes | Yes | Tested |
| 1.27.4 | 1.23 | No (`tlsmlkem=0`) | No | Yes | Tested |
| 1.26.11 | 1.26 | Yes | Yes | Yes | Tested |
| 1.26.11 | 1.25 | Yes | No (`tlssecpmlkem=0`) | Yes | Tested |
| 1.26.11 | 1.23 | No | No | Yes | Tested |
| 1.25.14 | 1.25 | Yes | No (added in 1.26) | Yes | Tested |
| 1.25.14 | 1.23 | No | No | Yes | Tested |
| 1.24.13 | 1.24 | Yes | No | Yes | Tested |
| 1.24.13 | 1.23 | No | No | Yes | Tested |
| 1.23.12 | any | No (no ML-KEM in 1.23) | No | Yes | Tested |

Pure MLKEM1024 is never offered by default. Go 1.27 offers it only when listed in `CurvePreferences` (Tested).

The binary carries its own TLS, so compute type does not change the result.

| Compute type | What to change | Evidence |
| --- | --- | --- |
| Lambda zip, `provided.al2023` or `provided.al2` | Rebuild `bootstrap`; optional `GODEBUG` env var | Tested: same binaries run in `public.ecr.aws/lambda/provided:al2023` gave identical results |
| Lambda container image | Rebuild the image (builder stage Go 1.26+) | Tested (same image as above) |
| Fargate, ECS on EC2, EKS | Rebuild the image; any base, including `scratch` and distroless | Tested in `gcr.io/distroless/static-debian12`; Fargate/EKS not run here |
| EC2 (systemd, SSM-deployed binary) | Redeploy the binary | Not run on EC2; no OS dependency (`CGO_ENABLED=0`) |
| `go1.x` managed Lambda runtime | Retired; move to `provided.al2023` | Documented ([AWS](https://docs.aws.amazon.com/lambda/latest/dg/golang-package.html)) |

## Client side (app level)

Rule for every library below: pass a `tls.Config` without `CurvePreferences`, or none at all. Tested with Go 1.26.11 (`go 1.26`) against a Go server that accepts only X25519MLKEM768 and logs the negotiated group.

| Client | Version tested | Where TLS is set | PQ by default | Evidence |
| --- | --- | --- | --- | --- |
| `crypto/tls` `Dialer`, `tls.Dial` | stdlib | `tls.Config` | Yes | Tested |
| `net/http` default client, `DefaultTransport.Clone()` | stdlib | `Transport.TLSClientConfig` | Yes | Tested |
| gRPC-go | v1.85.0 | `credentials.NewTLS(cfg)` | Yes; it doesn't set `CurvePreferences` | Tested (client to PQ-only gRPC server) |
| AWS SDK for Go v2 | v1.48.0 | `awshttp.NewBuildableClient()` | Yes, outside FIPS mode | Tested |
| AWS SDK for Go v2, FIPS 140-3 mode | v1.48.0 | same | **No**: the SDK forces P-256/P-384/P-521 | Tested; fix below |
| pgx (and `database/sql` via `pgx/v5/stdlib`) | v5.13.0 | `sslmode=require/verify-full`, `ConnConfig.TLSConfig` | Yes | Tested with `sslnegotiation=direct` |
| go-redis | v9.23.0 | `Options.TLSConfig` | Yes | Tested |
| segmentio/kafka-go | v0.4.51 | `Dialer.TLS`, `Transport.TLS` | Yes | Tested |
| IBM/sarama | v1.61.1 | `Config.Net.TLS.Config` | Yes | Tested |
| lib/pq, mongo-go-driver, others | — | their `tls.Config` | Probably, if they don't set `CurvePreferences` | Unverified: grep them (Verify) |

Whether the far end accepts ML-KEM is a server question: see AWS service endpoints and Databases and data services.

**net/http and crypto/tls.** Nothing to set. If a team insists on an explicit list, keep the hybrids in it. Since Go 1.24 the order of `CurvePreferences` is ignored, so position doesn't matter ([Documented](https://pkg.go.dev/crypto/tls#Config)).

```go
tr := http.DefaultTransport.(*http.Transport).Clone()
tr.TLSClientConfig = &tls.Config{MinVersion: tls.VersionTLS12} // no CurvePreferences
client := &http.Client{Transport: tr}

// Only if a list is mandatory (Go 1.26+ constants):
cfg := &tls.Config{CurvePreferences: []tls.CurveID{
    tls.X25519MLKEM768, tls.SecP256r1MLKEM768, tls.X25519, tls.CurveP256}}
```

**gRPC-go.** `credentials.NewTLS` keeps your `tls.Config` as given. Avoid helpers that build a config with a fixed curve list.

```go
creds := credentials.NewTLS(&tls.Config{ServerName: "api.internal"})
conn, err := grpc.NewClient("api.internal:443", grpc.WithTransportCredentials(creds))
```

**AWS SDK for Go v2.** Outside FIPS mode the default HTTP client leaves `CurvePreferences` nil, so it offers X25519MLKEM768 (Tested). In FIPS mode (`GOFIPS140` build or `GODEBUG=fips140=on`), v1.48.0's `aws/transport/http/client.go` sets `CurvePreferences` to P-256, P-384 and P-521. The handshake to a PQ-only server then failed (Tested). I'm not sure which SDK release added this. Put the FIPS-approved hybrids back (Tested: PQ-only server then succeeded):

```go
hc := awshttp.NewBuildableClient().WithTransportOptions(func(t *http.Transport) {
    if fips140.Enabled() {
        t.TLSClientConfig.CurvePreferences = []tls.CurveID{
            tls.SecP256r1MLKEM768, tls.X25519MLKEM768, tls.CurveP256, tls.CurveP384}
    }
})
cfg, _ := config.LoadDefaultConfig(ctx, config.WithHTTPClient(hc))
```

**pgx, database/sql.** `sslmode=verify-full` builds a `tls.Config` without curves. Your own `ConnConfig.TLSConfig` must not add any.

```go
pc, _ := pgx.ParseConfig("postgres://app@db.internal:5432/app?sslmode=verify-full&sslrootcert=/etc/ssl/rds-ca.pem")
conn, err := pgx.ConnectConfig(ctx, pc)
```

**go-redis, kafka-go, sarama.**

```go
rdb := redis.NewClient(&redis.Options{Addr: "cache.internal:6379", TLSConfig: &tls.Config{ServerName: "cache.internal"}})
dialer := &kafka.Dialer{TLS: &tls.Config{}}               // kafka-go
sc := sarama.NewConfig(); sc.Net.TLS.Enable = true; sc.Net.TLS.Config = &tls.Config{} // sarama
```

## Server side

| Server setup | PQ client | Classical client | Evidence |
| --- | --- | --- | --- |
| `net/http` `ListenAndServeTLS`, default `tls.Config` | X25519MLKEM768 and SecP256r1MLKEM768 negotiated | Works (X25519, or P-256 on TLS 1.2) | Tested, Go 1.26.11 |
| `CurvePreferences: {X25519, P256}` (the pitfall) | PQ-only client **fails**; hybrid-capable client silently falls back to X25519 | Works | Tested |
| PQ-only: `MinVersion: TLS13`, `CurvePreferences: {X25519MLKEM768}` | Works | Rejected; TLS 1.2 rejected | Tested |
| gRPC server, `credentials.NewTLS(default)` | X25519MLKEM768 with ALPN h2 | Works | Tested |

**Default server.** Leave `CurvePreferences` nil and build with Go 1.26+ and `go 1.26`. The `go` line governs servers too: `tlsmlkem=0` removes ML-KEM from the default list on both sides ([Documented](https://go.dev/doc/godebug); server side not separately tested).

```go
srv := &http.Server{Addr: ":8443", Handler: mux,
    TLSConfig: &tls.Config{MinVersion: tls.VersionTLS12}} // no CurvePreferences
log.Fatal(srv.ListenAndServeTLS("/etc/tls/tls.crt", "/etc/tls/tls.key"))
```

**PQ-only enforcement** (internal endpoints, after all clients are PQ):

```go
cfg := &tls.Config{MinVersion: tls.VersionTLS13,
    CurvePreferences: []tls.CurveID{tls.X25519MLKEM768, tls.SecP256r1MLKEM768}}
```

**Observed signal.** Go 1.25+ exposes the group: log `r.TLS.CurveID` in HTTP handlers and `credentials.TLSInfo.State.CurveID` in a gRPC interceptor. Lines from the test server:

```text
grpc addr=:9446 tls_group=X25519MLKEM768
raw addr=:9449 handshake_error=tls: no key exchanges supported by both client and server
```

**Behind a load balancer.**

| Front | Who decides the client-facing handshake | Go server's part |
| --- | --- | --- |
| ALB (HTTPS listener) | The ALB security policy | Only the ALB-to-target leg. Whether ALB offers ML-KEM to targets is not confirmed. |
| NLB, TCP listener (passthrough) | Your Go server | Everything above applies |
| NLB, TLS listener | The NLB security policy | Only the NLB-to-target leg |
| API Gateway, CloudFront | The front door | Origin legs are classical |

See the Load balancers tab, Edge and API front doors, and Web servers and proxies for those policies.

## Version rules and FIPS mode

1. **Toolchain** sets what exists: 1.24 added X25519MLKEM768; 1.26 added SecP256r1MLKEM768 and SecP384r1MLKEM1024 to the defaults; 1.27 added opt-in MLKEM1024 ([Go 1.26](https://go.dev/doc/go1.26), [Go 1.27](https://go.dev/doc/go1.27) notes; Tested).
2. **The `go` line** in the main module's `go.mod` (or `go.work`) sets the defaults. Below 1.24 gives `tlsmlkem=0`; below 1.26 gives `tlssecpmlkem=0`. A dependency's `go.mod` doesn't count ([Documented](https://go.dev/doc/godebug); Tested).
3. **Override without raising the `go` line**: a `godebug tlsmlkem=1` line in `go.mod` (Go 1.23+ toolchains), or `//go:debug tlsmlkem=1` above `package main`. Both put `tlsmlkem=1` into `DefaultGODEBUG` (Tested on 1.24 to 1.27). On 1.26+ add `tlssecpmlkem=1` for the SecP hybrids (Tested).
4. **Run-time `GODEBUG`** beats both: `GODEBUG=tlsmlkem=1` turns PQ on with no rebuild; `tlsmlkem=0` turns it off (Tested).
5. **Explicit `CurvePreferences` vs `tlsmlkem=0`.** On 1.24 to 1.26, `tlsmlkem=0` drops X25519MLKEM768 even from an explicit list. From 1.27 an explicit list wins ([Documented](https://go.dev/doc/go1.27); Tested both).
6. **Support window.** Go supports the two newest majors, today 1.27 and 1.26 ([release policy](https://go.dev/doc/devel/release)). Go 1.25 still works for X25519MLKEM768 but gets no security fixes.

Raising the `go` line changes other defaults too. Going to 1.27 removes `tls10server`, `tlsrsakex`, `tls3des`, `tlsunsafeekm`, `x509keypairleaf` and `asynctimerchan`, so run the service tests. The `GODEBUG` route changes only the TLS groups.

**FIPS 140-3 mode** (`GOFIPS140=latest|v1.0.0|v1.26.0` at build, or `GODEBUG=fips140=on`). `crypto/tls` silently drops non-approved groups ([Documented](https://go.dev/doc/security/fips140)). Client results:

| Mode | 1.24.13 | 1.25.14 | 1.26.11 | 1.27.4 |
| --- | --- | --- | --- | --- |
| `fips140=on` | P-256 only: **no PQ**, no X25519 | X25519MLKEM768, P-256 | X25519MLKEM768, SecP256r1MLKEM768, SecP384r1MLKEM1024, P-256 | Same as 1.26 |
| `fips140=only` | P-256 only | **Every handshake fails**: `crypto/ecdh: use of X25519 is not allowed in FIPS 140-only mode` | Same as `on` | Same as `on` |
| `GOEXPERIMENT=boringcrypto`, no `fipsonly` | Same as non-FIPS (PQ yes) | Same as non-FIPS | Same as non-FIPS | Same as non-FIPS |
| boringcrypto + `import _ "crypto/tls/fipsonly"` | not run | P-256 only, no PQ | P-256 only, no PQ | P-256 only, no PQ |
| boringcrypto + `fips140=on` | Panics at start: `FIPS 140-3 mode is incompatible with GOEXPERIMENT=boringcrypto` | Same | Same | Same |

All cells Tested. In FIPS mode a server that offers only X25519 can't be reached, whatever the PQ setting. The TLS group policy follows the toolchain, not the module version: `GOFIPS140=v1.0.0` built with 1.26 offered the SecP hybrids (Tested). Module v1.0.0 holds CMVP certificate #5247; v1.26.0 is in process ([Go FIPS page](https://go.dev/doc/security/fips140), as of 2026-04-28).

What to do: FIPS services should build with Go 1.26+ and native FIPS (`GOFIPS140`), not boringcrypto. Also apply the AWS SDK fix above.

## Packaging per compute type

Every compute type takes the same two levers: rebuild with Go 1.26+ and `go 1.26`+ (preferred), or set `GODEBUG` in the deployment config when the `go` line can't move yet. Full files are in the last section.

**Lambda zip (`provided.al2023`).** The binary must be named `bootstrap` at the zip root ([AWS](https://docs.aws.amazon.com/lambda/latest/dg/golang-package.html)).

```sh
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -tags lambda.norpc -o bootstrap .
zip function.zip bootstrap
go version -m bootstrap | grep -E '^bootstrap|DefaultGODEBUG'   # posture before deploy
```

SAM: `Metadata: BuildMethod: go1.x`, `Runtime: provided.al2023`, `Handler: bootstrap`. If needed: `Environment.Variables.GODEBUG: tlsmlkem=1,tlssecpmlkem=1`. CloudFormation and Terraform set the same variable.

**Lambda container image.** Multi-stage build: `golang:1.26` builder, `public.ecr.aws/lambda/provided:al2023` final stage ([AWS](https://docs.aws.amazon.com/lambda/latest/dg/go-image.html)). Set `GODEBUG` with `ENV` in the Dockerfile or in the function's environment.

**Fargate, ECS, EKS.** Build on `golang:1.26`, ship on `gcr.io/distroless/static-debian12:nonroot` or `scratch` (copy CA certificates). An optional `GODEBUG` goes in the task definition `environment` or the pod `env`.

**EC2.** Ship the binary. An optional `Environment=GODEBUG=...` goes in the systemd unit, rolled out with SSM Run Command or your AMI pipeline.

**FIPS builds.** `GOFIPS140=v1.26.0` (or `latest`) at build time; `go version -m` shows `GOFIPS140=` and `DefaultGODEBUG=fips140=on`.

## Verify

**1. Posture, without running anything.** `go version -m` reads the build info from any Go binary: Lambda `bootstrap`, a file copied out of an image, or a binary on an EC2 host (Tested).

```text
$ go version -m probe-go1.26-mod1.23
probe-go1.26-mod1.23: go1.26.11
        build   DefaultGODEBUG=...,tlsmlkem=0,tlssecpmlkem=0,...
$ go version -m probe-go1.26-mod1.26
probe-go1.26-mod1.26: go1.26.11            # no DefaultGODEBUG line = toolchain defaults = PQ
```

| `go version -m` shows | Meaning |
| --- | --- |
| `go1.23.x` or older | No PQ possible: rebuild |
| `tlsmlkem=0` in `DefaultGODEBUG` | Classical: raise the `go` line or set `tlsmlkem=1` |
| `tlssecpmlkem=0` | X25519MLKEM768 only, no SecP hybrids (matters for FIPS) |
| `GOEXPERIMENT=boringcrypto` | Check for `crypto/tls/fipsonly` (no PQ with it) |
| `GOFIPS140=` / `fips140=on` | FIPS mode: needs Go 1.25+ for any PQ, 1.26+ for the SecP hybrids |

Runtime `GODEBUG` env vars aren't in the binary, so also check the function, task or pod environment. The `go-pq-posture.sh` script in the last section checks every binary in a folder and fails CI.

**2. Code scan.** `CurvePreferences` anywhere in your code or dependencies disables the defaults.

```sh
grep -rn --include='*.go' 'CurvePreferences' . $(go env GOMODCACHE) | grep -v _test.go
```

In the tested versions, only the AWS SDK hit (its FIPS list).

**3. Live test.** Run two servers from an OpenSSL 3.5 image. The client must reach both: the PQ-only one proves PQ, the classical one proves fallback.

```sh
openssl s_server -accept 8443 -tls1_3 -groups X25519MLKEM768 -cert c.pem -key k.pem -www   # PQ-only
openssl s_server -accept 8444 -groups X25519 -cert c.pem -key k.pem -www                   # classical-only
```

For a Go server, run both of these:

- `openssl s_client -connect host:443 -tls1_3 -groups X25519MLKEM768` must print `Negotiated TLS1.3 group: X25519MLKEM768`.
- `-groups X25519` must still connect, unless PQ-only is the goal.

**4. Observed signal.** Server logs `tls_group=` (see Server side). For AWS calls, check CloudTrail `tlsDetails.keyExchange` = `X25519MLKEM768` (KMS, STS, IAM, Secrets Manager, ACM only; see AWS service endpoints).

## Pitfalls and rollback

- **New toolchain, old `go` line.** The most common miss: Go 1.27 with `go 1.23` stayed classical (Tested). Check `DefaultGODEBUG`, not the toolchain.
- **`CurvePreferences` set anywhere.** One explicit list without a hybrid makes that client or server classical, and the fallback is silent (Tested). Check libraries too (AWS SDK in FIPS mode).
- **FIPS on Go 1.24 or boringcrypto + `fipsonly`.** No PQ at all (Tested). Go 1.25 with `fips140=only` fails every handshake (Tested).
- **Go 1.26 with `go 1.25`.** X25519MLKEM768 works but SecP256r1MLKEM768 doesn't. That is the only hybrid FIPS-oriented servers may accept.
- **Big ClientHello.** ML-KEM adds about 1.2 KB, so the ClientHello spans two TCP segments. Broken middleboxes time out ([tldr.fail](https://tldr.fail/)). See Network devices and egress.
- **`tlsmlkem=0` beats your explicit list on 1.24 to 1.26.** Don't leave it set "temporarily".

**Rollback**, fastest first. No code change is needed.

1. Set `GODEBUG=tlsmlkem=0,tlssecpmlkem=0` in the function, task or pod environment, then redeploy or restart.
2. Rebuild with `godebug tlsmlkem=0` in `go.mod`.
3. Redeploy the previous artifact.

Remove the override once the peer is fixed, and record it as a temporary exception with an owner and an end date.

## Full configuration files
These files match the excerpts above. Replace the example account IDs, names and ARNs with your own. The Go sources compile against Go 1.26. Tested parts are marked in the sections above; IaC files follow AWS docs and were not deployed (no AWS access here).

`go.mod` (preferred: raise the `go` line)

```text
module example.com/payments

go 1.26

toolchain go1.27.4

require (
	github.com/aws/aws-lambda-go v1.55.1
	github.com/aws/aws-sdk-go-v2 v1.48.0
	github.com/aws/aws-sdk-go-v2/config v1.33.18
	github.com/aws/aws-sdk-go-v2/service/sts v1.52.0
	google.golang.org/grpc v1.85.0
)
```

Versions are what `go mod tidy` resolved on 2026-11-14 (the sources in this section compile and pass `go vet` with Go 1.26.11). Only the `go` line matters for PQ.

`go.mod` (alternative: keep an old `go` line, turn PQ on)

```text
module example.com/legacy

go 1.23

godebug (
	tlsmlkem=1
	tlssecpmlkem=1
)
```

`tlssecpmlkem` is only known to Go 1.26+ toolchains. On 1.24 or 1.25 builds, list `tlsmlkem=1` only, or the build fails on an unknown setting.

`cmd/client/main.go` (HTTP and AWS SDK client, FIPS-safe)

```go
//go:debug tlsmlkem=1
package main

import (
	"context"
	"crypto/fips140"
	"crypto/tls"
	"log"
	"net/http"
	"time"

	awshttp "github.com/aws/aws-sdk-go-v2/aws/transport/http"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sts"
)

// The //go:debug line is optional: needed only while go.mod says go < 1.24.

func httpClient() *http.Client {
	tr := http.DefaultTransport.(*http.Transport).Clone()
	tr.TLSClientConfig = &tls.Config{MinVersion: tls.VersionTLS12} // no CurvePreferences
	return &http.Client{Transport: tr, Timeout: 30 * time.Second}
}

func awsHTTPClient() *awshttp.BuildableClient {
	return awshttp.NewBuildableClient().WithTransportOptions(func(t *http.Transport) {
		if fips140.Enabled() {
			// aws-sdk-go-v2 v1.48.0 forces P-256/384/521 in FIPS mode; keep the approved hybrids.
			t.TLSClientConfig.CurvePreferences = []tls.CurveID{
				tls.SecP256r1MLKEM768, tls.X25519MLKEM768, tls.CurveP256, tls.CurveP384}
		}
	})
}

func main() {
	ctx := context.Background()
	cfg, err := config.LoadDefaultConfig(ctx, config.WithHTTPClient(awsHTTPClient()))
	if err != nil {
		log.Fatal(err)
	}
	out, err := sts.NewFromConfig(cfg).GetCallerIdentity(ctx, &sts.GetCallerIdentityInput{})
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("caller=%s", *out.Arn)

	resp, err := httpClient().Get("https://api.internal.example.com/health")
	if err != nil {
		log.Fatal(err)
	}
	defer resp.Body.Close()
	log.Printf("status=%d tls_group=%v", resp.StatusCode, resp.TLS.CurveID)
}
```

`cmd/server/main.go` (HTTPS and gRPC server that logs the group)

```go
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
```

`cmd/lambda/main.go` (Lambda handler)

```go
package main

import (
	"context"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sts"
)

func handler(ctx context.Context) (string, error) {
	cfg, err := config.LoadDefaultConfig(ctx) // default HTTP client: PQ outside FIPS mode
	if err != nil {
		return "", err
	}
	out, err := sts.NewFromConfig(cfg).GetCallerIdentity(ctx, &sts.GetCallerIdentityInput{})
	if err != nil {
		return "", err
	}
	return *out.Arn, nil
}

func main() { lambda.Start(handler) }
```

`Makefile` (Lambda zip)

```makefile
GO ?= go
build-lambda:
	GOOS=linux GOARCH=arm64 CGO_ENABLED=0 $(GO) build -trimpath -tags lambda.norpc -o dist/bootstrap ./cmd/lambda
	$(GO) version -m dist/bootstrap | grep -E 'go1\.|DefaultGODEBUG' || true
	cd dist && zip -q function.zip bootstrap
```

`Dockerfile` (ECS, Fargate, EKS: distroless)

```dockerfile
# Pin both images by digest in your registry mirror.
FROM golang:1.26 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -o /out/server ./cmd/server \
 && go version -m /out/server | grep -q 'tlsmlkem=0' && { echo 'classical build: raise go line'; exit 1; } || true

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/server /server
# Optional while go.mod is < 1.26:
# ENV GODEBUG=tlsmlkem=1,tlssecpmlkem=1
USER nonroot:nonroot
EXPOSE 8443 9443
ENTRYPOINT ["/server"]
```

`Dockerfile.lambda` (Lambda container image)

```dockerfile
FROM golang:1.26 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -tags lambda.norpc -o /out/main ./cmd/lambda

FROM public.ecr.aws/lambda/provided:al2023
COPY --from=build /out/main ./main
ENTRYPOINT ["./main"]
```

`Dockerfile.fips` (FIPS 140-3 build)

```dockerfile
FROM golang:1.26 AS build
WORKDIR /src
COPY . .
# Native Go FIPS module; do NOT also set GOEXPERIMENT=boringcrypto (panics at start).
RUN CGO_ENABLED=0 GOFIPS140=v1.26.0 go build -trimpath -o /out/server ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/server /server
ENTRYPOINT ["/server"]
```

`template.yaml` (SAM, Lambda zip)

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Resources:
  PaymentsFunction:
    Type: AWS::Serverless::Function
    Metadata:
      BuildMethod: go1.x
    Properties:
      CodeUri: cmd/lambda/
      Handler: bootstrap
      Runtime: provided.al2023
      Architectures: [arm64]
      Timeout: 10
      Environment:
        Variables:
          # Only while go.mod is below 1.26. Remove after raising the go line.
          GODEBUG: tlsmlkem=1,tlssecpmlkem=1
```

`lambda-cfn.yaml` (plain CloudFormation, zip in S3)

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Parameters:
  CodeBucket: {Type: String}
  CodeKey: {Type: String, Default: payments/function.zip}
  RoleArn: {Type: String}
Resources:
  PaymentsFunction:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: payments
      PackageType: Zip
      Runtime: provided.al2023
      Handler: bootstrap
      Architectures: [arm64]
      Role: !Ref RoleArn
      Code: {S3Bucket: !Ref CodeBucket, S3Key: !Ref CodeKey}
      Environment:
        Variables:
          GODEBUG: tlsmlkem=1,tlssecpmlkem=1
```

`lambda.tf` (Terraform, zip and image)

```hcl
resource "aws_lambda_function" "payments" {
  function_name    = "payments"
  role             = var.lambda_role_arn
  runtime          = "provided.al2023"
  handler          = "bootstrap"
  architectures    = ["arm64"]
  filename         = "${path.module}/dist/function.zip"
  source_code_hash = filebase64sha256("${path.module}/dist/function.zip")

  environment {
    variables = {
      GODEBUG = "tlsmlkem=1,tlssecpmlkem=1" # only while go.mod < 1.26
    }
  }
}

resource "aws_lambda_function" "payments_image" {
  function_name = "payments-image"
  role          = var.lambda_role_arn
  package_type  = "Image"
  image_uri     = "111122223333.dkr.ecr.us-east-1.amazonaws.com/payments@sha256:<digest>"
  architectures = ["arm64"]
}
```

`taskdef.json` (ECS / Fargate)

```json
{
  "family": "payments-api",
  "requiresCompatibilities": ["FARGATE"],
  "networkMode": "awsvpc",
  "cpu": "512",
  "memory": "1024",
  "runtimePlatform": {"cpuArchitecture": "ARM64", "operatingSystemFamily": "LINUX"},
  "executionRoleArn": "arn:aws:iam::111122223333:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::111122223333:role/payments-task",
  "containerDefinitions": [
    {
      "name": "api",
      "image": "111122223333.dkr.ecr.us-east-1.amazonaws.com/payments-api@sha256:<digest>",
      "essential": true,
      "portMappings": [{"containerPort": 8443, "protocol": "tcp"}, {"containerPort": 9443, "protocol": "tcp"}],
      "environment": [
        {"name": "GODEBUG", "value": "tlsmlkem=1,tlssecpmlkem=1"},
        {"name": "TLS_PQ_ONLY", "value": "0"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {"awslogs-group": "/ecs/payments-api", "awslogs-region": "us-east-1", "awslogs-stream-prefix": "api"}
      }
    }
  ]
}
```

`ecs-task.tf` (Terraform for the same task definition)

```hcl
resource "aws_ecs_task_definition" "payments_api" {
  family                   = "payments-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
  container_definitions = jsonencode([{
    name         = "api"
    image        = var.image # repo@sha256:digest
    essential    = true
    portMappings = [{ containerPort = 8443, protocol = "tcp" }, { containerPort = 9443, protocol = "tcp" }]
    environment  = [{ name = "GODEBUG", value = "tlsmlkem=1,tlssecpmlkem=1" }]
  }])
}
```

`deployment.yaml` (EKS)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payments-api
  namespace: payments
spec:
  replicas: 2
  selector:
    matchLabels: {app: payments-api}
  template:
    metadata:
      labels: {app: payments-api}
    spec:
      securityContext: {runAsNonRoot: true}
      containers:
        - name: api
          image: 111122223333.dkr.ecr.us-east-1.amazonaws.com/payments-api@sha256:<digest>
          ports:
            - {containerPort: 8443, name: https}
            - {containerPort: 9443, name: grpc}
          env:
            - name: GODEBUG          # only while go.mod < 1.26
              value: tlsmlkem=1,tlssecpmlkem=1
            - name: TLS_PQ_ONLY
              value: "0"
          volumeMounts:
            - {name: tls, mountPath: /etc/tls, readOnly: true}
      volumes:
        - name: tls
          secret: {secretName: payments-api-tls}
```

`/etc/systemd/system/payments-api.service` (EC2)

```ini
[Unit]
Description=payments API (Go)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/opt/payments/server
User=payments
# Only while the binary's go.mod is < 1.26:
Environment=GODEBUG=tlsmlkem=1,tlssecpmlkem=1
Environment=TLS_PQ_ONLY=0
Restart=on-failure
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

`go-pq-posture.sh` (CI gate and host or image scan)

```sh
#!/bin/sh
# Usage: go-pq-posture.sh <dir-with-go-binaries>   (needs a Go toolchain on PATH)
# Fails if any Go binary is classical by build. Runtime GODEBUG must be checked separately.
rc=0
for f in $(find "$1" -type f -perm -u+x); do
  info=$(go version -m "$f" 2>/dev/null) || continue      # not a Go binary
  ver=$(echo "$info" | head -1 | sed -E 's/.*go1\.([0-9]+).*/\1/')
  dbg=$(echo "$info" | grep -o 'DefaultGODEBUG=[^ ]*')
  exp=$(echo "$info" | grep -o 'GOEXPERIMENT=[^ ]*')
  if [ "$ver" -lt 24 ]; then echo "FAIL $f go1.$ver: no ML-KEM"; rc=1
  elif echo "$dbg" | grep -q 'tlsmlkem=0'; then echo "FAIL $f go1.$ver: tlsmlkem=0 (go.mod go line < 1.24)"; rc=1
  elif echo "$exp" | grep -q boringcrypto; then echo "WARN $f boringcrypto: check for crypto/tls/fipsonly"
  elif echo "$dbg" | grep -q 'fips140=on' && [ "$ver" -lt 25 ]; then echo "FAIL $f go1.$ver FIPS: no PQ before 1.25"; rc=1
  else echo "OK   $f go1.$ver $dbg"; fi
done
exit $rc
```

To scan an image: `docker create --name x <image>; docker cp x:/server ./scan/; docker rm x; ./go-pq-posture.sh ./scan`. To scan EC2 hosts, run it through SSM Run Command on the binary folder.

Test kit used for this tab (scripts and raw output): `servers.sh`, `probe/main.go`, `build.sh`, `run-clients.sh`, `srv/main.go`, `libs/main.go`, `extra/main.go`, `run-server-tests.sh`, `run-libs.sh`, with outputs `clients.out`, `server-tests.out`, `libs.out`, `awsfix.out`, `compute.out`, `gosrv.log`.
