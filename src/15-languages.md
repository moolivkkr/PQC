# Solutions by language

Each language chapter that follows is written for the application team that owns the code. It covers every version line, every compute type and every case a team meets (simple clients and servers, existing certificates and keystores, custom CA trust, mutual TLS, explicit TLS settings, FIPS mode, libraries with their own TLS, pinning and HSM keys). The compute-type view of the same fixes is in [Solutions by compute type](#ch-14-compute).

## Languages at a glance

| Language | What decides PQ | Status today | Main action |
| --- | --- | --- | --- |
| Go | Go's own `crypto/tls`: toolchain, `go` line in `go.mod`, `GODEBUG`, `CurvePreferences`, FIPS mode | PQ by default with Go 1.24+ and a `go` line of 1.24+; FIPS needs 1.25+ (1.26+ for the SecP hybrids) | Build with Go 1.26, raise the `go` line, drop explicit `CurvePreferences`; fix the AWS SDK's FIPS curve list |
| Python | stdlib `ssl` follows the platform OpenSSL; some wheels bundle their own TLS | Debian 13 and Alpine images PQ; Lambda and AL2023 need the config; grpcio, awscrt, psycopg binary, pyOpenSSL PQ everywhere | Ship `openssl-pq.cnf` on Lambda/AL2023 or use an OpenSSL 3.5 image; shim or upgrade 3.9 to 3.11 on Lambda |
| Node.js | Node's bundled OpenSSL plus the config file it reads | Official 22.20+ and 24.5+ PQ by default (policy floor 24.9); Lambda bootstrap config removes it; 18 and 20 can't | Override the Lambda config with `openssl-pq-node.cnf`; upgrade 18 and 20 |
| Java | The JSSE provider in the JVM | JDK 25.0.5+ PQ by default (JEP 527 backport); 8 to 21 have no ML-KEM | Move to JDK 25.0.5+, or add Bouncy Castle JSSE (kit v2 agent or `java.security`); servers with EC certificates also need `ssl.KeyManagerFactory.algorithm=PKIX`; tcnative or CRT clients are PQ on any JDK |
| .NET | The OS stack: OpenSSL on Linux, Schannel on Windows; no .NET group API | Alpine and Ubuntu 26.04 images PQ; Lambda and AL2023 need the config; Windows opt-in | Pick a PQ base image or ship `openssl-pq.cnf`; set the Schannel group order on Windows |

## How each language chapter is organised

1. **Problem statement:** what goes wrong today in this language, and who controls the handshake.
2. **Versions and native support:** one row per version line, with PQ defaults per compute type, FIPS behaviour, the fix and an evidence label.
3. **Cases: what to change:** A simple client, B simple server, C existing server certificates, D custom CA trust, E mutual TLS, F explicit TLS settings that block PQ, G FIPS mode, H libraries with their own TLS, I pinning and HSM or KMS keys, J other cases. Each says who it applies to (with a grep), what happens today, what to change (often nothing) and side effects.
4. **Solution and automation:** inventory, the change per compute type, CI guardrails, canary rollout and rollback.
5. **How to test:** posture, a PQ-only and a classical-only test server, a test per case, the in-cloud signal, and the rollback test.
6. **Pitfalls and rollback.**
7. **Configuration files:** links to every complete file in the repository (`configs/<language>/`). The paper keeps only the main change; the files are the source of truth for copying.

## Existing certificates, keystores and trust stores

Most application teams already load their own server certificates, client certificates and private CAs. PQ key exchange does not change certificates, so in almost every case **nothing in the keystore or CA bundle has to change**. Each language tab has a full case list (cases C, D and E), tested with the PQ fix in place. In summary:

| Language | Own server cert or keystore | Own CA trust | Mutual TLS | What can still break |
| --- | --- | --- | --- | --- |
| Go | No change; `tls.LoadX509KeyPair`, `GetCertificate` and SNI work as before (Tested) | No change; `SSL_CERT_FILE` replaces the default bundle rather than adding to it (Tested) | No change (Tested) | `AWS_CA_BUNDLE` with a plain `*http.Client` fails at config load: set `RootCAs` on the SDK's `BuildableClient`. `x/crypto/pkcs12` can't read OpenSSL 3 PKCS#12 files |
| Python | No change; `load_cert_chain` with RSA, EC or encrypted keys works (Tested) | No change for `cafile`, certifi and `REQUESTS_CA_BUNDLE` (Tested) | No change (Tested) | `truststore.inject_into_ssl()` disables the Lambda 3.9–3.11 shim for requests; gunicorn with an encrypted keyfile fails every worker (use an `ssl_context` hook); `set_ecdh_curve` or a TLS 1.2 maximum blocks PQ |
| Node.js | No change for key/cert or modern PFX (Tested) | No change for `ca` and `NODE_EXTRA_CA_CERTS` (Tested) | No change (Tested) | Legacy RC2/3DES PFX files fail on every current runtime: re-export them. The Lambda image has an empty system CA store: set `SSL_CERT_FILE` |
| Java | No change to JKS or PKCS#12 stores (Tested). With the Bouncy Castle agent, EC server certificates need the `PKIX` key manager (below) | No change for `cacerts` or `javax.net.ssl.trustStore` (Tested) | Works with kit v2; kit v1 silently sent no EC client cert (Tested) | Code that hard-codes `KeyManagerFactory.getInstance("SunX509")` or Tomcat `keyManagerAlgorithm="SunX509"`. RSA+EC stores serve EC to default clients |
| .NET | No change for PFX, PEM or `X509Store` (Tested on Linux) | No change for custom validation callbacks and `CustomTrustStore` (Tested) | No change (Tested) | `X509Certificate2.CreateFromPemFile(caPath)` throws on a CA-only file: use `CreateFromPem(File.ReadAllText(path))` |

**Java with the Bouncy Castle agent and an EC server certificate.** Every handshake used to fail. The cause is the key manager, not the certificate: Bouncy Castle asks for key type `EC/secp256r1`, and the JDK default `SunX509` key manager returns no alias for it. The fix is one security property, `ssl.KeyManagerFactory.algorithm=PKIX`, in a file passed with `-Djava.security.properties=<file>` or added to `java.security`. Kit v2's agent sets it and ships `pq-tls.security`. With it, Tomcat 11.0.29, Jetty 12.1.15 and HttpsServer on JDK 17 and 21 negotiate X25519MLKEM768 with an EC certificate, and an X25519-only client still connects (Tested). Spring Boot 3.5.16 SSL bundles use the default algorithm and work. An app's own `-Djava.security.properties` overrides the kit file, so add the line there too. On JDK 25 with the default `SunX509`, the server ignored SNI on a two-certificate store; `PKIX` fixes that as well (Tested).

## Other languages

- **Rust:** rustls with the aws-lc-rs provider supports X25519MLKEM768; sources disagree on which 0.23.x release made it the default (0.23.22 or 0.23.27). The AWS SDK for Rust defaults to PQ for crates published after 2025-08-29 (Documented). Apps on the `openssl` crate follow the system OpenSSL. Not tested here.
- **Ruby, PHP:** follow the system OpenSSL 3.5+, so they should behave like Python with the same config file (Documented in the AWS SDK guide; Lambda Unverified).
