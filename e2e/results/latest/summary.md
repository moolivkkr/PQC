# PQC end-to-end results - run r1117041043

LocalStack: pro 2026.10.6:5fe8a776. 471 of 471 cases passed.

PASS = the observed behaviour matched the expectation in the case file (which is the documented behaviour); it does not mean PQ was negotiated. Cells: what the client negotiated against each observer listener (hybrid :8443, pqonly :8444, mtls :8445, eccert :8446, tls12 :8447; ML-DSA certificates: mldsa-dual :8448, mldsa-only :8449, mldsa-mtls :8450). ML-DSA cells: the server certificate the client received (mldsa-dual, mldsa-only) or the client certificate it presented (mldsa-mtls).

## Load balancer target leg (server role)

The workload is the TLS server; the observer connects to it like an ALB/NLB TLS listener connects to an HTTPS target. alb-pq = backend policy used with a PQ listener policy (ELBSecurityPolicy-TLS13-1-0-PQ-2025-09), alb-classic = backend policy used with any other listener policy (ELBSecurityPolicy-2016-08). A model of AWS's client, not AWS's TLS stack.

| Case | Lang | Compute | Runtime | Mode | alb-pq | alb-classic | Verdict |
|---|---|---|---|---|---|---|---|
| srv-dotnet-ecsec2-runtime-100-alpine | dotnet | ecs-ec2 | 10.0.15 | baseline | **PQ** | classical 1.2 | PASS |
| srv-dotnet-fargate-al2023-net8-baseline | dotnet | ecs-fargate | 8.0.33 | baseline | classical | classical 1.2 | PASS |
| srv-dotnet-fargate-al2023-net8-conf | dotnet | ecs-fargate | 8.0.33 | config | **PQ** | classical 1.2 | PASS |
| srv-dotnet-fargate-al2023-net8-policy | dotnet | ecs-fargate | 8.0.33 | crypto-policy | **PQ** | classical 1.2 | PASS |
| srv-dotnet-fargate-aspnet-100-resolute | dotnet | ecs-fargate | 10.0.15 | baseline | **PQ** | classical 1.2 | PASS |
| srv-dotnet-fargate-runtime-100-alpine | dotnet | ecs-fargate | 10.0.15 | baseline | **PQ** | classical 1.2 | PASS |
| srv-dotnet-fargate-runtime-80 | dotnet | ecs-fargate | 8.0.34 | baseline | classical | classical 1.2 | PASS |
| srv-go-ecsec2-go126 | go | ecs-ec2 | go1.26.11 | baseline | **PQ** | classical 1.2 | PASS |
| srv-go-fargate-go123 | go | ecs-fargate | go1.23.12 | baseline | classical | classical 1.2 | PASS |
| srv-go-fargate-go126 | go | ecs-fargate | go1.26.11 | baseline | **PQ** | classical 1.2 | PASS |
| srv-go-fargate-go126-mod123 | go | ecs-fargate | go1.26.11 | baseline | classical | classical 1.2 | PASS |
| srv-go-fargate-go126-mod123-godebug | go | ecs-fargate | go1.26.11 | godebug | **PQ** | classical 1.2 | PASS |
| srv-java-ecsec2-corretto21-agent | java | ecs-ec2 | 21.0.13 | agent | **PQ** | classical 1.2 | PASS |
| srv-java-fargate-corretto17-agent | java | ecs-fargate | 17.0.21 | agent | **PQ** | classical 1.2 | PASS |
| srv-java-fargate-corretto21-agent | java | ecs-fargate | 21.0.13 | agent | **PQ** | classical 1.2 | PASS |
| srv-java-fargate-corretto21-baseline | java | ecs-fargate | 21.0.13 | baseline | classical | classical 1.2 | PASS |
| srv-java-fargate-corretto25 | java | ecs-fargate | 25.0.5 | baseline | **PQ** | classical 1.2 | PASS |
| srv-java-fargate-corretto8-agent | java | ecs-fargate | 1.8.0_512 | agent | **PQ** | classical 1.2 | PASS |
| srv-java-fargate-corretto8-baseline | java | ecs-fargate | 1.8.0_512 | baseline | classical | classical 1.2 | PASS |
| srv-node-ecsec2-lib-24-slim | node | ecs-ec2 | v24.22.3 | baseline | **PQ** | classical 1.2 | PASS |
| srv-node-fargate-al2023-n20-conf | node | ecs-fargate | v20.20.2 | config | **PQ** | classical 1.2 | PASS |
| srv-node-fargate-al2023-n22-baseline | node | ecs-fargate | v22.23.4 | baseline | classical | classical 1.2 | PASS |
| srv-node-fargate-al2023-n22-conf | node | ecs-fargate | v22.23.4 | config | **PQ** | classical 1.2 | PASS |
| srv-node-fargate-al2023-n22-policy | node | ecs-fargate | v22.23.4 | crypto-policy | **PQ** | classical 1.2 | PASS |
| srv-node-fargate-lib-20-slim | node | ecs-fargate | v20.20.2 | baseline | classical | classical 1.2 | PASS |
| srv-node-fargate-lib-24-slim | node | ecs-fargate | v24.22.3 | baseline | **PQ** | classical 1.2 | PASS |
| srv-python-ecsec2-al2023-py312-conf | python | ecs-ec2 | 3.12.16 | config | **PQ** | classical 1.2 | PASS |
| srv-python-fargate-al2023-py312-baseline | python | ecs-fargate | 3.12.16 | baseline | classical | classical 1.2 | PASS |
| srv-python-fargate-al2023-py312-conf | python | ecs-fargate | 3.12.16 | config | **PQ** | classical 1.2 | PASS |
| srv-python-fargate-al2023-py312-policy | python | ecs-fargate | 3.12.16 | crypto-policy | **PQ** | classical 1.2 | PASS |
| srv-python-fargate-bookworm-py312 | python | ecs-fargate | 3.12.16 | baseline | classical | classical 1.2 | PASS |
| srv-python-fargate-trixie-py313 | python | ecs-fargate | 3.13.18 | baseline | **PQ** | classical 1.2 | PASS |

## all

| Case | Compute | Runtime | Mode | hybrid | pqonly | mtls | eccert | tls12 | mldsa-dual | mldsa-only | mldsa-mtls | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| detect-cloudwatch-nonpq | cloudwatch-logs | | detection | pattern { ($.event = "tls_handshake") && ($.pq_status = "classical") }: expected 892, found 892 | | | | | | | | PASS |
| detect-server-handshake-log | observer | | detection | 1961 handshakes, 825 classical, 448 TLS1.2; all client-reported classical handshakes present | | | | | | | | PASS |

## dotnet

