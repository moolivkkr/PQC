# Rollout, gaps and open items

**Mechanism.** Every change ships as a release: (1) the inventory classifies each workload; (2) a bot opens a pull request bumping the shared build template, which adds the right file and variable; (3) the normal pipeline releases it, with guardrails warning then failing; (4) observed signals confirm the change, because shipping is not proof. Dormant workloads are ranked by observed classical traffic; runtimes past AWS's block date cannot change, so they go first.

| Phase (proposed) | Window |
| --- | --- |
| 0. Prove on real AWS (CloudTrail `keyExchange`, ELB logs, one workload per language and compute) | 2026-11-23 to 2026-12-18 |
| 1. Inventory and baseline; dashboards | 2026-11-23 to 2027-01-15 |
| Wave A. Runtime upgrades for runtimes AWS blocks (Node 18 and 20, Python 3.9 to 3.11, Java on AL2, `provided.al2`, `dotnet8`) | 2026-12-01 to 2027-06-30 |
| 2. Guardrails in warn mode | 2027-01-04 to 2027-02-12 |
| 3. Front doors to PQ policies | 2027-01-11 to 2027-03-12 |
| 4. Workload waves B to D through the build template | 2027-02-01 to 2027-06-30 |
| 5. Enforce (guardrails fail, org-wide SCP) | 2027-07-01 to 2027-09-30 |
| Certificate track (ML-DSA roots and signing first, then dual-certificate pilots) | 2026-11-23 to 2027-12-17 |

Dates and owners are in the rollout plan (`artifacts/PQC-TLS-rollout-plan.md`).

| Gap or risk | Impact | Next step |
| --- | --- | --- |
| Nothing ran on real AWS or x86_64 | Lab results may differ from AWS | Phase 0 |
| Node.js 18 and 20, Python 3.9 to 3.11 on Lambda | No full in-process fix; AWS blocks updates 2027-08-31 | Upgrade first; bridges only for urgent calls |
| Bouncy Castle agent on Java 8 to 21 | Replaces the TLS provider process-wide | Test FIPS, keystore and mTLS services first; prefer JDK 25 |
| Lambda and Fargate to non-AWS services | No AWS log shows the group | Posture, application logs, egress proxy |
| AWS-blocked legs (CloudFront origin, API Gateway egress and HTTP APIs, IoT Core, RDS Proxy, ElastiCache, MSK, OpenSearch, VPN) | Classical by design today | Exception register; quarterly recheck |
| ML-DSA | Public HTTPS can't use it; Go and Java don't negotiate it; chains grow to ~12 KB | Dual certificates only; certificate track |
| Inventory dashboards and Athena views | Not run on AWS | Build in Phase 0 |
| Node config file replaces AWS's | Drift on runtime updates | Pipeline diff check |

**What we ask:** an AWS sandbox account for Phase 0, owners per language and per infrastructure area, and agreement to the warn-then-fail schedule.
