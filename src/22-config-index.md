# Appendix B. Configuration file index

Every configuration file the paper refers to, with what it does, which side of the connection it changes, and where it applies. Each file name links to the complete file in the repository under `configs/` (the per-folder list is [configs/MANIFEST.md](REPO/configs/MANIFEST.md)); the chapter named in the last column explains it. Side: Client = outbound TLS from the workload; Server = inbound TLS it terminates; Both = the file sets the runtime or image, so it covers both directions; Infra = deployment, policy, detection or CI file that changes no handshake by itself. IaC and SSM files were linted or parse-checked, not deployed.

## Languages

| File | Purpose | Side | Applies to | Tab |
| --- | --- | --- | --- | --- |
| `go.mod` (go line 1.26+) | Raise the `go` line so `DefaultGODEBUG` keeps ML-KEM on | Both | Go, all compute | Go |
| `go.mod` (old go line + `godebug`) | Keep an old `go` line and turn PQ on with `tlsmlkem=1` | Both | Go, all compute | Go |
| `cmd/client/main.go` | HTTP and AWS SDK client, FIPS-safe group list | Client | Go, all compute | Go |
| `cmd/server/main.go` | HTTPS and gRPC server that logs the negotiated group | Server | Go; ECS, EKS, EC2 | Go |
| `cmd/lambda/main.go` | Lambda handler | Client | Go; Lambda | Go |
| `Makefile` | Build the Lambda zip | Client | Go; Lambda zip | Go |
| `Dockerfile` (distroless) | Container build | Both | Go; Fargate, ECS, EKS | Go |
| `Dockerfile.lambda` | Lambda container image | Client | Go; Lambda image | Go |
| `Dockerfile.fips` | FIPS 140-3 build (`GOFIPS140`) | Both | Go FIPS; containers | Go |
| `template.yaml` (SAM) | Lambda zip deployment | Client | Go; Lambda zip | Go |
| `lambda-cfn.yaml` | Plain CloudFormation, zip in S3 | Client | Go; Lambda zip | Go |
| `lambda.tf` | Terraform, zip and image | Client | Go; Lambda | Go |
| `taskdef.json` | ECS task definition | Both | Go; ECS, Fargate | Go |
| `ecs-task.tf` | Terraform for the same task definition | Both | Go; ECS, Fargate | Go |
| `deployment.yaml` | Kubernetes Deployment | Both | Go; EKS | Go |
| `/etc/systemd/system/payments-api.service` | Service unit | Both | Go; EC2 | Go |
| `go-pq-posture.sh` | CI gate and image or host scan of Go binaries | Infra | Go; CI, images, EC2 via SSM | Go |
| `pq-tls/openssl-pq.cnf` | AL2023 crypto policy plus X25519MLKEM768 | Both | Python; Lambda 3.12+, AL2023 images and hosts | Python |
| `pq-tls/pyshim/sitecustomize.py` | Routes requests and boto3 through pyOpenSSL (package must also contain pyOpenSSL, cryptography and idna) | Client | Python 3.9 to 3.11; Lambda only | Python |
| `template.yaml` (SAM) | Lambda zip, python3.13 | Client | Python; Lambda zip | Python |
| `cfn/lambda.yaml` | CloudFormation, Lambda zip | Client | Python; Lambda zip | Python |
| `terraform/lambda.tf` | Terraform, Lambda zip | Client | Python; Lambda zip | Python |
| `terraform/lambda-legacy.tf` | python3.11 bridge with the shim | Client | Python 3.11; Lambda zip | Python |
| `Dockerfile.lambda` | Lambda container image | Client | Python; Lambda image | Python |
| `Dockerfile` (Debian 13) | Image that is PQ with no setting | Both | Python; Fargate, ECS, EKS | Python |
| `Dockerfile.al2023` | AL2023 image with `DEFAULT:PQ` | Both | Python; Fargate, ECS, EKS | Python |
| `ecs/taskdef.json` | ECS task definition | Both | Python; Fargate | Python |
| `k8s/deployment.yaml` | Kubernetes Deployment | Both | Python; EKS | Python |
| `gunicorn.conf.py` | gunicorn TLS, `set_groups` on 3.15 | Server | Python; containers, EC2 | Python |
| `serve_uvicorn.py` | uvicorn TLS with an explicit group list | Server | Python 3.15; containers, EC2 | Python |
| `/etc/systemd/system/orders.service` | Service unit scoped to one service | Both | Python; EC2 AL2023 | Python |
| `ssm/pq-crypto-policy.yaml` | SSM document: `DEFAULT:PQ` and restart | Infra | Python; EC2 AL2023 | Python |
| `pq_probe.py` | Posture and live check | Client | Python; all compute | Python |
| `pq-tls/openssl-pq-node.cnf` | AWS's Node config with X25519MLKEM768 added | Client | Node 22/24; Lambda | Node.js |
| `/etc/app/openssl-pq-node-system.cnf` | PQ groups for distro Node on system OpenSSL | Both | Node (distro); AL2023 images, EC2 | Node.js |
| `check-lambda-node-conf.sh` | Pipeline diff of AWS's file against ours | Infra | Node; Lambda, CI | Node.js |
| `src/tls-pq.js` | Shared TLS options with feature detection | Both | Node 20 to 24; all compute | Node.js |
| `pq-check.js` | Posture and live check | Client | Node; all compute | Node.js |
| `server.js` | Express on HTTPS | Server | Node; containers, EC2 | Node.js |
| `template.yaml` (SAM) | Lambda zip | Client | Node; Lambda zip | Node.js |
| `lambda-cfn.yaml` | CloudFormation, Lambda zip | Client | Node; Lambda zip | Node.js |
| `lambda.tf` | Terraform, Lambda zip | Client | Node; Lambda zip | Node.js |
| `Dockerfile.lambda` | Lambda container image | Client | Node; Lambda image | Node.js |
| `Dockerfile` (node:24-slim) | Official image, nothing PQ-specific | Both | Node; Fargate, ECS, EKS | Node.js |
| `Dockerfile.al2023` | Distro Node with `DEFAULT:PQ` | Both | Node; Fargate, ECS, EKS | Node.js |
| `taskdef.json` | ECS task definition | Both | Node; ECS, Fargate | Node.js |
| `ecs.tf` | Terraform task definition | Both | Node; ECS, Fargate | Node.js |
| `ecs-cfn.yaml` | CloudFormation task definition | Both | Node; ECS, Fargate | Node.js |
| `deployment.yaml` | Kubernetes Deployment | Both | Node; EKS | Node.js |
| `/etc/systemd/system/orders.service` | Service unit | Both | Node; EC2 | Node.js |
| `pq-node-posture.json` | SSM document: report running Node processes | Infra | Node; EC2 | Node.js |
| `pq-tls-agent/src/PqTlsAgent.java` | Agent that puts BCJSSE first | Both | Java 8 to 21; all compute | Java |
| `pq-tls-agent/MANIFEST.MF` | Agent jar manifest | Both | Java 8 to 21 | Java |
| `pq-tls-agent/build.sh` | Build the agent with Java 8 bytecode | Infra | Java 8 to 21; CI | Java |
| `pom.xml` (excerpt) | PQ-relevant dependencies (BC, tcnative, SDK 2.59.1) | Both | Java; all compute | Java |
| `build.gradle.kts` | Same choices for Gradle | Both | Java; all compute | Java |
| `pq-tls/bc-static.security` | Static BCJSSE registration | Both | Java 11 to 21; containers, EC2 | Java |
| `src/main/resources/application.yml` | Spring Boot TLS | Server | Java; containers, EC2 | Java |
| `PqTomcatGroups.java` | Spring connector customizer for groups (Unverified) | Server | Java; Spring Boot | Java |
| `conf/server.xml` | Standalone Tomcat connector `groups` | Server | Java; Tomcat | Java |
| `bin/setenv.sh` | Agent for Tomcat on JDK 17/21 | Server | Java 17/21; Tomcat | Java |
| `NettyPq.java` | Netty client and server with tcnative | Both | Java; any JDK | Java |
| `AwsClients.java` | AWS SDK v2 CRT client | Client | Java; all compute | Java |
| Zip layout (`function.zip`) | Where the agent sits in the package | Client | Java 8 to 21; Lambda zip | Java |
| `template.yaml` (SAM) | Lambda with `JAVA_TOOL_OPTIONS` | Client | Java; Lambda zip | Java |
| `lambda.yaml` | Plain CloudFormation | Client | Java; Lambda zip | Java |
| `lambda.tf` | Terraform | Client | Java; Lambda zip | Java |
| `Dockerfile.lambda` | Lambda image on java:21 | Client | Java; Lambda image | Java |
| `Dockerfile` (JDK 25.0.5+) | Preferred image, no PQ lines | Both | Java 25; Fargate, ECS, EKS | Java |
| `Dockerfile.jdk21-agent` | JDK 17/21 with the agent | Both | Java 17/21; containers | Java |
| `Dockerfile.distroless-agent` | Distroless image with the agent | Both | Java 21; containers | Java |
| `Dockerfile.static` | Static provider registration | Both | Java 21; containers | Java |
| `taskdef.json` | ECS task definition | Both | Java; ECS, Fargate | Java |
| `ecs.tf` | Terraform task definition | Both | Java; ECS, Fargate | Java |
| `ecs.yaml` | CloudFormation task definition | Both | Java; ECS, Fargate | Java |
| `deployment.yaml` | Kubernetes Deployment | Both | Java; EKS | Java |
| `/etc/systemd/system/orders-java.service` | Service unit | Both | Java; EC2 | Java |
| `orders-java.service.d/pq-tls.conf` | Drop-in that adds the agent | Both | Java 8 to 21; EC2 | Java |
| `pq-tls-ssm.yaml` | SSM document: install kit and drop-in | Infra | Java; EC2 | Java |
| `pq-tls/openssl-pq.cnf` | AL2023 crypto policy plus X25519MLKEM768 | Both | .NET; Lambda, AL2023 images and hosts | .NET |
| `Program.cs` | Kestrel HTTPS server | Server | .NET; containers, EC2 | .NET |
| `appsettings.json` | Kestrel endpoint and protocols | Server | .NET; containers, EC2 | .NET |
| `App.csproj` | Kestrel service project | Server | .NET | .NET |
| `Function.csproj` | Ships the config at `/var/task/pq-tls/` | Client | .NET; Lambda zip | .NET |
| `FunctionAot.csproj` | Native AOT on provided.al2023 | Client | .NET; Lambda custom runtime | .NET |
| `Dockerfile` (Alpine) | PQ with no config | Both | .NET; Fargate, ECS, EKS | .NET |
| `Dockerfile.resolute` | Ubuntu 26.04, PQ with no config | Both | .NET 10; Fargate, ECS, EKS | .NET |
| `Dockerfile.al2023` | AL2023 image with the config file | Both | .NET; Fargate, ECS, EKS | .NET |
| `Dockerfile.lambda` | Lambda container image | Client | .NET; Lambda image | .NET |
| `template.yaml` (SAM) | Zip on managed runtime and AOT | Client | .NET; Lambda | .NET |
| `lambda.cfn.yaml` | Plain CloudFormation | Client | .NET; Lambda | .NET |
| `lambda.tf` | Terraform | Client | .NET; Lambda | .NET |
| `taskdef.json` | ECS task definition | Both | .NET; ECS, Fargate | .NET |
| `ecs.tf` | Terraform task definition | Both | .NET; ECS, Fargate | .NET |
| `ecs.cfn.yaml` | CloudFormation task definition | Both | .NET; ECS, Fargate | .NET |
| `deployment.yaml` | Kubernetes Deployment | Both | .NET; EKS | .NET |
| `/etc/systemd/system/orders-api.service` | Service unit with `OPENSSL_CONF` | Both | .NET; EC2 AL2023 | .NET |
| `ssm-al2023-pq-policy.yaml` | SSM document: `DEFAULT:PQ` on the host | Infra | .NET; EC2 AL2023 | .NET |
| `Enable-PqTls.ps1` | Schannel group order (hybrid first) | Both | .NET; Windows Server 2025, Windows 11 | .NET |
| `ssm-windows-pq.json` | SSM document wrapping the script | Infra | .NET; EC2 Windows | .NET |
| `appsettings.json` (Kafka) + producer setup | Confluent.Kafka (librdkafka bundles OpenSSL) | Client | .NET; all compute | .NET |