| Case | Compute | Runtime | Mode | hybrid | pqonly | mtls | eccert | tls12 | mldsa-dual | mldsa-only | mldsa-mtls | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| dotnet-ec2-al2023-net10-baseline | ec2 | 10.0.14 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-ec2-al2023-net10-host-policy | ec2 | 10.0.14 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| dotnet-ec2-al2023-net10-policy-store-clientcert | ec2 | 10.0.14 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| dotnet-ec2-al2023-net10-service-conf | ec2 | 10.0.14 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-ec2-al2023-net8-baseline | ec2 | 8.0.33 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-ec2-al2023-net8-host-policy | ec2 | 8.0.33 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | fail | PASS |
| dotnet-ec2-al2023-net8-service-conf | ec2 | 8.0.33 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-ecsec2-al2023-net10-baseline | ecs-ec2 | 10.0.14 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-ecsec2-al2023-net10-policy | ecs-ec2 | 10.0.14 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| dotnet-ecsec2-al2023-net8-conf | ecs-ec2 | 8.0.33 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-ecsec2-alpine10-baseline | ecs-ec2 | 10.0.15 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| dotnet-ecsec2-debian8-baseline | ecs-ec2 | 8.0.34 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-ecsec2-resolute-baseline | ecs-ec2 | 10.0.15 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| dotnet-fargate-al2023-fixed-net8 | ecs-fargate | 8.0.33 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-fargate-al2023-net10-baseline | ecs-fargate | 10.0.14 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-fargate-al2023-net10-conf | ecs-fargate | 10.0.14 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-fargate-al2023-net10-policy | ecs-fargate | 10.0.14 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| dotnet-fargate-al2023-net8-baseline | ecs-fargate | 8.0.33 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-fargate-al2023-net8-conf | ecs-fargate | 8.0.33 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-fargate-al2023-net8-policy | ecs-fargate | 8.0.33 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | fail | PASS |
| dotnet-fargate-al2023-sysca-conf | ecs-fargate | 10.0.14 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-fargate-alpine-sysca | ecs-fargate | 10.0.15 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| dotnet-fargate-alpine8-callback-trust | ecs-fargate | 8.0.34 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | fail | PASS |
| dotnet-fargate-aspnet-100-noble-chiseled | ecs-fargate | 10.0.15 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-fargate-aspnet-100-resolute | ecs-fargate | 10.0.15 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| dotnet-fargate-aspnet-100-resolute-chiseled | ecs-fargate | 10.0.15 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| dotnet-fargate-debian8-store-clientcert | ecs-fargate | 8.0.34 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-fargate-resolute-pem-clientcert | ecs-fargate | 10.0.15 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| dotnet-fargate-resolute-ssl-cert-file | ecs-fargate | 10.0.15 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| dotnet-fargate-resolute-store-clientcert | ecs-fargate | 10.0.15 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| dotnet-fargate-resolute-sysca | ecs-fargate | 10.0.15 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| dotnet-fargate-resolute-tls12-pin | ecs-fargate | 10.0.15 | baseline | classical 1.2 | fail | classical 1.2 | classical 1.2 | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| dotnet-fargate-runtime-100 | ecs-fargate | 10.0.15 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-fargate-runtime-100-alpine | ecs-fargate | 10.0.15 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| dotnet-fargate-runtime-100-azurelinux30 | ecs-fargate | 10.0.15 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-fargate-runtime-80 | ecs-fargate | 8.0.34 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-fargate-runtime-80-alpine | ecs-fargate | 8.0.34 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | fail | PASS |
| dotnet-fargate-runtime-80-noble | ecs-fargate | 8.0.34 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-aot-baseline | lambda | 10.0.14 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-aot-bundled-conf | lambda | 10.0.14 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet10-baseline | lambda | 10.0.15 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet10-bundled-conf | lambda | 10.0.15 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet10-callback-trust | lambda | 10.0.15 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet10-combined | lambda | 10.0.15 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| dotnet-lambda-dotnet10-combined-conf | lambda | 10.0.15 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet10-extension | lambda | 10.0.15 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| dotnet-lambda-dotnet10-hch-p12-clientcert | lambda | 10.0.15 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet10-layer-conf | lambda | 10.0.15 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet10-layer-wrapper | lambda | 10.0.15 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet10-no-ca | lambda | 10.0.15 | bundled | fail | fail | fail | fail | fail | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet10-pem-clientcert | lambda | 10.0.15 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet10-ssl-cert-dir | lambda | 10.0.15 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet10-ssl-cert-file | lambda | 10.0.15 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet10-store-clientcert | lambda | 10.0.15 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet10-store-clientcert-nohome | lambda | 10.0.15 | bundled | **PQ** | **PQ** | fail | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet10-tls12-pin | lambda | 10.0.15 | bundled | classical 1.2 | fail | classical 1.2 | classical 1.2 | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet10-tls12-tls13 | lambda | 10.0.15 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet8-baseline | lambda | 8.0.34 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet8-bundled-conf | lambda | 8.0.34 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet8-combined | lambda | 8.0.34 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| dotnet-lambda-dotnet8-combined-conf | lambda | 8.0.34 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet8-extension | lambda | 8.0.34 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| dotnet-lambda-dotnet8-layer-conf | lambda | 8.0.34 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet8-layer-wrapper | lambda | 8.0.34 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet8-ssl-cert-file | lambda | 8.0.34 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet8-store-clientcert | lambda | 8.0.34 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-dotnet8-store-clientcert-nohome | lambda | 8.0.34 | bundled | **PQ** | **PQ** | fail | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-image-dotnet10-baseline | lambda | 10.0.15 | image-baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-image-dotnet10-fixed | lambda | 10.0.15 | image-fixed | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-image-dotnet8-baseline | lambda | 8.0.34 | image-baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| dotnet-lambda-image-dotnet8-fixed | lambda | 8.0.34 | image-fixed | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |

## go

