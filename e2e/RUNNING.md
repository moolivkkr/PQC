# Running the PQC end-to-end tests

This guide takes you from a clean machine to a graded run for any language. For what the suite tests and why, see
[README.md](README.md). To add cases or a language, see [CONTRACT.md](CONTRACT.md).

Each test deploys a real workload (Lambda function, ECS task or EC2 instance) into a local LocalStack. The workload
opens TLS connections to a test server called the observer. The runner then checks what was negotiated against the
document's claim for that runtime and fix.

```
workload (Lambda / ECS task / EC2 instance)  --TLS-->  pq-observer (5 listeners)
   the TLS client under test                            logs offered vs negotiated groups
```

The suite tests the workload's **outbound** TLS. It does not test a load balancer in front of the workload; see
"What this does not prove" in the README.

## 1. Prerequisites

| Need | Check | Notes |
|---|---|---|
| Docker Desktop, Apple silicon or arm64 Linux | `docker version` | On macOS the CLI is at `/Applications/Docker.app/Contents/Resources/bin`; `env.sh` adds it to `PATH` |
| Plenty of free disk | `docker system df` | All languages pull Lambda base images, language and MCR images, two AMI images and build caches. On the machine that built this suite they total about 90 GB before shared layers are counted once; one language needs far less |
| LocalStack Pro auth token | see below | Needed for Lambda images, ECS, ECR and EC2 |
| Python 3 on the host | `python3 --version` | Only to generate case files; the runner runs in a container |
| Network access | | Image pulls (`public.ecr.aws`, Docker Hub, `mcr.microsoft.com`) and package registries (PyPI, Maven Central, NuGet, the Go module proxy, AL2023 dnf repos) |

**Auth token.** `env.sh` looks for it in this order:

1. The `LOCALSTACK_AUTH_TOKEN` variable in your shell.
2. The `export LOCALSTACK_AUTH_TOKEN=...` line in `~/.zshrc`. It is read with a regex, so a stray quote on that line
   doesn't matter.
3. `~/.localstack/auth.json`.

Confirm it was found:

```bash
source e2e/env.sh && echo "token length: ${#LOCALSTACK_AUTH_TOKEN}"     # expect about 39, not 0
```

## 2. First run (one language)

Start with one language to warm the image caches. Run it from the repository root:

```bash
e2e/run.sh --lang python
```

`run.sh` does the following:

1. Generates the test PKI in `e2e/.work/certs/` (only the first time).
2. Starts the stack: `pqc-e2e-localstack` (LocalStack Pro, `127.0.0.1:4600`) and `pqc-e2e-observer`, both on Docker
   network `pqc-e2e`.
3. `build/common.sh`: builds the runner image and the `pq-egress` extension, and lays out the `pq-tls` layer files.
4. `build/<lang>.sh`: builds Lambda zips, pushes images to LocalStack ECR and writes the EC2 files.
5. `build/layers.sh`: zips the three layers (`pq-tls`, `pq-egress`, `pq-tls-combined`).
6. `build/ami.sh`: builds the golden AMIs `pqc-al2023` (AL2023 `2023.12.20261109.0`) and `pqc-al2` (Amazon Linux 2).
7. Generates `cases/<lang>.json` from `cases/<lang>.py`.
8. Runs the cases and prints one line per case: `PASS`, `FAIL` or `ERROR`, then what was negotiated per listener.

The first build of a language pulls several GB of images. Later builds reuse them.

`run.sh` exits 0 only when every selected case passes.

## 3. Everyday commands

