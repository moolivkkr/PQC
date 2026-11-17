# Test evidence and test cases

Run r1117041043 (2026-11-16), LocalStack Pro end-to-end suite. Each case deploys the runtime and fix on real Lambda, ECS or EC2 resources in LocalStack and connects to a TLS observer; PASS means the observed result matched the expectation in the case file (a baseline that stays classical as documented passes). Not run on real AWS or x86_64.

## Summary

96 client cases and 7 load balancer target cases; 103 passed.

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

## Every client case

Cells: what the client negotiated with each target (hybrid, PQ-only, mutual TLS, TLS 1.2 only) and the certificate it got from the dual ML-DSA/ECDSA server.

### Lambda (57 cases)

| Case | Runtime | Mode | hybrid | pqonly | mtls | tls12 | ML-DSA dual | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `java-lambda-image-j11-baseline` | 11.0.33 | image-baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-lambda-image-j11-fixed` | 11.0.33 | image-fixed | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-image-j17-baseline` | 17.0.21 | image-baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-lambda-image-j17-fixed` | 17.0.21 | image-fixed | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-image-j21-baseline` | 21.0.13 | image-baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-lambda-image-j21-fixed` | 21.0.13 | image-fixed | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-image-j25-baseline` | 25.0.5 | image-baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-image-j8-baseline` | 1.8.0_512 | image-baseline | classical 1.2 | fail | classical 1.2 | classical 1.2 | ECDSA | PASS |
| `java-lambda-image-j8-fixed` | 1.8.0_512 | image-fixed | fail | fail | fail | fail | fail | PASS |
| `java-lambda-image-j8-layer` | 1.8.0_512 | image-layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-image-j8-layer-hostfix` | 1.8.0_512 | image-layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j11-baseline` | 11.0.33 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-lambda-j11-bundled` | 11.0.33 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j11-combined` | 11.0.33 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j11-extension` | 11.0.33 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `java-lambda-j11-layer` | 11.0.33 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j11-layer-ownsec` | 11.0.33 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j17-baseline` | 17.0.21 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-lambda-j17-bundled` | 17.0.21 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j17-combined` | 17.0.21 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j17-combined-ext` | 17.0.21 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `java-lambda-j17-extension` | 17.0.21 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `java-lambda-j17-ks-ec-pkix` | 17.0.21 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j17-ks-ec-sunx509` | 17.0.21 | bundled | **PQ** | **PQ** | fail | classical 1.2 | ECDSA | PASS |
| `java-lambda-j17-ks-rsa-sunx509` | 17.0.21 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j17-layer` | 17.0.21 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j21-baseline` | 21.0.13 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-lambda-j21-bundled` | 21.0.13 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j21-combined` | 21.0.13 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j21-extension` | 21.0.13 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `java-lambda-j21-ks-ec-baseline` | 21.0.13 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-lambda-j21-ks-ec-bundled` | 21.0.13 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j21-ks-ec-layer` | 21.0.13 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j21-ks-ec-v1` | 21.0.13 | bundled | **PQ** | **PQ** | fail | classical 1.2 | ECDSA | PASS |
| `java-lambda-j21-layer` | 21.0.13 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j21-layer-disabled` | 21.0.13 | layer | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-lambda-j21-layer-ownsec` | 21.0.13 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j21-layer-pin` | 21.0.13 | layer | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-lambda-j21-static` | 21.0.13 | static | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-lambda-j21-sysprops-ec-baseline` | 21.0.13 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-lambda-j21-sysprops-ec-bundled` | 21.0.13 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j21-sysprops-notrust-bundled` | 21.0.13 | bundled | fail | fail | fail | fail | ECDSA | PASS |
| `java-lambda-j25-baseline` | 25.0.5 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j25-combined` | 25.0.5 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j25-extension` | 25.0.5 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `java-lambda-j25-ks-ec-baseline` | 25.0.5 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j25-layer` | 25.0.5 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j25-pin` | 25.0.5 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-lambda-j25-sysprops-ec-baseline` | 25.0.5 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j8-baseline` | 1.8.0_512 | baseline | classical 1.2 | fail | classical 1.2 | classical 1.2 | ECDSA | PASS |
| `java-lambda-j8-bundled` | 1.8.0_512 | bundled | fail | fail | fail | fail | fail | PASS |
| `java-lambda-j8-bundled-hostfix` | 1.8.0_512 | bundled | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j8-bundled-noproto` | 1.8.0_512 | bundled | classical 1.2 | fail | classical 1.2 | classical 1.2 | ECDSA | PASS |
| `java-lambda-j8-combined` | 1.8.0_512 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j8-extension` | 1.8.0_512 | extension | **PQ** | **PQ** | **PQ** | classical 1.2 | — | PASS |
| `java-lambda-j8-layer` | 1.8.0_512 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-lambda-j8-layer-hostfix` | 1.8.0_512 | layer | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |

