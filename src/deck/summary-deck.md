---
title: Post-quantum TLS across languages and infrastructure
subtitle: Detection and remediation summary, 2026-11-14 (end-to-end verified 2026-11-15)
---

# The problem

## Why act now

- Traffic recorded today can be decrypted once a large quantum computer exists ("harvest now, decrypt later").
- The fix is the hybrid key exchange **X25519MLKEM768** in TLS 1.3. It changes only how the session key is agreed.
- **Certificates, keystores and CA bundles do not change** for PQ key exchange (tested with the fix in place: own server certificate, private CA trust, mutual TLS). ML-DSA certificates are a separate, later step.
- A TLS 1.2 connection is always non-PQ.
- Whether a connection is PQ depends on the **client's TLS library** (language runtime and version), not on the compute type.
- Compute type decides how we **see** non-PQ connections and how the fix **ships**.

## How we find non-PQ connections

| Signal | Lambda / Fargate | Containers on EC2, EC2 | Front doors |
|---|---|---|---|
| AWS API calls | CloudTrail `tlsDetails.keyExchange` (KMS, STS, IAM, Secrets Manager, ACM) | Same | n/a |
| Other outbound | Posture only, or an egress sensor | Zeek on VPC Traffic Mirroring | n/a |
| Inbound | Front door logs | Front door logs, mirroring | ALB/NLB logs record key exchange |
| Posture | Runtime, package type, env vars | Image SBOM, OpenSSL/JDK/Go versions | Security policy names |


# Status by language

## Languages at a glance

| Language | PQ by default today | Fix |
|---|---|---|
| Go | 1.24+ with `go` line 1.24+ | Build with 1.26+; drop classical `CurvePreferences` |
| Python | Trixie, Alpine images; not Lambda or AL2023 | `OPENSSL_CONF`; Lambda 3.9–3.11: shim + **idna**, then upgrade |
| Node.js | Official 22.20+, 24.5+; not on Lambda | Config file on Lambda; upgrade official 18/20 |
| Java | JDK 25.0.5+ | Kit v2 on 8–21 (JDK 8: + host-name flag), or JDK 25 |
| .NET | Alpine, Ubuntu 26.04; not Lambda or AL2023 | PQ image, `OPENSSL_CONF` or `pq-tls` layer |

## Existing certificates and keystores

| Language | Stores | Watch out for |
|---|---|---|
| Go | No change | `AWS_CA_BUNDLE` + own `http.Client`; `x/crypto/pkcs12` |
| Python | No change | Encrypted key in gunicorn; `truststore` disables the shim |
| Node.js | No change | Legacy RC2/3DES PFX: re-export |
| Java | No change | EC cert needs `PKIX` key manager; hard-coded `SunX509` |
| .NET | No change | `X509Store` on Lambda needs `HOME=/tmp` |

# Language detail

## Go: what decides PQ

- Go's own `crypto/tls`, compiled into the binary, does the handshake. OpenSSL, the OS crypto policy, the base image and the Lambda runtime play no part, so the answer is the same on every compute type.
- Five inputs decide: the toolchain version, the `go` line in `go.mod` (it sets `DefaultGODEBUG`), `GODEBUG` at run time, `CurvePreferences` or `MaxVersion` in code or a library, and FIPS mode.
- Every failure is silent: the handshake falls back to X25519. Check with `go version -m <binary>`.
- Most common miss: a new toolchain with an old `go` line (Go 1.27 with `go 1.23` stays classical).

## Go: versions and FIPS

| Toolchain | PQ by default | Action |
|---|---|---|
| 1.26, 1.27 | Yes with `go` line 1.24+; SecP256r1MLKEM768 and SecP384r1MLKEM1024 with `go` 1.26+ | **Target:** build with 1.26+ and `go 1.26` |
| 1.25 | Yes with `go` 1.24+ (X25519MLKEM768 only) | Upgrade: no security fixes |
| 1.24 | Yes with `go` 1.24+; classical with `go 1.22`/`1.23` | Upgrade; interim `GODEBUG=tlsmlkem=1` |
| 1.23 and older | No ML-KEM (pre-standard Kyber draft, refused by PQ-only servers) | Rebuild with 1.26 |
| FIPS | 1.26+ `GOFIPS140`: hybrids + P-256, P-384, P-521. Go 1.24 FIPS, boringcrypto `fipsonly`: no PQ. 1.25 `fips140=only`: every handshake fails | Native `GOFIPS140` on 1.26+ |

