## What decides enforcement here

No single AWS control can force ML-KEM. Policy can only force the *server-side setting* (ELB / API Gateway security policy, runtime, env var, image) and then *measure* what clients actually negotiate. So enforcement is layered: the organisation blocks non-PQ settings at the API, the pipeline blocks them before deploy, the cluster blocks them at admission, and runtime logs catch the clients that still connect classically.

| Layer | Runs where | Blocks or detects | Tools on this tab |
| --- | --- | --- | --- |
| Organisation | AWS Organizations (all accounts) | Blocks API calls | SCP, RCP |
| Account (detective) | AWS Config, Security Hub, every account/Region | Detects drift | Config managed + Guard custom rules, AWS PQC Readiness Scanner pack, ELB.17, APIGateway.11, CloudFront.15 |
| Pipeline | CI (PR and deploy job), CloudFormation service | Blocks merge / deploy | cfn-guard, Guard Hook, conftest (Terraform plan, Dockerfile, SBOM), Checkov, image scripts |
| Cluster | EKS admission | Blocks or audits objects | Kyverno (1.20+ CEL and legacy), Gatekeeper |
| Runtime | CloudTrail, ELB logs, network | Detects classical handshakes | CloudTrail Lake/Athena, metric filter alarm, EventBridge, ELB log Athena, Zeek |

All rule IDs (PQ-L1 Lambda, PQ-E ECS, PQ-B ELB, PQ-A API Gateway, PQ-I image, PQ-D Dockerfile, PQ-K Kubernetes) are shared across tools so one exception ID covers every layer.

## Enforcement matrix

Evidence: **Tested** = rule ran here in a container against sample good and bad inputs (syntax + sample evaluation, not tested in AWS). **Documented** = AWS/vendor docs. Tool versions: cfn-guard 3.2.1, cfn-lint 1.60.1, conftest 0.71.1 (OPA 1.21.1), Checkov 3.4.5, Terraform 1.13 + AWS provider 6.x, Kyverno CLI 1.19.0 and 1.20.0, gator 3.20.0, Syft (latest, by digest).

