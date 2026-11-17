# Introduction

## What we are solving

Every TLS connection we own agrees its session key with a classical key exchange (X25519 or ECDHE P-256) unless something changes it. Traffic recorded today can be decrypted once a large quantum computer exists ("harvest now, decrypt later"), so data that must stay confidential for years is exposed now.

- **Classical is still the default where we run.** On Lambda and Amazon Linux 2023, Python, Node.js and .NET negotiate classical X25519; Java before 25 and Node.js 18 and 20 cannot negotiate PQ at all.
- **It fails silently.** A PQ client and a classical server, or the reverse, quietly agree on classical. Only logs, sensors and the inventory show it.
- **One date is fixed.** AWS blocks updates to deprecated Lambda runtimes (Node.js 18 and 20, Python 3.9 to 3.11, Java on Amazon Linux 2, `provided.al2`, `dotnet8`) from 2027-08-31. After that no fix can be added to them.

## What "PQC-enabled" means

| Term | Meaning | Proven by |
| --- | --- | --- |
| **PQ connection** | TLS 1.3 handshake that negotiated a hybrid ML-KEM group (X25519MLKEM768; ML-KEM is FIPS 203) | The negotiated group in CloudTrail, ELB logs, Zeek or the application log |
| **PQ-enabled client or server** | Offers or accepts the hybrid group first **and** still accepts classical peers | A PQ-only and a classical-only test server both connect |
| **PQ-done workload** | Every connection it owns that can be PQ is observed as PQ; the rest are recorded exceptions | Dashboards, not the deployment record |
| **PQ-signed certificate** | Certificate or signature using ML-DSA (FIPS 204). A separate, slower track | Certificate algorithm; TLS signature algorithm |

It does **not** mean new certificates (ML-KEM works with today's RSA and ECDSA certificates), PQ-only endpoints (classical fallback stays until logs show no classical traffic), encryption at rest, or FIPS-validated PQ.

## Scope

Connections: internet to front doors (ALB, NLB, CloudFront, API Gateway); front door to target; workload to AWS APIs, internal services, third parties and data stores; SSH to hosts; devices to AWS IoT Core; and certificates and signatures. Compute: Lambda (zip and image), ECS on Fargate, ECS on EC2 and EKS, EC2. Languages: Go, Python, Node.js, Java, .NET.

## Approach

| Step | What | Chapter |
| --- | --- | --- |
| 1 Detect | Observed signals (what was negotiated) plus posture (what will be negotiated) | 3 |
| 2 Inventory and track | One classified list of every component; dashboards to done | 4 |
| 3 Remediate | One tested change per workload, by compute type and language; then infrastructure | 5, 6, 7 |
| 4 Enforce | Guardrails in the pipeline, AWS Organizations and Kubernetes, warn then fail | 8 |
| 5 Prove | Done only when observed PQ; the rest are owned exceptions | 9 |

Certificates run alongside: ML-DSA roots and long-lived signatures first, internal dual-certificate pilots next, public HTTPS when AWS and browsers support it.

## Evidence

Every claim carries a label: **Tested** (run between 2026-11-12 and 2026-11-16 in Lambda base images, official images or the LocalStack end-to-end suite; not on real AWS), **Documented** (vendor documentation), **Claimed** (vendor plan) or **Unverified**. The end-to-end suite deploys real Lambda functions, ECS tasks and EC2 instances in LocalStack Pro: run r1117041043 passed 471 of 471 cases (437 client cases, 32 load balancer target cases, 2 detection checks). Language teams have their own documents with the full detail; every configuration file and test is in the repository.