## Go: shipping the fix

| Compute | Change |
|---|---|
| Lambda zip (`provided.al2023`, `al2`) | Rebuild `bootstrap`; optional `GODEBUG` env var |
| Lambda container image | Builder stage on Go 1.26+ |
| Fargate, ECS, EKS | Rebuild the image; any base, including `scratch` and distroless |
| EC2 | Redeploy the binary; optional `Environment=GODEBUG=` in the unit |

## Go: guardrails, pitfalls and evidence

- Guardrails: `go-pq-lint.sh` on source (classical `CurvePreferences`, TLS 1.2 caps, `fipsonly`), `go-pq-posture.sh` on built binaries.
- Rollback: `GODEBUG=tlsmlkem=0,tlssecpmlkem=0` in the environment, no rebuild.
- `tlsmlkem=0` beats an explicit list on 1.24 to 1.26: don't leave it set "temporarily".
- Certificates: no change. Watch `x/crypto/pkcs12` on OpenSSL 3 PKCS#12 files, and `AWS_CA_BUNDLE` with your own `http.Client`.
- e2e: **118 cases pass** (Lambda 77, Fargate 22, ECS on EC2 5, EC2 14), Go 1.23 to 1.27 on `provided.al2023` and `al2`.

## Python: what decides PQ

- The TLS library each package uses decides, not the Python version. Inventory by library: one process can have both answers.
- **`ssl` family** (requests, urllib3, boto3, httpx, aiohttp, redis-py, uvicorn, gunicorn): the OpenSSL the interpreter links plus its config. PQ needs OpenSSL 3.5+ with ML-KEM in the group list.
- **Bundled-TLS wheels** (grpcio, awscrt, confluent-kafka, psycopg binary, pyOpenSSL): already PQ on every base image tested, Debian 12 included.
- Python 3.15 adds `SSLContext.set_groups()` and `SSLSocket.group()`. `set_ecdh_curve` is not a group API and removes ML-KEM.

## Python: by compute type

| Compute / base | PQ by default | Fix |
|---|---|---|
| Lambda python3.12 to 3.15 (AL2023, OpenSSL 3.5.8) | No: crypto policy omits ML-KEM | Ship `openssl-pq.cnf` + `OPENSSL_CONF`, or the `pq-tls` layer |
| Lambda python3.9 to 3.11 (AL2, OpenSSL 1.1.1) | No | Upgrade to 3.12+. Bridge: shim with pyOpenSSL + cryptography + **idna**, built in each version's image (requests, boto3 only) |
| Containers `-slim-trixie`, `-alpine` | Yes | None |
| Containers bookworm, Ubuntu 24.04 (OpenSSL 3.0) | No | Change the base image |
| AL2023 image or EC2 | No | `DEFAULT:PQ` policy, or `OPENSSL_CONF` per service |
| EC2 Amazon Linux 2 | No | Migrate the host |

## Python: pitfalls and evidence

- Shim without `idna`: every urllib3, requests and boto3 call raises `ModuleNotFoundError`. The 3.11 abi3 wheel fails on 3.9 and 3.10.
- `truststore` disables the shim. `OPENSSL_CONF` is inherited by child processes: merge into an existing file, never `/dev/null`.
- Any TLS 1.2 cap (`maximum_version`, `PROTOCOL_TLSv1_2`) removes PQ. gunicorn with an encrypted key fails every worker: use the `ssl_context` hook.
- Certificates, PKCS#12 and CA bundles: no change. A base-image move resets the OS trust store: re-add the private CA.
- e2e: **59 cases pass** (Lambda 35, Fargate 13, ECS on EC2 3, EC2 8), Python 3.7 (AL2 EC2) and 3.9 to 3.14.

## Node.js: what decides PQ