| Case | Compute | Runtime | Mode | hybrid | pqonly | mtls | eccert | tls12 | mldsa-dual | mldsa-only | mldsa-mtls | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| go-ec2-al2-distro-golang | ec2 | go1.26.10-X:nodwarf5 | distro-toolchain | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-ec2-al2-go123 | ec2 | go1.23.12 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-ec2-al2-go126 | ec2 | go1.26.11 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-ec2-al2-go127 | ec2 | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-ec2-al2023-distro-golang | ec2 | go1.26.10-X:nodwarf5 | distro-toolchain | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-ec2-al2023-go123 | ec2 | go1.23.12 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-ec2-al2023-go123-host-policy | ec2 | go1.23.12 | crypto-policy | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-ec2-al2023-go124 | ec2 | go1.24.13 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-ec2-al2023-go124-mod123-systemd-godebug | ec2 | go1.24.13 | godebug | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-ec2-al2023-go125 | ec2 | go1.25.14 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-ec2-al2023-go126 | ec2 | go1.26.11 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-ec2-al2023-go127 | ec2 | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-ec2-al2023-go127-fips140-on | ec2 | go1.27.4 | fips | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-ec2-al2023-go127-host-policy | ec2 | go1.27.4 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-ecsec2-al2023-go123 | ecs-ec2 | go1.23.12 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-ecsec2-al2023-go127 | ecs-ec2 | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-ecsec2-distroless-go124 | ecs-ec2 | go1.24.13 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-ecsec2-golang-go126 | ecs-ec2 | go1.26.11 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-ecsec2-scratch-go127 | ecs-ec2 | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-fargate-al2-go123 | ecs-fargate | go1.23.12 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-fargate-al2-go127 | ecs-fargate | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-fargate-al2023-go123 | ecs-fargate | go1.23.12 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-fargate-al2023-go124 | ecs-fargate | go1.24.13 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-fargate-al2023-go126-boring-fips140-on | ecs-fargate | unknown (crashed: probe-1.26-boring) | fips | fail | fail | fail | fail | fail | fail | fail | fail | PASS |
| go-fargate-al2023-go126-mod123-taskdef-godebug | ecs-fargate | go1.26.11 | godebug | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-fargate-al2023-go127 | ecs-fargate | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-fargate-al2023-policy-go123 | ecs-fargate | go1.23.12 | crypto-policy | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-fargate-al2023-policy-go127 | ecs-fargate | go1.27.4 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-fargate-distroless-go123 | ecs-fargate | go1.23.12 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-fargate-distroless-go124 | ecs-fargate | go1.24.13 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-fargate-distroless-go127 | ecs-fargate | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-fargate-doc-dockerfile | ecs-fargate | go1.26.11 | image | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-fargate-doc-dockerfile-fips | ecs-fargate | go1.26.11 | fips | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-fargate-golang-go123 | ecs-fargate | go1.23.12 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-fargate-golang-go124 | ecs-fargate | go1.24.13 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-fargate-golang-go127 | ecs-fargate | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-fargate-scratch-go123 | ecs-fargate | go1.23.12 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-fargate-scratch-go124 | ecs-fargate | go1.24.13 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-fargate-scratch-go127 | ecs-fargate | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-fargate-scratch-go127-no-bundle | ecs-fargate | go1.27.4 | trust | fail | fail | fail | fail | fail | ECDSA | fail | fail | PASS |
| go-fargate-scratch-go127-ssl-cert-file | ecs-fargate | go1.27.4 | trust | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2-go123-baseline | lambda | go1.23.12 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2-go123-clientcert-callback | lambda | go1.23.12 | mtls | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2-go123-extension | lambda | go1.23.12 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| go-lambda-al2-go123-pqtls-layer | lambda | go1.23.12 | layer | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2-go124-baseline | lambda | go1.24.13 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2-go124-gofips140 | lambda | go1.24.13 | fips | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2-go124-mod123-godebug-gomod | lambda | go1.24.13 | godebug | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2-go124-tlsmlkem0 | lambda | go1.24.13 | godebug | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2-go125-baseline | lambda | go1.25.14 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2-go125-mod123 | lambda | go1.25.14 | go-line | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2-go126-baseline | lambda | go1.26.11 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2-go126-gofips140-v100 | lambda | go1.26.11 | fips | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2-go127-baseline | lambda | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2-go127-trust-ssl-cert-dir | lambda | go1.27.4 | trust | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go123-baseline | lambda | go1.23.12 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go123-combined | lambda | go1.23.12 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| go-lambda-al2023-go123-combined-wrapper | lambda | go1.23.12 | layer | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go123-curve4588 | lambda | go1.23.12 | settings | fail | fail | fail | fail | fail | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go123-extension | lambda | go1.23.12 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| go-lambda-al2023-go123-pqtls-layer | lambda | go1.23.12 | layer | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go123-trust-ssl-cert-file | lambda | go1.23.12 | trust | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go124-baseline | lambda | go1.24.13 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go124-fips140-on | lambda | go1.24.13 | fips | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go124-fips140-only | lambda | go1.24.13 | fips | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go124-mod123 | lambda | go1.24.13 | go-line | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go124-mod123-godebug-env | lambda | go1.24.13 | godebug | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go124-trust-ssl-cert-file | lambda | go1.24.13 | trust | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go125-baseline | lambda | go1.25.14 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go125-boring-fipsonly | lambda | go1.25.14 X:boringcrypto | fips | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go125-fips140-on | lambda | go1.25.14 | fips | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go125-fips140-only | lambda | go1.25.14 | fips | fail | fail | fail | fail | fail | fail | fail | fail | PASS |
| go-lambda-al2023-go126-awssdk | lambda | go1.26.11 | library | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-awssdk-fips | lambda | go1.26.11 | library | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-awssdk-fips-fix | lambda | go1.26.11 | library | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-baseline | lambda | go1.26.11 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-boring | lambda | go1.26.11-X:boringcrypto | fips | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-boring-fipsonly | lambda | go1.26.11-X:boringcrypto | fips | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-ciphers12 | lambda | go1.26.11 | settings | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-clientcert-callback | lambda | go1.26.11 | mtls | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-clientcert-env-pem | lambda | go1.26.11 | mtls | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-clientcert-none | lambda | go1.26.11 | mtls | **PQ** | **PQ** | fail | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-curves-classical | lambda | go1.26.11 | settings | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-curves-hybrid | lambda | go1.26.11 | settings | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-curves-hybrid-tlsmlkem0 | lambda | go1.26.11 | settings | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-fips140-on | lambda | go1.26.11 | fips | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-fips140-only | lambda | go1.26.11 | fips | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-gofips140-v1260 | lambda | go1.26.11 | fips | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-max12 | lambda | go1.26.11 | settings | classical 1.2 | fail | classical 1.2 | classical 1.2 | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-min13 | lambda | go1.26.11 | settings | **PQ** | **PQ** | **PQ** | **PQ** | fail | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-mod123 | lambda | go1.26.11 | go-line | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-mod123-godebug-env | lambda | go1.26.11 | godebug | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-mod123-godebug-gomod | lambda | go1.26.11 | godebug | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-mod125 | lambda | go1.26.11 | go-line | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-p12-sslmate | lambda | go1.26.11 | mtls | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-p12-xcrypto | lambda | go1.26.11 | mtls | **PQ** | **PQ** | fail | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-pin-ca | lambda | go1.26.11 | pinning | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-pin-wrong | lambda | go1.26.11 | pinning | fail | fail | fail | fail | fail | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-rollback | lambda | go1.26.11 | godebug | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-tlssecpmlkem0 | lambda | go1.26.11 | godebug | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-trust-empty | lambda | go1.26.11 | trust | fail | fail | fail | fail | fail | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-trust-none | lambda | go1.26.11 | trust | fail | fail | fail | fail | fail | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-trust-ssl-cert-file | lambda | go1.26.11 | trust | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go126-trust-system-plus-ca | lambda | go1.26.11 | trust | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go127-awssdk-tlsmlkem0 | lambda | go1.27.4 | library | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go127-baseline | lambda | go1.27.4 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go127-boring-fipsonly | lambda | go1.27.4-X:boringcrypto | fips | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go127-curves-hybrid-tlsmlkem0 | lambda | go1.27.4 | settings | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go127-fips140-on | lambda | go1.27.4 | fips | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go127-fips140-only | lambda | go1.27.4 | fips | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go127-gofips140 | lambda | go1.27.4 | fips | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go127-mlkem1024 | lambda | go1.27.4 | settings | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go127-mod123 | lambda | go1.27.4 | go-line | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go127-mod123-directive | lambda | go1.27.4 | godebug | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go127-pqtls-layer | lambda | go1.27.4 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-al2023-go127-tlsmlkem0 | lambda | go1.27.4 | godebug | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-image-go123 | lambda | go1.23.12 | image | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| go-lambda-image-go126 | lambda | go1.26.11 | image | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |

## java

