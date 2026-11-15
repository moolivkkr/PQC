# Runbook by language

Each language tab says, for each component, exactly what to change: the version to upgrade to, the file to ship, the variable to set, and how to check it worked. Every change goes through the normal build, package and release; nothing here is applied by hand.

## Language tabs

| Language | What decides PQ | Status today | Main action |
| --- | --- | --- | --- |
| Go | Go's own `crypto/tls`: toolchain, `go` line in `go.mod`, `GODEBUG`, `CurvePreferences`, FIPS mode | PQ by default with Go 1.24+ and a `go` line of 1.24+; FIPS needs 1.25+ (1.26+ for the SecP hybrids) | Build with Go 1.26, raise the `go` line, drop explicit `CurvePreferences`; fix the AWS SDK's FIPS curve list |
| Python | stdlib `ssl` follows the platform OpenSSL; some wheels bundle their own TLS | Debian 13 and Alpine images PQ; Lambda and AL2023 need the config; grpcio, awscrt, psycopg binary, pyOpenSSL PQ everywhere | Ship `openssl-pq.cnf` on Lambda/AL2023 or use an OpenSSL 3.5 image; shim or upgrade 3.9 to 3.11 on Lambda |
| Node.js | Node's bundled OpenSSL plus the config file it reads | Official 22.20+ and 24.5+ PQ by default (policy floor 24.9); Lambda bootstrap config removes it; 18 and 20 can't | Override the Lambda config with `openssl-pq-node.cnf`; upgrade 18 and 20 |
| Java | The JSSE provider in the JVM | JDK 25.0.5+ PQ by default (JEP 527 backport); 8 to 21 have no ML-KEM | Move to JDK 25.0.5+, or add Bouncy Castle JSSE (kit v2 agent or `java.security`); servers with EC certificates also need `ssl.KeyManagerFactory.algorithm=PKIX`; tcnative or CRT clients are PQ on any JDK |
| .NET | The OS stack: OpenSSL on Linux, Schannel on Windows; no .NET group API | Alpine and Ubuntu 26.04 images PQ; Lambda and AL2023 need the config; Windows opt-in | Pick a PQ base image or ship `openssl-pq.cnf`; set the Schannel group order on Windows |

Every language tab follows the same page template, built for application teams that already run services with their own certificates and TLS settings:

1. **Problem statement:** what goes wrong today in this language, and who controls the handshake.
2. **Versions and native support:** one row per runtime version line, with the TLS stack, PQ client and server defaults per compute type, the group API, FIPS behaviour, the proposed fix and an evidence label; then a short decision guide.
3. **Cases: what to change:** A simple client, B simple server, C existing server certificates in a custom keystore or key files, D custom CA trust, E mutual TLS, F explicit TLS settings that block PQ, G FIPS mode, H libraries with their own TLS stack, I pinning and HSM or KMS keys, J other cases. Each case says who it applies to (with a grep), what happens today, what to change (often nothing), and side effects.
4. **Solution and automation:** inventory, the change per compute type with IaC excerpts, CI guardrails, and canary rollout with rollback.
5. **How to test:** numbered steps with full scripts: posture, a PQ-only and a classical-only test server, a test per case, the in-cloud signal, and the rollback test.
6. **Pitfalls and rollback.**
7. **Full configuration files**, also listed in Configuration file index.

**Existing certificates and keystores:** in every language the keystore, key files and CA bundles stay as they are; only the platform fix applies. The exceptions are listed per language in the Overview's "Existing certificates, keystores and trust stores" table, most importantly the `PKIX` key manager setting for Java servers with EC certificates under Bouncy Castle.

## Components

| Component | Who owns the OS and TLS library | Where the fix lives |
| --- | --- | --- |
| Lambda, managed runtime (zip) | AWS | Files in the deployment package under `/var/task/pq-tls/`; variables in the function's IaC |
| Lambda, container image | You, starting from an AWS base image (`public.ecr.aws/lambda/...`) | Files and `ENV` in the Dockerfile; function variables override image `ENV` |
| Fargate (ECS or EKS) | You (the image) | Base image and Dockerfile; variables in the ECS task definition or pod spec |
| ECS or EKS on EC2 | You (the image); the host OS doesn't affect the container's TLS | Same as Fargate |
| EC2 or other hosts (no containers) | You | OS packages, crypto policy pushed with SSM State Manager, service unit environment |

## Where a variable goes, per component

| Component | How to set `NAME=value` |
| --- | --- |
| Lambda (zip or image) | `Environment.Variables` in CloudFormation or SAM, `environment` in CDK or Terraform `aws_lambda_function` |
| Lambda image, Fargate, EKS, ECS on EC2 | `ENV NAME=value` in the Dockerfile, so every deployment of the image carries it |
| ECS task (override) | `containerDefinitions[].environment` in the task definition |
| EKS pod (override) | `spec.containers[].env` in the pod or Deployment spec |
| EC2 service | `Environment=NAME=value` in the systemd unit, rolled out by SSM or the AMI pipeline |

## Shared files (the pq-tls kit)

| File | Used by | Purpose |
| --- | --- | --- |
| `openssl-pq.cnf` | Python and .NET on Amazon Linux 2023 | Loads the AL2023 crypto policy, adds X25519MLKEM768 first |
| `openssl-pq-node.cnf` | Node.js on Lambda | AWS's Node group list with X25519MLKEM768 added first |
| `pq-tls-agent.jar` (kit v2) plus Bouncy Castle 1.87 jars (`bcprov`, `bctls`, `bcutil`) | Java 8 to 21 | Makes Bouncy Castle JSSE the TLS provider and enables the ML-KEM group; sets the `PKIX` key manager unless the app chose one |
| `pq-tls.security` | Java 8 to 21 servers | One line, `ssl.KeyManagerFactory.algorithm=PKIX`, passed with `-Djava.security.properties=`, for EC server and client certificates under Bouncy Castle |
| `ci/java-pq-check.sh` and each language's lint script | CI | Fails builds on settings that block PQ (pinned groups, TLS 1.2 maximum, hard-coded `SunX509`) |
| `pyshim/sitecustomize.py` plus pyOpenSSL, cryptography and idna (built per Python version) | Python 3.9 to 3.11 on Lambda only | Routes requests and boto3 through pyOpenSSL's newer OpenSSL |
| `pq-tls` layer `wrapper` (`AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper`) | Lambda python3.9+, nodejs22+, java8-21, dotnet8/10 | Applies the right fix per runtime at start: `OPENSSL_CONF` (Python 3.12+, Node 22+, .NET), the shim (Python 3.9-3.11), the agent plus JDK 8 flags (Java). Leaves a function's own settings alone; `PQ_TLS_DISABLE=1` rolls back |
| `pq-egress` Lambda extension (`e2e/lambda/extension/pq-egress/`) | Interim, any Lambda runtime without an in-process fix | Makes the outbound TLS connection with PQ; the function calls it over loopback HTTP (Tested in the e2e suite, not on real AWS) |

The kit is versioned once and pulled in by the shared build template, so a fix to a file reaches every workload on its next release.

## Checking a workload

- **Observed:** CloudTrail `tlsDetails.keyExchange` for its AWS API calls shows `X25519MLKEM768`, and ELB logs show the same for inbound traffic.
- **Test endpoint:** a test server that accepts only X25519MLKEM768 (`openssl s_server -groups X25519MLKEM768 -tls1_3` with OpenSSL 3.5) fails any client that isn't PQ. Each tab's verify step uses it.