- The OpenSSL inside `node` (bundled in official builds, the system library in distro builds), then the config file Node reads, then TLS options in code.
- Official 22.20+ and 24.5+ bundle OpenSSL 3.5 and are PQ by default on any OS. Use 24.9+ as the policy floor (matches AWS).
- Lambda `nodejs22.x`/`24.x` are **not** PQ: the bootstrap sets an `OPENSSL_CONF` whose groups omit ML-KEM.
- Decide by `process.versions.openssl`, not the Node major: AL2023 `dnf` nodejs20 links system OpenSSL 3.5.8 and takes the fix.
- Every client library tested (fetch, undici, axios, AWS SDK v3, grpc-js, pg, mysql2, ioredis, kafkajs) inherits Node's defaults.

## Node.js: by runtime and compute

| Runtime | PQ by default | Fix |
|---|---|---|
| Lambda `nodejs22.x`, `nodejs24.x` | No (bootstrap config) | `OPENSSL_CONF=/var/task/pq-tls/openssl-pq-node.cnf`, or the `pq-tls` layer |
| Lambda `nodejs18.x` (OpenSSL 3.1.8), `nodejs20.x` (3.2.6) | No, and no setting helps | Upgrade; interim: `pq-egress` extension over loopback |
| `node:22`, `node:24`, `node:26` images; official tarball on EC2 | Yes | None; run the CI check for pins |
| Official 22.0–22.19, 24.0–24.4, 20, 18 | No (OpenSSL 3.0) | Upgrade to 22.20+ or 24.9+ |
| AL2023 `dnf` nodejs20/22/24 | No until the policy changes | `DEFAULT:PQ`, or `openssl-pq-node-system.cnf` |
| Debian 13, Alpine 3.22 distro Node | Yes | None |

## Node.js: pitfalls and evidence

- Classical `ecdhCurve` or `tls.DEFAULT_ECDH_CURVE`, `maxVersion: 'TLSv1.2'`, `--tls-max-v1.2`: each removes PQ. A PQ-first `ecdhCurve` throws on Node 20 / OpenSSL 3.0.
- A function that already sets `OPENSSL_CONF` (FIPS, custom engine): merge, don't overwrite. The layer leaves it alone.
- Certificates, keys and CA bundles: no change. Legacy RC2/3DES PFX files fail on every Node 17+: re-export.
- A Lambda runtime pinned in Manual update mode could stay below 22.20: check the runtime version ARN (Unverified).
- e2e: **93 cases pass** (Lambda 48, Fargate 28, ECS on EC2 5, EC2 12), Node 18 to 26, including the `pq-egress` extension.

## Java: what decides PQ

- JSSE, the JDK's TLS provider, for almost every library (Apache HttpClient, OkHttp, JDK HttpClient, JDBC, Kafka, Tomcat, Jetty, Spring Boot). The OS and its OpenSSL don't matter.
- **JDK 25.0.5+** offers and prefers X25519MLKEM768 by default, as client and server. 25.0.0 to 25.0.4 do not.
- **JDK 8 to 21** have no ML-KEM: use kit v2 (Bouncy Castle agent + `pq-tls.security`) until the vendor ships PQ.
- Own TLS stacks, already PQ: Netty tcnative-boringssl-static, AWS SDK v2 CRT client 2.35.11+.

## Java: by JDK and compute

| JDK | Fix | Notes |
|---|---|---|
| 25.0.5+ | None: `java25`, `lambda/java:25`, `amazoncorretto:25` | Check for `jdk.tls.namedGroups` pins |
| 11, 17, 21 | Kit v2 in `JAVA_TOOL_OPTIONS`; Lambda: `pq-tls` layer + `AWS_LAMBDA_EXEC_WRAPPER` | Static `java.security` works in containers and EC2, not Lambda |
| 8 | Kit v2 + `assumeOriginalHostName=true` everywhere; + `jdk.tls.client.protocols=TLSv1.3,TLSv1.2` on Lambda | Without the host-name flag every `HttpsURLConnection` handshake fails. The layer adds both |
| FIPS JVM | Don't add the kit | `bc-fips` PQ support not confirmed |

## Java: certificates, pitfalls and evidence

