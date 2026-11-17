# Node.js

**What decides PQ.** Official Node.js binaries bundle their own OpenSSL: 22.20+ and 24.5+ ship OpenSSL 3.5 and are PQ by default (use 24.9+ as the policy floor, as AWS does). On Lambda, the runtime's bootstrap sets `OPENSSL_CONF` to a file whose group list has no ML-KEM, so Lambda Node is classical until that file is overridden. Official Node 18 and 20 bundle OpenSSL without ML-KEM (3.0 in `node:20` images; 3.1 and 3.2 on Lambda `nodejs18.x` and `nodejs20.x`). Distro Node links the system OpenSSL, so AL2023 `dnf` Node, even `nodejs20`, is fixable with the system policy or config.

| Compute | PQ today? | What to change |
| --- | --- | --- |
| Lambda nodejs22.x, nodejs24.x | No (bootstrap config) | Ship `openssl-pq-node.cnf`, set `OPENSSL_CONF` to it (or the `pq-tls` layer). Prefer 24: `nodejs22.x` updates are blocked from 2027-08-31 |
| Lambda nodejs26.x (preview) | Not sure: the base image is PQ unless `AWS_LAMBDA_TLS_PROFILE=aws` selects its classical profile (Docker test only) | Set `OPENSSL_CONF` as for 22 and 24 |
| Lambda nodejs18.x, nodejs20.x | No, and no setting helps | Upgrade before 2027-08-31; interim, the `pq-egress` extension for calls that must be PQ |
| Fargate, ECS on EC2, EKS | Official `node` images 22.20+ and 24.5+: yes. AL2023 `dnf` Node: no | Official image 24.9+; AL2023 `dnf` Node: `DEFAULT:PQ` in the Dockerfile or `OPENSSL_CONF` (EKS not tested) |
| EC2 | Official binaries: yes. AL2023 `dnf` Node: no | Official binaries, or `DEFAULT:PQ` / a per-service `OPENSSL_CONF` for `dnf` Node |

**What to change, in order**

1. Lambda: ship the override file and variable. Our file replaces AWS's rather than including it, so add a pipeline check that diffs AWS's file against ours on each new runtime image.
2. Upgrade Node 18 and 20; don't put X25519MLKEM768 first in `ecdhCurve` on bundled Node 20: it crashes.
3. Remove explicit `ecdhCurve` lists and TLS 1.2 maximums, or add X25519MLKEM768 to them.

**Certificates and keystores:** no change for key/cert, modern PFX, `ca` or `NODE_EXTRA_CA_CERTS`. Legacy RC2 or 3DES PFX files fail on every current runtime: re-export them. The Lambda image has an empty system CA store: set `SSL_CERT_FILE`. **ML-DSA:** Node on OpenSSL 3.5 (Lambda 22 and 24 even unfixed, official 22.20+/24.5+ images, fixed AL2023 Node) negotiates ML-DSA on all three targets; unfixed AL2023 Node and Node 20 get ECDSA.

**Rollback:** remove `OPENSSL_CONF` (or `PQ_TLS_DISABLE=1` with the layer). **Detect:** CloudTrail for AWS calls; application handshake logs.

**Tested:** 93 client cases (Lambda 48, Fargate 28, ECS on EC2 5, EC2 12) and 7 load balancer target cases, all passing (LocalStack, run r1117041043; not yet on real AWS).
