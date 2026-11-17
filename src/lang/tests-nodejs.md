# Test evidence and test cases

Run r1117041043 (2026-11-16), LocalStack Pro end-to-end suite. Each case deploys the runtime and fix on real Lambda, ECS or EC2 resources in LocalStack and connects to a TLS observer; PASS means the observed result matched the expectation in the case file (a baseline that stays classical as documented passes). Not run on real AWS or x86_64.

## Summary

93 client cases and 7 load balancer target cases; 100 passed.

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

## Every client case

Cells: what the client negotiated with each target (hybrid, PQ-only, mutual TLS, TLS 1.2 only) and the certificate it got from the dual ML-DSA/ECDSA server.

### Lambda (48 cases)

| Case | Runtime | Mode | hybrid | pqonly | mtls | tls12 | ML-DSA dual | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `node-lambda-image-n22-baseline` | v22.23.5 | image-baseline | classical | fail | classical | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-image-n22-fixed` | v22.23.5 | image-fixed | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-image-n24-baseline` | v24.22.3 | image-baseline | classical | fail | classical | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-image-n24-fixed` | v24.22.3 | image-fixed | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n18-baseline` | v18.20.8 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `node-lambda-n18-bundled-conf` | v18.20.8 | bundled | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `node-lambda-n18-bundled-flag` | v18.20.8 | bundled | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `node-lambda-n18-combined` | v18.20.8 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `node-lambda-n18-extension` | v18.20.8 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `node-lambda-n18-layer` | v18.20.8 | layer | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `node-lambda-n20-baseline` | v20.20.2 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `node-lambda-n20-bundled-conf` | v20.20.2 | bundled | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `node-lambda-n20-bundled-flag` | v20.20.2 | bundled | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `node-lambda-n20-combined` | v20.20.2 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `node-lambda-n20-extension` | v20.20.2 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `node-lambda-n20-layer` | v20.20.2 | layer | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `node-lambda-n20-pfx-legacy` | v20.20.2 | baseline | classical | fail | fail | classical 1.2 | ECDSA | PASS |
| `node-lambda-n22-baseline` | v22.23.5 | baseline | classical | fail | classical | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n22-bundled-conf` | v22.23.5 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n22-bundled-flag` | v22.23.5 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n22-combined` | v22.23.5 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `node-lambda-n22-devnull` | v22.23.5 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n22-extension` | v22.23.5 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `node-lambda-n22-layer` | v22.23.5 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n22-layer-chain` | v22.23.5 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n22-nec-bundled` | v22.23.5 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n22-nec-layer` | v22.23.5 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n22-pfx-legacy` | v22.23.5 | bundled | **PQ** | **PQ** | fail | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n24-baseline` | v24.22.3 | baseline | classical | fail | classical | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n24-bundled-conf` | v24.22.3 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n24-bundled-flag` | v24.22.3 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n24-code-ecdh` | v24.22.3 | code | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n24-code-ecdh-classical` | v24.22.3 | code | classical | fail | classical | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n24-combined` | v24.22.3 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `node-lambda-n24-combined-wrapper` | v24.22.3 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n24-devnull` | v24.22.3 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n24-extension` | v24.22.3 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `node-lambda-n24-fetch-nec` | v24.22.3 | bundled | **PQ** | **PQ** | — | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n24-layer` | v24.22.3 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n24-layer-disabled` | v24.22.3 | layer | classical | fail | classical | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n24-layer-ownconf` | v24.22.3 | layer | classical | fail | classical | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n24-nec-aws` | v24.22.3 | baseline | classical | fail | classical | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n24-nec-bundled` | v24.22.3 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n24-nec-none` | v24.22.3 | bundled | fail | fail | fail | fail | **ML-DSA** | PASS |
| `node-lambda-n24-pfx` | v24.22.3 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n24-pfx-legacy` | v24.22.3 | bundled | **PQ** | **PQ** | fail | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n24-pfx-legacy-provider` | v24.22.3 | bundled | **PQ** | **PQ** | fail | classical 1.2 | **ML-DSA** | PASS |
| `node-lambda-n24-tls-max-12` | v24.22.3 | code | classical 1.2 | fail | classical 1.2 | classical 1.2 | ECDSA | PASS |

### ECS Fargate (28 cases)

