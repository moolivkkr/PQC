## Language runbooks

| File | Purpose | Side | Applies to | Tab |
|---|---|---|---|---|
| `go.mod` (go line 1.26+) | Raise the `go` line so `DefaultGODEBUG` keeps ML-KEM on | Both | Go, all compute | <?claude block go?> |
| `go.mod` (old go line + `godebug`) | Keep an old `go` line and turn PQ on with `tlsmlkem=1` | Both | Go, all compute | <?claude block go?> |
| `cmd/client/main.go` | HTTP and AWS SDK client, FIPS-safe group list | Client | Go, all compute | <?claude block go?> |
| `cmd/server/main.go` | HTTPS and gRPC server that logs the negotiated group | Server | Go; ECS, EKS, EC2 | <?claude block go?> |
| `cmd/lambda/main.go` | Lambda handler | Client | Go; Lambda | <?claude block go?> |
| `Makefile` | Build the Lambda zip | Client | Go; Lambda zip | <?claude block go?> |
| `Dockerfile` (distroless) | Container build | Both | Go; Fargate, ECS, EKS | <?claude block go?> |
| `Dockerfile.lambda` | Lambda container image | Client | Go; Lambda image | <?claude block go?> |
| `Dockerfile.fips` | FIPS 140-3 build (`GOFIPS140`) | Both | Go FIPS; containers | <?claude block go?> |
| `template.yaml` (SAM) | Lambda zip deployment | Client | Go; Lambda zip | <?claude block go?> |
| `lambda-cfn.yaml` | Plain CloudFormation, zip in S3 | Client | Go; Lambda zip | <?claude block go?> |
| `lambda.tf` | Terraform, zip and image | Client | Go; Lambda | <?claude block go?> |
| `taskdef.json` | ECS task definition | Both | Go; ECS, Fargate | <?claude block go?> |
| `ecs-task.tf` | Terraform for the same task definition | Both | Go; ECS, Fargate | <?claude block go?> |
| `deployment.yaml` | Kubernetes Deployment | Both | Go; EKS | <?claude block go?> |
| `/etc/systemd/system/payments-api.service` | Service unit | Both | Go; EC2 | <?claude block go?> |
| `go-pq-posture.sh` | CI gate and image or host scan of Go binaries | Infra | Go; CI, images, EC2 via SSM | <?claude block go?> |
| `pq-tls/openssl-pq.cnf` | AL2023 crypto policy plus X25519MLKEM768 | Both | Python; Lambda 3.12+, AL2023 images and hosts | <?claude block py?> |
| `pq-tls/pyshim/sitecustomize.py` | Routes requests and boto3 through pyOpenSSL | Client | Python 3.9 to 3.11; Lambda only | <?claude block py?> |
| `template.yaml` (SAM) | Lambda zip, python3.13 | Client | Python; Lambda zip | <?claude block py?> |
| `cfn/lambda.yaml` | CloudFormation, Lambda zip | Client | Python; Lambda zip | <?claude block py?> |
| `terraform/lambda.tf` | Terraform, Lambda zip | Client | Python; Lambda zip | <?claude block py?> |
| `terraform/lambda-legacy.tf` | python3.11 bridge with the shim | Client | Python 3.11; Lambda zip | <?claude block py?> |
| `Dockerfile.lambda` | Lambda container image | Client | Python; Lambda image | <?claude block py?> |
| `Dockerfile` (Debian 13) | Image that is PQ with no setting | Both | Python; Fargate, ECS, EKS | <?claude block py?> |
| `Dockerfile.al2023` | AL2023 image with `DEFAULT:PQ` | Both | Python; Fargate, ECS, EKS | <?claude block py?> |
| `ecs/taskdef.json` | ECS task definition | Both | Python; Fargate | <?claude block py?> |
| `k8s/deployment.yaml` | Kubernetes Deployment | Both | Python; EKS | <?claude block py?> |
| `gunicorn.conf.py` | gunicorn TLS, `set_groups` on 3.15 | Server | Python; containers, EC2 | <?claude block py?> |
| `serve_uvicorn.py` | uvicorn TLS with an explicit group list | Server | Python 3.15; containers, EC2 | <?claude block py?> |
| `/etc/systemd/system/orders.service` | Service unit scoped to one service | Both | Python; EC2 AL2023 | <?claude block py?> |
| `ssm/pq-crypto-policy.yaml` | SSM document: `DEFAULT:PQ` and restart | Infra | Python; EC2 AL2023 | <?claude block py?> |
| `pq_probe.py` | Posture and live check | Client | Python; all compute | <?claude block py?> |
| `pq-tls/openssl-pq-node.cnf` | AWS's Node config with X25519MLKEM768 added | Client | Node 22/24; Lambda | <?claude block node?> |
| `/etc/app/openssl-pq-node-system.cnf` | PQ groups for distro Node on system OpenSSL | Both | Node (distro); AL2023 images, EC2 | <?claude block node?> |
| `check-lambda-node-conf.sh` | Pipeline diff of AWS's file against ours | Infra | Node; Lambda, CI | <?claude block node?> |
| `src/tls-pq.js` | Shared TLS options with feature detection | Both | Node 20 to 24; all compute | <?claude block node?> |
| `pq-check.js` | Posture and live check | Client | Node; all compute | <?claude block node?> |
| `server.js` | Express on HTTPS | Server | Node; containers, EC2 | <?claude block node?> |
| `template.yaml` (SAM) | Lambda zip | Client | Node; Lambda zip | <?claude block node?> |
| `lambda-cfn.yaml` | CloudFormation, Lambda zip | Client | Node; Lambda zip | <?claude block node?> |
| `lambda.tf` | Terraform, Lambda zip | Client | Node; Lambda zip | <?claude block node?> |
| `Dockerfile.lambda` | Lambda container image | Client | Node; Lambda image | <?claude block node?> |
| `Dockerfile` (node:24-slim) | Official image, nothing PQ-specific | Both | Node; Fargate, ECS, EKS | <?claude block node?> |
| `Dockerfile.al2023` | Distro Node with `DEFAULT:PQ` | Both | Node; Fargate, ECS, EKS | <?claude block node?> |
| `taskdef.json` | ECS task definition | Both | Node; ECS, Fargate | <?claude block node?> |
| `ecs.tf` | Terraform task definition | Both | Node; ECS, Fargate | <?claude block node?> |
| `ecs-cfn.yaml` | CloudFormation task definition | Both | Node; ECS, Fargate | <?claude block node?> |
| `deployment.yaml` | Kubernetes Deployment | Both | Node; EKS | <?claude block node?> |
| `/etc/systemd/system/orders.service` | Service unit | Both | Node; EC2 | <?claude block node?> |
| `pq-node-posture.json` | SSM document: report running Node processes | Infra | Node; EC2 | <?claude block node?> |
| `pq-tls-agent/src/PqTlsAgent.java` | Agent that puts BCJSSE first | Both | Java 8 to 21; all compute | <?claude block java?> |
| `pq-tls-agent/MANIFEST.MF` | Agent jar manifest | Both | Java 8 to 21 | <?claude block java?> |
| `pq-tls-agent/build.sh` | Build the agent with Java 8 bytecode | Infra | Java 8 to 21; CI | <?claude block java?> |
| `pom.xml` (excerpt) | PQ-relevant dependencies (BC, tcnative, SDK 2.59.1) | Both | Java; all compute | <?claude block java?> |
| `build.gradle.kts` | Same choices for Gradle | Both | Java; all compute | <?claude block java?> |
| `pq-tls/bc-static.security` | Static BCJSSE registration | Both | Java 11 to 21; containers, EC2 | <?claude block java?> |
| `src/main/resources/application.yml` | Spring Boot TLS | Server | Java; containers, EC2 | <?claude block java?> |
| `PqTomcatGroups.java` | Spring connector customizer for groups (Unverified) | Server | Java; Spring Boot | <?claude block java?> |
| `conf/server.xml` | Standalone Tomcat connector `groups` | Server | Java; Tomcat | <?claude block java?> |
| `bin/setenv.sh` | Agent for Tomcat on JDK 17/21 | Server | Java 17/21; Tomcat | <?claude block java?> |
| `NettyPq.java` | Netty client and server with tcnative | Both | Java; any JDK | <?claude block java?> |
| `AwsClients.java` | AWS SDK v2 CRT client | Client | Java; all compute | <?claude block java?> |
| Zip layout (`function.zip`) | Where the agent sits in the package | Client | Java 8 to 21; Lambda zip | <?claude block java?> |
| `template.yaml` (SAM) | Lambda with `JAVA_TOOL_OPTIONS` | Client | Java; Lambda zip | <?claude block java?> |
| `lambda.yaml` | Plain CloudFormation | Client | Java; Lambda zip | <?claude block java?> |
| `lambda.tf` | Terraform | Client | Java; Lambda zip | <?claude block java?> |
| `Dockerfile.lambda` | Lambda image on java:21 | Client | Java; Lambda image | <?claude block java?> |
| `Dockerfile` (JDK 25.0.5+) | Preferred image, no PQ lines | Both | Java 25; Fargate, ECS, EKS | <?claude block java?> |
| `Dockerfile.jdk21-agent` | JDK 17/21 with the agent | Both | Java 17/21; containers | <?claude block java?> |
| `Dockerfile.distroless-agent` | Distroless image with the agent | Both | Java 21; containers | <?claude block java?> |
| `Dockerfile.static` | Static provider registration | Both | Java 21; containers | <?claude block java?> |
| `taskdef.json` | ECS task definition | Both | Java; ECS, Fargate | <?claude block java?> |
| `ecs.tf` | Terraform task definition | Both | Java; ECS, Fargate | <?claude block java?> |
| `ecs.yaml` | CloudFormation task definition | Both | Java; ECS, Fargate | <?claude block java?> |
| `deployment.yaml` | Kubernetes Deployment | Both | Java; EKS | <?claude block java?> |
| `/etc/systemd/system/orders-java.service` | Service unit | Both | Java; EC2 | <?claude block java?> |
| `orders-java.service.d/pq-tls.conf` | Drop-in that adds the agent | Both | Java 8 to 21; EC2 | <?claude block java?> |
| `pq-tls-ssm.yaml` | SSM document: install kit and drop-in | Infra | Java; EC2 | <?claude block java?> |
| `pq-tls/openssl-pq.cnf` | AL2023 crypto policy plus X25519MLKEM768 | Both | .NET; Lambda, AL2023 images and hosts | <?claude block net?> |
| `Program.cs` | Kestrel HTTPS server | Server | .NET; containers, EC2 | <?claude block net?> |
| `appsettings.json` | Kestrel endpoint and protocols | Server | .NET; containers, EC2 | <?claude block net?> |
| `App.csproj` | Kestrel service project | Server | .NET | <?claude block net?> |
| `Function.csproj` | Ships the config at `/var/task/pq-tls/` | Client | .NET; Lambda zip | <?claude block net?> |
| `FunctionAot.csproj` | Native AOT on provided.al2023 | Client | .NET; Lambda custom runtime | <?claude block net?> |
| `Dockerfile` (Alpine) | PQ with no config | Both | .NET; Fargate, ECS, EKS | <?claude block net?> |
| `Dockerfile.resolute` | Ubuntu 26.04, PQ with no config | Both | .NET 10; Fargate, ECS, EKS | <?claude block net?> |
| `Dockerfile.al2023` | AL2023 image with the config file | Both | .NET; Fargate, ECS, EKS | <?claude block net?> |
| `Dockerfile.lambda` | Lambda container image | Client | .NET; Lambda image | <?claude block net?> |
| `template.yaml` (SAM) | Zip on managed runtime and AOT | Client | .NET; Lambda | <?claude block net?> |
| `lambda.cfn.yaml` | Plain CloudFormation | Client | .NET; Lambda | <?claude block net?> |
| `lambda.tf` | Terraform | Client | .NET; Lambda | <?claude block net?> |
| `taskdef.json` | ECS task definition | Both | .NET; ECS, Fargate | <?claude block net?> |
| `ecs.tf` | Terraform task definition | Both | .NET; ECS, Fargate | <?claude block net?> |
| `ecs.cfn.yaml` | CloudFormation task definition | Both | .NET; ECS, Fargate | <?claude block net?> |
| `deployment.yaml` | Kubernetes Deployment | Both | .NET; EKS | <?claude block net?> |
| `/etc/systemd/system/orders-api.service` | Service unit with `OPENSSL_CONF` | Both | .NET; EC2 AL2023 | <?claude block net?> |
| `ssm-al2023-pq-policy.yaml` | SSM document: `DEFAULT:PQ` on the host | Infra | .NET; EC2 AL2023 | <?claude block net?> |
| `Enable-PqTls.ps1` | Schannel group order (hybrid first) | Both | .NET; Windows Server 2025, Windows 11 | <?claude block net?> |
| `ssm-windows-pq.json` | SSM document wrapping the script | Infra | .NET; EC2 Windows | <?claude block net?> |
| `appsettings.json` (Kafka) + producer setup | Confluent.Kafka (librdkafka bundles OpenSSL) | Client | .NET; all compute | <?claude block net?> |
