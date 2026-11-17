# Detection

Detection answers two questions for every connection we own: **is it PQ today**, and **did our fix make it PQ**. No single signal answers both for every compute type, so we combine two kinds:

- **Observed:** what a handshake actually negotiated, from an AWS log, a sensor or the application's own log. Observed signals prove a connection is PQ and catch what posture misses, such as a library that pins its own groups.
- **Posture:** what a workload will negotiate, predicted from its runtime, versions and settings. Posture covers everything we can inventory, including Lambda and Fargate calls to non-AWS services, which no AWS log or sensor sees.

One rule holds for every source: a TLS 1.2 connection is never PQ, so the logged protocol version alone is enough to flag it.

## Signals at a glance

| Signal | What it records | Covers | Evidence | Configuration |
| --- | --- | --- | --- | --- |
| CloudTrail `tlsDetails.keyExchange` | Negotiated group per AWS API call | Calls to KMS, STS, IAM, Secrets Manager, ACM, Roles Anywhere, Payment Cryptography (others "coming soon") | Documented; the query and alarm are Unverified (no AWS account) | [cloudtrail-alarm.yaml](REPO/configs/enforcement/rules/runtime/cloudtrail-alarm.yaml), [cloudtrail-non-pq.sql](REPO/configs/enforcement/rules/runtime/cloudtrail-non-pq.sql) |
| ALB connection logs, NLB TLS access logs | `tls_keyexchange` per inbound connection | Every ALB and NLB TLS listener (logs are off by default) | Documented | [elb-logs-athena.sql](REPO/configs/enforcement/rules/runtime/elb-logs-athena.sql) |
| CloudFront `CloudFront-Viewer-TLS-Details` header | Viewer key exchange, passed to the origin | CloudFront viewers | Documented | [Edge and API front doors](#ch-edge-and-api-front-doors) |
| **Zeek** on VPC Traffic Mirroring | `ssl.log` field `curve` per session; our script adds `pq` and raises a notice | East-west and egress traffic of Nitro EC2 ENIs: hosts, ECS and EKS on EC2, NAT instances, proxies | **Tested** (Zeek 7.2.2 in the e2e stack; 8.0.10 on a pcap) | [pq-tls.zeek](REPO/configs/network-devices-and-egress/opt/zeek/share/zeek/site/pq-tls.zeek), [traffic-mirror.tf](REPO/configs/network-devices-and-egress/traffic-mirror.tf) |
| Application handshake log | One JSON line per outbound handshake (`event=tls_handshake`, `group`, `pq_status`) | Any compute type, including Lambda and Fargate, for code we own | **Tested** (CloudWatch filter found 892 of 892 classical handshakes in run r1117041043) | Per language chapter, "How to test" |
| Proxy and server logs | Envoy `%DOWNSTREAM_TLS_GROUP%`, nginx `$ssl_curve`, HAProxy `%[ssl_fc_curve]` | Self-managed web servers, proxies and egress gateways | Tested (Envoy, nginx) | [Web servers and proxies](#ch-web-servers-and-proxies), [Network devices and egress](#ch-network-devices-and-egress) |
| Posture inventory | Runtime, versions, settings, policies per component, classified | Everything the AWS APIs list | **Tested** on LocalStack (25 of 25 components) | [Inventory and dashboards](#ch-13-inventory) |

## Observed and posture signals by compute type

### Observed signals by compute type

| Compute type | Calls to AWS APIs | Calls to other services (internal, SaaS, internet) | Inbound traffic | Packet capture possible? |
| --- | --- | --- | --- | --- |
| Lambda | CloudTrail `tlsDetails.keyExchange` per call, for KMS, STS, IAM, Secrets Manager and ACM only; other services log version and cipher (Documented) | No AWS log shows the group. Options: route VPC-attached egress through a sensor appliance, or log from the client library | Front door logs (row below) | No |
| Fargate (ECS or EKS) | CloudTrail `tlsDetails.keyExchange` | Same gap as Lambda; an egress proxy or sensor appliance in the VPC path | Front door logs | No. VPC Traffic Mirroring does not support Fargate (Documented) |
| Containers on EC2 (ECS, EKS, self-managed) and plain EC2 | CloudTrail `tlsDetails.keyExchange` | Zeek 7.2+ on VPC Traffic Mirroring logs the negotiated group in `ssl.log` field `curve`. Node-level eBPF agents are possible but young | Front door logs plus mirroring | Yes, Nitro instance ENIs |
| Front doors: ALB, NLB, CloudFront, API Gateway | n/a | n/a | ALB connection logs and NLB access logs record the key exchange (Documented). CloudFront passes `CloudFront-Viewer-TLS-Details` to the origin, including the key exchange (Documented) | n/a |
| IoT devices on AWS IoT Core | n/a | n/a | IoT Core has no PQ security policy, so every device connection is classical today (Documented). Inventory devices by firmware and TLS library | n/a |

### Posture signals by compute type

| Compute type | Inventory source | What to read |
| --- | --- | --- |
| Lambda | `lambda list-functions` across accounts, or AWS Config | Runtime identifier, `PackageType` (zip or image), `OPENSSL_CONF`, `JAVA_TOOL_OPTIONS`, `GODEBUG`, attached layers. Classify with the matrix in the next section |
| Fargate and EC2 containers | ECR images, task definitions, pod specs; an SBOM per image (Amazon Inspector SBOM export, Unverified) | OS OpenSSL version, Go toolchain and `go.mod` version (`go version -m <binary>`), JDK version, Node version, Python's linked OpenSSL, env vars in the task definition |
| EC2 hosts | SSM Inventory | OS and OpenSSL version, crypto policy (`update-crypto-policies --show`) |
| Front doors | AWS Config | ELB and API Gateway security policy names; Config rule `elbv2-predefined-security-policy-ssl-check` takes an allowlist of PQ policy names |

One rule holds for every row: a TLS 1.2 connection is always non-PQ, so `tlsDetails.tlsVersion` or the logged protocol is enough to flag it.

CloudTrail records `keyExchange` only for KMS, STS, IAM, Secrets Manager, ACM and Payment Cryptography so far; AWS lists it as coming soon for S3, DynamoDB, SQS, SNS, EventBridge, ECR and Direct Connect. Systems Manager isn't on AWS's PQ readiness list at all. Details are on the AWS service endpoints page.
## Zeek: network detection

Zeek is the only signal that sees east-west and egress traffic that no AWS log covers, whatever language or library made the connection. It reads the ServerHello, so it reports what was **negotiated**, not what was offered.

**What we tested.** In the e2e stack, Zeek 7.2.2 sniffed the observer's interface with our `pq-tls.zeek` loaded and JSON logs on, while an OpenSSL 3.5 client and an OpenSSL 3.0 client connected to the hybrid, TLS 1.2 and dual-certificate listeners. Every session was classified correctly, and Zeek raised one notice per classical server and group (`e2e/zeek/check.sh`, passed 2026-11-16). Zeek 8.0.10 gave the same result on a pcap.

| Port | Client | `version` | `curve` | `pq` |
| --- | --- | --- | --- | --- |
| 8443 (hybrid) | OpenSSL 3.5 | TLSv13 | X25519MLKEM768 | true |
| 8443 (hybrid) | OpenSSL 3.0 | TLSv13 | x25519 | false |
| 8447 (TLS 1.2 only) | both | TLSv12 | x25519 | false |
| 8448 (dual certificate) | OpenSSL 3.5 | TLSv13 | X25519MLKEM768 | true |
| 8448 (dual certificate) | OpenSSL 3.0 | TLSv13 | x25519 | false |

**The main change** is one script that adds a `pq` column and a notice (full file: [pq-tls.zeek](REPO/configs/network-devices-and-egress/opt/zeek/share/zeek/site/pq-tls.zeek)):

```
event ssl_established(c: connection) &priority=3 {
    local grp = c$ssl?$curve ? c$ssl$curve : "none";
    c$ssl$pq = grp in pq_groups;     # the three hybrid ML-KEM groups
    if ( ! c$ssl$pq )
        NOTICE([$note=PQTLS::Classical_Key_Exchange, $conn=c,
                $identifier=cat(c$id$resp_h, c$id$resp_p, grp), $suppress_for=1hr,
                $msg=fmt("non-PQ TLS key exchange: group=%s", grp)]);
}
```

**Deploying it on AWS.**

- **Where it can look.** VPC Traffic Mirroring works only from Nitro EC2 network interfaces. It cannot mirror Fargate tasks, Lambda functions or AWS-managed endpoints. Mirror the ENIs of NAT instances, egress proxies and application hosts (including ECS and EKS nodes) to a sensor ENI, or to an NLB in front of a sensor fleet.
- **What to mirror.** TCP 443 and other TLS ports only, to cut cost. Don't truncate packets: the hybrid ClientHello is about 1.2 KB larger and spans two segments.
- **Encapsulation.** Mirrored packets arrive VXLAN-encapsulated on UDP 4789; Zeek decodes it by default.
- **Logs.** Run with `LogAscii::use_json=T` and ship `ssl.log` and `notice.log` to S3. The Athena table `zeek_ssl` reads that format ([athena-views.sql](REPO/configs/inventory/athena-views.sql)).
- **Offered groups.** To find clients that never offer ML-KEM (as opposed to servers that refuse it), add the JA4 package (`zkg install zeek/foxio/ja4`).

**What Zeek cannot see.** In TLS 1.3 the certificate is encrypted, so Zeek cannot tell an ML-DSA certificate from an ECDSA one; certificate posture comes from the inventory and server logs. Inside a service mesh, Zeek sees the mesh's mTLS, not the application's own TLS.

## Application and server handshake logs

Where no sensor can look (Lambda, Fargate), the application logs its own handshakes. Every e2e probe writes one JSON line per handshake, which a CloudWatch Logs metric filter counts:

```
{"event":"tls_handshake","lang":"python","runtime":"3.12.16","compute":"lambda","target":"api.partner.example",
 "ok":true,"tls_version":"TLSv1.3","group":"X25519","pq":false,"pq_status":"classical"}

{ ($.event = "tls_handshake") && ($.pq_status = "classical") }
```

The filter found exactly the 892 classical handshakes the clients reported in run r1117041043 (e2e check `detect-cloudwatch-nonpq`). The observer's own server-side log held all of them plus every TLS 1.2 negotiation (`detect-server-handshake-log`), which is the pattern for servers we run: log the negotiated group on the server. Not every runtime can read the negotiated group: Go 1.25+ exposes `ConnectionState().CurveID` and Python 3.15 `SSLSocket.group()`, while Java and .NET have no public API for it. So the e2e probes log the group the server reports (the observer echoes it), and for servers we run, the server log is the better source. Each language chapter's "How to test" has the check for that language.

## Alerting

Alerts are configured in [Enforcement and guardrails](#ch-21-enforcement) (runtime detection): a CloudTrail metric filter and alarm for classical AWS API calls, an hourly classical-share metric from ELB logs, EventBridge rules on non-PQ listener changes, and Zeek notices for destinations on a PQ-required list. Dashboards are in the next chapter.

## What detection cannot see

| Gap | Why | What covers it |
| --- | --- | --- |
| Lambda and Fargate calls to non-AWS services | No AWS log records the group; no packet mirroring | Posture, application handshake logs, or an egress proxy that logs the group |
| AWS API calls to services without `keyExchange` in CloudTrail (S3, DynamoDB, SQS and others, "coming soon") | Not logged yet | Posture: the SDK and runtime version |
| Certificate algorithm in TLS 1.3 | Certificate is encrypted on the wire | Inventory of issued certificates (Private CA, ACM) and server configuration |
| AWS-managed legs: CloudFront to origin, API Gateway to integrations, ALB to targets | AWS does not log the group on these legs | Target-side server logs for ALB targets; the rest are recorded exceptions |
| IoT devices on AWS IoT Core | IoT Core has no PQ policy; every leg is classical today | Inventory of device firmware and TLS library |
