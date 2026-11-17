# Detection

Two kinds of signal, used together. **Observed** signals show what a handshake negotiated and prove a fix worked. **Posture** predicts what a workload will negotiate from its runtime, versions and settings, and covers what no log or sensor sees (Lambda and Fargate calls to non-AWS services). A TLS 1.2 connection is never PQ, so the protocol version alone flags it.

| Signal | Sees | Covers | Evidence |
| --- | --- | --- | --- |
| CloudTrail `tlsDetails.keyExchange` | Group per AWS API call | KMS, STS, IAM, Secrets Manager, ACM, Roles Anywhere (others "coming soon") | Documented |
| ALB connection logs, NLB TLS access logs | Group per inbound connection | Every ALB and NLB TLS listener (logs off by default) | Documented |
| **Zeek** on VPC Traffic Mirroring | `ssl.log` `curve`; our script adds `pq` and raises a notice | East-west and egress traffic of EC2 hosts, ECS and EKS nodes, NAT instances, proxies | **Tested**: Zeek 7.2.2 classified every handshake in the e2e stack; 8.0.10 on a pcap |
| Application handshake log | One JSON line per handshake | Any compute, including Lambda and Fargate | **Tested**: a CloudWatch filter found 892 of 892 classical handshakes |
| Proxy and server logs | Envoy, nginx, HAProxy group variables | Self-managed servers and egress proxies | Tested (Envoy, nginx) |
| Posture inventory | Runtime, settings, policies, classified | Everything AWS APIs list | **Tested** on LocalStack: 25 of 25 |

| Compute | AWS API calls | Other outbound | Packet capture |
| --- | --- | --- | --- |
| Lambda | CloudTrail | Posture or application log only | No |
| Fargate | CloudTrail | Posture, application log or an egress proxy | No |
| ECS on EC2, EKS, EC2 | CloudTrail | **Zeek** on mirrored ENIs | Yes (Nitro) |

**Zeek** is the only signal for east-west and egress traffic that no AWS log covers, whatever made the connection. Mirror only TLS ports from NAT instances, egress proxies and busy hosts; don't truncate packets (the hybrid ClientHello spans two segments); write JSON logs to S3 for Athena. It cannot see Fargate or Lambda, nor certificate types in TLS 1.3.

**Blind spots** and their cover: Lambda and Fargate to non-AWS services (posture, app logs, egress proxy); AWS APIs not yet logging `keyExchange` (posture); AWS-managed legs such as CloudFront to origin and API Gateway to integrations (recorded exceptions); IoT Core (device inventory).
