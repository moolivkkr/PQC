# Configuration files

Extracted from each tab's "Full configuration files" section by `build/extract-configs.py`. The document text is the source; re-run the script after editing it.

| File | Label in the document |
| --- | --- |
| `go/go.mod` | `go.mod` (preferred: raise the `go` line) |
| `go/go.variant2.mod` | `go.mod` (alternative: keep an old `go` line, turn PQ on) |
| `go/cmd/client/main.go` | `cmd/client/main.go` (HTTP and AWS SDK client, FIPS-safe) |
| `go/cmd/server/main.go` | `cmd/server/main.go` (HTTPS and gRPC server that logs the group) |
| `go/cmd/lambda/main.go` | `cmd/lambda/main.go` (Lambda handler) |
| `go/Makefile` | `Makefile` (Lambda zip) |
| `go/Dockerfile` | `Dockerfile` (ECS, Fargate, EKS: distroless) |
| `go/Dockerfile.lambda` | `Dockerfile.lambda` (Lambda container image) |
| `go/Dockerfile.fips` | `Dockerfile.fips` (FIPS 140-3 build) |
| `go/template.yaml` | `template.yaml` (SAM, Lambda zip) |
| `go/lambda-cfn.yaml` | `lambda-cfn.yaml` (plain CloudFormation, zip in S3) |
| `go/lambda.tf` | `lambda.tf` (Terraform, zip and image) |
| `go/taskdef.json` | `taskdef.json` (ECS / Fargate) |
| `go/ecs-task.tf` | `ecs-task.tf` (Terraform for the same task definition) |
| `go/deployment.yaml` | `deployment.yaml` (EKS) |
| `go/etc/systemd/system/payments-api.service` | `/etc/systemd/system/payments-api.service` (EC2) |
| `go/go-pq-posture.sh` | `go-pq-posture.sh` (CI gate and host or image scan) |
| `go/go-pq-lint.sh` | `go-pq-lint.sh` (CI check: source, go.mod and IaC settings that block PQ) |
| `go/gen-certs.sh` | `gen-certs.sh` (test PKI: private CA, RSA and EC server certs, SNI certs, client certs, encrypted keys, PKCS#12) |
| `go/pq-servers.sh` | `pq-servers.sh` (the four OpenSSL 3.5 test servers) |
| `go/cases/main.go` | `cases/main.go` (cases C, D, E, F, standard library only; build with a go.mod of `module cases` and the `go` line under test) |
| `go/cases/casei.go` | `cases/casei.go` (case I: pinning and an opaque crypto.Signer key) |
| `go/cases/curve_new.go` | `cases/curve_new.go` (group name on Go 1.25+) |
| `go/cases/curve_old.go` | `cases/curve_old.go` (fallback for Go 1.23 and 1.24) |
| `go/deps/go.mod` | `deps/go.mod` (versions resolved for the library tests) |
| `go/deps/main.go` | `deps/main.go` (cases C (PKCS#12, encrypted PKCS#8) and H (AWS SDK, gRPC, pgx)) |
| `python/pq-tls/openssl-pq.cnf` | `pq-tls/openssl-pq.cnf` (Lambda python3.12+, Lambda images, AL2023 containers and hosts; Tested) |
| `python/pq-tls/pyshim/sitecustomize.py` | `pq-tls/pyshim/sitecustomize.py` (Lambda python3.9 to 3.11 bridge only; Tested on Lambda base images 3.9 and 3.11) |
| `python/template.yaml` | `template.yaml` (AWS SAM, Lambda zip, python3.13) |
| `python/cfn/lambda.yaml` | `cfn/lambda.yaml` (CloudFormation, Lambda zip) |
| `python/terraform/lambda.tf` | `terraform/lambda.tf` (Lambda zip) |
| `python/terraform/lambda-legacy.tf` | `terraform/lambda-legacy.tf` (python3.11 bridge until the upgrade; in CloudFormation or SAM set the same `PYTHONPATH` variable) |
| `python/Dockerfile.lambda` | `Dockerfile.lambda` (Lambda container image) |
| `python/Dockerfile` | `Dockerfile` (Fargate / ECS / EKS, Debian 13 trixie: PQ with no extra setting) |
| `python/Dockerfile.al2023` | `Dockerfile.al2023` (Fargate / ECS / EKS on Amazon Linux 2023) |
| `python/ecs/taskdef.json` | `ecs/taskdef.json` (Fargate) |
| `python/k8s/deployment.yaml` | `k8s/deployment.yaml` (EKS) |
| `python/gunicorn.conf.py` | `gunicorn.conf.py` (gunicorn terminates TLS; Tested on 3.12, 3.13 and 3.15; set_groups applies on 3.15 only) |
| `python/serve_uvicorn.py` | `serve_uvicorn.py` (uvicorn terminates TLS with an explicit group list; Tested on 3.15: PQ-first and PQ-only) |
| `python/etc/systemd/system/orders.service` | `/etc/systemd/system/orders.service` (EC2, AL2023; scope the config to one service) |
| `python/ssm/pq-crypto-policy.yaml` | `ssm/pq-crypto-policy.yaml` (SSM Command document for AL2023 hosts; run from a State Manager association) |
| `python/pq_probe.py` | `pq_probe.py` (posture and live check; run inside the same image, env and user as the service; Tested on 3.15) |
| `python/gunicorn-enc.conf.py` | `gunicorn-enc.conf.py` (gunicorn with an encrypted key; Tested on 3.12, 3.13, AL2023 3.12 + config) |
| `python/p12_to_pem.py` | `p12_to_pem.py` (convert a PKCS#12/PFX at startup; Tested with cryptography 50.0.2: the converted pair served X25519MLKEM768, key file mode 0600) |
| `python/ci/pq-tls-lint.sh` | `ci/pq-tls-lint.sh` (CI guardrail for case F; Tested) |
| `python/pq-harness.sh` | `pq-harness.sh` (PQ-only, classical-only and mTLS test servers; Tested as `srv2.sh` + `mkcerts.sh`) |
| `python/probe-server.sh` | `probe-server.sh` (server-side check; Tested as the probe in `run-v2.sh`) |
| `nodejs/pq-tls/openssl-pq-node.cnf` | `pq-tls/openssl-pq-node.cnf` (Lambda nodejs22/24: AWS's file with the hybrid group added first; Tested) |
| `nodejs/etc/app/openssl-pq-node-system.cnf` | `/etc/app/openssl-pq-node-system.cnf` (distro Node on system OpenSSL 3.5+ when you can't change the host policy; Tested on AL2023 nodejs22) |
| `nodejs/check-lambda-node-conf.sh` | `check-lambda-node-conf.sh` (pipeline check; Tested against nodejs22 and nodejs24 images: "OK: only Groups differs") |
| `nodejs/src/tls-pq.js` | `src/tls-pq.js` (shared TLS options with feature detection; Tested on Node 20, 22, 24) |
| `nodejs/pq-check.js` | `pq-check.js` (posture and live check; exits 1 if the runtime can't do ML-KEM or any target is not PQ; Tested) |
| `nodejs/server.js` | `server.js` (Express on HTTPS; Tested on `node:24-slim`: PQ client got X25519MLKEM768, classical client X25519, TLS 1.2 client connected) |
| `nodejs/template.yaml` | `template.yaml` (SAM, Lambda zip) |
| `nodejs/lambda-cfn.yaml` | `lambda-cfn.yaml` (CloudFormation, Lambda zip) |
| `nodejs/lambda.tf` | `lambda.tf` (Terraform, Lambda zip) |
| `nodejs/Dockerfile.lambda` | `Dockerfile.lambda` (Lambda container image) |
| `nodejs/Dockerfile` | `Dockerfile` (Fargate / ECS / EKS on an official image: nothing PQ-specific) |
| `nodejs/Dockerfile.al2023` | `Dockerfile.al2023` (AL2023 base with the distro Node package; policy step Tested) |
| `nodejs/taskdef.json` | `taskdef.json` (ECS / Fargate; no TLS setting needed) |
| `nodejs/ecs.tf` | `ecs.tf` (Terraform; distro-Node images only need the commented line) |
| `nodejs/ecs-cfn.yaml` | `ecs-cfn.yaml` (CloudFormation) |
| `nodejs/deployment.yaml` | `deployment.yaml` (EKS) |
| `nodejs/etc/systemd/system/orders.service` | `/etc/systemd/system/orders.service` (EC2) |
| `nodejs/pq-node-posture.json` | `pq-node-posture.json` (SSM Command document: reports every running Node process on an instance) |
| `nodejs/ci/check-node-tls.sh` | `ci/check-node-tls.sh` (CI guardrail; Tested against fixtures, ci-check.out) |
| `nodejs/test/gen-certs.sh` | `test/gen-certs.sh` (private CA, RSA/EC server certs, encrypted keys, PFX files, client certs; run inside an OpenSSL 3.5 container with this dir at /w) |
| `nodejs/test/start-ossl.sh` | `test/start-ossl.sh` (the four reference servers: PQ-only, classical, and both with client certs required) |
| `nodejs/test/srv.cjs` | `test/srv.cjs` (server probe for cases C, E (server side) and F) |
| `nodejs/test/cli.cjs` | `test/cli.cjs` (client probe for cases D, E and F) |
| `nodejs/test/pin.cjs` | `test/pin.cjs` (case I: SPKI pinning) |
| `nodejs/test/run-cases.sh` | `test/run-cases.sh` (runs C, D, E and F for one runtime image) |
| `nodejs/test/fn/index.js` | `test/fn/index.js` (Lambda handler for the emulator test) |
| `nodejs/test/run-lambda-rie.sh` | `test/run-lambda-rie.sh` (Lambda nodejs22/24 under the Runtime Interface Emulator with NODE_EXTRA_CA_CERTS and mTLS) |
| `nodejs/test/run-pin.sh` | `test/run-pin.sh` (runs pin.cjs on the four runtimes) |
| `java/pq-tls-agent/src/PqTlsAgent.java` | `pq-tls-agent/src/PqTlsAgent.java` (v2) |
| `java/pq-tls/pq-tls.security` | `pq-tls/pq-tls.security` (new in v2) |
| `java/pq-tls-agent/MANIFEST.MF` | `pq-tls-agent/MANIFEST.MF` (zip, image and EC2 layout: jars next to the agent) |
| `java/pq-tls-agent/MANIFEST-layer.MF` | `pq-tls-agent/MANIFEST-layer.MF` (Lambda layer layout: agent in `/opt/pq-tls`, jars in `/opt/java/lib`) |
| `java/pq-tls-agent/build.sh` | `pq-tls-agent/build.sh` (v2: also builds the layer jar and copies `pq-tls.security`) |
| `java/pq-tls-layer/wrapper` | `pq-tls-layer/wrapper` (v2; only the Java branch changed from the layer's v1 wrapper, see the Python and Node.js tabs for the other branches) |
| `java/pom.xml` | `pom.xml` (excerpt: only the dependencies that matter for PQ; pick the options your service uses) |
| `java/build.gradle.kts` | `build.gradle.kts` (same choices) |
| `java/pq-tls/bc-static.security` | `pq-tls/bc-static.security` (v2: adds the key manager line; load with `-Djava.security.properties=<path>`) |
| `java/src/main/resources/application.yml` | `src/main/resources/application.yml` |
| `java/src/main/java/com/example/PqTomcatGroups.java` | `src/main/java/com/example/PqTomcatGroups.java` (Unverified: Tomcat's `SSLHostConfig.setGroups` was tested; this Spring wiring and the Boot 4 package name were  |
| `java/conf/server.xml` | `conf/server.xml` (connector; `groups` needs Tomcat 11.0.12+ or the matching 10.1/9.0 releases) |
| `java/bin/setenv.sh` | `bin/setenv.sh` (v2) |
| `java/NettyPq.java` | `NettyPq.java` (client and server; the explicit list is optional, the tested default already prefers X25519MLKEM768) |
| `java/AwsClients.java` | `AwsClients.java` (AWS SDK for Java v2 CRT client; PQ by default from 2.35.11) |
| `java/template.yaml` | `template.yaml` (SAM, zip) |
| `java/template-layer.yaml` | `template-layer.yaml` (SAM, layer v2) |
| `java/lambda.yaml` | `lambda.yaml` (plain CloudFormation) |
| `java/lambda.tf` | `lambda.tf` (Terraform; zip, and the layer variant) |
| `java/Dockerfile.lambda` | `Dockerfile.lambda` (Lambda container image, java21 base; for java25 drop the COPY and ENV lines) |
| `java/Dockerfile` | `Dockerfile` (preferred: JDK 25.0.5+, no PQ-specific lines) |
| `java/Dockerfile.jdk21-agent` | `Dockerfile.jdk21-agent` (kit v2, JDK 17/21 until the upgrade) |
| `java/Dockerfile.distroless-agent` | `Dockerfile.distroless-agent` (distroless has no shell; the JVM reads JAVA_TOOL_OPTIONS itself) |
| `java/Dockerfile.static` | `Dockerfile.static` (static provider registration instead of the agent; `bc-static.security` v2 holds the PKIX line) |
| `java/taskdef.json` | `taskdef.json` (ECS / Fargate; only needed if the image does not already set it) |
| `java/ecs.tf` | `ecs.tf` (Terraform) |
| `java/ecs.yaml` | `ecs.yaml` (CloudFormation) |
| `java/deployment.yaml` | `deployment.yaml` (EKS) |
| `java/etc/systemd/system/orders-java.service` | `/etc/systemd/system/orders-java.service` |
| `java/etc/systemd/system/orders-java.service.d/pq-tls.conf` | `/etc/systemd/system/orders-java.service.d/pq-tls.conf` (drop-in, when you cannot edit the unit) |
| `java/pq-tls-ssm.yaml` | `pq-tls-ssm.yaml` (SSM Command document: install kit v2 from S3 and add the drop-in) |
| `java/ci/java-pq-check.sh` | `ci/java-pq-check.sh` |
| `java/V2Test.java` | `V2Test.java` (server with a keystore and optional client auth, client, embedded Tomcat) |
| `java/run-v2.sh` | `run-v2.sh` (one JDK image and one kit mode per run; needs Docker, `debian:trixie-slim` for OpenSSL 3.5 and the keystores from `build-v2.sh`) |
| `java/build-v2.sh` | `build-v2.sh` (builds kit v2 and the test classes, makes the client and rogue certs) |
| `dotnet/pq-tls/openssl-pq.cnf` | **`pq-tls/openssl-pq.cnf`** (Amazon Linux 2023 family only: Lambda dotnet8/dotnet10, provided.al2023, AL2023 containers and EC2; tested). It includes AL2023's c |
| `dotnet/Program.cs` | **`Program.cs`** (Kestrel server; tested on every image in the status matrix) |
| `dotnet/appsettings.json` | **`appsettings.json`** (tested) |
| `dotnet/App.csproj` | **`App.csproj`** (Kestrel service; tested) |
| `dotnet/Function.csproj` | **`Function.csproj`** (Lambda zip on the dotnet8 or dotnet10 managed runtime; puts the config file at `/var/task/pq-tls/openssl-pq.cnf`) |
| `dotnet/FunctionAot.csproj` | **`FunctionAot.csproj`** (Native AOT on `provided.al2023`; an AOT binary was tested in the `provided:al2023` image) |
| `dotnet/Dockerfile` | **`Dockerfile`** (Fargate/ECS/EKS on Alpine: PQ with no config; tested with `aspnet:8.0-alpine` and `aspnet:10.0-alpine`) |
| `dotnet/Dockerfile.resolute` | **`Dockerfile.resolute`** (glibc alternative: Ubuntu 26.04, PQ with no config; tested with `aspnet:10.0-resolute` and `10.0-resolute-chiseled`) |
| `dotnet/Dockerfile.al2023` | **`Dockerfile.al2023`** (glibc on Amazon Linux 2023 with the config file; tested) |
| `dotnet/Dockerfile.lambda` | **`Dockerfile.lambda`** (Lambda container image; tested with `public.ecr.aws/lambda/dotnet:8` and `:10`) |
| `dotnet/template.yaml` | **`template.yaml`** (SAM: zip on the managed runtime, and Native AOT) |
| `dotnet/lambda.cfn.yaml` | **`lambda.cfn.yaml`** (plain CloudFormation) |
| `dotnet/lambda.tf` | **`lambda.tf`** (Terraform) |
| `dotnet/taskdef.json` | **`taskdef.json`** (ECS/Fargate; the env var is only needed for the AL2023 image and can be left out for Alpine or resolute) |
| `dotnet/ecs.tf` | **`ecs.tf`** (Terraform for the same task definition) |
| `dotnet/ecs.cfn.yaml` | **`ecs.cfn.yaml`** (CloudFormation for the same task definition) |
| `dotnet/deployment.yaml` | **`deployment.yaml`** (EKS) |
| `dotnet/etc/systemd/system/orders-api.service` | **`/etc/systemd/system/orders-api.service`** (EC2 Amazon Linux 2023, one service; the same `OPENSSL_CONF` setting was tested in an AL2023 container) |
| `dotnet/ssm-al2023-pq-policy.yaml` | **`ssm-al2023-pq-policy.yaml`** (SSM Command document, whole host on EC2 AL2023.12+; route [Documented](https://docs.aws.amazon.com/linux/al2023/ug/crypto-polic |
| `dotnet/Enable-PqTls.ps1` | **`Enable-PqTls.ps1`** (Windows Server 2025 / Windows 11 24H2+, Schannel; Documented by Microsoft, not run here) |
| `dotnet/ssm-windows-pq.json` | **`ssm-windows-pq.json`** (SSM Command document wrapping the script; `exit 3010` asks SSM to reboot the instance) |
| `dotnet/appsettings.variant2.json` | **`appsettings.json` (Kafka section) and producer setup** (Confluent.Kafka; `ssl.curves.list` is optional because librdkafka 2.14.2+ is PQ by default; tested) |
| `dotnet/tools/check-dotnet-pq.sh` | **`tools/check-dotnet-pq.sh`** (CI guardrail; tested on fixtures: bad tree exit 1 with 4 findings, good tree exit 0) |
| `dotnet/.github/workflows/pq-check.yml` | **`.github/workflows/pq-check.yml`** (GitHub Actions wrapper; not run here) |
| `dotnet/pq-test/build2.sh` | **`pq-test/build2.sh`** (creates the private CA, EC and RSA server certs, client cert (PFX, PEM, encrypted PEM) and builds the probes; tested) |
| `dotnet/pq-test/kserver/Program.cs` | **`pq-test/kserver/Program.cs`** (Kestrel probe for cases C, E, F; tested) |
| `dotnet/pq-test/kserver/kserver.csproj` | **`pq-test/kserver/kserver.csproj`** (tested) |
| `dotnet/pq-test/kclient/Program.cs` | **`pq-test/kclient/Program.cs`** (HttpClient probe for cases D, E, F; tested) |
| `dotnet/pq-test/kclient/kclient.csproj` | **`pq-test/kclient/kclient.csproj`** (tested) |
| `dotnet/pq-test/client-cases.sh` | **`pq-test/client-cases.sh`** (runs inside each .NET image; tested) |
| `dotnet/pq-test/run-cases.sh` | **`pq-test/run-cases.sh`** (full matrix: harness servers, client cases, Kestrel cases; tested) |
| `dotnet/pq-test/run-f3.sh` | **`pq-test/run-f3.sh`** (TLS 1.2 + EC certificate follow-up; tested) |
| `enforcement/rules/scp-pq-tls.json` | `rules/scp-pq-tls.json` |
| `enforcement/rules/rcp-s3-tls13.json` | `rules/rcp-s3-tls13.json` |
| `enforcement/rules/config/org-config-rules.yaml` | `rules/config/org-config-rules.yaml` |
| `enforcement/rules/cfn/pq-tls.guard` | `rules/cfn/pq-tls.guard` |
| `enforcement/rules/cfn/guard-hook.yaml` | `rules/cfn/guard-hook.yaml` |
| `enforcement/rules/opa/terraform/pq_tls.rego` | `rules/opa/terraform/pq_tls.rego` |
| `enforcement/rules/opa/terraform/pq_tls_test.rego` | `rules/opa/terraform/pq_tls_test.rego` |
| `enforcement/rules/checkov/pq_tls_1.yaml` | `rules/checkov/pq_tls_1.yaml` |
| `enforcement/rules/checkov/pq_tls_2.yaml` | `rules/checkov/pq_tls_2.yaml` |
| `enforcement/rules/checkov/pq_tls_3.yaml` | `rules/checkov/pq_tls_3.yaml` |
| `enforcement/rules/checkov/pq_tls_4.yaml` | `rules/checkov/pq_tls_4.yaml` |
| `enforcement/rules/opa/image/openssl_sbom.rego` | `rules/opa/image/openssl_sbom.rego` |
| `enforcement/rules/image/check-go-pq.sh` | `rules/image/check-go-pq.sh` |
| `enforcement/rules/image/check-jdk-pq.sh` | `rules/image/check-jdk-pq.sh` |
| `enforcement/rules/opa/dockerfile/pq_dockerfile.rego` | `rules/opa/dockerfile/pq_dockerfile.rego` |
| `enforcement/rules/k8s/kyverno-pq-tls-cel.yaml` | `rules/k8s/kyverno-pq-tls-cel.yaml` |
| `enforcement/rules/k8s/kyverno-pq-tls.yaml` | `rules/k8s/kyverno-pq-tls.yaml` (Kyverno 1.19 and earlier) |
| `enforcement/rules/k8s/gatekeeper-pq-tls.yaml` | `rules/k8s/gatekeeper-pq-tls.yaml` |
| `enforcement/rules/runtime/cloudtrail-alarm.yaml` | `rules/runtime/cloudtrail-alarm.yaml` |
| `enforcement/rules/runtime/cloudtrail-non-pq.sql` | `rules/runtime/cloudtrail-non-pq.sql` |
| `enforcement/rules/runtime/eventbridge-rules.json` | `rules/runtime/eventbridge-rules.json` |
| `enforcement/rules/runtime/elb-logs-athena.sql` | `rules/runtime/elb-logs-athena.sql` |
| `aws-service-endpoints/monitoring/pq-metric-filter.tf` | monitoring/pq-metric-filter.tf |
| `aws-service-endpoints/monitoring/pq-metric-filter.yaml` | monitoring/pq-metric-filter.yaml (CloudFormation) |
| `aws-service-endpoints/monitoring/pq-eventbridge.tf` | monitoring/pq-eventbridge.tf (per-call events for write APIs; see the read-only caveat above; untested) |
| `aws-service-endpoints/athena/cloudtrail_pq.sql` | athena/cloudtrail_pq.sql |
| `aws-service-endpoints/lambda/template.yaml` | lambda/template.yaml (SAM: extension layer ≥ v19 plus the Python PQ conf; look up the layer ARN for your Region in the extension docs) |
| `aws-service-endpoints/lambda/main.tf` | lambda/main.tf (Terraform equivalent) |
| `aws-service-endpoints/images/awscli/Dockerfile` | images/awscli/Dockerfile (container or Lambda image step that needs the CLI; amazon/aws-cli 2.40.3 is the Tested version) |
| `aws-service-endpoints/ssm/PQ-UpgradeAwsCliV2.json` | ssm/PQ-UpgradeAwsCliV2.json (SSM Command document for EC2 Linux) |
| `aws-service-endpoints/home/.aws/config` | ~/.aws/config (FIPS endpoints, optional) |
| `certificates-ml-dsa/mkchain.sh` | mkchain.sh (OpenSSL 3.5: ML-DSA and ECDSA chains, Tested) |
| `certificates-ml-dsa/ca.ext` | ca.ext |
| `certificates-ml-dsa/openssl-pq-mldsa.cnf` | openssl-pq-mldsa.cnf (AL2023: ML-KEM groups and ML-DSA signature algorithms, Tested) |
| `certificates-ml-dsa/default.conf` | default.conf (nginx dual-certificate server, Tested) |
| `certificates-ml-dsa/web-ssl.conf` | web-ssl.conf (Apache httpd; Unverified with ML-DSA) |
| `certificates-ml-dsa/private-ca-mldsa.tf` | private-ca-mldsa.tf (Terraform; provider acceptance of ML_DSA values Unverified) |
| `certificates-ml-dsa/private-ca-mldsa.yaml` | private-ca-mldsa.yaml (CloudFormation; schema acceptance of ML_DSA values Unverified) |
| `certificates-ml-dsa/Dockerfile` | Dockerfile (client trust store, Debian 13) |
| `certificates-ml-dsa/template.yaml` | template.yaml (SAM excerpt: Lambda trust) |
| `databases-and-data-services/postgresql.conf` | postgresql.conf (TLS section) |
| `databases-and-data-services/pg_hba.conf` | pg_hba.conf |
| `databases-and-data-services/rds-pg-pq.tf` | rds-pg-pq.tf (Terraform: RDS instance and Aurora cluster parameter groups) |
| `databases-and-data-services/rds-pg-pq.yaml` | rds-pg-pq.yaml (CloudFormation) |
| `databases-and-data-services/tls-pq.cnf` | tls-pq.cnf (MySQL 26.x) |
| `databases-and-data-services/90-tls.cnf` | 90-tls.cnf (MariaDB 13 on OpenSSL 3.5) |
| `databases-and-data-services/valkey.conf` | valkey.conf (TLS section) |
| `databases-and-data-services/openssl-groups.cnf` | openssl-groups.cnf (process-wide groups for daemons without a group option) |
| `databases-and-data-services/server.properties` | server.properties (Kafka TLS listener; Unverified) |
| `databases-and-data-services/postgres-pq.yaml` | postgres-pq.yaml (EKS StatefulSet) |
| `databases-and-data-services/valkey-pq` | valkey-pq task definition (ECS/Fargate) |
| `databases-and-data-services/valkey.variant2.conf` | Bake valkey.conf, openssl-groups.cnf and the certificates into the image and pin it by digest. |
| `edge-and-api-front-doors/iac/edge/main.tf` | iac/edge/main.tf |
| `edge-and-api-front-doors/iac/edge/edge.yaml` | iac/edge/edge.yaml (CloudFormation) |
| `hosts-and-os/ssm/PQ-SetCryptoPolicy.json` | ssm/PQ-SetCryptoPolicy.json (SSM Command document, AL2023 and RHEL 9.7+) |
| `hosts-and-os/ssm/pq-policy.tf` | ssm/pq-policy.tf (Terraform: document, a wave association and a rollback association) |
| `hosts-and-os/ssm/pq-policy.yaml` | ssm/pq-policy.yaml (CloudFormation equivalent) |
| `hosts-and-os/etc/crypto-policies/policies/modules/PQ-HYBRID.pmod` | /etc/crypto-policies/policies/modules/PQ-HYBRID.pmod |
| `hosts-and-os/user-data-pq.sh` | user-data-pq.sh (EC2 user data or Image Builder step for AL2023 AMIs) |
| `hosts-and-os/etc/pki/tls/openssl-pq.cnf` | /etc/pki/tls/openssl-pq.cnf (per-service override; same file as the Lambda kit) |
| `hosts-and-os/etc/systemd/system/myapp.service.d/pq-tls.conf` | /etc/systemd/system/myapp.service.d/pq-tls.conf |
| `hosts-and-os/etc/ssh/sshd_config.d/40-pq-kex.conf` | /etc/ssh/sshd_config.d/40-pq-kex.conf (Debian/Ubuntu/Alpine servers that must refuse classical SSH; leave out on AL2023 and RHEL) |
| `hosts-and-os/etc/ssh/ssh_config.d/40-pq-kex.conf` | /etc/ssh/ssh_config.d/40-pq-kex.conf (clients with OpenSSH ≥ 9.9) |
| `hosts-and-os/ssm/PQ-WindowsSchannel.json` | ssm/PQ-WindowsSchannel.json (SSM Command document, Windows Server 2025 / Windows 11; not run here) |
| `iot/user_settings.h` | user_settings.h (wolfSSL on an MCU. The PQ defines are from wolfSSL's examples/configs/user_settings_pq.h; the platform lines are a typical FreeRTOS/lwIP client |
| `iot/pqclient.c` | pqclient.c (Tested, wolfSSL 5.9.4 on Alpine 3.24 against OpenSSL 3.5 servers. Build: cc pqclient.c -lwolfssl -o pqclient) |
| `iot/transport_wolfSSL.c` | transport_wolfSSL.c addition (FreeRTOS coreMQTT, in TLS_FreeRTOS_Connect() after wolfSSL_new. Uses the same API calls as pqclient.c, but wasn't built in FreeRTO |
| `iot/etc/mosquitto/mosquitto.conf` | /etc/mosquitto/mosquitto.conf (Tested, Mosquitto 2.0.21 / OpenSSL 3.5.7; complete broker config) |
| `iot/etc/mosquitto/openssl-pq-only.cnf` | /etc/mosquitto/openssl-pq-only.cnf (Tested; enforces PQ for the broker, or for a client process) |
| `iot/etc/systemd/system/mosquitto.service.d/pq.conf` | /etc/systemd/system/mosquitto.service.d/pq.conf (EC2 broker; enforces PQ. The OPENSSL_CONF mechanism was Tested; the systemd unit wasn't) |
| `iot/Dockerfile.mosquitto` | Dockerfile.mosquitto (ECS/EKS broker; not deployed) |
| `iot/crt_mqtt_pq.py` | crt_mqtt_pq.py (Tested, awscrt 0.36.1 / awsiotsdk 1.31.0. Usage: python crt_mqtt_pq.py HOST PORT CA CERT KEY [PQ_DEFAULT/DEFAULT/TLSv1_2_2025_07]) |
| `iot/Dockerfile.gateway` | Dockerfile.gateway (Linux gateway with Device SDK v2 and Mosquitto clients on OpenSSL 3.5; the image and package versions are the tested ones, but the Dockerfil |
| `load-balancers/iac/lb/main.tf` | iac/lb/main.tf |
| `load-balancers/iac/lb/lb.yaml` | iac/lb/lb.yaml (CloudFormation) |
| `load-balancers/iac/lb/scp-elb-pq.json` | iac/lb/scp-elb-pq.json |
| `load-balancers/iac/lb/k8s-lbc.yaml` | iac/lb/k8s-lbc.yaml (AWS Load Balancer Controller) |
| `load-balancers/iac/lb/athena.sql` | iac/lb/athena.sql (DDL and queries Q1 to Q5) |
| `mobile-desktop-and-cli-clients/ci/toolbox/Dockerfile` | ci/toolbox/Dockerfile (PQ-capable CI toolbox; every tool here passed the PQ-only test) |
| `mobile-desktop-and-cli-clients/home/.curlrc` | ~/.curlrc (pin the group order; optional, OpenSSL-backed curl only) |
| `mobile-desktop-and-cli-clients/home/.ssh/config` | ~/.ssh/config (OpenSSH ≥ 9.9 clients) |
| `mobile-desktop-and-cli-clients/app/src/main/java/com/example/App.kt` | app/src/main/java/com/example/App.kt (Android: bundle Conscrypt as the first provider) |
| `mobile-desktop-and-cli-clients/app/build.gradle.kts` | app/build.gradle.kts (excerpt; OkHttp version is an example) |
| `mobile-desktop-and-cli-clients/windows/Enable-PqTls.ps1` | windows/Enable-PqTls.ps1 (Windows 11 client, elevated) |
| `mobile-desktop-and-cli-clients/ci/check-clients.sh` | ci/check-clients.sh (posture gate for a CI image) |
| `network-devices-and-egress/etc/squid/squid.conf` | /etc/squid/squid.conf (Tested, Squid 6.13 / OpenSSL 3.5.7; the localnet ranges were narrowed after the test) |
| `network-devices-and-egress/Dockerfile.squid` | Dockerfile.squid (not deployed; uses the tested base image) |
| `network-devices-and-egress/squid-entrypoint.sh` | squid-entrypoint.sh (not deployed) |
| `network-devices-and-egress/squid-taskdef.json` | squid-taskdef.json (ECS Fargate; not deployed) |
| `network-devices-and-egress/etc/envoy/envoy-egress.yaml` | /etc/envoy/envoy-egress.yaml (Tested, Envoy 1.40.2; change the cluster address, SNI and SAN to your partner host) |
| `network-devices-and-egress/etc/swanctl/conf.d/pq.conf` | /etc/swanctl/conf.d/pq.conf (Tested, strongSwan 6.0.7 / OpenSSL 3.5.9; replace LOCAL and REMOTE on each peer, and use certificates instead of the lab PSK in pro |
| `network-devices-and-egress/etc/strongswan.d/zz-log.conf` | /etc/strongswan.d/zz-log.conf (logs the selected proposal, including KE1_ML_KEM_768) |
| `network-devices-and-egress/fortigate-ipsec-pq.conf` | fortigate-ipsec-pq.conf (FortiOS 7.6.5+ CLI. The addke1 and childless-ike lines are from the Fortinet guide; interface, proposal and peer lines are placeholders |
| `network-devices-and-egress/f5-pq.tmsh` | f5-pq.tmsh (BIG-IP 17.5.1+, TLS 1.3 only. Steps 1–3 are from the F5 guide; the server-ssl line is our inference from the documented GUI step) |
| `network-devices-and-egress/netscaler-pq.cli` | netscaler-pq.cli (NetScaler 14.1, front end only. Only the bind ssl profile … -eccCurveName lines are from the NetScaler page; check the profile setup lines aga |
| `network-devices-and-egress/etc/openvpn/server/pq.conf` | /etc/openvpn/server/pq.conf (PQ lines) (OpenVPN 2.6 linked to OpenSSL 3.5+ on both ends; Documented in the 2.6 manual and the vendor tutorial; add to your exist |
| `network-devices-and-egress/opt/zeek/share/zeek/site/pq-tls.zeek` | /opt/zeek/share/zeek/site/pq-tls.zeek (Tested, Zeek 8.0.10; add @load ./pq-tls to local.zeek) |
| `network-devices-and-egress/traffic-mirror.tf` | traffic-mirror.tf (Terraform; not deployed. Mirrored packets arrive at the sensor as VXLAN on UDP 4789, so allow that in the sensor's security group) |
| `network-devices-and-egress/traffic-mirror.yaml` | traffic-mirror.yaml (CloudFormation; not deployed) |
| `service-mesh/values-istiod-pqc.yaml` | values-istiod-pqc.yaml, values-ztunnel-pqc.yaml, istio-operator-pqc.yaml, egress-tls-origination.yaml (Istio) |
| `service-mesh/mesh.hcl` | mesh.hcl, mesh.yaml, /etc/consul.d/tls.hcl, systemd drop-in (Consul) |
| `service-mesh/Dockerfile` | Dockerfile (self-managed Envoy sidecar for ECS; envoy.yaml is in the Web servers tab) |
| `service-mesh/ecs-envoy-sidecar.tf` | ecs-envoy-sidecar.tf (Terraform) |
| `service-mesh/ecs-envoy-sidecar.yaml` | ecs-envoy-sidecar.yaml (CloudFormation) |
| `service-mesh/kyverno-pq-policies.yaml` | kyverno-pq-policies.yaml (and the test resources in kyverno-test-resources.yaml under the work dir) |
| `waf/iac/waf/main.tf` | iac/waf/main.tf |
| `waf/iac/waf/waf.yaml` | iac/waf/waf.yaml (CloudFormation) |
| `waf/tests/run-modsec-pq.sh` | tests/run-modsec-pq.sh (the software-WAF test; needs Docker) |
| `web-servers-and-proxies/etc/nginx/nginx.conf` | /etc/nginx/nginx.conf |
| `web-servers-and-proxies/usr/local/apache2/conf/httpd.conf` | /usr/local/apache2/conf/httpd.conf (official image; on AL2023 use ServerRoot "/etc/httpd", User apache, Group apache, DocumentRoot /var/www/html, and drop the m |
| `web-servers-and-proxies/usr/local/etc/haproxy/haproxy.cfg` | /usr/local/etc/haproxy/haproxy.cfg |
| `web-servers-and-proxies/etc/caddy/Caddyfile` | /etc/caddy/Caddyfile |
| `web-servers-and-proxies/etc/traefik/traefik.yml` | /etc/traefik/traefik.yml (static) |
| `web-servers-and-proxies/etc/traefik/dynamic.yml` | /etc/traefik/dynamic.yml (file provider) |
| `web-servers-and-proxies/etc/envoy/envoy.yaml` | /etc/envoy/envoy.yaml (also the sidecar config for the Service mesh tab's ECS example) |
| `web-servers-and-proxies/usr/local/tomcat/conf/server.xml` | /usr/local/tomcat/conf/server.xml (JSSE connector) |
| `web-servers-and-proxies/usr/local/tomcat/conf/server.variant2.xml` | /usr/local/tomcat/conf/server.xml (OpenSSL implementation via tomcat-native) |
| `web-servers-and-proxies/ingress-nginx-values.yaml` | ingress-nginx-values.yaml (Helm) |
| `web-servers-and-proxies/envoy-gateway-pq.yaml` | envoy-gateway-pq.yaml (field names from the v1.10 API reference; not run here) |
| `web-servers-and-proxies/Dockerfile` | Dockerfile (nginx for ECS, Fargate, EKS) |
| `web-servers-and-proxies/ecs-nginx.tf` | ecs-nginx.tf (Terraform) |
| `web-servers-and-proxies/ecs-nginx.yaml` | ecs-nginx.yaml (CloudFormation) |
| `web-servers-and-proxies/ssm-nginx-pq.tf` | ssm-nginx-pq.tf (Terraform; EC2 on AL2023, run with State Manager or Run Command) |
| `web-servers-and-proxies/ssm-nginx-pq.yaml` | ssm-nginx-pq.yaml (CloudFormation) |