## Infrastructure and services

| File | Purpose | Side | Applies to | Tab |
| --- | --- | --- | --- | --- |
| `iac/lb/main.tf` | ALB/NLB listeners with the PQ security policy | Server | ALB, NLB | Load balancers |
| `iac/lb/lb.yaml` | CloudFormation equivalent | Server | ALB, NLB | Load balancers |
| `iac/lb/scp-elb-pq.json` | SCP allowing only PQ ELB policies | Infra | AWS Organizations | Load balancers |
| `iac/lb/k8s-lbc.yaml` | AWS Load Balancer Controller annotations | Server | EKS ingress and services | Load balancers |
| `iac/lb/athena.sql` | Athena DDL and queries over ELB logs | Infra | ALB, NLB logs | Load balancers |
| `iac/edge/main.tf` | CloudFront TLS-details forwarding, API Gateway PQ policy, Transfer Family | Server | CloudFront, API Gateway REST, Transfer Family | Edge and API front doors |
| `iac/edge/edge.yaml` | CloudFormation equivalent, plus Cognito domain | Server | Same, plus Cognito | Edge and API front doors |
| `monitoring/pq-metric-filter.tf` | CloudWatch metric filter on non-PQ CloudTrail calls | Infra | CloudTrail | AWS service endpoints |
| `monitoring/pq-metric-filter.yaml` | CloudFormation equivalent | Infra | CloudTrail | AWS service endpoints |
| `monitoring/pq-eventbridge.tf` | Per-call events for write APIs (untested) | Infra | CloudTrail, EventBridge | AWS service endpoints |
| `athena/cloudtrail_pq.sql` | Athena queries on `tlsDetails.keyExchange` | Infra | CloudTrail | AWS service endpoints |
| `lambda/template.yaml` (SAM) | Credentials extension layer v19+ with the Python PQ config | Client | Lambda | AWS service endpoints |
| `lambda/main.tf` | Terraform equivalent | Client | Lambda | AWS service endpoints |
| `images/awscli/Dockerfile` | Image step with a PQ-capable AWS CLI | Client | Containers, Lambda images | AWS service endpoints |
| `ssm/PQ-UpgradeAwsCliV2.json` | SSM document to upgrade AWS CLI v2 | Client | EC2 Linux | AWS service endpoints |
| `~/.aws/config` | FIPS endpoints (optional) | Client | AWS CLI and SDKs | AWS service endpoints |
| `/etc/squid/squid.conf` | Egress proxy, PQ on both legs | Both | Squid; ECS, EC2 | Network devices and egress |
| `Dockerfile.squid` | Squid image | Both | Squid; ECS | Network devices and egress |
| `squid-entrypoint.sh` | Container entrypoint | Infra | Squid; ECS | Network devices and egress |
| `squid-taskdef.json` | ECS Fargate task definition | Infra | Squid; Fargate | Network devices and egress |
| `/etc/envoy/envoy-egress.yaml` | Envoy egress that upgrades calls to PQ | Both | Envoy; ECS, EKS, EC2 | Network devices and egress |
| `/etc/swanctl/conf.d/pq.conf` | IKEv2 with ML-KEM additional key exchange | Both | strongSwan 6.0.2+; EC2 | Network devices and egress |
| `/etc/strongswan.d/zz-log.conf` | Log the selected proposal | Infra | strongSwan | Network devices and egress |
| `fortigate-ipsec-pq.conf` | IPsec with ML-KEM (not tested) | Both | FortiGate 7.6.5+ | Network devices and egress |
| `f5-pq.tmsh` | PQ client and server SSL profiles | Both | BIG-IP 17.5.1+ | Network devices and egress |
| `netscaler-pq.cli` | Front-end PQ groups | Server | NetScaler 14.1 | Network devices and egress |
| `/etc/openvpn/server/pq.conf` | PQ TLS groups for the control channel | Both | OpenVPN 2.6 on OpenSSL 3.5 | Network devices and egress |
| `/opt/zeek/share/zeek/site/pq-tls.zeek` | Flag non-PQ TLS in `ssl.log` | Infra | Zeek 8 sensor | Network devices and egress |
| `traffic-mirror.tf` | VPC Traffic Mirroring to the sensor | Infra | EC2 Nitro ENIs | Network devices and egress |
| `traffic-mirror.yaml` | CloudFormation equivalent | Infra | EC2 Nitro ENIs | Network devices and egress |
| `user_settings.h` | wolfSSL build with ML-KEM | Client | MCU devices (FreeRTOS, lwIP) | IoT |
| `pqclient.c` | wolfSSL client that offers X25519MLKEM768 | Client | Linux-class devices, wolfSSL 5.9.4 | IoT |
| `transport_wolfSSL.c` addition | coreMQTT transport key share | Client | FreeRTOS devices | IoT |
| `/etc/mosquitto/mosquitto.conf` | MQTT broker TLS | Server | Mosquitto; EC2, ECS, EKS | IoT |
| `/etc/mosquitto/openssl-pq-only.cnf` | PQ-only groups for the broker or a client | Both | Mosquitto on OpenSSL 3.5 | IoT |
| `mosquitto.service.d/pq.conf` | systemd drop-in that sets `OPENSSL_CONF` | Server | Mosquitto; EC2 | IoT |
| `Dockerfile.mosquitto` | Broker image | Server | Mosquitto; ECS, EKS | IoT |
| `crt_mqtt_pq.py` | AWS CRT MQTT client with TLS policy choice | Client | Linux devices, gateways | IoT |
| `Dockerfile.gateway` | Linux gateway with Device SDK v2 | Client | IoT gateways | IoT |
| `values-istiod-pqc.yaml`, `values-ztunnel-pqc.yaml`, `istio-operator-pqc.yaml`, `egress-tls-origination.yaml` | Istio PQ settings and TLS origination | Both | Istio 1.27+; EKS | Service mesh |
| `mesh.hcl`, `mesh.yaml`, `/etc/consul.d/tls.hcl`, systemd drop-in | Consul mesh and agent TLS groups | Both | Consul 2.1+; EKS, ECS, EC2 | Service mesh |
| `Dockerfile` (Envoy sidecar) | Self-managed Envoy sidecar image | Both | Envoy; ECS | Service mesh |
| `ecs-envoy-sidecar.tf` | Task definition with the sidecar | Infra | ECS, Fargate | Service mesh |
| `ecs-envoy-sidecar.yaml` | CloudFormation equivalent | Infra | ECS, Fargate | Service mesh |
| `kyverno-pq-policies.yaml` | Admission checks for istiod, Envoy Gateway, ingress-nginx | Infra | EKS | Service mesh |
| `postgresql.conf` (TLS section) | `ssl_groups` with X25519MLKEM768 | Server | PostgreSQL 18; EC2, EKS | Databases and data services |
| `pg_hba.conf` | Require TLS (`hostssl`) | Server | PostgreSQL | Databases and data services |
| `rds-pg-pq.tf` | RDS and Aurora parameter groups | Server | RDS PostgreSQL, Aurora | Databases and data services |
| `rds-pg-pq.yaml` | CloudFormation equivalent | Server | RDS PostgreSQL, Aurora | Databases and data services |
| `tls-pq.cnf` | MySQL PQ groups and `force_pqc` | Server | MySQL 26.7+ | Databases and data services |
| `90-tls.cnf` | MariaDB TLS groups | Server | MariaDB 13 on OpenSSL 3.5 | Databases and data services |
| `valkey.conf` (TLS section) | Valkey TLS settings | Server | Valkey 8.1+ | Databases and data services |
| `openssl-groups.cnf` | Process-wide groups for daemons without a group option | Server | Any OpenSSL 3.5 daemon | Databases and data services |
| `server.properties` | Kafka TLS listener (Unverified) | Server | Self-managed Kafka | Databases and data services |
| `postgres-pq.yaml` | StatefulSet with PQ config | Server | PostgreSQL; EKS | Databases and data services |
| `valkey-pq` task definition | Valkey with baked config | Server | Valkey; ECS, Fargate | Databases and data services |
| `10-pq-groups.conf` | systemd drop-in with `OPENSSL_CONF` | Server | Valkey; EC2 | Databases and data services |
| `ssm/PQ-SetCryptoPolicy.json` | SSM document: crypto policy `DEFAULT:PQ` | Both | EC2 AL2023, RHEL 9.7+ | Hosts and OS |
| `ssm/pq-policy.tf` | Document, wave association and rollback association | Infra | EC2 fleets | Hosts and OS |
| `ssm/pq-policy.yaml` | CloudFormation equivalent | Infra | EC2 fleets | Hosts and OS |
| `/etc/crypto-policies/policies/modules/PQ-HYBRID.pmod` | Crypto-policy subpolicy | Both | AL2023, RHEL hosts and images | Hosts and OS |
| `user-data-pq.sh` | User data or Image Builder step | Both | EC2 AL2023 AMIs | Hosts and OS |
| `/etc/pki/tls/openssl-pq.cnf` | Per-service override (same as the Lambda kit) | Both | AL2023 hosts | Hosts and OS |
| `myapp.service.d/pq-tls.conf` | systemd drop-in that sets `OPENSSL_CONF` | Both | EC2 | Hosts and OS |
| `/etc/ssh/sshd_config.d/40-pq-kex.conf` | SSH server PQ-only key exchange | Server | Debian, Ubuntu, Alpine hosts | Hosts and OS |
| `/etc/ssh/ssh_config.d/40-pq-kex.conf` | SSH client PQ key exchange | Client | OpenSSH 9.9+ | Hosts and OS |
| `ssm/PQ-WindowsSchannel.json` | SSM document: Schannel group order (not run here) | Both | Windows Server 2025, Windows 11 | Hosts and OS |
| `mkchain.sh` | Build ML-DSA and ECDSA test chains | Infra | OpenSSL 3.5 | Certificates (ML-DSA) |
| `ca.ext` | Certificate extensions for the chains | Infra | OpenSSL 3.5 | Certificates (ML-DSA) |
| `default.conf` | nginx dual-certificate (ML-DSA + ECDSA) server | Server | nginx on OpenSSL 3.5 | Certificates (ML-DSA) |
| `web-ssl.conf` | Apache dual certificate (Unverified with ML-DSA) | Server | Apache httpd | Certificates (ML-DSA) |
| `private-ca-mldsa.tf` | AWS Private CA with ML-DSA keys | Infra | AWS Private CA | Certificates (ML-DSA) |
| `private-ca-mldsa.yaml` | CloudFormation equivalent | Infra | AWS Private CA | Certificates (ML-DSA) |
| `Dockerfile` (trust store) | Client trust store on Debian 13 | Client | Containers | Certificates (ML-DSA) |
| `template.yaml` (SAM excerpt) | Lambda trust store | Client | Lambda | Certificates (ML-DSA) |
| `iac/waf/main.tf` | AWS WAF rules (JA4, TLS signals) | Infra | AWS WAF on CloudFront, ALB, API Gateway | WAF |
| `iac/waf/waf.yaml` | CloudFormation equivalent | Infra | AWS WAF | WAF |
| `tests/run-modsec-pq.sh` | Software WAF test harness | Infra | ModSecurity on nginx | WAF |
| `/etc/nginx/nginx.conf` | nginx server and proxy PQ groups | Both | nginx; containers, EC2 | Web servers and proxies |
| `/usr/local/apache2/conf/httpd.conf` | Apache httpd server and proxy groups | Both | Apache httpd | Web servers and proxies |
| `/usr/local/etc/haproxy/haproxy.cfg` | HAProxy frontend and backend groups | Both | HAProxy | Web servers and proxies |
| `/etc/caddy/Caddyfile` | Caddy TLS curves | Both | Caddy | Web servers and proxies |
| `/etc/traefik/traefik.yml` | Traefik static config | Both | Traefik | Web servers and proxies |
| `/etc/traefik/dynamic.yml` | Traefik TLS options (curve preferences) | Both | Traefik | Web servers and proxies |
| `/etc/envoy/envoy.yaml` | Envoy listener and cluster `ecdh_curves`, TLS 1.3 max upstream | Both | Envoy; also the mesh sidecar | Web servers and proxies |
| `/usr/local/tomcat/conf/server.xml` (JSSE) | Tomcat connector groups | Server | Tomcat on JDK 25 | Web servers and proxies |
| `/usr/local/tomcat/conf/server.xml` (OpenSSL) | Tomcat via tomcat-native | Server | Tomcat with OpenSSL 3.5 | Web servers and proxies |
| `ingress-nginx-values.yaml` | Helm values with `ssl-ecdh-curve` | Server | ingress-nginx; EKS | Web servers and proxies |
| `envoy-gateway-pq.yaml` | ClientTrafficPolicy `ecdhCurves` (not run) | Server | Envoy Gateway; EKS | Web servers and proxies |
| `Dockerfile` (nginx) | nginx image | Both | ECS, Fargate, EKS | Web servers and proxies |
| `ecs-nginx.tf` | Task definition | Infra | ECS, Fargate | Web servers and proxies |
| `ecs-nginx.yaml` | CloudFormation equivalent | Infra | ECS, Fargate | Web servers and proxies |
| `ssm-nginx-pq.tf` | SSM document for nginx on AL2023 | Infra | EC2 AL2023 | Web servers and proxies |
| `ssm-nginx-pq.yaml` | CloudFormation equivalent | Infra | EC2 AL2023 | Web servers and proxies |
| `ci/toolbox/Dockerfile` | CI toolbox whose tools all passed the PQ-only test | Client | CI runners | Mobile, desktop and CLI clients |
| `~/.curlrc` | Pin curl's group order (OpenSSL-backed curl) | Client | Developer machines, CI | Mobile, desktop and CLI clients |
| `~/.ssh/config` | SSH client PQ key exchange | Client | OpenSSH 9.9+ | Mobile, desktop and CLI clients |
| `app/src/main/java/com/example/App.kt` | Bundle Conscrypt as first provider | Client | Android apps | Mobile, desktop and CLI clients |
| `app/build.gradle.kts` (excerpt) | Conscrypt and OkHttp dependencies | Client | Android apps | Mobile, desktop and CLI clients |
| `windows/Enable-PqTls.ps1` | Schannel group order | Client | Windows 11 clients | Mobile, desktop and CLI clients |
| `ci/check-clients.sh` | Posture gate for a CI image | Infra | CI images | Mobile, desktop and CLI clients |

