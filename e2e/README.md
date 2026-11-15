# PQC end-to-end tests on LocalStack

Runnable tests for the document's claims about post-quantum TLS: for each language, runtime version, compute type and
fix, the suite deploys a real workload into LocalStack, connects to a TLS observer and grades what was negotiated.

## What runs where

| Compute | How it runs in LocalStack | Base images |
|---|---|---|
| Lambda (zip) | Managed runtime identifiers (`python3.12`, `nodejs22.x`, `java21`, `dotnet8`, `provided.al2023`, ...) | AWS's own runtime images, `public.ecr.aws/lambda/*` |
| Lambda (container image) | `PackageType: Image` from LocalStack ECR | `public.ecr.aws/lambda/*` |
| ECS Fargate | Task definition + `run_task`, awslogs to CloudWatch Logs | AL2023 `2023.12.20261109.0` + dnf runtimes, official language images |
| ECS on EC2 | Same, `launchType: EC2`, bridge networking | Same images |
| EC2 | `run_instances` with user data, docker VM manager | Golden AMIs: `pqc-al2023` (AL2023 release `2023.12.20261109.0`, the same build as AMI `al2023-ami-2023.12.20261109.0`) and `pqc-al2` (Amazon Linux 2) |

Lambda fixes are tested three ways: the `pq-tls` **layer** (exec wrapper), the `pq-egress` **extension** (an external
extension that originates PQ TLS for runtimes that can't), and **bundled** files in the deployment package. A
`pq-tls-combined` layer puts both in one of the five layer slots.

## The observer

`observer/` is a Go 1.27 TLS server with five listeners, and it logs every ClientHello (offered groups, offered
versions) and every request (negotiated version and group):

| Listener | Port | Purpose |
|---|---|---|
| hybrid | 8443 | TLS 1.2-1.3, PQ preferred, classical accepted: what does the client negotiate? |
| pqonly | 8444 | TLS 1.3 + X25519MLKEM768 only: does the client survive PQ enforcement? |
| mtls | 8445 | Client certificate required: existing keystore / client certificate |
| eccert | 8446 | ECDSA P-256 server certificate |
| tls12 | 8447 | TLS 1.2 only: legacy server still works, and visibility flags it |

Every client trusts only the suite's test CA (the custom-CA case) and presents a client certificate on `mtls`.

## Detection checks

After the cases run, two checks test visibility of non-PQ handshakes:

- **CloudWatch Logs:** a filter over the Lambda and ECS log groups,
  `{ ($.event = "tls_handshake") && ($.pq_status = "classical") }`, must find exactly the classical handshakes the
  clients reported.
- **Server side:** the observer's handshake log must contain every one of them, plus TLS 1.2 negotiations, without
  any client-side logging.

## Run it

Step-by-step instructions for every language, reading results and troubleshooting: [RUNNING.md](RUNNING.md).


```bash
e2e/run.sh                         # build everything, run every language
e2e/run.sh --lang python           # one language
e2e/run.sh --skip-build --id 'py-lambda-py312*'
e2e/run.sh down                    # delete this suite's functions and instances, stop its two containers
```

Results land in `e2e/results/runs/<run>/` (`summary.md`, `results.json`, `junit.xml`), copied to `results/latest/`.

**Prerequisites:** Docker Desktop, a LocalStack auth token (env `LOCALSTACK_AUTH_TOKEN`, or the `export` line in
`~/.zshrc`, or `~/.localstack/auth.json`), and network access for image pulls and package registries.

## Isolation from other LocalStack instances

The suite runs its own LocalStack: container `pqc-e2e-localstack`, port `127.0.0.1:4600`, network `pqc-e2e`
(`10.250.0.0/24`), volume `pqc-e2e-ls-state`. It sets `EC2_REMOVE_CONTAINERS=0` and `EC2_DOWNLOAD_DEFAULT_IMAGES=0`,
so it never removes another instance's EC2 containers or re-pulls shared AMI tags. Cleanup deletes only `pqc-*`
resources and `project=pqc-e2e` tagged instances.

## Adding or changing cases

See [CONTRACT.md](CONTRACT.md). An expectation is the document's claim. When reality differs, the case records what
is observed plus a `finding` explaining the gap, so the suite stays green and the summary lists every documented
error.

## What the suite found (fixed in the document on 2026-11-14)

Every item below is kept as a regression case, so a revert to the old text or kit fails the run.

| Tab | Was | Observed | Fixed in |
|---|---|---|---|
| Python | Legacy bridge: `pip install pyopenssl cryptography` | Lambda 3.9-3.11 lack `idna`: every urllib3/requests/boto3 request raises `ModuleNotFoundError`. The 3.11 abi3 cryptography wheel fails on 3.9/3.10 | `src/04-python.md` Bridge step: add `idna`, build in each version's Lambda image |
| Node.js | "Node 20: no setting adds PQ" | AL2023 `dnf install nodejs20` links system OpenSSL 3.5.8 and is PQ with `OPENSSL_CONF` or `DEFAULT:PQ`. Lambda `nodejs18.x`/`20.x` bundle OpenSSL 3.1.8/3.2.6, not 3.0.x (still no ML-KEM) | `src/05-nodejs.md`, `src/01-overview.md` |
| Java | JDK 8 + kit + `-Djdk.tls.client.protocols` gives PQ | With `HttpsURLConnection` every handshake fails (BCJSSE endpoint identification, bc-java#1656) until `-Dorg.bouncycastle.jsse.client.assumeOriginalHostName=true`. The TLS 1.2 client default is the Lambda Java 8 runtime's, not JDK 8's | `src/06-java.md`, `src/01-overview.md`, `template.yaml`, layer `wrapper` (adds the flag) |
| .NET / enforcement | Guard rule PQ-L2 accepts the `pq-tls` wrapper for dotnet8/10 | The wrapper had no dotnet branch: functions passed the guard and stayed classical | Layer `wrapper`: dotnet branch sets `OPENSSL_CONF` |
| .NET | CurrentUser/My store only needs re-import at start | On Lambda the passwd home is read-only: the import fails before any handshake | `src/07-dotnet.md`: set `HOME=/tmp` on Lambda |
| Go | FIPS modes: "P-256 only" / "hybrids + P-256" | The client also offers P-384 and P-521 | `src/03-go.md` FIPS tables, `go-pq-lint.sh` message |

## What this does not prove

- EC2 instances are containers built from the AMI's release packages, not the AMI disk image. The kernel is Docker
  Desktop's. The TLS userland (OpenSSL, crypto policy, runtimes) matches the AMI.
- Lambda functions run in AWS's runtime images under LocalStack's runtime emulation, not Firecracker. The bootstrap and
  OpenSSL configuration are AWS's.
- ECS on EC2 runs tasks without registered container instances, so the ECS-optimized AMI host isn't exercised. A
  container's TLS comes from its own image, so this doesn't change client results.
- ALB/NLB listener security policies can't be tested on LocalStack. Probe on 2026-11-15 (throwaway LocalStack 2026.10.6, `elbv2` + `acm`): an HTTPS listener with `ELBSecurityPolicy-2016-08` and an imported RSA certificate served LocalStack's own `localhost.localstack.cloud` certificate and negotiated `X25519MLKEM768`. A LocalStack ALB case would pass whatever policy is set, so the suite has none. Verify listener policies on real AWS (connection logs field 13 `tls_keyexchange`).
- AWS-managed TLS endpoints (ALB/NLB, API Gateway, CloudFront, KMS, SSM, Secrets Manager) are not tested: LocalStack's
  endpoints don't use AWS's TLS stacks. The AWS Parameters and Secrets Lambda Extension can't be downloaded offline.
  `pq-egress` stands in for that pattern.
- Everything ran on arm64 (Apple silicon). x86_64 runtimes are not exercised.
- LocalStack drops `HOME` from a Lambda function's environment variables (AWS doesn't reserve it, and AWS's image under its own emulator honours it). Cases that need `HOME` export it from an exec wrapper.
- LocalStack's EC2 service is slow under parallel load: run one suite at a time ([RUNNING.md](RUNNING.md), Troubleshooting).
- LocalStack's CloudWatch Logs filters don't support boolean JSON comparisons (`$.pq IS FALSE`). The suite uses the
  string field `pq_status`, which works on both. LocalStack's Logs Insights ignored the `filter` clause.
