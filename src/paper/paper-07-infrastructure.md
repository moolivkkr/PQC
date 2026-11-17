# Infrastructure and services

Most infrastructure becomes PQ by configuration we control today; some legs wait for AWS. Where the client is our own code (SDKs, database drivers, apps behind a mesh) the fix is the language fix. Full detail per area is in the complete guide.

| Area | PQ today | Main action | Blocked by AWS |
| --- | --- | --- | --- |
| Load balancers | ALB and NLB opt-in | 2025-09 PQ policy; SCP on `elasticloadbalancing:SecurityPolicy`; target leg needs the target's fix (Tested) | Classic LB (migrate) |
| Edge and API front doors | CloudFront viewer on; API Gateway REST opt-in | REST PQ policies; front HTTP and WebSocket APIs with CloudFront or a PQ ALB | CloudFront to origin; API Gateway egress; HTTP and WebSocket APIs |
| AWS service endpoints | KMS, Secrets Manager, STS, IAM, ACM, S3, DynamoDB | Client-side language fixes; CloudTrail to prove | Unlisted services (e.g. SSM) |
| Network devices and egress | Squid, Envoy, strongSwan 6.0.2+, vendor appliances | PQ egress proxy for what can't upgrade; Zeek for detection | Network Firewall TLS inspection; AWS VPN |
| Service mesh | Linkerd 2.19+ on; Istio 1.27+, Envoy opt-in | Upgrade or set mesh config | ECS Service Connect |
| Databases and data services | RDS and Aurora by version; PostgreSQL 18, MySQL 26.7+, Valkey 8.1 | Engine upgrade, group config, PQ-capable drivers | RDS Proxy, ElastiCache, MSK, OpenSearch |
| Hosts and OS | AL2023, RHEL opt-in; Debian 13 and Ubuntu 26.04 on (OpenSSL only); Windows opt-in | `DEFAULT:PQ` via SSM; Schannel group via GPO or SSM | Amazon Linux 2 (migrate) |
| Web servers and proxies | nginx, Apache, HAProxy on OpenSSL 3.5; Envoy 1.40+ | Set groups on both listener and upstream leg | None |
| IoT | Classical into IoT Core; wolfSSL, awscrt, Mosquitto can do PQ | PQ-capable stacks and ML-DSA roots in new firmware | IoT Core |
| WAF | Follows the resource it is attached to | PQ on the resource | Same as the resource |
| Certificates (ML-DSA) | Private CA, KMS, Roles Anywhere issue ML-DSA | Dual-certificate pilot after ML-KEM | ACM, ELB, CloudFront, public web PKI |
| Mobile, desktop, CLI | Browsers and Apple 26 on; Windows opt-in | Upgrade CI toolboxes and clients | None |

**TLS 1.3 at the front door:** allow 1.2 and 1.3 with a PQ policy first, measure, then move each endpoint to 1.3-only once its TLS 1.2 traffic reaches zero. Every "blocked by AWS" leg goes into the exception register and is rechecked against AWS's PQ readiness page each quarter.
