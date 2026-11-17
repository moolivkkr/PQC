# PQC Detection and Remediation by Language and Compute

## Summary

Outbound TLS becomes post-quantum (PQ) only when the client's TLS library offers the hybrid group X25519MLKEM768 in TLS 1.3. Whether it does depends on the language runtime and its crypto library, not on the compute type. Compute type decides two other things: how you can see non-PQ connections, and how the fix ships.

- **Detection** differs by compute type. Lambda and Fargate cannot be packet-mirrored, so they rely on AWS logs and app-side telemetry. Containers on EC2 can also use passive sensors.
- **Remediation** differs by language and version. Some need only a config file, some a Java agent or library shim, and some a runtime or toolchain upgrade.
- **Certificates are a separate, slower track.** ML-KEM key exchange needs no new certificates. ML-DSA certificates and signatures matter first where trust lasts for years (device roots in firmware, code and firmware signing); internal TLS can pilot dual certificates; public HTTPS waits for AWS and browsers (Use cases below).
- **Every change ships through build, package and release.** Configuration changes are released like code here, so the fix rides a shared build template, not per-function edits.

How to read the evidence labels in the tables:

| Label | Meaning |
| --- | --- |
| Tested | Run between 2026-11-12 and 2026-11-16 in AWS Lambda base images under the local Runtime Interface Emulator, in official language and distro container images, or in the LocalStack end-to-end suite (`e2e/`), against a server that accepts only X25519MLKEM768. Not run on real AWS |
| Documented | Stated in vendor documentation, not tested here |
| Claimed | Stated by a vendor or third party as a plan or roadmap item, not yet shipped or confirmed |
| Unverified | Believed true, no source opened or test run; confirm before relying on it |

## Detection: finding non-PQ connections

Use two kinds of signal together: **posture** (what a workload will negotiate, predicted from its runtime, versions and config) and **observed** (what a handshake actually negotiated, from logs or sensors). Posture covers everything you can inventory, including Lambda and Fargate, which can't be packet-mirrored. Observed signals confirm the fix and catch what posture misses, such as libraries that pin their own groups.

### Observed signals by compute type

| Compute type | Calls to AWS APIs | Calls to other services (internal, SaaS, internet) | Inbound traffic | Packet capture possible? |
| --- | --- | --- | --- | --- |
| Lambda | CloudTrail `tlsDetails.keyExchange` per call, for KMS, STS, IAM, Secrets Manager and ACM only; other services log version and cipher (Documented) | No AWS log shows the group. Options: route VPC-attached egress through a sensor appliance, or log from the client library | Front door logs (row below) | No |
| Fargate (ECS or EKS) | CloudTrail `tlsDetails.keyExchange` | Same gap as Lambda; an egress proxy or sensor appliance in the VPC path | Front door logs | No. VPC Traffic Mirroring does not support Fargate (Documented) |
| Containers on EC2 (ECS, EKS, self-managed) and plain EC2 | CloudTrail `tlsDetails.keyExchange` | Zeek 7.2+ on VPC Traffic Mirroring logs the negotiated group in `ssl.log` field `curve`. Node-level eBPF agents are possible but young | Front door logs plus mirroring | Yes, Nitro instance ENIs |
| Front doors: ALB, NLB, CloudFront, API Gateway | n/a | n/a | ALB connection logs and NLB access logs record the key exchange (Documented). CloudFront passes `CloudFront-Viewer-TLS-Details` to the origin, including the key exchange (Documented) | n/a |
| IoT devices on AWS IoT Core | n/a | n/a | IoT Core has no PQ security policy, so every device connection is classical today (Documented). Inventory devices by firmware and TLS library | n/a |

### Posture signals by compute type

| Compute type | Inventory source | What to read |
| --- | --- | --- |
| Lambda | `lambda list-functions` across accounts, or AWS Config | Runtime identifier, `PackageType` (zip or image), `OPENSSL_CONF`, `JAVA_TOOL_OPTIONS`, `GODEBUG`, attached layers. Classify with the matrix in the next section |
| Fargate and EC2 containers | ECR images, task definitions, pod specs; an SBOM per image (Amazon Inspector SBOM export, Unverified) | OS OpenSSL version, Go toolchain and `go.mod` version (`go version -m <binary>`), JDK version, Node version, Python's linked OpenSSL, env vars in the task definition |
| EC2 hosts | SSM Inventory | OS and OpenSSL version, crypto policy (`update-crypto-policies --show`) |
| Front doors | AWS Config | ELB and API Gateway security policy names; Config rule `elbv2-predefined-security-policy-ssl-check` takes an allowlist of PQ policy names |

One rule holds for every row: a TLS 1.2 connection is always non-PQ, so `tlsDetails.tlsVersion` or the logged protocol is enough to flag it.

CloudTrail records `keyExchange` only for KMS, STS, IAM, Secrets Manager, ACM and Payment Cryptography so far; AWS lists it as coming soon for S3, DynamoDB, SQS, SNS, EventBridge, ECR and Direct Connect. Systems Manager isn't on AWS's PQ readiness list at all. Details are on the AWS service endpoints page.

## Remediation matrix: language by compute type

The language and version decide the fix; the compute type decides where the fix lives. On Lambda zip functions AWS owns the OS, so the fix is a config file, agent or shim shipped in the package. In containers you own the base image, so the fix is usually the image's OpenSSL, JDK or toolchain version. Lambda container images follow the container column.

