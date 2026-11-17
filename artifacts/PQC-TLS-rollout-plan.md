# PQC TLS rollout plan

Nov 16, 2026 · Kishore Mooli

We move TLS on our AWS workloads to the hybrid key exchange X25519MLKEM768 in six phases, with deprecated Lambda runtimes upgraded before AWS blocks updates on Aug 31, 2027. The fixes are known and tested; the plan is about order, guardrails and proof.

## Starting point

The fix for every language and compute type is known and tested in emulation; nothing has run on a real AWS account yet. The guide (`PQC-Detection-and-Remediation`, commit `c6e5cd3`) is the source for every change below.

| Area | State today | Evidence |
| --- | --- | --- |
| Language fixes (Python, Node.js, Java, .NET, Go) on Lambda, Fargate, ECS on EC2, EC2 | Fix per runtime known; certificates and keystores do not change | 437 LocalStack e2e cases pass |
| ALB/NLB to container (target leg) | PQ when the listener has a PQ policy and the container has its fix | 32 e2e cases, modelled with Go's TLS client |
| Guardrails (cfn-guard, OPA/conftest, Checkov, Config, SCP) | Written and unit-tested | cfn-guard 3.2.1, OPA 12/12, conftest; never applied to an account |
| Detection (CloudWatch filter, server-side log) | Finds classical handshakes | 11 of 12 checks; one log line dropped by LocalStack |
| Client to ALB/NLB listener, API Gateway, CloudFront | Policy names documented | Not testable on LocalStack; needs real AWS |
| KMS, STS, Secrets Manager endpoints; `pq-egress` with SigV4; x86\_64; `java11.al2023`, `java17.al2023` | Expected to work | Not tested |

The blind spot is outbound calls from Lambda and Fargate to non-AWS services: no AWS log shows their key exchange. Posture inventory carries those until a sensor or app-side log exists. How much of our traffic that is, we will know after Phase 1.

## Phases and gates

| Track | Window (proposed) |
| --- | --- |
| Phase 0. Prove on real AWS | 2026-11-23 to 2026-12-18 |
| Phase 1. Inventory and baseline | 2026-11-23 to 2027-01-15 |
| Wave A. Runtime upgrades | 2026-12-01 to 2027-06-30 |
| Phase 2. Guardrails in warn mode | 2027-01-04 to 2027-02-12 |
| Phase 3. Front doors | 2027-01-11 to 2027-03-12 |
| Phase 4. Workload waves B to D | 2027-02-01 to 2027-06-30 |
| Phase 5. Enforce | 2027-07-01 to 2027-09-30 |
| Certificate track (ML-DSA) | 2026-11-23 to 2027-12-17, then as stacks catch up |
| AWS: function create blocked (deprecated runtimes) | 2027-07-29 |
| AWS: function update blocked (deprecated runtimes) | 2027-08-31 |

Phases 0 and 1 run together; runtime upgrades (Wave A) start in December because no setting fixes most of those runtimes and AWS blocks updates on 31 August 2027. Each phase ends at the exit gate in Phase detail.

## Phase detail

Dates are a proposal for the steering group; the only fixed date is AWS's update block on 2027-08-31 for deprecated Lambda runtimes.

