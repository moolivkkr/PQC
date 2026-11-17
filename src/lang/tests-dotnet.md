# Test evidence and test cases

Run r1117041043 (2026-11-16), LocalStack Pro end-to-end suite. Each case deploys the runtime and fix on real Lambda, ECS or EC2 resources in LocalStack and connects to a TLS observer; PASS means the observed result matched the expectation in the case file (a baseline that stays classical as documented passes). Not run on real AWS or x86_64.

## Summary

71 client cases and 7 load balancer target cases; 78 passed.

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

## Every client case

Cells: what the client negotiated with each target (hybrid, PQ-only, mutual TLS, TLS 1.2 only) and the certificate it got from the dual ML-DSA/ECDSA server.

### Lambda (33 cases)

| Case | Runtime | Mode | hybrid | pqonly | mtls | tls12 | ML-DSA dual | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `dotnet-lambda-aot-baseline` | 10.0.14 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-aot-bundled-conf` | 10.0.14 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet10-baseline` | 10.0.15 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet10-bundled-conf` | 10.0.15 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet10-callback-trust` | 10.0.15 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet10-combined` | 10.0.15 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `dotnet-lambda-dotnet10-combined-conf` | 10.0.15 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet10-extension` | 10.0.15 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `dotnet-lambda-dotnet10-hch-p12-clientcert` | 10.0.15 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet10-layer-conf` | 10.0.15 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet10-layer-wrapper` | 10.0.15 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet10-no-ca` | 10.0.15 | bundled | fail | fail | fail | fail | ECDSA | PASS |
| `dotnet-lambda-dotnet10-pem-clientcert` | 10.0.15 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet10-ssl-cert-dir` | 10.0.15 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet10-ssl-cert-file` | 10.0.15 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet10-store-clientcert` | 10.0.15 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet10-store-clientcert-nohome` | 10.0.15 | bundled | **PQ** | **PQ** | fail | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet10-tls12-pin` | 10.0.15 | bundled | classical 1.2 | fail | classical 1.2 | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet10-tls12-tls13` | 10.0.15 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet8-baseline` | 8.0.34 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet8-bundled-conf` | 8.0.34 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet8-combined` | 8.0.34 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `dotnet-lambda-dotnet8-combined-conf` | 8.0.34 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet8-extension` | 8.0.34 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `dotnet-lambda-dotnet8-layer-conf` | 8.0.34 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet8-layer-wrapper` | 8.0.34 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet8-ssl-cert-file` | 8.0.34 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet8-store-clientcert` | 8.0.34 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-dotnet8-store-clientcert-nohome` | 8.0.34 | bundled | **PQ** | **PQ** | fail | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-image-dotnet10-baseline` | 10.0.15 | image-baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-image-dotnet10-fixed` | 10.0.15 | image-fixed | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-image-dotnet8-baseline` | 8.0.34 | image-baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `dotnet-lambda-image-dotnet8-fixed` | 8.0.34 | image-fixed | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |

### ECS Fargate (25 cases)

