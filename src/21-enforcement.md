# Enforcement and guardrails

## What decides enforcement here

No single AWS control can force ML-KEM. Policy can only force the *server-side setting* (ELB / API Gateway security policy, runtime, env var, image) and then *measure* what clients actually negotiate. So enforcement is layered: the organisation blocks non-PQ settings at the API, the pipeline blocks them before deploy, the cluster blocks them at admission, and runtime logs catch the clients that still connect classically.

| Layer | Runs where | Blocks or detects | Tools on this tab |
| --- | --- | --- | --- |
| Organisation | AWS Organizations (all accounts) | Blocks API calls | SCP, RCP |
| Account (detective) | AWS Config, Security Hub, every account/Region | Detects drift | Config managed + Guard custom rules, AWS PQC Readiness Scanner pack, ELB.17, APIGateway.11, CloudFront.15 |
| Pipeline | CI (PR and deploy job), CloudFormation service | Blocks merge / deploy | cfn-guard, Guard Hook, conftest (Terraform plan, Dockerfile, SBOM), Checkov, image scripts |
| Cluster | EKS admission | Blocks or audits objects | Kyverno (1.20+ CEL and legacy), Gatekeeper |
| Runtime | CloudTrail, ELB logs, network | Detects classical handshakes | CloudTrail Lake/Athena, metric filter alarm, EventBridge, ELB log Athena, Zeek |

Rule IDs are shared across tools (PQ-L Lambda, PQ-E ECS, PQ-B ELB, PQ-A API Gateway, PQ-I image, PQ-D Dockerfile, PQ-K Kubernetes), so one exception ID covers every layer.

## Enforcement matrix

Evidence: **Tested** = the rule ran here in a container against sample good and bad inputs (syntax + sample evaluation, not tested in AWS). **Documented** = AWS or vendor docs. Tool versions: cfn-guard 3.2.1, cfn-lint 1.60.1, conftest 0.71.1 (OPA 1.21.1), Checkov 3.4.5, Terraform 1.13 + AWS provider 6.x, Kyverno CLI 1.19.0 and 1.20.0, gator 3.20.0, Syft (pinned by digest).

| Control | What it enforces | Where | Rollout | Evidence |
| --- | --- | --- | --- | --- |
| SCP `scp-pq-tls.json` | ELB listener names a -PQ-2025-09 policy; HTTPS/TLS listener must name a policy; no new Classic LB listener policies; REST API / domain uses a PQ policy | Org | New OUs first; all workload OUs after the Config window | `elasticloadbalancing:SecurityPolicy` Documented; `apigateway:Request/SecurityPolicy` key Documented, behaviour on POST/PATCH Unverified; JSON Tested |
| RCP `rcp-s3-tls13.json` (optional) | Named S3 buckets refuse TLS below 1.3 (PQ needs 1.3) | Org | Per bucket, after logs show no TLS 1.2 callers | `s3:TlsVersion` Documented; JSON Tested |
| Config `ELBV2_PREDEFINED_SECURITY_POLICY_SSL_CHECK` + PQ list | ALB/NLB listener policy | Account | Detect only | Documented |
| Config `APIGATEWAY_DOMAIN_NAME_TLS_CHECK` + PQ list | REST custom domain policy | Account | Detect only | Documented |
| Config `CLOUDFRONT_SSL_POLICY_CHECK` | Viewer policy allows TLS 1.3 | us-east-1 | Detect only | Documented |
| Config custom Guard rule `lambda-pq-tls.guard` | Lambda runtime + OPENSSL\_CONF / agent / GODEBUG | Account | Detect only | Tested on sample configuration items; CI path Unverified |
| AWS PQC Readiness Scanner (May 2026) | ELB + API Gateway PQ tiers and legacy TLS | Org | Detect only | Documented (AWS sample, not managed) |
| Security Hub ELB.17, APIGateway.11, CloudFront.15 | AWS "recommended" TLS policies | Account | Detect only | Documented; they also pass non-PQ policies |
| cfn-guard `pq-tls.guard` | Lambda per runtime family, SAM Globals, ECS env, ELB listeners, API GW REST/domain, v2 domains | Pipeline | Warn 30 days, then fail | Tested (14 rules) |
| CloudFormation Guard Hook | Same rules inside CloudFormation for every stack | Account | `FailureMode: WARN` then `FAIL` | Template Tested (cfn-lint); behaviour Documented |
| conftest `terraform/pq_tls.rego` | Same rules on Terraform plan JSON | Pipeline | `warn` then `deny` | Tested (10/10 unit tests; real plan) |
| Checkov custom YAML | ELB listener, Lambda runtime, Lambda OPENSSL\_CONF, API GW domain | Pipeline | Soft-fail then hard-fail | Tested |
| conftest `image/openssl_sbom.rego` on Syft SBOM | System OpenSSL 3.5 or later; AL2023 warning | Pipeline (after build) | Warn, then fail on new images | Tested on 5 images |
| `check-go-pq.sh` | Go 1.24+ and no `tlsmlkem=0` in DefaultGODEBUG | Pipeline | Fail | Tested |
| `check-jdk-pq.sh` | JDK 25+ or Bouncy Castle JSSE agent | Pipeline | Warn | Tested |
| conftest `dockerfile/pq_dockerfile.rego` | Base image, GODEBUG, OPENSSL\_CONF, namedGroups, crypto-policy | Pipeline (PR) | Warn on base, deny on switches | Tested |
| Kyverno ValidatingPolicy (1.20+) | ALB Ingress, NLB Service, ingress-nginx curves, istiod, Pod env | Cluster | `Audit` then `Deny` | Tested (CLI 1.20.0) |
| Kyverno ClusterPolicy (1.19 and older) | Same | Cluster | `Audit` then `Enforce` | Tested (CLI 1.19.0); rejected by 1.20.0 |
| Gatekeeper template | ALB Ingress, NLB Service | Cluster | `warn` then `deny` | Tested (gator 3.20.0) |
| CloudTrail metric filter + alarm | Non-ML-KEM calls to KMS, STS, IAM, Secrets Manager, ACM, Payment Cryptography | Runtime | Alert | Pattern Documented (KMS guide), extended; template Tested (cfn-lint) |
| CloudTrail Lake / Athena SQL | Who still calls classically | Runtime | Weekly report | Unverified (no AWS account here) |
| EventBridge rules | Non-PQ listener; API GW policy change; Config NON\_COMPLIANT; hook result | Runtime | Alert | JSON Tested; patterns Unverified |
| ELB log Athena tables | Share of ML-KEM handshakes per ALB/NLB | Runtime | Weekly report + hourly metric | Regex Tested on sample lines |

## Organisation level