| Phase | Window (proposed) | Work | Exit gate | Lead |
| --- | --- | --- | --- | --- |
| 0. Prove on real AWS | 2026-11-23 to 2026-12-18 | Sandbox account: ALB and NLB listeners on `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09` with connection logs; a fixed Lambda per language calling KMS and Secrets Manager (CloudTrail `tlsDetails.keyExchange`); `pq-egress` with SigV4 calls; one x86\_64 run of the e2e suite; `java11.al2023` and `java17.al2023`; guardrails applied in audit mode; AWS Private CA ML-DSA test root issuing a dual ECDSA + ML-DSA certificate to one internal test service, and IAM Roles Anywhere with an ML-DSA trust anchor | Every "not tested" row in Starting point is Tested or an accepted exception | Security architecture |
| 1. Inventory and baseline | 2026-11-23 to 2027-01-15 | Posture inventory across all accounts: Lambda runtimes and env vars, ECR image SBOMs, SSM inventory, ELB and API Gateway policies; ALB/NLB connection logs and Athena tables; CloudTrail key-exchange queries; RemediationEngine PQC readiness findings | Every workload sits in a guide matrix row with an owner; baseline share of classical handshakes recorded | Platform engineering |
| 2. Guardrails in warn mode | 2027-01-04 to 2027-02-12 | cfn-guard, conftest and Checkov rules in every pipeline as warnings; Config rules in audit; ELB SCP on a sandbox OU | Warnings visible on every pull request; no false positives open | Security architecture |
| 3. Front doors | 2027-01-11 to 2027-03-12 | All ALB and NLB TLS listeners to the `Res-PQ` policy (classical and TLS 1.2 clients still connect); API Gateway REST to the PQ policy | Listener posture 100% PQ policy; key-exchange mix from connection logs reported weekly | Network engineering |
| 4. Workload waves | 2027-02-01 to 2027-06-30 | Shared build template carries the pq-tls kit; waves B to D (Order of work) ship on each service's normal release. Wave A, runtime upgrades, runs from 2026-12-01 to 2027-06-30 as its own track | Each workload meets the definition of done | Platform engineering with app teams |
| 5. Enforce | 2027-07-01 to 2027-09-30 | Guardrails fail builds; SCP denies non-PQ ELB policies; listeners whose TLS 1.2 traffic is zero move to `TLS13-1-3-PQ`; exceptions register reviewed | No new non-PQ workload can ship; every remaining classical connection is a recorded exception | Security architecture |

After Phase 5: JDK 25.0.5+ replaces the Java kit as teams upgrade.

## Certificate track (ML-DSA)

ML-KEM (the phases above) protects key exchange and needs no new certificates. ML-DSA protects certificates and signatures; a forged signature only matters once a quantum computer exists, so this track is smaller and runs alongside, with two exceptions that start now: roots that ship in device firmware and code or firmware signatures that are verified for years. For TLS, "hybrid" certificates mean two certificates on one server (ECDSA and ML-DSA, chosen per client); composite ML-DSA certificates have no TLS code points yet.

| Step | Window (proposed) | Work | Exit gate | Lead |
| --- | --- | --- | --- | --- |
| C0. Test in Phase 0 | 2026-11-23 to 2026-12-18 | Private CA ML-DSA test root; dual certificate on one internal test service; Roles Anywhere ML-DSA trust anchor and `aws_signing_helper` with an ML-DSA key; client matrix from the e2e targets `mldsa-dual`, `mldsa-only`, `mldsa-mtls` repeated on real AWS | Each use case in the guide's Use cases table marked Tested or Unverified on real AWS | Security architecture |
| C1. Roots and signing | 2027-01-04 to 2027-03-31 | Add the ML-DSA root to trust bundles next to the existing roots (old clients ignore it, Tested); ML-DSA signature from KMS next to the existing signature for firmware and long-lived artifacts; ML-DSA root in new device firmware | New firmware and signed artifacts carry ML-DSA; trust bundles carry the ML-DSA root | Platform engineering, device teams |
| C2. Internal pilot | 2027-04-01 to 2027-12-17 | Dual certificates on internal mTLS services whose clients run OpenSSL 3.5 (Python, Node.js, .NET on Debian 13, Alpine, Ubuntu 26.04, or AL2023 with `configs/certificates-ml-dsa/openssl-pq-mldsa.cnf`) | Pilot services serve ML-DSA to those clients and ECDSA to the rest with no failed handshakes | Platform engineering |
| C3. Wider use | When Go and Java negotiate ML-DSA, and ACM, ELB, CloudFront and browsers serve it | Extend dual certificates; public HTTPS follows browsers and AWS | Recheck each quarter | Security architecture |

