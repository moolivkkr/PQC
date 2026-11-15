<!-- go-v2.md: new and rewritten sections for the Go tab (v2 structure). Blocks marked [MOVED] are the existing
tab blocks (text in ../go.md) moved under the new headings with the docs `move` op, not retyped. -->

## Problem statement

A Go service is classical when any one of these is true, and it says nothing about it: the binary was built with Go 1.23 or older, the main module's `go` line is below 1.24, code or a library sets `CurvePreferences` without a hybrid or caps TLS at 1.2, or FIPS mode runs on Go 1.24 or with boringcrypto `fipsonly`. The handshake still succeeds with X25519, so nothing breaks and no log shows it (Tested).

Go's own `crypto/tls`, compiled into the binary, controls the handshake. OpenSSL, the OS crypto policy, the base image and the Lambda runtime play no part. Five inputs decide the result: the toolchain version, the `go` line in `go.mod` (it sets `DefaultGODEBUG`), `GODEBUG` at run time, any `tls.Config.CurvePreferences` or `MaxVersion` in your code or a library, and FIPS 140-3 mode. Exceptions: the Microsoft build of Go and Red Hat's Go toolset can route crypto to OpenSSL in FIPS mode; their PQ behaviour was not tested.

The risk is harvest-now-decrypt-later: traffic recorded today under X25519 or P-256 key exchange can be decrypted once a large quantum computer exists. Hybrid X25519MLKEM768 removes that risk for new sessions. Certificates and keystores are a separate question (see Certificates (ML-DSA)).

## Versions and native support

The binary carries its own TLS, so the answer is the same on Lambda (zip or image), ECS, Fargate, EKS and EC2 (Tested: identical results in `public.ecr.aws/lambda/provided:al2023`, `distroless/static-debian12` and `debian:trixie-slim`).

| Version | TLS stack | PQ client by default (all compute types) | PQ server by default | API to set groups | FIPS-mode behaviour | Proposed solution | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1.27.x (supported) | `crypto/tls` in the binary | Yes, when `go` line ≥ 1.24: X25519MLKEM768; SecP256r1MLKEM768 and SecP384r1MLKEM1024 when `go` ≥ 1.26 | Yes, same rule | `CurvePreferences` (an explicit list now beats `tlsmlkem=0`); `GODEBUG` `tlsmlkem`, `tlssecpmlkem`; opt-in `MLKEM1024` | `fips140=on`/`only`: the three hybrids + P-256 | Keep; set `go 1.26`+ | Tested (2026-11-14, first pass) |
| 1.26.x (supported) | same | Yes, same rule as 1.27 | Yes | `CurvePreferences`; `GODEBUG` (`tlsmlkem=0` beats an explicit list) | Same as 1.27 | **Target.** Build with 1.26+, `go 1.26` | Tested (this pass: cases C to I) |
| 1.25.x (no security fixes since 1.27) | same | Yes if `go` ≥ 1.24, X25519MLKEM768 only | Yes | same as 1.26 | `on`: X25519MLKEM768 + P-256; `only`: **every handshake fails** | Upgrade to 1.26 | Tested |
| 1.24.x (unsupported) | same | Yes if `go` ≥ 1.24; **No** with `go 1.22`/`1.23` (`tlsmlkem=0`) | Same rule: a `go 1.22` server refused a PQ-only client (Tested this pass) | same | `on`/`only`: P-256 only, **no PQ** | Upgrade; interim `GODEBUG=tlsmlkem=1` (Tested client and server) | Tested |
| 1.23 and older (unsupported) | same | **No ML-KEM.** 1.23 offers the pre-standard `X25519Kyber768Draft00` (0x6399), which OpenSSL 3.5 PQ-only servers reject | No | `tlskyber` only | No PQ | Rebuild with 1.26 | Tested (1.23.12; source `crypto/tls/defaults.go`) |

**Decision guide**

- `go version -m <binary>` shows `go1.23` or older: rebuild with Go 1.26. Nothing else helps.
- It shows `tlsmlkem=0` in `DefaultGODEBUG`: raise the `go` line to 1.26. If you can't yet, add `godebug tlsmlkem=1` to `go.mod` or set `GODEBUG=tlsmlkem=1` in the function, task or pod.
- Your code or a library sets `CurvePreferences` or `MaxVersion: tls.VersionTLS12`: fix it (case F).
- You run FIPS mode: Go 1.26+ native FIPS (`GOFIPS140`), not boringcrypto (case G).
- None of the above: you already negotiate X25519MLKEM768. Verify (How to test) and move on.

