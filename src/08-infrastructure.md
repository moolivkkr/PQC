# Infrastructure and services

Most infrastructure can be made PQ by configuration you control today; a few legs are blocked until AWS ships support. Each section that follows covers one area: what decides PQ, status, the server-side change, verification, pitfalls and the configuration files.

Where an area's client is our own code (an SDK calling AWS, a database driver, an app behind a mesh), the fix is the language fix: those sections point to [Solutions by language](#ch-15-languages) and [Solutions by compute type](#ch-14-compute) rather than repeat it, and add only what is specific to the service.

## Areas at a glance

| Area | PQ today | Main action | Blocked by AWS | Risk |
| --- | --- | --- | --- | --- |
| Load balancers | ALB and NLB opt-in; Classic none | Set the 2025-09 PQ policy; SCP on `elasticloadbalancing:SecurityPolicy` (CreateListener, ModifyListener) | Classic LB (migrate) | IaC defaults to the classical 2016-08 policy; Security Hub ELB.17 passes non-PQ policies; the target leg follows the target's own TLS (Tested, 32 e2e cases) |
| Edge and API front doors | CloudFront viewer on; API Gateway REST opt-in (TLS 1.2+1.3 only); Transfer Family SFTP on 2025-03 policies | Set REST PQ policies; front HTTP and WebSocket APIs with CloudFront or a PQ ALB | CloudFront origin leg, API Gateway egress, HTTP and WebSocket APIs | Fronting HTTP and WebSocket APIs adds a hop, cost and a failure point; origin legs stay classical |
| AWS service endpoints | KMS, Secrets Manager, STS, IAM, ACM, S3, DynamoDB on; others control plane or unlisted | Client-side fixes only (language runbooks); CloudTrail `keyExchange` for detection | SSM and other unlisted services | Only CloudTrail-logged calls can be proven PQ; the rest rely on posture |
| Network devices and egress | AWS network services undocumented; Squid, Envoy, strongSwan 6.0.2+ and vendor appliances ready | Use a PQ egress proxy for what can't upgrade; Zeek for detection | Network Firewall TLS inspection, AWS VPN | TLS inspection re-terminates connections, so inspected traffic is classical; AWS VPN has no PQ option |
| IoT | Classical into IoT Core; wolfSSL, awscrt and Mosquitto on OpenSSL 3.5 can do PQ | Inventory TLS stacks; PQ-capable stacks for new devices; PQ gateways and brokers | IoT Core (no PQ policy) | Devices live 10+ years: the TLS stack and roots in firmware shipped now decide PQ for a decade; IoT Core has no ML-DSA either |
| Service mesh | Linkerd 2.19+ on; Istio 1.27+, Consul 2.1+, Envoy opt-in | Upgrade or set mesh config (Istio `COMPLIANCE_POLICY=pqc` is PQ-only) | ECS Service Connect (no setting) | Istio `COMPLIANCE_POLICY=pqc` is PQ-only and cuts off classical peers; ECS Service Connect has no setting |
| Databases and data services | RDS and Aurora opt-in by version; PG18, MySQL 26.7+, Valkey 8.1 self-managed | Engine upgrade, `ssl_groups` or group config, PQ-capable drivers | RDS Proxy, ElastiCache, MSK, OpenSearch | Engine and driver must both support the group; engine upgrades need maintenance windows; managed proxies and caches stay classical |
| Hosts and OS | AL2023 and RHEL opt-in; Debian 13 and Ubuntu 26.04 on for OpenSSL programs only (not GnuTLS); Windows opt-in | `DEFAULT:PQ` via SSM; Schannel group via GPO or SSM | Amazon Linux 2 (migrate) | Host-wide `DEFAULT:PQ` changes every OpenSSL program at once; GnuTLS tools (wget, git on Debian) stay classical; AL2023 also needs `SignatureAlgorithms` for ML-DSA |
| Certificates (ML-DSA) | Private CA, KMS, Roles Anywhere can issue ML-DSA | CLM pilot on internal mutual TLS after ML-KEM | ACM, ELB, CloudFront, public web PKI | An ML-DSA-only server breaks Go, Java, OpenSSL 3.0 and default AL2023 clients; chains grow 0.9 KB to 11.8 KB; composite certificates have no TLS code points yet |
| WAF | AWS WAF never terminates TLS: the attached resource decides | Set PQ on the resource; reverse-proxy WAFs need their own PQ profile | Same as the resource it protects | A WAF on a classical listener looks protected but is not PQ |
| Web servers and proxies | OpenSSL 3.5, Go 1.24+ and JDK 25 servers PQ with one or two lines; Envoy and AL2023 builds classical until set | Set the group list on both the listener and the upstream leg | None (self-managed) | Setting only the listener leaves the upstream leg classical; Envoy before 1.40 is classical unless `ecdh_curves` is set |
| Mobile, desktop and CLI clients | Chrome, Edge, Firefox, Safari and Apple 26 OS stacks PQ; Windows Schannel opt-in; Android platform TLS not confirmed; macOS LibreSSL curl and GnuTLS tools not | Upgrade CI toolboxes and clients; PQ only shows once the server offers it | None (client-side) | macOS LibreSSL curl and Debian GnuTLS tools stay classical; Android platform TLS not confirmed |

