# Use cases: key exchange and certificates

This chapter says which use cases "PQC-enabled" covers, and which algorithm each one needs. The rest of the paper is mostly about the first column (key exchange), because that is where the risk is today and where every fix is available.

## ML-KEM and ML-DSA

Two separate algorithms. **ML-KEM (FIPS 203) protects key exchange**: it stops traffic recorded today from being decrypted later, so it is urgent for every TLS connection, and it needs no new certificates. **ML-DSA (FIPS 204) protects certificates and signatures**: a forged signature only matters once a quantum computer exists, so it is urgent only where a signature or trust anchor must stay trusted for many years (device roots in firmware, code and firmware signing). ML-KEM cannot sign, so there is no "ML-KEM certificate".

"Hybrid" means different things on each side. For key exchange it is one group (X25519MLKEM768) that combines both algorithms, and it is what AWS, browsers and Go use. For TLS certificates, the deployable form today is a **dual certificate**: the server holds an ECDSA and an ML-DSA certificate and sends the one the client asks for (Tested, nginx and the e2e fixture). Composite ML-DSA certificates (one certificate, both algorithms) are standardized for X.509 by IETF LAMPS, but their TLS code points are still TBD in draft-ietf-tls-composite-mldsa-00 (October 2026), so no TLS stack negotiates them yet (Documented).

## Use-case matrix

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

## ML-DSA per client stack

**ML-DSA per language** (e2e, three targets on one fixture: `mldsa-dual` = dual certificate, `mldsa-only` = ML-DSA certificate only, `mldsa-mtls` = ML-DSA client certificate required). 

Runs r1117034807 and r1117041043 (2026-11-16, identical ML-DSA results): 409 client cases across Lambda, ECS Fargate, ECS on EC2 and EC2 (the 28 `pq-egress` extension cases have no ML-DSA targets). 91 got ML-DSA on all three targets, 4 (.NET 8) on two, 307 got the ECDSA certificate from the dual server and failed the other two, and 7 failed every target for unrelated reasons (FIPS-only Go, a boringcrypto panic, Java 8 without the host-name flag, the shim without idna). Expectations per case: `e2e/cases/mldsa_rules.py`; the fixture: `e2e/mldsa/server.py`.

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
