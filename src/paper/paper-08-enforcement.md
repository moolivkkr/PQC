# Enforcement and guardrails

Guardrails keep new work PQ while the backlog is fixed. All start in warn mode and move to fail on a schedule; each step is reversible by flipping the mode.

| Layer | Controls | Evidence |
| --- | --- | --- |
| Organisation | SCP on ELB and API Gateway security policies; optional RCP for TLS 1.3 on named S3 buckets; Config rules for ELB, API Gateway and CloudFront policies and a Guard rule for Lambda settings | Documented; JSON and rules Tested on samples |
| Pipeline | cfn-guard (14 rules) and a CloudFormation Guard Hook; conftest on Terraform plans; Checkov; Dockerfile and SBOM policies; `check-go-pq.sh`, `check-jdk-pq.sh` | Tested on good and bad samples |
| Kubernetes | Kyverno (audit, then deny) and Gatekeeper for ALB Ingress, NLB Service, ingress-nginx, istiod and pod variables | Tested (CLI) |
| Runtime | CloudTrail metric filter and alarm; EventBridge rules on non-PQ changes; hourly classical share from ELB logs; Zeek notices | Partly Tested; AWS-side Unverified |

**Schedule:** week 0 inventory and warn everywhere; week 2 block new risk (SCP on new OUs, pipeline fails on changed resources); week 6 fail all resources in CI with exceptions for the rest; week 8 org-wide SCP. **Exceptions** carry an owner, a reason (blocked by AWS, third party, legacy client) and a review date. Security Hub ELB.17 passes non-PQ policies, so a green control does not mean PQ.