## Enforcement and guardrails

| File | Purpose | Side | Applies to | Tab |
| --- | --- | --- | --- | --- |
| `rules/scp-pq-tls.json` | SCP: PQ ELB policies only, TLS conditions | Infra | AWS Organizations | Enforcement and guardrails |
| `rules/rcp-s3-tls13.json` | Resource control policy: TLS 1.3 to S3 | Infra | S3 | Enforcement and guardrails |
| `rules/config/org-config-rules.yaml` | Organization Config rules (ELB, API Gateway, Lambda) | Infra | AWS Config | Enforcement and guardrails |
| `rules/cfn/pq-tls.guard` | cfn-guard rules for PQ settings | Infra | CloudFormation pipelines | Enforcement and guardrails |
| `rules/cfn/guard-hook.yaml` | CloudFormation Guard Hook | Infra | CloudFormation | Enforcement and guardrails |
| `rules/opa/terraform/pq_tls.rego` | OPA/conftest policy for Terraform plans | Infra | Terraform pipelines | Enforcement and guardrails |
| `rules/opa/terraform/pq_tls_test.rego` | Tests for that policy | Infra | Terraform pipelines | Enforcement and guardrails |
| `rules/checkov/pq_tls_1.yaml` to `pq_tls_4.yaml` | Checkov custom checks | Infra | Terraform, CloudFormation | Enforcement and guardrails |
| `rules/opa/image/openssl_sbom.rego` | SBOM check for OpenSSL 3.5+ | Infra | Container images | Enforcement and guardrails |
| `rules/image/check-go-pq.sh` | Go binary posture check | Infra | Container images | Enforcement and guardrails |
| `rules/image/check-jdk-pq.sh` | JDK version and agent check | Infra | Container images | Enforcement and guardrails |
| `rules/opa/dockerfile/pq_dockerfile.rego` | Dockerfile lint for PQ settings | Infra | Dockerfiles | Enforcement and guardrails |
| `rules/k8s/kyverno-pq-tls-cel.yaml` | Kyverno CEL ValidatingPolicy | Infra | EKS, Kyverno 1.20+ | Enforcement and guardrails |
| `rules/k8s/kyverno-pq-tls.yaml` | Kyverno ClusterPolicy | Infra | EKS, Kyverno 1.19 and earlier | Enforcement and guardrails |
| `rules/k8s/gatekeeper-pq-tls.yaml` | Gatekeeper template and constraint | Infra | EKS | Enforcement and guardrails |
| `rules/runtime/cloudtrail-alarm.yaml` | Alarm on non-PQ CloudTrail calls | Infra | CloudTrail, CloudWatch | Enforcement and guardrails |
| `rules/runtime/cloudtrail-non-pq.sql` | Athena query for non-PQ calls | Infra | CloudTrail | Enforcement and guardrails |
| `rules/runtime/eventbridge-rules.json` | EventBridge rules on policy changes | Infra | EventBridge | Enforcement and guardrails |
| `rules/runtime/elb-logs-athena.sql` | Athena query for non-PQ ELB connections | Infra | ALB, NLB logs | Enforcement and guardrails |