| Goal | Command |
|---|---|
| Everything: build all languages, run all cases | `e2e/run.sh` |
| One language: build and run | `e2e/run.sh --lang java` |
| Several languages | `e2e/run.sh --lang node,dotnet` |
| Rerun without rebuilding | `e2e/run.sh --skip-build --lang go` |
| One compute type | `e2e/run.sh --skip-build --lang python --compute lambda` (also `ecs-fargate`, `ecs-ec2`, `ec2`) |
| Matching case ids (glob, comma-separated) | `e2e/run.sh --skip-build --id 'py-lambda-py312*,node-lambda-n22*'` |
| Fewer parallel jobs (slow machine) | `PQC_JOBS=3 e2e/run.sh --lang go` (default 6; EC2 cases use at most 4) |
| List cases without running them | `source e2e/env.sh && docker run --rm --network pqc-e2e -v "$PWD/e2e":/e2e pqc-e2e/runner:local list --lang java` |
| Delete this suite's functions and instances, stop its containers | `e2e/run.sh down` |

**Use `--skip-build` carefully.** `build/common.sh` rebuilds the `pq-tls` layer from scratch, and Java adds its agent
jar to that layer. If you build only Python and then run Java with `--skip-build`, the Java layer cases will fail. Run
`e2e/run.sh --lang java` once without `--skip-build`, or build everything with `e2e/run.sh`.

After you change a language's probe or EC2 files, rebuild that language before rerunning. The AMI and images carry
copies of them.

## 4. Reading the results

Each run writes `e2e/results/runs/<run-id>/` and copies the files to `e2e/results/latest/`. `latest/` holds only the
most recent run, so a one-language run replaces it.

| File | Use |
|---|---|
| `summary.md` | One table per language: what each case negotiated on each listener, and the verdict. Lists findings and failures at the end |
| `junit.xml` | For CI (one test suite per language and compute) |
| `results.json` | Everything: client output, the observer's records of each connection, offered groups, Lambda log lines from the wrapper or extension, mismatches |

Cell values in `summary.md`:

| Cell | Meaning |
|---|---|
| **PQ** | Negotiated a hybrid post-quantum group (X25519MLKEM768 and similar) |
| classical | Connected with a classical group (X25519, P-256) |
| classical 1.2 | Connected with TLS 1.2 |
| fail | The handshake or request failed (expected against `pqonly` for classical clients) |

**Verdicts:**

- **PASS:** what was observed matched the case's expectation. PASS doesn't mean PQ. A baseline case passes when the
  runtime is classical, exactly as the document says.
- **FAIL:** something differed from the expectation. The summary names each mismatch, for example
  `hybrid: pq=False expected True`.
- **ERROR:** the case didn't produce a client result (deploy error, timeout, crash). `results.json` has the details.

**Findings.** When the document or a kit file turned out to be wrong, the case records what really happens and adds a
`finding` that explains the gap. Findings appear in the summary's "Findings" section and stay green, so a regression
still shows up.

**Detection checks**, which run after the cases:

- `detect-cloudwatch-nonpq`: a CloudWatch Logs filter, `{ ($.event = "tls_handshake") && ($.pq_status = "classical") }`,
  must find exactly the classical handshakes the clients reported.
- `detect-server-handshake-log`: the observer's log must contain every one of them.

## 5. The five listeners every case visits

| Listener | Port | A classical client | A PQ client |
|---|---|---|---|
| `hybrid` | 8443 | connects, classical | connects, X25519MLKEM768 |
| `pqonly` | 8444 | **fails** | connects |
| `mtls` | 8445 | connects with the client certificate | same, with PQ |
| `eccert` | 8446 | connects to the ECDSA P-256 server certificate | same, with PQ |
| `tls12` | 8447 | connects, TLS 1.2 | connects, TLS 1.2 (the fallback still works) |

Every client trusts only the suite's test CA (`e2e/.work/certs/ca.crt`, or `truststore.p12` for Java). The `mtls`
listener needs `client.crt`/`client.key`, or `client.p12` (password `changeit`).

## 6. Per-language guide

