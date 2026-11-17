# Solutions by compute type

The language and its version decide whether a connection **can** be PQ; the compute type decides **who owns the TLS library, where the fix lives and how we see the result**. Every fix is a file, a variable, a base image or a version, versioned once in the shared `pq-tls` kit and shipped through the build template, so each workload picks it up on its next release and rolls back by removing it.

| Compute | Who owns the TLS library | Where the fix lives | How we see it | e2e cases |
| --- | --- | --- | --- | --- |
| Lambda (zip, image) | AWS (zip); you, from an AWS base image | Files under `/var/task/pq-tls/` plus a variable; or the `pq-tls` layer | CloudTrail; application logs | 250 |
| ECS on Fargate | You (the image) | Base image, Dockerfile, task definition | CloudTrail; app logs; egress proxy | 109 + 27 target |
| ECS on EC2, EKS | You (the image); node OS doesn't matter | Same; pod spec on EKS | Plus Zeek on node ENIs | 24 + 5 target |
| EC2 hosts | You (OS packages) | OS crypto policy via SSM, service unit | CloudTrail; Zeek; SSM Inventory | 54 |

**Fix by language and compute** (detail in each language document):

| Language | Lambda | Containers (Fargate, ECS, EKS) | EC2 |
| --- | --- | --- | --- |
| Go | Go 1.24+ build with `go` line ≥ 1.24, or `GODEBUG=tlsmlkem=1` | Same; base image irrelevant | Same |
| Python 3.12+ | `openssl-pq.cnf` + `OPENSSL_CONF` | Debian 13 or Alpine image; on AL2023 the config or `DEFAULT:PQ` | `DEFAULT:PQ` via SSM |
| Python 3.9 to 3.11 | Upgrade; bridge: shim or layer | Not blocked: any OpenSSL 3.5 image | As above |
| Node.js 22, 24 | `openssl-pq-node.cnf` + `OPENSSL_CONF` (overrides the bootstrap) | Official image 22.20+ / 24.5+: PQ by default | Official binaries |
| Node.js 18, 20 | Upgrade; interim `pq-egress` extension | Upgrade | Upgrade |
| Java 8 to 21 | Kit v2 agent via `JAVA_TOOL_OPTIONS` | JDK 25.0.5+ image, or the agent | Same |
| Java 25 | Nothing | JDK 25.0.5+ | Same |
| .NET 8, 10 | `openssl-pq.cnf` + `OPENSSL_CONF` | Alpine or Ubuntu 26.04 image; on AL2023 the config | `DEFAULT:PQ`; Windows: Schannel group |

**Lambda** ships the fix three ways, in order of preference: bundled in the package by the build template (no layer limit); the `pq-tls` layer with `AWS_LAMBDA_EXEC_WRAPPER` (one layer for all runtimes, `PQ_TLS_DISABLE=1` rolls back); or, interim, the `pq-egress` extension, which makes the TLS connection for runtimes that cannot (the app calls it over loopback). All three Tested in e2e, not on real AWS. Runtimes AWS blocks on 2027-08-31 move first.

**Containers** usually need one Dockerfile line: a base image that is PQ by default (`python:3.13-slim-trixie`, `node:24`, Corretto 25, .NET 10 Alpine). As ALB/NLB targets, the same fix makes the load balancer's backend leg PQ (32 target cases Tested).

**EC2 hosts** take `update-crypto-policies --set DEFAULT:PQ` on AL2023, in waves by tag through SSM State Manager; Amazon Linux 2 must migrate; Debian 13 and Ubuntu 26.04 are PQ for OpenSSL programs but not GnuTLS tools (wget, Debian git).
