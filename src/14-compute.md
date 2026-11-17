# Solutions by compute type

The language and its version decide **whether** a connection can be PQ. The compute type decides **who owns the TLS library, where the fix lives, how it ships and how we see the result**. This chapter has one section per compute type. Each gives the per-language fix in one line and links to the language chapter for the detail, cases and full files.

| Compute type | Who owns the OS and TLS library | Where the fix lives | How we see it | e2e client cases (all pass) |
| --- | --- | --- | --- | --- |
| [AWS Lambda](#ch-14-compute--aws-lambda-zip-and-container-image) | AWS (zip); you, from an AWS base image (container image) | Files in the package under `/var/task/pq-tls/` and function variables; or the `pq-tls` layer | CloudTrail for AWS APIs; application logs | 250 |
| [Amazon ECS on AWS Fargate](#ch-14-compute--amazon-ecs-on-aws-fargate) | You (the image) | Base image and Dockerfile; task definition variables | CloudTrail; application logs; an egress proxy | 109, plus 27 load balancer target cases |
| [Amazon ECS on EC2 and Amazon EKS](#ch-14-compute--amazon-ecs-on-ec2-and-amazon-eks) | You (the image); the node's OS does not affect the container's TLS | As for Fargate; pod spec for EKS | As for Fargate, plus Zeek on mirrored node ENIs | 24, plus 5 load balancer target cases |
| [Amazon EC2 hosts](#ch-14-compute--amazon-ec2-hosts) | You (the AMI and OS packages) | OS packages, crypto policy via SSM, the service's systemd unit | CloudTrail; Zeek; SSM Inventory | 54 |

e2e = the LocalStack end-to-end suite, run r1117041043 (2026-11-16): 437 client cases and 32 load balancer target cases, 471 of 471 passed including the two detection checks. "Pass" means the observed behaviour matched the documented expectation, which for a baseline case is "classical". Per-language counts are in Appendix A.

## The shared kit

Every fix is one of a few files or variables, versioned once in the `pq-tls` kit and pulled in by the shared build template, so a workload picks it up on its next release.

| File or variable | Used by | Purpose | Full file |
| --- | --- | --- | --- |
| `openssl-pq.cnf` + `OPENSSL_CONF` | Python, .NET (and distro Node) on Amazon Linux 2023 | Keeps the AL2023 crypto policy, puts X25519MLKEM768 first | [configs/python/pq-tls/openssl-pq.cnf](REPO/configs/python/pq-tls/openssl-pq.cnf) |
| `openssl-pq-node.cnf` + `OPENSSL_CONF` | Node.js 22 and 24 on Lambda | AWS's Node group list with X25519MLKEM768 added first | [configs/nodejs](REPO/configs/nodejs) |
| `pq-tls-agent.jar` (kit v2) + Bouncy Castle 1.87 + `JAVA_TOOL_OPTIONS` | Java 8 to 21 | Bouncy Castle JSSE as the TLS provider with ML-KEM; `PKIX` key manager for EC server certificates | [kit/java-v2](REPO/kit/java-v2) |
| `pyshim/sitecustomize.py` + `PYTHONPATH` | Python 3.9 to 3.11 on Lambda only | Routes requests and boto3 through pyOpenSSL's OpenSSL 3.5 (bridge) | [configs/python/pq-tls/pyshim/sitecustomize.py](REPO/configs/python/pq-tls/pyshim/sitecustomize.py) |
| `GODEBUG=tlsmlkem=1` | Go modules with a `go` line below 1.24 | Turns ML-KEM on without a `go.mod` change | [Go](#ch-03-go) |
| `pq-tls` layer, `AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper` | Lambda python3.9+, nodejs22+, java8 to 21, dotnet8 and 10 | Applies the right fix per runtime at start; `PQ_TLS_DISABLE=1` rolls back | [e2e/build/layers.sh](REPO/e2e/build/layers.sh) |
| `pq-egress` Lambda extension | Interim, any Lambda runtime with no in-process fix | Makes the outbound TLS connection with PQ; the function calls it over loopback HTTP | [e2e/lambda/extension/pq-egress](REPO/e2e/lambda/extension/pq-egress) |

**Where a variable goes:**

| Component | How to set `NAME=value` |
| --- | --- |
| Lambda (zip or image) | `Environment.Variables` in CloudFormation or SAM; `environment` in CDK or Terraform `aws_lambda_function` |
| Lambda image, Fargate, EKS, ECS on EC2 | `ENV NAME=value` in the Dockerfile, so every deployment of the image carries it |
| ECS task (override) | `containerDefinitions[].environment` in the task definition |
| EKS pod (override) | `spec.containers[].env` in the Deployment or pod spec |
| EC2 service | `Environment=NAME=value` in the systemd unit, rolled out by SSM or the AMI pipeline |

## AWS Lambda (zip and container image)

**What decides PQ.** On a zip function AWS owns the OS and the language runtime, so the fix is a file, agent or shim shipped in the package plus a variable. Python, Node.js 22+ and .NET runtimes on Amazon Linux 2023 have OpenSSL 3.5 but negotiate classical X25519, because the AL2023 crypto policy (Python, .NET) or the Lambda bootstrap's own config file (Node.js) leaves ML-KEM out. A container image function built from an AWS base image (`public.ecr.aws/lambda/...`) behaves the same; function variables override image `ENV`.

| Language and runtime | PQ today | Fix | Detail |
| --- | --- | --- | --- |
| Python 3.12, 3.13, 3.14 | No | Ship `openssl-pq.cnf`, set `OPENSSL_CONF=/var/task/pq-tls/openssl-pq.cnf` | [Python](#ch-04-python) |
| Python 3.9, 3.10, 3.11 (Amazon Linux 2, OpenSSL 1.1.1) | No | Upgrade to 3.12+. Bridge: the shim (requests and boto3 only) or the `pq-tls` layer | [Python](#ch-04-python) |
| Python libraries with bundled TLS (grpcio, awscrt, psycopg binary, pyOpenSSL) | Yes, on every runtime | Nothing beyond a current wheel | [Python](#ch-04-python) |
| Node.js 22.x, 24.x | No (the bootstrap config removes ML-KEM) | Ship `openssl-pq-node.cnf`, set `OPENSSL_CONF` to it | [Node.js](#ch-05-nodejs) |
| Node.js 18.x, 20.x | No, and no setting helps (OpenSSL 3.1 and 3.2) | Upgrade; interim, the `pq-egress` extension | [Node.js](#ch-05-nodejs) |
| Java 8, 11, 17, 21 | No | Kit v2 agent: `JAVA_TOOL_OPTIONS=-javaagent:/var/task/pq-tls/pq-tls-agent.jar` (the layer adds the Java 8 flags) | [Java](#ch-06-java) |
| Java 25 | Yes (25.0.5+) | Nothing | [Java](#ch-06-java) |
| .NET 8, 10 | No | Ship `openssl-pq.cnf`, set `OPENSSL_CONF` | [.NET](#ch-07-dotnet) |
| Go on `provided.al2023` or `provided.al2` | Yes with Go 1.24+ and a `go` line of 1.24+ | Rebuild with Go 1.26 and raise the `go` line; or `GODEBUG=tlsmlkem=1` | [Go](#ch-03-go) |

**Three ways to ship it**, in order of preference:

1. **Bundle in the package** through the shared build template: files under `/var/task/pq-tls/`, variables in the function's IaC. Avoids Lambda's five-layer limit and keeps the fix versioned with the function.
2. **The `pq-tls` layer** with `AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper`: one layer for every runtime; it leaves a function's own settings alone and `PQ_TLS_DISABLE=1` rolls it back (Tested in e2e on every supported runtime).
3. **The `pq-egress` extension**, interim, for runtimes with no in-process fix (Node.js 18 and 20) or functions that cannot be rebuilt soon. The function sends plain HTTP to `http://127.0.0.1:2779/<route>/<path>` and the extension makes the TLS connection with X25519MLKEM768. Tested in e2e on every Lambda runtime (28 cases); not tested for AWS SDK calls (SigV4 signs the host name) or on real AWS.

The main change, a SAM function with the bundled config (full templates per language: [configs/python/template.yaml](REPO/configs/python/template.yaml), [configs/go/template.yaml](REPO/configs/go/template.yaml)):

```
Resources:
  Fn:
    Type: AWS::Serverless::Function
    Properties:
      Runtime: python3.13
      Environment:
        Variables:
          OPENSSL_CONF: /var/task/pq-tls/openssl-pq.cnf
```

**Detection.** CloudTrail `keyExchange` for calls to KMS, STS, IAM, Secrets Manager and ACM; the function's own handshake log for everything else. Lambda cannot be packet-mirrored.

**Deadline.** AWS blocks updates to nodejs18.x, nodejs20.x, python3.9 to 3.11, java8.al2, java11, java17, provided.al2 and dotnet8 from 2027-08-31 (function creation from 2027-07-29). After that no file, layer or variable can be added, so these functions move first.

## Amazon ECS on AWS Fargate

**What decides PQ.** You own the image, so the fix is usually the base image: its OpenSSL, JDK or Node version. The host is AWS's and does not matter. Choose a base image that is PQ by default, and you need no variable at all.

| Language | PQ by default in | Not PQ by default in | Fix | Detail |
| --- | --- | --- | --- | --- |
| Python | Debian 13 (`-trixie`), Alpine 3.24 | Debian 12 (`-bookworm`), Ubuntu 24.04, Azure Linux 3.0, AL2023 | Move to a trixie or Alpine image; on AL2023 `update-crypto-policies --set DEFAULT:PQ` in the Dockerfile or `openssl-pq.cnf` | [Python](#ch-04-python) |
| Node.js | Official `node` images 22.20+ and 24.5+ (bundled OpenSSL 3.5) | Node 18 and 20; AL2023 `dnf install nodejs22` | Official image 24.9+; distro Node: system policy or config | [Node.js](#ch-05-nodejs) |
| Java | Corretto or Temurin 25.0.5+ | JDK 8 to 21 | JDK 25.0.5+ image, or the kit v2 agent, or a static `java.security` Bouncy Castle entry (17, 21) | [Java](#ch-06-java) |
| .NET | .NET 10 on Alpine or Ubuntu 26.04 (`resolute`) | .NET 8 default images (Debian 12), AL2023 | Alpine or `resolute` image; on AL2023 the config or `DEFAULT:PQ` | [.NET](#ch-07-dotnet) |
| Go | Any image, with Go 1.24+ and a `go` line of 1.24+ | Older toolchain or `go` line | Rebuild; base image does not matter | [Go](#ch-03-go) |

The main change is usually one line of the Dockerfile:

```
FROM python:3.13-slim-trixie        # was python:3.13-slim-bookworm: OpenSSL 3.5, PQ by default
```

**As a load balancer target.** When an ALB or NLB with a PQ listener policy forwards to an HTTPS target, the load balancer's leg is PQ only if the target's TLS server offers ML-KEM. The same fixes apply to servers: 27 Fargate target cases (Tested) show a fixed server negotiates PQ with the ALB's PQ backend policy and classical TLS 1.2 with the classic one. Java servers with EC certificates under Bouncy Castle also need `ssl.KeyManagerFactory.algorithm=PKIX` (kit v2 sets it). See [Load balancers](#ch-load-balancers).

**Detection.** CloudTrail for AWS API calls; application handshake logs; an egress proxy that logs the group for third-party traffic. VPC Traffic Mirroring does not support Fargate.

**Ship and roll back.** Base image bump or Dockerfile `ENV` through the normal pipeline; roll back by reverting the image tag. Task definition variables override image `ENV` for a fast rollback without a rebuild.

## Amazon ECS on EC2 and Amazon EKS

**What decides PQ.** The same as Fargate: the container image decides, and the node's OS and crypto policy do not reach inside the container. Everything in the Fargate table applies unchanged; EKS sets variables in the pod spec instead of the task definition.

What is different on EC2-backed clusters:

- **Detection is better.** Node ENIs are Nitro EC2 interfaces, so VPC Traffic Mirroring to a Zeek sensor sees every pod's and task's east-west and egress TLS, whatever the language ([Detection](#ch-12-detection)).
- **Host agents follow the node OS.** The ECS agent, kubelet, SSM agent and node-level tools use the AMI's OpenSSL and crypto policy; treat them as [EC2 hosts](#ch-14-compute--amazon-ec2-hosts).
- **A service mesh can carry PQ for the app.** On EKS, Linkerd 2.19+ is PQ by default and Istio 1.27+ can be set to PQ, covering mesh-owned mTLS legs whatever the app's language. ECS Service Connect has no group setting. See [Service mesh](#ch-service-mesh).
- **Admission control.** Kyverno or Gatekeeper policies check images and pod variables at admission ([Enforcement and guardrails](#ch-21-enforcement)).

The main change for an EKS Deployment that keeps an AL2023 image:

```
spec:
  containers:
    - name: app
      image: <account>.dkr.ecr.<region>.amazonaws.com/payments:1.4.2
      env:
        - name: OPENSSL_CONF
          value: /etc/pq-tls/openssl-pq.cnf     # baked into the image
```

Full files: [configs/go/deployment.yaml](REPO/configs/go/deployment.yaml), [configs/go/taskdef.json](REPO/configs/go/taskdef.json) and the matching files in each language folder under `configs/`.

## Amazon EC2 hosts

**What decides PQ.** You own the OS. Programs that link the system OpenSSL (Python, .NET, distro Node.js, curl, nginx) follow the OS default and crypto policy; Java, Go and official Node.js binaries bring their own TLS and follow their language rules.

| OS | PQ by default for OpenSSL programs? | Fix |
| --- | --- | --- |
| Amazon Linux 2023 | No (crypto policy omits ML-KEM) | `update-crypto-policies --set DEFAULT:PQ` via SSM State Manager, in waves by tag; or per service, `OPENSSL_CONF` in a systemd drop-in |
| Amazon Linux 2 | No, and cannot be (OpenSSL 1.0.2 and 1.1.1) | Migrate to AL2023 |
| Debian 13, Ubuntu 26.04 | Yes, for OpenSSL programs. GnuTLS programs (wget, Debian git) stay classical | Use OpenSSL-linked tools where the traffic matters |
| Windows Server | Opt-in (Schannel `x25519_mlkem768`, TLS 1.3 only) | Schannel group order via GPO or SSM |

| Language on the host | Fix | Detail |
| --- | --- | --- |
| Python, .NET, distro Node.js | The OS fix above | [Python](#ch-04-python), [.NET](#ch-07-dotnet), [Node.js](#ch-05-nodejs) |
| Node.js official binaries | Node 22.20+ or 24.5+; nothing else | [Node.js](#ch-05-nodejs) |
| Java | JDK 25.0.5+, or the kit v2 agent in the unit's `JAVA_TOOL_OPTIONS` | [Java](#ch-06-java) |
| Go | Rebuild with Go 1.24+ and a `go` line of 1.24+ | [Go](#ch-03-go) |

The main change, host-wide on AL2023 (full SSM document: [configs/hosts-and-os](REPO/configs/hosts-and-os)):

```
sudo update-crypto-policies --set DEFAULT:PQ    # every OpenSSL program on the host; reboot or restart services
```

Host-wide `DEFAULT:PQ` changes every OpenSSL program at once, so roll it out in waves by tag with SSM State Manager and keep the per-service `OPENSSL_CONF` drop-in for hosts that cannot take the whole policy. See [Hosts and OS](#ch-hosts-and-os).

**Detection.** CloudTrail; Zeek on mirrored ENIs; SSM Inventory for OS, OpenSSL version and crypto policy.