Case ids start with the language prefix, then the compute: `<lang>-lambda-…`, `<lang>-fargate-…`, `<lang>-ecsec2-…`,
`<lang>-ec2-…`. Modes: `baseline` (no change), `bundled` (fix files in the package), `layer` (pq-tls layer + exec
wrapper), `extension` (pq-egress extension), `config` (an environment variable such as `OPENSSL_CONF`),
`crypto-policy` (`DEFAULT:PQ`), `image-baseline`/`image-fixed` (Lambda container images).

### Python (`py-`)

| | |
|---|---|
| Document tab | `src/04-python.md`; fix files from `configs/python/` |
| Probe | `clients/python/probe.py`: urllib3 when available (the requests and boto3 path), otherwise `http.client`; `PQC_PY_STACK=stdlib` forces `http.client` |
| Lambda | `python3.9`-`python3.14` zip; container images on `public.ecr.aws/lambda/python:3.12` and `3.13` |
| ECS (Fargate, EC2) | AL2023 + dnf Python 3.11-3.14; `python:3.12/3.13-slim-trixie`, `3.12-alpine`, `3.12-slim-bookworm` |
| EC2 | `pqc-al2023` with Python 3.11-3.14; `pqc-al2` with Python 3.7 |
| Fixes tested | `OPENSSL_CONF` with `openssl-pq.cnf`; the pq-tls layer; the legacy shim (pyOpenSSL + cryptography + idna) for 3.9-3.11; the pq-egress extension; `DEFAULT:PQ` |
| Downloads | PyPI: `cryptography==50.0.2`, `pyOpenSSL==26.4.0`, `idna==3.20`, installed inside each Lambda Python image |

```bash
e2e/run.sh --lang python
e2e/run.sh --skip-build --id 'py-lambda-py39*,py-lambda-py311*'    # legacy runtimes: shim, layer, extension
e2e/run.sh --skip-build --id 'py-fargate-*'                        # base image comparison
```

The shim cases need wheels built per Python version; `build/python.sh` does that. The `py-lambda-py311-shim-noidna`
case is supposed to fail its requests: it is the regression test for the missing-`idna` pitfall.

### Node.js (`node-`)

| | |
|---|---|
| Document tab | `src/05-nodejs.md`; fix files from `configs/nodejs/` |
| Probe | `clients/node/index.js` using the `https` module (`ca`, `cert`/`key`, `pfx`) |
| Lambda | `nodejs18.x`, `20.x`, `22.x`, `24.x` zip; container images on `lambda/nodejs:22` and `24` |
| ECS (Fargate, EC2) | AL2023 + dnf `nodejs20/22/24`; official `node` images (20, 22, 24, slim and alpine, plus pinned 22.19/22.20 and 24.4/24.5 to show where PQ starts); Debian 13 and Alpine distro Node |
| EC2 | `pqc-al2023` with dnf `node-20/22/24` and official Node 22 and 24 binaries in `/opt/pqc/node/official-*` |
| Fixes tested | `OPENSSL_CONF` / `NODE_OPTIONS=--openssl-config` with `openssl-pq-node.cnf`; the pq-tls layer; the pq-egress extension; `DEFAULT:PQ`; a legacy RC2/3DES PFX |
| Downloads | Node images and binaries only (no npm packages) |

```bash
e2e/run.sh --lang node
e2e/run.sh --skip-build --id 'node-lambda-n18*,node-lambda-n20*'   # runtimes with no in-process fix: extension only
e2e/run.sh --skip-build --id 'node-fargate-lib-*'                  # official images by version
```

### Java (`java-`)

