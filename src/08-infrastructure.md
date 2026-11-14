# Infrastructure and services

Most infrastructure can be made PQ by configuration you control today; a few legs are blocked until AWS ships support. Each sub-page has status, detection, steps and enforcement for one area.

| Area | PQ today | Main action | Blocked by AWS |
| --- | --- | --- | --- |
| Load balancers | ALB and NLB opt-in; Classic none | Set the 2025-09 PQ policy; SCP on `elasticloadbalancing:SecurityPolicy` (CreateListener, ModifyListener) | Classic LB (migrate) |
| Edge and API front doors | CloudFront viewer on; API Gateway REST opt-in (TLS 1.2+1.3 only); Transfer Family SFTP on 2025-03 policies | Set REST PQ policies; front HTTP and WebSocket APIs with CloudFront or a PQ ALB | CloudFront origin leg, API Gateway egress, HTTP and WebSocket APIs |
| AWS service endpoints | KMS, Secrets Manager, STS, IAM, ACM, S3, DynamoDB on; others control plane or unlisted | Client-side fixes only (language runbooks); CloudTrail `keyExchange` for detection | SSM and other unlisted services |
| Network devices and egress | AWS network services undocumented; Squid, Envoy, strongSwan 6.0.2+ and vendor appliances ready | Use a PQ egress proxy for what can't upgrade; Zeek for detection | Network Firewall TLS inspection, AWS VPN |
| IoT | Classical into IoT Core; wolfSSL, awscrt and Mosquitto on OpenSSL 3.5 can do PQ | Inventory TLS stacks; PQ-capable stacks for new devices; PQ gateways and brokers | IoT Core (no PQ policy) |
| Service mesh | Linkerd 2.19+ on; Istio 1.27+, Consul 2.1+, Envoy opt-in | Upgrade or set mesh config (Istio `COMPLIANCE_POLICY=pqc` is PQ-only) | ECS Service Connect (no setting) |
| Databases and data services | RDS and Aurora opt-in by version; PG18, MySQL 26.7+, Valkey 8.1 self-managed | Engine upgrade, `ssl_groups` or group config, PQ-capable drivers | RDS Proxy, ElastiCache, MSK, OpenSearch |
| Hosts and OS | AL2023 and RHEL opt-in; Debian 13 and Ubuntu 26.04 on for OpenSSL programs only (not GnuTLS); Windows opt-in | `DEFAULT:PQ` via SSM; Schannel group via GPO or SSM | Amazon Linux 2 (migrate) |
| Certificates (ML-DSA) | Private CA, KMS, Roles Anywhere can issue ML-DSA | CLM pilot on internal mutual TLS after ML-KEM | ACM, ELB, CloudFront, public web PKI |
| WAF | AWS WAF never terminates TLS: the attached resource decides | Set PQ on the resource; reverse-proxy WAFs need their own PQ profile | Same as the resource it protects |
| Web servers and proxies | OpenSSL 3.5, Go 1.24+ and JDK 25 servers PQ with one or two lines; Envoy and AL2023 builds classical until set | Set the group list on both the listener and the upstream leg | None (self-managed) |
| Mobile, desktop and CLI clients | Chrome, Edge, Firefox, Safari and Apple 26 OS stacks PQ; Windows Schannel opt-in; Android platform TLS not confirmed; macOS LibreSSL curl and GnuTLS tools not | Upgrade CI toolboxes and clients; PQ only shows once the server offers it | None (client-side) |

Record every "blocked by AWS" leg in the exception register and recheck it against AWS's PQ readiness page each quarter.
