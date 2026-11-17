# Appendix C. Evidence and sources

## Tests

**Tests (2026-11-12).** AWS Lambda base images under the Runtime Interface Emulator, against a Node 24 test server with one port accepting only X25519MLKEM768 and one accepting only X25519. Images: python 3.9 to 3.14, nodejs 18 to 24, java 8.al2023, 11, 17, 21, 25, dotnet 8 and 10, provided.al2023 with Go 1.23 to 1.25. Scripts and results: `tests/lambda/`.

**Tests (2026-11-15 and 2026-11-16), end to end.** 471 cases in LocalStack Pro (run r1117041043, 471 of 471 passed) (`e2e/`): real Lambda zip, layer, extension and image functions, ECS Fargate and ECS on EC2 tasks, and EC2 instances from AL2023 and AL2 AMIs, for all five languages, each graded against this document by a TLS observer, plus 32 load balancer target-leg cases. Results: `e2e/results/latest/summary.md`. Real AWS, x86_64 and the ALB/NLB listener leg were not covered.

**Tests (2026-11-13 and 2026-11-14).** Existing-certificate cases (own keystores and key files, private CA trust, mutual TLS, explicit TLS settings) for all five languages, in official language and distro images (Debian 12, 13 and 14, Ubuntu 26.04, Alpine, AL2023, Fedora) against OpenSSL 3.5 `s_server` instances that accept only X25519MLKEM768 or only X25519. The Bouncy Castle EC server fix was tested on Tomcat 11.0.29, Jetty 12.1.15 and HttpsServer, JDK 17, 21 and 25. Scripts and results: `tests/deep/`. Appendix A lists them per language.

## Documentation

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