Never serve an ML-DSA certificate alone while any client runs Go, Java, OpenSSL 3.0 or an unmodified AL2023 crypto policy: those clients fail the handshake (Tested). Certificate chains grow from about 0.9 KB to 11.8 KB.

## Order of work

Waves are set by how hard the fix is; within a wave, workloads go by data sensitivity first, because recorded traffic stays decryptable for as long as the data matters.

| Wave | Workloads | Fix | Why this order |
| --- | --- | --- | --- |
| A. Runtime upgrades | Lambda `nodejs18.x`, `nodejs20.x`, `python3.9` to `3.11`, `provided.al2`, `java8.al2`, `java11`, `java17` (AL2), `dotnet8` | Upgrade the runtime, then apply the wave B fix; `pq-egress` only for calls that must be PQ sooner | No setting works on most of these, and AWS blocks updates on 2027-08-31: start first, finish by 2027-06-30 |
| B. Config only | Python 3.12+, Node 22.20+/24, .NET 8/10 on Lambda and AL2023 images; Go rebuilt with 1.26 and `go 1.26` | `OPENSSL_CONF` file or `DEFAULT:PQ` in the image; Go rebuild | Lowest risk: one file and one variable, rolled back by removing them |
| C. Java 8 to 21 | Every JVM below 25.0.5 | Kit v2: Bouncy Castle agent plus `pq-tls.security`; JDK 25.0.5+ where the team can upgrade | Replaces the TLS provider process-wide: canary each service, test keystores, mTLS and FIPS first |
| D. Base images | Debian 12 (`bookworm`), Ubuntu 24.04, Alpine before 3.22, `-bookworm` Python tags, pinned old Node | Move to Debian 13, Alpine 3.24 or Ubuntu 26.04 | Larger change with its own testing; ride the team's next image refresh |

Two rules cut across the waves:

- Code that pins classical groups or TLS 1.2 (`CurvePreferences`, `jdk.tls.namedGroups`, `ecdhCurve`, `SslProtocols.Tls12`) gets fixed in the same release; the per-language CI checks find it.
- FIPS workloads wait for Phase 0 evidence; do not add the Java kit or the generic config file to a FIPS host.

## Who does what

App teams change almost nothing by hand: the platform ships the fix in the shared template and the app team releases it. Names are open until the steering group assigns them.

| Role | Owns | Phases |
| --- | --- | --- |
| Security architecture | The guide, the policy and the exceptions register; guardrail rules; Phase 0 tests on real AWS | 0, 2, 5 |
| Platform engineering | The pq-tls kit, the Lambda layer, the shared build templates, base images; the posture inventory | 1, 4 |
| Network engineering | ALB, NLB and API Gateway policies, connection logs and Athena queries, egress sensors | 3 |
| App teams | Releasing the template bump; removing code pins; testing their keystores and mTLS; Java and runtime upgrades | 4 |
| RemediationEngine | PQC readiness findings per workload from the guide, and automated change requests | 1, 4 |
| Steering group | Dates, funding for Phase 0, FIPS policy, exception approvals | All |

## Measuring done

A workload is done when its connections are observed using X25519MLKEM768, not when the change ships. Shipping without the observation leaves it in progress.

Per workload, all three:

