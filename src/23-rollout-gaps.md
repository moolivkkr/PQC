# Rollout, gaps and open items

The dated plan (waves, owners, the certificate track and decisions) is in the companion rollout plan, [artifacts/PQC-TLS-rollout-plan.md](REPO/artifacts/PQC-TLS-rollout-plan.md). This chapter gives the mechanism every wave uses and the open items.

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

## Checking a workload

- **Observed:** CloudTrail `tlsDetails.keyExchange` for its AWS API calls shows `X25519MLKEM768`, ELB logs show the same for inbound traffic, and Zeek shows no classical sessions from its hosts ([Detection](#ch-12-detection)).
- **Test endpoint:** a test server that accepts only X25519MLKEM768 (`openssl s_server -groups X25519MLKEM768 -tls1_3` with OpenSSL 3.5) fails any client that isn't PQ. Each language chapter's verify step uses it.
- **Inventory:** the component's status is `pq` or `pq-fixed`, and the Fix verification dashboard shows no classical calls for seven days ([Inventory and dashboards](#ch-13-inventory)).
