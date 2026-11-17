# Use cases: key exchange and certificates

**ML-KEM protects key exchange** and stops traffic recorded today from being read later: urgent for every connection, and no new certificates. **ML-DSA protects certificates and signatures**: a forged signature matters only once a quantum computer exists, so it is urgent only where trust must last for years. In TLS today, "hybrid" key exchange is one group (X25519MLKEM768); "hybrid" certificates mean a **dual certificate** (the server holds ECDSA and ML-DSA and sends what the client asks for). Composite certificates have no TLS code points yet (Documented).

| Use case | Key exchange (ML-KEM) | Certificate (ML-DSA) | Do now |
| --- | --- | --- | --- |
| Public HTTPS | PQ policy on ALB, NLB, CloudFront, API Gateway REST | Not possible: AWS front doors and browsers serve RSA/ECDSA only | Key exchange now; keep ECDSA certificates |
| Internal HTTPS (private CA) | Language fix per workload | Dual certificate from AWS Private CA; OpenSSL 3.5 clients get ML-DSA, Go and Java get ECDSA | Key exchange now; pilot dual certificates. Never ML-DSA-only |
| Workload identity and mTLS | Same as internal | ML-DSA client keys work on OpenSSL 3.5 stacks and .NET 10; not .NET 8, Go, Java. IAM Roles Anywhere accepts ML-DSA | Pilot Roles Anywhere; mesh identities stay ECDSA |
| User certificates | Windows Schannel opt-in | AD CS 2025 issues ML-DSA; Microsoft calls Schannel ML-DSA a pilot | Separate test CA only |
| Devices and IoT | AWS IoT Core has no PQ policy | IoT Core: RSA/ECDSA only | **Plan now:** ML-DSA root alongside ECDSA in new firmware |
| Code and firmware signing | n/a | KMS ML-DSA keys; Private CA code-signing certificates; AWS Signer is ECDSA only | **Plan now:** add an ML-DSA signature for artifacts verified for years |
| SSH | OpenSSH 10 defaults to `mlkem768x25519-sha256` (Tested) | OpenSSH 10.6 hybrid ML-DSA keys | Upgrade OpenSSH; ML-DSA keys only where all clients are 10.6+ |

**Tested across 409 client cases:** 91 used ML-DSA on all three test targets, 4 (.NET 8) on server certificates only, 307 got ECDSA from the dual server, and every client that connects at all still connected to the dual server. So ML-DSA roots can be distributed now, and dual certificates break nobody; ML-DSA-only servers would break Go, Java, OpenSSL 3.0 and the default Amazon Linux 2023 policy.