| Language and version | Lambda managed runtime (zip) | Containers you build (Fargate, ECS or EKS on EC2, Lambda images) | Evidence |
| --- | --- | --- | --- |
| Python 3.12, 3.13, 3.14 | Ship `openssl-pq.cnf` in the package and set `OPENSSL_CONF` to it. Keeps the AL2023 crypto policy, adds the PQ group | Debian 13 and Alpine 3.24 (OpenSSL 3.5) are PQ by default; Debian 12, Ubuntu 24.04 and Azure Linux 3.0 are not. On AL2023: `update-crypto-policies --set DEFAULT:PQ` in the Dockerfile, or the same config file. Python 3.15 adds `SSLContext.set_groups()` for code that must pin groups | Tested |
| Python 3.9, 3.10, 3.11 | Runtime runs on AL2 with OpenSSL 1.1.1. Upgrade to 3.12+, or ship the urllib3/botocore shim (covers requests and boto3 only). Libraries that bundle their own TLS (next row) are already PQ here | Not blocked: Python 3.11 on an AL2023 image links OpenSSL 3.5 and works with the config file | Tested |
| Python libraries with bundled TLS: grpcio, awscrt, confluent-kafka, psycopg\[binary\], psycopg2-binary, pyOpenSSL | Nothing beyond a current wheel: PQ on every Python runtime, including 3.9 to 3.11 on AL2. OPENSSL\_CONF does not affect them | Same, on any base image including Debian 12 | Tested (grpcio 1.85.1, awscrt 0.38.1, psycopg 3.3.9) |
| Node.js 22.20+, 24.5+ (policy floor 24.9+, as AWS states) | Ship `openssl-pq-node.cnf` and set `OPENSSL_CONF`. The Lambda bootstrap's own config removes the PQ group, so an override is required. Alternatives: `NODE_OPTIONS=--openssl-config=...`, `OPENSSL_CONF=/dev/null`, or `tls.DEFAULT_ECDH_CURVE` in code | Official `node` images and tarballs: PQ by default (bundled OpenSSL 3.5), unless the image sets `OPENSSL_CONF`. Distro Node follows the system OpenSSL: AL2023 `dnf install nodejs22` stays classical until `DEFAULT:PQ` | Tested (Lambda, images, 24.5.0 and 24.9.0); floor Documented |
| Node.js 18, 20 | No in-process fix: bundled OpenSSL has no ML-KEM. Upgrade the runtime; interim, the `pq-egress` extension (Tested in e2e) | Upgrade Node, or use a distro Node linked to a system OpenSSL 3.5 (Debian 13's Node 20 and AL2023's `dnf install nodejs20` negotiated PQ, the AL2023 one after `DEFAULT:PQ` or `OPENSSL_CONF`). Don't put X25519MLKEM768 first in `ecdhCurve` on the bundled Node 20: it crashes | Tested (Lambda, Debian 13) |
| Java 8, 11, 17, 21 | Ship the Bouncy Castle JSSE agent jar and set `JAVA_TOOL_OPTIONS=-javaagent:...`. Java 8 also needs `-Djdk.tls.client.protocols=TLSv1.3,TLSv1.2` (on Lambda) and `-Dorg.bouncycastle.jsse.client.assumeOriginalHostName=true` (everywhere; the `pq-tls` layer adds both). Servers with an EC certificate also need `ssl.KeyManagerFactory.algorithm=PKIX` (kit v2 sets it) | Same agent, or a static `java.security` BCJSSE entry (17, 21). Without Bouncy Castle: Netty `tcnative-boringssl` 2.0.85, or AWS SDK v2 CRT client (PQ in 2.59.1; CRT bundled with 2.35.10 was classical). Or move to JDK 25.0.5+. Oracle plans backports to 21 and 17 in H1 2027 (Claimed) | Tested on java8.al2023, java8.al2, java11 and java17 (AL2) and java21; the newer java11.al2023 and java17.al2023 runtimes not tested (same JVM, other OS) |
| Java 25 (25.0.5+) | Nothing: Corretto 25.0.5 negotiates PQ by default | Corretto or Temurin 25.0.5+. JEP 527 targets JDK 27 but was backported to 25.0.5 ([Oracle 25.0.5 release notes](https://www.oracle.com/java/technologies/javase/25-0-5-relnotes.html)); other 25 builds need that update | Tested (Lambda java25, Corretto and Temurin 25.0.5); backport Documented |
| Go | Custom runtime (`provided.al2023`): build with Go 1.24+ and a `go` line of 1.24+ in `go.mod`, or set `GODEBUG=tlsmlkem=1` | Same; the base image doesn't matter, Go has its own TLS. FIPS mode: 1.24 no PQ; 1.25 X25519MLKEM768 only (`fips140=only` fails every handshake); 1.26+ adds the SecP hybrids. AWS SDK for Go v2 in FIPS mode forces P-256/384/521: re-add the hybrids with `WithTransportOptions` | Tested 1.23 to 1.26, FIPS modes and the SDK fix |
| .NET 8, 10 | Ship `openssl-pq.cnf` and set `OPENSSL_CONF`; .NET uses the OS OpenSSL 3.5 on Lambda | Linux image with OpenSSL 3.5+ (Debian 13, Alpine, Ubuntu 26.04 `resolute` for .NET 10) or a PQ policy/config. .NET has no TLS group API, so the fix is OS-level only. Windows: Schannel group `x25519_mlkem768`, TLS 1.3 only, opt-in (Documented) | Tested (Lambda dotnet8, dotnet10) |
| Rust | Custom runtime: rebuild with rustls 0.23.x and the aws-lc-rs provider; AWS SDK for Rust crates published after 2025-08-29 default to PQ | Same | Documented (AWS SDK); rustls default version Claimed |
| Ruby, PHP | Follow the system OpenSSL 3.5+; expected to behave like Python with the config file | Same as Python | Documented (AWS SDK guide); Lambda Unverified |

Alternatives that change code or dependencies, for teams already editing a service:

- **AWS SDK for Java v2:** the AWS CRT HTTP client negotiates PQ by default from 2.35.11, for AWS API calls only (Documented). Pin a tested version: 2.59.1 was PQ here, while the CRT shipped with 2.35.10 stayed classical (Tested).
- **Any language:** explicitly configured group lists (Go `CurvePreferences`, Java `jdk.tls.namedGroups`, nginx `ssl_ecdh_curve`, Envoy `ecdh_curves`) silently stay classical until X25519MLKEM768 is added (Documented).
- **Debian 13 and Ubuntu 26.04 hosts and images:** "PQ by default" covers programs linked to OpenSSL only. GnuTLS programs, such as `wget` and `git` over HTTPS (libcurl-gnutls), stay classical (Tested). GnuTLS has no ML-KEM group on Debian 13 (3.8.9), Debian 14 "forky" (3.8.13) or Ubuntu 26.04 (3.8.12); Fedora's 3.8.13 build lists five. Against a PQ-only server, Debian git fails with "GnuTLS, handshake failed", while Alpine git (libcurl on OpenSSL) connects. OpenSSH 10 defaults to `mlkem768x25519-sha256` on all of them (Tested). Fix: use OpenSSL-linked tools (curl, Alpine or Fedora images) where the traffic matters, and count GnuTLS tools in posture.

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

## Use cases: key exchange and certificates

Two separate algorithms. **ML-KEM (FIPS 203) protects key exchange**: it stops traffic recorded today from being decrypted later, so it is urgent for every TLS connection, and it needs no new certificates. **ML-DSA (FIPS 204) protects certificates and signatures**: a forged signature only matters once a quantum computer exists, so it is urgent only where a signature or trust anchor must stay trusted for many years (device roots in firmware, code and firmware signing). ML-KEM cannot sign, so there is no "ML-KEM certificate".

"Hybrid" means different things on each side. For key exchange it is one group (X25519MLKEM768) that combines both algorithms, and it is what AWS, browsers and Go use. For TLS certificates, the deployable form today is a **dual certificate**: the server holds an ECDSA and an ML-DSA certificate and sends the one the client asks for (Tested, nginx and the e2e fixture). Composite ML-DSA certificates (one certificate, both algorithms) are standardized for X.509 by IETF LAMPS, but their TLS code points are still TBD in draft-ietf-tls-composite-mldsa-00 (October 2026), so no TLS stack negotiates them yet (Documented).

| Use case | Key exchange (ML-KEM) | Certificate (ML-DSA) | Evidence | Risk and what to do |
| --- | --- | --- | --- | --- |
| **Public HTTPS** (browsers, partners, public APIs) | Hybrid X25519MLKEM768 at the ALB, NLB or CloudFront with a PQ security policy | Not possible today. ACM, ALB, NLB, CloudFront and API Gateway serve RSA or ECDSA only; browsers do not negotiate ML-DSA server certificates, and Chrome plans Merkle Tree Certificates rather than ML-DSA X.509 | Key exchange Tested (e2e LB cases) and Documented; certificate Documented | Keep ECDSA certificates. Revisit when browsers and AWS certificate services ship a PQ format |
| **Internal HTTPS** (service to service, private CA) | Hybrid X25519MLKEM768 in every language and compute type (this document) | Dual certificate from a private CA (AWS Private CA issues ML-DSA). Clients on OpenSSL 3.5 get ML-DSA; Go and Java verify ML-DSA chains but negotiate ECDSA; OpenSSL 3.0 gets ECDSA. On AL2023 the crypto policy blocks ML-DSA until `DEFAULT:PQ` is set or `SignatureAlgorithms` is extended (`configs/certificates-ml-dsa/openssl-pq-mldsa.cnf`); our ML-KEM file alone does not | Tested (e2e targets `mldsa-dual`, `mldsa-only`; per-stack table below) | Pilot only. Never serve ML-DSA alone while any client is on Go, Java, OpenSSL 3.0 or an unmodified AL2023 policy: they fail the handshake. Chains grow from about 0.9 KB to 11.8 KB |
| **Workload identity and mTLS** (client certificates, IAM Roles Anywhere, mesh) | Same as internal HTTPS | Client certificates: tested per language with an ML-DSA client key (`mldsa-mtls`): works on OpenSSL 3.5 stacks with .NET 10, not .NET 8, Go or Java. IAM Roles Anywhere accepts ML-DSA trust anchors and end-entity certificates (AWS, February/March 2026). SPIRE and Envoy/BoringSSL: no upstream ML-DSA certificate support found | Client side Tested; Roles Anywhere Documented; SPIRE and Envoy Unverified (not found) | Roles Anywhere can pilot ML-DSA now with a Private CA trust anchor. Mesh and SPIFFE identities stay ECDSA until upstream support lands |
| **User certificates** (Windows logon, VPN, Wi-Fi, S/MIME) | Windows Schannel hybrid ML-KEM (July 2026 update); VPN and Wi-Fi depend on the vendor | AD CS on Windows Server 2025 issues ML-DSA (May 2026 update), with client-authentication templates for Windows 11 24H2/25H2. Microsoft calls Schannel ML-DSA a pilot, "not for production" (2026-10-08). Smart card logon: not confirmed. S/MIME: RFC 9882 defines ML-DSA in CMS; mail client support not found | Documented (Microsoft); smart card and S/MIME clients Unverified | Build a separate ML-DSA test CA (AD CS cannot convert an existing CA). Keep production user certificates ECDSA or RSA |
| **Device and IoT certificates** | AWS IoT Core has no PQ policy; device legs stay classical (see IoT tab) | AWS IoT Core documents RSA and ECDSA device certificates only; no ML-DSA support found. Devices that ship a root in firmware for 10+ years need a PQ root before they ship | IoT Core Documented (no PQ); ML-DSA Unverified | **Plan now** for long-lived devices: put an ML-DSA root (alongside the ECDSA root) in new firmware and choose TLS stacks that can verify ML-DSA (OpenSSL 3.5, wolfSSL 5.8+) |
| **Code and firmware signing** | Not TLS | AWS KMS has ML-DSA keys (ML_DSA_44/65/87) and AWS Private CA issues ML-DSA code-signing certificates. AWS Signer (Lambda zips and container images) is ECDSA only | Documented (AWS) | **Plan now** for firmware and artifacts verified for years: sign with ML-DSA from KMS in the pipeline next to the existing signature; keep AWS Signer for Lambda code-signing config |
| **SSH** (hosts, users, bastions) | `mlkem768x25519-sha256` is the default in OpenSSH 10 (Tested) | OpenSSH 10.6 (2026-10-06) added the hybrid `ssh-mldsa44-ed25519` key type; 10.6p2 allows it as a CA signature algorithm. Older OpenSSH cannot use these keys | Key exchange Tested; ML-DSA keys Documented (release notes), not tested here | Upgrade OpenSSH for key exchange now. Pilot ML-DSA host and user keys only where every client is 10.6+ |
| **AWS API calls** (SDK to AWS endpoints) | Hybrid ML-KEM per language (this document) | AWS's own certificates; nothing for us to change | Tested | None beyond the key-exchange fix |

**ML-DSA per language** (e2e, three targets on one fixture: `mldsa-dual` = dual certificate, `mldsa-only` = ML-DSA certificate only, `mldsa-mtls` = ML-DSA client certificate required). 

Run r1117034807 (2026-11-16): 409 client cases across Lambda, ECS Fargate, ECS on EC2 and EC2. 91 got ML-DSA on all three targets, 4 (.NET 8) on two, 307 got the ECDSA certificate from the dual server and failed the other two, and 7 failed every target for unrelated reasons (FIPS-only Go, a boringcrypto panic, Java 8 without the host-name flag, the shim without idna). Expectations per case: `e2e/cases/mldsa_rules.py`.

| Client stack | Dual server gives | ML-DSA only | ML-DSA client certificate | Evidence |
| --- | --- | --- | --- | --- |
| Node.js with bundled OpenSSL 3.5: Lambda `nodejs22.x` and `nodejs24.x` (with or without our fix), official images and binaries 22.20+ and 24.5+ | ML-DSA | Connects | Works | Tested (e2e) |
| Python, Node.js, .NET 10 on a distro OpenSSL 3.5: Debian 13, Alpine, Ubuntu 26.04 | ML-DSA | Connects | Works | Tested (e2e) |
| .NET 8 on any OpenSSL 3.5 base | ML-DSA | Connects | **Fails**: .NET 8 cannot load an ML-DSA private key ("not a known key algorithm"); .NET 10 can | Tested (e2e) |
| Amazon Linux 2023, default crypto policy: Lambda `python3.12`–`3.14`, `dotnet8`, `dotnet10`; AL2023 images and hosts | ECDSA | Fails | Fails | Tested (e2e) |
| AL2023 with our ML-KEM file `openssl-pq.cnf` (Python, .NET; it includes the policy's signature list) | ECDSA | Fails | Fails | Tested (e2e) |
| AL2023 with `openssl-pq-mldsa.cnf` | ML-DSA | Connects | Works | Tested (Python 3.12, outside the suite) |
| AL2023 with `update-crypto-policies --set DEFAULT:PQ` (image or host) | ML-DSA | Connects | Works (.NET 8: fails, as above) | Tested (e2e) |
| AL2023 Node.js from dnf with `openssl-pq-node-system.cnf` | ML-DSA | Connects | Works | Tested (e2e) |
| Lambda `python3.9`–`3.11` with the pq-tls shim or layer (requests goes through pyOpenSSL, whose wheel bundles OpenSSL 3.5) | ML-DSA | Connects | Works | Tested (e2e); stdlib `ssl` on the same runtime stays ECDSA |
| OpenSSL 1.0.2, 1.1.1, 3.0 to 3.4: Node 18 and 20, Node 22.19 and 24.4, Debian 12, Ubuntu 24.04, Azure Linux 3.0, Amazon Linux 2 | ECDSA | Fails | Fails | Tested (e2e) |
| Go 1.23 to 1.27 (every compute type and FIPS mode that connects) | ECDSA | Fails | Fails | Tested (e2e); Go 1.27 verifies ML-DSA chains offline but crypto/tls does not negotiate ML-DSA |
| Java 8 to 25, SunJSSE and Bouncy Castle JSSE (kit v1 and v2) | ECDSA | Fails | Fails | Tested (e2e); JDK 25 PKIX validates ML-DSA chains offline |
| Any stack capped at TLS 1.2 (`--tls-max-v1.2`, `EnabledSslProtocols=Tls12`) | ECDSA | Fails | Fails | Tested (e2e); ML-DSA is TLS 1.3 only |

**Trust bundles.** Every ML-DSA target used a bundle holding both the classical and the ML-DSA root (`ca-both.crt`, `truststore-both.p12` for Java). All 402 clients that connect at all connected to the dual server, including OpenSSL 1.0.2, 1.1.1 and 3.0, Go 1.23 to 1.25 (which cannot parse ML-DSA) and Java 8 (Tested). So the ML-DSA root can be distributed ahead of any ML-DSA server certificate.

Step-by-step instructions per language and component: Runbook by language

Load balancers, edge, AWS endpoints, network devices, IoT, mesh, databases, hosts and certificates: Infrastructure and services. Also under it: WAF, Web servers and proxies (nginx, Apache httpd, HAProxy, Envoy as servers) and Mobile, desktop and CLI clients.

SCPs, Config rules, admission policies and CI checks that keep new work PQ: Enforcement and guardrails. Every configuration file in the doc, by side and component: Configuration file index.

## Per-language detail

Each entry gives the exact setting, what it covers, and how to check it worked. Lambda results for the AL2023 runtimes come from the AL2023.12.20261109 base images; python3.9 to 3.11, nodejs18.x, java8.al2, java11, java17 and provided.al2 run on Amazon Linux 2.

### Python and .NET (system OpenSSL)

Both use the operating system's OpenSSL, so one config file serves both. It loads the AL2023 crypto policy and replaces only the group list:

```
openssl_conf = openssl_init
.include /etc/pki/tls/openssl.d
[openssl_init]
providers = provider_sect
ssl_conf = ssl_module
[provider_sect]
default = default_sect
[default_sect]
activate = 1
[ssl_module]
system_default = pq_system_default
[pq_system_default]
.include = /etc/crypto-policies/back-ends/opensslcnf.config
Groups = *X25519MLKEM768:*X25519:secp256r1:X448:secp521r1:secp384r1:ffdhe2048:ffdhe3072:ffdhe4096:ffdhe6144:ffdhe8192
```

- **Set:** `OPENSSL_CONF=/var/task/pq-tls/openssl-pq.cnf`.
- **Baseline check:** with this file, Python 3.12's minimum TLS version, cipher list and options were identical to the default. `OPENSSL_CONF=/dev/null` also enables PQ but drops the crypto policy and changed the cipher list, so don't use it.
- **Python 3.9 to 3.11 on Lambda** (AL2, OpenSSL 1.1.1): a `sitecustomize.py` shim patches urllib3 and botocore to use pyOpenSSL, whose bundled OpenSSL offers PQ. Set `PYTHONPATH` to the shim's directory. It covers `requests` and `boto3`, not `ssl`, `http.client`, aiohttp or httpx. It overrides a deliberate botocore choice; it was tested with certificate verification on against a private CA, including mutual TLS (e2e `py-lambda-py39/310/311-*`), but not against real AWS endpoints, so treat it as a bridge until the runtime upgrade. Build pyOpenSSL, cryptography **and idna** inside each Python version's Lambda image: without idna every request fails.
- **`pq-egress` Lambda extension** (interim, Tested in the LocalStack e2e suite on every Lambda runtime: Python 3.9-3.14, Node 18-24, Java 8-25, dotnet8/10, Go 1.23 on `provided.al2023`/`al2`): an external extension that makes the outbound TLS connection with X25519MLKEM768 for a function whose runtime can't. The function sends plain HTTP to `http://127.0.0.1:2779/<route>/<path>` (routes in `PQ_EGRESS_ROUTES`, optional client certificate per route), so the app's base URL changes; the loopback hop never leaves the execution environment. Same pattern as the AWS Parameters and Secrets Lambda Extension. Source: `e2e/lambda/extension/pq-egress/`. Not tested for AWS SDK calls (SigV4 signs the host name) or on real AWS.

### Node.js (bundled OpenSSL)

Node compiles in its own OpenSSL; 22.20+ and 24.5+ ship 3.5 (use 24.9+ as the policy floor, as AWS does). On Lambda the bootstrap sets `OPENSSL_CONF=/var/runtime/openssl_conf/openssl.cnf`, whose only setting is a group list without ML-KEM. The override is the same file with the PQ group added:

```
nodejs_conf = openssl_init
[openssl_init]
ssl_conf = ssl_sect
[ssl_sect]
system_default = system_default_sect
[system_default_sect]
Groups = *X25519MLKEM768:*X25519:secp256r1:X448:secp521r1:secp384r1:ffdhe2048:ffdhe3072:ffdhe4096:ffdhe6144:ffdhe8192
```

- **Set:** `OPENSSL_CONF=/var/task/pq-tls/openssl-pq-node.cnf`.
- **Watch for drift:** this file replaces AWS's rather than including it. Add a pipeline check that diffs AWS's file against ours, minus the PQ group.
- **Node 18 and 20:** bundled OpenSSL is older than 3.5. No setting helps; upgrade.

### Java (JSSE, independent of the OS)

Java's TLS stack doesn't use OpenSSL, so moving to AL2023 changes nothing for Java. JDKs before 25 have no ML-KEM groups.

- **Java 8 to 21:** a Java agent (`pq-tls-agent.jar`, compiled for Java 8) registers Bouncy Castle 1.87 as the first JSSE provider and sets `jdk.tls.namedGroups=X25519MLKEM768,x25519,secp256r1,secp384r1` unless already set. Set `JAVA_TOOL_OPTIONS=-javaagent:/var/task/pq-tls/pq-tls-agent.jar`.
- **Java 8 only:** also add `-Djdk.tls.client.protocols=TLSv1.3,TLSv1.2`, since the Lambda Java 8 runtime limits clients to TLS 1.2, and `-Dorg.bouncycastle.jsse.client.assumeOriginalHostName=true`, without which Bouncy Castle rejects every `HttpsURLConnection` handshake ("No hostname specified for HTTPS endpoint ID check").
- **Why an agent:** the Lambda Java bootstrap's system classpath is `/var/runtime/lib` only, so providers registered through `java.security` from other paths are silently ignored.
- **Risk:** Bouncy Castle becomes the TLS provider for the whole process. Test functions that use custom keystores, FIPS mode or mutual TLS first.
- **Servers with an EC certificate:** also set `ssl.KeyManagerFactory.algorithm=PKIX` (kit v2's `pq-tls.security`, passed with `-Djava.security.properties=`). Without it every handshake fails. See "Existing certificates, keystores and trust stores" above.
- **Java 25:** Corretto 25.0.5 negotiates PQ with the stock SunJSSE provider.

### Go (own TLS stack)

- **Needs both:** a Go 1.24+ toolchain and a `go` directive of 1.24+ in `go.mod`. A 1.25 build of a module whose `go.mod` says 1.23 stayed classical in testing.
- **No-code override:** `GODEBUG=tlsmlkem=1` turned that build PQ, and can be set in the deployment config.
- **Pitfall:** code that sets `tls.Config.CurvePreferences` gets no PQ.

### Rust

rustls with the aws-lc-rs provider supports X25519MLKEM768. Sources disagree on which 0.23.x release made it the default (0.23.22 or 0.23.27). The AWS SDK for Rust defaults to PQ for crates published after 2025-08-29. Rebuild with current crates; apps on the `openssl` crate follow the system OpenSSL instead.

## Inbound: front doors and TLS 1.3 enforcement

Inbound connections become PQ when the front door's TLS policy offers ML-KEM and the caller supports it. Allow TLS 1.2 and 1.3 first, measure, then move each endpoint to TLS 1.3 only once its TLS 1.2 traffic reaches zero. TLS negotiation already picks 1.3 when both sides support it, and TLS 1.3's downgrade protection stops an attacker forcing 1.2.

| Front door | PQ setting | Notes | Evidence |
| --- | --- | --- | --- |
| ALB, NLB | `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09` (allows 1.2 and 1.3), later `ELBSecurityPolicy-TLS13-1-3-PQ-2025-09` (1.3 only); FIPS variants exist | Console default is a PQ policy, but CLI, CloudFormation and CDK default to `ELBSecurityPolicy-2016-08`. The backend leg also becomes PQ-capable: AWS then uses `ELBSecurityPolicy-TLS13-1-0-PQ-2025-09` towards HTTPS targets, and the hop is PQ only when the target has its language fix (e2e target-leg cases, 2026-11-15; LocalStack can't test the listener leg itself). Enforce in an SCP with the `elasticloadbalancing:SecurityPolicy` condition key, which applies to CreateListener and ModifyListener (not CreateLoadBalancer) | Documented |
| CloudFront | Viewer side PQ by default on all policies | Origin leg is classical; AWS says PQ is coming | Documented |
| API Gateway REST (Regional, private) | `SecurityPolicy_TLS13_1_2_PQ_2025_09` and variants | No TLS 1.3-only PQ policy exists. API Gateway egress to integrations is TLS 1.2 only, so that leg can never be PQ | Documented |
| API Gateway HTTP, WebSocket, edge-optimized | No PQ policy | Front with CloudFront or ALB if PQ is required | Documented (absence) |
| AWS IoT Core | No PQ policy | Every device leg classical until AWS adds one | Documented (absence) |
| Service mesh (EKS) | Linkerd 2.19+ PQ by default; Istio 1.27+ `COMPLIANCE_POLICY=pqc` (enforces PQ, breaks non-PQ peers) | Covers mesh-owned legs only, not app-originated TLS | Documented |

Move legacy callers that can't do TLS 1.3 to a separate listener or hostname that still allows 1.2, tracked as exceptions, rather than holding the main endpoint open for them. The SCP and Config rules that hold this line are on the Enforcement and guardrails tab. Check exact policy names with `aws elbv2 describe-ssl-policies` before putting them in templates.

## Rollout through build, package and release

Every change, including configuration, ships as a release here. So the fix lives in the shared build template, and each workload picks it up on its next release with no per-service code edits.

The loop has four steps, repeated every release cycle: Classify → Change request → Release → Verify.

The release step is the only one that changes a workload; the others are automation around it.

1. **Classify.** The posture inventory sorts each workload into a matrix row and records the gap.
2. **Change request.** A bot opens a pull request in each repo that bumps the shared module or template. The template ships the right files under `/var/task/pq-tls/` (config file, agent jar or shim) and sets the matching variable. It leaves a workload's own `OPENSSL_CONF` alone and flags it for review. Bundling into the package avoids Lambda's 5-layer limit.
3. **Release.** The normal pipeline builds, packages and releases. A guardrail (cfn-guard, OPA/conftest or a CloudFormation Hook) warns, then later fails, on Lambda and task definitions missing the PQ settings, and on non-PQ ELB policies.
4. **Verify.** Observed signals confirm the workload's connections moved to PQ; shipping isn't proof. CLM tracks each workload as a campaign item.

Dormant workloads with no release coming: rank them by observed classical traffic. One making no classical outbound TLS doesn't need forcing; the rest get a no-op rebuild and release. Runtimes past AWS's block-update date can't be changed at all, so schedule those first.

## Gaps, risks and open items

| Item | Impact | Next step |
| --- | --- | --- |
| Node.js 18 and 20 on Lambda | No in-process fix short of a runtime upgrade. Interim: the `pq-egress` extension (Tested in e2e; the app calls it over loopback) | Schedule upgrades to nodejs22 or 24; use the extension only for the calls that must be PQ before then |
| Runtime deprecation dates | After block-update, no config change or layer can be applied. AWS's runtime page (read 2026-11-16): nodejs18.x, nodejs20.x, python3.9, python3.10, provided.al2 and dotnet8 are already deprecated, with function create blocked from 2027-07-29 and update from 2027-08-31; python3.11, java8.al2, java11 and java17 (AL2) deprecate 2027-06-30 with the same block dates. Dates are AWS forecasts and can move (Documented) | Move these workloads first, and finish before 2027-08-31; re-read the AWS runtimes page each quarter |
| Python 3.9 to 3.11 shim | Covers requests and boto3 only; overrides a botocore design choice; needs idna in the package. Tested with verification on against a private CA and mTLS (e2e), not against real AWS endpoints | Test against real AWS endpoints; prefer the runtime upgrade |
| Bouncy Castle agent on Java 8 to 21 | Replaces the TLS provider process-wide | Test FIPS, custom keystore and mutual TLS functions before rollout |
| Bouncy Castle JSSE as a server with an EC (P-256) certificate | **Resolved.** The JDK default `SunX509` key manager returns no alias for Bouncy Castle's `EC/secp256r1` key type. `ssl.KeyManagerFactory.algorithm=PKIX` fixes it (Tested: Tomcat, Jetty, HttpsServer on JDK 17 and 21). Code that hard-codes `SunX509` still fails | Ship kit v2; CI check `java-pq-check.sh` flags hard-coded `SunX509`; test servers with their real keystore. RSA+EC stores start serving EC, so check clients that pin the RSA certificate |
| IaC and guardrail files not deployed | Terraform, CloudFormation, SAM, SCP, Config and policy files follow AWS docs but were not applied to an AWS account (no access here) | Plan or validate each in a sandbox account first; start SCPs and policies in audit mode |
| GnuTLS programs on Debian 13 and 14, and Ubuntu 26.04 | wget and git over HTTPS stay classical although the OS is "PQ by default"; they fail outright against a PQ-only server. No Debian or Ubuntu GnuTLS release has ML-KEM yet (Fedora's does) | Count them in posture; use OpenSSL-linked curl or Alpine/Fedora-based tool images where the traffic matters; SSH is already PQ (OpenSSH 10) |
| Security Hub control ELB.17 | Passes six non-PQ policies (for example `ELBSecurityPolicy-TLS13-1-3-2021-06`, the FIPS-2023-04 and RFC9151 policies), so a green ELB.17 does not mean PQ (Documented) | Deploy the org Config rule `pq-tls-elbv2-listener-policy` with a PQ-only `sslPolicies` list, plus the SCP (Enforcement and guardrails tab) |
| Lambda and Fargate outbound to non-AWS services | No AWS log records the negotiated group | Rely on posture; add an egress sensor where the traffic matters |
| AWS IoT Core | No PQ policy; device legs stay classical | Track AWS roadmap; new devices choose wolfSSL 5.8+ or OpenSSL 3.5 |
| API Gateway egress, CloudFront origin leg | Classical by AWS design today | Accept and record as exceptions |
| Node config drift | Our Node file replaces AWS's | Pipeline diff check against each new runtime image |
| ML-DSA certificates | Public HTTPS cannot use ML-DSA (ACM, ELB, CloudFront, browsers); Go and Java do not negotiate it; AL2023 needs `SignatureAlgorithms` as well as Groups; chains grow 0.9 KB to 11.8 KB | Dual certificates only; certificate track in the rollout plan; recheck AWS and browser support each quarter |
| Untested rows | Ruby, PHP, Rust and non-Corretto/Temurin JDK 25 builds are Documented or Unverified. Also not confirmed: which AWS SDK for Go v2 release added the FIPS curve list, AWS Network Firewall TLS-inspection PQ legs, the RDS enable setting for MySQL PQ groups, and Oracle's 17/21 backport dates | Add them to the emulator test matrix |

## Evidence and sources

**Tests (2026-11-12).** AWS Lambda base images under the Runtime Interface Emulator, against a Node 24 test server with one port accepting only X25519MLKEM768 and one accepting only X25519. Images: python 3.9 to 3.14, nodejs 18 to 24, java 8.al2023, 11, 17, 21, 25, dotnet 8 and 10, provided.al2023 with Go 1.23 to 1.25. Scripts and files are kept with the pq-tls test kit.

**Tests (2026-11-15), end to end.** 469 cases in LocalStack Pro (`e2e/`): real Lambda zip, layer, extension and image functions, ECS Fargate and ECS on EC2 tasks, and EC2 instances from AL2023 and AL2 AMIs, for all five languages, each graded against this document by a TLS observer, plus 32 load balancer target-leg cases. Results: `e2e/results/latest/summary.md`. Real AWS, x86_64 and the ALB/NLB listener leg were not covered.

**Tests (2026-11-13 and 2026-11-14).** Existing-certificate cases (own keystores and key files, private CA trust, mutual TLS, explicit TLS settings) for all five languages, in official language and distro images (Debian 12, 13 and 14, Ubuntu 26.04, Alpine, AL2023, Fedora) against OpenSSL 3.5 `s_server` instances that accept only X25519MLKEM768 or only X25519. The Bouncy Castle EC server fix was tested on Tomcat 11.0.29, Jetty 12.1.15 and HttpsServer, JDK 17, 21 and 25. Each language tab lists its scripts and results.

**Documentation:**

- AWS: [IAM Roles Anywhere post-quantum certificates](https://aws.amazon.com/about-aws/whats-new/2026/03/iam-roles-anywhere-post-quantum-digital-certificates)
- AWS: [AWS Private CA post-quantum certificates](https://aws.amazon.com/about-aws/whats-new/2025/11/aws-private-ca-post-quantum-digital-certificates)
- AWS: [ML-DSA keys in AWS KMS](https://docs.aws.amazon.com/kms/latest/developerguide/mldsa.html)
- AWS: [ML-DSA code signing with AWS Private CA and KMS](https://aws.amazon.com/blogs/security/post-quantum-ml-dsa-code-signing-with-aws-private-ca-and-aws-kms)
- AWS: [AWS Signer platforms (ECDSA)](https://docs.aws.amazon.com/govcloud-us/latest/UserGuide/govcloud-Signer.html)
- AWS: [IoT Core X.509 client certificates](https://docs.aws.amazon.com/iot/latest/developerguide/x509-client-certs)
- Microsoft: [Post-quantum authentication: start testing certificate ecosystems (2026-10-08)](https://microsoft.com/en-us/security/blog/2026/10/08/post-quantum-authentication-why-organizations-should-start-testing-certificate-ecosystems-now)
- Microsoft: [ML-DSA in AD CS](https://learn.microsoft.com/windows-server/identity/ad-cs/ml-dsa-overview)
- OpenSSH: [Release notes (10.6, ssh-mldsa44-ed25519)](https://www.openssh.org/releasenotes.html)
- IETF: [RFC 9882, ML-DSA in CMS](https://www.rfc-editor.org/rfc/rfc9882.html); [draft-ietf-tls-composite-mldsa-00](https://www.ietf.org/archive/id/draft-ietf-tls-composite-mldsa-00.html)
- Apple: [Quantum-secure cryptography in Apple devices](https://support.apple.com/guide/security/quantum-secure-cryptography-apple-devices-secc7c82e533/web)

- AWS: [PQ readiness for AWS services](https://aws.amazon.com/security/post-quantum-cryptography/aws-pq-readiness-confidentiality/)
- AWS: [SDK and tool PQ TLS support](https://docs.aws.amazon.com/sdkref/latest/guide/pqtls-details.html)
- AWS: [ALB security policies](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/describe-ssl-policies.html)
- AWS: [NLB security policies](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/describe-ssl-policies.html)
- AWS: [CloudFront viewer protocols and ciphers](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/secure-connections-supported-viewer-protocols-ciphers.html)
- AWS: [API Gateway security policies](https://docs.aws.amazon.com/en_us/apigateway/latest/developerguide/apigateway-security-policies-list.html)
- AWS: [IoT Core transport security](https://docs.aws.amazon.com/iot/latest/developerguide/transport-security.html)
- AWS: [AL2023 PQ crypto policies](https://docs.aws.amazon.com/linux/al2023/ug/crypto-policies-pq.html)
- AWS: [Secrets Manager post-quantum TLS](https://docs.aws.amazon.com/secretsmanager/latest/userguide/pqtls.html)
- AWS: [Lambda quotas](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html)
- AWS: [Lambda runtimes and deprecation](https://docs.amazonaws.cn/en_us/lambda/latest/dg/lambda-runtimes.html)
- AWS: [Config rule elbv2-predefined-security-policy-ssl-check](https://docs.aws.amazon.com/config/latest/developerguide/elbv2-predefined-security-policy-ssl-check.html)
- Go: [Go 1.24 release notes](https://go.dev/doc/go1.24)
- OpenJDK: [JEP 527](https://openjdk.org/jeps/527)
- rustls: [defaults](https://docs.rs/crate/rustls/latest/source/src/manual/defaults.rs)
- Linkerd: [2.19 announcement](https://linkerd.io/2025/10/31/announcing-linkerd-2.19/)
- Istio: [1.27 change notes](https://istio.io/latest/news/releases/1.27.x/announcing-1.27/change-notes/)
- Microsoft: [Windows TLS 1.3 and PQ FAQ](https://techcommunity.microsoft.com/t5/post-quantum-crypto-tech-blog/windows-tls-1-3-and-post-quantum-crypto-faq/ba-p/4556389)
- Third party: [When an AWS connection uses ML-KEM](https://hidekazu-konishi.com/entry/when_an_aws_connection_uses_ml_kem.html)

Related: [PQC Connection Migration: Tooling Capability Review](https://claude.ai/artifact/8wFt3xY4hJjG9wm8FuDHaH).