| Control | What it enforces | Where | Rollout | Evidence |
| --- | --- | --- | --- | --- |
| SCP `scp-pq-tls.json` | ELB listener must name a -PQ-2025-09 policy; HTTPS/TLS listener must name a policy; no new Classic LB policies; REST API / domain must use a PQ policy | Org | Deny from day 1 on new OUs; legacy OUs after the Config window | Key `elasticloadbalancing:SecurityPolicy` Documented; `apigateway:Request/SecurityPolicy` key Documented, its behaviour on POST/PATCH Unverified; JSON Tested |
| RCP `rcp-s3-tls13.json` (optional) | Named S3 buckets refuse TLS < 1.3 (PQ needs 1.3) | Org | Per bucket, after logs show no TLS 1.2 callers | `s3:TlsVersion` Documented; JSON Tested |
| Config `ELBV2_PREDEFINED_SECURITY_POLICY_SSL_CHECK` with PQ list | ALB/NLB listener policy | Account | Detect only | Documented |
| Config `APIGATEWAY_DOMAIN_NAME_TLS_CHECK` with PQ list | REST custom domain policy | Account | Detect only | Documented |
| Config `CLOUDFRONT_SSL_POLICY_CHECK` | Viewer policy allows TLS 1.3 | us-east-1 | Detect only | Documented |
| Config custom policy rule (Guard) `lambda-pq-tls.guard` | Lambda runtime + OPENSSL_CONF / agent / GODEBUG | Account | Detect only | Tested on sample CIs; CI path `configuration.environment.variables` Unverified |
| AWS PQC Readiness Scanner (conformance pack, May 2026) | ELB + API Gateway PQ-ready / legacy TLS tiers | Org | Detect only | Documented (AWS sample, not a managed product) |
| Security Hub ELB.17, APIGateway.11, CloudFront.15 | AWS "recommended" TLS policies | Account | Detect only | Documented; ELB.17 also passes non-PQ policies |
| cfn-guard `pq-tls.guard` | Lambda (per runtime family), SAM Globals, ECS env, ELB listeners, API GW REST/domain, v2 domains | Pipeline | Warn 30 days, then fail | Tested (14 rules: good PASS, bad FAIL) |
| CloudFormation Guard Hook | Same rules, inside CloudFormation for every stack | Account | `FailureMode: WARN` then `FAIL` | Template cfn-lint Tested; hook behaviour Documented |
| conftest `terraform/pq_tls.rego` | Same rules on `terraform show -json` | Pipeline | `warn` then `deny` | Tested (10/10 unit tests; real plan: good 0, bad 5 failures) |
| Checkov custom YAML | ELB listener, Lambda runtime, Lambda OPENSSL_CONF, API GW domain | Pipeline | Soft-fail then hard-fail | Tested (good 6 pass; bad 4 fail) |
| conftest `image/openssl_sbom.rego` on Syft SBOM | System OpenSSL ≥ 3.5; AL2023 warn | Pipeline (after build) | Warn, then fail on new images | Tested on 5 images |
| `check-go-pq.sh` | Go ≥ 1.24 and no `tlsmlkem=0` in DefaultGODEBUG | Pipeline | Fail | Tested (go.mod 1.23 FAIL, 1.24 PASS) |
| `check-jdk-pq.sh` | JDK ≥ 25 or BC JSSE agent | Pipeline | Warn | Tested (Temurin 21.0.13 WARN, 25.0.5 PASS) |
| conftest `dockerfile/pq_dockerfile.rego` | Base image, GODEBUG, OPENSSL_CONF, namedGroups, crypto-policy | Pipeline (PR) | Warn on base, deny on switches | Tested (good 5 pass; bad 1 warn + 4 fail) |
| Kyverno ValidatingPolicy (1.20+) | ALB Ingress, NLB Service, ingress-nginx curves, istiod, Pod env | Cluster | `Audit` then `Deny` | Tested with CLI 1.20.0 |
| Kyverno ClusterPolicy (≤ 1.19) | Same | Cluster | `failureAction: Audit` then `Enforce` | Tested with CLI 1.19.0; rejected by 1.20.0 |
| Gatekeeper template | ALB Ingress, NLB Service | Cluster | `enforcementAction: warn` then `deny` | Tested with gator 3.20.0 |
| CloudTrail metric filter + alarm | Non-ML-KEM calls to KMS, STS, IAM, Secrets Manager, ACM, Payment Cryptography | Runtime | Alert | Pattern Documented (KMS guide), extended; cfn-lint Tested |
| CloudTrail Lake / Athena SQL | Who still calls classically | Runtime | Weekly report | Unverified (no AWS account here) |
| EventBridge rules | Listener set to non-PQ policy; API GW policy change; Config NON_COMPLIANT; hook result | Runtime | Alert | JSON Tested; patterns Unverified |
| ELB log Athena tables | Share of ML-KEM handshakes per ALB/NLB | Runtime | Weekly report + hourly metric | Regex Tested on sample lines |

## Organisation level