1. **Posture:** the inventory puts it in a PQ row (runtime, image and settings match the guide's fix), and its CI checks pass.
2. **Observed:** at least one of CloudTrail `tlsDetails.keyExchange` for its AWS API calls, ALB/NLB connection logs for its inbound traffic, a sensor or app-side handshake log for other outbound calls shows the hybrid group.
3. **Fallback intact:** classical peers still connect; no error-rate change across the canary.

Fleet metrics, reported weekly from Phase 1:

| Metric | Source | Target by end of Phase 5 |
| --- | --- | --- |
| Workloads in a PQ posture row | Posture inventory | 100%, less recorded exceptions |
| Inbound handshakes using an ML-KEM group | ALB/NLB connection logs (`tls_keyexchange`) | Trend up; depends on clients |
| AWS API calls using an ML-KEM group | CloudTrail `tlsDetails.keyExchange` (KMS, STS, IAM, Secrets Manager, ACM) | 100% from fixed workloads |
| TLS 1.2 connections per listener | ALB connection logs | Zero before a listener moves to TLS 1.3 only |
| Open exceptions | Exceptions register | Each with an owner and a review date |

## Risks and rollback

Every fix rolls back by removing a file or a variable in the next release, except runtime and base-image upgrades.

| Risk | Effect | Mitigation | Rollback |
| --- | --- | --- | --- |
| Real AWS behaves differently from LocalStack | A fix that passed e2e fails in production | Phase 0 before any wave; canary per wave | Remove `OPENSSL_CONF`, the agent or `GODEBUG` |
| Java kit replaces the TLS provider process-wide | Keystore, mTLS or FIPS breakage | Canary; kit v2 only (sets the `PKIX` key manager); no kit on FIPS JVMs | Drop the agent from `JAVA_TOOL_OPTIONS`, or `PQ_TLS_DISABLE=1` with the layer |
| Larger ClientHello (about 1.2 KB more) | Old middleboxes drop it | Test partner networks before TLS 1.3-only listeners | Listener back to the `Res-PQ` policy |
| Deprecated runtimes miss 2027-08-31 | No config change possible afterwards | Wave A starts in Phase 1, tracked separately | None: upgrade is the only path |
| Node config file replaces AWS's | Drift when AWS changes its Lambda file | Pipeline diff against each new runtime image | Remove the variable |
| Guardrails block delivery | Teams stall on false positives | Warn mode for 30 days first; exceptions by tag | Switch the rule back to warn |
| ML-DSA-only certificate on a server | Go, Java, OpenSSL 3.0 and default AL2023 clients fail the handshake | Dual certificates only; client inventory before each pilot service | Remove the ML-DSA certificate; ECDSA keeps serving |
| AL2023 crypto policy omits ML-DSA signature algorithms | AL2023 clients get ECDSA from a dual server and fail against ML-DSA only, even with the ML-KEM config | Use `openssl-pq-mldsa.cnf` (adds `SignatureAlgorithms`) on pilot clients | Point `OPENSSL_CONF` back at `openssl-pq.cnf` |
| No log shows outbound key exchange from Lambda and Fargate to non-AWS services | Done cannot be proven for those calls | App-side handshake logs or an egress sensor where the data warrants it | n/a |

## Decisions needed

Phase 0 cannot start until the first decision is made.

- [ ] Fund a sandbox AWS account and about four weeks for Phase 0.
- [ ] Approve the phase windows, or move them; keep Wave A ending by 2027-06-30.
- [ ] Name a lead for each role in Who does what.
- [ ] Java policy: kit v2 on 8 to 21 as the bridge, or require JDK 25.0.5+ (or wait for vendor backports to 17 and 21, which Oracle says are planned for H1 2027 but has not shipped).
- [ ] FIPS policy: which workloads must stay FIPS, and whether they wait for FIPS PQ evidence.
- [ ] Exception rule: who approves a workload staying classical, and how often it is reviewed.
- [ ] Which data classes rank first inside each wave.
- [ ] Certificate track: approve C0 in Phase 0, ML-DSA signing for firmware and long-lived artifacts in 2027 Q1, and one internal dual-certificate pilot service.

## Sources

- PQC Detection and Remediation guide, repo `moolivkkr/PQC`, commit `c6e5cd3` (overview, language tabs, Load balancers, Enforcement and guardrails)
- End-to-end results: `e2e/results/latest/summary.md` (run final-20261115)
- [Corrections from the end-to-end run and the document review](https://claude.ai/artifact/1mrSswVXbaRLEftostDitr)
- [AWS Lambda runtimes and deprecation dates](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html), read 2026-11-16
- [ALB security policies](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/describe-ssl-policies.html)
