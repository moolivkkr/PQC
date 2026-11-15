## What decides PQ here
The load balancer's security policy decides the client-facing leg: only policies with `PQ` in the name offer X25519MLKEM768, SecP256r1MLKEM768 and SecP384r1MLKEM1024 (TLS 1.3 only). The console defaults to a PQ policy; the CLI, CloudFormation, CDK, Terraform and the AWS Load Balancer Controller default to `ELBSecurityPolicy-2016-08`, which is classical. The target leg uses a backend policy AWS picks from your listener policy; the target's own TLS stack decides whether that hop is PQ. ([ALB policies](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/describe-ssl-policies.html), [NLB policies](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/describe-ssl-policies.html), Documented)

## Status matrix
| Load balancer / listener | Device type | Client leg PQ | Target leg | Default from IaC | Evidence |
|---|---|---|---|---|---|
| ALB, HTTPS listener | Managed AWS service | Opt-in PQ policy | Backend policy `ELBSecurityPolicy-TLS13-1-0-PQ-2025-09` when any listener is PQ; PQ only if the target offers ML-KEM | `ELBSecurityPolicy-2016-08` (classical) | Documented |
| NLB, TLS listener | Managed AWS service | Opt-in PQ policy | Same backend rule for TLS target groups; plaintext for TCP target groups | `ELBSecurityPolicy-2016-08` | Documented |
| NLB, TCP/UDP listener | Managed AWS service | Pass-through: client and target negotiate end to end | Same connection | n/a | Documented |
| Gateway Load Balancer | Managed AWS service, GENEVE to appliances | No TLS listener: end-to-end between client and server; an inspecting appliance behind it uses its own TLS stack (see Network devices tab) | n/a | n/a | Documented (no TLS listener type) |
| Classic Load Balancer | Managed AWS service (legacy) | No PQ policy; migrate to ALB or NLB | Classical | n/a | Documented |
| ALB/NLB via AWS Load Balancer Controller (EKS) | Kubernetes controller | Annotation or IngressClassParams | Annotation `backend-protocol` | `ELBSecurityPolicy-2016-08` unless `defaultSSLPolicy` is set | Documented ([LBC docs](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/)) |
| Lightsail load balancer | Managed (Lightsail) | No: only `TLS-2016-08` and `TLS-FS-1-2-Res-2019-08` | Classical | `TLS-2016-08` | Documented ([Lightsail](https://docs.aws.amazon.com/lightsail/latest/userguide/amazon-lightsail-configure-load-balancer-tls-security-policy.html)) |
| Elastic Beanstalk, App Runner behind ELB | Managed, uses ELB | Whatever policy you set on the ELB listener (Beanstalk); App Runner exposes no policy | As above | Platform default | Unverified for App Runner |

PQ policy names (all `-2025-09`): `TLS13-1-2-Res-PQ` (AWS recommends), `TLS13-1-2-PQ`, `TLS13-1-2-Ext1-PQ`, `TLS13-1-2-Ext2-PQ`, `TLS13-1-3-PQ`; FIPS: `TLS13-1-2-Res-FIPS-PQ`, `TLS13-1-2-FIPS-PQ`, `TLS13-1-2-Ext0-FIPS-PQ`, `TLS13-1-2-Ext1-FIPS-PQ`, `TLS13-1-2-Ext2-FIPS-PQ`, `TLS13-1-3-FIPS-PQ`; backend-only: `TLS13-1-0-PQ`, `TLS13-1-0-FIPS-PQ`. Prefix each with `ELBSecurityPolicy-`. Documented.

## Client side: the load balancer's connection to targets
The load balancer is the TLS client on the target leg. You cannot choose its policy. AWS uses `ELBSecurityPolicy-TLS13-1-0-PQ-2025-09` if any listener uses a PQ policy (`-TLS13-1-0-FIPS-PQ-2025-09` for FIPS PQ; an RFC 9151 listener overrides both). It offers ML-KEM groups, so the hop is PQ only when the target accepts one. AWS does not log the group negotiated to the target (Documented absence).

| Target type | What the target must run for a PQ hop | Evidence |
|---|---|---|
| ALB HTTPS target group (EC2, ECS, EKS pods) | A TLS 1.3 server whose library offers X25519MLKEM768: nginx/Apache/HAProxy/Envoy on OpenSSL 3.5+ (Debian 13, Alpine 3.24), Go 1.24+, Java 25, .NET on OpenSSL 3.5. See the Web servers tab and the language tabs. | Documented (policy) + Tested (servers, other tabs) |
| ALB HTTP target group | Plaintext inside the VPC: no TLS on this hop at all | Documented |
| ALB Lambda target | Invoked by the service, not a TLS connection you control | Documented |
| NLB TLS target group | Same as ALB HTTPS targets | Documented |
| NLB TCP target group behind a TLS listener | Plaintext to the target | Documented |
| NLB TCP listener (pass-through) | The target is the TLS server for the client; its stack decides PQ end to end | Documented |

To see the group on the target leg, log it on the target (nginx `$ssl_curve`, Envoy `%DOWNSTREAM_TLS_...%`; see the Web servers tab). The target sees the load balancer as its client.

## Server side: the listener
| Tool | Setting | PQ value |
|---|---|---|
| Console | Security policy | Default is already `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09` |
| AWS CLI | `aws elbv2 modify-listener --listener-arn ARN --ssl-policy ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09` | |
| CloudFormation | `AWS::ElasticLoadBalancingV2::Listener` `SslPolicy` | Tested (cfn-lint 1.60.1) |
| Terraform | `aws_lb_listener.ssl_policy` | Tested (validate, aws provider 6.73.0) |
| CDK | `sslPolicy: elbv2.SslPolicy.TLS13_12_RES_PQ` (enum added by aws-cdk PR #36297, merged 2026-03-19); older versions: pass the string | Documented (source) |
| LBC Ingress (ALB) | `alb.ingress.kubernetes.io/ssl-policy` or `IngressClassParams.spec.sslPolicy` (wins over the annotation) | Documented |
| LBC Service (NLB) | `service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy` | Documented |
| LBC cluster default | Helm `defaultSSLPolicy` / flag `--default-ssl-policy` | Documented |

Terraform excerpt:
```hcl
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
  certificate_arn   = var.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_https.arn
  }
}
```
CloudFormation excerpt:
```yaml
HttpsListener:
  Type: AWS::ElasticLoadBalancingV2::Listener
  Properties:
    LoadBalancerArn: !Ref Alb
    Port: 443
    Protocol: HTTPS
    SslPolicy: ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09
    Certificates: [{CertificateArn: !Ref CertificateArn}]
    DefaultActions: [{Type: forward, TargetGroupArn: !Ref AppTargetGroup}]
```
CDK (TypeScript):
```ts
alb.addListener('Https', {
  port: 443,
  certificates: [cert],
  sslPolicy: elbv2.SslPolicy.TLS13_12_RES_PQ,
  defaultTargetGroups: [tg],
});
```
EKS excerpt (ALB Ingress and NLB Service):
```yaml
alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09
alb.ingress.kubernetes.io/backend-protocol: HTTPS
---
service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy: ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09
service.beta.kubernetes.io/aws-load-balancer-backend-protocol: ssl
```
mTLS on ALB: mutual authentication (`verify` or `passthrough`) is a listener setting next to the policy, so a PQ policy and mTLS combine on one listener. The client certificate signature (RSA/ECDSA) is separate from the key exchange. A connection log failure code `ClientCertIncompatible` means the client certificate does not fit the chosen policy. Documented ([connection logs](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-connection-logs.html)); a PQ + mTLS handshake was not tested here.

## Packaging and rollout per platform
| Platform | Where the policy lives | File |
|---|---|---|
| Terraform | `aws_lb_listener.ssl_policy` | `iac/lb/main.tf` |
| CloudFormation | `SslPolicy` parameter with `AllowedValues` restricted to PQ policies | `iac/lb/lb.yaml` |
| EKS | `IngressClassParams.spec.sslPolicy` for ALB classes, Service annotation for NLB, Helm `defaultSSLPolicy` as the cluster default | `iac/lb/k8s-lbc.yaml` |
| Org guardrail | SCP on `elasticloadbalancing:SecurityPolicy` | `iac/lb/scp-elb-pq.json` |
| Detection | Athena tables and queries | `iac/lb/athena.sql` |

Rollout from TLS 1.2+1.3 to TLS 1.3-only:
1. Turn on ALB connection logs and NLB access logs (both are off by default) and create the Athena tables.
2. Move every HTTPS/TLS listener of a load balancer to `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09` in the same change. Nothing breaks: classical and TLS 1.2 clients still connect.
3. Watch Q1 (key-exchange mix) and Q2 (classical client IPs). Q4 joins user agents through `conn_trace_id`. Hand the client list to app owners (language tabs).
4. When Q3 (TLS 1.2 connections) is zero for the agreed window, move the listener to `ELBSecurityPolicy-TLS13-1-3-PQ-2025-09`. This still allows classical TLS 1.3 key exchange, so it ends TLS 1.2, not classical TLS 1.3.
5. There is no ELB policy that refuses classical TLS 1.3 key exchange. A PQ-only gate needs a server you control (Web servers tab).
6. Put remaining TLS 1.2 callers on a separate load balancer or hostname and record them as exceptions.

## Verify
Posture (no traffic needed):
```bash
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerArn' --output text | tr '\t' '\n' |
while read lb; do
  aws elbv2 describe-listeners --load-balancer-arn "$lb" \
    --query 'Listeners[?Protocol==`HTTPS`||Protocol==`TLS`].[ListenerArn,Protocol,SslPolicy]' --output text
done | awk '$3 !~ /PQ-2025-09$/ {print "NOT PQ:", $0}'
aws elb describe-load-balancers --query 'LoadBalancerDescriptions[].LoadBalancerName'   # Classic: every one is a migration item
aws elbv2 describe-ssl-policies --query 'SslPolicies[?contains(Name, `PQ`)].Name'      # confirm names in your Region
```
Config rule: `ELBV2_PREDEFINED_SECURITY_POLICY_SSL_CHECK` (console name `elbv2-predefined-security-policy-ssl-check`), resource `AWS::ElasticLoadBalancingV2::Listener`, parameter `sslPolicies` = comma-separated PQ policy names. It covers ALB HTTPS and NLB TLS listeners. Not available in me-central-1, ap-south-2, ap-southeast-4, ca-west-1, eu-south-2, eu-central-2 (Documented, [rule page](https://docs.aws.amazon.com/config/latest/developerguide/elbv2-predefined-security-policy-ssl-check.html)).

Live test (from a container with OpenSSL 3.5, for example `debian:trixie-slim` plus `apt-get install openssl`):
```bash
# PQ client must negotiate the hybrid group
echo | openssl s_client -connect app.example.com:443 -servername app.example.com -tls1_3 -groups X25519MLKEM768 2>&1 | grep 'Negotiated TLS1.3 group'
# expected: Negotiated TLS1.3 group: X25519MLKEM768
# classical client must still connect on the Res policy (fallback)
echo | openssl s_client -connect app.example.com:443 -servername app.example.com -groups X25519 2>&1 | grep -E 'Protocol|group'
# after the 1.3-only move this must fail
echo | openssl s_client -connect app.example.com:443 -servername app.example.com -tls1_2 2>&1 | grep -E 'alert|Protocol'
```
Observed signal, from logs (field names Documented):
| Log | Where | Fields |
|---|---|---|
| ALB connection log (file prefix `conn_log_`) | S3, 5-minute files per node | `tls_protocol` (5), `tls_cipher` (6), `conn_trace_id` (12), `tls_keyexchange` (13), `elb` (14), `ip_address` (15) |
| ALB access log | S3 | `ssl_protocol`, `ssl_cipher`, `conn_trace_id`; no key exchange |
| NLB access log v2.0 (TLS listeners only) | S3 | `tls_cipher` (15), `tls_protocol_version` (16, `tlsv12`/`tlsv13`), `tls_keyexchange` (17), `domain_name` (18) |

Two documentation quirks: the NLB policy page says key exchange is "log field position 13", but the NLB field table puts `tls_keyexchange` 17th. And AWS does not document the spelling of `tls_keyexchange` values, so the queries match `mlkem` case-insensitively. The Athena regexes were Tested against AWS's sample log lines and synthetic 15/22-field PQ lines (python 3.13 container, 7/7 lines parsed); Athena itself was not run.

## Enforce, pitfalls and rollback
SCP (full file below). The condition key `elasticloadbalancing:SecurityPolicy` works on `CreateListener` and `ModifyListener` (ALB/NLB) and on `CreateLoadBalancerPolicy` and `SetLoadBalancerPoliciesOfListener` (Classic). It does not apply to `CreateLoadBalancer`, so a listener created inside `CreateLoadBalancer` is not covered by this key (Documented, [ELB IAM page](https://docs.aws.amazon.com/elasticloadbalancing/latest/userguide/security_iam_service-with-iam.html)). AWS's own example uses `ForAnyValue:StringEquals`; the deny below uses `ForAnyValue:StringNotEquals` plus a `Null` check for listeners created without an explicit policy. The deny behaviour was not tested against AWS (no credentials): try it in a sandbox OU first. Unverified.

Pitfalls:
- IaC that omits the policy gets `ELBSecurityPolicy-2016-08`, even though the console shows a PQ default. Same for the Load Balancer Controller.
- `IngressClassParams.spec.sslPolicy` silently overrides any Ingress `ssl-policy` annotation.
- A PQ ClientHello is larger (about 1.2 KB of key share) and often spans two packets; old middleboxes in front of clients can break it. Fallback is the client's job, so test partner networks before the 1.3-only move.
- The backend policy follows "any listener"; check every listener when you reason about the target leg. A search snippet claims PQ and non-PQ policies are "not compatible" on listeners of one load balancer; this is not on the policy pages we read, so it is not confirmed. Move all listeners of a load balancer together anyway.
- Policy changes are online, but clients with pinned cipher lists can fail after a 1.3-only move.

Rollback: `aws elbv2 modify-listener --listener-arn ARN --ssl-policy ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09` (from 1.3-only) or to your previous policy. The break-glass role in the SCP must be allowed to do this. Revert in IaC in the same change so the next deploy does not undo it.

## Full configuration files
(files follow)