| | |
|---|---|
| Document tab | `src/06-java.md`; kit `kit/java-v2/` (agent source, `pq-tls.security`, layer wrapper); fix files from `configs/java/` |
| Probe | `clients/java/Probe.java`, compiled once with `--release 8`: `HttpsURLConnection` with an `SSLContext` built from `truststore.p12` and `client.p12` (the custom keystore case) |
| Lambda | `java8.al2023`, `java11`, `java17`, `java21`, `java25` zip; container images on `lambda/java` 8-25 |
| ECS (Fargate, EC2) | `amazoncorretto` 8/11/17/21/25, AL2023 + dnf Corretto, an agent image, static `java.security` images (Corretto 17/21, Temurin 21) |
| EC2 | `pqc-al2023` with Corretto 11/17/21/25; `pqc-al2` with Corretto 11/17 |
| Fixes tested | Bouncy Castle JSSE agent v2 via `JAVA_TOOL_OPTIONS`; the pq-tls layer v2; a static `java.security` provider; JDK 25 defaults; the pq-egress extension |
| Downloads | Maven Central: Bouncy Castle 1.87 jars (SHA-1 checked and cached); the agent jar is built from `kit/java-v2/src` |

```bash
e2e/run.sh --lang java
e2e/run.sh --skip-build --id 'java-lambda-j8*,java-lambda-j21*'    # agent and layer on old JDKs
e2e/run.sh --skip-build --id 'java-*static*'                       # static java.security images
```

The build adds the agent jar and Bouncy Castle jars to the `pq-tls` layer. Run `e2e/run.sh --lang java` (not
`--skip-build`) after any Python-only build.

### .NET (`dotnet-`)

| | |
|---|---|
| Document tab | `src/07-dotnet.md`, plus the Lambda rows of `src/21-enforcement.md`; fix files from `configs/dotnet/` |
| Probe | `clients/dotnet/` (`Probe.cs`, `probe.csproj`): `HttpClient` + `SocketsHttpHandler`, a `CustomTrustStore` with the test CA, client certificate from `client.p12` |
| Lambda | `dotnet8`, `dotnet10` zip; Native AOT on `provided.al2023`; container images on `lambda/dotnet:8` and `10` |
| ECS (Fargate, EC2) | AL2023 + dnf .NET 8/10 (baseline, `OPENSSL_CONF`, `DEFAULT:PQ`, CA in the system store); MCR runtime and aspnet images (Debian, Alpine, Azure Linux 3.0, Ubuntu 24.04 chiseled, Ubuntu 26.04) |
| EC2 | `pqc-al2023` with dnf .NET 8 and 10 |
| Fixes tested | `OPENSSL_CONF` with the AL2023 config file; the pq-tls layer, both through its wrapper and with `OPENSSL_CONF` set directly; the pq-egress extension; `DEFAULT:PQ`; `SSL_CERT_DIR` and the system CA store |
| Downloads | NuGet: Amazon.Lambda packages, restored inside the .NET SDK containers |

```bash
e2e/run.sh --lang dotnet
e2e/run.sh --skip-build --id 'dotnet-lambda-*layer*'               # wrapper vs OPENSSL_CONF on the layer
e2e/run.sh --skip-build --id 'dotnet-fargate-mcr-*'                # MCR base images compared
```

.NET on Linux uses the system OpenSSL. So the base image's OpenSSL version and crypto policy decide the result, not
the .NET version.

### Go (`go-`)

| | |
|---|---|
| Document tab | `src/03-go.md`; fix files from `configs/go/` |
| Probe | `clients/go/`: `net/http` with `RootCAs` from the test CA and a client certificate; build tags produce FIPS, BoringCrypto, explicit-settings and AWS SDK variants |
| Lambda | `provided.al2023` and `provided.al2` with `bootstrap` built by Go 1.23-1.27; container images from `configs/go/Dockerfile.lambda` |
| ECS (Fargate, EC2) | The same binaries on AL2023, AL2, distroless, scratch and golang bases; the document's `Dockerfile` and `Dockerfile.fips` |
| EC2 | `pqc-al2023` and `pqc-al2` running prebuilt binaries per Go version, plus one built with the distro `golang` package |
| Fixes tested | Go version upgrades; `GODEBUG` (`tlsmlkem=0` opt-out); go line in `go.mod`; FIPS modes; hard-coded `CurvePreferences` / `MaxVersion` (settings that block PQ); the pq-egress extension for Go 1.23 builds; the pq-tls layer (no effect on Go) |
| Downloads | Go module proxy (aws-lambda-go and others); modules are vendored for the offline EC2 distro-toolchain build |