| Case | Runtime | Mode | hybrid | pqonly | mtls | tls12 | ML-DSA dual | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `dotnet-fargate-al2023-fixed-net8` | 8.0.33 | config | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-fargate-al2023-net10-baseline` | 10.0.14 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `dotnet-fargate-al2023-net10-conf` | 10.0.14 | config | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-fargate-al2023-net10-policy` | 10.0.14 | crypto-policy | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `dotnet-fargate-al2023-net8-baseline` | 8.0.33 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `dotnet-fargate-al2023-net8-conf` | 8.0.33 | config | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-fargate-al2023-net8-policy` | 8.0.33 | crypto-policy | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `dotnet-fargate-al2023-sysca-conf` | 10.0.14 | config | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-fargate-alpine-sysca` | 10.0.15 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `dotnet-fargate-alpine8-callback-trust` | 8.0.34 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `dotnet-fargate-aspnet-100-noble-chiseled` | 10.0.15 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `dotnet-fargate-aspnet-100-resolute` | 10.0.15 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `dotnet-fargate-aspnet-100-resolute-chiseled` | 10.0.15 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `dotnet-fargate-debian8-store-clientcert` | 8.0.34 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `dotnet-fargate-resolute-pem-clientcert` | 10.0.15 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `dotnet-fargate-resolute-ssl-cert-file` | 10.0.15 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `dotnet-fargate-resolute-store-clientcert` | 10.0.15 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `dotnet-fargate-resolute-sysca` | 10.0.15 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `dotnet-fargate-resolute-tls12-pin` | 10.0.15 | baseline | classical 1.2 | fail | classical 1.2 | classical 1.2 | **ML-DSA** | PASS |
| `dotnet-fargate-runtime-100` | 10.0.15 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `dotnet-fargate-runtime-100-alpine` | 10.0.15 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `dotnet-fargate-runtime-100-azurelinux30` | 10.0.15 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `dotnet-fargate-runtime-80` | 8.0.34 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `dotnet-fargate-runtime-80-alpine` | 8.0.34 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `dotnet-fargate-runtime-80-noble` | 8.0.34 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |

### ECS on EC2 (6 cases)

| Case | Runtime | Mode | hybrid | pqonly | mtls | tls12 | ML-DSA dual | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `dotnet-ecsec2-al2023-net10-baseline` | 10.0.14 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `dotnet-ecsec2-al2023-net10-policy` | 10.0.14 | crypto-policy | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `dotnet-ecsec2-al2023-net8-conf` | 8.0.33 | config | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-ecsec2-alpine10-baseline` | 10.0.15 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `dotnet-ecsec2-debian8-baseline` | 8.0.34 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `dotnet-ecsec2-resolute-baseline` | 10.0.15 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |

### EC2 (7 cases)

| Case | Runtime | Mode | hybrid | pqonly | mtls | tls12 | ML-DSA dual | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `dotnet-ec2-al2023-net10-baseline` | 10.0.14 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `dotnet-ec2-al2023-net10-host-policy` | 10.0.14 | crypto-policy | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `dotnet-ec2-al2023-net10-policy-store-clientcert` | 10.0.14 | crypto-policy | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `dotnet-ec2-al2023-net10-service-conf` | 10.0.14 | config | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `dotnet-ec2-al2023-net8-baseline` | 8.0.33 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `dotnet-ec2-al2023-net8-host-policy` | 8.0.33 | crypto-policy | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `dotnet-ec2-al2023-net8-service-conf` | 8.0.33 | config | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |

## Load balancer target cases (7)

The workload is the HTTPS server; the observer connects like an ALB with the PQ backend policy (alb-pq) or the classic one (alb-classic).

| Case | Compute | Runtime | Mode | alb-pq | alb-classic | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| `srv-dotnet-ecsec2-runtime-100-alpine` | ecs-ec2 | 10.0.15 | baseline | **PQ** | classical 1.2 | PASS |
| `srv-dotnet-fargate-al2023-net8-baseline` | ecs-fargate | 8.0.33 | baseline | classical | classical 1.2 | PASS |
| `srv-dotnet-fargate-al2023-net8-conf` | ecs-fargate | 8.0.33 | config | **PQ** | classical 1.2 | PASS |
| `srv-dotnet-fargate-al2023-net8-policy` | ecs-fargate | 8.0.33 | crypto-policy | **PQ** | classical 1.2 | PASS |
| `srv-dotnet-fargate-aspnet-100-resolute` | ecs-fargate | 10.0.15 | baseline | **PQ** | classical 1.2 | PASS |
| `srv-dotnet-fargate-runtime-100-alpine` | ecs-fargate | 10.0.15 | baseline | **PQ** | classical 1.2 | PASS |
| `srv-dotnet-fargate-runtime-80` | ecs-fargate | 8.0.34 | baseline | classical | classical 1.2 | PASS |
