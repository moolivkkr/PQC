# Introduction

## What we are solving

Every TLS connection we own agrees on a session key with a classical key exchange (X25519 or ECDHE on P-256) unless something changes it. Traffic recorded today can be decrypted once a large quantum computer exists ("harvest now, decrypt later"), so data that must stay confidential for years is exposed now, not later.

Three facts make this a programme rather than a setting:

- **Classical is still the default where we run.** On AWS Lambda managed runtimes and Amazon Linux 2023 images, Python, Node.js and .NET negotiate classical X25519; Java before 25 and Node.js 18 and 20 cannot negotiate post-quantum at all. Only some newer images (Debian 13, Alpine 3.24, Ubuntu 26.04, official Node 22.20+ and 24.5+, Go 1.24+, JDK 25.0.5+) are post-quantum out of the box.
- **It fails silently.** A hybrid client talking to a classical server, or a classical client talking to a hybrid server, falls back to classical with no error. Only logs, sensors and inventory show which connections are still classical.
- **One date is fixed.** AWS blocks updates to deprecated Lambda runtimes (Node.js 18 and 20, Python 3.9 to 3.11, Java on Amazon Linux 2, `provided.al2`, `dotnet8`) from 2027-08-31. After that no layer, file or variable can be added to those functions.

## What "PQC-enabled" means in this paper