### ECS Fargate (21 cases)

| Case | Runtime | Mode | hybrid | pqonly | mtls | tls12 | ML-DSA dual | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `java-fargate-al2023-j17-baseline` | 17.0.21 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-fargate-al2023-j21-agent` | 21.0.13 | agent | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-fargate-al2023-j21-baseline` | 21.0.13 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-fargate-al2023-j25-baseline` | 25.0.5 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-fargate-corretto11-agent` | 11.0.33 | agent | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-fargate-corretto11-baseline` | 11.0.33 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-fargate-corretto17-agent` | 17.0.21 | agent | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-fargate-corretto17-baseline` | 17.0.21 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-fargate-corretto17-static` | 17.0.21 | static | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-fargate-corretto21-agent` | 21.0.13 | agent | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-fargate-corretto21-agent-ec` | 21.0.13 | agent | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-fargate-corretto21-agent-image` | 21.0.13 | agent | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-fargate-corretto21-baseline` | 21.0.13 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-fargate-corretto21-static` | 21.0.13 | static | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-fargate-corretto21-static-ec` | 21.0.13 | static | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-fargate-corretto25-baseline` | 25.0.5 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-fargate-corretto8-agent` | 1.8.0_512 | agent | fail | fail | fail | fail | fail | PASS |
| `java-fargate-corretto8-agent-hostfix` | 1.8.0_512 | agent | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-fargate-corretto8-agent-noproto` | 1.8.0_512 | agent | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-fargate-corretto8-baseline` | 1.8.0_512 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-fargate-temurin21-static` | 21.0.13 | static | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |

### ECS on EC2 (5 cases)

| Case | Runtime | Mode | hybrid | pqonly | mtls | tls12 | ML-DSA dual | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `java-ecsec2-corretto17-static` | 17.0.21 | static | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-ecsec2-corretto21-agent` | 21.0.13 | agent | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-ecsec2-corretto21-baseline` | 21.0.13 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-ecsec2-corretto25-baseline` | 25.0.5 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-ecsec2-corretto8-agent` | 1.8.0_512 | agent | fail | fail | fail | fail | fail | PASS |

### EC2 (13 cases)

| Case | Runtime | Mode | hybrid | pqonly | mtls | tls12 | ML-DSA dual | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `java-ec2-al2-j11-agent` | 11.0.33 | agent | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-ec2-al2-j11-baseline` | 11.0.33 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-ec2-al2-j17-agent` | 17.0.21 | agent | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-ec2-al2-j17-baseline` | 17.0.21 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-ec2-al2023-default-java` | 25.0.5 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-ec2-al2023-j11-agent` | 11.0.33 | agent | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-ec2-al2023-j11-baseline` | 11.0.33 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-ec2-al2023-j17-agent` | 17.0.21 | agent | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-ec2-al2023-j17-baseline` | 17.0.21 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-ec2-al2023-j21-agent` | 21.0.13 | agent | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-ec2-al2023-j21-agent-ec` | 21.0.13 | agent | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |
| `java-ec2-al2023-j21-baseline` | 21.0.13 | baseline | classical | fail | classical | classical 1.2 | ECDSA | PASS |
| `java-ec2-al2023-j25-baseline` | 25.0.5 | baseline | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | PASS |

## Load balancer target cases (7)

The workload is the HTTPS server; the observer connects like an ALB with the PQ backend policy (alb-pq) or the classic one (alb-classic).

| Case | Compute | Runtime | Mode | alb-pq | alb-classic | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| `srv-java-ecsec2-corretto21-agent` | ecs-ec2 | 21.0.13 | agent | **PQ** | classical 1.2 | PASS |
| `srv-java-fargate-corretto17-agent` | ecs-fargate | 17.0.21 | agent | **PQ** | classical 1.2 | PASS |
| `srv-java-fargate-corretto21-agent` | ecs-fargate | 21.0.13 | agent | **PQ** | classical 1.2 | PASS |
| `srv-java-fargate-corretto21-baseline` | ecs-fargate | 21.0.13 | baseline | classical | classical 1.2 | PASS |
| `srv-java-fargate-corretto25` | ecs-fargate | 25.0.5 | baseline | **PQ** | classical 1.2 | PASS |
| `srv-java-fargate-corretto8-agent` | ecs-fargate | 1.8.0_512 | agent | **PQ** | classical 1.2 | PASS |
| `srv-java-fargate-corretto8-baseline` | ecs-fargate | 1.8.0_512 | baseline | classical | classical 1.2 | PASS |