| Case | Runtime | Mode | hybrid | pqonly | mtls | tls12 | ML-DSA dual | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `node-fargate-al2023-n20-baseline` | v20.20.2 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `node-fargate-al2023-n20-conf` | v20.20.2 | config | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-fargate-al2023-n20-policy` | v20.20.2 | crypto-policy | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-fargate-al2023-n22-baseline` | v22.23.4 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `node-fargate-al2023-n22-conf` | v22.23.4 | config | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-fargate-al2023-n22-policy` | v22.23.4 | crypto-policy | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-fargate-al2023-n24-baseline` | v24.22.1 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `node-fargate-al2023-n24-conf` | v24.22.1 | config | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-fargate-al2023-n24-policy` | v24.22.1 | crypto-policy | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-fargate-distro-alpine322` | v22.23.5 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-fargate-distro-debian13` | v20.19.2 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-fargate-lib-20-alpine` | v20.20.2 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `node-fargate-lib-20-slim` | v20.20.2 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `node-fargate-lib-22-alpine` | v22.23.5 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-fargate-lib-22-slim` | v22.23.5 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-fargate-lib-22-slim-fetch` | v22.23.5 | baseline | **PQ** | **PQ** | — | classical 1.2 | **ML-DSA** | PASS |
| `node-fargate-lib-2219-alpine` | v22.19.0 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `node-fargate-lib-2220-alpine` | v22.20.0 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-fargate-lib-24-alpine` | v24.22.3 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-fargate-lib-24-slim` | v24.22.3 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-fargate-lib-24-slim-nec` | v24.22.3 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-fargate-lib-24-slim-pfx` | v24.22.3 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-fargate-lib-24-slim-pfx-legacy` | v24.22.3 | baseline | **PQ** | **PQ** | fail | classical 1.2 | **ML-DSA** | PASS |
| `node-fargate-lib-24-slim-pfx-legacy-provider` | v24.22.3 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-fargate-lib-24-slim-tls-max-12` | v24.22.3 | code | classical 1.2 | fail | classical 1.2 | classical 1.2 | ECDSA | PASS |
| `node-fargate-lib-244-alpine` | v24.4.1 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `node-fargate-lib-245-alpine` | v24.5.0 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-fargate-lib-26-slim` | v26.13.1 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |

### ECS on EC2 (5 cases)

| Case | Runtime | Mode | hybrid | pqonly | mtls | tls12 | ML-DSA dual | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `node-ecsec2-al2023-n22-baseline` | v22.23.4 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `node-ecsec2-al2023-n22-conf` | v22.23.4 | config | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-ecsec2-al2023-n24-policy` | v24.22.1 | crypto-policy | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-ecsec2-lib-20-slim` | v20.20.2 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `node-ecsec2-lib-24-slim` | v24.22.3 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |

### EC2 (12 cases)

| Case | Runtime | Mode | hybrid | pqonly | mtls | tls12 | ML-DSA dual | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `node-ec2-al2023-n20-baseline` | v20.20.2 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `node-ec2-al2023-n20-host-policy` | v20.20.2 | crypto-policy | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-ec2-al2023-n20-service-conf` | v20.20.2 | config | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-ec2-al2023-n22-baseline` | v22.23.4 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `node-ec2-al2023-n22-host-policy` | v22.23.4 | crypto-policy | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-ec2-al2023-n22-service-conf` | v22.23.4 | config | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-ec2-al2023-n24-baseline` | v24.22.1 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `node-ec2-al2023-n24-host-policy` | v24.22.1 | crypto-policy | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-ec2-al2023-n24-service-conf` | v24.22.1 | config | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-ec2-al2023-official22-baseline` | v22.23.5 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-ec2-al2023-official24-baseline` | v24.22.3 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `node-ec2-al2023-official24-host-default-pq` | v24.22.3 | crypto-policy | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |

## Load balancer target cases (7)

The workload is the HTTPS server; the observer connects like an ALB with the PQ backend policy (alb-pq) or the classic one (alb-classic).

| Case | Compute | Runtime | Mode | alb-pq | alb-classic | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| `srv-node-ecsec2-lib-24-slim` | ecs-ec2 | v24.22.3 | baseline | **PQ** | classical 1.2 | PASS |
| `srv-node-fargate-al2023-n20-conf` | ecs-fargate | v20.20.2 | config | **PQ** | classical 1.2 | PASS |
| `srv-node-fargate-al2023-n22-baseline` | ecs-fargate | v22.23.4 | baseline | classical | classical 1.2 | PASS |
| `srv-node-fargate-al2023-n22-conf` | ecs-fargate | v22.23.4 | config | **PQ** | classical 1.2 | PASS |
| `srv-node-fargate-al2023-n22-policy` | ecs-fargate | v22.23.4 | crypto-policy | **PQ** | classical 1.2 | PASS |
| `srv-node-fargate-lib-20-slim` | ecs-fargate | v20.20.2 | baseline | classical | classical 1.2 | PASS |
| `srv-node-fargate-lib-24-slim` | ecs-fargate | v24.22.3 | baseline | **PQ** | classical 1.2 | PASS |
