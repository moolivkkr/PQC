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

## What this does not prove

- EC2 instances are containers built from the AMI's release packages, not the AMI disk image. The kernel is Docker
  Desktop's. The TLS userland (OpenSSL, crypto policy, runtimes) matches the AMI.
- Lambda functions run in AWS's runtime images under LocalStack's runtime emulation, not Firecracker. The bootstrap and
  OpenSSL configuration are AWS's.
- ECS on EC2 runs tasks without registered container instances, so the ECS-optimized AMI host isn't exercised. A
  container's TLS comes from its own image, so this doesn't change client results.
- AWS-managed TLS endpoints (ALB/NLB, API Gateway, CloudFront, KMS, SSM, Secrets Manager) are not tested: LocalStack's
  endpoints don't use AWS's TLS stacks. The AWS Parameters and Secrets Lambda Extension can't be downloaded offline.
  `pq-egress` stands in for that pattern.
- Everything ran on arm64 (Apple silicon). x86_64 runtimes are not exercised.
- LocalStack's CloudWatch Logs filters don't support boolean JSON comparisons (`$.pq IS FALSE`). The suite uses the
  string field `pq_status`, which works on both. LocalStack's Logs Insights ignored the `filter` clause.
