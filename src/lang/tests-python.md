# Test evidence and test cases

Run r1117041043 (2026-11-16), LocalStack Pro end-to-end suite. Each case deploys the runtime and fix on real Lambda, ECS or EC2 resources in LocalStack and connects to a TLS observer; PASS means the observed result matched the expectation in the case file (a baseline that stays classical as documented passes). Not run on real AWS or x86_64.

## Summary

59 client cases and 6 load balancer target cases; 65 passed.

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

## Every client case

Cells: what the client negotiated with each target (hybrid, PQ-only, mutual TLS, TLS 1.2 only) and the certificate it got from the dual ML-DSA/ECDSA server.

### Lambda (35 cases)

| Case | Runtime | Mode | hybrid | pqonly | mtls | tls12 | ML-DSA dual | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `py-lambda-image-py312-baseline` | 3.12.16 | image-baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `py-lambda-image-py312-fixed` | 3.12.16 | image-fixed | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `py-lambda-image-py313-baseline` | 3.13.18 | image-baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `py-lambda-image-py313-fixed` | 3.13.18 | image-fixed | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `py-lambda-py310-baseline` | 3.10.22 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `py-lambda-py310-bundled-shim` | 3.10.22 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `py-lambda-py310-extension` | 3.10.22 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `py-lambda-py310-layer` | 3.10.22 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `py-lambda-py311-baseline` | 3.11.18 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `py-lambda-py311-bundled-shim` | 3.11.18 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `py-lambda-py311-combined-ext-stdlib` | 3.11.18 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `py-lambda-py311-extension` | 3.11.18 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `py-lambda-py311-layer` | 3.11.18 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `py-lambda-py311-layer-stdlib` | 3.11.18 | layer | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `py-lambda-py311-shim-noidna` | 3.11.18 | bundled | fail | fail | fail | fail | fail | PASS |
| `py-lambda-py312-baseline` | 3.12.16 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `py-lambda-py312-bundled-conf` | 3.12.16 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `py-lambda-py312-extension` | 3.12.16 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `py-lambda-py312-layer` | 3.12.16 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `py-lambda-py312-layer-chain` | 3.12.16 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `py-lambda-py312-layer-disabled` | 3.12.16 | layer | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `py-lambda-py312-layer-ownconf` | 3.12.16 | layer | classical | fail | classical | classical 1.2 | **ML-DSA** | PASS |
| `py-lambda-py313-baseline` | 3.13.18 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `py-lambda-py313-bundled-conf` | 3.13.18 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `py-lambda-py313-combined-wrapper` | 3.13.18 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `py-lambda-py313-extension` | 3.13.18 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `py-lambda-py313-layer` | 3.13.18 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `py-lambda-py314-baseline` | 3.14.10 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `py-lambda-py314-bundled-conf` | 3.14.10 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `py-lambda-py314-extension` | 3.14.10 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `py-lambda-py314-layer` | 3.14.10 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `py-lambda-py39-baseline` | 3.9.23 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `py-lambda-py39-bundled-shim` | 3.9.23 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `py-lambda-py39-extension` | 3.9.23 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `py-lambda-py39-layer` | 3.9.23 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |

### ECS Fargate (13 cases)

| Case | Runtime | Mode | hybrid | pqonly | mtls | tls12 | ML-DSA dual | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `py-fargate-al2023-py311-baseline` | 3.11.18 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `py-fargate-al2023-py311-conf` | 3.11.18 | config | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `py-fargate-al2023-py312-baseline` | 3.12.16 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `py-fargate-al2023-py312-conf` | 3.12.16 | config | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `py-fargate-al2023-py312-policy` | 3.12.16 | crypto-policy | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `py-fargate-al2023-py313-baseline` | 3.13.18 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `py-fargate-al2023-py313-conf` | 3.13.18 | config | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `py-fargate-al2023-py314-baseline` | 3.14.10 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `py-fargate-al2023-py314-conf` | 3.14.10 | config | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `py-fargate-lib-312-alpine` | 3.12.16 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `py-fargate-lib-312-slim-bookworm` | 3.12.16 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `py-fargate-lib-312-slim-trixie` | 3.12.16 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `py-fargate-lib-313-slim-trixie` | 3.13.18 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |

### ECS on EC2 (3 cases)

| Case | Runtime | Mode | hybrid | pqonly | mtls | tls12 | ML-DSA dual | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `py-ecsec2-al2023-py312-baseline` | 3.12.16 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `py-ecsec2-al2023-py312-conf` | 3.12.16 | config | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `py-ecsec2-lib-313-slim-trixie` | 3.13.18 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |

### EC2 (8 cases)

| Case | Runtime | Mode | hybrid | pqonly | mtls | tls12 | ML-DSA dual | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `py-ec2-al2-py3-baseline` | 3.7.16 | baseline | classical 1.2 | fail | classical 1.2 | classical 1.2 | ECDSA | PASS |
| `py-ec2-al2023-py311-baseline` | 3.11.18 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `py-ec2-al2023-py311-host-policy` | 3.11.18 | crypto-policy | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `py-ec2-al2023-py312-baseline` | 3.12.16 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `py-ec2-al2023-py312-service-conf` | 3.12.16 | config | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `py-ec2-al2023-py313-baseline` | 3.13.18 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `py-ec2-al2023-py313-host-policy` | 3.13.18 | crypto-policy | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | PASS |
| `py-ec2-al2023-py314-baseline` | 3.14.10 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |

## Load balancer target cases (6)

The workload is the HTTPS server; the observer connects like an ALB with the PQ backend policy (alb-pq) or the classic one (alb-classic).

| Case | Compute | Runtime | Mode | alb-pq | alb-classic | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| `srv-python-ecsec2-al2023-py312-conf` | ecs-ec2 | 3.12.16 | config | **PQ** | classical 1.2 | PASS |
| `srv-python-fargate-al2023-py312-baseline` | ecs-fargate | 3.12.16 | baseline | classical | classical 1.2 | PASS |
| `srv-python-fargate-al2023-py312-conf` | ecs-fargate | 3.12.16 | config | **PQ** | classical 1.2 | PASS |
| `srv-python-fargate-al2023-py312-policy` | ecs-fargate | 3.12.16 | crypto-policy | **PQ** | classical 1.2 | PASS |
| `srv-python-fargate-bookworm-py312` | ecs-fargate | 3.12.16 | baseline | classical | classical 1.2 | PASS |
| `srv-python-fargate-trixie-py313` | ecs-fargate | 3.13.18 | baseline | **PQ** | classical 1.2 | PASS |