[MOVED under a "Detail: toolchain and go line" paragraph: status-matrix lead .3153, table .3295, MLKEM1024 note .3862, compute paragraph .3971, compute table .4047, version-rules list .10221 and the raising-the-go-line paragraph .11317]

## Cases: what to change

### A. Simple client

**Who this is.** No TLS settings in your code: `grep -rnE --include='*.go' 'tls\.Config|TLSClientConfig|CurvePreferences|MaxVersion' .` finds nothing. You use `http.Get`, the AWS SDK default client, or a DB driver with a DSN.

**What happens today.** PQ when the toolchain and the `go` line are both 1.24+; classical otherwise (Tested, every library in the table below).

**What to change.** Nothing in code. Raise the `go` line and rebuild.

**Side effects.** The ClientHello grows by about 1.2 KB (see Pitfalls). Raising the `go` line changes other `GODEBUG` defaults too.

[MOVED: client table .4746 .4953 .5963 and the net/http paragraph + code .6033 .6234]

### B. Simple server

**Who this is.** `http.ListenAndServeTLS`, or frameworks on top of `net/http` (chi, gin, echo), or a gRPC server with `credentials.NewTLS`, with no `CurvePreferences`.

**What happens today.** With 1.24+ and `go` ≥ 1.24, RSA and EC servers negotiate X25519MLKEM768 with a PQ client and X25519 with a classical one (Tested 1.24.13, 1.25.14, 1.26.11). A 1.24 build with `go 1.22` refused a PQ-only client and served X25519 to others; `GODEBUG=tlsmlkem=1` fixed it with no rebuild (Tested).

**What to change.** Nothing beyond the build. **Side effects.** None seen.

[MOVED: server table .8249, default-server paragraph + code .8793 .9017]

### C. Existing server certificates in your own files or keystore

**Who this is.** `grep -rnE --include='*.go' 'LoadX509KeyPair|X509KeyPair|GetCertificate|pkcs12\.|DecryptPEMBlock|pkcs8\.' .`

**What happens today.** The certificate store has no effect on key exchange. Every setup below negotiated X25519MLKEM768 with an OpenSSL 3.5.7 PQ-only client and X25519 with a classical client, as a server built with Go 1.24.13 (`go 1.24`), 1.25.14 and 1.26.11. With Go 1.23.12 or `go 1.22` every row was classical, so the store was never the cause (all Tested).

| Setup | Code | Which certificate is served | Store change |
| --- | --- | --- | --- |
| RSA 2048 PEM pair | `tls.LoadX509KeyPair(crt, key)` | RSA | None |
| EC P-256 PEM pair | same | EC | None |
| RSA and EC together | `Certificates: {rsa, ec}` | Go serves the **first** certificate the client supports: RSA to a default client, EC only to an ECDSA-only client | None; order picks the cert, not the group |
| EC and RSA together | `Certificates: {ec, rsa}` | EC to a default client, RSA to an RSA-only client | None |
| Two hostnames | `Certificates: {a.test, b.test}` | Matched by SNI; unknown SNI gets the first | None |
| Callback | `GetCertificate` by `ClientHelloInfo.ServerName` | Per SNI, with your fallback | None |
| Legacy encrypted PEM (`Proc-Type: 4,ENCRYPTED`) | `x509.DecryptPEMBlock` then `tls.X509KeyPair` | RSA | None |
| Encrypted PKCS#8 (`BEGIN ENCRYPTED PRIVATE KEY`) | `github.com/youmark/pkcs8` `ParsePKCS8PrivateKey` (1.26.11) | EC | None |
| PKCS#12, OpenSSL 3 default (AES-256-CBC, PBKDF2, SHA-256 MAC) with chain | `software.sslmate.com/src/go-pkcs12` v0.7.4 `DecodeChain` (1.26.11) | EC | None |
| PKCS#12, legacy 3DES/SHA-1 | `golang.org/x/crypto/pkcs12` v0.59.0 `Decode` (1.26.11) | RSA | None |
| Same x/crypto package on the OpenSSL 3 default file | `Decode` | Fails at load: `pkcs12: unknown digest algorithm: 2.16.840.1.101.3.4.2.1` | Use go-pkcs12, or re-export the file |
| Cert and key PEM in env vars (ECS `secrets`, Lambda env) | `tls.X509KeyPair([]byte(os.Getenv(...)))` | RSA | None |

