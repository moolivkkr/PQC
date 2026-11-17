# Python

**What decides PQ.** The standard library `ssl` module uses the platform's OpenSSL, so the OS image and its crypto policy decide. OpenSSL 3.5 can do ML-KEM, but Amazon Linux 2023's crypto policy leaves it out, so Lambda and AL2023 images negotiate classical X25519 until a config file adds it. Libraries that bundle their own TLS (grpcio, awscrt, psycopg binary, pyOpenSSL, confluent-kafka) are already PQ on every runtime.

| Compute | PQ today? | What to change |
| --- | --- | --- |
| Lambda python3.12 to 3.14 | No | Ship `openssl-pq.cnf`, set `OPENSSL_CONF=/var/task/pq-tls/openssl-pq.cnf` (or the `pq-tls` layer) |
| Lambda python3.9 to 3.11 (Amazon Linux 2, OpenSSL 1.1.1) | No | Upgrade to 3.12+ before 2027-08-31. Bridge: the shim (requests and boto3 only) or the layer |
| Fargate, ECS on EC2, EKS | Debian 13 (`-trixie`) and Alpine 3.24: yes. Debian 12, Ubuntu 24.04, AL2023: no | Move to a trixie or Alpine image; on AL2023, `DEFAULT:PQ` in the Dockerfile or the config file |
| EC2 | AL2023: no; Debian 13, Ubuntu 26.04: yes | `update-crypto-policies --set DEFAULT:PQ` via SSM, or `OPENSSL_CONF` in the service unit |

**What to change, in order**

1. Pick the row above; one file and one variable, or one base image change.
2. Don't use `OPENSSL_CONF=/dev/null`: it enables PQ but drops the crypto policy and changes the cipher list.
3. Remove `set_ecdh_curve(...)` and TLS 1.2 maximums from code; on Python 3.15, `SSLContext.set_groups()` is the right API if you must pin groups.
4. Python 3.9 to 3.11 bridge: build pyOpenSSL, cryptography **and idna** in each version's Lambda image (without idna every request fails); `truststore.inject_into_ssl()` disables it.

**Certificates and keystores:** no change for `load_cert_chain`, `cafile`, certifi or `REQUESTS_CA_BUNDLE`. gunicorn with an encrypted key file fails every worker: use an `ssl_context` hook. **ML-DSA:** works on OpenSSL 3.5 images (Debian 13, Alpine) and through the 3.9 to 3.11 shim; AL2023 also needs `SignatureAlgorithms` (`openssl-pq-mldsa.cnf` or `DEFAULT:PQ`).

**Rollback:** remove `OPENSSL_CONF` (or `PQ_TLS_DISABLE=1` with the layer). **Detect:** CloudTrail for AWS calls; log `SSLSocket.group()` on Python 3.15+.

**Tested:** 59 client cases (Lambda 35, Fargate 13, ECS on EC2 3, EC2 8) and 6 load balancer target cases, all passing.