- **EC certificates need the PKIX key manager** under Bouncy Castle: the JDK default `SunX509` returns nothing for `EC/secp256r1`. Kit v2 sets `ssl.KeyManagerFactory.algorithm=PKIX`. Tested on Tomcat 11, Jetty 12 and HttpsServer (JDK 17, 21).
- Kit v1 (agent only) breaks EC server certificates and drops EC client certificates: upgrade to v2 first.
- Hard-coded `SunX509`, `jdk.tls.namedGroups` without ML-KEM, and TLS 1.2 pins all win over the kit. The CI check flags them.
- Append to `JAVA_TOOL_OPTIONS`: APM agents live there. Keystores and truststores don't change.
- e2e: **96 cases pass** (Lambda 57, Fargate 21, ECS on EC2 5, EC2 13), JDK 8 to 25, zip, layer and image.

## .NET: what decides PQ

- .NET has no TLS library of its own. `SslStream` (HttpClient, Kestrel, gRPC, Npgsql, Redis, the AWS SDK) calls OpenSSL on Linux and Schannel on Windows. The OS image decides.
- No .NET API sets key-exchange groups. `OPENSSL_CONF` is honoured. Code can only block PQ, by pinning `SslProtocols.Tls12`.
- Rule of thumb: OpenSSL 3.5+ with ML-KEM in the default group list = PQ. OpenSSL 3.0 to 3.4 = never. AL2023 has 3.5 but its policy omits ML-KEM.
- .NET 8 and 9 left support on 2026-11-10: plan the move to .NET 10. The PQ fix works on 8 meanwhile.

## .NET: by image and compute

| Compute / image | PQ by default | Fix |
|---|---|---|
| Lambda `dotnet8`, `dotnet10`, Native AOT | No (AL2023 policy) | `openssl-pq.cnf` + `OPENSSL_CONF`, or the `pq-tls` layer (dotnet branch) |
| `aspnet:8.0` (Debian 12), `10.0`/`-noble` (Ubuntu 24.04), Azure Linux 3.0 | No (OpenSSL 3.0 / 3.3) | Change `FROM` |
| `8.0-alpine`, `10.0-alpine`, `10.0-resolute`, `-resolute-chiseled` | Yes | None |
| AL2023 image or EC2 | No | `OPENSSL_CONF`, or `DEFAULT:PQ` (`FIPS:PQ` on FIPS hosts) |
| Windows Server 2025, `ltsc2025` | No (disabled by default) | July 2026 update, enable `X25519_MLKEM768` (not tested) |

## .NET: certificates, pitfalls and evidence

- PFX, PEM, encrypted PEM, RSA, EC, SNI, `X509Store`, private CAs, validation callbacks and client certificates all keep working with PQ on.
- `X509Store` on Lambda: set `HOME=/tmp`, because the user's home is read-only and the import fails before any handshake.
- `CreateFromPemFile` on a CA-only file throws. `SslProtocols` or `appsettings` pinned to `Tls12` blocks PQ; `check-dotnet-pq.sh` fails the build on it.
- Rollback: remove `OPENSSL_CONF`, revert `FROM`, or `update-crypto-policies --set DEFAULT`. No certificate to roll back.
- e2e: **71 cases pass** (Lambda 33, Fargate 25, ECS on EC2 6, EC2 7), .NET 8 and 10, zip, AOT and image.

# Verification

## End-to-end verification on LocalStack

