# Test evidence and test cases

Run r1117041043 (2026-11-16), LocalStack Pro end-to-end suite. Each case deploys the runtime and fix on real Lambda, ECS or EC2 resources in LocalStack and connects to a TLS observer; PASS means the observed result matched the expectation in the case file (a baseline that stays classical as documented passes). Not run on real AWS or x86_64.

## Summary

118 client cases and 5 load balancer target cases; 123 passed.

| Compute | Cases | PQ on `hybrid` | Connected to `pqonly` | Runtimes |
| --- | --- | --- | --- | --- |
| Lambda | 77 | 46 | 46 | image, provided.al2, provided.al2023 |
| ECS Fargate | 22 | 14 | 14 | pqc-go:al2 probe-1.23, pqc-go:al2 probe-1.27, pqc-go:al2023 probe-1.23, pqc-go:al2023 probe-1.24, pqc-go:al2023 probe-1.26-boring, pqc-go:al2023 probe-1.26-go1.23, pqc-go:al2023 probe-1.27, pqc-go:al2023-policy probe-1.23 and 12 more |
| ECS on EC2 | 5 | 4 | 4 | pqc-go:al2023 probe-1.23, pqc-go:al2023 probe-1.27, pqc-go:distroless probe-1.24, pqc-go:golang probe-1.26, pqc-go:scratch probe-1.27 |
| EC2 | 14 | 11 | 11 | pqc-al2 probe-1.23, pqc-al2 probe-1.26, pqc-al2 probe-1.27, pqc-al2 probe-distro, pqc-al2023 probe-1.23, pqc-al2023 probe-1.24, pqc-al2023 probe-1.24-go1.23, pqc-al2023 probe-1.25 and 3 more |

**What the cases vary:** no change: the runtime's default (expected classical where the paper says so) (37); FIPS modes (Go FIPS 140-3, boringcrypto, Java and .NET FIPS settings) (19); `GODEBUG=tlsmlkem=1` or a `//go:debug` directive (11); explicit TLS settings that block PQ (case F) (9); custom CA trust (case D) (9); mutual TLS (case E) (6); `go` line in `go.mod` below and above 1.24 (5); the `pq-tls` layer and `AWS_LAMBDA_EXEC_WRAPPER` (4); libraries with their own TLS stack (case H) (4); `update-crypto-policies --set DEFAULT:PQ` (image or host) (4); the `pq-egress` Lambda extension (3); container image variants (3); certificate or key pinning (case I) (2); distro-packaged toolchain or runtime (2).

**ML-DSA:** 113 got ECDSA from the dual server and failed the ML-DSA-only targets; 2 failed every target for reasons unrelated to ML-DSA.

**Load balancer target leg:** 5 servers (ecs-ec2, ecs-fargate); 3 negotiated PQ with the ALB's PQ backend policy (the rest are baselines); 5 of 5 negotiated classical TLS 1.2 with the classic policy.

| Test component | Path |
| --- | --- |
| Case definitions (one entry per case, with its expectation) | [e2e/cases/go.py](REPO/e2e/cases/go.py) |
| Probe deployed in every case | [e2e/clients/go/probe.go](REPO/e2e/clients/go/probe.go) |
| Build and deploy script | [e2e/build/go.sh](REPO/e2e/build/go.sh) |
| Load balancer target server | [e2e/clients/server/go/main.go](REPO/e2e/clients/server/go/main.go) |
| Earlier tests: existing certificates, keystores, libraries (containers) | [tests/deep/go/](REPO/tests/deep/go/) |
| Earlier tests: Lambda base images under the Runtime Interface Emulator | [tests/lambda/goprobe/](REPO/tests/lambda/goprobe/), [tests/lambda/run-dotnet-go.sh](REPO/tests/lambda/run-dotnet-go.sh) |
| Configuration and test harness files from the chapter | [configs/go/](REPO/configs/go/) |

## Every client case

Cells: what the client negotiated with each target (hybrid, PQ-only, mutual TLS, TLS 1.2 only) and the certificate it got from the dual ML-DSA/ECDSA server.

### Lambda (77 cases)