**SCP.** Only two services expose a TLS-policy condition key: Elastic Load Balancing (`elasticloadbalancing:SecurityPolicy` on CreateListener, ModifyListener, CreateLoadBalancerPolicy and SetLoadBalancerPoliciesOfListener, not CreateLoadBalancer) and API Gateway (`apigateway:Request/SecurityPolicy` and `apigateway:Resource/SecurityPolicy` on DomainNames and RestApis). CloudFront has only tag keys and IoT Core has no TLS-policy key. Checked in the AWS programmatic service reference on 2026-11-14 ([service authorization reference](https://docs.aws.amazon.com/service-authorization/latest/reference/reference_policies_actions-resources-contextkeys.html)). So CloudFront and IoT domain configurations can only be checked by Config and the pipeline. Documented.

The SCP has four statements:

1. Deny CreateListener/ModifyListener when the named policy is not a -PQ-2025-09 policy (TLS 1.0 PQ variants excluded).
2. Deny an HTTPS/TLS CreateListener with no policy. CloudFormation, CLI and CDK otherwise default to `ELBSecurityPolicy-2016-08`.
3. Deny new Classic Load Balancer listener policies (Classic cannot do TLS 1.3).
4. Deny REST API / custom domain writes whose `SecurityPolicy` is not a PQ policy.

The bypass is one role, `pq-exception-break-glass`, the same as the SCP on the Load balancers tab. This org baseline allows all eleven non-TLS-1.0 PQ ELB policies during migration; that tab's four-policy SCP is the next stage (TLS 1.2+1.3 restricted PQ and TLS 1.3-only PQ, plus FIPS). The end state, once TLS 1.2 traffic is zero, allows only the TLS 1.3-only PQ policies (ELBSecurityPolicy-TLS13-1-3-PQ-2025-09 and its FIPS variant). Read the two allowlists as stages, not a conflict. Full text in Full configuration files.

API Gateway limits: HTTP and WebSocket APIs support only `TLS_1_2`, so no SCP can make them PQ ([AWS](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-security-policies.html)). There is no TLS 1.3-only PQ policy; all PQ policies are `SecurityPolicy_TLS13_1_2_*PQ_2025_09` ([list](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-security-policies-list.html)). Edge-optimized endpoints have no PQ-named policy; the SCP allows `SecurityPolicy_TLS13_2025_EDGE` and `SecurityPolicy_TLS12_PFS_2025_EDGE` because the viewer leg is CloudFront. Whether that leg negotiates ML-KEM for edge-optimized APIs is not confirmed; see Edge and API front doors.

**RCP.** No IAM condition key exposes the key-exchange group; `aws:SecureTransport` is the only global TLS key. The useful RCP is `s3:TlsVersion` of 1.3 or higher on named buckets, because ML-KEM exists only in TLS 1.3. It does not force ML-KEM. Use it only for buckets whose callers all run PQ-capable SDKs ([RCPs](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_rcps.html)). Documented.

**AWS Config managed rules** (`org-config-rules.yaml`, deployed per Region from the Config delegated administrator):

| Rule | Parameter | Note |
| --- | --- | --- |
| [elbv2-predefined-security-policy-ssl-check](https://docs.aws.amazon.com/config/latest/developerguide/elbv2-predefined-security-policy-ssl-check.html) | `sslPolicies` = the 11 PQ policies | Not available in me-central-1, ap-south-2, ap-southeast-4, ca-west-1, eu-south-2, eu-central-2 |
| [apigateway-domain-name-tls-check](https://docs.aws.amazon.com/config/latest/developerguide/apigateway-domain-name-tls-check.html) | `allowedSecurityPolicies` = PQ + edge policies | REST custom domains only; execute-api endpoints are covered by the scanner pack |
| [cloudfront-ssl-policy-check](https://docs.aws.amazon.com/config/latest/developerguide/cloudfront-ssl-policy-check.html) | `securityPolicies` = TLSv1.2\_2021, TLSv1.2\_2025, TLSv1.3\_2025 | us-east-1 only; viewer PQ is on by default, origin leg is classical |
| [lambda-function-settings-check](https://docs.aws.amazon.com/config/latest/developerguide/lambda-function-settings-check.html) | Not used | It also checks `memorySize` (default 128) and `timeout` (default 3), so most functions fail; use the Guard rule below |

**Custom Guard rule** (`lambda-pq-tls.guard`, Config custom policy rule, runtime `guard-2.x.x`): blocks nodejs18.x/20.x, python3.8, java8, dotnet6; python3.12+, nodejs22+ and dotnet8+ need `OPENSSL_CONF` set to `/var/task/pq-tls/openssl-pq*.cnf` (bundled) or `/opt/pq-tls/openssl-pq*.cnf` (layer), or `AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper`; java8.al2 to java21 need the agent in `JAVA_TOOL_OPTIONS` or the wrapper; GODEBUG must not contain `tlsmlkem=0`. Image functions are skipped (the pipeline checks the image). Before enforcing, pull one real configuration item (`aws configservice get-resource-config-history --resource-type AWS::Lambda::Function --resource-id <name> --limit 1`) and confirm the variables sit under `configuration.environment.variables`; I could not confirm that path from docs.

**AWS PQC Readiness Scanner (May 2026).** AWS Security Blog, 2026-05-14, [Automating post-quantum cryptography readiness using AWS Config](https://aws.amazon.com/blogs/security/automating-post-quantum-cryptography-readiness-using-aws-config/); code at [aws-samples/sample-PQC-Readiness-using-AWS-Config](https://github.com/aws-samples/sample-PQC-Readiness-using-AWS-Config). It is a sample, not a managed rule. Four custom rules on two Lambda functions (`pqc-elb-pqc-compliance-*`, `pqc-elb-legacy-tls-*`, `pqc-apigateway-pqc-compliance-*`, `pqc-apigateway-legacy-tls-*`) cover ALB/NLB HTTPS/TLS listeners and REST (Regional, private), HTTP and WebSocket APIs. Tier 1 = TLS 1.3 only with PQ; Tier 2 = TLS 1.2 + 1.3 with PQ; Tier 3 = no PQ (high priority). CloudFront and Classic LB are out of scope. Org deploy: StackSet `pqc-readiness-lambda-functions`, then `aws configservice put-organization-conformance-pack --organization-conformance-pack-name pqc-legacy-tls-compliance` with `conformance-packs/pqc-legacy-tls-conformance-pack.yaml`. Run it next to the managed rules: it adds execute-api endpoints and the tier view. Documented (blog); not deployed here.

**Security Hub.** [ELB.17](https://docs.aws.amazon.com/securityhub/latest/userguide/elb-controls.html) uses the same Config rule with a fixed list that includes non-PQ policies (`ELBSecurityPolicy-TLS13-1-3-2021-06`, FIPS 2023, RFC9151), so PASS does not mean PQ. [APIGateway.11](https://docs.aws.amazon.com/securityhub/latest/userguide/apigateway-controls.html) allows `SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09` but also non-PQ TLS 1.3 policies. [CloudFront.15](https://docs.aws.amazon.com/securityhub/latest/userguide/cloudfront-controls.html) wants TLSv1.2\_2025 or TLSv1.3\_2025. Keep them on; use the customised Config rules as the PQ signal. Documented.

**Firewall Manager.** Its policy types are WAF, Shield Advanced, security groups, network ACLs, Network Firewall, DNS Firewall and third-party firewalls ([AWS](https://docs.aws.amazon.com/waf/latest/developerguide/working-with-policies.html)). None sets an ELB, API Gateway or CloudFront TLS policy, so FMS has no PQ role beyond rolling out Network Firewall (see Network devices and egress). Documented.

## Pipeline

Run every check on the PR (fast feedback) and again in the deploy job (the gate). Order: Dockerfile lint, build, SBOM and binary checks, IaC checks (cfn-guard / conftest / Checkov), then the CloudFormation Guard Hook in the account as the last line.

**cfn-guard** (`pq-tls.guard`, 14 rules): `cfn-guard validate --rules pq-tls.guard --data template.yaml --show-summary fail`.

| Rule | Resource | Check |
| --- | --- | --- |
| PQ-L1 | Lambda, SAM function, SAM `Globals.Function.Runtime` | Runtime not nodejs18.x/20.x, python3.8, java8, dotnet6 |
| PQ-L2 | Lambda python3.12-3.14, nodejs22/24, dotnet8/10 | `OPENSSL_CONF` = `/var/task/pq-tls/` or `/opt/pq-tls/` `openssl-pq*.cnf`, or `AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper` |
| PQ-L3 | Lambda java8.al2, java11/17/21 | `JAVA_TOOL_OPTIONS` loads `pq-tls-agent.jar`, or the wrapper |
| PQ-L4 (warn) | Lambda python3.9-3.11 | Wrapper set (shim covers urllib3/botocore only) |
| PQ-L5 | Lambda | GODEBUG has no `tlsmlkem=0` |
| PQ-E1-E3 | ECS task definition | No GODEBUG `tlsmlkem=0`; `jdk.tls.namedGroups` includes X25519MLKEM768; no `OPENSSL_CONF=/dev/null` |
| PQ-B1/B2 | ELBv2 listener HTTPS/TLS | `SslPolicy` present and in the PQ list |
| PQ-A1-A3 | API GW REST domain and API (Regional/Private) | `*_PQ_2025_09` policy and `EndpointAccessMode` set |
| PQ-A4 | API GW v2 domain | Tag `PqTlsException` (HTTP/WebSocket cannot be PQ) |

For warn-then-fail, run PQ-L4 and PQ-A4 (or the whole file during the warn window) in a non-blocking step.

**CloudFormation Guard Hook** (`guard-hook.yaml`): `AWS::CloudFormation::GuardHook` reads the same rule file from S3, `TargetOperations: [RESOURCE, STACK]`, `FailureMode: WARN` during the warn window, then `FAIL`. Deploy with a service-managed StackSet. It catches console and ad-hoc stacks that skip CI ([GuardHook](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-cloudformation-guardhook.html)). Documented; the template passes cfn-lint.

**OPA / conftest for Terraform** (`terraform/pq_tls.rego`):

```bash
terraform plan -out plan.out
terraform show -json plan.out > plan.json
conftest test --policy rules/opa/terraform --namespace terraform.pq_tls plan.json
```

Same rule IDs. Exceptions: tag `pq-tls-exception = "EXC-nnnn"`. The AWS provider 6.x accepted `security_policy = "SecurityPolicy_TLS13_1_2_PQ_2025_09"` and `endpoint_access_mode = "BASIC"` on `aws_api_gateway_domain_name` in a real offline plan (Tested).

**Checkov** (`rules/checkov/pq_tls_1.yaml` to `_4.yaml`, one policy per file): `checkov -d . --framework terraform --external-checks-dir rules/checkov --check CKV2_PQTLS_1,CKV2_PQTLS_2,CKV2_PQTLS_3,CKV2_PQTLS_4`. Use it if Checkov is already your scanner; conftest covers more (ECS JSON, exceptions, warn level).

**Container images.**

- OpenSSL in the image: `syft <image> -o syft-json > sbom.json`, then `conftest test --policy rules/opa/image --namespace image.openssl sbom.json`. Fails libssl/openssl below 3.5 (PQ-I1), warns when no system OpenSSL is present (PQ-I2: check the language runtime instead) and on Amazon Linux 2023 (PQ-I3: needs `DEFAULT:PQ` or the conf).
- Go binaries: `check-go-pq.sh <binary>...` runs `go version -m` and fails a toolchain below 1.24 or `tlsmlkem=0` in DefaultGODEBUG. 1.24 is the PQ floor (X25519MLKEM768 by default), so the check fails only binaries with no PQ; the Go tab's target, 1.26 with `go 1.26`, adds the two NIST hybrids and is still in support. Raise the floor to 1.26 when the fleet allows. It cannot see an explicit `CurvePreferences` in code; add `grep -rn 'CurvePreferences' --include=*.go .` and require X25519MLKEM768 in every hit (see Go).
- JDK: `check-jdk-pq.sh <image>` reads the JDK `release` file without running the image; JDK 25+ passes, 8-21 warns unless `JAVA_TOOL_OPTIONS` loads the agent (see Java).

**Dockerfile lint** (`dockerfile/pq_dockerfile.rego`, conftest's built-in Dockerfile parser): warns on classical base images (debian:bookworm, ubuntu 22.04/24.04, node:18/20 and Node tags pinned below 22.20 / 24.5, python `-bookworm`/`-bullseye` tags (default python tags are trixie and PQ), golang 1.22/1.23, JDK 17/21 images, amazonlinux:2); denies `ENV GODEBUG=...tlsmlkem=0`, `OPENSSL_CONF=/dev/null`, `jdk.tls.namedGroups` without X25519MLKEM768, and `update-crypto-policies --set DEFAULT` without `:PQ`. hadolint has no custom-rule mechanism, so this rule lives in conftest:

```bash
conftest test --parser dockerfile --policy rules/opa/dockerfile --namespace dockerfile.pq_tls Dockerfile
```

## Kubernetes

Kyverno 1.20 no longer runs `kyverno.io/v1` ClusterPolicy. The 1.20.0 CLI rejected it with "Kyverno v1.20 removed execution of legacy kyverno.io policy types … Migrate to ValidatingPolicy" (Tested; see the [migration guide](https://kyverno.io/docs/guides/migration-to-cel/)). So there are two files: `kyverno-pq-tls-cel.yaml` (ValidatingPolicy, CEL, `policies.kyverno.io/v1`) for 1.20+, and `kyverno-pq-tls.yaml` (ClusterPolicy) for 1.19 and older.

| Policy | Object | Check |
| --- | --- | --- |
| PQ-K1 | Ingress, class `alb`, with a certificate | `alb.ingress.kubernetes.io/ssl-policy` in the PQ list (controller default is ELBSecurityPolicy-2016-08) |
| PQ-K2 | Service `LoadBalancer` with `aws-load-balancer-ssl-cert` | `service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy` in the PQ list |
| PQ-K3 | ConfigMap `ingress-nginx-controller` | `ssl-ecdh-curve` starts with `X25519MLKEM768`; works only when the controller image links OpenSSL 3.5 (see Web servers and proxies) |
| PQ-K4/K5 | istiod Deployment, ztunnel DaemonSet | env `COMPLIANCE_POLICY=pqc` (Istio 1.27+, see Service mesh) |
| PQ-K6/K7 | Pod | No `GODEBUG` with `tlsmlkem=0`, no `OPENSSL_CONF=/dev/null` |

Exception: annotation `pq-tls.example.com/exception: EXC-nnnn` on K1/K2 objects. Rollout: `validationActions: [Audit]` (ClusterPolicy `failureAction: Audit`), read PolicyReports for 30 days, then `[Deny]` / `Enforce`. In the CEL version a Pod that breaks both K6 and K7 reports only the first failed validation of that policy.

**Gatekeeper alternative** (`gatekeeper-pq-tls.yaml`): ConstraintTemplate `K8sPqTlsElbPolicy` with the PQ list as a parameter covers K1/K2; start with `enforcementAction: warn`, then `deny`. Extend the same Rego for K3-K7 if Gatekeeper is your admission controller.

## Runtime detection and alerting

**CloudTrail** records `tlsDetails.keyExchange` only for KMS, STS, IAM, Secrets Manager, ACM and Payment Cryptography. Calls a service makes on your behalf have no `tlsDetails`; exclude them with `userIdentity.invokedBy`. The alarm (`cloudtrail-alarm.yaml`) extends the metric filter in the [KMS guide](https://docs.aws.amazon.com/kms/latest/developerguide/pqtls.html) to all six services: `keyExchange` not matching `*MLKEM*` or missing, Sum of 1 or more per hour. `cloudtrail-non-pq.sql` lists the callers (principal, user agent, source IP) for CloudTrail Lake and for Athena; the stock Athena CloudTrail DDL needs `keyexchange:STRING` added to the `tlsdetails` struct. See AWS service endpoints for which endpoints negotiate PQ.

**EventBridge** (`eventbridge-rules.json`): listener created or modified with a non-PQ `sslPolicy`; any API Gateway domain or API create/update (re-check with Config); Config NON\_COMPLIANT for `pq-tls-*` rules; Guard Hook invocations. The patterns are valid JSON; the `anything-but` + `wildcard` match and the Hook event detail-type are not confirmed against live events.

**ALB and NLB logs** (`elb-logs-athena.sql`): ALB connection logs field 13 and NLB TLS access logs field 17 hold `tls_keyexchange` ([ALB](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-connection-logs.html), [NLB](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-access-logs.html)). The file has table DDL, the ML-KEM share per load balancer, top classical clients, and an hourly count to publish as a CloudWatch metric (EventBridge Scheduler → Step Functions → Athena → PutMetricData) with an alarm on the classical share. ALB access logs (not connection logs) do not carry the key exchange. CloudFront: the `CloudFront-Viewer-TLS-Details` origin request header includes the key exchange (Documented; see Edge and API front doors).

**Zeek** on a traffic mirror or behind Network Firewall sees the TLS named group for east-west and egress flows that no AWS log covers. Alert on TLS 1.3 sessions whose group is not X25519MLKEM768 for destinations on the PQ-required list. Configuration is on Network devices and egress.

## Warn-then-fail rollout

1. **Week 0, inventory.** Deploy the Config rules, the scanner pack, the CloudTrail alarm (notify only) and the ELB log tables. Pipeline checks run in warn mode: cfn-guard in a non-blocking step, conftest `warn`, Checkov `--soft-fail`, Guard Hook `WARN`, Kyverno `Audit`, Gatekeeper `warn`.
2. **Week 2, block new risk.** SCP on sandbox and new-workload OUs. Pipeline fails on resources in the change set only.
3. **Week 6, block everything in CI.** Fail the pipeline on all resources; open exceptions for the rest. Guard Hook `FAIL`, Kyverno `Deny`.
4. **Week 8, org-wide SCP.** Attach to all workload OUs once Config shows no non-compliant listeners outside the exception register.
5. **Ongoing.** The classical-share metric per load balancer trends down to the exception list. Apply the RCP per bucket once its logs show TLS 1.3 only.

Each step is reversible by flipping the mode (WARN, Audit, soft-fail) or detaching the SCP; no resource changes.

## Exception register

One register (GRC tool or a repo file) keyed by `EXC-nnnn`. The same ID appears as tag `pq-tls-exception` (Terraform; `PqTlsException` in CloudFormation rules where a hyphen breaks the rule syntax), annotation `pq-tls.example.com/exception` (Kubernetes), and as the session tag when someone assumes `pq-exception-break-glass` to pass the SCP.

| Field | Content |
| --- | --- |
| ID | EXC-nnnn |
| Rule IDs | e.g. PQ-B2, PQ-A4 |
| Resources | Exact ARNs or repo paths; no wildcards |
| Reason | e.g. HTTP API (TLS\_1\_2 only), partner client on TLS 1.2, Lambda nodejs20.x pending migration |
| Data exposure | Confidentiality lifetime of the data on this path (harvest-now-decrypt-later risk) |
| Compensating control | e.g. CloudFront in front, VPN, short-lived data |
| Owner and approver | Team and security approver |
| Created / expires | 90 days maximum; 180 for vendor-blocked items |
| Exit plan | Fix and target date |
| Evidence | Ticket, client inventory, log query result |

Review monthly (platform security lead) and report count and age quarterly. No renewal without a new exit date. Recommended: a nightly job that compares tags and annotations with the register and removes or flags expired IDs, so the pipeline fails again on expiry.

## Verify

All runs on 2026-11-14 in containers on this machine, images pinned by digest; scripts and outputs are kept with the work files (`run-cfn-guard.sh`, `run-image-checks.sh`, `out/*.out`). These are syntax and sample evaluations, not tests in AWS.

| Check | Inputs | Result |
| --- | --- | --- |
| cfn-guard 3.2.1 `pq-tls.guard` | cfn-good / cfn-bad / sam-bad templates | good PASS (9 pass, 5 skip); bad FAIL (11 rules fail); SAM FAIL (Globals runtime, py legacy) |
| Retest 2026-11-15 (cfn-guard 3.2.1, OPA, conftest) | PQ-L2 with `OPENSSL_CONF` at `/var/task/pq-tls/` (python3.13, nodejs22.x), `/opt/pq-tls/` (dotnet8), and `/var/task/other.cnf`; Dockerfile `FROM` for 12 tags | Bundled and layer paths PASS, other path FAIL (cfn-guard and OPA, 12/12 Rego tests). Dockerfile: `python:3.11-slim`, `3.13-trixie`, `node:22`, `22.20.0`, `24.10-alpine` pass; `python:*-bookworm`/`-bullseye`, `node:22.19.0-slim`, `node:24.4`, `node:20-slim`, `golang:1.23` warn |
| cfn-guard Config Guard rule | 5 sample configuration items | good PASS; each of 4 bad items FAILs on the expected rule |
| cfn-lint 1.60.1 | org-config-rules, guard-hook, cloudtrail-alarm, samples | 0 errors (it caught `PolicyRuntime`, fixed to `Runtime`) |
| conftest verify | 10 Rego unit tests | 10/10 pass |
| conftest on real Terraform plan JSON | tf-good / tf-bad | good 0 failures; bad 5 (A1, B2, E1, L1, L2) |
| Checkov 3.4.5 custom | tf-good / tf-bad | good 6 pass; bad 4 fail |
| Syft + conftest SBOM | debian:trixie-slim, debian:bookworm-slim, python:3.11-slim-bookworm, alpine:3.22, amazonlinux:2023 | trixie and alpine pass; python 3.11 bookworm FAIL (libssl3 3.0.22); bookworm-slim WARN (no libssl); AL2023 WARN |
| check-go-pq.sh | go.mod `go 1.23` vs `go 1.24`, both built with Go 1.25 | 1.23 FAIL (`tlsmlkem=0`); 1.24 PASS |
| check-jdk-pq.sh | eclipse-temurin 21-jre-alpine / 25-jre-alpine | 21.0.13 WARN; 25.0.5 PASS |
| conftest Dockerfile | Dockerfile.good / .bad | good 5 pass; bad 1 warn + 4 fail |
| Kyverno CLI 1.20.0, CEL | good / bad manifests (5 objects each) | good 6 pass; bad 5 fail |
| Kyverno CLI 1.19.0, ClusterPolicy | same | good 6 pass; bad 6 fail |
| gator 3.20.0 | same | good 0 violations; bad 2 (K1, K2) |
| JSON and size | SCP, RCP, EventBridge | valid; SCP 2,393 characters minified (limit 5,120) |
| Athena regex | ALB/NLB sample log lines (Python `re`) | all match; `tls_keyexchange` extracted |

In an account, verify in a sandbox OU: create one non-PQ listener and confirm (1) the SCP returns AccessDenied, (2) the Guard Hook warns, (3) Config marks it NON\_COMPLIANT, (4) the EventBridge rule fires.

## Pitfalls and rollback

- CloudFormation, CLI and CDK default ELB listeners to `ELBSecurityPolicy-2016-08`; only the console defaults to `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`. Require an explicit policy.
- Security Hub ELB.17 and APIGateway.11 pass non-PQ TLS 1.3 policies. Do not report them as PQ coverage.
- `lambda-function-settings-check` also checks memory and timeout, so most functions show non-compliant.
- A PQ server policy is not PQ traffic: clients must offer ML-KEM. Measure with logs.
- Kyverno 1.20 needs ValidatingPolicy; pin the policy file to the Kyverno version you run.
- The SCP's API Gateway statement depends on `apigateway:Request/SecurityPolicy` being populated on POST/PATCH; test in a sandbox OU before attaching widely.
- Config custom Guard rules run Guard 2.x; keep them free of 3.x-only syntax.
- A plain prefix match on `amazonlinux:2` also catches `amazonlinux:2023`; the Dockerfile rule matches on tag boundaries for that reason.
- Rollback: detach the SCP (takes effect in minutes), set Guard Hook `FailureMode: WARN`, Kyverno `Audit`, conftest rules to `warn`. Config rules only detect and need no rollback.

**Sources:** [AWS PQC readiness blog (2026-05-14)](https://aws.amazon.com/blogs/security/automating-post-quantum-cryptography-readiness-using-aws-config/) · [ALB security policies](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/describe-ssl-policies.html) · [NLB security policies](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/describe-ssl-policies.html) · [API Gateway security policies](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-security-policies.html) · [Security Hub ELB controls](https://docs.aws.amazon.com/securityhub/latest/userguide/elb-controls.html) · [GuardHook](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-cloudformation-guardhook.html) · [KMS hybrid PQ TLS](https://docs.aws.amazon.com/kms/latest/developerguide/pqtls.html) · [Firewall Manager policy types](https://docs.aws.amazon.com/waf/latest/developerguide/working-with-policies.html) · [RCPs](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_rcps.html) · [Kyverno CEL migration](https://kyverno.io/docs/guides/migration-to-cel/)

## Full configuration files

Every file below is complete. Paths are relative to the rules folder. `config/lambda-pq-tls.guard` is identical to the `PolicyText` inside `org-config-rules.yaml`.

### Organisation

`rules/scp-pq-tls.json`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyElbListenerWithoutPqPolicy",
      "Effect": "Deny",
      "Action": [
        "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:ModifyListener"
      ],
      "Resource": "*",
      "Condition": {
        "Null": {
          "elasticloadbalancing:SecurityPolicy": "false"
        },
        "StringNotEquals": {
          "elasticloadbalancing:SecurityPolicy": [
            "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09",
            "ELBSecurityPolicy-TLS13-1-2-Res-FIPS-PQ-2025-09",
            "ELBSecurityPolicy-TLS13-1-2-PQ-2025-09",
            "ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09",
            "ELBSecurityPolicy-TLS13-1-2-Ext0-FIPS-PQ-2025-09",
            "ELBSecurityPolicy-TLS13-1-2-Ext1-PQ-2025-09",
            "ELBSecurityPolicy-TLS13-1-2-Ext1-FIPS-PQ-2025-09",
            "ELBSecurityPolicy-TLS13-1-2-Ext2-PQ-2025-09",
            "ELBSecurityPolicy-TLS13-1-2-Ext2-FIPS-PQ-2025-09",
            "ELBSecurityPolicy-TLS13-1-3-PQ-2025-09",
            "ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09"
          ]
        },
        "ArnNotLike": {
          "aws:PrincipalArn": "arn:aws:iam::*:role/pq-exception-break-glass"
        }
      }
    },
    {
      "Sid": "DenyHttpsListenerWithoutExplicitPolicy",
      "Effect": "Deny",
      "Action": "elasticloadbalancing:CreateListener",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "elasticloadbalancing:ListenerProtocol": [
            "HTTPS",
            "TLS"
          ]
        },
        "Null": {
          "elasticloadbalancing:SecurityPolicy": "true"
        },
        "ArnNotLike": {
          "aws:PrincipalArn": "arn:aws:iam::*:role/pq-exception-break-glass"
        }
      }
    },
    {
      "Sid": "DenyClassicLbListenerPolicies",
      "Effect": "Deny",
      "Action": [
        "elasticloadbalancing:CreateLoadBalancerListeners",
        "elasticloadbalancing:CreateLoadBalancerPolicy",
        "elasticloadbalancing:SetLoadBalancerPoliciesOfListener"
      ],
      "Resource": "arn:aws:elasticloadbalancing:*:*:loadbalancer/*",
      "Condition": {
        "ArnNotLike": {
          "aws:PrincipalArn": "arn:aws:iam::*:role/pq-exception-break-glass"
        }
      }
    },
    {
      "Sid": "DenyRestApiAndDomainWithoutPqPolicy",
      "Effect": "Deny",
      "Action": [
        "apigateway:POST",
        "apigateway:PATCH",
        "apigateway:PUT"
      ],
      "Resource": [
        "arn:aws:apigateway:*::/domainnames",
        "arn:aws:apigateway:*::/domainnames/*",
        "arn:aws:apigateway:*::/restapis",
        "arn:aws:apigateway:*::/restapis/*"
      ],
      "Condition": {
        "Null": {
          "apigateway:Request/SecurityPolicy": "false"
        },
        "ForAnyValue:StringNotEquals": {
          "apigateway:Request/SecurityPolicy": [
            "SecurityPolicy_TLS13_1_2_PQ_2025_09",
            "SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09",
            "SecurityPolicy_TLS13_1_2_FIPS_PQ_2025_09",
            "SecurityPolicy_TLS13_1_2_FIPS_PFS_PQ_2025_09",
            "SecurityPolicy_TLS13_2025_EDGE",
            "SecurityPolicy_TLS12_PFS_2025_EDGE"
          ]
        },
        "ArnNotLike": {
          "aws:PrincipalArn": "arn:aws:iam::*:role/pq-exception-break-glass"
        }
      }
    }
  ]
}
```

`rules/rcp-s3-tls13.json`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyS3BelowTls13ForTaggedBuckets",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::example-pq-only-bucket",
        "arn:aws:s3:::example-pq-only-bucket/*"
      ],
      "Condition": {
        "NumericLessThan": {
          "s3:TlsVersion": "1.3"
        },
        "BoolIfExists": {
          "aws:PrincipalIsAWSService": "false"
        }
      }
    }
  ]
}
```

`rules/config/org-config-rules.yaml`

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: >
  PQ TLS detective controls for the whole organisation. Deploy in the AWS Config delegated
  administrator account, once per Region (CloudFront rule: us-east-1 only).
Parameters:
  ElbPqPolicies:
    Type: String
    Default: "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09,ELBSecurityPolicy-TLS13-1-2-Res-FIPS-PQ-2025-09,ELBSecurityPolicy-TLS13-1-2-PQ-2025-09,ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09,ELBSecurityPolicy-TLS13-1-2-Ext0-FIPS-PQ-2025-09,ELBSecurityPolicy-TLS13-1-2-Ext1-PQ-2025-09,ELBSecurityPolicy-TLS13-1-2-Ext1-FIPS-PQ-2025-09,ELBSecurityPolicy-TLS13-1-2-Ext2-PQ-2025-09,ELBSecurityPolicy-TLS13-1-2-Ext2-FIPS-PQ-2025-09,ELBSecurityPolicy-TLS13-1-3-PQ-2025-09,ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09"
  ApiGwPqPolicies:
    Type: String
    Default: "SecurityPolicy_TLS13_1_2_PQ_2025_09,SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09,SecurityPolicy_TLS13_1_2_FIPS_PQ_2025_09,SecurityPolicy_TLS13_1_2_FIPS_PFS_PQ_2025_09,SecurityPolicy_TLS13_2025_EDGE,SecurityPolicy_TLS12_PFS_2025_EDGE"
  ExcludedAccounts:
    Type: CommaDelimitedList
    Default: ""
Conditions:
  IsUsEast1: !Equals [ !Ref "AWS::Region", us-east-1 ]
  HasExclusions: !Not [ !Equals [ !Join [ "", !Ref ExcludedAccounts ], "" ] ]
Resources:
  ElbPqPolicyRule:
    Type: AWS::Config::OrganizationConfigRule
    Properties:
      OrganizationConfigRuleName: pq-tls-elbv2-listener-policy
      ExcludedAccounts: !If [ HasExclusions, !Ref ExcludedAccounts, !Ref "AWS::NoValue" ]
      OrganizationManagedRuleMetadata:
        RuleIdentifier: ELBV2_PREDEFINED_SECURITY_POLICY_SSL_CHECK
        Description: ALB HTTPS / NLB TLS listeners must use a -PQ-2025-09 security policy
        ResourceTypesScope: [ "AWS::ElasticLoadBalancingV2::Listener" ]
        InputParameters: !Sub '{"sslPolicies":"${ElbPqPolicies}"}'
  ApiGwDomainPqRule:
    Type: AWS::Config::OrganizationConfigRule
    Properties:
      OrganizationConfigRuleName: pq-tls-apigw-domain-policy
      ExcludedAccounts: !If [ HasExclusions, !Ref ExcludedAccounts, !Ref "AWS::NoValue" ]
      OrganizationManagedRuleMetadata:
        RuleIdentifier: APIGATEWAY_DOMAIN_NAME_TLS_CHECK
        Description: API Gateway REST custom domains must use a PQ security policy
        ResourceTypesScope: [ "AWS::ApiGateway::DomainName" ]
        InputParameters: !Sub '{"allowedSecurityPolicies":"${ApiGwPqPolicies}"}'
  CloudFrontViewerPolicyRule:
    Type: AWS::Config::OrganizationConfigRule
    Condition: IsUsEast1
    Properties:
      OrganizationConfigRuleName: pq-tls-cloudfront-viewer-policy
      ExcludedAccounts: !If [ HasExclusions, !Ref ExcludedAccounts, !Ref "AWS::NoValue" ]
      OrganizationManagedRuleMetadata:
        RuleIdentifier: CLOUDFRONT_SSL_POLICY_CHECK
        Description: CloudFront viewer TLS policy must allow TLS 1.3 (PQ is negotiated only in TLS 1.3)
        ResourceTypesScope: [ "AWS::CloudFront::Distribution" ]
        InputParameters: '{"securityPolicies":"TLSv1.2_2021,TLSv1.2_2025,TLSv1.3_2025"}'
  LambdaPqRule:
    Type: AWS::Config::OrganizationConfigRule
    Properties:
      OrganizationConfigRuleName: pq-tls-lambda-runtime-env
      ExcludedAccounts: !If [ HasExclusions, !Ref ExcludedAccounts, !Ref "AWS::NoValue" ]
      OrganizationCustomPolicyRuleMetadata:
        Description: Lambda runtime has a PQ path and the pq-tls env is set
        Runtime: guard-2.x.x
        OrganizationConfigRuleTriggerTypes: [ ConfigurationItemChangeNotification ]
        ResourceTypesScope: [ "AWS::Lambda::Function" ]
        PolicyText: |
          let blocked = [ "nodejs18.x", "nodejs20.x", "python3.8", "java8", "dotnet6" ]
          let needs_conf = [ "python3.12", "python3.13", "python3.14", "nodejs22.x", "nodejs24.x", "dotnet8", "dotnet10" ]
          let needs_agent = [ "java8.al2", "java11", "java17", "java21" ]
          let pq_confs = [ "/opt/pq-tls/openssl-pq.cnf", "/opt/pq-tls/openssl-pq-node.cnf", "/var/task/pq-tls/openssl-pq.cnf", "/var/task/pq-tls/openssl-pq-node.cnf" ]
          rule lambda_runtime_has_pq_path when configuration.packageType != "Image" {
            configuration.runtime not in %blocked
          }
          rule lambda_openssl_conf_set when configuration.runtime in %needs_conf {
            configuration.environment.variables.OPENSSL_CONF in %pq_confs or
            configuration.environment.variables.AWS_LAMBDA_EXEC_WRAPPER == "/opt/pq-tls/wrapper"
          }
          rule lambda_java_agent_set when configuration.runtime in %needs_agent {
            configuration.environment.variables.JAVA_TOOL_OPTIONS == /pq-tls-agent\.jar/ or
            configuration.environment.variables.AWS_LAMBDA_EXEC_WRAPPER == "/opt/pq-tls/wrapper"
          }
          rule lambda_godebug_not_off when configuration.environment.variables.GODEBUG exists {
            configuration.environment.variables.GODEBUG != /tlsmlkem=0/
          }
```

### Pipeline

`rules/cfn/pq-tls.guard`

```text
#
# pq-tls.guard - CloudFormation Guard 3.x rules for hybrid post-quantum TLS (X25519MLKEM768).
# Use: cfn-guard validate --rules pq-tls.guard --data template.yaml
# Also usable as the rule file of an AWS::CloudFormation::GuardHook (S3 RuleLocation).
#

# ---------- shared lists ----------
let pq_elb_policies = [
  "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09",
  "ELBSecurityPolicy-TLS13-1-2-Res-FIPS-PQ-2025-09",
  "ELBSecurityPolicy-TLS13-1-2-PQ-2025-09",
  "ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09",
  "ELBSecurityPolicy-TLS13-1-2-Ext0-FIPS-PQ-2025-09",
  "ELBSecurityPolicy-TLS13-1-2-Ext1-PQ-2025-09",
  "ELBSecurityPolicy-TLS13-1-2-Ext1-FIPS-PQ-2025-09",
  "ELBSecurityPolicy-TLS13-1-2-Ext2-PQ-2025-09",
  "ELBSecurityPolicy-TLS13-1-2-Ext2-FIPS-PQ-2025-09",
  "ELBSecurityPolicy-TLS13-1-3-PQ-2025-09",
  "ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09"
]

let pq_apigw_policies = [
  "SecurityPolicy_TLS13_1_2_PQ_2025_09",
  "SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09",
  "SecurityPolicy_TLS13_1_2_FIPS_PQ_2025_09",
  "SecurityPolicy_TLS13_1_2_FIPS_PFS_PQ_2025_09"
]

# Runtimes with no in-place PQ fix: upgrade.
let lambda_runtimes_blocked = [
  "nodejs18.x", "nodejs20.x", "python3.8", "java8", "dotnet6"
]
# OpenSSL 3.5 runtimes: PQ needs the pq-tls layer (OPENSSL_CONF or the exec wrapper).
let lambda_runtimes_conf = [
  "python3.12", "python3.13", "python3.14",
  "nodejs22.x", "nodejs24.x",
  "dotnet8", "dotnet10"
]
# JDK < 25: PQ needs the Bouncy Castle JSSE agent.
let lambda_runtimes_java_agent = [ "java8.al2", "java11", "java17", "java21" ]
# OpenSSL 1.1.1 Python: shim covers urllib3/botocore only (partial). Warn-level rule.
let lambda_runtimes_py_legacy = [ "python3.9", "python3.10", "python3.11" ]

let pq_conf_paths = [ "/opt/pq-tls/openssl-pq.cnf", "/opt/pq-tls/openssl-pq-node.cnf", "/var/task/pq-tls/openssl-pq.cnf", "/var/task/pq-tls/openssl-pq-node.cnf" ]

let lambda_zip = Resources.*[
  Type == "AWS::Lambda::Function"
  Properties.PackageType !exists or Properties.PackageType != "Image"
]
let sam_zip = Resources.*[
  Type == "AWS::Serverless::Function"
  Properties.PackageType !exists or Properties.PackageType != "Image"
]

# ---------- Lambda ----------
rule PQ_LAMBDA_RUNTIME_NOT_BLOCKED when %lambda_zip !empty {
  %lambda_zip.Properties.Runtime not in %lambda_runtimes_blocked
  <<
    PQ-L1: Lambda runtime has no PQ path (Node.js 18/20 bundle OpenSSL 3.0; python3.8, java8 on AL1, dotnet6 are end of life).
    Fix: move to nodejs22.x/24.x, python3.12+, java21+agent or java25, dotnet8/10.
  >>
}

rule PQ_LAMBDA_OPENSSL_CONF when %lambda_zip !empty {
  let conf_fns = %lambda_zip[ Properties.Runtime in %lambda_runtimes_conf ]
  when %conf_fns !empty {
    %conf_fns {
      Properties.Environment.Variables exists
      Properties.Environment.Variables.OPENSSL_CONF in %pq_conf_paths or
      Properties.Environment.Variables.AWS_LAMBDA_EXEC_WRAPPER == "/opt/pq-tls/wrapper"
      <<
        PQ-L2: python3.12+/nodejs22+/dotnet8+ on AL2023 omit ML-KEM from the default group list.
        Fix: bundle pq-tls/ in the package and set OPENSSL_CONF=/var/task/pq-tls/openssl-pq.cnf (Node: openssl-pq-node.cnf),
        or attach the pq-tls layer and set OPENSSL_CONF=/opt/pq-tls/... or AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper.
      >>
    }
  }
}

rule PQ_LAMBDA_JAVA_AGENT when %lambda_zip !empty {
  let java_fns = %lambda_zip[ Properties.Runtime in %lambda_runtimes_java_agent ]
  when %java_fns !empty {
    %java_fns {
      Properties.Environment.Variables exists
      Properties.Environment.Variables.JAVA_TOOL_OPTIONS == /pq-tls-agent\.jar/ or
      Properties.Environment.Variables.AWS_LAMBDA_EXEC_WRAPPER == "/opt/pq-tls/wrapper"
      <<
        PQ-L3: JDK 8-21 have no ML-KEM TLS group. Fix: JAVA_TOOL_OPTIONS=-javaagent:/opt/pq-tls/pq-tls-agent.jar
        (Bouncy Castle JSSE) or the exec wrapper, or move to java25.
      >>
    }
  }
}

# Warn-level: run with this rule in a separate file/pass whose failures do not block.
rule PQ_LAMBDA_PY_LEGACY_SHIM when %lambda_zip !empty {
  let py_fns = %lambda_zip[ Properties.Runtime in %lambda_runtimes_py_legacy ]
  when %py_fns !empty {
    %py_fns {
      Properties.Environment.Variables.AWS_LAMBDA_EXEC_WRAPPER == "/opt/pq-tls/wrapper"
      <<
        PQ-L4 (warn): python3.9-3.11 use OpenSSL 1.1.1. The pq-tls shim covers urllib3/botocore only. Plan python3.12+.
      >>
    }
  }
}

rule PQ_LAMBDA_NO_GODEBUG_OFF when %lambda_zip !empty {
  %lambda_zip.Properties.Environment.Variables.GODEBUG !exists or
  %lambda_zip.Properties.Environment.Variables.GODEBUG != /tlsmlkem=0/
  <<
    PQ-L5: GODEBUG tlsmlkem=0 turns off X25519MLKEM768 in Go crypto/tls.
  >>
}

rule PQ_SAM_RUNTIME_NOT_BLOCKED when %sam_zip !empty {
  %sam_zip.Properties.Runtime !exists or
  %sam_zip.Properties.Runtime not in %lambda_runtimes_blocked
  << PQ-L1 (SAM): see PQ-L1. Runtime may also come from Globals.Function.Runtime; check Globals. >>
}

rule PQ_SAM_GLOBAL_RUNTIME_NOT_BLOCKED when Globals.Function.Runtime exists {
  Globals.Function.Runtime not in %lambda_runtimes_blocked
  << PQ-L1 (SAM Globals): see PQ-L1. >>
}

# ---------- ECS task definitions ----------
let ecs_tds = Resources.*[ Type == "AWS::ECS::TaskDefinition" ]

rule PQ_ECS_NO_GODEBUG_OFF when %ecs_tds !empty {
  let envs = %ecs_tds.Properties.ContainerDefinitions[*].Environment[*]
  when %envs !empty {
    %envs[ Name == "GODEBUG" ].Value != /tlsmlkem=0/
    << PQ-E1: GODEBUG tlsmlkem=0 in a task definition disables PQ in Go. >>
  }
}

rule PQ_ECS_JAVA_NAMED_GROUPS when %ecs_tds !empty {
  let jto = %ecs_tds.Properties.ContainerDefinitions[*].Environment[ Name == "JAVA_TOOL_OPTIONS" ]
  when %jto !empty {
    %jto.Value != /jdk\.tls\.namedGroups=/ or %jto.Value == /X25519MLKEM768/
    << PQ-E2: -Djdk.tls.namedGroups set without X25519MLKEM768 removes PQ on JDK 25. >>
  }
}

rule PQ_ECS_OPENSSL_CONF_NOT_CLASSICAL when %ecs_tds !empty {
  let oc = %ecs_tds.Properties.ContainerDefinitions[*].Environment[ Name == "OPENSSL_CONF" ]
  when %oc !empty {
    %oc.Value != "/dev/null"
    << PQ-E3: OPENSSL_CONF=/dev/null drops the PQ group config. Point it at the pq-tls config instead. >>
  }
}

# ---------- Load balancer listeners ----------
let tls_listeners = Resources.*[
  Type == "AWS::ElasticLoadBalancingV2::Listener"
  Properties.Protocol in ["HTTPS", "TLS"]
]

rule PQ_ELB_LISTENER_POLICY when %tls_listeners !empty {
  %tls_listeners.Properties.SslPolicy exists
  <<
    PQ-B1: HTTPS/TLS listener without SslPolicy gets ELBSecurityPolicy-2016-08 from CloudFormation (no PQ).
  >>
  %tls_listeners.Properties.SslPolicy in %pq_elb_policies
  <<
    PQ-B2: SslPolicy must be a -PQ-2025-09 policy (TLS 1.0 PQ variants excluded).
    Default choice: ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09.
  >>
}

# ---------- API Gateway ----------
let rest_domains = Resources.*[
  Type == "AWS::ApiGateway::DomainName"
  Properties.EndpointConfiguration.Types[0] != "EDGE"
]
rule PQ_APIGW_DOMAIN_POLICY when %rest_domains !empty {
  %rest_domains.Properties.SecurityPolicy in %pq_apigw_policies
  << PQ-A1: REST custom domain (Regional/Private) must use a *_PQ_2025_09 security policy. >>
  %rest_domains.Properties.EndpointAccessMode in ["BASIC", "STRICT"]
  << PQ-A2: enhanced SecurityPolicy_* policies require EndpointAccessMode (start BASIC, move to STRICT). >>
}

let rest_apis = Resources.*[
  Type == "AWS::ApiGateway::RestApi"
  Properties.EndpointConfiguration.Types[0] != "EDGE"
  Properties.DisableExecuteApiEndpoint !exists or Properties.DisableExecuteApiEndpoint != true
]
rule PQ_APIGW_RESTAPI_POLICY when %rest_apis !empty {
  %rest_apis.Properties.SecurityPolicy in %pq_apigw_policies
  << PQ-A3: Regional/Private REST API execute-api endpoint must use a *_PQ_2025_09 policy, or disable the default endpoint. >>
}

let v2_domains = Resources.*[ Type == "AWS::ApiGatewayV2::DomainName" ]
rule PQ_APIGW_V2_DOMAIN_EXCEPTION when %v2_domains !empty {
  # HTTP/WebSocket APIs support only TLS_1_2 (no PQ policy). Require a registered exception tag.
  %v2_domains.Properties.Tags.PqTlsException exists
  << PQ-A4: HTTP/WebSocket API domains cannot be PQ (TLS_1_2 only). Front with CloudFront or a REST API, or register an exception (tag PqTlsException=EXC-id). >>
}
```

`rules/cfn/guard-hook.yaml`

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: >
  CloudFormation Guard Hook that runs pq-tls.guard on every stack and resource operation in this
  account and Region. Start with FailureMode WARN; switch to FAIL after the warn window.
  Deploy to all accounts with a service-managed StackSet.
Parameters:
  RulesBucket: { Type: String }
  RulesKey: { Type: String, Default: guard/pq-tls.guard }
  LogBucket: { Type: String }
  Mode:
    Type: String
    Default: WARN
    AllowedValues: [ WARN, FAIL ]
Resources:
  GuardHookRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Principal: { Service: hooks.cloudformation.amazonaws.com }
            Action: sts:AssumeRole
      Policies:
        - PolicyName: read-rules-write-logs
          PolicyDocument:
            Version: "2012-10-17"
            Statement:
              - Effect: Allow
                Action: [ s3:GetObject, s3:GetObjectVersion, s3:ListBucket ]
                Resource:
                  - !Sub arn:aws:s3:::${RulesBucket}
                  - !Sub arn:aws:s3:::${RulesBucket}/*
              - Effect: Allow
                Action: s3:PutObject
                Resource: !Sub arn:aws:s3:::${LogBucket}/*
  PqTlsGuardHook:
    Type: AWS::CloudFormation::GuardHook
    Properties:
      Alias: Private::Guard::PqTls
      ExecutionRole: !GetAtt GuardHookRole.Arn
      FailureMode: !Ref Mode
      HookStatus: ENABLED
      LogBucket: !Ref LogBucket
      RuleLocation:
        Uri: !Sub s3://${RulesBucket}/${RulesKey}
      TargetOperations: [ RESOURCE, STACK ]
      TargetFilters:
        Actions: [ CREATE, UPDATE ]
```

`rules/opa/terraform/pq_tls.rego`

```text
# Conftest / OPA policy for `terraform show -json plan.out` output.
# Usage: conftest test --policy rules/opa/terraform --namespace terraform.pq_tls plan.json
package terraform.pq_tls

import rego.v1

pq_elb_policies := {
	"ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09",
	"ELBSecurityPolicy-TLS13-1-2-Res-FIPS-PQ-2025-09",
	"ELBSecurityPolicy-TLS13-1-2-PQ-2025-09",
	"ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09",
	"ELBSecurityPolicy-TLS13-1-2-Ext0-FIPS-PQ-2025-09",
	"ELBSecurityPolicy-TLS13-1-2-Ext1-PQ-2025-09",
	"ELBSecurityPolicy-TLS13-1-2-Ext1-FIPS-PQ-2025-09",
	"ELBSecurityPolicy-TLS13-1-2-Ext2-PQ-2025-09",
	"ELBSecurityPolicy-TLS13-1-2-Ext2-FIPS-PQ-2025-09",
	"ELBSecurityPolicy-TLS13-1-3-PQ-2025-09",
	"ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09",
}

pq_apigw_policies := {
	"SecurityPolicy_TLS13_1_2_PQ_2025_09",
	"SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09",
	"SecurityPolicy_TLS13_1_2_FIPS_PQ_2025_09",
	"SecurityPolicy_TLS13_1_2_FIPS_PFS_PQ_2025_09",
}

blocked_runtimes := {"nodejs18.x", "nodejs20.x", "python3.8", "java8", "dotnet6"}

conf_runtimes := {"python3.12", "python3.13", "python3.14", "nodejs22.x", "nodejs24.x", "dotnet8", "dotnet10"}

agent_runtimes := {"java8.al2", "java11", "java17", "java21"}

pq_confs := {"/opt/pq-tls/openssl-pq.cnf", "/opt/pq-tls/openssl-pq-node.cnf", "/var/task/pq-tls/openssl-pq.cnf", "/var/task/pq-tls/openssl-pq-node.cnf"}

# Resources being created or updated, with their planned values.
changed contains rc if {
	some rc in input.resource_changes
	some action in rc.change.actions
	action in {"create", "update"}
}

has_exception(rc) if rc.change.after.tags["pq-tls-exception"]

env_vars(rc) := v if {
	v := rc.change.after.environment[0].variables
} else := {}

# ---------- load balancer listeners ----------
deny contains msg if {
	some rc in changed
	rc.type in {"aws_lb_listener", "aws_alb_listener"}
	rc.change.after.protocol in {"HTTPS", "TLS"}
	not elb_ok(rc.change.after)
	not has_exception(rc)
	msg := sprintf("PQ-B2 %s: ssl_policy %v is not a -PQ-2025-09 policy (default choice ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09)", [rc.address, rc.change.after.ssl_policy])
}

# ---------- API Gateway ----------
deny contains msg if {
	some rc in changed
	rc.type == "aws_api_gateway_domain_name"
	not rc.change.after.endpoint_configuration[0].types[0] == "EDGE"
	not apigw_ok(rc.change.after)
	not has_exception(rc)
	msg := sprintf("PQ-A1 %s: security_policy %v is not a *_PQ_2025_09 policy", [rc.address, rc.change.after.security_policy])
}

warn contains msg if {
	some rc in changed
	rc.type == "aws_apigatewayv2_domain_name"
	not has_exception(rc)
	msg := sprintf("PQ-A4 %s: HTTP/WebSocket API domains support TLS_1_2 only (no PQ); register an exception or front with CloudFront", [rc.address])
}

# ---------- Lambda ----------
deny contains msg if {
	some rc in changed
	rc.type == "aws_lambda_function"
	rc.change.after.runtime in blocked_runtimes
	not has_exception(rc)
	msg := sprintf("PQ-L1 %s: runtime %s has no PQ path; upgrade", [rc.address, rc.change.after.runtime])
}

deny contains msg if {
	some rc in changed
	rc.type == "aws_lambda_function"
	rc.change.after.runtime in conf_runtimes
	not conf_ok(env_vars(rc))
	not has_exception(rc)
	msg := sprintf("PQ-L2 %s: %s needs OPENSSL_CONF=/var/task/pq-tls/openssl-pq*.cnf (bundled) or /opt/pq-tls/openssl-pq*.cnf (layer), or AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper", [rc.address, rc.change.after.runtime])
}

deny contains msg if {
	some rc in changed
	rc.type == "aws_lambda_function"
	rc.change.after.runtime in agent_runtimes
	not agent_ok(env_vars(rc))
	not has_exception(rc)
	msg := sprintf("PQ-L3 %s: %s needs the Bouncy Castle JSSE agent (JAVA_TOOL_OPTIONS -javaagent:/opt/pq-tls/pq-tls-agent.jar) or java25", [rc.address, rc.change.after.runtime])
}

deny contains msg if {
	some rc in changed
	rc.type == "aws_lambda_function"
	contains(object.get(env_vars(rc), "GODEBUG", ""), "tlsmlkem=0")
	msg := sprintf("PQ-L5 %s: GODEBUG tlsmlkem=0 disables PQ", [rc.address])
}

# ---------- ECS ----------
deny contains msg if {
	some rc in changed
	rc.type == "aws_ecs_task_definition"
	defs := json.unmarshal(rc.change.after.container_definitions)
	some c in defs
	some e in c.environment
	e.name == "GODEBUG"
	contains(e.value, "tlsmlkem=0")
	msg := sprintf("PQ-E1 %s container %s: GODEBUG tlsmlkem=0 disables PQ", [rc.address, c.name])
}

# ---------- helpers (a missing attribute counts as not compliant) ----------
elb_ok(after) if after.ssl_policy in pq_elb_policies

apigw_ok(after) if after.security_policy in pq_apigw_policies

conf_ok(vars) if vars.OPENSSL_CONF in pq_confs

conf_ok(vars) if vars.AWS_LAMBDA_EXEC_WRAPPER == "/opt/pq-tls/wrapper"

agent_ok(vars) if contains(object.get(vars, "JAVA_TOOL_OPTIONS", ""), "pq-tls-agent.jar")

agent_ok(vars) if vars.AWS_LAMBDA_EXEC_WRAPPER == "/opt/pq-tls/wrapper"
```

`rules/opa/terraform/pq_tls_test.rego`

```text
package terraform.pq_tls_test

import rego.v1

import data.terraform.pq_tls

rc(type, after) := {"address": sprintf("%s.x", [type]), "type": type, "change": {"actions": ["create"], "after": after}}

test_listener_pq_ok if {
	count(pq_tls.deny) == 0 with input as {"resource_changes": [rc("aws_lb_listener", {"protocol": "HTTPS", "ssl_policy": "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"})]}
}

test_listener_classic_denied if {
	count(pq_tls.deny) == 1 with input as {"resource_changes": [rc("aws_lb_listener", {"protocol": "TLS", "ssl_policy": "ELBSecurityPolicy-TLS13-1-2-2021-06"})]}
}

test_listener_http_ignored if {
	count(pq_tls.deny) == 0 with input as {"resource_changes": [rc("aws_lb_listener", {"protocol": "HTTP", "ssl_policy": null})]}
}

test_listener_exception_tag if {
	count(pq_tls.deny) == 0 with input as {"resource_changes": [rc("aws_lb_listener", {"protocol": "HTTPS", "ssl_policy": "ELBSecurityPolicy-2016-08", "tags": {"pq-tls-exception": "EXC-0007"}})]}
}

test_lambda_python_conf_ok if {
	count(pq_tls.deny) == 0 with input as {"resource_changes": [rc("aws_lambda_function", {"runtime": "python3.13", "environment": [{"variables": {"OPENSSL_CONF": "/opt/pq-tls/openssl-pq.cnf"}}]})]}
}

test_lambda_python_bundled_conf_ok if {
	count(pq_tls.deny) == 0 with input as {"resource_changes": [rc("aws_lambda_function", {"runtime": "python3.13", "environment": [{"variables": {"OPENSSL_CONF": "/var/task/pq-tls/openssl-pq.cnf"}}]})]}
}

test_lambda_python_other_conf_denied if {
	count(pq_tls.deny) == 1 with input as {"resource_changes": [rc("aws_lambda_function", {"runtime": "python3.13", "environment": [{"variables": {"OPENSSL_CONF": "/var/task/other.cnf"}}]})]}
}

test_lambda_python_no_conf_denied if {
	count(pq_tls.deny) == 1 with input as {"resource_changes": [rc("aws_lambda_function", {"runtime": "python3.12", "environment": []})]}
}

test_lambda_node20_denied if {
	count(pq_tls.deny) == 1 with input as {"resource_changes": [rc("aws_lambda_function", {"runtime": "nodejs20.x"})]}
}

test_lambda_java21_agent_ok if {
	count(pq_tls.deny) == 0 with input as {"resource_changes": [rc("aws_lambda_function", {"runtime": "java21", "environment": [{"variables": {"JAVA_TOOL_OPTIONS": "-javaagent:/opt/pq-tls/pq-tls-agent.jar"}}]})]}
}

test_ecs_godebug_denied if {
	count(pq_tls.deny) == 1 with input as {"resource_changes": [rc("aws_ecs_task_definition", {"container_definitions": "[{\"name\":\"api\",\"environment\":[{\"name\":\"GODEBUG\",\"value\":\"tlsmlkem=0\"}]}]"})]}
}

test_apigw_v2_warns if {
	count(pq_tls.warn) == 1 with input as {"resource_changes": [rc("aws_apigatewayv2_domain_name", {"domain_name": "a.example.com"})]}
}
```

`rules/checkov/pq_tls_1.yaml`

```yaml
metadata:
  id: "CKV2_PQTLS_1"
  name: "ALB HTTPS / NLB TLS listener must use a -PQ-2025-09 security policy"
  category: "ENCRYPTION"
  severity: "HIGH"
definition:
  or:
    - cond_type: attribute
      resource_types: [ aws_lb_listener, aws_alb_listener ]
      attribute: protocol
      operator: not_within
      value: [ "HTTPS", "TLS" ]
    - cond_type: attribute
      resource_types: [ aws_lb_listener, aws_alb_listener ]
      attribute: ssl_policy
      operator: within
      value:
        - ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09
        - ELBSecurityPolicy-TLS13-1-2-Res-FIPS-PQ-2025-09
        - ELBSecurityPolicy-TLS13-1-2-PQ-2025-09
        - ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09
        - ELBSecurityPolicy-TLS13-1-2-Ext0-FIPS-PQ-2025-09
        - ELBSecurityPolicy-TLS13-1-2-Ext1-PQ-2025-09
        - ELBSecurityPolicy-TLS13-1-2-Ext1-FIPS-PQ-2025-09
        - ELBSecurityPolicy-TLS13-1-2-Ext2-PQ-2025-09
        - ELBSecurityPolicy-TLS13-1-2-Ext2-FIPS-PQ-2025-09
        - ELBSecurityPolicy-TLS13-1-3-PQ-2025-09
        - ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09
```

`rules/checkov/pq_tls_2.yaml`

```yaml
metadata:
  id: "CKV2_PQTLS_2"
  name: "Lambda runtime must have a PQ path (no nodejs18.x/20.x, python3.8, java8, dotnet6)"
  category: "ENCRYPTION"
  severity: "HIGH"
definition:
  cond_type: attribute
  resource_types: [ aws_lambda_function ]
  attribute: runtime
  operator: not_within
  value: [ "nodejs18.x", "nodejs20.x", "python3.8", "java8", "dotnet6" ]
```

`rules/checkov/pq_tls_3.yaml`

```yaml
metadata:
  id: "CKV2_PQTLS_3"
  name: "Lambda python3.12+/nodejs22+/dotnet8+ must set the pq-tls OPENSSL_CONF or exec wrapper"
  category: "ENCRYPTION"
  severity: "MEDIUM"
definition:
  or:
    - cond_type: attribute
      resource_types: [ aws_lambda_function ]
      attribute: runtime
      operator: not_within
      value: [ "python3.12", "python3.13", "python3.14", "nodejs22.x", "nodejs24.x", "dotnet8", "dotnet10" ]
    - cond_type: attribute
      resource_types: [ aws_lambda_function ]
      attribute: environment.variables.OPENSSL_CONF
      operator: within
      value: [ "/opt/pq-tls/openssl-pq.cnf", "/opt/pq-tls/openssl-pq-node.cnf", "/var/task/pq-tls/openssl-pq.cnf", "/var/task/pq-tls/openssl-pq-node.cnf" ]
    - cond_type: attribute
      resource_types: [ aws_lambda_function ]
      attribute: environment.variables.AWS_LAMBDA_EXEC_WRAPPER
      operator: equals
      value: "/opt/pq-tls/wrapper"
```

`rules/checkov/pq_tls_4.yaml`

```yaml
metadata:
  id: "CKV2_PQTLS_4"
  name: "API Gateway REST Regional/Private custom domain must use a *_PQ_2025_09 security policy"
  category: "ENCRYPTION"
  severity: "HIGH"
definition:
  cond_type: attribute
  resource_types: [ aws_api_gateway_domain_name ]
  attribute: security_policy
  operator: within
  value:
    - SecurityPolicy_TLS13_1_2_PQ_2025_09
    - SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09
    - SecurityPolicy_TLS13_1_2_FIPS_PQ_2025_09
    - SecurityPolicy_TLS13_1_2_FIPS_PFS_PQ_2025_09
```

`rules/opa/image/openssl_sbom.rego`

```text
# Conftest policy for a Syft JSON SBOM (syft <image> -o syft-json).
# Fails when the image's system OpenSSL is older than 3.5 (no ML-KEM).
# Usage: conftest test --policy rules/opa/image --namespace image.openssl sbom.json
package image.openssl

import rego.v1

openssl_pkgs := {"openssl", "libssl3", "libssl3t64", "openssl-libs", "libcrypto3", "libssl3-openssl", "openssl3"}

# Packages that carry the system TLS library, with "major.minor" parsed from the version.
ssl_pkgs contains {"name": a.name, "version": a.version, "mm": mm} if {
	some a in input.artifacts
	a.name in openssl_pkgs
	m := regex.find_all_string_submatch_n(`^(?:\d+:)?(\d+)\.(\d+)`, a.version, 1)
	mm := [to_number(m[0][1]), to_number(m[0][2])]
}

too_old(mm) if mm[0] < 3

too_old(mm) if {
	mm[0] == 3
	mm[1] < 5
}

deny contains msg if {
	some p in ssl_pkgs
	too_old(p.mm)
	msg := sprintf("PQ-I1 %s: %s %s is older than OpenSSL 3.5 (no X25519MLKEM768). Rebase on debian:trixie / alpine:3.22+ or add a PQ-capable TLS library.", [input.source.metadata.userInput, p.name, p.version])
}

warn contains msg if {
	count(ssl_pkgs) == 0
	msg := sprintf("PQ-I2 %s: no system OpenSSL package found (distroless/static image?). Check the language runtime's own TLS stack (Go, Java, .NET, Node).", [input.source.metadata.userInput])
}

warn contains msg if {
	some a in input.artifacts
	a.name in {"openssl-libs"}
	contains(a.version, "amzn2023")
	msg := sprintf("PQ-I3 %s: Amazon Linux 2023 OpenSSL needs crypto-policy DEFAULT:PQ or OPENSSL_CONF=openssl-pq.cnf for ML-KEM by default.", [input.source.metadata.userInput])
}
```

`rules/image/check-go-pq.sh`

```bash
#!/bin/sh
# check-go-pq.sh <go-binary>...  - fail if a Go binary will not offer X25519MLKEM768 by default.
# Needs a Go toolchain (any version >= the binary's) on PATH for `go version -m`.
# Rules (Go crypto/tls): toolchain >= 1.24 AND the module's go directive >= 1.24, otherwise the
# default GODEBUG carries tlsmlkem=0. An explicit tls.Config.CurvePreferences is not visible here:
# catch it with the source grep at the end of this script's README section.
rc=0
for bin in "$@"; do
  info=$(go version -m "$bin" 2>/dev/null) || { echo "SKIP $bin: not a Go binary"; continue; }
  tool=$(printf '%s\n' "$info" | head -1 | sed -E 's/.*: go([0-9]+)\.([0-9]+).*/\1 \2/')
  set -- $tool
  major=$1; minor=$2
  godebug=$(printf '%s\n' "$info" | awk '$1=="build" && $2 ~ /^DefaultGODEBUG=/ {sub(/^DefaultGODEBUG=/,"",$2); print $2}')
  if [ "$major" -lt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -lt 24 ]; }; then
    echo "FAIL $bin: built with go$major.$minor (< 1.24, no ML-KEM in crypto/tls)"; rc=1
  elif printf '%s' "$godebug" | grep -q 'tlsmlkem=0'; then
    echo "FAIL $bin: DefaultGODEBUG=$godebug (go.mod go directive < 1.24). Raise go to >= 1.24 or add //go:debug tlsmlkem=1"; rc=1
  else
    echo "PASS $bin: go$major.$minor DefaultGODEBUG=${godebug:-<none>}"
  fi
done
exit $rc
```

`rules/image/check-jdk-pq.sh`

```bash
#!/bin/sh
# check-jdk-pq.sh <image>  - read the JDK `release` file from a container image without running it.
# PASS: JAVA_VERSION >= 25. WARN: 8-21 (needs the Bouncy Castle JSSE agent; check JAVA_TOOL_OPTIONS).
# Needs: docker (or podman with the same CLI).
img="$1"
cid=$(docker create ${DOCKER_CREATE_ARGS:-} "$img" /bin/true) || exit 2
trap 'docker rm -f "$cid" >/dev/null 2>&1' EXIT
jhome=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$img" | sed -n 's/^JAVA_HOME=//p' | head -1)
for p in "${jhome:-/nonexistent}/release" /opt/java/openjdk/release /usr/lib/jvm/default-jvm/release /usr/lib/jvm/java/release; do
  if docker cp "$cid:$p" - 2>/dev/null | tar -xO 2>/dev/null > /tmp/jdk-release.$$; then
    [ -s /tmp/jdk-release.$$ ] && break
  fi
done
ver=$(sed -n 's/^JAVA_VERSION="\{0,1\}\([^"]*\)"\{0,1\}/\1/p' /tmp/jdk-release.$$ 2>/dev/null); rm -f /tmp/jdk-release.$$
[ -z "$ver" ] && { echo "SKIP $img: no JDK release file found"; exit 0; }
major=$(echo "$ver" | sed -E 's/^1\.([0-9]+).*/\1/; s/^([0-9]+).*/\1/')
jto=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$img" | sed -n 's/^JAVA_TOOL_OPTIONS=//p')
if [ "$major" -ge 25 ]; then
  echo "PASS $img: JDK $ver (ML-KEM hybrid groups on by default)"
elif echo "$jto" | grep -q 'pq-tls-agent.jar\|bctls'; then
  echo "PASS $img: JDK $ver with Bouncy Castle JSSE agent ($jto)"
else
  echo "WARN $img: JDK $ver has no ML-KEM TLS group. Add -javaagent:/opt/pq-tls/pq-tls-agent.jar or move to JDK 25"; exit 1
fi
```

`rules/opa/dockerfile/pq_dockerfile.rego`

```text
# Conftest policy for Dockerfiles (conftest parses Dockerfile natively).
# Usage: conftest test --policy rules/opa/dockerfile --namespace dockerfile.pq_tls Dockerfile
package dockerfile.pq_tls

import rego.v1

# ENV is parsed as triplets: [key, value, "="] per pair.
# Base images whose system OpenSSL is < 3.5 or whose runtime has no PQ (warn: upgrade the base).
classical_bases := [
	"debian:bookworm", "debian:12", "ubuntu:22.04", "ubuntu:24.04", "ubuntu:jammy", "ubuntu:noble",
	"node:18", "node:20",
	"amazonlinux:2", "public.ecr.aws/lambda/nodejs:20", "public.ecr.aws/lambda/nodejs:18",
	"public.ecr.aws/lambda/python:3.11", "public.ecr.aws/lambda/python:3.10", "public.ecr.aws/lambda/python:3.9",
	"golang:1.22", "golang:1.23", "eclipse-temurin:17", "eclipse-temurin:21", "amazoncorretto:17", "amazoncorretto:21",
]

from_images contains img if {
	some instr in input
	instr.Cmd == "from"
	img := lower(instr.Value[0])
}

env_pairs contains [k, v] if {
	some instr in input
	instr.Cmd == "env"
	some i
	i % 3 == 0
	k := instr.Value[i]
	v := instr.Value[i + 1]
}

run_lines contains line if {
	some instr in input
	instr.Cmd == "run"
	line := concat(" ", instr.Value)
}

warn contains msg if {
	some img in from_images
	some base in classical_bases
	base_match(img, base)
	msg := sprintf("PQ-D1: base image %s has no PQ by default (OpenSSL < 3.5 or runtime too old). Use debian:trixie, alpine:3.22+, node:22.20+/24.5+, golang:1.26+, JDK 25.", [img])
}

# Official python images default to Debian trixie (OpenSSL 3.5, PQ) for every tag, 3.9 to 3.15;
# only the explicit -bookworm (OpenSSL 3.0) and -bullseye (1.1.1) variants are classical.
warn contains msg if {
	some img in from_images
	regex.match(`^python:[^@]*-(bookworm|bullseye)([-@]|$)`, img)
	msg := sprintf("PQ-D1: base image %s is Debian bookworm/bullseye (OpenSSL < 3.5, no PQ). Use the default tag or -trixie.", [img])
}

# Official Node bundles OpenSSL 3.5 from 22.20.0 and 24.5.0; a tag pinned below that is classical.
# Floating tags (node:22, node:24) resolve to current releases and pass.
warn contains msg if {
	some img in from_images
	regex.match(`^node:(22\.([0-9]|1[0-9])|24\.[0-4])([.@-]|$)`, img)
	msg := sprintf("PQ-D1: base image %s pins Node below 22.20 / 24.5 (bundled OpenSSL 3.0, no PQ). Use 22.20+ or 24.9+.", [img])
}

deny contains msg if {
	some [k, v] in env_pairs
	k == "GODEBUG"
	contains(v, "tlsmlkem=0")
	msg := "PQ-D2: ENV GODEBUG tlsmlkem=0 disables X25519MLKEM768 in Go"
}

deny contains msg if {
	some [k, v] in env_pairs
	k == "OPENSSL_CONF"
	v == "/dev/null"
	msg := "PQ-D3: ENV OPENSSL_CONF=/dev/null drops PQ group configuration"
}

deny contains msg if {
	some [k, v] in env_pairs
	k in {"JAVA_TOOL_OPTIONS", "JAVA_OPTS", "JDK_JAVA_OPTIONS"}
	contains(v, "jdk.tls.namedGroups=")
	not contains(v, "X25519MLKEM768")
	msg := sprintf("PQ-D4: %s sets jdk.tls.namedGroups without X25519MLKEM768", [k])
}

deny contains msg if {
	some line in run_lines
	regex.match(`update-crypto-policies\s+--set\s+(DEFAULT|LEGACY|FUTURE)\s*($|[;&])`, line)
	msg := "PQ-D5: update-crypto-policies sets a policy without the :PQ subpolicy (use DEFAULT:PQ on AL2023/RHEL)"
}

# "node:20" matches node:20, node:20-slim, node:20.18 but not node:200; "amazonlinux:2" does not match amazonlinux:2023.
base_match(img, base) if img == base

base_match(img, base) if startswith(img, concat("", [base, "-"]))

base_match(img, base) if startswith(img, concat("", [base, "."]))

base_match(img, base) if startswith(img, concat("", [base, "@"]))
```

### Kubernetes

`rules/k8s/kyverno-pq-tls-cel.yaml`

```yaml
# Kyverno 1.20+ (CEL ValidatingPolicy). Kyverno 1.20 no longer executes kyverno.io/v1 ClusterPolicy.
# Start with validationActions [Audit]; switch to [Deny] after the warn window.
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: pq-tls-alb-ingress
spec:
  validationActions: [ Audit ]
  matchConstraints:
    resourceRules:
      - apiGroups: [ networking.k8s.io ]
        apiVersions: [ v1 ]
        operations: [ CREATE, UPDATE ]
        resources: [ ingresses ]
  variables:
    - name: ann
      expression: "has(object.metadata.annotations) ? object.metadata.annotations : {}"
    - name: pq
      expression: >-
        ['ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09','ELBSecurityPolicy-TLS13-1-2-Res-FIPS-PQ-2025-09',
        'ELBSecurityPolicy-TLS13-1-2-PQ-2025-09','ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09',
        'ELBSecurityPolicy-TLS13-1-2-Ext0-FIPS-PQ-2025-09','ELBSecurityPolicy-TLS13-1-2-Ext1-PQ-2025-09',
        'ELBSecurityPolicy-TLS13-1-2-Ext1-FIPS-PQ-2025-09','ELBSecurityPolicy-TLS13-1-2-Ext2-PQ-2025-09',
        'ELBSecurityPolicy-TLS13-1-2-Ext2-FIPS-PQ-2025-09','ELBSecurityPolicy-TLS13-1-3-PQ-2025-09',
        'ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09']
  matchConditions:
    - name: alb-class
      expression: >-
        (has(object.spec.ingressClassName) && object.spec.ingressClassName == 'alb') ||
        (has(object.metadata.annotations) && object.metadata.annotations[?'kubernetes.io/ingress.class'].orValue('') == 'alb')
    - name: tls-and-no-exception
      expression: >-
        has(object.metadata.annotations) &&
        'alb.ingress.kubernetes.io/certificate-arn' in object.metadata.annotations &&
        !('pq-tls.example.com/exception' in object.metadata.annotations)
  validations:
    - expression: "variables.ann[?'alb.ingress.kubernetes.io/ssl-policy'].orValue('') in variables.pq"
      message: "PQ-K1: set alb.ingress.kubernetes.io/ssl-policy to a -PQ-2025-09 policy (default ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09)"
---
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: pq-tls-nlb-service
spec:
  validationActions: [ Audit ]
  matchConstraints:
    resourceRules:
      - apiGroups: [ "" ]
        apiVersions: [ v1 ]
        operations: [ CREATE, UPDATE ]
        resources: [ services ]
  matchConditions:
    - name: tls-lb
      expression: >-
        object.spec.type == 'LoadBalancer' && has(object.metadata.annotations) &&
        'service.beta.kubernetes.io/aws-load-balancer-ssl-cert' in object.metadata.annotations &&
        !('pq-tls.example.com/exception' in object.metadata.annotations)
  validations:
    - expression: >-
        object.metadata.annotations[?'service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy'].orValue('')
        .matches('^ELBSecurityPolicy-TLS13-1-[23]-.*PQ-2025-09$')
      message: "PQ-K2: set service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy to a -PQ-2025-09 policy"
---
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: pq-tls-ingress-nginx-curves
spec:
  validationActions: [ Audit ]
  matchConstraints:
    resourceRules:
      - apiGroups: [ "" ]
        apiVersions: [ v1 ]
        operations: [ CREATE, UPDATE ]
        resources: [ configmaps ]
  matchConditions:
    - name: controller-cm
      expression: "object.metadata.name == 'ingress-nginx-controller'"
  validations:
    - expression: "has(object.data) && object.data[?'ssl-ecdh-curve'].orValue('').startsWith('X25519MLKEM768')"
      message: "PQ-K3: set data.ssl-ecdh-curve to X25519MLKEM768:X25519:prime256v1"
---
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: pq-tls-istiod
spec:
  validationActions: [ Audit ]
  matchConstraints:
    resourceRules:
      - apiGroups: [ apps ]
        apiVersions: [ v1 ]
        operations: [ CREATE, UPDATE ]
        resources: [ deployments ]
  matchConditions:
    - name: istiod
      expression: "object.metadata.namespace == 'istio-system' && object.metadata.name.startsWith('istiod')"
  validations:
    - expression: >-
        object.spec.template.spec.containers.exists(c, c.name == 'discovery' && has(c.env) &&
        c.env.exists(e, e.name == 'COMPLIANCE_POLICY' && has(e.value) && e.value == 'pqc'))
      message: "PQ-K4: istiod container needs env COMPLIANCE_POLICY=pqc"
---
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: pq-tls-workload-env
spec:
  validationActions: [ Audit ]
  matchConstraints:
    resourceRules:
      - apiGroups: [ "" ]
        apiVersions: [ v1 ]
        operations: [ CREATE, UPDATE ]
        resources: [ pods ]
  variables:
    - name: envs
      expression: >-
        object.spec.containers.filter(c, has(c.env)).map(c, c.env).flatten()
  validations:
    - expression: "!variables.envs.exists(e, e.name == 'GODEBUG' && has(e.value) && e.value.contains('tlsmlkem=0'))"
      message: "PQ-K6: GODEBUG tlsmlkem=0 disables X25519MLKEM768 in Go"
    - expression: "!variables.envs.exists(e, e.name == 'OPENSSL_CONF' && has(e.value) && e.value == '/dev/null')"
      message: "PQ-K7: OPENSSL_CONF=/dev/null drops the PQ group configuration"
```

`rules/k8s/kyverno-pq-tls.yaml` (Kyverno 1.19 and earlier)

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: pq-tls-aws-load-balancers
  annotations:
    policies.kyverno.io/title: PQ TLS policy on AWS Load Balancer Controller Ingress and Service
    policies.kyverno.io/category: PQ TLS
    policies.kyverno.io/description: >-
      ALB Ingresses and NLB Services that terminate TLS must name a -PQ-2025-09 ELB security policy.
      Without the annotation the controller uses ELBSecurityPolicy-2016-08 (no PQ).
spec:
  background: true
  rules:
    - name: alb-ingress-ssl-policy
      match:
        any:
          - resources:
              kinds: [ Ingress ]
      preconditions:
        all:
          - key: "{{ request.object.spec.ingressClassName || request.object.metadata.annotations.\"kubernetes.io/ingress.class\" || '' }}"
            operator: Equals
            value: alb
          - key: "{{ request.object.metadata.annotations.\"alb.ingress.kubernetes.io/certificate-arn\" || request.object.metadata.annotations.\"alb.ingress.kubernetes.io/listen-ports\" || '' }}"
            operator: NotEquals
            value: ""
          - key: "{{ request.object.metadata.annotations.\"pq-tls.example.com/exception\" || '' }}"
            operator: Equals
            value: ""
      validate:
        failureAction: Audit
        message: >-
          PQ-K1: set alb.ingress.kubernetes.io/ssl-policy to a -PQ-2025-09 policy
          (default choice ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09).
        deny:
          conditions:
            all:
              - key: "{{ request.object.metadata.annotations.\"alb.ingress.kubernetes.io/ssl-policy\" || '' }}"
                operator: AnyNotIn
                value:
                  - ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Res-FIPS-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Ext0-FIPS-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Ext1-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Ext1-FIPS-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Ext2-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Ext2-FIPS-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-3-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09
    - name: nlb-service-ssl-negotiation-policy
      match:
        any:
          - resources:
              kinds: [ Service ]
      preconditions:
        all:
          - key: "{{ request.object.spec.type || '' }}"
            operator: Equals
            value: LoadBalancer
          - key: "{{ request.object.metadata.annotations.\"service.beta.kubernetes.io/aws-load-balancer-ssl-cert\" || '' }}"
            operator: NotEquals
            value: ""
          - key: "{{ request.object.metadata.annotations.\"pq-tls.example.com/exception\" || '' }}"
            operator: Equals
            value: ""
      validate:
        failureAction: Audit
        message: >-
          PQ-K2: set service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy to a -PQ-2025-09 policy.
        deny:
          conditions:
            all:
              - key: "{{ request.object.metadata.annotations.\"service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy\" || '' }}"
                operator: AnyNotIn
                value:
                  - ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Res-FIPS-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Ext0-FIPS-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Ext1-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Ext1-FIPS-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Ext2-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Ext2-FIPS-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-3-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: pq-tls-ingress-nginx-curves
  annotations:
    policies.kyverno.io/title: ingress-nginx offers X25519MLKEM768
    policies.kyverno.io/description: >-
      The ingress-nginx controller ConfigMap must list X25519MLKEM768 first in ssl-ecdh-curve.
      Only effective when the controller image links OpenSSL 3.5+.
spec:
  background: true
  rules:
    - name: ssl-ecdh-curve-has-mlkem
      match:
        any:
          - resources:
              kinds: [ ConfigMap ]
              names: [ ingress-nginx-controller ]
      validate:
        failureAction: Audit
        message: "PQ-K3: set data.ssl-ecdh-curve to X25519MLKEM768:X25519:prime256v1"
        pattern:
          data:
            ssl-ecdh-curve: "X25519MLKEM768*"
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: pq-tls-istio-compliance-policy
  annotations:
    policies.kyverno.io/title: Istio control plane runs with COMPLIANCE_POLICY=pqc
    policies.kyverno.io/description: >-
      Istio 1.27+: COMPLIANCE_POLICY=pqc on istiod restricts mesh mTLS to TLS 1.3 with X25519MLKEM768.
      Set the same value for proxies (meshConfig.defaultConfig.proxyMetadata) and ztunnel in ambient mode.
spec:
  background: true
  rules:
    - name: istiod-env
      match:
        any:
          - resources:
              kinds: [ Deployment ]
              namespaces: [ istio-system ]
              selector:
                matchLabels:
                  app: istiod
      validate:
        failureAction: Audit
        message: "PQ-K4: istiod container needs env COMPLIANCE_POLICY=pqc"
        deny:
          conditions:
            all:
              - key: pqc
                operator: AnyNotIn
                value: "{{ request.object.spec.template.spec.containers[?name=='discovery'].env[] | [?name=='COMPLIANCE_POLICY'].value || `[]` }}"
    - name: ztunnel-env
      match:
        any:
          - resources:
              kinds: [ DaemonSet ]
              namespaces: [ istio-system ]
              names: [ ztunnel ]
      validate:
        failureAction: Audit
        message: "PQ-K5: ztunnel needs env COMPLIANCE_POLICY=pqc"
        deny:
          conditions:
            all:
              - key: pqc
                operator: AnyNotIn
                value: "{{ request.object.spec.template.spec.containers[].env[] | [?name=='COMPLIANCE_POLICY'].value || `[]` }}"
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: pq-tls-workload-env
  annotations:
    policies.kyverno.io/title: Workloads do not switch PQ off
    policies.kyverno.io/description: >-
      Blocks GODEBUG tlsmlkem=0, OPENSSL_CONF=/dev/null and jdk.tls.namedGroups without X25519MLKEM768 in Pod specs.
spec:
  background: true
  rules:
    - name: no-godebug-tlsmlkem-off
      match:
        any:
          - resources:
              kinds: [ Pod ]
      validate:
        failureAction: Audit
        message: "PQ-K6: GODEBUG tlsmlkem=0 disables X25519MLKEM768 in Go"
        foreach:
          - list: "request.object.spec.[containers, initContainers][][].env[?name=='GODEBUG'][]"
            deny:
              conditions:
                any:
                  - key: "{{ element.value || '' }}"
                    operator: Equals
                    value: "*tlsmlkem=0*"
    - name: no-openssl-conf-devnull
      match:
        any:
          - resources:
              kinds: [ Pod ]
      validate:
        failureAction: Audit
        message: "PQ-K7: OPENSSL_CONF=/dev/null drops the PQ group configuration"
        foreach:
          - list: "request.object.spec.[containers, initContainers][][].env[?name=='OPENSSL_CONF'][]"
            deny:
              conditions:
                any:
                  - key: "{{ element.value || '' }}"
                    operator: Equals
                    value: /dev/null
```

`rules/k8s/gatekeeper-pq-tls.yaml`

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8spqtlselbpolicy
spec:
  crd:
    spec:
      names:
        kind: K8sPqTlsElbPolicy
      validation:
        openAPIV3Schema:
          type: object
          properties:
            allowedPolicies:
              type: array
              items: { type: string }
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8spqtlselbpolicy

        ann := object.get(input.review.object.metadata, "annotations", {})

        exempt { ann["pq-tls.example.com/exception"] }

        violation[{"msg": msg}] {
          input.review.kind.kind == "Ingress"
          object.get(input.review.object.spec, "ingressClassName", "") == "alb"
          ann["alb.ingress.kubernetes.io/certificate-arn"]
          not exempt
          p := object.get(ann, "alb.ingress.kubernetes.io/ssl-policy", "")
          not allowed(p)
          msg := sprintf("PQ-K1: alb.ingress.kubernetes.io/ssl-policy %q is not a -PQ-2025-09 policy", [p])
        }

        violation[{"msg": msg}] {
          input.review.kind.kind == "Service"
          input.review.object.spec.type == "LoadBalancer"
          ann["service.beta.kubernetes.io/aws-load-balancer-ssl-cert"]
          not exempt
          p := object.get(ann, "service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy", "")
          not allowed(p)
          msg := sprintf("PQ-K2: aws-load-balancer-ssl-negotiation-policy %q is not a -PQ-2025-09 policy", [p])
        }

        allowed(p) { p == input.parameters.allowedPolicies[_] }
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPqTlsElbPolicy
metadata:
  name: pq-tls-elb-policy
spec:
  enforcementAction: warn
  match:
    kinds:
      - apiGroups: [ networking.k8s.io ]
        kinds: [ Ingress ]
      - apiGroups: [ "" ]
        kinds: [ Service ]
  parameters:
    allowedPolicies:
      - ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09
      - ELBSecurityPolicy-TLS13-1-2-Res-FIPS-PQ-2025-09
      - ELBSecurityPolicy-TLS13-1-2-PQ-2025-09
      - ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09
      - ELBSecurityPolicy-TLS13-1-2-Ext0-FIPS-PQ-2025-09
      - ELBSecurityPolicy-TLS13-1-2-Ext1-PQ-2025-09
      - ELBSecurityPolicy-TLS13-1-2-Ext1-FIPS-PQ-2025-09
      - ELBSecurityPolicy-TLS13-1-2-Ext2-PQ-2025-09
      - ELBSecurityPolicy-TLS13-1-2-Ext2-FIPS-PQ-2025-09
      - ELBSecurityPolicy-TLS13-1-3-PQ-2025-09
      - ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09
```

### Runtime

`rules/runtime/cloudtrail-alarm.yaml`

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: >
  Metric filter + alarm on the organisation trail's CloudWatch Logs group: API calls to PQ-capable
  endpoints that did not negotiate ML-KEM. Pattern extends the one in the AWS KMS developer guide
  to the six services that record tlsDetails.keyExchange.
Parameters:
  TrailLogGroup: { Type: String }
  AlarmTopicArn: { Type: String }
Resources:
  NonPqApiCalls:
    Type: AWS::Logs::MetricFilter
    Properties:
      LogGroupName: !Ref TrailLogGroup
      FilterName: pq-tls-non-pq-api-calls
      FilterPattern: >-
        { (($.eventSource = "kms.amazonaws.com") || ($.eventSource = "sts.amazonaws.com") ||
        ($.eventSource = "iam.amazonaws.com") || ($.eventSource = "secretsmanager.amazonaws.com") ||
        ($.eventSource = "acm.amazonaws.com") || ($.eventSource = "payment-cryptography.amazonaws.com")) &&
        ($.userIdentity.invokedBy NOT EXISTS) &&
        (($.tlsDetails.keyExchange != "*MLKEM*") || ($.tlsDetails.keyExchange NOT EXISTS)) }
      MetricTransformations:
        - MetricNamespace: PqTls
          MetricName: NonPqApiCalls
          MetricValue: "1"
          DefaultValue: 0
  NonPqApiCallsAlarm:
    Type: AWS::CloudWatch::Alarm
    Properties:
      AlarmName: pq-tls-non-pq-api-calls
      AlarmDescription: Classical (non-ML-KEM) TLS to KMS/STS/IAM/Secrets Manager/ACM/Payment Cryptography. Run cloudtrail-non-pq.sql to find the callers.
      Namespace: PqTls
      MetricName: NonPqApiCalls
      Statistic: Sum
      Period: 3600
      EvaluationPeriods: 1
      Threshold: 1
      ComparisonOperator: GreaterThanOrEqualToThreshold
      TreatMissingData: notBreaching
      AlarmActions: [ !Ref AlarmTopicArn ]
```

`rules/runtime/cloudtrail-non-pq.sql`

```sql
-- cloudtrail-non-pq.sql
-- Callers that reached a PQ-capable AWS endpoint WITHOUT hybrid PQ key exchange.
-- tlsDetails.keyExchange is recorded only for KMS, STS, IAM, Secrets Manager, ACM and Payment Cryptography.
-- Calls an AWS service makes on your behalf carry no tlsDetails; they are excluded via invokedBy.

-- (A) CloudTrail Lake. Replace $EDS_ID with the event data store ID.
SELECT
  eventSource,
  userIdentity.arn            AS principal,
  userAgent,
  sourceIPAddress,
  tlsDetails.tlsVersion       AS tls_version,
  tlsDetails.keyExchange      AS key_exchange,
  count(*)                    AS calls
FROM $EDS_ID
WHERE eventTime > date_add('day', -7, now())
  AND eventSource IN ('kms.amazonaws.com', 'sts.amazonaws.com', 'iam.amazonaws.com',
                      'secretsmanager.amazonaws.com', 'acm.amazonaws.com',
                      'payment-cryptography.amazonaws.com')
  AND userIdentity.invokedBy IS NULL
  AND (tlsDetails.keyExchange IS NULL OR tlsDetails.keyExchange NOT LIKE '%MLKEM%')
GROUP BY 1, 2, 3, 4, 5, 6
ORDER BY calls DESC
LIMIT 500;

-- (B) Athena over the CloudTrail S3 trail. The table DDL must declare keyExchange inside tlsdetails:
--   tlsdetails STRUCT<tlsversion:STRING, ciphersuite:STRING, clienthostheader:STRING, keyexchange:STRING>
-- (the stock DDL in the Athena docs predates keyExchange; add the field, Hive JSON SerDe ignores case).
SELECT
  eventsource,
  useridentity.arn            AS principal,
  useragent,
  tlsdetails.tlsversion       AS tls_version,
  tlsdetails.keyexchange      AS key_exchange,
  count(*)                    AS calls
FROM cloudtrail_logs
WHERE timestamp >= date_format(current_date - interval '7' day, '%Y/%m/%d')
  AND eventsource IN ('kms.amazonaws.com', 'sts.amazonaws.com', 'iam.amazonaws.com',
                      'secretsmanager.amazonaws.com', 'acm.amazonaws.com',
                      'payment-cryptography.amazonaws.com')
  AND useridentity.invokedby IS NULL
  AND (tlsdetails.keyexchange IS NULL OR tlsdetails.keyexchange NOT LIKE '%MLKEM%')
GROUP BY 1, 2, 3, 4, 5
ORDER BY calls DESC
LIMIT 500;
```

`rules/runtime/eventbridge-rules.json`

```json
{
  "pq-tls-listener-changed-to-classical": {
    "source": ["aws.elasticloadbalancing"],
    "detail-type": ["AWS API Call via CloudTrail"],
    "detail": {
      "eventSource": ["elasticloadbalancing.amazonaws.com"],
      "eventName": ["CreateListener", "ModifyListener"],
      "requestParameters": {
        "sslPolicy": [{ "anything-but": { "wildcard": "ELBSecurityPolicy-TLS13-1-[23]*PQ-2025-09" } }]
      }
    }
  },
  "pq-tls-apigw-policy-changed": {
    "source": ["aws.apigateway"],
    "detail-type": ["AWS API Call via CloudTrail"],
    "detail": {
      "eventSource": ["apigateway.amazonaws.com"],
      "eventName": ["CreateDomainName", "UpdateDomainName", "CreateRestApi", "UpdateRestApi", "ImportRestApi", "PutRestApi"]
    }
  },
  "pq-tls-config-noncompliant": {
    "source": ["aws.config"],
    "detail-type": ["Config Rules Compliance Change"],
    "detail": {
      "configRuleName": [{ "prefix": "OrgConfigRule-pq-tls-" }, { "prefix": "pq-tls-" }],
      "newEvaluationResult": { "complianceType": ["NON_COMPLIANT"] }
    }
  },
  "pq-tls-guard-hook-failed": {
    "source": ["aws.cloudformation"],
    "detail-type": ["CloudFormation Hook Invocation Progress"],
    "detail": {
      "hook-type": [{ "prefix": "Private::Guard::PqTls" }]
    }
  }
}
```

`rules/runtime/elb-logs-athena.sql`

```sql
-- elb-logs-athena.sql: classical vs PQ handshakes at ALB (connection logs) and NLB (TLS access logs).

-- ALB connection logs (15 space-separated fields; tls_keyexchange = field 13).
CREATE EXTERNAL TABLE IF NOT EXISTS alb_connection_logs (
  time string, client_ip string, client_port int, listener_port int,
  tls_protocol string, tls_cipher string, tls_handshake_latency double,
  leaf_client_cert_subject string, leaf_client_cert_validity string, leaf_client_cert_serial_number string,
  tls_verify_status string, conn_trace_id string, tls_keyexchange string, elb string, ip_address string)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.RegexSerDe'
WITH SERDEPROPERTIES ('input.regex' =
  '([^ ]*) ([^ ]*) ([0-9]*) ([0-9]*) ([^ ]*) ([^ ]*) ([-.0-9]*) ("[^"]*"|[^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ?([^ ]*)? ?([^ ]*)?.*')
LOCATION 's3://LOG_BUCKET/PREFIX/AWSLogs/ACCOUNT_ID/elasticloadbalancing/REGION/';

SELECT elb, listener_port, tls_protocol, tls_keyexchange, count(*) AS conns,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY elb), 1) AS pct
FROM alb_connection_logs
WHERE tls_protocol <> '-' AND tls_verify_status = 'Success'
GROUP BY 1, 2, 3, 4 ORDER BY elb, conns DESC;

-- Top classical clients (for the exception register / client upgrade list)
SELECT client_ip, tls_protocol, tls_keyexchange, count(*) AS conns
FROM alb_connection_logs
WHERE tls_protocol <> '-' AND tls_keyexchange NOT LIKE '%MLKEM%'
GROUP BY 1, 2, 3 ORDER BY conns DESC LIMIT 100;

-- NLB TLS access logs (tls_keyexchange = field 17).
CREATE EXTERNAL TABLE IF NOT EXISTS nlb_tls_logs (
  type string, version string, time string, elb string, listener string, client_port string,
  destination_port string, connection_time double, tls_handshake_time string, received_bytes bigint,
  sent_bytes bigint, incoming_tls_alert string, chosen_cert_arn string, chosen_cert_serial string,
  tls_cipher string, tls_protocol_version string, tls_keyexchange string, domain_name string,
  alpn_fe_protocol string, alpn_be_protocol string, alpn_client_preference_list string,
  tls_connection_creation_time string)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.RegexSerDe'
WITH SERDEPROPERTIES ('input.regex' =
  '([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([-.0-9]*) ([^ ]*) ([-0-9]*) ([-0-9]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ("[^"]*"|[^ ]*) ?([^ ]*)?.*')
LOCATION 's3://LOG_BUCKET/PREFIX/AWSLogs/ACCOUNT_ID/elasticloadbalancing/REGION/';

SELECT elb, tls_protocol_version, tls_keyexchange, count(*) AS conns
FROM nlb_tls_logs
WHERE tls_protocol_version <> '-'
GROUP BY 1, 2, 3 ORDER BY conns DESC;

-- Alarm feed: run hourly (EventBridge Scheduler -> Athena StartQueryExecution via Step Functions)
-- and publish the share of non-ML-KEM TLS 1.3+1.2 handshakes as a CloudWatch metric.
SELECT count_if(tls_keyexchange NOT LIKE '%MLKEM%') AS classical,
       count(*) AS total
FROM alb_connection_logs
WHERE tls_protocol <> '-'
  AND from_iso8601_timestamp(time) > now() - interval '1' hour;
```
