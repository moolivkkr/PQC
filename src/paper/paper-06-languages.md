# Solutions by language

One page per language follows: what decides PQ, the change on each compute type, what to watch with existing certificates, ML-DSA, rollback and what was tested. Each language team has its own document with every version, case (simple client and server, own keystores, custom CA trust, mutual TLS, explicit settings, FIPS, libraries with their own TLS, pinning), test procedure, configuration file and test case.

| Language | What decides PQ | PQ by default today | Main action |
| --- | --- | --- | --- |
| Go | `crypto/tls` in the binary: toolchain and `go` line | Go 1.24+ with `go` ≥ 1.24, everywhere | Build with 1.26, raise the `go` line |
| Python | The platform OpenSSL | Debian 13 and Alpine images | Config file on Lambda and AL2023; upgrade 3.9 to 3.11 |
| Node.js | Bundled OpenSSL plus its config | Official 22.20+ and 24.5+ (not on Lambda) | Override file on Lambda; upgrade 18 and 20 |
| Java | The JVM's JSSE provider | JDK 25.0.5+ | JDK 25, or the Bouncy Castle agent for 8 to 21 |
| .NET | The OS (OpenSSL, Schannel) | Alpine and Ubuntu 26.04 images | Config file or PQ base image; Windows opt-in |

Rust (rustls with aws-lc-rs, AWS SDK for Rust), Ruby and PHP (system OpenSSL) are Documented, not tested.
