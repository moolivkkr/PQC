# .NET

**What decides PQ.** .NET has no API for TLS groups: it uses the operating system's stack, OpenSSL on Linux and Schannel on Windows. So the base image and its crypto policy decide, exactly as for Python. Lambda's dotnet8 and dotnet10 runtimes have OpenSSL 3.5 under the AL2023 policy, which leaves ML-KEM out.

| Compute | PQ today? | What to change |
| --- | --- | --- |
| Lambda dotnet8, dotnet10 (zip, image, Native AOT) | No | Ship `openssl-pq.cnf`, set `OPENSSL_CONF` (or the `pq-tls` layer). dotnet8 is deprecated: creation blocked from 2027-07-29, updates from 2027-08-31; move to dotnet10 |
| Fargate, ECS on EC2, EKS | `8.0-alpine`, `10.0-alpine`, `10.0-resolute` (Ubuntu 26.04): yes. Default `8.0` and `10.0` tags, `-noble`, Azure Linux, AL2023: no | Use an Alpine or `resolute` image; on AL2023 the config file or `DEFAULT:PQ` |
| EC2 Linux | AL2023: no | `DEFAULT:PQ` via SSM, or `OPENSSL_CONF` in the service unit |
| Windows | Opt-in, not tested | Schannel group `X25519_MLKEM768` (TLS 1.3 only) via GPO or SSM, after the July 2026 update |

**What to change, in order**

1. Pick the row above. There is nothing to change in code, and nothing code can do.
2. Remove `EnabledSslProtocols = Tls12` caps: ML-KEM needs TLS 1.3.
3. On Lambda, code that opens an `X509Store` needs a writable `HOME`: export `HOME=/tmp` from an exec wrapper in the package (tested), or load the PFX/PEM directly.

**Certificates and keystores:** no change for PFX, PEM, `X509Store`, custom validation callbacks or `CustomTrustStore`. `X509Certificate2.CreateFromPemFile(caPath)` throws on a CA-only file: use `CreateFromPem(File.ReadAllText(path))`. **ML-DSA:** .NET 10 on Alpine, `resolute` or AL2023 with `DEFAULT:PQ` accepts ML-DSA server certificates and presents ML-DSA client certificates (client side tested; a .NET server with an ML-DSA certificate was not). The `openssl-pq.cnf` route (Lambda, AL2023 config) adds ML-KEM only: ML-DSA-only servers fail. .NET 8 receives ML-DSA server certificates but cannot load an ML-DSA client key.

**Rollback:** remove `OPENSSL_CONF` (or `PQ_TLS_DISABLE=1` with the layer), revert the `FROM` line, or `update-crypto-policies --set DEFAULT`. **Detect:** CloudTrail for AWS calls; .NET does not expose the negotiated group, so application logs cannot prove PQ.

**Tested:** 71 client cases (Lambda 33, Fargate 25, ECS on EC2 6, EC2 7) and 7 load balancer target cases, all passing, on LocalStack and Docker (not real AWS). Not tested: EKS, Windows, FIPS hosts.