- **469 cases, all passing:** 437 client cases (Python, Node.js, Java, .NET and Go on Lambda zip, layer, extension and image, ECS Fargate, ECS on EC2, and EC2 from AL2023 `2023.12.20261109` and AL2 AMIs) plus 32 load balancer target-leg cases.
- **The method:** each workload connects to a TLS observer that records the offered and negotiated groups, and the run is graded against the document's claims.
- **Detection:** a CloudWatch Logs filter and the server-side handshake log both find the classical handshakes.
- **Corrections** (next slide) are in the document and kept as regression cases in `e2e/`.
- **Not covered:** real AWS, x86_64, and the ALB/NLB listener leg (LocalStack's ALB ignores security policies).

## What the end-to-end run corrected

| Area | Was | Now |
|---|---|---|
| Python 3.9–3.11 shim | pyOpenSSL + cryptography | Also **idna**, built in each version's image; without it every request fails |
| Node.js 20 | No setting adds PQ | AL2023 `nodejs20` (system OpenSSL 3.5.8) is PQ with the config |
| Java 8 + kit | Agent + TLS 1.3 flag | Also `assumeOriginalHostName=true`; the layer adds it |
| .NET on Lambda | Layer wrapper counted as a fix | The wrapper had no .NET branch; it now has one |
| .NET `X509Store` | Re-import at start | On Lambda set `HOME=/tmp` first |
| Go FIPS | P-256 only | P-256, P-384 and P-521 are offered |

# Infrastructure

## Infrastructure at a glance

| Component | PQ path |
|---|---|
| ALB, NLB | `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`, later 1.3-only PQ |
| CloudFront | Viewer side PQ by default; origin leg classical |
| API Gateway REST | PQ policy; HTTP/WebSocket and egress have none |
| AWS endpoints | KMS, STS, Secrets Manager, ACM, IAM PQ now |
| Service mesh | Linkerd 2.19+ default; Istio 1.27+ `COMPLIANCE_POLICY=pqc` |
| Hosts | Debian 13 / Ubuntu 26.04 OpenSSL PQ; AL2023 `DEFAULT:PQ` |
| IoT Core | No PQ policy yet |

## ALB and NLB: what turns PQ on

- The **listener security policy** decides, not the certificate. Keep the existing ACM certificate (RSA or ECDSA).
- Set `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`, later the TLS 1.3-only PQ policy. CLI, CloudFormation and CDK default to classical `ELBSecurityPolicy-2016-08`.
- A PQ listener policy makes the load balancer offer ML-KEM to HTTPS targets too: that hop is PQ only when the container has its language fix.
- Verify in ALB connection logs (`tls_keyexchange`). Log the target leg on the target.
- LocalStack's ALB ignores the policy: the listener leg needs real AWS. The container leg is tested (next slide).

## ALB to container: tested on LocalStack

| Container (HTTPS target) | No fix | With the fix | No change needed |
|---|---|---|---|
| Python | AL2023, bookworm: classical | `OPENSSL_CONF`, `DEFAULT:PQ`: PQ | trixie |
| Node.js | `node:20`, AL2023 nodejs22: classical | AL2023 nodejs20/22 + config or policy: PQ | `node:24` |
| Go | 1.23; 1.26 with `go 1.23`: classical | `GODEBUG=tlsmlkem=1`: PQ | 1.26 with `go 1.26` |
| Java | Corretto 8, 21: classical | Kit v2 on 8, 17, 21: PQ | Corretto 25.0.5 |
| .NET | `runtime:8.0`, AL2023: classical | AL2023 + config or policy: PQ | `10.0-alpine`, `10.0-resolute` |
| Non-PQ backend policy | Every target: classical TLS 1.2 | Same | Same |

## Resolved risks

- **GnuTLS tools** (wget, git on Debian/Ubuntu): no ML-KEM in any Debian or Ubuntu GnuTLS yet; they fail against PQ-only servers. Use OpenSSL-linked tools. SSH is already PQ (OpenSSH 10).
- **Security Hub ELB.17** passes six non-PQ policies. Use the org Config rule `pq-tls-elbv2-listener-policy` with a PQ-only list, plus the SCP.
- **Kyverno 1.20** dropped legacy ClusterPolicy: admission checks are written as ValidatingPolicy (CEL).

# Rollout

## How the fix ships

1. **Classify:** posture inventory puts each workload in a matrix row.
2. **Change request:** a bot bumps the shared build template; it ships the pq-tls kit and sets the variable.
3. **Release:** the normal pipeline; guardrails warn, then fail, on missing PQ settings and non-PQ ELB policies.
4. **Verify:** observed signals (CloudTrail, ELB logs, sensors) confirm PQ; shipping is not proof.

Canary first; rollback is removing the variable or file in the next release.

## Open items

- Node.js 18/20 and Python 3.9–3.11 on Lambda: upgrade before AWS block-update dates. Interim: the `pq-egress` extension (Tested in e2e; the app calls it over loopback).
- Lambda and Fargate outbound to non-AWS services: no AWS log shows the group.
- API Gateway egress, CloudFront origin leg, IoT Core: classical by AWS design; record as exceptions.
- IaC, guardrails and the e2e results not yet confirmed on a real AWS account: validate in a sandbox, start in audit mode.
- Untested: Ruby, PHP, Rust, Windows Schannel, HSM/PKCS#11 keys.