| Case | Compute | Runtime | Mode | hybrid | pqonly | mtls | eccert | tls12 | mldsa-dual | mldsa-only | mldsa-mtls | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| java-ec2-al2-j11-agent | ec2 | 11.0.33 | agent | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-ec2-al2-j11-baseline | ec2 | 11.0.33 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-ec2-al2-j17-agent | ec2 | 17.0.21 | agent | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-ec2-al2-j17-baseline | ec2 | 17.0.21 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-ec2-al2023-default-java | ec2 | 25.0.5 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-ec2-al2023-j11-agent | ec2 | 11.0.33 | agent | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-ec2-al2023-j11-baseline | ec2 | 11.0.33 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-ec2-al2023-j17-agent | ec2 | 17.0.21 | agent | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-ec2-al2023-j17-baseline | ec2 | 17.0.21 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-ec2-al2023-j21-agent | ec2 | 21.0.13 | agent | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-ec2-al2023-j21-agent-ec | ec2 | 21.0.13 | agent | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-ec2-al2023-j21-baseline | ec2 | 21.0.13 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-ec2-al2023-j25-baseline | ec2 | 25.0.5 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-ecsec2-corretto17-static | ecs-ec2 | 17.0.21 | static | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-ecsec2-corretto21-agent | ecs-ec2 | 21.0.13 | agent | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-ecsec2-corretto21-baseline | ecs-ec2 | 21.0.13 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-ecsec2-corretto25-baseline | ecs-ec2 | 25.0.5 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-ecsec2-corretto8-agent | ecs-ec2 | 1.8.0_512 | agent | fail | fail | fail | fail | fail | fail | fail | fail | PASS |
| java-fargate-al2023-j17-baseline | ecs-fargate | 17.0.21 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-fargate-al2023-j21-agent | ecs-fargate | 21.0.13 | agent | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-fargate-al2023-j21-baseline | ecs-fargate | 21.0.13 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-fargate-al2023-j25-baseline | ecs-fargate | 25.0.5 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-fargate-corretto11-agent | ecs-fargate | 11.0.33 | agent | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-fargate-corretto11-baseline | ecs-fargate | 11.0.33 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-fargate-corretto17-agent | ecs-fargate | 17.0.21 | agent | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-fargate-corretto17-baseline | ecs-fargate | 17.0.21 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-fargate-corretto17-static | ecs-fargate | 17.0.21 | static | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-fargate-corretto21-agent | ecs-fargate | 21.0.13 | agent | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-fargate-corretto21-agent-ec | ecs-fargate | 21.0.13 | agent | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-fargate-corretto21-agent-image | ecs-fargate | 21.0.13 | agent | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-fargate-corretto21-baseline | ecs-fargate | 21.0.13 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-fargate-corretto21-static | ecs-fargate | 21.0.13 | static | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-fargate-corretto21-static-ec | ecs-fargate | 21.0.13 | static | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-fargate-corretto25-baseline | ecs-fargate | 25.0.5 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-fargate-corretto8-agent | ecs-fargate | 1.8.0_512 | agent | fail | fail | fail | fail | fail | fail | fail | fail | PASS |
| java-fargate-corretto8-agent-hostfix | ecs-fargate | 1.8.0_512 | agent | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-fargate-corretto8-agent-noproto | ecs-fargate | 1.8.0_512 | agent | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-fargate-corretto8-baseline | ecs-fargate | 1.8.0_512 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-fargate-temurin21-static | ecs-fargate | 21.0.13 | static | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-image-j11-baseline | lambda | 11.0.33 | image-baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-image-j11-fixed | lambda | 11.0.33 | image-fixed | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-image-j17-baseline | lambda | 17.0.21 | image-baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-image-j17-fixed | lambda | 17.0.21 | image-fixed | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-image-j21-baseline | lambda | 21.0.13 | image-baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-image-j21-fixed | lambda | 21.0.13 | image-fixed | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-image-j25-baseline | lambda | 25.0.5 | image-baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-image-j8-baseline | lambda | 1.8.0_512 | image-baseline | classical 1.2 | fail | classical 1.2 | classical 1.2 | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-image-j8-fixed | lambda | 1.8.0_512 | image-fixed | fail | fail | fail | fail | fail | fail | fail | fail | PASS |
| java-lambda-image-j8-layer | lambda | 1.8.0_512 | image-layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-image-j8-layer-hostfix | lambda | 1.8.0_512 | image-layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j11-baseline | lambda | 11.0.33 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j11-bundled | lambda | 11.0.33 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j11-combined | lambda | 11.0.33 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j11-extension | lambda | 11.0.33 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| java-lambda-j11-layer | lambda | 11.0.33 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j11-layer-ownsec | lambda | 11.0.33 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j17-baseline | lambda | 17.0.21 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j17-bundled | lambda | 17.0.21 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j17-combined | lambda | 17.0.21 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j17-combined-ext | lambda | 17.0.21 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| java-lambda-j17-extension | lambda | 17.0.21 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| java-lambda-j17-ks-ec-pkix | lambda | 17.0.21 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j17-ks-ec-sunx509 | lambda | 17.0.21 | bundled | **PQ** | **PQ** | fail | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j17-ks-rsa-sunx509 | lambda | 17.0.21 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j17-layer | lambda | 17.0.21 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j21-baseline | lambda | 21.0.13 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j21-bundled | lambda | 21.0.13 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j21-combined | lambda | 21.0.13 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j21-extension | lambda | 21.0.13 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| java-lambda-j21-ks-ec-baseline | lambda | 21.0.13 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j21-ks-ec-bundled | lambda | 21.0.13 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j21-ks-ec-layer | lambda | 21.0.13 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j21-ks-ec-v1 | lambda | 21.0.13 | bundled | **PQ** | **PQ** | fail | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j21-layer | lambda | 21.0.13 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j21-layer-disabled | lambda | 21.0.13 | layer | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j21-layer-ownsec | lambda | 21.0.13 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j21-layer-pin | lambda | 21.0.13 | layer | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j21-static | lambda | 21.0.13 | static | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j21-sysprops-ec-baseline | lambda | 21.0.13 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j21-sysprops-ec-bundled | lambda | 21.0.13 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j21-sysprops-notrust-bundled | lambda | 21.0.13 | bundled | fail | fail | fail | fail | fail | ECDSA | fail | fail | PASS |
| java-lambda-j25-baseline | lambda | 25.0.5 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j25-combined | lambda | 25.0.5 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j25-extension | lambda | 25.0.5 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| java-lambda-j25-ks-ec-baseline | lambda | 25.0.5 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j25-layer | lambda | 25.0.5 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j25-pin | lambda | 25.0.5 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j25-sysprops-ec-baseline | lambda | 25.0.5 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j8-baseline | lambda | 1.8.0_512 | baseline | classical 1.2 | fail | classical 1.2 | classical 1.2 | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j8-bundled | lambda | 1.8.0_512 | bundled | fail | fail | fail | fail | fail | fail | fail | fail | PASS |
| java-lambda-j8-bundled-hostfix | lambda | 1.8.0_512 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j8-bundled-noproto | lambda | 1.8.0_512 | bundled | classical 1.2 | fail | classical 1.2 | classical 1.2 | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j8-combined | lambda | 1.8.0_512 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j8-extension | lambda | 1.8.0_512 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| java-lambda-j8-layer | lambda | 1.8.0_512 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| java-lambda-j8-layer-hostfix | lambda | 1.8.0_512 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |

## node