| Term | Meaning | How it is proven |
| --- | --- | --- |
| **PQ connection** | A TLS 1.3 handshake that negotiated a hybrid ML-KEM key exchange group: X25519MLKEM768 (or SecP256r1MLKEM768, SecP384r1MLKEM1024). ML-KEM is FIPS 203 | The negotiated group in a log or sensor: CloudTrail `tlsDetails.keyExchange`, ALB/NLB logs, Zeek `ssl.log` `curve`, or the application's own handshake log |
| **PQ-enabled client** | Offers a hybrid ML-KEM group first and still offers classical groups, so it connects to every server | A PQ-only test server accepts it; a classical-only server still accepts it |
| **PQ-enabled server or front door** | Accepts and prefers the hybrid group and still accepts classical clients | A PQ client negotiates the hybrid group; a classical client still connects |
| **PQ-done workload** | Every connection it owns that can be PQ is observed as PQ; the rest are recorded exceptions | Dashboards ([Inventory and dashboards](#ch-13-inventory)), not the deployment record |
| **PQ-signed certificate** | A certificate or signature that uses ML-DSA (FIPS 204). A separate track: see [Use cases](#ch-11-use-cases) | The certificate's algorithm; the TLS `server_sigalg` |

What it does **not** mean:

- **Not new certificates.** ML-KEM key exchange works with today's RSA and ECDSA certificates. ML-DSA certificates are a separate, slower track, by use case.
- **Not PQ-only.** Every fix keeps classical groups as a fallback, so nothing breaks on the day it ships. PQ-only (TLS 1.3 with only hybrid groups) comes later, per endpoint, once logs show no classical traffic.
- **Not encryption at rest, application-layer cryptography or tokens.** KMS keys, S3 encryption, JWT and message signing are out of scope, except where noted under code signing.
- **Not FIPS-validated PQ.** FIPS workloads follow the FIPS notes per language and wait for validation evidence.

## Scope: connections, compute types and languages

| Connection | Example | Who is the TLS client | Covered in |
| --- | --- | --- | --- |
| Internet to front door | Browser or partner to ALB, NLB, CloudFront, API Gateway | The caller | [Load balancers](#ch-load-balancers); [Edge and API front doors](#ch-edge-and-api-front-doors) |
| Front door to target | ALB to an ECS service | The load balancer | [Load balancers](#ch-load-balancers) (target leg) |
| Workload to AWS APIs | Lambda calling KMS, S3, Secrets Manager | Our code (SDK) | [Solutions by compute type](#ch-14-compute); [by language](#ch-15-languages); [AWS service endpoints](#ch-aws-service-endpoints) |
| Workload to internal services | Service to service, private CA, mTLS | Our code | [Solutions by compute type](#ch-14-compute); [by language](#ch-15-languages); [Service mesh](#ch-service-mesh) |
| Workload to third parties | SaaS APIs, partners, the internet | Our code, or an egress proxy | [Solutions by language](#ch-15-languages); [Network devices and egress](#ch-network-devices-and-egress) |
| Workload to data stores | RDS, Aurora, ElastiCache, MSK, OpenSearch | Our driver | [Databases and data services](#ch-databases-and-data-services) |
| Host administration | SSH to EC2 | OpenSSH | [Hosts and OS](#ch-hosts-and-os) |
| Devices | Sensors and gateways to AWS IoT Core | Device firmware | [IoT](#ch-iot) |
| Certificates and signatures | Server, client, user, device and code-signing certificates | n/a | [Use cases](#ch-11-use-cases); [Certificates (ML-DSA)](#ch-certificates-ml-dsa) |

**Compute types:** AWS Lambda (zip and container image), Amazon ECS on AWS Fargate, Amazon ECS on EC2 and Amazon EKS, and Amazon EC2 hosts. **Languages:** Go, Python, Node.js, Java and .NET, with notes on Rust, Ruby and PHP.

## Approach

The programme runs in five steps, each with its own chapter. The language and its version decide whether a connection is PQ; the compute type decides how we see it and where the fix ships.

1. **Detect** ([chapter 3](#ch-12-detection)). Combine *observed* signals (what a handshake actually negotiated: CloudTrail, load balancer logs, Zeek, application logs) with *posture* signals (what a workload will negotiate, predicted from its runtime, versions and settings). Observed signals prove; posture covers what no log sees, such as Lambda and Fargate calls to non-AWS services.
2. **Inventory and track** ([chapter 4](#ch-13-inventory)). Put every workload, front door, data service, host, device and certificate in one inventory, classify each against the matrices in this paper, and track the classical share on dashboards fed by the detection signals.
3. **Remediate** (chapters [5](#ch-14-compute), [6](#ch-15-languages) and [7](#ch-08-infrastructure)). Apply the tested fix for each language on each compute type, then the infrastructure services. Every fix is a file, a variable, a rebuild or a version bump, shipped through the shared build template and rolled back by removing it.
4. **Enforce** ([chapter 8](#ch-21-enforcement)). Guardrails in the pipeline, AWS Organizations and Kubernetes start in warn mode and then fail builds, so new work stays PQ.
5. **Prove** ([chapter 9](#ch-23-rollout-gaps)). A workload is done only when the dashboards show its connections as PQ. Anything that cannot be PQ (blocked by AWS or a third party) is a recorded exception with an owner and a review date.

Certificates follow their own track alongside: ML-DSA roots and long-lived signatures first, internal dual-certificate pilots next, public HTTPS when AWS and browsers support it.

## Summary of results

- **Every language can be made PQ on every compute type we run**, with one change per workload. 437 client cases and 32 load balancer target cases pass end to end in LocalStack Pro on real Lambda, ECS and EC2 deployments (run 2026-11-16).
- **Certificates and keystores do not change** for ML-KEM. Existing server certificates, private CA trust and mutual TLS keep working in all five languages.
- **ML-DSA certificates work today only on OpenSSL 3.5 stacks** with ML-DSA enabled; Go, Java, OpenSSL 3.0 and the default Amazon Linux 2023 policy get ECDSA from a dual-certificate server. A dual-certificate server broke none of the 402 clients that connect at all.
- **Detection works** from CloudTrail, load balancer logs, CloudWatch filters and Zeek (`ssl.log` field `curve`, tested with Zeek 7.2.2 and 8.0.10); Lambda and Fargate calls to non-AWS services remain posture-only.
- **AWS blocks some legs today:** CloudFront to origin, API Gateway egress and HTTP/WebSocket APIs, IoT Core, RDS Proxy, ElastiCache, MSK, OpenSearch, Network Firewall TLS inspection and AWS VPN. These are recorded exceptions.
- **Not yet tested on real AWS.** All tests ran on LocalStack and Docker on arm64; Phase 0 of the rollout plan closes that gap.

## How to read this paper

Evidence labels used in every table:

| Label | Meaning |
| --- | --- |
| Tested | Run between 2026-11-12 and 2026-11-16 in AWS Lambda base images, official language and distro images, or the LocalStack end-to-end suite (`e2e/`). Not run on real AWS |
| Documented | Stated in vendor documentation, not tested here |
| Claimed | Stated by a vendor as a plan or roadmap item, not yet shipped or confirmed |
| Unverified | Believed true, no source opened or test run; confirm before relying on it |

**Code in this paper** is limited to the main change. Every complete file (configs, IaC, scripts, policies) is in the repository under `configs/`, linked by relative path from each chapter and indexed in [Appendix B](#ch-22-config-index). Test code is under `e2e/` and `tests/`, listed per language in [Appendix A](#ch-24-appendix-tests). Paths are relative to the repository root.
