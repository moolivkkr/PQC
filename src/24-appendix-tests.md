# Appendix A. What is tested, per language

Every result below comes from the LocalStack Pro end-to-end suite, run r1117041043 (2026-11-16): 471 cases, 471 passed (437 client cases, 32 load balancer target cases and 2 detection checks). Earlier container and Lambda-emulator tests (2026-11-12 to 2026-11-14) are listed per language under "Earlier tests". Nothing here ran on real AWS, on x86_64 or through a real ALB or NLB listener.

**How a case works.** Each case deploys a real Lambda function, ECS task or EC2 instance in LocalStack, with the language runtime and the fix under test. Its probe connects to a TLS observer that records what the client offered and negotiated. The probe sets no TLS options itself, so the result reflects the runtime and the fix. Each case is graded against the expectation written in its case file, which follows this paper. PASS means the observed behaviour matched the expectation, so a baseline case that stays classical as documented passes.

| Observer target | Port | Accepts | Question it answers |
| --- | --- | --- | --- |
| `hybrid` | 8443 | X25519MLKEM768 first, classical groups too | Does the client negotiate PQ when it can? |
| `pqonly` | 8444 | X25519MLKEM768 only | Does the client offer ML-KEM at all? |
| `mtls` | 8445 | Hybrid, client certificate required | Does mutual TLS still work with the fix? |
| `eccert` | 8446 | Hybrid with an ECDSA server certificate | Do EC certificates work (Bouncy Castle `PKIX`)? |
| `tls12` | 8447 | TLS 1.2 only | Does the client still connect to a legacy server? |
| `mldsa-dual`, `mldsa-only`, `mldsa-mtls` | 8448 to 8450 | Dual certificate, ML-DSA only, ML-DSA client certificate | Which certificate does the client get, and can it use ML-DSA? |

Shared test code: observer [e2e/observer/](REPO/e2e/observer/), ML-DSA fixture [e2e/mldsa/server.py](REPO/e2e/mldsa/server.py), certificates [e2e/certs/gen.sh](REPO/e2e/certs/gen.sh) and [e2e/certs/gen-mldsa.sh](REPO/e2e/certs/gen-mldsa.sh), case framework [e2e/cases/lib.py](REPO/e2e/cases/lib.py), ML-DSA expectations [e2e/cases/mldsa_rules.py](REPO/e2e/cases/mldsa_rules.py), runner [e2e/run.sh](REPO/e2e/run.sh), Lambda layers [e2e/build/layers.sh](REPO/e2e/build/layers.sh), the `pq-egress` extension [e2e/lambda/extension/pq-egress/](REPO/e2e/lambda/extension/pq-egress/), ECS and EC2 deployment [e2e/ecs/](REPO/e2e/ecs/) and [e2e/ec2/](REPO/e2e/ec2/). Every case and result: [e2e/results/latest/summary.md](REPO/e2e/results/latest/summary.md). How to run: [e2e/RUNNING.md](REPO/e2e/RUNNING.md).

## Go