| Case | Compute | Runtime | Mode | hybrid | pqonly | mtls | eccert | tls12 | mldsa-dual | mldsa-only | mldsa-mtls | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| node-ec2-al2023-n20-baseline | ec2 | v20.20.2 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| node-ec2-al2023-n20-host-policy | ec2 | v20.20.2 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-ec2-al2023-n20-service-conf | ec2 | v20.20.2 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-ec2-al2023-n22-baseline | ec2 | v22.23.4 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| node-ec2-al2023-n22-host-policy | ec2 | v22.23.4 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-ec2-al2023-n22-service-conf | ec2 | v22.23.4 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-ec2-al2023-n24-baseline | ec2 | v24.22.1 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| node-ec2-al2023-n24-host-policy | ec2 | v24.22.1 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-ec2-al2023-n24-service-conf | ec2 | v24.22.1 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-ec2-al2023-official22-baseline | ec2 | v22.23.5 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-ec2-al2023-official24-baseline | ec2 | v24.22.3 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-ec2-al2023-official24-host-default-pq | ec2 | v24.22.3 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-ecsec2-al2023-n22-baseline | ecs-ec2 | v22.23.4 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| node-ecsec2-al2023-n22-conf | ecs-ec2 | v22.23.4 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-ecsec2-al2023-n24-policy | ecs-ec2 | v24.22.1 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-ecsec2-lib-20-slim | ecs-ec2 | v20.20.2 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| node-ecsec2-lib-24-slim | ecs-ec2 | v24.22.3 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-fargate-al2023-n20-baseline | ecs-fargate | v20.20.2 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| node-fargate-al2023-n20-conf | ecs-fargate | v20.20.2 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-fargate-al2023-n20-policy | ecs-fargate | v20.20.2 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-fargate-al2023-n22-baseline | ecs-fargate | v22.23.4 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| node-fargate-al2023-n22-conf | ecs-fargate | v22.23.4 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-fargate-al2023-n22-policy | ecs-fargate | v22.23.4 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-fargate-al2023-n24-baseline | ecs-fargate | v24.22.1 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| node-fargate-al2023-n24-conf | ecs-fargate | v24.22.1 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-fargate-al2023-n24-policy | ecs-fargate | v24.22.1 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-fargate-distro-alpine322 | ecs-fargate | v22.23.5 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-fargate-distro-debian13 | ecs-fargate | v20.19.2 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-fargate-lib-20-alpine | ecs-fargate | v20.20.2 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| node-fargate-lib-20-slim | ecs-fargate | v20.20.2 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| node-fargate-lib-22-alpine | ecs-fargate | v22.23.5 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-fargate-lib-22-slim | ecs-fargate | v22.23.5 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-fargate-lib-22-slim-fetch | ecs-fargate | v22.23.5 | baseline | **PQ** | **PQ** | - | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-fargate-lib-2219-alpine | ecs-fargate | v22.19.0 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| node-fargate-lib-2220-alpine | ecs-fargate | v22.20.0 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-fargate-lib-24-alpine | ecs-fargate | v24.22.3 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-fargate-lib-24-slim | ecs-fargate | v24.22.3 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-fargate-lib-24-slim-nec | ecs-fargate | v24.22.3 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-fargate-lib-24-slim-pfx | ecs-fargate | v24.22.3 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-fargate-lib-24-slim-pfx-legacy | ecs-fargate | v24.22.3 | baseline | **PQ** | **PQ** | fail | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-fargate-lib-24-slim-pfx-legacy-provider | ecs-fargate | v24.22.3 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-fargate-lib-24-slim-tls-max-12 | ecs-fargate | v24.22.3 | code | classical 1.2 | fail | classical 1.2 | classical 1.2 | classical 1.2 | ECDSA | fail | fail | PASS |
| node-fargate-lib-244-alpine | ecs-fargate | v24.4.1 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| node-fargate-lib-245-alpine | ecs-fargate | v24.5.0 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-fargate-lib-26-slim | ecs-fargate | v26.13.1 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-image-n22-baseline | lambda | v22.23.5 | image-baseline | classical | fail | classical | classical | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-image-n22-fixed | lambda | v22.23.5 | image-fixed | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-image-n24-baseline | lambda | v24.22.3 | image-baseline | classical | fail | classical | classical | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-image-n24-fixed | lambda | v24.22.3 | image-fixed | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n18-baseline | lambda | v18.20.8 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| node-lambda-n18-bundled-conf | lambda | v18.20.8 | bundled | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| node-lambda-n18-bundled-flag | lambda | v18.20.8 | bundled | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| node-lambda-n18-combined | lambda | v18.20.8 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| node-lambda-n18-extension | lambda | v18.20.8 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| node-lambda-n18-layer | lambda | v18.20.8 | layer | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| node-lambda-n20-baseline | lambda | v20.20.2 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| node-lambda-n20-bundled-conf | lambda | v20.20.2 | bundled | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| node-lambda-n20-bundled-flag | lambda | v20.20.2 | bundled | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| node-lambda-n20-combined | lambda | v20.20.2 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| node-lambda-n20-extension | lambda | v20.20.2 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| node-lambda-n20-layer | lambda | v20.20.2 | layer | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| node-lambda-n20-pfx-legacy | lambda | v20.20.2 | baseline | classical | fail | fail | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| node-lambda-n22-baseline | lambda | v22.23.5 | baseline | classical | fail | classical | classical | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n22-bundled-conf | lambda | v22.23.5 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n22-bundled-flag | lambda | v22.23.5 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n22-combined | lambda | v22.23.5 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| node-lambda-n22-devnull | lambda | v22.23.5 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n22-extension | lambda | v22.23.5 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| node-lambda-n22-layer | lambda | v22.23.5 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n22-layer-chain | lambda | v22.23.5 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n22-nec-bundled | lambda | v22.23.5 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n22-nec-layer | lambda | v22.23.5 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n22-pfx-legacy | lambda | v22.23.5 | bundled | **PQ** | **PQ** | fail | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n24-baseline | lambda | v24.22.3 | baseline | classical | fail | classical | classical | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n24-bundled-conf | lambda | v24.22.3 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n24-bundled-flag | lambda | v24.22.3 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n24-code-ecdh | lambda | v24.22.3 | code | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n24-code-ecdh-classical | lambda | v24.22.3 | code | classical | fail | classical | classical | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n24-combined | lambda | v24.22.3 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| node-lambda-n24-combined-wrapper | lambda | v24.22.3 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n24-devnull | lambda | v24.22.3 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n24-extension | lambda | v24.22.3 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| node-lambda-n24-fetch-nec | lambda | v24.22.3 | bundled | **PQ** | **PQ** | - | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n24-layer | lambda | v24.22.3 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n24-layer-disabled | lambda | v24.22.3 | layer | classical | fail | classical | classical | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n24-layer-ownconf | lambda | v24.22.3 | layer | classical | fail | classical | classical | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n24-nec-aws | lambda | v24.22.3 | baseline | classical | fail | classical | classical | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n24-nec-bundled | lambda | v24.22.3 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n24-nec-none | lambda | v24.22.3 | bundled | fail | fail | fail | fail | fail | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n24-pfx | lambda | v24.22.3 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n24-pfx-legacy | lambda | v24.22.3 | bundled | **PQ** | **PQ** | fail | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n24-pfx-legacy-provider | lambda | v24.22.3 | bundled | **PQ** | **PQ** | fail | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| node-lambda-n24-tls-max-12 | lambda | v24.22.3 | code | classical 1.2 | fail | classical 1.2 | classical 1.2 | classical 1.2 | ECDSA | fail | fail | PASS |

## python

