# Go

**What decides PQ.** Go's own `crypto/tls` is compiled into the binary, so the OS, base image and Lambda runtime play no part. Three things decide the result: the toolchain version, the `go` line in `go.mod`, and any explicit TLS settings in code. A binary built with Go 1.24+ **and** a `go` line of 1.24+ negotiates X25519MLKEM768 by default on every compute type.

| Compute | PQ today? | What to change |
| --- | --- | --- |
| Lambda (`provided.al2023`, `provided.al2`) | Yes with Go 1.24+ and `go` ≥ 1.24 | Rebuild with Go 1.26, raise the `go` line; or `GODEBUG=tlsmlkem=1` |
| ECS Fargate, ECS on EC2, EKS | Same rule; the base image does not matter | Same |
| EC2 | Same rule | Same; the systemd unit can carry `GODEBUG` |

**What to change, in order**

1. `go version -m <binary>` shows Go 1.23 or older: rebuild with Go 1.26. Nothing else helps (1.23 offers only the pre-standard Kyber draft).
2. The `go` line is below 1.24: raise it to 1.26. If you can't yet, `godebug tlsmlkem=1` in `go.mod` or `GODEBUG=tlsmlkem=1` in the deployment.
3. Code or a library sets `CurvePreferences` or `MaxVersion: tls.VersionTLS12`: add X25519MLKEM768 or remove the setting.
4. FIPS mode: use Go 1.26+ native FIPS 140-3 (1.24 has no PQ in FIPS mode; `fips140=only` on 1.25 fails every handshake). The AWS SDK for Go v2 in FIPS mode forces classical curves: re-add the hybrids with `WithTransportOptions`.

**Certificates and keystores:** no change. Watch two things: `SSL_CERT_FILE` replaces the system bundle rather than adding to it, and `x/crypto/pkcs12` cannot read OpenSSL 3 PKCS#12 files (use `go-pkcs12`). **ML-DSA:** Go 1.23 to 1.27 never negotiate ML-DSA in TLS; they get the ECDSA certificate from a dual-certificate server and fail an ML-DSA-only one.

**Rollback:** `GODEBUG=tlsmlkem=0,tlssecpmlkem=0` in the environment; no rebuild. **Detect:** CloudTrail for AWS calls; Go 1.25+ can log `ConnectionState().CurveID` itself.

**Tested:** 118 client cases (Lambda 77, Fargate 22, ECS on EC2 5, EC2 14) and 5 load balancer target cases, all passing, covering Go 1.23 to 1.27, every `go` line, `GODEBUG`, FIPS modes and the AWS SDK fix.