## Inbound: front doors and TLS 1.3 enforcement

Inbound connections become PQ when the front door's TLS policy offers ML-KEM and the caller supports it. Allow TLS 1.2 and 1.3 first, measure, then move each endpoint to TLS 1.3 only once its TLS 1.2 traffic reaches zero. TLS negotiation already picks 1.3 when both sides support it, and TLS 1.3's downgrade protection stops an attacker forcing 1.2.

| Front door | PQ setting | Notes | Evidence |
| --- | --- | --- | --- |
| ALB, NLB | `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09` (allows 1.2 and 1.3), later `ELBSecurityPolicy-TLS13-1-3-PQ-2025-09` (1.3 only); FIPS variants exist | Console default is a PQ policy, but CLI, CloudFormation and CDK default to `ELBSecurityPolicy-2016-08`. The backend leg also becomes PQ-capable: AWS then uses `ELBSecurityPolicy-TLS13-1-0-PQ-2025-09` towards HTTPS targets, and the hop is PQ only when the target has its language fix (e2e target-leg cases, 2026-11-15; LocalStack can't test the listener leg itself). Enforce in an SCP with the `elasticloadbalancing:SecurityPolicy` condition key, which applies to CreateListener and ModifyListener (not CreateLoadBalancer) | Documented |
| CloudFront | Viewer side PQ by default on all policies | Origin leg is classical; AWS says PQ is coming | Documented |
| API Gateway REST (Regional, private) | `SecurityPolicy_TLS13_1_2_PQ_2025_09` and variants | No TLS 1.3-only PQ policy exists. API Gateway egress to integrations is TLS 1.2 only, so that leg can never be PQ | Documented |
| API Gateway HTTP, WebSocket, edge-optimized | No PQ policy | Front with CloudFront or ALB if PQ is required | Documented (absence) |
| AWS IoT Core | No PQ policy | Every device leg classical until AWS adds one | Documented (absence) |
| Service mesh (EKS) | Linkerd 2.19+ PQ by default; Istio 1.27+ `COMPLIANCE_POLICY=pqc` (enforces PQ, breaks non-PQ peers) | Covers mesh-owned legs only, not app-originated TLS | Documented |

Move legacy callers that can't do TLS 1.3 to a separate listener or hostname that still allows 1.2, tracked as exceptions, rather than holding the main endpoint open for them. The SCP and Config rules that hold this line are on the Enforcement and guardrails tab. Check exact policy names with `aws elbv2 describe-ssl-policies` before putting them in templates.

## Exceptions

Record every "blocked by AWS" leg in the exception register and recheck it against AWS's PQ readiness page each quarter.