| Case | Compute | Runtime | Mode | hybrid | pqonly | mtls | eccert | tls12 | mldsa-dual | mldsa-only | mldsa-mtls | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| py-ec2-al2-py3-baseline | ec2 | 3.7.16 | baseline | classical 1.2 | fail | classical 1.2 | classical 1.2 | classical 1.2 | ECDSA | fail | fail | PASS |
| py-ec2-al2023-py311-baseline | ec2 | 3.11.18 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| py-ec2-al2023-py311-host-policy | ec2 | 3.11.18 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| py-ec2-al2023-py312-baseline | ec2 | 3.12.16 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| py-ec2-al2023-py312-service-conf | ec2 | 3.12.16 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| py-ec2-al2023-py313-baseline | ec2 | 3.13.18 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| py-ec2-al2023-py313-host-policy | ec2 | 3.13.18 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| py-ec2-al2023-py314-baseline | ec2 | 3.14.10 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| py-ecsec2-al2023-py312-baseline | ecs-ec2 | 3.12.16 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| py-ecsec2-al2023-py312-conf | ecs-ec2 | 3.12.16 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| py-ecsec2-lib-313-slim-trixie | ecs-ec2 | 3.13.18 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| py-fargate-al2023-py311-baseline | ecs-fargate | 3.11.18 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| py-fargate-al2023-py311-conf | ecs-fargate | 3.11.18 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| py-fargate-al2023-py312-baseline | ecs-fargate | 3.12.16 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| py-fargate-al2023-py312-conf | ecs-fargate | 3.12.16 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| py-fargate-al2023-py312-policy | ecs-fargate | 3.12.16 | crypto-policy | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| py-fargate-al2023-py313-baseline | ecs-fargate | 3.13.18 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| py-fargate-al2023-py313-conf | ecs-fargate | 3.13.18 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| py-fargate-al2023-py314-baseline | ecs-fargate | 3.14.10 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| py-fargate-al2023-py314-conf | ecs-fargate | 3.14.10 | config | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| py-fargate-lib-312-alpine | ecs-fargate | 3.12.16 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| py-fargate-lib-312-slim-bookworm | ecs-fargate | 3.12.16 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| py-fargate-lib-312-slim-trixie | ecs-fargate | 3.12.16 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| py-fargate-lib-313-slim-trixie | ecs-fargate | 3.13.18 | baseline | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| py-lambda-image-py312-baseline | lambda | 3.12.16 | image-baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| py-lambda-image-py312-fixed | lambda | 3.12.16 | image-fixed | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| py-lambda-image-py313-baseline | lambda | 3.13.18 | image-baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| py-lambda-image-py313-fixed | lambda | 3.13.18 | image-fixed | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| py-lambda-py310-baseline | lambda | 3.10.22 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| py-lambda-py310-bundled-shim | lambda | 3.10.22 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| py-lambda-py310-extension | lambda | 3.10.22 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| py-lambda-py310-layer | lambda | 3.10.22 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| py-lambda-py311-baseline | lambda | 3.11.18 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| py-lambda-py311-bundled-shim | lambda | 3.11.18 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| py-lambda-py311-combined-ext-stdlib | lambda | 3.11.18 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| py-lambda-py311-extension | lambda | 3.11.18 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| py-lambda-py311-layer | lambda | 3.11.18 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| py-lambda-py311-layer-stdlib | lambda | 3.11.18 | layer | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| py-lambda-py311-shim-noidna | lambda | 3.11.18 | bundled | fail | fail | fail | fail | fail | fail | fail | fail | PASS |
| py-lambda-py312-baseline | lambda | 3.12.16 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| py-lambda-py312-bundled-conf | lambda | 3.12.16 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| py-lambda-py312-extension | lambda | 3.12.16 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| py-lambda-py312-layer | lambda | 3.12.16 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| py-lambda-py312-layer-chain | lambda | 3.12.16 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| py-lambda-py312-layer-disabled | lambda | 3.12.16 | layer | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| py-lambda-py312-layer-ownconf | lambda | 3.12.16 | layer | classical | fail | classical | classical | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| py-lambda-py313-baseline | lambda | 3.13.18 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| py-lambda-py313-bundled-conf | lambda | 3.13.18 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| py-lambda-py313-combined-wrapper | lambda | 3.13.18 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| py-lambda-py313-extension | lambda | 3.13.18 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| py-lambda-py313-layer | lambda | 3.13.18 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| py-lambda-py314-baseline | lambda | 3.14.10 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| py-lambda-py314-bundled-conf | lambda | 3.14.10 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| py-lambda-py314-extension | lambda | 3.14.10 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| py-lambda-py314-layer | lambda | 3.14.10 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | ECDSA | fail | fail | PASS |
| py-lambda-py39-baseline | lambda | 3.9.23 | baseline | classical | fail | classical | classical | classical 1.2 | ECDSA | fail | fail | PASS |
| py-lambda-py39-bundled-shim | lambda | 3.9.23 | bundled | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |
| py-lambda-py39-extension | lambda | 3.9.23 | extension | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | - | - | - | PASS |
| py-lambda-py39-layer | lambda | 3.9.23 | layer | **PQ** | **PQ** | **PQ** | **PQ** | classical 1.2 | **ML-DSA** | **ML-DSA** | **ML-DSA** | PASS |

## Findings (observed behaviour differs from the document or a kit file)