**Encrypted keys.** The Go standard library can't read encrypted PKCS#8, and `x509.DecryptPEMBlock` is deprecated because RFC 1423 encryption is insecure by design ([Documented](https://pkg.go.dev/crypto/x509#DecryptPEMBlock)). What teams do instead, in order of preference:

1. Keep the key unencrypted at rest inside a secret store (Secrets Manager, a Kubernetes Secret, the ECS `secrets` field), mount or inject it with tight permissions, and load it with `tls.X509KeyPair` (Tested above).
2. Keep the encrypted file and decrypt at start-up with `youmark/pkcs8`, the passphrase coming from Secrets Manager (Tested above).
3. Move the key into KMS or an HSM behind a `crypto.Signer` (case I).

`golang.org/x/crypto/pkcs12` is frozen; its own docs point to `software.sslmate.com/src/go-pkcs12` ([Documented](https://pkg.go.dev/golang.org/x/crypto/pkcs12)).

**What changes in the store.** Nothing. Keep the same files, formats, passwords, key types and chains. The only change is the build: Go 1.26+ toolchain and `go 1.26` in `go.mod`, or `GODEBUG=tlsmlkem=1` while the `go` line can't move.

**Exact code or config change, per setup.** Your loading code stays as it is. The one rule: the `tls.Config` it fills must not set `CurvePreferences` (or must include `tls.X25519MLKEM768`) and must not set `MaxVersion: tls.VersionTLS12`. The excerpts below are the tested loaders (full code in `cases/main.go` and `deps/main.go`):

```go
// PEM pair, RSA or EC: unchanged
cert, err := tls.LoadX509KeyPair("/etc/tls/tls.crt", "/etc/tls/tls.key")
cfg := &tls.Config{Certificates: []tls.Certificate{cert}} // no CurvePreferences, no MaxVersion

// Paths from env vars (TLS_CERT_FILE / TLS_KEY_FILE): unchanged
cert, err := tls.LoadX509KeyPair(os.Getenv("TLS_CERT_FILE"), os.Getenv("TLS_KEY_FILE"))

// PEM content injected as env vars (ECS `secrets`, Lambda env from Secrets Manager): unchanged
cert, err := tls.X509KeyPair([]byte(os.Getenv("TLS_CERT_PEM")), []byte(os.Getenv("TLS_KEY_PEM")))

// RSA + EC on one listener: order decides which cert default clients get (first supported wins)
cfg := &tls.Config{Certificates: []tls.Certificate{ecCert, rsaCert}} // EC first = EC to modern clients

// Several hostnames: either a list matched by SNI ...
cfg := &tls.Config{Certificates: []tls.Certificate{aCert, bCert}}
// ... or a callback (hot reload, many tenants)
cfg := &tls.Config{GetCertificate: func(h *tls.ClientHelloInfo) (*tls.Certificate, error) {
    if c, ok := byName[h.ServerName]; ok { return c, nil }
    return &defaultCert, nil
}}

// PKCS#12 / PFX (OpenSSL 3 default or legacy): software.sslmate.com/src/go-pkcs12
key, leaf, chain, err := pkcs12.DecodeChain(p12Bytes, os.Getenv("TLS_KEY_PASS"))
c := tls.Certificate{PrivateKey: key, Leaf: leaf, Certificate: [][]byte{leaf.Raw}}
for _, ca := range chain { c.Certificate = append(c.Certificate, ca.Raw) }

// Encrypted PKCS#8 ("BEGIN ENCRYPTED PRIVATE KEY"): github.com/youmark/pkcs8
blk, _ := pem.Decode(keyPEM)
key, err := pkcs8.ParsePKCS8PrivateKey(blk.Bytes, []byte(os.Getenv("TLS_KEY_PASS")))

// Legacy encrypted PEM ("Proc-Type: 4,ENCRYPTED"): stdlib, deprecated; migrate when you can
blk, _ := pem.Decode(keyPEM)
der, err := x509.DecryptPEMBlock(blk, []byte(pass)) //nolint:staticcheck
cert, err := tls.X509KeyPair(certPEM, pem.EncodeToMemory(&pem.Block{Type: blk.Type, Bytes: der}))
```

If you load PKCS#12 with `golang.org/x/crypto/pkcs12`, switch the import to `software.sslmate.com/src/go-pkcs12` when your files come from OpenSSL 3 (its default PKCS#12 format). Or re-export them with `openssl pkcs12 -export -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1`. Prefer the import change, because the legacy format uses 3DES and SHA-1.

**Tested proof.** Go 1.26.11 server, OpenSSL 3.5.7 `s_client -brief -CAfile ca.pem -verify_return_error`, from `run-v2.out`. The server log is Go's own `ConnectionState().CurveID`:

```text
port=9443 case="C rsa LoadX509KeyPair" TLS1.3 group=X25519MLKEM768
port=9444 case="C ec LoadX509KeyPair" TLS1.3 group=X25519MLKEM768
probe C two certs [rsa,ec] -groups X25519MLKEM768 -tls1_3 | OK | Negotiated TLS1.3 group: X25519MLKEM768 | cert=CN=srv-rsa
probe C two certs [rsa,ec] ... -sigalgs ecdsa_secp256r1_sha256 | OK | X25519MLKEM768 | cert=CN=srv-ec
probe C two certs [ec,rsa] -groups X25519MLKEM768 -tls1_3 | OK | X25519MLKEM768 | cert=CN=srv-ec
port=9447 case="C SNI Certificates=[a.test,b.test]" group=X25519MLKEM768 sni="a.test"   (cert=CN=a.test)
port=9447 ... group=X25519 sni="b.test"   (classical client, cert=CN=b.test)
port=9448 case="C GetCertificate by SNI" group=X25519MLKEM768 sni="c.test"   (fallback cert=CN=srv-ec)
port=9449 case="C encrypted legacy PEM key" TLS1.3 group=X25519MLKEM768
port=9455 case="C cert+key PEM from env vars" TLS1.3 group=X25519MLKEM768
port=9460 case="C PKCS#12 modern via sslmate DecodeChain" group=X25519MLKEM768 leaf=srv-ec
port=9461 case="C PKCS#12 legacy via x/crypto Decode" group=X25519MLKEM768 leaf=srv-rsa
port=9462 case="C encrypted PKCS#8 via youmark/pkcs8" group=X25519MLKEM768 leaf=srv-ec
case="C x/crypto Decode on modern PKCS#12" load_error=pkcs12: unknown digest algorithm: 2.16.840.1.101.3.4.2.1
```

Each server also served X25519 to a classical client (fallback). Go 1.24.13 (`go 1.24`) and 1.25.14 gave the same OK results. Go 1.23.12 and 1.24.13 with `go 1.22` failed every PQ-only probe with the same stores. The test files were made by `gen-certs.sh`: RSA 2048, EC P-256, and the PKCS#12 formats confirmed with `openssl pkcs12 -info`: AES-256-CBC/PBKDF2/SHA-256 MAC, and 3DES/SHA-1.

**Side effects.** None for PQ. If you list RSA before EC, default clients get RSA; that was already true.

### D. Custom CA trust

**Who this is.** `grep -rnE 'SystemCertPool|AppendCertsFromPEM|RootCAs|SSL_CERT_FILE|SSL_CERT_DIR|AWS_CA_BUNDLE|WithCustomCABundle|sslrootcert'` in code and deployment files.

**What happens today.** Trust and key exchange are independent. Each row reached the PQ-only server with X25519MLKEM768 and the classical server with X25519, on Go 1.24.13 (`go 1.24`), 1.25.14 and 1.26.11 (Tested):

| Trust setup | Result |
| --- | --- |
| `SSL_CERT_FILE=/certs/ca.pem`, `RootCAs` nil | PQ and fallback OK |
| `SSL_CERT_DIR=/certs/cadir`, `RootCAs` nil | PQ and fallback OK |
| Neither set, private CA not in the system store | `x509: certificate signed by unknown authority` (expected) |
| `x509.SystemCertPool()` + `AppendCertsFromPEM` | PQ and fallback OK |
| `RootCAs` = new pool with only the private CA | PQ and fallback OK |
| `RootCAs` = empty pool | Unknown authority (expected) |
| AWS SDK `AWS_CA_BUNDLE` or `config.WithCustomCABundle`, default HTTP client | PQ OK (1.26.11) |
| AWS SDK CA bundle + a plain `*http.Client` | **Config error**: `unable to add custom RootCAs HTTPClient, has no WithTransportOptions, *http.Client` (1.26.11) |
| gRPC `credentials.NewClientTLSFromFile(ca.pem, ...)` | PQ OK (1.26.11) |
| pgx DSN `sslrootcert=` | PQ OK (1.26.11) |

`SSL_CERT_FILE` and `SSL_CERT_DIR` replace the default locations, they don't add to them ([Documented](https://pkg.go.dev/crypto/x509#SystemCertPool)). Put public roots in that file too if the service also calls public endpoints.

**What changes in the truststore.** Nothing. Keep the same CA bundle files, directories, env vars and pools. Rebuild with Go 1.26+ and `go 1.26`, or set `GODEBUG=tlsmlkem=1` in the interim.

**Exact code or config change, per setup.** Your trust code stays as it is, with one exception (the AWS row). The tested forms:

```go
// 1. Env-var trust (no code): SSL_CERT_FILE or SSL_CERT_DIR, RootCAs left nil
//    Dockerfile:   ENV SSL_CERT_FILE=/etc/ssl/certs/bundle-with-private-ca.pem
//    ECS taskdef:  "environment": [{"name": "SSL_CERT_FILE", "value": "/etc/ssl/certs/bundle-with-private-ca.pem"}]
//    Lambda / systemd: same variable. It REPLACES the default file, so the bundle must also hold public roots
//    if the service calls public endpoints.
cfg := &tls.Config{} // RootCAs nil = system pool built from SSL_CERT_FILE / SSL_CERT_DIR

// 2. System roots plus your private CA
pool, err := x509.SystemCertPool()
if err != nil { pool = x509.NewCertPool() }
pool.AppendCertsFromPEM(caPEM)
cfg := &tls.Config{RootCAs: pool}

// 3. Private CA only (internal endpoints)
pool := x509.NewCertPool(); pool.AppendCertsFromPEM(caPEM)
cfg := &tls.Config{RootCAs: pool}

// 4. AWS SDK: AWS_CA_BUNDLE env or WithCustomCABundle needs the SDK's BuildableClient
cfg, err := config.LoadDefaultConfig(ctx, config.WithCustomCABundle(caFile)) // default client: works
// With your own client: do NOT pass a plain *http.Client together with a CA bundle (config error).
// Set RootCAs on a BuildableClient instead:
hc := awshttp.NewBuildableClient().WithTransportOptions(func(t *http.Transport) {
    t.TLSClientConfig = &tls.Config{RootCAs: pool} // no CurvePreferences
})
cfg, err := config.LoadDefaultConfig(ctx, config.WithHTTPClient(hc))

// 5. gRPC
creds, err := credentials.NewClientTLSFromFile("/etc/ssl/private-ca.pem", "api.internal")

// 6. pgx / database/sql
//    postgres://app@db.internal:5432/app?sslmode=verify-full&sslrootcert=/etc/ssl/rds-ca.pem
```

On `scratch` or distroless static images there is no system bundle. Copy one in (`COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/`) or use form 3.

**Tested proof.** Go client against the OpenSSL 3.5.7 PQ-only server (:8443) and the classical server (:8444). Both use a cert issued by the private test CA. From `run-v2.out`, Go 1.26.11:

```text
D | default RootCAs (SSL_CERT_FILE)            | localhost:8443 | OK   | TLS1.3 group=X25519MLKEM768
D | default RootCAs (SSL_CERT_FILE)            | localhost:8444 | OK   | TLS1.3 group=X25519
D | default RootCAs (SSL_CERT_DIR)             | localhost:8443 | OK   | TLS1.3 group=X25519MLKEM768
D | default RootCAs (no env, negative)         | localhost:8443 | FAIL | x509: certificate signed by unknown authority
D | SystemCertPool()+AppendCertsFromPEM(ca)    | localhost:8443 | OK   | TLS1.3 group=X25519MLKEM768
D | RootCAs = NewCertPool with private CA only | localhost:8443 | OK   | TLS1.3 group=X25519MLKEM768
D | RootCAs = empty pool (negative)            | localhost:8443 | FAIL | x509: certificate signed by unknown authority
H | aws-sdk | default client + AWS_CA_BUNDLE env           | :8443 | TLS-OK (then protocol error: test server isn't STS)
H | aws-sdk | default client + WithCustomCABundle          | :8443 | TLS-OK
H | aws-sdk | plain *http.Client + WithCustomCABundle      | :8443 | config: unable to add custom RootCAs HTTPClient, has no WithTransportOptions, *http.Client
H | grpc    | credentials.NewClientTLSFromFile(ca.pem)     | :9473 | TLS-OK   (observer: X25519MLKEM768)
H | pgx     | DSN sslrootcert+sslcert+sslkey               | :9471 | observer=raw group=X25519MLKEM768 client_cn=cli-ec
```

The 8443 server accepts only X25519MLKEM768, so every OK against it proves PQ. Go 1.24.13 (`go 1.24`) and 1.25.14 gave the same results. Go 1.23.12 and 1.24.13 with `go 1.22` failed on 8443 with every trust setup and passed on 8444. So trust was never the cause.

**Side effects.** None.

### E. Mutual TLS (client certificates)

**Who this is.** `grep -rnE --include='*.go' 'ClientAuth|ClientCAs|GetClientCertificate|Certificates:' .`

**What happens today.** Client certificates don't change the group (Tested on 1.24.13 `go 1.24`, 1.25.14, 1.26.11):

- Go client with `Certificates: {RSA client cert}` or `GetClientCertificate` returning an EC cert, against an OpenSSL server with `-Verify 1`: X25519MLKEM768 when PQ-only, X25519 when classical-only.
- Go server with `ClientAuth: tls.RequireAndVerifyClientCert` and `ClientCAs`: RSA and EC clients over X25519MLKEM768, `client_cn` logged; a classical client over X25519.
- No client cert: refused as expected. In TLS 1.3 the client sees the error on its first read (`remote error: tls: certificate required`); the server logs `tls: client didn't provide a certificate`.
- AWS SDK, gRPC and pgx with a client cert: case H.

**What to change.** Nothing. **Side effects.** None.

### F. Explicit TLS settings that block PQ

**Who this is.** Run `go-pq-lint.sh` (Full configuration files), or:

```sh
grep -rnE --include='*.go' 'CurvePreferences|MaxVersion|CipherSuites|tlsmlkem|tlskyber|fipsonly' . $(go env GOMODCACHE) | grep -v _test.go
grep -rnE 'GODEBUG|godebug' go.mod go.work Dockerfile* *.yaml *.json *.tf 2>/dev/null
```

**What happens today** (client: Go vs OpenSSL servers; server: Go vs OpenSSL `s_client`; Go 1.24.13 `go 1.24`, 1.25.14, 1.26.11; all Tested):

| Setting | Client to PQ-only server | Client to classical | As a server | Change to |
| --- | --- | --- | --- | --- |
| `CurvePreferences: {X25519, P256}` | Fails: `handshake failure` | X25519 | PQ-only client fails; a hybrid-capable client silently gets X25519 | Remove it, or add `tls.X25519MLKEM768` (and `tls.SecP256r1MLKEM768` on 1.26+) |
| `CurvePreferences: {X25519MLKEM768, X25519, P256}` | X25519MLKEM768 | X25519 | — | Fine. With `tlsmlkem=0` (old `go` line) the hybrid is dropped even from this list on 1.24 to 1.26 |
| `MaxVersion: tls.VersionTLS12` | Fails: `protocol version not supported` | TLS 1.2, X25519 | TLS 1.2 only, never PQ | Remove it: the hybrids exist only in TLS 1.3 |
| `MinVersion: tls.VersionTLS13` | X25519MLKEM768 | X25519 | — | Fine |
| `CipherSuites` (a TLS 1.2 list) | X25519MLKEM768 | X25519 | PQ on TLS 1.3; TLS 1.2 clients limited to the list | Keep: it doesn't touch TLS 1.3 |
| `GODEBUG=tlsmlkem=0` at run time | Fails | X25519 | — | Remove it |
| `GODEBUG=tlsmlkem=1` on a `go 1.22` module | X25519MLKEM768 | X25519 | PQ too | Interim fix until the `go` line moves |
| Go 1.23 with curve 4588 listed by number | Fails even to classical: `tls: CurvePreferences includes unsupported curve` | Fails | — | Upgrade the toolchain |

[MOVED: PQ-only enforcement paragraph + code .9220 .9288]

**Side effects.** Removing `MaxVersion` lets TLS 1.3 through; check peers that pin TLS 1.2 behaviour, such as inspection proxies.

### G. FIPS mode

**Who this is.** `go version -m` shows `GOFIPS140=`, `fips140=on` or `GOEXPERIMENT=boringcrypto`, or the environment sets `GODEBUG=fips140=on|only`.

**What happens today.** See the table: Go 1.24 FIPS and boringcrypto `fipsonly` give no PQ; Go 1.26+ native FIPS offers all three hybrids. The AWS SDK forces classical curves in FIPS mode (case H).

**What to change.** Build with Go 1.26+ and `GOFIPS140=v1.26.0` or `latest`; add the AWS SDK fix.

[MOVED: FIPS paragraph .11543, table .11702, notes .12389 .12732]

### H. Libraries with their own TLS settings

**Who this is.** You pass a `tls.Config` to the AWS SDK, gRPC or a database driver, often to add a private CA or a client certificate.

**What happens today.** All three pass your `tls.Config` through unchanged, PQ included. Tested with Go 1.26.11, a custom config holding the private CA in `RootCAs` and an EC client cert, against a Go observer server (PQ-only, mTLS required, logs the group and client CN), an OpenSSL PQ-only mTLS server and an OpenSSL classical mTLS server:

| Library | How the config was passed | Observer | OpenSSL PQ-only | Classical | Same config + `CurvePreferences {X25519, P256}` | Run with `GODEBUG=tlsmlkem=0` |
| --- | --- | --- | --- | --- | --- | --- |
| aws-sdk-go-v2 v1.48.0, config v1.33.18 | `awshttp.NewBuildableClient().WithTransportOptions(t.TLSClientConfig = cfg)` | X25519MLKEM768, `client_cn=cli-ec` | OK | OK | Fails to PQ-only: config passed through | Fails to PQ-only |
| same | plain `&http.Client{Transport: &http.Transport{TLSClientConfig: cfg}}` via `config.WithHTTPClient` | X25519MLKEM768, `cli-ec` | OK | OK | — | Fails to PQ-only |
| grpc-go v1.85.0 | `credentials.NewTLS(cfg)` | X25519MLKEM768, `cli-ec` | — | — | Fails | Fails |
| grpc-go v1.85.0 | `credentials.NewClientTLSFromFile(ca.pem, name)` | X25519MLKEM768 (no mTLS) | — | — | — | Fails |
| pgx v5.13.0 | `ConnConfig.TLSConfig = cfg`, `sslnegotiation=direct` | X25519MLKEM768, `cli-ec` | OK | OK | Fails | Fails |
| pgx v5.13.0 | DSN `sslrootcert`, `sslcert`, `sslkey` | X25519MLKEM768, `cli-ec` | OK | OK | — | Fails |

pgx was tested only with direct TLS; the default `sslnegotiation=postgres` (TLS after `SSLRequest`) uses the same `tls.Config` but was not run (Unverified). The FIPS-mode curve override in the AWS SDK is the one library default that blocks PQ.

Outside Go's TLS: `confluent-kafka-go` uses librdkafka with its own OpenSSL, and anything you exec (curl, git, wget) uses the image's TLS library. Debian and Ubuntu GnuTLS has no ML-KEM (lead's test, Java tab notes). Neither was tested from Go (Unverified).

[MOVED: per-library paragraphs and code .6593 .6712 .6867 .7312 .7642 .7765 .7921 .7949]

### I. Pinning, and HSM, PKCS#11 or KMS keys

**Who this is.** `VerifyPeerCertificate` or `VerifyConnection` with SPKI hashes; a `tls.Certificate` whose `PrivateKey` is a KMS, CloudHSM or PKCS#11 `crypto.Signer`.

**What happens today.**

- SPKI pinning in `VerifyConnection`: the right pin passed over X25519MLKEM768 and over X25519; a wrong pin failed with your error (Tested 1.24.13, 1.26.11). PQ key exchange doesn't change certificates, so pins stay valid. They change only when you move to ML-DSA certificates.
- A server key behind an opaque `crypto.Signer` (only `Public` and `Sign`, the shape KMS and PKCS#11 wrappers expose), RSA and EC: `Sign` was called once per handshake and X25519MLKEM768 was negotiated (Tested 1.24.13, 1.26.11). The ML-KEM part runs in software in `crypto/tls`; the HSM only signs. A real KMS, CloudHSM or PKCS#11 module was not tested (no AWS access).

**What to change.** Nothing. **Side effects.** None.

### J. Other cases

- **Behind a load balancer.** The front door may own the client-facing handshake (table below).
- **HTTPS_PROXY.** `net/http` tunnels TLS through `CONNECT`, so the Go client's settings still decide, unless the proxy intercepts TLS; then the proxy's stack decides (Unverified; see Network devices and egress).
- **HTTP/2 and gRPC servers.** ALPN `h2` and X25519MLKEM768 work together (Tested, earlier pass).
- **WebSockets** (`gorilla/websocket`, `coder/websocket`) dial through `net/http` or a `tls.Config`; same rules (Unverified).
- **Service mesh sidecar.** If the app talks plaintext to the sidecar, the mesh decides (see Service mesh).

[MOVED: behind-LB paragraph .9716, table .9740, links .10158]

## Solution and automation

1. **Inventory.** Run `go-pq-posture.sh` over every built artifact (Lambda `bootstrap`, files copied out of images, EC2 binaries) and `go-pq-lint.sh` over every repo. Export `GODEBUG` from Lambda configurations, task definitions and pod specs. Use CloudTrail `tlsDetails.keyExchange` for KMS, STS, IAM, Secrets Manager and ACM callers.
2. **Change.** Raise the `go` line to 1.26 and rebuild with Go 1.26+. Remove blocking settings (case F). For FIPS, move to native `GOFIPS140` and apply the AWS SDK fix (cases G, H). Where the `go` line can't move yet, set `GODEBUG=tlsmlkem=1,tlssecpmlkem=1`. Packaging per compute type is below.
3. **CI guardrails.** Fail the build on `go-pq-lint.sh` findings before compiling, then run `go-pq-posture.sh` on the built binary. Both scripts are in Full configuration files. The lint is a file-level heuristic: a file that mentions ML-KEM anywhere passes its `CurvePreferences` check, so review hits by hand.
4. **Fleet rollout.** Clients first: they fall back to X25519, so a client change can't break a classical server. Then servers, which still accept classical clients. PQ-only enforcement comes last, per endpoint, after the logs show no classical clients. Canary one function version, one task set or one Deployment, and watch `tls_group=` logs, handshake errors and p99 latency for a day. Roll back with `GODEBUG=tlsmlkem=0,tlssecpmlkem=0` in the environment (no rebuild).

[MOVED: packaging blocks .12893 to .14235]

## How to test

1. **Posture.** Run `go version -m` on the artifact (table below).
2. **Code scan.** Run `go-pq-lint.sh .`; it must print `go-pq-lint: OK`.
3. **Local harness.** Run `gen-certs.sh` and `pq-servers.sh` in `debian:trixie-slim` (OpenSSL 3.5). They start a PQ-only server on 8443, a classical-only server on 8444, and mTLS versions of both on 8445 and 8446. Run your client against each. It must reach 8443 (PQ) and 8444 (fallback).
4. **Case C (your server and its store).** Start your server with its real cert files or keystore and run:
   `openssl s_client -brief -connect host:port -CAfile ca.pem -groups X25519MLKEM768 -tls1_3` → `Negotiated TLS1.3 group: X25519MLKEM768`; `-groups X25519` → still connects. For several certificates add `-servername <each name>`, and `-sigalgs ecdsa_secp256r1_sha256` or `-sigalgs rsa_pss_rsae_sha256:rsa_pkcs1_sha256` to see each one. For a TLS 1.2 probe of an ECDSA P-256 cert, offer `-groups X25519:P-256`; with X25519 alone OpenSSL fails with `wrong curve`, which is a probe artifact.
5. **Case D.** Point the client at 8443 with your CA setup (`SSL_CERT_FILE`, your pool, `AWS_CA_BUNDLE`); then with no CA, which must fail with `unknown authority`.
6. **Case E.** Client with its cert against 8445 must succeed; without it, it must fail with `certificate required`. Your mTLS server: `s_client ... -cert client.pem -key client.key` must succeed, and the server log must show `client_cn`.
7. **In-cloud signal.** Server `tls_group=` logs and CloudTrail `tlsDetails.keyExchange` (below).
8. **Rollback test.** Restart with `GODEBUG=tlsmlkem=0`: 8443 must now fail and 8444 still work. Remove it, and 8443 works again.

The cases program (`cases/main.go`) and the library program (`deps/main.go`) used for this tab are in Full configuration files; outputs are in `run-v2.out`, `run-v2b.out` and `run-v2c.out`.

[MOVED: Verify blocks .14243 to .16278; observed-signal paragraph + log .9417 .9586]

## Pitfalls and rollback (new bullets added to the existing list)

- **RSA listed before EC.** With `Certificates: {rsa, ec}` default clients get RSA. Not a PQ issue, but surprising during cert migrations (Tested).
- **`x/crypto/pkcs12` can't read OpenSSL 3 default PKCS#12 files.** It fails at start-up with `unknown digest algorithm`; use `go-pkcs12` (Tested).
- **AWS CA bundle with your own `*http.Client`.** `AWS_CA_BUNDLE` or `WithCustomCABundle` then fails at config load (Tested).
- **Go 1.23 isn't "almost PQ".** Its Kyber draft group (0x6399) isn't ML-KEM; standard PQ-only servers refuse it (Tested).
- **mTLS errors move to the first read in TLS 1.3.** A missing client cert shows up as `certificate required` on read, not on dial (Tested).