**SCP.** Only two services expose a TLS-policy condition key: Elastic Load Balancing (`elasticloadbalancing:SecurityPolicy` on CreateListener, ModifyListener, CreateLoadBalancerPolicy, SetLoadBalancerPoliciesOfListener) and API Gateway v1/v2 (`apigateway:Request/SecurityPolicy`, `apigateway:Resource/SecurityPolicy` on DomainNames and RestApis). CloudFront has only tag keys and IoT Core has no TLS-policy key, checked in the AWS service reference JSON on 2026-11-14 ([service authorization reference](https://docs.aws.amazon.com/service-authorization/latest/reference/reference_policies_actions-resources-contextkeys.html)). So CloudFront and IoT domain configurations can only be checked by Config and the pipeline. Documented.

The SCP has four statements: deny a listener whose named policy is not a -PQ-2025-09 policy; deny an HTTPS/TLS CreateListener with no policy (CloudFormation, CLI and CDK otherwise default to `ELBSecurityPolicy-2016-08`); deny new Classic Load Balancer listener policies (Classic cannot do TLS 1.3); deny REST API / custom domain writes whose `SecurityPolicy` is not PQ. The exception path is one role, `pq-exception-break-glass`, matching the SCP on the <?claude block lb?> tab. This org baseline allows all eleven non-TLS-1.0 PQ ELB policies during migration; that tab's four-policy SCP is the strict end state. Full text in Full configuration files.

API Gateway caveats: HTTP and WebSocket APIs support only `TLS_1_2`, so no SCP can make them PQ ([AWS](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-security-policies.html)). There is no TLS 1.3-only PQ policy for API Gateway; the PQ policies are all `SecurityPolicy_TLS13_1_2_*PQ_2025_09` ([list](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-security-policies-list.html)). Edge-optimized endpoints have no PQ-named policy; the SCP allows `SecurityPolicy_TLS13_2025_EDGE` / `SecurityPolicy_TLS12_PFS_2025_EDGE` because the viewer leg is CloudFront. Whether that leg negotiates ML-KEM for edge-optimized APIs is not confirmed. See <?claude block edge?>.

**RCP.** No IAM condition key exposes the key-exchange group (`aws:SecureTransport` is the only global TLS key). The useful RCP is `s3:TlsVersion` ≥ 1.3 on named buckets, because ML-KEM exists only in TLS 1.3. It does not force ML-KEM. Use it only for buckets whose callers are all on PQ-capable SDKs. Documented ([RCPs](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_rcps.html)).

**AWS Config managed rules** (`org-config-rules.yaml`, deploy per Region from the Config delegated admin):

| Rule | Parameter | Note |
| --- | --- | --- |
| [elbv2-predefined-security-policy-ssl-check](https://docs.aws.amazon.com/config/latest/developerguide/elbv2-predefined-security-policy-ssl-check.html) | `sslPolicies` = the 11 PQ policies | Not in me-central-1, ap-south-2, ap-southeast-4, ca-west-1, eu-south-2, eu-central-2 |
| [apigateway-domain-name-tls-check](https://docs.aws.amazon.com/config/latest/developerguide/apigateway-domain-name-tls-check.html) | `allowedSecurityPolicies` = PQ + edge policies | REST custom domains only; REST execute-api endpoints are covered by the scanner pack |
| [cloudfront-ssl-policy-check](https://docs.aws.amazon.com/config/latest/developerguide/cloudfront-ssl-policy-check.html) | `securityPolicies` = TLSv1.2_2021, TLSv1.2_2025, TLSv1.3_2025 | us-east-1 only; viewer PQ is on by default, origin leg is classical |
| [lambda-function-settings-check](https://docs.aws.amazon.com/config/latest/developerguide/lambda-function-settings-check.html) | not used | It also checks `memorySize` (default 128) and `timeout` (default 3), so most functions fail. Use the Guard custom rule instead |

**Custom Guard rule** (`lambda-pq-tls.guard`, AWS Config custom policy rule, `guard-2.x.x`): blocked runtimes (nodejs18.x/20.x, python3.8, java8, dotnet6); python3.12+/nodejs22+/dotnet8+ need `OPENSSL_CONF=/opt/pq-tls/openssl-pq*.cnf` or `AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper`; java8.al2–21 need the agent in `JAVA_TOOL_OPTIONS` or the wrapper; GODEBUG must not contain `tlsmlkem=0`. Image functions are skipped (pipeline checks the image). Before enforcing, pull one real configuration item (`aws configservice get-resource-config-history --resource-type AWS::Lambda::Function --resource-id <name> --limit 1`) and confirm environment variables appear under `configuration.environment.variables`; I could not confirm that path from docs.

**AWS PQC Readiness Scanner (May 2026).** AWS Security Blog, 2026-05-14, ["Automating post-quantum cryptography readiness using AWS Config"](https://aws.amazon.com/blogs/security/automating-post-quantum-cryptography-readiness-using-aws-config/), code at [aws-samples/sample-PQC-Readiness-using-AWS-Config](https://github.com/aws-samples/sample-PQC-Readiness-using-AWS-Config). It is a sample, not a managed rule. Four custom rules backed by two Lambda functions (`pqc-elb-pqc-compliance-*`, `pqc-elb-legacy-tls-*`, `pqc-apigateway-pqc-compliance-*`, `pqc-apigateway-legacy-tls-*`) cover ALB/NLB HTTPS/TLS listeners and REST (Regional, private), HTTP and WebSocket APIs. Tiers: 1 = TLS 1.3 only with PQ; 2 = TLS 1.2+1.3 with PQ; 3 = no PQ (high priority). CloudFront and Classic LB are out of scope. Org deploy: StackSet `pqc-readiness-lambda-functions`, then `aws configservice put-organization-conformance-pack --organization-conformance-pack-name pqc-legacy-tls-compliance` with `conformance-packs/pqc-legacy-tls-conformance-pack.yaml`. Run it alongside the managed rules: it adds REST execute-api endpoints and the tier view. Documented (blog); not deployed here.

**Security Hub.** [ELB.17](https://docs.aws.amazon.com/securityhub/latest/userguide/elb-controls.html#elb-17) uses the same Config rule with a fixed list that includes non-PQ policies (`ELBSecurityPolicy-TLS13-1-3-2021-06`, FIPS 2023, RFC9151), so PASS does not mean PQ. [APIGateway.11](https://docs.aws.amazon.com/securityhub/latest/userguide/apigateway-controls.html) allows `SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09` but also non-PQ TLS 1.3 policies. [CloudFront.15](https://docs.aws.amazon.com/securityhub/latest/userguide/cloudfront-controls.html) wants TLSv1.2_2025 or TLSv1.3_2025. Keep them on; use the Config rules above (customised lists) as the PQ signal. Documented.

**Firewall Manager.** Its policy types are WAF, Shield Advanced, security groups, network ACLs, Network Firewall, DNS Firewall and third-party firewalls ([AWS](https://docs.aws.amazon.com/waf/latest/developerguide/working-with-policies.html)). None sets an ELB, API Gateway or CloudFront TLS policy, so FMS has no PQ role beyond deploying Network Firewall (see <?claude block net?>). Documented.

## Pipeline

Run every check on the PR (fast feedback) and again in the deploy job (the gate). Order: Dockerfile lint → build → SBOM + binary checks → IaC (cfn-guard / conftest / Checkov) → CloudFormation Guard Hook in the account as the last line.

**cfn-guard** (`pq-tls.guard`, 14 rules): `cfn-guard validate --rules pq-tls.guard --data template.yaml --show-summary fail`. Per runtime family: blocked runtimes fail (PQ-L1, including SAM `Globals.Function.Runtime`); OpenSSL 3.5 runtimes need the config or wrapper (PQ-L2); JDK 8–21 need the agent (PQ-L3); python3.9–3.11 without the wrapper is a separate warn rule (PQ-L4); GODEBUG `tlsmlkem=0` fails (PQ-L5). ECS: GODEBUG off, `jdk.tls.namedGroups` without X25519MLKEM768, `OPENSSL_CONF=/dev/null` (PQ-E1–E3). ELB: HTTPS/TLS listener must set `SslPolicy` from the PQ list (PQ-B1/B2). API Gateway: Regional/Private REST domain and API need a `*_PQ_2025_09` policy and `EndpointAccessMode` (PQ-A1–A3); HTTP/WebSocket domains need a `PqTlsException` tag (PQ-A4). For warn-then-fail, run PQ-L4 and PQ-A4 in a separate non-blocking step.

**CloudFormation Guard Hook** (`guard-hook.yaml`): `AWS::CloudFormation::GuardHook` reading the same rule file from S3, `TargetOperations: [RESOURCE, STACK]`, `FailureMode: WARN` for the warn window, then `FAIL`. Deploy with a service-managed StackSet. This catches console and ad-hoc stacks that skip CI. Documented ([GuardHook](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-cloudformation-guardhook.html)).

**OPA / conftest for Terraform** (`terraform/pq_tls.rego`): `terraform plan -out plan.out && terraform show -json plan.out > plan.json && conftest test --policy rules/opa/terraform --namespace terraform.pq_tls plan.json`. Same rule IDs. Exceptions: tag `pq-tls-exception = "EXC-nnnn"`. The AWS provider 6.x accepted `security_policy = "SecurityPolicy_TLS13_1_2_PQ_2025_09"` and `endpoint_access_mode = "BASIC"` on `aws_api_gateway_domain_name` in a real offline plan (Tested).

**Checkov** (`rules/checkov/pq_tls_[1-4].yaml`, one policy per file): `checkov -d . --framework terraform --external-checks-dir rules/checkov --check CKV2_PQTLS_1,CKV2_PQTLS_2,CKV2_PQTLS_3,CKV2_PQTLS_4`. Use it if Checkov is already your scanner; conftest covers more (ECS JSON, exceptions, warn level).

**Container images.**
- OpenSSL in the image: `syft <image> -o syft-json > sbom.json` then `conftest test --policy rules/opa/image --namespace image.openssl sbom.json`. Fails libssl/openssl < 3.5 (PQ-I1), warns on no system OpenSSL (PQ-I2: check the language runtime instead) and on AL2023 (PQ-I3: needs `DEFAULT:PQ` or the conf).
- Go binaries: `check-go-pq.sh <binary>...` runs `go version -m` and fails toolchain < 1.24 or `tlsmlkem=0` in DefaultGODEBUG. It cannot see an explicit `CurvePreferences` in code; add a source grep: `grep -rn 'CurvePreferences' --include=*.go .` and require X25519MLKEM768 in any hit (see <?claude block go?>).
- JDK: `check-jdk-pq.sh <image>` reads the JDK `release` file without running the image; JDK ≥ 25 passes, 8–21 warns unless `JAVA_TOOL_OPTIONS` loads the agent (see <?claude block java?>).

**Dockerfile lint** (`dockerfile/pq_dockerfile.rego`, conftest's native Dockerfile parser): warns on classical base images (debian:bookworm, ubuntu 22.04/24.04, node:18/20, python ≤ 3.11, golang ≤ 1.23, JDK 17/21 images, amazonlinux:2); denies `ENV GODEBUG=...tlsmlkem=0`, `OPENSSL_CONF=/dev/null`, `jdk.tls.namedGroups` without X25519MLKEM768, and `update-crypto-policies --set DEFAULT` without `:PQ`. hadolint has no custom-rule mechanism, so the rule lives in conftest.

## Kubernetes

Kyverno 1.20 no longer runs `kyverno.io/v1` ClusterPolicy: the 1.20.0 CLI rejected it with "Kyverno v1.20 removed execution of legacy kyverno.io policy types … Migrate to ValidatingPolicy" (Tested, see [migration guide](https://kyverno.io/docs/guides/migration-to-cel/)). So there are two files: `kyverno-pq-tls-cel.yaml` (ValidatingPolicy, CEL, `policies.kyverno.io/v1`) for 1.20+ and `kyverno-pq-tls.yaml` (ClusterPolicy) for ≤ 1.19.

| Policy | Object | Check |
| --- | --- | --- |
| PQ-K1 | Ingress, class `alb`, with a certificate | `alb.ingress.kubernetes.io/ssl-policy` in the PQ list (controller default is ELBSecurityPolicy-2016-08) |
| PQ-K2 | Service `LoadBalancer` with `aws-load-balancer-ssl-cert` | `service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy` in the PQ list |
| PQ-K3 | ConfigMap `ingress-nginx-controller` | `ssl-ecdh-curve` starts with `X25519MLKEM768`; only works when the controller image links OpenSSL 3.5 (see <?claude block web?>) |
| PQ-K4/K5 | istiod Deployment, ztunnel DaemonSet | env `COMPLIANCE_POLICY=pqc` (Istio 1.27+, see <?claude block mesh?>) |
| PQ-K6/K7 | Pod | no `GODEBUG` with `tlsmlkem=0`, no `OPENSSL_CONF=/dev/null` |

Exception: annotation `pq-tls.example.com/exception: EXC-nnnn` on K1/K2 objects. Rollout: `validationActions: [Audit]` (ClusterPolicy `failureAction: Audit`), read PolicyReports for 30 days, then `[Deny]` / `Enforce`. In the CEL version a Pod that breaks both K6 and K7 reports only the first failed validation per policy.

**Gatekeeper alternative** (`gatekeeper-pq-tls.yaml`): ConstraintTemplate `K8sPqTlsElbPolicy` with the PQ list as a parameter covers K1/K2; `enforcementAction: warn`, then `deny`. Extend the same Rego for K3–K7 if Gatekeeper is your admission controller.

## Runtime detection and alerting

**CloudTrail** records `tlsDetails.keyExchange` only for KMS, STS, IAM, Secrets Manager, ACM and Payment Cryptography; calls a service makes on your behalf have no `tlsDetails` (exclude them with `userIdentity.invokedBy`). The alarm (`cloudtrail-alarm.yaml`) extends the metric filter from the [KMS guide](https://docs.aws.amazon.com/kms/latest/developerguide/pqtls.html) to all six services: `keyExchange != "*MLKEM*"` or missing, Sum ≥ 1 per hour. `cloudtrail-non-pq.sql` lists the callers (principal, user agent, source IP) for CloudTrail Lake and for Athena; the stock Athena CloudTrail DDL needs `keyexchange:STRING` added to the `tlsdetails` struct. See <?claude block aws?> for which endpoints negotiate PQ.

**EventBridge** (`eventbridge-rules.json`): listener created/modified with a non-PQ `sslPolicy`; any API Gateway domain/API create or update (re-check with Config); Config NON_COMPLIANT for `pq-tls-*` rules; Guard Hook invocations. Patterns are valid JSON; the `anything-but`/`wildcard` match and the Hook event detail-type are not confirmed against live events.

**ALB and NLB logs** (`elb-logs-athena.sql`): ALB connection logs field 13 and NLB TLS access logs field 17 hold `tls_keyexchange` ([ALB](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-connection-logs.html), [NLB](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-access-logs.html)). The file has table DDL, per-LB share of ML-KEM, top classical clients, and an hourly count to publish as a CloudWatch metric (EventBridge Scheduler → Step Functions → Athena → PutMetricData) with an alarm on the classical share. ALB access logs (not connection logs) do not carry key exchange. CloudFront: the `CloudFront-Viewer-TLS-Details` origin request header includes the key exchange (Documented, see <?claude block edge?>).

**Zeek** on a traffic mirror or Network Firewall sees `ssl.log` named groups for east-west and egress flows that no AWS log covers. Alert on TLS 1.3 sessions whose group is not X25519MLKEM768 for destinations on the PQ-required list. Configuration on <?claude block net?>.

## Warn-then-fail rollout

1. **Week 0 – inventory.** Deploy Config rules, scanner pack, CloudTrail alarm in notify-only mode, ELB log tables. Pipeline checks run in warn mode (cfn-guard non-blocking step, conftest `warn`, Checkov `--soft-fail`, Guard Hook `WARN`, Kyverno `Audit`).
2. **Week 2 – block new risk.** SCP on sandbox and new-workload OUs. Pipeline fails on *new* resources (diff-aware: only resources in the change set).
3. **Week 6 – block everything in CI.** Fail the pipeline on all resources; open exceptions for the rest. Guard Hook `FAIL`. Kyverno `Deny`.
4. **Week 8 – org-wide SCP.** Attach to all workload OUs once Config shows zero non-compliant listeners outside exceptions.
5. **Ongoing.** Classical-share metric per LB trends to the exception list only; RCP per bucket when its logs show TLS 1.3 only.

Each step is reversible by flipping the mode (WARN, Audit, soft-fail) or detaching the SCP; no resource changes.

## Exception register

One register (a table in the GRC tool or a repo file) keyed by `EXC-nnnn`; the same ID appears as tag `pq-tls-exception` (Terraform/CloudFormation; `PqTlsException` where a hyphen is not allowed), annotation `pq-tls.example.com/exception` (Kubernetes), and the `pq-exception-break-glass` role session tag for SCP bypass.

| Field | Content |
| --- | --- |
| ID | EXC-nnnn |
| Rule IDs | e.g. PQ-B2, PQ-A4 |
| Resource ARNs / paths | Exact resources; no wildcards |
| Reason | e.g. HTTP API (TLS_1_2 only), partner client on TLS 1.2, Lambda nodejs20.x pending migration |
| Data sensitivity / harvest-now-decrypt-later exposure | Confidentiality lifetime of data on this path |
| Compensating control | e.g. CloudFront in front, VPN, short-lived data |
| Owner and approver | Team + security approver |
| Created / expires | Max 90 days; 180 for vendor-blocked items |
| Exit plan | Target fix and date |
| Evidence link | Ticket, client inventory, log query |

Review: monthly by the platform security lead (expired → pipeline fails again automatically because the tag value is checked against the register in the nightly sync); quarterly report of count and age. No renewal without a new exit date.

## Verify

All runs on 2026-11-14 in containers on this machine; scripts and outputs are in the work dir (`run-cfn-guard.sh`, `run-image-checks.sh`, `out/*.out`). These are syntax and sample evaluations, not tests in AWS.

| Check | Inputs | Result |
| --- | --- | --- |
| cfn-guard 3.2.1 `pq-tls.guard` | cfn-good.yaml / cfn-bad.yaml / sam-bad.yaml | good PASS (9 pass, 5 skip); bad FAIL (11 fail); SAM FAIL (Globals + py legacy) |
| cfn-guard Config rule | 5 sample configuration items | good PASS; 4 bad each FAIL on the expected rule |
| cfn-lint 1.60.1 | org-config-rules, guard-hook, cloudtrail-alarm, samples | 0 errors (it caught `PolicyRuntime` → `Runtime`, fixed) |
| conftest verify | 10 Rego unit tests | 10/10 pass |
| conftest on real Terraform plan JSON | tf-good / tf-bad | good 0 failures; bad 5 (A1, B2, E1, L1, L2) |
| Checkov 3.4.5 custom | tf-good / tf-bad | good 6 pass; bad 4 fail |
| Syft + conftest SBOM | trixie-slim, bookworm-slim, python:3.11-slim-bookworm, alpine:3.22, amazonlinux:2023 | trixie/alpine pass; python 3.11 bookworm FAIL (libssl3 3.0.22); bookworm-slim WARN (no libssl); AL2023 WARN |
| check-go-pq.sh | go.mod `go 1.23` / `go 1.24`, built with Go 1.25 | 1.23 FAIL (`tlsmlkem=0`); 1.24 PASS |
| check-jdk-pq.sh | eclipse-temurin 21-jre-alpine / 25-jre-alpine | 21.0.13 WARN; 25.0.5 PASS |
| conftest Dockerfile | Dockerfile.good / .bad | good 5 pass; bad 1 warn + 4 fail |
| Kyverno CLI 1.20.0 CEL | good.yaml / bad.yaml (5 objects each) | good 6 pass; bad 5 fail |
| Kyverno CLI 1.19.0 ClusterPolicy | same | good 6 pass; bad 6 fail |
| gator 3.20.0 | same | good 0 violations; bad 2 (K1, K2) |
| JSON + size | SCP, RCP, EventBridge | valid; SCP 2,393 chars minified (< 5,120 limit) |
| Athena regex | ALB/NLB sample lines (Python `re`) | all match; `tls_keyexchange` extracted |

To verify in an account: deploy in a sandbox, create one non-PQ listener and confirm (1) the SCP returns AccessDenied, (2) the Guard Hook warns, (3) Config marks it NON_COMPLIANT within minutes, (4) the EventBridge rule fires.

## Pitfalls and rollback

- CloudFormation, CLI and CDK default ELB listeners to `ELBSecurityPolicy-2016-08`; the console defaults to `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`. Require an explicit policy.
- Security Hub ELB.17 and APIGateway.11 pass non-PQ TLS 1.3 policies. Do not report them as PQ coverage.
- `lambda-function-settings-check` also checks memory and timeout; it marks most functions non-compliant.
- A PQ server policy does not mean PQ traffic: clients must offer ML-KEM. Measure with logs.
- Kyverno 1.20 silently changes the policy kind you need; pin the policy file to the Kyverno version.
- The SCP API Gateway statement depends on `apigateway:Request/SecurityPolicy` being populated on POST/PATCH; test in a sandbox OU before attaching widely.
- Config custom Guard rules use Guard 2.x; keep them free of 3.x-only syntax.
- `amazonlinux:2` prefix matching would catch `amazonlinux:2023`; the Dockerfile rule matches on tag boundaries for that reason.
- Rollback: detach the SCP (minutes), set Guard Hook `FailureMode: WARN`, Kyverno `Audit`, conftest rules to `warn`. Config rules are detect-only and need no rollback.

## Sources

[AWS PQC Readiness blog (2026-05-14)](https://aws.amazon.com/blogs/security/automating-post-quantum-cryptography-readiness-using-aws-config/) · [ALB security policies](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/describe-ssl-policies.html) · [NLB security policies](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/describe-ssl-policies.html) · [API Gateway security policies](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-security-policies.html) · [Security Hub ELB controls](https://docs.aws.amazon.com/securityhub/latest/userguide/elb-controls.html) · [GuardHook](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-cloudformation-guardhook.html) · [KMS hybrid PQ TLS](https://docs.aws.amazon.com/kms/latest/developerguide/pqtls.html) · [Firewall Manager policy types](https://docs.aws.amazon.com/waf/latest/developerguide/working-with-policies.html) · [RCPs](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_rcps.html) · [Kyverno CEL migration](https://kyverno.io/docs/guides/migration-to-cel/)