```bash
e2e/run.sh --lang go
e2e/run.sh --skip-build --id 'go-lambda-al2023-go12*-baseline'     # version matrix
e2e/run.sh --skip-build --id 'go-*fips*'                           # FIPS modes
```

Go has its own TLS stack, so the OS, crypto policy and base image don't change its result. Several cases exist to
prove exactly that.

## 7. Looking inside a case

```bash
source e2e/env.sh
# Everything the observer saw for one case (use full_id from results.json: <run-id>-<case-id>)
docker exec pqc-e2e-observer wget -qO- "http://127.0.0.1:8080/events?id=r1115005115-py-lambda-py312-layer"

# Talk to this suite's LocalStack with the AWS SDK from the runner image
docker run --rm --network pqc-e2e --entrypoint python3 pqc-e2e/runner:local -c \
  'import boto3; print([f["FunctionName"] for f in boto3.client("lambda").list_functions()["Functions"]])'

# Keep a Lambda function after its case runs: add "keep": true to the case's "lambda" block, regenerate, rerun
# EC2 instance containers are named localstack-ec2.<instance-id>; this suite's carry the label project=pqc-e2e
docker ps --filter label=project=pqc-e2e
```

LocalStack's API is also on the host at `http://localhost:4600`, for example with `AWS_ENDPOINT_URL` set by `env.sh`.

## 8. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `LOCALSTACK_AUTH_TOKEN not set` | See section 1. `echo ${#LOCALSTACK_AUTH_TOKEN}` after `source e2e/env.sh` must not be 0 |
| `docker: command not found` | Use `source e2e/env.sh`; it adds Docker Desktop's bin directory to `PATH` |
| Port 4600 in use | Something else is on it. Set `PQC_LS_PORT` in `env.sh` to a free port |
| LocalStack shows `unhealthy` but answers | Check `curl -s localhost:4600/_localstack/info`; `is_license_activated` must be `true` |
| Many `ERROR` cases with `RepositoryNotFoundException` | The language wasn't built in this LocalStack session (state isn't persisted). Run without `--skip-build` |
| EC2 cases time out | The AMI lacks that language's files, or the instance didn't boot. Run `bash e2e/build/ami.sh` and rerun with `--compute ec2` |
| Java layer cases classical or failing after a Python-only build | `common.sh` rebuilt the layer without the Java jars. Run `e2e/run.sh --lang java` |
| First Lambda case of a runtime is slow | LocalStack is pulling that runtime image; later cases reuse it |
| `results/latest` shows only one language | `latest/` is the last run only. Older runs stay in `results/runs/` |
| A case says `FAIL` after you changed a fix file | That's the suite working: the fix changed behaviour. Either the fix is wrong, or update the case's expectation and add a `finding` if the document no longer matches |

## 9. Isolation and cleanup

The suite has its own LocalStack and never touches another project's instance. The two share only the Docker daemon.

- **Own resources:** container `pqc-e2e-localstack`, network `pqc-e2e` (`10.250.0.0/24`), volume
  `pqc-e2e-ls-state`, port `127.0.0.1:4600`.
- **Created resources:** Lambda functions and layers named `pqc-*`, EC2 instances tagged `project=pqc-e2e`, AMI images
  tagged `localstack-ec2/pqc-*`.
- **EC2 settings:** `EC2_REMOVE_CONTAINERS=0` and `EC2_DOWNLOAD_DEFAULT_IMAGES=0`, so it never removes other
  instances' containers or re-pulls shared AMI tags.

`e2e/run.sh down` deletes only those resources and stops the two containers. It never removes volumes. To reclaim disk
afterwards, remove images by name (`docker images | grep -E 'pqc-|localstack-ec2/pqc-'`). Don't run
`docker system prune` while another project's LocalStack is in use.
