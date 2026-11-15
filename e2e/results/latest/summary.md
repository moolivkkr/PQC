# PQC end-to-end results - run r1115005115

LocalStack: pro 2026.10.6:5fe8a776. 61 of 61 cases passed.

PASS = the observed behaviour matched the expectation in the case file (which is the documented behaviour); it does not mean PQ was negotiated. Cells: what the client negotiated against each observer listener (hybrid :8443, pqonly :8444, mtls :8445, eccert :8446, tls12 :8447).

## all

| Case | Compute | Runtime | Mode | hybrid | pqonly | mtls | eccert | tls12 | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| detect-cloudwatch-nonpq | cloudwatch-logs | | detection | pattern { ($.event = "tls_handshake") && ($.pq_status = "classical") }: expected 101, found 101 | | | | | PASS |
| detect-server-handshake-log | observer | | detection | 268 handshakes, 124 classical, 61 TLS1.2; all client-reported classical handshakes present | | | | | PASS |

## python

| Case | Compute | Runtime | Mode | hybrid | pqonly | mtls | eccert | tls12 | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| py-ec2-al2-py3-baseline | ec2 | 3.7.16 | baseline | classical 1.2 | fail | classical 1.2 | classical 1.2 | classical 1.2 | PASS |
| py-ec2-al2023-py311-baseline | ec2 | 3.11.18 | baseline | classical | fail | classical | classical | classical 1.2 | PASS |
| py-ec2-al2023-py311-host-policy | ec2 | 3.11.18 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-ec2-al2023-py312-baseline | ec2 | 3.12.16 | baseline | classical | fail | classical | classical | classical 1.2 | PASS |
| py-ec2-al2023-py312-service-conf | ec2 | 3.12.16 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-ec2-al2023-py313-baseline | ec2 | 3.13.18 | baseline | classical | fail | classical | classical | classical 1.2 | PASS |
| py-ec2-al2023-py313-host-policy | ec2 | 3.13.18 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-ec2-al2023-py314-baseline | ec2 | 3.14.10 | baseline | classical | fail | classical | classical | classical 1.2 | PASS |
| py-ecsec2-al2023-py312-baseline | ecs-ec2 | 3.12.16 | baseline | classical | fail | classical | classical | classical 1.2 | PASS |
| py-ecsec2-al2023-py312-conf | ecs-ec2 | 3.12.16 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-ecsec2-lib-313-slim-trixie | ecs-ec2 | 3.13.18 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-fargate-al2023-py311-baseline | ecs-fargate | 3.11.18 | baseline | classical | fail | classical | classical | classical 1.2 | PASS |
| py-fargate-al2023-py311-conf | ecs-fargate | 3.11.18 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-fargate-al2023-py312-baseline | ecs-fargate | 3.12.16 | baseline | classical | fail | classical | classical | classical 1.2 | PASS |
| py-fargate-al2023-py312-conf | ecs-fargate | 3.12.16 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-fargate-al2023-py312-policy | ecs-fargate | 3.12.16 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-fargate-al2023-py313-baseline | ecs-fargate | 3.13.18 | baseline | classical | fail | classical | classical | classical 1.2 | PASS |
| py-fargate-al2023-py313-conf | ecs-fargate | 3.13.18 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-fargate-al2023-py314-baseline | ecs-fargate | 3.14.10 | baseline | classical | fail | classical | classical | classical 1.2 | PASS |
| py-fargate-al2023-py314-conf | ecs-fargate | 3.14.10 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-fargate-lib-312-alpine | ecs-fargate | 3.12.16 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-fargate-lib-312-slim-bookworm | ecs-fargate | 3.12.16 | baseline | classical | fail | classical | classical | classical 1.2 | PASS |
| py-fargate-lib-312-slim-trixie | ecs-fargate | 3.12.16 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-fargate-lib-313-slim-trixie | ecs-fargate | 3.13.18 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-image-py312-baseline | lambda | 3.12.16 | image-baseline | classical | fail | classical | classical | classical 1.2 | PASS |
| py-lambda-image-py312-fixed | lambda | 3.12.16 | image-fixed | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-image-py313-baseline | lambda | 3.13.18 | image-baseline | classical | fail | classical | classical | classical 1.2 | PASS |
| py-lambda-image-py313-fixed | lambda | 3.13.18 | image-fixed | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-py310-baseline | lambda | 3.10.22 | baseline | classical | fail | classical | classical | classical 1.2 | PASS |
| py-lambda-py310-bundled-shim | lambda | 3.10.22 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-py310-extension | lambda | 3.10.22 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-py310-layer | lambda | 3.10.22 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-py311-baseline | lambda | 3.11.18 | baseline | classical | fail | classical | classical | classical 1.2 | PASS |
| py-lambda-py311-bundled-shim | lambda | 3.11.18 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-py311-combined-ext-stdlib | lambda | 3.11.18 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-py311-extension | lambda | 3.11.18 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-py311-layer | lambda | 3.11.18 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-py311-layer-stdlib | lambda | 3.11.18 | layer | classical | fail | classical | classical | classical 1.2 | PASS |
| py-lambda-py311-shim-noidna | lambda | 3.11.18 | bundled | fail | fail | fail | fail | fail | PASS |
| py-lambda-py312-baseline | lambda | 3.12.16 | baseline | classical | fail | classical | classical | classical 1.2 | PASS |
| py-lambda-py312-bundled-conf | lambda | 3.12.16 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-py312-extension | lambda | 3.12.16 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-py312-layer | lambda | 3.12.16 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-py312-layer-chain | lambda | 3.12.16 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-py312-layer-disabled | lambda | 3.12.16 | layer | classical | fail | classical | classical | classical 1.2 | PASS |
| py-lambda-py312-layer-ownconf | lambda | 3.12.16 | layer | classical | fail | classical | classical | classical 1.2 | PASS |
| py-lambda-py313-baseline | lambda | 3.13.18 | baseline | classical | fail | classical | classical | classical 1.2 | PASS |
| py-lambda-py313-bundled-conf | lambda | 3.13.18 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-py313-combined-wrapper | lambda | 3.13.18 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-py313-extension | lambda | 3.13.18 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-py313-layer | lambda | 3.13.18 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-py314-baseline | lambda | 3.14.10 | baseline | classical | fail | classical | classical | classical 1.2 | PASS |
| py-lambda-py314-bundled-conf | lambda | 3.14.10 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-py314-extension | lambda | 3.14.10 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-py314-layer | lambda | 3.14.10 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-py39-baseline | lambda | 3.9.23 | baseline | classical | fail | classical | classical | classical 1.2 | PASS |
| py-lambda-py39-bundled-shim | lambda | 3.9.23 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-py39-extension | lambda | 3.9.23 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
| py-lambda-py39-layer | lambda | 3.9.23 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | PASS |