- `go-lambda-al2023-go124-fips140-on` (PASS, src/03-go.md:371): Fixed in the doc on 2026-11-14; kept as a regression check. Tab says 'P-256 only' (src/03-go.md:371, :374); the client offers P-256, P-384 and P-521 (crypto/tls defaultCurvePreferencesFIPS / allowedCurvePreferencesFIPS) and the server picked P-256. No PQ, no X25519 as claimed.
- `go-lambda-al2023-go124-fips140-only` (PASS, src/03-go.md:372): Fixed in the doc on 2026-11-14; kept as a regression check. Tab says 'P-256 only' (src/03-go.md:371, :374); the client offers P-256, P-384 and P-521 (crypto/tls defaultCurvePreferencesFIPS / allowedCurvePreferencesFIPS) and the server picked P-256. No PQ, no X25519 as claimed.
- `go-lambda-al2-go124-gofips140` (PASS, src/03-go.md:363, :523): Fixed in the doc on 2026-11-14; kept as a regression check. Tab says 'P-256 only' (src/03-go.md:371, :374); the client offers P-256, P-384 and P-521 (crypto/tls defaultCurvePreferencesFIPS / allowedCurvePreferencesFIPS) and the server picked P-256. No PQ, no X25519 as claimed.
- `go-lambda-al2023-go125-fips140-on` (PASS, src/03-go.md:19, :371): Fixed in the doc on 2026-11-14; kept as a regression check. Tab lists the FIPS groups as hybrids + 'P-256' (src/03-go.md:17, :371); the client also offers P-384 and P-521. PQ as claimed.
- `go-lambda-al2023-go126-fips140-on` (PASS, src/03-go.md:17-18, :371-372): Fixed in the doc on 2026-11-14; kept as a regression check. Tab lists the FIPS groups as hybrids + 'P-256' (src/03-go.md:17, :371); the client also offers P-384 and P-521. PQ as claimed.
- `go-lambda-al2023-go126-fips140-only` (PASS, src/03-go.md:17-18, :371-372): Fixed in the doc on 2026-11-14; kept as a regression check. Tab lists the FIPS groups as hybrids + 'P-256' (src/03-go.md:17, :371); the client also offers P-384 and P-521. PQ as claimed.
- `go-lambda-al2023-go127-fips140-on` (PASS, src/03-go.md:17-18, :371-372): Fixed in the doc on 2026-11-14; kept as a regression check. Tab lists the FIPS groups as hybrids + 'P-256' (src/03-go.md:17, :371); the client also offers P-384 and P-521. PQ as claimed.
- `go-lambda-al2023-go127-fips140-only` (PASS, src/03-go.md:17-18, :371-372): Fixed in the doc on 2026-11-14; kept as a regression check. Tab lists the FIPS groups as hybrids + 'P-256' (src/03-go.md:17, :371); the client also offers P-384 and P-521. PQ as claimed.
- `go-lambda-al2023-go126-gofips140-v1260` (PASS, src/03-go.md:365, :489, :831): Fixed in the doc on 2026-11-14; kept as a regression check. Tab lists the FIPS groups as hybrids + 'P-256' (src/03-go.md:17, :371); the client also offers P-384 and P-521. PQ as claimed.
- `go-lambda-al2-go126-gofips140-v100` (PASS, src/03-go.md:377): Fixed in the doc on 2026-11-14; kept as a regression check. Tab lists the FIPS groups as hybrids + 'P-256' (src/03-go.md:17, :371); the client also offers P-384 and P-521. PQ as claimed.
- `go-lambda-al2023-go127-gofips140` (PASS, src/03-go.md:17): Fixed in the doc on 2026-11-14; kept as a regression check. Tab lists the FIPS groups as hybrids + 'P-256' (src/03-go.md:17, :371); the client also offers P-384 and P-521. PQ as claimed.
- `go-lambda-al2023-go125-boring-fipsonly` (PASS, src/03-go.md:374): Fixed in the doc on 2026-11-14; kept as a regression check. Tab says 'P-256 only' (src/03-go.md:371, :374); the client offers P-256, P-384 and P-521 (crypto/tls defaultCurvePreferencesFIPS / allowedCurvePreferencesFIPS) and the server picked P-256. No PQ, no X25519 as claimed.
- `go-lambda-al2023-go126-boring-fipsonly` (PASS, src/03-go.md:374): Fixed in the doc on 2026-11-14; kept as a regression check. Tab says 'P-256 only' (src/03-go.md:371, :374); the client offers P-256, P-384 and P-521 (crypto/tls defaultCurvePreferencesFIPS / allowedCurvePreferencesFIPS) and the server picked P-256. No PQ, no X25519 as claimed.
- `go-lambda-al2023-go127-boring-fipsonly` (PASS, src/03-go.md:374): Fixed in the doc on 2026-11-14; kept as a regression check. Tab says 'P-256 only' (src/03-go.md:371, :374); the client offers P-256, P-384 and P-521 (crypto/tls defaultCurvePreferencesFIPS / allowedCurvePreferencesFIPS) and the server picked P-256. No PQ, no X25519 as claimed.
- `go-fargate-doc-dockerfile-fips` (PASS, src/03-go.md:489, :824-836): Fixed in the doc on 2026-11-14; kept as a regression check. Tab lists the FIPS groups as hybrids + 'P-256' (src/03-go.md:17, :371); the client also offers P-384 and P-521. PQ as claimed.
- `java-lambda-j8-bundled` (PASS, src/06-java.md Lambda: template.yaml (zip, kit v2)): Fixed in the doc and kit on 2026-11-14; this case keeps the old instructions as a regression check. src/06-java.md:30, :44 (and template.yaml at :962) say JDK 8 + kit (agent + -Djdk.tls.client.protocols=TLSv1.3,TLSv1.2) gives PQ. Observed on Corretto 8u512 (Lambda java8.al2, lambda/java:8.al2023 image, amazoncorretto:8 on ECS): with HttpsURLConnection every handshake fails, PQ and classical, with BCJSSE 'certificate_unknown(46) <- No hostname specified for HTTPS endpoint ID check'. JDK 8's HttpsURLConnection creates the socket without a host name; BCJSSE 1.78+ fails endpoint identification by default then (bc-java issue #1656). Adding -Dorg.bouncycastle.jsse.client.assumeOriginalHostName=true to JAVA_TOOL_OPTIONS fixes it (PQ on all targets, case java-lambda-j8-bundled-hostfix). The tab's JDK 8 test used raw SSLSocket, not HttpsURLConnection. JDK 11+ is not affected.
- `java-lambda-image-j8-fixed` (PASS, src/06-java.md Packaging table: Lambda container image): Fixed in the doc and kit on 2026-11-14; this case keeps the old instructions as a regression check. src/06-java.md:30, :44 (and template.yaml at :962) say JDK 8 + kit (agent + -Djdk.tls.client.protocols=TLSv1.3,TLSv1.2) gives PQ. Observed on Corretto 8u512 (Lambda java8.al2, lambda/java:8.al2023 image, amazoncorretto:8 on ECS): with HttpsURLConnection every handshake fails, PQ and classical, with BCJSSE 'certificate_unknown(46) <- No hostname specified for HTTPS endpoint ID check'. JDK 8's HttpsURLConnection creates the socket without a host name; BCJSSE 1.78+ fails endpoint identification by default then (bc-java issue #1656). Adding -Dorg.bouncycastle.jsse.client.assumeOriginalHostName=true to JAVA_TOOL_OPTIONS fixes it (PQ on all targets, case java-lambda-j8-bundled-hostfix). The tab's JDK 8 test used raw SSLSocket, not HttpsURLConnection. JDK 11+ is not affected.
- `java-fargate-corretto8-baseline` (PASS, src/06-java.md By JDK and compute type (Fargate column)): Fixed in the doc and kit on 2026-11-14; this case keeps the old instructions as a regression check. src/06-java.md:30 ('SunJSSE, TLS 1.2 client default'), :376 ('8 defaults clients to TLS 1.2') and :445 state it for JDK 8 generally. Observed: only the Lambda Java 8 runtime sets jdk.tls.client.protocols=TLSv1.2,TLSv1.1,TLSv1 (java8.al2 zip and the lambda/java:8.al2023 image, also under the image's own RIE without LocalStack); a plain Corretto 8u512 (amazoncorretto:8, and /var/lang/bin/java in the Lambda image started directly) offers TLS 1.3 by default (classical P-256 here). BCJSSE honours the same property, so on Lambda the flag is required with the kit; in containers and EC2 with 8u512 it is not (java-fargate-corretto8-agent-noproto is PQ without it). The flag in JAVA_TOOL_OPTIONS overrides Lambda's value.
- `java-fargate-corretto8-agent` (PASS, src/06-java.md taskdef.json): Fixed in the doc and kit on 2026-11-14; this case keeps the old instructions as a regression check. src/06-java.md:30, :44 (and template.yaml at :962) say JDK 8 + kit (agent + -Djdk.tls.client.protocols=TLSv1.3,TLSv1.2) gives PQ. Observed on Corretto 8u512 (Lambda java8.al2, lambda/java:8.al2023 image, amazoncorretto:8 on ECS): with HttpsURLConnection every handshake fails, PQ and classical, with BCJSSE 'certificate_unknown(46) <- No hostname specified for HTTPS endpoint ID check'. JDK 8's HttpsURLConnection creates the socket without a host name; BCJSSE 1.78+ fails endpoint identification by default then (bc-java issue #1656). Adding -Dorg.bouncycastle.jsse.client.assumeOriginalHostName=true to JAVA_TOOL_OPTIONS fixes it (PQ on all targets, case java-lambda-j8-bundled-hostfix). The tab's JDK 8 test used raw SSLSocket, not HttpsURLConnection. JDK 11+ is not affected.
- `java-fargate-corretto8-agent-noproto` (PASS, src/06-java.md JVM flags: jdk.tls.client.protocols): Fixed in the doc and kit on 2026-11-14; this case keeps the old instructions as a regression check. src/06-java.md:30 ('SunJSSE, TLS 1.2 client default'), :376 ('8 defaults clients to TLS 1.2') and :445 state it for JDK 8 generally. Observed: only the Lambda Java 8 runtime sets jdk.tls.client.protocols=TLSv1.2,TLSv1.1,TLSv1 (java8.al2 zip and the lambda/java:8.al2023 image, also under the image's own RIE without LocalStack); a plain Corretto 8u512 (amazoncorretto:8, and /var/lang/bin/java in the Lambda image started directly) offers TLS 1.3 by default (classical P-256 here). BCJSSE honours the same property, so on Lambda the flag is required with the kit; in containers and EC2 with 8u512 it is not (java-fargate-corretto8-agent-noproto is PQ without it). The flag in JAVA_TOOL_OPTIONS overrides Lambda's value.
- `java-ecsec2-corretto8-agent` (PASS, src/06-java.md Packaging table: Fargate, ECS, EKS): Fixed in the doc and kit on 2026-11-14; this case keeps the old instructions as a regression check. src/06-java.md:30, :44 (and template.yaml at :962) say JDK 8 + kit (agent + -Djdk.tls.client.protocols=TLSv1.3,TLSv1.2) gives PQ. Observed on Corretto 8u512 (Lambda java8.al2, lambda/java:8.al2023 image, amazoncorretto:8 on ECS): with HttpsURLConnection every handshake fails, PQ and classical, with BCJSSE 'certificate_unknown(46) <- No hostname specified for HTTPS endpoint ID check'. JDK 8's HttpsURLConnection creates the socket without a host name; BCJSSE 1.78+ fails endpoint identification by default then (bc-java issue #1656). Adding -Dorg.bouncycastle.jsse.client.assumeOriginalHostName=true to JAVA_TOOL_OPTIONS fixes it (PQ on all targets, case java-lambda-j8-bundled-hostfix). The tab's JDK 8 test used raw SSLSocket, not HttpsURLConnection. JDK 11+ is not affected.
- `node-lambda-n18-baseline` (PASS, src/05-nodejs.md version table l.21-25, Lambda zip l.352): Fixed in the doc on 2026-11-14; kept as a regression check. Outcome as documented (classical, no fix), but the library differs: on Lambda nodejs18.x process.versions.openssl is 3.1.8, not the 'Bundled OpenSSL 3.0.x' of src/05-nodejs.md l.25 (that is node:20-slim's 3.0.19). Neither has ML-KEM, and the bundled openssl-pq-node.cnf / --openssl-config / layer leave it classical without breaking startup (cases node-lambda-n18-bundled-*).
- `node-lambda-n20-baseline` (PASS, src/05-nodejs.md version table l.21-25, Lambda zip l.352): Fixed in the doc on 2026-11-14; kept as a regression check. Outcome as documented (classical, no fix), but the library differs: on Lambda nodejs20.x process.versions.openssl is 3.2.6, not the 'Bundled OpenSSL 3.0.x' of src/05-nodejs.md l.25 (that is node:20-slim's 3.0.19). Neither has ML-KEM, and the bundled openssl-pq-node.cnf / --openssl-config / layer leave it classical without breaking startup (cases node-lambda-n20-bundled-*).
- `node-fargate-al2023-n20-conf` (PASS, src/05-nodejs.md l.25, l.38 (Node 20: no setting adds PQ)): Fixed in the doc on 2026-11-14; kept as a regression check. AL2023 dnf nodejs20 (20.20.2) links the system OpenSSL 3.5.8, so it negotiates X25519MLKEM768 once the crypto policy is DEFAULT:PQ or OPENSSL_CONF points at openssl-pq-node-system.cnf, exactly like nodejs22/24. The tab says the opposite: src/05-nodejs.md l.25 ('20.x ... No / No / No ... Upgrade; no setting adds PQ'), l.38 ('any Node below 22.20 / 24.5: upgrade ... There is no setting') and l.5 ('anything on Node 20 or older'). l.452 already notes this for Debian 13's Node 20; the l.26 AL2023 row should cover nodejs20 too, and the rule should be 'check process.versions.openssl'.
- `node-fargate-al2023-n20-policy` (PASS, src/05-nodejs.md l.25, l.38 (Node 20: no setting adds PQ)): Fixed in the doc on 2026-11-14; kept as a regression check. AL2023 dnf nodejs20 (20.20.2) links the system OpenSSL 3.5.8, so it negotiates X25519MLKEM768 once the crypto policy is DEFAULT:PQ or OPENSSL_CONF points at openssl-pq-node-system.cnf, exactly like nodejs22/24. The tab says the opposite: src/05-nodejs.md l.25 ('20.x ... No / No / No ... Upgrade; no setting adds PQ'), l.38 ('any Node below 22.20 / 24.5: upgrade ... There is no setting') and l.5 ('anything on Node 20 or older'). l.452 already notes this for Debian 13's Node 20; the l.26 AL2023 row should cover nodejs20 too, and the rule should be 'check process.versions.openssl'.
- `py-lambda-py311-shim-noidna` (PASS, src/04-python.md Bridge (pip install line)): Fixed in the doc on 2026-11-14; kept as a regression check. Bridge step installs only pyopenssl + cryptography; urllib3.contrib.pyopenssl also imports idna, which the Lambda runtime lacks, so every urllib3/boto3 request raises ImportError. Add idna to the pip line (and build per Python version: the 3.11 abi3 cryptography wheel fails on 3.9/3.10).
- `go-ec2-al2023-go127-fips140-on` (PASS, src/03-go.md:17): Fixed in the doc on 2026-11-14; kept as a regression check. Tab lists the FIPS groups as hybrids + 'P-256' (src/03-go.md:17, :371); the client also offers P-384 and P-521. PQ as claimed.
- `node-ec2-al2023-n20-service-conf` (PASS, src/05-nodejs.md l.25, l.38 (Node 20: no setting adds PQ)): Fixed in the doc on 2026-11-14; kept as a regression check. AL2023 dnf nodejs20 (20.20.2) links the system OpenSSL 3.5.8, so it negotiates X25519MLKEM768 once the crypto policy is DEFAULT:PQ or OPENSSL_CONF points at openssl-pq-node-system.cnf, exactly like nodejs22/24. The tab says the opposite: src/05-nodejs.md l.25 ('20.x ... No / No / No ... Upgrade; no setting adds PQ'), l.38 ('any Node below 22.20 / 24.5: upgrade ... There is no setting') and l.5 ('anything on Node 20 or older'). l.452 already notes this for Debian 13's Node 20; the l.26 AL2023 row should cover nodejs20 too, and the rule should be 'check process.versions.openssl'.
- `node-ec2-al2023-n20-host-policy` (PASS, src/05-nodejs.md l.25, l.38 (Node 20: no setting adds PQ)): Fixed in the doc on 2026-11-14; kept as a regression check. AL2023 dnf nodejs20 (20.20.2) links the system OpenSSL 3.5.8, so it negotiates X25519MLKEM768 once the crypto policy is DEFAULT:PQ or OPENSSL_CONF points at openssl-pq-node-system.cnf, exactly like nodejs22/24. The tab says the opposite: src/05-nodejs.md l.25 ('20.x ... No / No / No ... Upgrade; no setting adds PQ'), l.38 ('any Node below 22.20 / 24.5: upgrade ... There is no setting') and l.5 ('anything on Node 20 or older'). l.452 already notes this for Debian 13's Node 20; the l.26 AL2023 row should cover nodejs20 too, and the rule should be 'check process.versions.openssl'.