| Case | Runtime | Mode | hybrid | pqonly | mtls | tls12 | ML-DSA dual | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `go-lambda-al2-go123-baseline` | go1.23.12 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2-go123-clientcert-callback` | go1.23.12 | mtls | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2-go123-extension` | go1.23.12 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `go-lambda-al2-go123-pqtls-layer` | go1.23.12 | layer | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2-go124-baseline` | go1.24.13 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2-go124-gofips140` | go1.24.13 | fips | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2-go124-mod123-godebug-gomod` | go1.24.13 | godebug | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2-go124-tlsmlkem0` | go1.24.13 | godebug | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2-go125-baseline` | go1.25.14 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2-go125-mod123` | go1.25.14 | go-line | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2-go126-baseline` | go1.26.11 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2-go126-gofips140-v100` | go1.26.11 | fips | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2-go127-baseline` | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2-go127-trust-ssl-cert-dir` | go1.27.4 | trust | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go123-baseline` | go1.23.12 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go123-combined` | go1.23.12 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `go-lambda-al2023-go123-combined-wrapper` | go1.23.12 | layer | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go123-curve4588` | go1.23.12 | settings | fail | fail | fail | fail | ECDSA | PASS |
| `go-lambda-al2023-go123-extension` | go1.23.12 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `go-lambda-al2023-go123-pqtls-layer` | go1.23.12 | layer | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go123-trust-ssl-cert-file` | go1.23.12 | trust | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go124-baseline` | go1.24.13 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go124-fips140-on` | go1.24.13 | fips | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go124-fips140-only` | go1.24.13 | fips | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go124-mod123` | go1.24.13 | go-line | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go124-mod123-godebug-env` | go1.24.13 | godebug | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go124-trust-ssl-cert-file` | go1.24.13 | trust | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go125-baseline` | go1.25.14 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go125-boring-fipsonly` | go1.25.14 X:boringcrypto | fips | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go125-fips140-on` | go1.25.14 | fips | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go125-fips140-only` | go1.25.14 | fips | fail | fail | fail | fail | fail | PASS |
| `go-lambda-al2023-go126-awssdk` | go1.26.11 | library | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-awssdk-fips` | go1.26.11 | library | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-awssdk-fips-fix` | go1.26.11 | library | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-baseline` | go1.26.11 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-boring` | go1.26.11-X:boringcrypto | fips | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-boring-fipsonly` | go1.26.11-X:boringcrypto | fips | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-ciphers12` | go1.26.11 | settings | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-clientcert-callback` | go1.26.11 | mtls | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-clientcert-env-pem` | go1.26.11 | mtls | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-clientcert-none` | go1.26.11 | mtls | **PQ** | **PQ** | fail | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-curves-classical` | go1.26.11 | settings | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-curves-hybrid` | go1.26.11 | settings | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-curves-hybrid-tlsmlkem0` | go1.26.11 | settings | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-fips140-on` | go1.26.11 | fips | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-fips140-only` | go1.26.11 | fips | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-gofips140-v1260` | go1.26.11 | fips | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-max12` | go1.26.11 | settings | classical 1.2 | fail | classical 1.2 | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-min13` | go1.26.11 | settings | **PQ** | **PQ** | **PQ** | fail | ECDSA | PASS |
| `go-lambda-al2023-go126-mod123` | go1.26.11 | go-line | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-mod123-godebug-env` | go1.26.11 | godebug | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-mod123-godebug-gomod` | go1.26.11 | godebug | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-mod125` | go1.26.11 | go-line | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-p12-sslmate` | go1.26.11 | mtls | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-p12-xcrypto` | go1.26.11 | mtls | **PQ** | **PQ** | fail | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-pin-ca` | go1.26.11 | pinning | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-pin-wrong` | go1.26.11 | pinning | fail | fail | fail | fail | ECDSA | PASS |
| `go-lambda-al2023-go126-rollback` | go1.26.11 | godebug | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-tlssecpmlkem0` | go1.26.11 | godebug | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-trust-empty` | go1.26.11 | trust | fail | fail | fail | fail | ECDSA | PASS |
| `go-lambda-al2023-go126-trust-none` | go1.26.11 | trust | fail | fail | fail | fail | ECDSA | PASS |
| `go-lambda-al2023-go126-trust-ssl-cert-file` | go1.26.11 | trust | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go126-trust-system-plus-ca` | go1.26.11 | trust | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go127-awssdk-tlsmlkem0` | go1.27.4 | library | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go127-baseline` | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go127-boring-fipsonly` | go1.27.4-X:boringcrypto | fips | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go127-curves-hybrid-tlsmlkem0` | go1.27.4 | settings | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go127-fips140-on` | go1.27.4 | fips | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go127-fips140-only` | go1.27.4 | fips | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go127-gofips140` | go1.27.4 | fips | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go127-mlkem1024` | go1.27.4 | settings | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go127-mod123` | go1.27.4 | go-line | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go127-mod123-directive` | go1.27.4 | godebug | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go127-pqtls-layer` | go1.27.4 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-lambda-al2023-go127-tlsmlkem0` | go1.27.4 | godebug | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-image-go123` | go1.23.12 | image | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-lambda-image-go126` | go1.26.11 | image | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |

### ECS Fargate (22 cases)

| Case | Runtime | Mode | hybrid | pqonly | mtls | tls12 | ML-DSA dual | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `go-fargate-al2-go123` | go1.23.12 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-fargate-al2-go127` | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-fargate-al2023-go123` | go1.23.12 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-fargate-al2023-go124` | go1.24.13 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-fargate-al2023-go126-boring-fips140-on` | unknown (crashed: probe-1.26-boring) | fips | fail | fail | fail | fail | fail | PASS |
| `go-fargate-al2023-go126-mod123-taskdef-godebug` | go1.26.11 | godebug | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-fargate-al2023-go127` | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-fargate-al2023-policy-go123` | go1.23.12 | crypto-policy | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-fargate-al2023-policy-go127` | go1.27.4 | crypto-policy | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-fargate-distroless-go123` | go1.23.12 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-fargate-distroless-go124` | go1.24.13 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-fargate-distroless-go127` | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-fargate-doc-dockerfile` | go1.26.11 | image | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-fargate-doc-dockerfile-fips` | go1.26.11 | fips | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-fargate-golang-go123` | go1.23.12 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-fargate-golang-go124` | go1.24.13 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-fargate-golang-go127` | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-fargate-scratch-go123` | go1.23.12 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-fargate-scratch-go124` | go1.24.13 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-fargate-scratch-go127` | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-fargate-scratch-go127-no-bundle` | go1.27.4 | trust | fail | fail | fail | fail | ECDSA | PASS |
| `go-fargate-scratch-go127-ssl-cert-file` | go1.27.4 | trust | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |

### ECS on EC2 (5 cases)

| Case | Runtime | Mode | hybrid | pqonly | mtls | tls12 | ML-DSA dual | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `go-ecsec2-al2023-go123` | go1.23.12 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-ecsec2-al2023-go127` | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-ecsec2-distroless-go124` | go1.24.13 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-ecsec2-golang-go126` | go1.26.11 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-ecsec2-scratch-go127` | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |

### EC2 (14 cases)

| Case | Runtime | Mode | hybrid | pqonly | mtls | tls12 | ML-DSA dual | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `go-ec2-al2-distro-golang` | go1.26.10-X:nodwarf5 | distro-toolchain | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-ec2-al2-go123` | go1.23.12 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-ec2-al2-go126` | go1.26.11 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-ec2-al2-go127` | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-ec2-al2023-distro-golang` | go1.26.10-X:nodwarf5 | distro-toolchain | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-ec2-al2023-go123` | go1.23.12 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-ec2-al2023-go123-host-policy` | go1.23.12 | crypto-policy | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `go-ec2-al2023-go124` | go1.24.13 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-ec2-al2023-go124-mod123-systemd-godebug` | go1.24.13 | godebug | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-ec2-al2023-go125` | go1.25.14 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-ec2-al2023-go126` | go1.26.11 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-ec2-al2023-go127` | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-ec2-al2023-go127-fips140-on` | go1.27.4 | fips | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `go-ec2-al2023-go127-host-policy` | go1.27.4 | crypto-policy | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |

## Load balancer target cases (5)

The workload is the HTTPS server; the observer connects like an ALB with the PQ backend policy (alb-pq) or the classic one (alb-classic).

| Case | Compute | Runtime | Mode | alb-pq | alb-classic | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| `srv-go-ecsec2-go126` | ecs-ec2 | go1.26.11 | baseline | **PQ** | classical 1.2 | PASS |
| `srv-go-fargate-go123` | ecs-fargate | go1.23.12 | baseline | classical | classical 1.2 | PASS |
| `srv-go-fargate-go126` | ecs-fargate | go1.26.11 | baseline | **PQ** | classical 1.2 | PASS |
| `srv-go-fargate-go126-mod123` | ecs-fargate | go1.26.11 | baseline | classical | classical 1.2 | PASS |
| `srv-go-fargate-go126-mod123-godebug` | ecs-fargate | go1.26.11 | godebug | **PQ** | classical 1.2 | PASS |