Detail: [Go](#ch-03-go). 118 client cases and 5 load balancer target cases; 123 passed.

| Compute | Cases | PQ on `hybrid` | Connected to `pqonly` | Runtimes |
| --- | --- | --- | --- | --- |
| Lambda | 77 | 46 | 46 | image, provided.al2, provided.al2023 |
| ECS Fargate | 22 | 14 | 14 | pqc-go:al2 probe-1.23, pqc-go:al2 probe-1.27, pqc-go:al2023 probe-1.23, pqc-go:al2023 probe-1.24, pqc-go:al2023 probe-1.26-boring, pqc-go:al2023 probe-1.26-go1.23, pqc-go:al2023 probe-1.27, pqc-go:al2023-policy probe-1.23 and 12 more |
| ECS on EC2 | 5 | 4 | 4 | pqc-go:al2023 probe-1.23, pqc-go:al2023 probe-1.27, pqc-go:distroless probe-1.24, pqc-go:golang probe-1.26, pqc-go:scratch probe-1.27 |
| EC2 | 14 | 11 | 11 | pqc-al2 probe-1.23, pqc-al2 probe-1.26, pqc-al2 probe-1.27, pqc-al2 probe-distro, pqc-al2023 probe-1.23, pqc-al2023 probe-1.24, pqc-al2023 probe-1.24-go1.23, pqc-al2023 probe-1.25 and 3 more |

**What the cases vary:** no change: the runtime's default (expected classical where the paper says so) (37); FIPS modes (Go FIPS 140-3, boringcrypto, Java and .NET FIPS settings) (19); `GODEBUG=tlsmlkem=1` or a `//go:debug` directive (11); explicit TLS settings that block PQ (case F) (9); custom CA trust (case D) (9); mutual TLS (case E) (6); `go` line in `go.mod` below and above 1.24 (5); the `pq-tls` layer and `AWS_LAMBDA_EXEC_WRAPPER` (4); libraries with their own TLS stack (case H) (4); `update-crypto-policies --set DEFAULT:PQ` (image or host) (4); the `pq-egress` Lambda extension (3); container image variants (3); certificate or key pinning (case I) (2); distro-packaged toolchain or runtime (2).

**ML-DSA:** 113 got ECDSA from the dual server and failed the ML-DSA-only targets; 2 failed every target for reasons unrelated to ML-DSA.

**Load balancer target leg:** 5 servers (ecs-ec2, ecs-fargate); 3 negotiated PQ with the ALB's PQ backend policy (the rest are baselines); 5 of 5 negotiated classical TLS 1.2 with the classic policy.

| Test component | Path |
| --- | --- |
| Case definitions (one entry per case, with its expectation) | [e2e/cases/go.py](REPO/e2e/cases/go.py) |
| Probe deployed in every case | [e2e/clients/go/probe.go](REPO/e2e/clients/go/probe.go) |
| Build and deploy script | [e2e/build/go.sh](REPO/e2e/build/go.sh) |
| Load balancer target server | [e2e/clients/server/go/main.go](REPO/e2e/clients/server/go/main.go) |
| Earlier tests: existing certificates, keystores, libraries (containers) | [tests/deep/go/](REPO/tests/deep/go/) |
| Earlier tests: Lambda base images under the Runtime Interface Emulator | [tests/lambda/goprobe/](REPO/tests/lambda/goprobe/), [tests/lambda/run-dotnet-go.sh](REPO/tests/lambda/run-dotnet-go.sh) |
| Configuration and test harness files from the chapter | [configs/go/](REPO/configs/go/) |

## Python

Detail: [Python](#ch-04-python). 59 client cases and 6 load balancer target cases; 65 passed.

| Compute | Cases | PQ on `hybrid` | Connected to `pqonly` | Runtimes |
| --- | --- | --- | --- | --- |
| Lambda | 35 | 23 | 23 | image, python3.10, python3.11, python3.12, python3.13, python3.14, python3.9 |
| ECS Fargate | 13 | 8 | 8 | pqc-python:al2023 python3.11, pqc-python:al2023 python3.12, pqc-python:al2023 python3.13, pqc-python:al2023 python3.14, pqc-python:al2023-policy python3.12, pqc-python:lib-3.12-alpine python, pqc-python:lib-3.12-slim-bookworm python, pqc-python:lib-3.12-slim-trixie python and 1 more |
| ECS on EC2 | 3 | 2 | 2 | pqc-python:al2023 python3.12, pqc-python:lib-3.13-slim-trixie python |
| EC2 | 8 | 3 | 3 | pqc-al2 python3, pqc-al2023 python3.11, pqc-al2023 python3.12, pqc-al2023 python3.13, pqc-al2023 python3.14 |

**What the cases vary:** no change: the runtime's default (expected classical where the paper says so) (21); the `pq-tls` layer and `AWS_LAMBDA_EXEC_WRAPPER` (11); kit files bundled in the Lambda package (7); the `pq-egress` Lambda extension (7); OpenSSL config file and `OPENSSL_CONF` (6); `update-crypto-policies --set DEFAULT:PQ` (image or host) (3); Lambda container image, unchanged (2); Lambda container image with the fix in the Dockerfile (2).

**ML-DSA:** 14 used ML-DSA on all three targets; 37 got ECDSA from the dual server and failed the ML-DSA-only targets; 1 failed every target for reasons unrelated to ML-DSA.

**Load balancer target leg:** 6 servers (ecs-ec2, ecs-fargate); 4 negotiated PQ with the ALB's PQ backend policy (the rest are baselines); 6 of 6 negotiated classical TLS 1.2 with the classic policy.

| Test component | Path |
| --- | --- |
| Case definitions (one entry per case, with its expectation) | [e2e/cases/python.py](REPO/e2e/cases/python.py) |
| Probe deployed in every case | [e2e/clients/python/probe.py](REPO/e2e/clients/python/probe.py) |
| Build and deploy script | [e2e/build/python.sh](REPO/e2e/build/python.sh) |
| Load balancer target server | [e2e/clients/server/server.py](REPO/e2e/clients/server/server.py) |
| Earlier tests: existing certificates, keystores, libraries (containers) | [tests/deep/python/](REPO/tests/deep/python/) |
| Earlier tests: Lambda base images under the Runtime Interface Emulator | [tests/lambda/client.py](REPO/tests/lambda/client.py), [tests/lambda/run-matrix.sh](REPO/tests/lambda/run-matrix.sh), [tests/lambda/run-py-legacy.sh](REPO/tests/lambda/run-py-legacy.sh), [tests/lambda/al2023-python-test.sh](REPO/tests/lambda/al2023-python-test.sh) |
| Configuration and test harness files from the chapter | [configs/python/](REPO/configs/python/) |

## Node.js

Detail: [Node.js](#ch-05-nodejs). 93 client cases and 7 load balancer target cases; 100 passed.

| Compute | Cases | PQ on `hybrid` | Connected to `pqonly` | Runtimes |
| --- | --- | --- | --- | --- |
| Lambda | 48 | 29 | 29 | image, nodejs18.x, nodejs20.x, nodejs22.x, nodejs24.x |
| ECS Fargate | 28 | 20 | 20 | pqc-node:al2023 node-20, pqc-node:al2023 node-22, pqc-node:al2023 node-24, pqc-node:al2023-policy node-20, pqc-node:al2023-policy node-22, pqc-node:al2023-policy node-24, pqc-node:distro-alpine322 node, pqc-node:distro-debian13 node and 11 more |
| ECS on EC2 | 5 | 3 | 3 | pqc-node:al2023 node-22, pqc-node:al2023-policy node-24, pqc-node:lib-20-slim node, pqc-node:lib-24-slim node |
| EC2 | 12 | 9 | 9 | pqc-al2023 /opt/pqc/node/official-22/bin/node, pqc-al2023 /opt/pqc/node/official-24/bin/node, pqc-al2023 node-20, pqc-al2023 node-22, pqc-al2023 node-24 |

**What the cases vary:** no change: the runtime's default (expected classical where the paper says so) (35); kit files bundled in the Lambda package (18); the `pq-tls` layer and `AWS_LAMBDA_EXEC_WRAPPER` (9); the `pq-egress` Lambda extension (8); `update-crypto-policies --set DEFAULT:PQ` (image or host) (8); OpenSSL config file and `OPENSSL_CONF` (7); a code-level group setting (4); Lambda container image, unchanged (2); Lambda container image with the fix in the Dockerfile (2).

**ML-DSA:** 62 used ML-DSA on all three targets; 23 got ECDSA from the dual server and failed the ML-DSA-only targets.

**Load balancer target leg:** 7 servers (ecs-ec2, ecs-fargate); 5 negotiated PQ with the ALB's PQ backend policy (the rest are baselines); 7 of 7 negotiated classical TLS 1.2 with the classic policy.

| Test component | Path |
| --- | --- |
| Case definitions (one entry per case, with its expectation) | [e2e/cases/node.py](REPO/e2e/cases/node.py) |
| Probe deployed in every case | [e2e/clients/node/index.js](REPO/e2e/clients/node/index.js) |
| Build and deploy script | [e2e/build/node.sh](REPO/e2e/build/node.sh) |
| Load balancer target server | [e2e/clients/server/server.js](REPO/e2e/clients/server/server.js) |
| Earlier tests: existing certificates, keystores, libraries (containers) | [tests/deep/node/](REPO/tests/deep/node/) |
| Earlier tests: Lambda base images under the Runtime Interface Emulator | [tests/lambda/client.js](REPO/tests/lambda/client.js), [tests/lambda/run-matrix.sh](REPO/tests/lambda/run-matrix.sh) |
| Configuration and test harness files from the chapter | [configs/nodejs/](REPO/configs/nodejs/) |

## Java

Detail: [Java](#ch-06-java). 96 client cases and 7 load balancer target cases; 103 passed.

| Compute | Cases | PQ on `hybrid` | Connected to `pqonly` | Runtimes |
| --- | --- | --- | --- | --- |
| Lambda | 57 | 39 | 39 | image, java11, java17, java21, java25, java8.al2 |
| ECS Fargate | 21 | 14 | 14 | pqc-java:al2023 /usr/lib/jvm/jre-17/bin/java, pqc-java:al2023 /usr/lib/jvm/jre-21/bin/java, pqc-java:al2023 /usr/lib/jvm/jre-25/bin/java, pqc-java:corretto11 java, pqc-java:corretto17 java, pqc-java:corretto17-static java, pqc-java:corretto21 java, pqc-java:corretto21-agent-image java and 4 more |
| ECS on EC2 | 5 | 3 | 3 | pqc-java:corretto17-static java, pqc-java:corretto21 java, pqc-java:corretto25 java, pqc-java:corretto8 java |
| EC2 | 13 | 8 | 8 | pqc-al2 /usr/lib/jvm/jre-11/bin/java, pqc-al2 /usr/lib/jvm/jre-17/bin/java, pqc-al2023 /usr/lib/jvm/jre-11/bin/java, pqc-al2023 /usr/lib/jvm/jre-17/bin/java, pqc-al2023 /usr/lib/jvm/jre-21/bin/java, pqc-al2023 /usr/lib/jvm/jre-25/bin/java, pqc-al2023 java |

**What the cases vary:** no change: the runtime's default (expected classical where the paper says so) (27); kit v1 or v2 Java agent (Bouncy Castle JSSE) (17); the `pq-tls` layer and `AWS_LAMBDA_EXEC_WRAPPER` (16); kit files bundled in the Lambda package (13); the `pq-egress` Lambda extension (6); static `java.security` Bouncy Castle entry (6); Lambda container image, unchanged (5); Lambda container image with the fix in the Dockerfile (4); Lambda container image with the layer contents (2).

**ML-DSA:** 86 got ECDSA from the dual server and failed the ML-DSA-only targets; 4 failed every target for reasons unrelated to ML-DSA.

**Load balancer target leg:** 7 servers (ecs-ec2, ecs-fargate); 5 negotiated PQ with the ALB's PQ backend policy (the rest are baselines); 7 of 7 negotiated classical TLS 1.2 with the classic policy.

| Test component | Path |
| --- | --- |
| Case definitions (one entry per case, with its expectation) | [e2e/cases/java.py](REPO/e2e/cases/java.py) |
| Probe deployed in every case | [e2e/clients/java/Probe.java](REPO/e2e/clients/java/Probe.java) |
| Build and deploy script | [e2e/build/java.sh](REPO/e2e/build/java.sh) |
| Load balancer target server | [e2e/clients/server/java/Server.java](REPO/e2e/clients/server/java/Server.java) |
| Earlier tests: existing certificates, keystores, libraries (containers) | [tests/deep/java/](REPO/tests/deep/java/) |
| Earlier tests: Lambda base images under the Runtime Interface Emulator | [tests/lambda/Client.java](REPO/tests/lambda/Client.java), [tests/lambda/agent/](REPO/tests/lambda/agent/), [tests/lambda/run-java-al2023.sh](REPO/tests/lambda/run-java-al2023.sh), [kit/java-v2/](REPO/kit/java-v2/) |
| Configuration and test harness files from the chapter | [configs/java/](REPO/configs/java/) |

## .NET

Detail: [.NET](#ch-07-dotnet). 71 client cases and 7 load balancer target cases; 78 passed.

| Compute | Cases | PQ on `hybrid` | Connected to `pqonly` | Runtimes |
| --- | --- | --- | --- | --- |
| Lambda | 33 | 26 | 26 | dotnet10, dotnet8, image, provided.al2023 |
| ECS Fargate | 25 | 16 | 16 | pqc-dotnet:al2023 net10, pqc-dotnet:al2023 net8, pqc-dotnet:al2023-fixed net8, pqc-dotnet:al2023-policy net10, pqc-dotnet:al2023-policy net8, pqc-dotnet:al2023-sysca net10, pqc-dotnet:mcr-aspnet-10.0-noble-chiseled net10, pqc-dotnet:mcr-aspnet-10.0-resolute net10 and 9 more |
| ECS on EC2 | 6 | 4 | 4 | pqc-dotnet:al2023 net10, pqc-dotnet:al2023 net8, pqc-dotnet:al2023-policy net10, pqc-dotnet:mcr-aspnet-10.0-resolute net10, pqc-dotnet:mcr-runtime-10.0-alpine net10, pqc-dotnet:mcr-runtime-8.0 net8 |
| EC2 | 7 | 5 | 5 | pqc-al2023 /opt/pqc/dotnet/net10/probe.dll, pqc-al2023 /opt/pqc/dotnet/net8/probe.dll |

**What the cases vary:** no change: the runtime's default (expected classical where the paper says so) (28); kit files bundled in the Lambda package (16); OpenSSL config file and `OPENSSL_CONF` (7); the `pq-tls` layer and `AWS_LAMBDA_EXEC_WRAPPER` (6); `update-crypto-policies --set DEFAULT:PQ` (image or host) (6); the `pq-egress` Lambda extension (4); Lambda container image, unchanged (2); Lambda container image with the fix in the Dockerfile (2).

**ML-DSA:** 15 used ML-DSA on all three targets; 4 used ML-DSA on the server targets but could not load an ML-DSA client key; 48 got ECDSA from the dual server and failed the ML-DSA-only targets.

**Load balancer target leg:** 7 servers (ecs-ec2, ecs-fargate); 5 negotiated PQ with the ALB's PQ backend policy (the rest are baselines); 7 of 7 negotiated classical TLS 1.2 with the classic policy.

| Test component | Path |
| --- | --- |
| Case definitions (one entry per case, with its expectation) | [e2e/cases/dotnet.py](REPO/e2e/cases/dotnet.py) |
| Probe deployed in every case | [e2e/clients/dotnet/Probe.cs](REPO/e2e/clients/dotnet/Probe.cs) |
| Build and deploy script | [e2e/build/dotnet.sh](REPO/e2e/build/dotnet.sh) |
| Load balancer target server | [e2e/clients/server/dotnet/Server.cs](REPO/e2e/clients/server/dotnet/Server.cs) |
| Earlier tests: existing certificates, keystores, libraries (containers) | [tests/deep/dotnet/](REPO/tests/deep/dotnet/) |
| Earlier tests: Lambda base images under the Runtime Interface Emulator | [tests/lambda/dotnet/](REPO/tests/lambda/dotnet/), [tests/lambda/run-dotnet-go.sh](REPO/tests/lambda/run-dotnet-go.sh) |
| Configuration and test harness files from the chapter | [configs/dotnet/](REPO/configs/dotnet/) |

## Infrastructure, detection and enforcement

| Area | What was tested | Evidence | Path |
| --- | --- | --- | --- |
| Load balancers | Workload as an HTTPS target with the ALB PQ and classic backend policies (32 cases); IaC validated with `terraform validate` and cfn-lint | e2e; static checks | [e2e/cases/server.py](REPO/e2e/cases/server.py), [tests/deep/edge/](REPO/tests/deep/edge/) |
| Edge and API front doors | Policy names and IaC; origin and integration legs from documentation | Static checks; Documented | [tests/deep/edge/](REPO/tests/deep/edge/) |
| Web servers and proxies, service mesh | nginx, Apache httpd, HAProxy, Envoy 1.40 listener and upstream legs against PQ-only and classical backends; Istio charts rendered | Docker | [tests/deep/websrv/](REPO/tests/deep/websrv/) |
| Network devices, egress and IoT | Envoy and Squid egress, strongSwan, Mosquitto, wolfSSL, Zeek 8.0.10 on a pcap | Docker | [tests/deep/netiot/](REPO/tests/deep/netiot/) |
| Hosts and OS, AWS service endpoints | AL2023 crypto policies, Debian, Ubuntu, Alpine, Fedora, GnuTLS tools, OpenSSH 10, AWS CLI v2 | Docker | [tests/deep/hosts/](REPO/tests/deep/hosts/) |
| Databases and certificates | PostgreSQL, MySQL, MariaDB, Valkey servers and drivers; ML-DSA dual certificates with nginx | Docker | [tests/deep/data/](REPO/tests/deep/data/) |
| ML-DSA certificates across all languages | Three ML-DSA targets for every client case | e2e | [e2e/mldsa/server.py](REPO/e2e/mldsa/server.py), [e2e/cases/mldsa_rules.py](REPO/e2e/cases/mldsa_rules.py) |
| Detection: CloudWatch Logs | Metric filter finds every classical handshake the clients reported | e2e (`detect-cloudwatch-nonpq`) | [e2e/runner/](REPO/e2e/runner/) |
| Detection: server handshake log | Observer log holds every classical and TLS 1.2 handshake | e2e (`detect-server-handshake-log`) | [e2e/observer/](REPO/e2e/observer/) |
| Detection: Zeek 7.2.2 | `ssl.log` `curve` and `pq` per session; three notices | e2e stack, passed 2026-11-16 | [e2e/zeek/check.sh](REPO/e2e/zeek/check.sh) |
| Posture inventory | 25 components classified correctly | LocalStack, passed 25/25 on 2026-11-16 | [e2e/inventory/test_inventory.py](REPO/e2e/inventory/test_inventory.py), [configs/inventory/pq_inventory.py](REPO/configs/inventory/pq_inventory.py) |
| Enforcement | cfn-guard rules, OPA tests, image checks against good and bad samples | Docker | [tests/deep/guard/](REPO/tests/deep/guard/) |

## Not tested

- Anything on real AWS: CloudTrail `keyExchange`, ALB and NLB listener legs and logs, Athena queries and dashboards, SCPs, Config rules, Guard hooks.
- x86_64: all tests ran on arm64.
- Ruby, PHP and Rust; JDK 25 builds other than Corretto and Temurin; the `pq-egress` extension for AWS SDK calls.
