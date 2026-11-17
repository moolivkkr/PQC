# Python

## Problem statement

A Python service on the wrong base image or runtime negotiates classical X25519 or P-256 with no ML-KEM, so traffic it sends or receives can be recorded now and decrypted later by a quantum computer (harvest-now-decrypt-later). Nothing fails, so nobody notices.

Python has no PQ switch of its own. The TLS library each package uses decides, and every package belongs to one of two families:

| Family | Packages | Who decides the key exchange | PQ when | Evidence |
|----|----|----|----|----|
| **`ssl` family**: linked to the system OpenSSL through the `ssl` module | `ssl`, `http.client`, `urllib`, requests, urllib3, boto3/botocore (default path), httpx, aiohttp, redis-py, PyMySQL, uvicorn, gunicorn, hypercorn, and Flask/Django/FastAPI behind them | The OpenSSL the interpreter links (base image, Lambda runtime or host) plus its config (`OPENSSL_CONF`, the AL2023 crypto policy) | OpenSSL 3.5+ and the config keeps ML-KEM in the group list | Tested |
| **Bundled-TLS wheels**: carry their own TLS library | grpcio (BoringSSL), awscrt (s2n-tls + AWS-LC), confluent-kafka (static OpenSSL 3.5.8 in librdkafka 2.16.0), psycopg `[binary]` and psycopg2-binary (own libpq + libssl), pyOpenSSL (the OpenSSL in the cryptography wheel) | The wheel version | Already PQ in current wheels on every base image tested, including Debian 12 with OpenSSL 3.0 | Tested |

So the first question for any service is which family each connection uses: a requests call on Debian 12 is classical while a grpcio call from the same container is PQ. The fix is almost always a base-image change, one file plus one environment variable, or a runtime upgrade. Certificates, key files, PKCS#12 stores and CA bundles do not change, because key exchange is negotiated apart from the certificate (cases C and D, Tested).

Python 3.15 (released 9 Oct 2026, [python.org](https://www.python.org/downloads/release/python-3150/)) adds `SSLContext.set_groups()`, `get_groups()` and `SSLSocket.group()` ([3.15 ssl docs](https://docs.python.org/3.15/library/ssl.html#ssl.SSLContext.set_groups), Documented and Tested). Earlier versions have no group API; `set_ecdh_curve("X25519MLKEM768")` raises `ValueError: unknown elliptic curve name` on 3.12, 3.13 and 3.15 (Tested).

## Quick start by compute type

Find your row, make the one change, verify, and keep the rollback. Everything here is for the `ssl` family; bundled-TLS wheels need only a current version on every row. All "Tested" rows ran in the e2e suite (run r1117041043) or in Lambda base images; none ran on real AWS.

| Compute type | Check | PQ today? | The one change | Verify | Roll back | Evidence |
|----|----|----|----|----|----|----|
| Lambda zip, python3.12, 3.13, 3.14 | `Runtime` in the IaC | No: OpenSSL 3.5.8, but the AL2023 crypto policy omits ML-KEM | Ship `pq-tls/openssl-pq.cnf` in the package, set `OPENSSL_CONF=/var/task/pq-tls/openssl-pq.cnf`. Fleet option: the `pq-tls` layer with `AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper` | `pq_probe.py` against a PQ-only server succeeds; CloudTrail `tlsDetails.keyExchange = X25519MLKEM768` for KMS, STS, Secrets Manager calls | Remove `OPENSSL_CONF` (layer: `PQ_TLS_DISABLE=1`) | Tested (e2e) |
| Lambda zip, python3.15 (public preview) | as above | No, same as 3.14 | Same file and variable; or in code `ctx.set_groups("X25519MLKEM768:X25519")`. Preview runtimes are outside the Lambda SLA ([Lambda runtimes](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html)) | as above, plus `SSLSocket.group()` in logs | Remove the variable or the call | Tested (Lambda 3.15 base image, not in e2e) |
| Lambda zip, python3.9, 3.10, 3.11 | `Runtime` in the IaC | No: Amazon Linux 2, OpenSSL 1.1.1zb, no setting helps | Upgrade the runtime to python3.13. Bridge until then: the shim (`PYTHONPATH=/var/task/pq-tls/pyshim` plus pyOpenSSL, cryptography **and idna**), or the `pq-tls` layer. Covers urllib3, requests and boto3 only | CloudWatch log line `pq-tls: python legacy shim: urllib3 -> pyOpenSSL`; PQ-only probe succeeds | Remove `PYTHONPATH` (layer: `PQ_TLS_DISABLE=1`) | Tested (e2e) |
| Lambda container image | `FROM public.ecr.aws/lambda/python:3.x` | No (3.12+), as the zip | `COPY` the file and `ENV OPENSSL_CONF=/var/task/pq-tls/openssl-pq.cnf` in the Dockerfile | Run `pq_probe.py` in the built image in CI | Redeploy the previous image digest, or override `OPENSSL_CONF` in the function variables | Tested (e2e, 3.12 and 3.13) |
| ECS on Fargate | `FROM` line; `python3 -c "import ssl; print(ssl.OPENSSL_VERSION)"` in the image | `python:*-slim-trixie`, `python:*-alpine`: yes. `-bookworm`, Ubuntu 24.04, AL2023: no | Move to `python:3.13-slim-trixie` or `-alpine`. On AL2023: `ENV OPENSSL_CONF=/etc/pq-tls/openssl-pq.cnf` (or the task definition) or `update-crypto-policies --set DEFAULT:PQ` in the Dockerfile | PQ-only probe in CI; server: `probe-server.sh app:8443` | Redeploy the previous image digest; remove the task-definition variable | Tested (e2e) |
| ECS on EC2, EKS | as Fargate: the image decides, not the node | as Fargate | as Fargate; on EKS the variable goes in the pod spec `env` | as Fargate | as Fargate | ECS on EC2: Tested (e2e). EKS: not run; same images |
| EC2, Amazon Linux 2023 | `update-crypto-policies --show`; `python3.X -c "import ssl; print(ssl.OPENSSL_VERSION)"` | No: OpenSSL 3.5.8, policy `DEFAULT` omits ML-KEM | One service: `Environment=OPENSSL_CONF=/etc/pq-tls/openssl-pq.cnf` in its systemd unit. Whole host: `update-crypto-policies --set DEFAULT:PQ` through SSM, then restart services | PQ-only probe on the host; CloudTrail | Remove the drop-in, or `update-crypto-policies --set DEFAULT`, then restart | Tested (e2e, python3.11 to 3.14) |
| EC2, Amazon Linux 2 | `cat /etc/os-release` | No, and cannot be: python3.7 with OpenSSL 1.0.2k, TLS 1.2 only | Migrate the host to AL2023 (AL2 end of life 30 Jun 2026, [Lambda runtimes](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html)) | n/a | n/a | Tested (e2e) |
| EC2, Ubuntu 24.04 or Debian 12 | as above | No: OpenSSL 3.0 | Run the service in a trixie or alpine container, or move the OS | PQ-only probe | Previous AMI or image | Debian 12: Tested. Ubuntu 24.04: Documented (ships OpenSSL 3.0) |

Two rules apply on every row:

- If the function, image or unit already sets `OPENSSL_CONF`, merge the `Groups` line from `openssl-pq.cnf` into that file. The layer leaves an existing `OPENSSL_CONF` alone, so such a function stays classical (Tested, e2e `py-lambda-py312-layer-ownconf`).
- Don't use `OPENSSL_CONF=/dev/null`. It does turn PQ on (Tested 2026-11-16, Lambda python3.12 and 3.15 images), but it drops the whole AL2023 crypto policy, not just the group list (in the Lambda python3.12 image the default context lost `TLS_AES_128_CCM_SHA256` and the policy's TLS 1.3 maximum: [tests/lambda/baseline-default.json](REPO/tests/lambda/baseline-default.json) against [baseline-devnull.json](REPO/tests/lambda/baseline-devnull.json)).

Lambda deadlines: python3.9 was deprecated on 15 Dec 2025, python3.10 on 31 Oct 2026, and python3.11 is deprecated on 30 Jun 2027. Function creation is blocked from 29 Jul 2027 and updates from 31 Aug 2027 for all three ([Lambda runtimes](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html), Documented). After that no file, layer or variable can be added, so these functions move first.

## Versions and native support

PQ depends on the OpenSSL under Python, so the same Python version gives different answers on Lambda, in a container and on EC2.

| Version | `ssl`-family OpenSSL | PQ by default (client and server) | Group API | Proposed solution | Evidence |
| --- | --- | --- | --- | --- | --- |
| 3.9, 3.10, 3.11 | Lambda: 1.1.1zb (AL2). AL2023 (EC2, containers): 3.5.8. trixie: 3.5.7 | Lambda: no. AL2023: no. trixie: yes | None; `set_ecdh_curve` takes one classical curve only | Lambda: upgrade to python3.12+; bridge with the shim (requests, boto3 only). AL2023: the config or `DEFAULT:PQ`. Containers: trixie or alpine base | Tested (Lambda 3.9 to 3.11, AL2023 3.11, trixie 3.11) |
| 3.12, 3.13, 3.14 | Lambda and AL2023: 3.5.8. trixie: 3.5.7. alpine 3.24: 3.5.9. bookworm: 3.0.22 | Lambda, AL2023: no (crypto policy). trixie, alpine: yes. bookworm: no | None | Lambda and AL2023: `OPENSSL_CONF=openssl-pq.cnf` or `DEFAULT:PQ`. bookworm: move to trixie | Tested |
| 3.15 (Lambda: public preview) | As 3.12 | As 3.12 | `SSLContext.set_groups()`, `get_groups()`, `SSLSocket.group()` | Platform fix as 3.12; `set_groups("X25519MLKEM768:X25519")` also works without the file; log `group()` | Tested (trixie 3.15, Lambda 3.15 image) |
| Bundled-TLS wheels, any version | BoringSSL, s2n-tls, static OpenSSL 3.5.8, own libssl, cryptography's OpenSSL 4.0.3 | Yes; grpcio server also yes | Library-specific (`ssl.curves.list`, `TlsCipherPref`) | Keep wheels current | Tested |

FIPS mode for the `ssl` family (AL2023 in FIPS mode, or a FIPS OpenSSL provider) was not tested; see case G.

### By library (does the client offer ML-KEM to a PQ-only server?)

| Library | Lambda 3.11 (AL2) | Lambda 3.14 | Lambda 3.14 + conf | trixie 3.13 / 3.15 | bookworm 3.12 | AL2023 3.12 | AL2023 3.12 + conf |
|----|----|----|----|----|----|----|----|
| `ssl`, `http.client`, `urllib`, requests, urllib3, botocore, httpx, aiohttp, redis-py | No | No | Yes | Yes | No | No | Yes |
| urllib3 + `inject_into_urllib3()` (pyOpenSSL) | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| pyOpenSSL 26.4.0 | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| awscrt 0.38.1 (default and `PQ_DEFAULT`) | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| grpcio 1.85.1 client | Yes | Yes | Yes | Yes (3.13) | Yes | Yes | Yes |
| psycopg 3.3.9 binary, psycopg2-binary 2.9.13 | Yes | Yes | Yes | Yes (3.13) | Yes | Yes | Yes |
| confluent-kafka (librdkafka 2.16.0) | No wheel installed | Yes | Yes | Yes (3.13) | Yes | Yes | Yes |

All cells Tested on 2026-11-14 in containers (arm64) against an OpenSSL 3.5.7 `s_server` limited to X25519MLKEM768 and one limited to X25519 ([tests/deep/python/run-python.sh](REPO/tests/deep/python/run-python.sh), outputs in [tests/deep/python/out](REPO/tests/deep/python/out)). Every library also connected to the classical-only server, so fallback works. For grpcio, Kafka and Redis the server log confirmed `Peer Temp Key: X25519MLKEM768`; PostgreSQL drivers were tested against PostgreSQL 18.7 with `ssl_groups = 'X25519MLKEM768'`.

Gaps: on the Lambda python3.11 image pip found no confluent-kafka wheel. On Python 3.15 (trixie and the Lambda image) pip chose `confluent-kafka 4.4.0b1`, whose build failed to import, so Kafka is untested on 3.11 Lambda and on 3.15. The Lambda 3.15 image otherwise matched Lambda 3.14.

## Cases: what to change

Unless a row says otherwise, results here were Tested on 2026-11-14 in containers (arm64) on Debian 13 trixie with Python 3.12.16 and 3.13.18 (OpenSSL 3.5.7, no setting), Amazon Linux 2023 with Python 3.12.15 and `OPENSSL_CONF` (OpenSSL 3.5.8), and the Lambda `python:3.11` image with the shim (clients only). Test servers are OpenSSL 3.5.7 `s_server` instances: PQ-only (`-groups X25519MLKEM768 -tls1_3`), classical-only (`-groups X25519`), and the same pair requiring a client certificate. A client that reaches the PQ-only server has proved it offered X25519MLKEM768. Python servers were probed with `openssl s_client`, which printed `Negotiated TLS1.3 group: X25519MLKEM768`. Scripts and outputs: [tests/deep/python/v2](REPO/tests/deep/python/v2) (`run-v2.sh`, `cases.py`, `servers.py`, `out/d312.txt`, `out/d313.txt`, `out/al-conf.txt`, `out/l311-shim.txt`).

### A. Simple client

**Who this is:** code that calls requests, boto3, httpx, aiohttp, urllib or a DB/queue driver with default TLS settings; `grep -rnE "ssl\.|SSLContext|verify=|cert=" src/` finds nothing unusual.

**What to change:** the platform fix only (Quick start). No code change. Code is needed only to pin the group list (3.15+) or to log the negotiated group.

| Library (tested version) | TLS stack | What to set | Evidence |
|----|----|----|----|
| `ssl`, `http.client`, `urllib.request` (3.12, 3.13, 3.15) | System OpenSSL | Nothing. On 3.15+ you may call `ctx.set_groups("X25519MLKEM768:X25519")`; `"X25519MLKEM768"` alone refuses classical servers | Tested |
| requests 2.34.2, urllib3 2.8.0 | System OpenSSL via `ssl` | Nothing. To pin groups on 3.15, pass a context through an `HTTPAdapter` (below) | Tested |
| boto3 / botocore 1.44.3 (default HTTP path) | System OpenSSL via `ssl` | Nothing. botocore builds its own `SSLContext`, so `inject_into_urllib3()` alone does not reach it; the Lambda shim patches both | Tested |
| awscrt 0.38.1 (`boto3[crt]`, S3 transfer manager) | s2n-tls, bundled | Nothing: the default policy offered ML-KEM; `TlsCipherPref.PQ_DEFAULT` also works. `PQ_TLSv1_0_2021_05` raises `AWS_IO_TLS_CIPHER_PREF_UNSUPPORTED`. The FIPS policy `TLSv1_2_2025_07` allows only P-256/P-384 per its docstring | Tested; FIPS policy from the docstring |
| httpx 0.28.1 | System OpenSSL via `ssl` | Nothing. To pin on 3.15: `httpx.Client(verify=ctx)` | Tested |
| aiohttp 3.14.5 | System OpenSSL via `ssl` | Nothing. To pin on 3.15: `session.get(url, ssl=ctx)` | Tested |
| pyOpenSSL 26.4.0 | cryptography wheel's OpenSSL (4.0.3) | Nothing; PQ even on Debian 12 and AL2023 without the config | Tested |
| grpcio 1.85.1 (client) | BoringSSL, bundled | Nothing. ClientHello listed `X25519MLKEM768:x25519:secp256r1:secp384r1:secp521r1` on every image. No Python group setting; `OPENSSL_CONF` has no effect | Tested |
| psycopg 3.3.9 `[binary]` (libpq 18), psycopg2-binary 2.9.13 (libpq 17) | libpq + libssl bundled | Nothing; use `sslmode=verify-full`. Connected to PostgreSQL 18 with `ssl_groups = 'X25519MLKEM768'` on every image | Tested |
| psycopg or psycopg2 built from source, mysqlclient | System libpq / client library and OpenSSL | Platform fix, as for the `ssl` family | Unverified (follows from linkage) |
| PyMySQL | System OpenSSL via `ssl.create_default_context` (read from source) | Platform fix; the MySQL server must also offer ML-KEM | Source read; handshake not tested |
| redis-py 8.1.0 | System OpenSSL via `ssl` | Platform fix (`ssl=True`, `ssl_ca_certs`) | Tested |
| confluent-kafka 2.x (librdkafka 2.16.0) | OpenSSL 3.5.8, static in the wheel | Nothing. `ssl.curves.list=X25519MLKEM768:X25519` also works. The broker or Amazon MSK must also accept ML-KEM | Tested (client); MSK not tested |

Pin the group list for requests on Python 3.15+ (most services do not need this):

``` python
import ssl, requests
from requests.adapters import HTTPAdapter

class PQAdapter(HTTPAdapter):
    def init_poolmanager(self, *args, **kwargs):
        ctx = ssl.create_default_context()
        ctx.set_groups("X25519MLKEM768:X25519")  # 3.15+; omit X25519 to refuse classical
        kwargs["ssl_context"] = ctx
        return super().init_poolmanager(*args, **kwargs)

s = requests.Session()
s.mount("https://", PQAdapter())
```

Log the negotiated group once per dependency at startup (3.15+): `log.info("tls", extra={"host": host, "group": tls_sock.group()})`.

### B. Simple server

**Who this is:** uvicorn, gunicorn, hypercorn or a grpcio server that terminates TLS in the Python process: an HTTPS target group, an NLB TCP passthrough, in-VPC service-to-service, or gRPC. If an ALB, NLB TLS listener, API Gateway or CloudFront terminates TLS, that service's security policy sets the client-facing key exchange, not Python (guide chapters: Load balancers, Edge and API front doors).

**What to change:** the platform fix only. Python servers accept ML-KEM whenever the linked OpenSSL is 3.5+ with ML-KEM in its group list; no server flag is needed. A server without ML-KEM still serves PQ-capable clients over X25519, so the failure is silent.

| Server (tested version) | TLS stack | trixie 3.13 / 3.15 | bookworm 3.12 | AL2023 3.12 | AL2023 + `OPENSSL_CONF` | Group control in code |
|----|----|----|----|----|----|----|
| uvicorn 0.54.0 (`--ssl-certfile`) | System OpenSSL | PQ | Classical only | Classical only | PQ | 3.15+: build `Config`, call `config.load()`, then `config.ssl.set_groups(...)` (Tested) |
| gunicorn 27.0.1 (`certfile`) | System OpenSSL | PQ | Classical only | Classical only | PQ | 3.15+: `ssl_context` hook calling `set_groups` (Tested) |
| hypercorn 0.18.0 (`--certfile`) | System OpenSSL | PQ | Classical only | Classical only | PQ | No hook checked; platform only |
| grpcio 1.85.1 (`ssl_server_credentials`) | BoringSSL, bundled | PQ | PQ | PQ | PQ | None needed |

All rows Tested with `openssl s_client -groups X25519MLKEM768 -tls1_3` and `-groups X25519`. "Classical only" means the PQ-only client was refused with a handshake alert; classical clients connected in every cell.

- uvicorn `--ssl-ciphers` and gunicorn `ciphers` set TLS 1.2 cipher suites only; they do not affect groups (Tested).
- **Enforcing PQ-only** (refusing classical clients) needs Python 3.15 `set_groups("X25519MLKEM768")`. Tested for gunicorn and uvicorn; on 3.12 and 3.13 the same hook is a no-op. Only do this on internal endpoints whose every client you control.
- **Flask** `app.run(ssl_context=ctx)` takes an `SSLContext` ([Werkzeug docs](https://werkzeug.palletsprojects.com/en/stable/serving/), Documented), so `set_groups` should work on 3.15; not tested. Not for production. **Django** `runserver` has no TLS; production Django and FastAPI run under the servers above.
- **Behind an ALB or NLB TLS listener** (e2e, load balancer modelled as the client on the target leg): an `ssl`-module HTTPS target on AL2023 Python 3.12 or `python:3.12-slim-bookworm` stayed classical; `OPENSSL_CONF`, `DEFAULT:PQ` or `python:3.13-slim-trixie` gave X25519MLKEM768 with the same certificate. The classic backend leg stayed TLS 1.2 in every case (Tested, cases `srv-python-*`).

`gunicorn.conf.py` hook (full file at the end):

``` python
def ssl_context(conf, default_ssl_context_factory):
    ctx = default_ssl_context_factory()
    if hasattr(ctx, "set_groups"):  # Python 3.15+
        ctx.set_groups(os.environ.get("PQ_GROUPS", "X25519MLKEM768:X25519:secp256r1"))
    return ctx
```

### C. Existing server certificates and key files

**Who this is:** a Python server that loads its own certificate and key. Find it with:

```bash
grep -rnE "load_cert_chain|ssl[-_]keyfile|ssl[-_]certfile|--keyfile|--certfile|keyfile *=|certfile *=|ssl_server_credentials|pkcs12|\.p12|\.pfx" .
```

**What changes in the store: nothing.** The certificate and key sign the handshake; ML-KEM changes only the key exchange. The same RSA or EC certificate, encrypted key and PKCS#12 file negotiated X25519MLKEM768 once the platform fix was in place. Do not re-issue certificates for PQ key exchange; ML-DSA certificates are a separate, later step (guide chapter: Certificates (ML-DSA)).

**What to change:** the platform fix only. Two exceptions, neither about PQ:

- **gunicorn with an encrypted key.** gunicorn has no key-password option. The master reports `Listening at: https://...`, but every worker fails with `OSError: [Errno 22] Invalid argument` and clients get `unexpected eof` (Tested). Load the key in the `ssl_context` hook with the password from the environment (full `gunicorn-enc.conf.py` at the end):

  ```python
  def ssl_context(conf, default_ssl_context_factory):
      ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)  # the factory loads the key without a password
      ctx.load_cert_chain(conf.certfile, conf.keyfile, password=os.environ["TLS_KEY_PASSWORD"])
      return ctx
  ```

- **PKCS#12 / PFX.** The `ssl` module cannot read PKCS#12, and pyOpenSSL 26.4.0 no longer has `crypto.load_pkcs12` (Tested). Convert with cryptography's `pkcs12.load_key_and_certificates()` at startup (`p12_to_pem.py` at the end) to a tmpfs path readable only by the service user, or once at build time with `openssl pkcs12 -in server.p12 -nodes -out server.pem` (key mode 0600; add `-aes256` and `load_cert_chain(..., password=...)` to keep it encrypted).

**Tested proof** (`out/d312.txt`, `out/d313.txt`, `out/al-conf.txt`; each row: a PQ-only client negotiated X25519MLKEM768 and an X25519-only client still connected):

| Server and store | Cert served | Result with the platform fix |
| --- | --- | --- |
| `ssl.SSLContext` + `load_cert_chain`, RSA 2048 PEM / EC P-256 PEM | RSA / EC | X25519MLKEM768; classical client OK |
| `load_cert_chain(..., password=...)` (string or callable), encrypted RSA and EC | RSA / EC | X25519MLKEM768; classical client OK |
| RSA and EC in one context (two `load_cert_chain` calls) | EC to an ECDSA-only client, RSA to an RSA-only client | X25519MLKEM768 for both |
| SNI: `sni_callback` swaps to a second EC cert | The cert for the requested name | X25519MLKEM768 |
| PKCS#12 converted to PEM with cryptography 50.0.2 | EC | X25519MLKEM768; classical client OK |
| uvicorn 0.54.0 `--ssl-certfile/--ssl-keyfile`, plain and `--ssl-keyfile-password` | RSA / EC | X25519MLKEM768; classical client OK |
| gunicorn 27.0.1 `--certfile/--keyfile`, plain key | RSA / EC | X25519MLKEM768; classical client OK |
| gunicorn `--keyfile` with an encrypted key | none | Workers fail (`OSError: [Errno 22]`); not a PQ issue |
| gunicorn encrypted key through the `ssl_context` hook | EC | X25519MLKEM768; classical client OK |

On Debian 12 and on AL2023 without the config the same servers were classical-only (`tests/deep/python/out/b312.txt`, `out/al.txt`): the certificate never made a difference. grpcio servers were PQ on every image. Not tested: hypercorn with an encrypted key, HSM or KMS keys (case I), Windows.

### D. Custom CA trust (private CA, custom bundle, system store)

**Who this is:** a client that trusts a private CA (AWS Private CA, an internal root, a TLS-inspecting proxy root). Find it with:

```bash
grep -rnE "REQUESTS_CA_BUNDLE|SSL_CERT_FILE|SSL_CERT_DIR|AWS_CA_BUNDLE|CURL_CA_BUNDLE|cafile=|capath=|load_verify_locations|verify=['\"/]|certifi|truststore|ca_certs|root_certificates|GRPC_DEFAULT_SSL_ROOTS_FILE_PATH" . ; env | grep -E "CA_BUNDLE|SSL_CERT"
```

Also check Dockerfiles for `update-ca-certificates`, `update-ca-trust` or a PEM appended to certifi's `cacert.pem`.

**What changes in the trust store: nothing.** Trust decides which server certificates are accepted; key exchange is negotiated apart from it. Every method below kept working against the PQ-only server once the platform fix was in place.

**What to change:** the platform fix only. Two things that are not PQ issues often surface during the change:

- requests ignores `SSL_CERT_FILE` and the OS store; it uses certifi unless `REQUESTS_CA_BUNDLE`, `verify=` or truststore says otherwise. httpx 0.28.1 honours `SSL_CERT_FILE` but not the OS store (both Tested).
- A base-image move (bookworm to trixie, or to AL2023) resets the OS store. Re-add the CA in the new Dockerfile: Debian/Ubuntu/Alpine `COPY corp-root.pem /usr/local/share/ca-certificates/corp-root.crt` + `RUN update-ca-certificates`; AL2023 `COPY corp-root.pem /etc/pki/ca-trust/source/anchors/` + `RUN update-ca-trust extract`. A CA appended to certifi is lost on every `pip install -U certifi`; prefer `REQUESTS_CA_BUNDLE` or truststore.

**Tested proof, platform fix in place** (Debian 13 3.12 and 3.13, AL2023 3.12 + `OPENSSL_CONF`). OK = reached both the PQ-only and the classical-only server:

| Trust method | Result |
| --- | --- |
| `ssl.create_default_context(cafile=ca.pem)`, `SSL_CERT_FILE=ca.pem`, CA in the OS store | OK |
| requests `REQUESTS_CA_BUNDLE=ca.pem`, `verify="ca.pem"`, certifi with the CA appended | OK |
| requests with `SSL_CERT_FILE` only, or CA only in the OS store | Fails verification on both servers: requests uses certifi (expected, not PQ) |
| `truststore.inject_into_ssl()` (0.10.5) + requests, CA in the OS store; `truststore.SSLContext(...)` | OK |
| httpx `verify=ssl.create_default_context(cafile=...)`, httpx with `SSL_CERT_FILE` | OK |
| httpx with CA only in the OS store | Fails verification (uses certifi; expected) |
| aiohttp `ssl=ssl.create_default_context(cafile=...)` | OK |
| boto3 `AWS_CA_BUNDLE=ca.pem` (endpoint pointed at the test server) | TLS OK on both servers (the API call then times out: the server is not STS) |
| Negative control: requests with stock certifi | Fails verification (proves verification was on) |

On Lambda python3.9 to 3.11 with the shim, `REQUESTS_CA_BUNDLE`, `verify=`, an appended certifi and boto3 `AWS_CA_BUNDLE` all keep working, but **`truststore.inject_into_ssl()` turns the shim off for requests** (case J).

### E. Mutual TLS (client certificates)

**Who this is:** a client that presents a certificate, or a server that requires one. `grep -rnE "cert=\(|load_cert_chain|client_cert|ssl-cert-reqs|cert_reqs|CERT_REQUIRED|ssl_channel_credentials|require_client_auth" .`

**What to change:** the platform fix only; client certificates and keys are unaffected. With the fix every row completed mTLS against a PQ-only server requiring a client certificate and against a classical-only one (Tested).

| Client or server | Setting | Result |
| --- | --- | --- |
| requests | `cert=("client.pem", "client.key")`, `verify=ca` | OK; without a cert: `TLSV13_ALERT_CERTIFICATE_REQUIRED` |
| `ssl`, httpx 0.28.1, aiohttp 3.14.5 | `ctx.load_cert_chain(crt, key[, password=...])` passed as the context | OK, including an encrypted key |
| boto3 | `Config(client_cert=(crt, key))` + `AWS_CA_BUNDLE` | TLS OK (the API call then times out on the test server) |
| grpcio 1.85.1 client | `grpc.ssl_channel_credentials(root, key, chain)` | Server log: `Peer Temp Key: X25519MLKEM768`, `Verification: OK` |
| `ssl` server | `verify_mode=CERT_REQUIRED` + `load_verify_locations(ca)` | X25519MLKEM768 with the client cert |
| uvicorn / gunicorn | `--ssl-cert-reqs 2 --ssl-ca-certs ca.pem` / `--cert-reqs 2 --ca-certs ca.pem` | X25519MLKEM768 with the client cert |

requests cannot take a password for an encrypted client key; build an `ssl` context or use httpx. PKCS#12 client stores: convert as in case C.

### F. Explicit TLS settings that block PQ

**Who this is:** code or config that sets TLS versions, curves or ciphers by hand. Find it with `ci/pq-tls-lint.sh` (full file at the end) or:

```bash
grep -rnE "set_ecdh_curve|maximum_version|ssl_maximum_version|OP_NO_TLSv1_3|PROTOCOL_TLSv1|set_ciphers|ssl[-_]ciphers|set_groups|ssl\.curves\.list|OPENSSL_CONF" .
```

| Setting | PQ-only peer | Classical peer | Change it to | Evidence |
| --- | --- | --- | --- | --- |
| `ctx.set_ciphers("ECDHE+AESGCM:...")`, uvicorn `--ssl-ciphers`, gunicorn `ciphers` | OK, X25519MLKEM768 | OK | Nothing (TLS 1.2 suites only) | Tested |
| `ctx.minimum_version = TLSVersion.TLSv1_3` | OK | OK | Nothing | Tested |
| `ctx.maximum_version = TLSVersion.TLSv1_2`, `ctx.options \|= ssl.OP_NO_TLSv1_3`, `ssl.SSLContext(ssl.PROTOCOL_TLSv1_2)`, urllib3 `ssl_maximum_version=TLSv1_2` (client) | Fails: `TLSV1_ALERT_PROTOCOL_VERSION` | OK, TLS 1.2 | Remove it; use `ssl.create_default_context()` or `PROTOCOL_TLS_CLIENT` / `PROTOCOL_TLS_SERVER` | Tested |
| `ctx.maximum_version = TLSv1_2` (server) | Fails | Fails for a TLS 1.3-only client | Remove it | Tested |
| `ctx.set_ecdh_curve("prime256v1")` (client or server) | Fails: handshake failure | Fails against an X25519-only peer too | Remove it | Tested |
| `ctx.set_ecdh_curve("X25519")` | Fails | OK | Remove it | Tested |
| `ctx.set_ecdh_curve("X25519MLKEM768")` | `ValueError: unknown elliptic curve name` | same | Use `set_groups` on 3.15+, else the platform | Tested |
| `ctx.set_groups(...)` (3.15+) or confluent-kafka `ssl.curves.list` without an ML-KEM group | Fails | OK | Put `X25519MLKEM768` first, keep `X25519` | `set_groups` replacing the whole list Tested (`tests/deep/python/out/t315.txt`); the `"X25519"`-only string not run |
| A custom `OPENSSL_CONF` without a `Groups` line on AL2023 or Lambda | Classical | OK | Merge the `Groups` line from `openssl-pq.cnf` | Tested (e2e `py-lambda-py312-layer-ownconf`) |
| `OPENSSL_CONF=/dev/null` on AL2023 or Lambda | OK, X25519MLKEM768 | OK | Point it at `openssl-pq.cnf` instead: `/dev/null` drops the whole crypto policy | Tested 2026-11-16 (Lambda python3.12 and 3.15 images) |

`set_ecdh_curve` is the trap: on OpenSSL 3 it replaces the whole group list with one classical curve, so it removes ML-KEM on every platform, client or server. The Python docs say it "doesn't apply to client sockets" ([ssl docs](https://docs.python.org/3.15/library/ssl.html#ssl.SSLContext.set_ecdh_curve)), but in the tests it did change the client's offer. Old code often has it from TLS 1.2 tuning. Removing these settings keeps TLS 1.2-only peers working, because the defaults still allow TLS 1.2.

### G. FIPS mode

**Who this is:** AL2023 with FIPS mode enabled (`fips-mode-setup --check`), images with a FIPS OpenSSL provider, awscrt with a FIPS policy, or FIPS AWS endpoints.

**What happens today:** not tested for the `ssl` family; whether the AL2023 FIPS provider offers ML-KEM is not confirmed here (guide chapter: Hosts and OS). awscrt's FIPS policy `TLSv1_2_2025_07` lists only P-256 and P-384 in its docstring, so no PQ. Whether FIPS AWS endpoints accept ML-KEM was not checked here: not sure.

**What to change:** nothing in Python. Treat FIPS paths as classical until the platform team confirms ML-KEM in the FIPS provider, and record them as exceptions.

### H. Libraries with their own TLS stack

**Who this is:** grpcio, awscrt, confluent-kafka, psycopg `[binary]`, psycopg2-binary, pyOpenSSL. `pip list | grep -Ei '^(grpcio|awscrt|confluent-kafka|psycopg|psycopg2-binary|pyopenssl|cryptography) '`.

**What happens today:** PQ on every base image, including Debian 12 and AL2023 without the config (Tested, library table). The platform fix has no effect on them, and `OPENSSL_CONF` does not reach BoringSSL or s2n.

**What to change:** keep the wheels current. Building from source (`psycopg[c]`, `psycopg2`, `mysqlclient`) links the system OpenSSL and follows the `ssl` family (Unverified, from linkage). grpcio custom trust goes through `root_certificates=` or `GRPC_DEFAULT_SSL_ROOTS_FILE_PATH`, not `SSL_CERT_FILE`.

**Side effect:** one process can be PQ on gRPC and classical on requests at the same time. Inventory by library, not by service.

### I. Pinning, HSM/PKCS#11 and KMS-backed keys

- **Certificate pinning:** unaffected. A pin on the SHA-256 of the peer certificate matched on the PQ-only server (Tested). Re-pin only when certificates change, for example to ML-DSA.
- **HSM / PKCS#11 / KMS keys:** the `ssl` module cannot use them without an OpenSSL provider (for example pkcs11-provider) or a TLS-terminating proxy. The key only signs; ML-KEM is done in software, so PQ should not change this (Unverified, not tested).

### J. Other cases

**Lambda 3.9 to 3.11 shim with custom trust or mTLS** (Lambda `python:3.11` image, OpenSSL 1.1.1zb, `PYTHONPATH=/kit/pyshim`; Python 3.11.18, cryptography 50.0.2 with OpenSSL 4.0.3, pyOpenSSL 26.4.0, truststore 0.10.5; Tested 2026-11-14, `out/l311-shim.txt`):

| Path | PQ-only server | Classical server | Note |
| --- | --- | --- | --- |
| requests with `REQUESTS_CA_BUNDLE`, `verify=`, appended certifi, or `cert=(crt, key)` | OK | OK | Shim log: `urllib3 -> pyOpenSSL (OpenSSL 4.0.3 ...)` |
| boto3 `AWS_CA_BUNDLE`, `Config(client_cert=...)` | TLS OK | TLS OK | Shim log: `botocore -> pyOpenSSL` |
| grpcio mTLS | OK (`Peer Temp Key: X25519MLKEM768`) | | BoringSSL; no shim needed |
| **truststore `inject_into_ssl()` + requests** | **Fails** | OK | truststore puts requests back on the stdlib context (OpenSSL 1.1.1). Use `REQUESTS_CA_BUNDLE` instead |
| raw `ssl`, `http.client`, httpx, aiohttp | Fails | OK | Not covered by the shim, also when loaded by the layer (e2e `py-lambda-py311-layer-stdlib`). Upgrade to python3.12+ |
| urllib3 `ssl_maximum_version=TLSv1_2` | Fails | OK | Case F applies through the shim too |

**stdlib clients on Lambda 3.9 to 3.11.** The interim option is the `pq-egress` extension: the function sends plain HTTP to `http://127.0.0.1:2779/<route>/<path>` and the extension makes the TLS connection with X25519MLKEM768 (Tested in e2e on python3.9 to 3.14, and for `http.client` on 3.11 through the combined layer). Not tested for AWS SDK calls (SigV4 signs the host name) or on real AWS. Source: [e2e/lambda/extension/pq-egress](REPO/e2e/lambda/extension/pq-egress).

**HTTPS proxy (`HTTPS_PROXY`).** With a CONNECT proxy TLS runs end to end, so the client's PQ setting applies. A TLS-inspecting proxy terminates TLS and decides both legs (guide chapter: Network devices and egress). Not tested.

**WebSockets, HTTP/2.** `websockets`, aiohttp WebSockets and h2/httpx HTTP/2 use the `ssl` module: platform fix only (Unverified for websockets).

**Service mesh sidecar.** If Envoy or Linkerd originates mTLS for the pod, the sidecar decides (guide chapter: Service mesh). The app's own TLS still follows this chapter.

**Child processes.** `OPENSSL_CONF` is inherited by `subprocess`, the AWS CLI and curl. Programs that link GnuTLS (Debian curl and git builds) get no ML-KEM at all (Tested 2026-11-14).

## Solution and automation

### Step 1: inventory and detect

1. **Platform per service**, inside the deployed image with the deployed env:

   ```bash
   python3 -c "import ssl,os; print(ssl.OPENSSL_VERSION, os.environ.get('OPENSSL_CONF'))"
   cat /etc/os-release | head -2; (update-crypto-policies --show 2>/dev/null || true)
   pip list | grep -Ei '^(grpcio|awscrt|confluent-kafka|psycopg|psycopg2-binary|pyopenssl|cryptography|truststore|certifi) '
   ```

2. **Cases C to F:** run the grep line from each case over the app repo and the deployment repo (Dockerfiles, task definitions, Helm values).
3. **Live:** `pq_probe.py` against a PQ-only test server from inside the image (How to test).

### Step 2: change (packaging per compute type)

The Quick start table gives the change per row. Details that matter when you build it:

**Lambda zip, python3.12+.** Put the file in the package and set the variable (full SAM, CloudFormation and Terraform templates at the end):

``` text
build/
  app.py
  pq-tls/openssl-pq.cnf      # keeps the AL2023 policy, changes only the group list
  <your dependencies>
```

``` yaml
      Runtime: python3.13
      Environment:
        Variables:
          OPENSSL_CONF: /var/task/pq-tls/openssl-pq.cnf
```

Fleet option without repackaging: the `pq-tls` layer with `AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper` sets `OPENSSL_CONF` on python3.12+ and the shim on 3.9 to 3.11. It leaves a function's own `OPENSSL_CONF` alone, and chains an existing wrapper (Datadog, OpenTelemetry) through `PQ_TLS_NEXT_WRAPPER` (both Tested, e2e).

**Lambda zip, python3.9 to 3.11 bridge.** Add `pq-tls/pyshim/sitecustomize.py` and install pyOpenSSL, cryptography **and idna** inside the Lambda image of the same Python version and architecture:

```bash
docker run --rm --entrypoint sh -v "$PWD/build:/out" public.ecr.aws/lambda/python:3.11 \
  -c 'pip install --target /out cryptography==50.0.2 pyOpenSSL==26.4.0 idna==3.20'
```

Set `PYTHONPATH=/var/task/pq-tls/pyshim`. For a layer, install into `python/lib/python3.X/site-packages`.

- **`idna` is required.** pyOpenSSL's urllib3 integration imports it and the Lambda runtime does not ship it. Without it the shim still logs `urllib3 -> pyOpenSSL`, then every urllib3, requests and boto3 request raises `No module named 'idna'` (Tested, e2e `py-lambda-py311-shim-noidna`).
- **Build once per Python version.** The cryptography wheel pip picks on 3.11 fails to import on 3.9 and 3.10 (`PyType_GetName`), and `pip install --platform manylinux2014_...` hides cryptography 50.x. Installing inside each version's image avoids both (Tested).
- **Size:** the bridge adds about 18 MB unpacked, 6 MB zipped (cryptography, cffi, pycparser, pyOpenSSL, idna; measured from the e2e `probe-shim-py311.zip`: 17,983,187 bytes unpacked against 28,647 for the probe alone).

**Lambda container image** (full `Dockerfile.lambda` at the end):

``` dockerfile
COPY pq-tls/openssl-pq.cnf ${LAMBDA_TASK_ROOT}/pq-tls/openssl-pq.cnf
ENV OPENSSL_CONF=/var/task/pq-tls/openssl-pq.cnf
```

**Fargate, ECS on EC2, EKS.** Pick the base image first; the Python version matters much less.

| Base image | OpenSSL | `ssl` family PQ out of the box | Action | Evidence |
|----|----|----|----|----|
| `python:3.x-slim-trixie` (Debian 13) | 3.5.7 | Yes | None | Tested (3.11, 3.12, 3.13, 3.15) |
| `python:3.x-alpine` (Alpine 3.24) | 3.5.9 | Yes | None | Tested (3.12) |
| `python:3.x-slim-bookworm` (Debian 12) | 3.0.22 | No | Move to trixie or alpine; nothing adds ML-KEM to OpenSSL 3.0 | Tested |
| `amazonlinux:2023` + `python3.11` to `python3.14` | 3.5.8 | No: crypto policy omits ML-KEM | `ENV OPENSSL_CONF=/etc/pq-tls/openssl-pq.cnf` with the file, or `update-crypto-policies --set DEFAULT:PQ` in the Dockerfile | Tested (e2e) |
| Ubuntu 24.04 | 3.0.x | No | Move to one of the above | Documented |

The variable can live in the task definition (`environment`) or pod spec (`env`) instead of the image. Add a build-time guard so an image regression fails CI:

``` dockerfile
RUN python -c "import ssl,sys; sys.exit(0 if ssl.OPENSSL_VERSION_INFO >= (3,5) else 'OpenSSL < 3.5')"
```

On AL2023 the version guard is not enough (3.5.8 is classical by default): also run `pq_probe.py` against a PQ-only server in CI.

**EC2.** AL2023: one service (`Environment=OPENSSL_CONF=/etc/pq-tls/openssl-pq.cnf` in its systemd unit) or the whole host (SSM document running `update-crypto-policies --set DEFAULT:PQ`, then restart services); both files at the end, host-wide details in the guide chapter Hosts and OS. On AL2023 EC2 `python3.11` links the system OpenSSL 3.5.8, unlike Lambda's python3.11, so the same fix works (Tested, e2e). AL2, Ubuntu 24.04 and Debian 12 hosts cannot be fixed in place.

When you change the base image, carry over the OS trust-store step (case D) and any key-password plumbing (case C).

### Step 3: CI guardrails

- **Lint:** `sh ci/pq-tls-lint.sh src/` fails the build on the case F settings (full file at the end). Tested: it flagged `maximum_version=TLSv1_2`, `OP_NO_TLSv1_3`, `PROTOCOL_TLSv1_2`, `set_ecdh_curve` and `ssl_maximum_version`, and passed `set_groups("X25519MLKEM768:X25519")`. Mark a reviewed line with `# pq-tls: allow`.
- **Image gate:** the `OPENSSL_VERSION_INFO >= (3,5)` line above; on AL2023 also `RUN test "$OPENSSL_CONF" = /etc/pq-tls/openssl-pq.cnf`.
- **Handshake gate:** start `pq-harness.sh` as a service container and run `pq_probe.py pqsrv:8443` and, for servers, `probe-server.sh app:8443` inside the built image. Both must pass.
- **Policy:** deny base images `python:*-bookworm`, `ubuntu:24.04` and `amazonlinux:2` and `OPENSSL_CONF=/dev/null` in your image and pod policy (guide chapter: Enforcement and guardrails).

## How to test

Run in the same image, env and user as the service. Steps 1 to 6 need no AWS account.

1. **Posture.** Step 1 commands above. `ssl` family: OpenSSL 3.5 or later, and on AL2023 `OPENSSL_CONF` set or `update-crypto-policies --show` = `DEFAULT:PQ`. Bundled wheels: compare versions with the library table.
2. **Start the harness.** `pq-harness.sh` (full file at the end) starts a PQ-only server on 8443, a classical-only one on 8444 and the mTLS pair on 8451/8452, signed by a throw-away CA. Run it in `python:3.13-slim-trixie` or `debian:trixie-slim` on the same Docker network.
3. **Client (cases A, D).** `SSL_CERT_FILE=/certs/ca.pem python3 pq_probe.py pqsrv:8443` must connect (on 3.15 it prints `RESULT pqsrv:8443 TLSv1.3 group=X25519MLKEM768`, Tested); before 3.15 the connection itself is the proof. `pqsrv:8444` must also connect (fallback). Repeat with your real trust setting by pointing your client code at the harness.
4. **Server (cases B, C).** Start the server with its real cert and key, then `sh probe-server.sh app:8443`: expect `Negotiated TLS1.3 group: X25519MLKEM768` on the first check and a connection on the second.
5. **mTLS (case E).** `python3 -c "import requests; print(requests.get('https://pqsrv:8451/', verify='/certs/ca.pem', cert=('/certs/client.pem','/certs/client.key')).status_code)"` must print 200. For a server that requires client certs: `sh probe-server.sh app:8443 -cert client.pem -key client.key`.
6. **Settings (case F).** `sh ci/pq-tls-lint.sh .` must print `clean`.
7. **Rollback test.** Remove `OPENSSL_CONF` (or redeploy the old image) in a test environment and rerun step 3: the PQ-only probe must now fail and the classical one pass. This proves the probe detects a regression.
8. **In the cloud.** CloudTrail `tlsDetails.keyExchange` shows `X25519MLKEM768` on the workload's calls to KMS, STS, IAM, Secrets Manager, ACM and Payment Cryptography (other services don't log it). On 3.15 log `SSLSocket.group()`. On Lambda with the shim, look for `pq-tls: python legacy shim: urllib3 -> pyOpenSSL` and `botocore -> pyOpenSSL` in CloudWatch Logs.

## Rollout checklist

Owner: the service team, unless noted.

1. **Inventory (platform team).** List every Python workload with compute type, runtime or base image, OpenSSL version and `OPENSSL_CONF` (Step 1). Tag each with its Quick start row.
2. **Library check.** For each service, list which connections use the `ssl` family and which use bundled-TLS wheels. Bundled wheels: confirm current versions; nothing else to do.
3. **Settings sweep.** Run `ci/pq-tls-lint.sh` and the case C to F greps. Remove `set_ecdh_curve`, TLS 1.2 maximums and `OPENSSL_CONF=/dev/null`; merge `Groups` into any existing `OPENSSL_CONF` file.
4. **Plan the legacy Lambdas first.** python3.9 to 3.11 functions: schedule the runtime upgrade before 29 Jul 2027 (create blocked) and 31 Aug 2027 (update blocked). Use the shim or layer only as a bridge, with `idna` in the package and no truststore.
5. **Make the one change** from the Quick start row in a branch: file plus variable, base image, or crypto policy. Carry over CA and key-password steps if the base image changes.
6. **Add CI gates:** lint, image guard, and the PQ-only and classical-only probe against `pq-harness.sh`.
7. **Canary.** Deploy to one task, pod, host or a 10% weighted Lambda alias. Watch error rate and latency for a day.
8. **Confirm the signal.** CloudTrail `tlsDetails.keyExchange = X25519MLKEM768` for that role's KMS, STS or Secrets Manager calls, or the `group()` log on 3.15. No signal means not done.
9. **Check the peers.** For servers, confirm what terminates TLS in front (ALB, NLB, API Gateway, CloudFront) and whether its policy is PQ. For Kafka, PostgreSQL, MySQL and Redis, confirm the server side offers ML-KEM.
10. **Widen** by account or OU. Record FIPS paths and anything left classical as exceptions with an owner and date.
11. **Keep the rollback** (table below) with the change ticket; run the rollback test (How to test, step 7) once in a test environment.
12. **Clean up:** remove the shim and its packages when a function reaches python3.12+.

## Pitfalls and rollback

- **Silent fallback.** Every failure mode still connects with X25519. Only a PQ-only test or a logged group proves the change.
- **One process, two answers.** On Debian 12 or AL2023 without the config, requests and boto3 are classical while grpcio, awscrt, confluent-kafka and psycopg binary are PQ (Tested).
- **A version guard is not enough on AL2023.** OpenSSL 3.5.8 there is classical until the config or policy changes.
- **Building from source changes the answer.** `psycopg[c]`, `psycopg2` and `mysqlclient` link the system libraries. New Python versions can lag on wheels: on 3.15 pip picked `confluent-kafka 4.4.0b1`, which failed to import.
- **`set_ecdh_curve` removes ML-KEM**, client or server, on every platform, and rejects `X25519MLKEM768` (Tested). Remove the call; use `set_groups` on 3.15+.
- **`set_groups` replaces the whole list.** `set_groups("X25519MLKEM768")` refuses classical peers (Tested). Keep `X25519` (and `secp256r1` if peers need it) unless you mean to enforce.
- **TLS 1.2 maximums block PQ:** `maximum_version`, `OP_NO_TLSv1_3`, `PROTOCOL_TLSv1_2`, urllib3 `ssl_maximum_version` (Tested).
- **`OPENSSL_CONF` is process-wide and inherited** by child processes. If it is already set, merge the `Groups` line; the layer will not override it. `/dev/null` turns PQ on but drops the crypto policy.
- **`DEFAULT:PQ` on a host changes every OpenSSL, GnuTLS and NSS program.** Prefer the per-service systemd `Environment=` when only one service should change.
- **Legacy Lambda shim** covers urllib3, requests and boto3 only, needs `idna`, must be built per Python version, adds about 18 MB unpacked, and is turned off for requests by `truststore.inject_into_ssl()` (all Tested).
- **gunicorn with an encrypted key** looks healthy (`Listening at`) but every worker fails. Use the `ssl_context` hook (Tested).
- **pyOpenSSL has no `load_pkcs12`.** Convert PKCS#12 with cryptography (Tested on 26.4.0).
- **Base-image moves reset the OS trust store,** and certifi upgrades drop an appended CA. requests and httpx do not read the OS store by default (Tested).
- **FIPS** paths (awscrt `TLSv1_2_2025_07`, a FIPS provider) are classical until proven otherwise.
- **Python 3.15 on Lambda is a public preview** (announced 25 Aug 2026), outside the Lambda SLA ([Lambda runtimes](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html)). Don't move production to it for `set_groups` alone.

**Rollback** (each is one change, no code):

| Change | Roll back | Evidence |
|----|----|----|
| `OPENSSL_CONF` in Lambda, task definition, pod spec or systemd | Remove the variable and redeploy or restart | Tested (baseline cases) |
| `pq-tls` layer | `PQ_TLS_DISABLE=1`, or remove `AWS_LAMBDA_EXEC_WRAPPER` | Tested (e2e `py-lambda-py312-layer-disabled`) |
| Legacy shim | Remove `PYTHONPATH=/var/task/pq-tls/pyshim`, or set `PQ_TLS_DISABLE=1` | Tested (baseline cases) |
| AL2023 `DEFAULT:PQ` policy | `update-crypto-policies --set DEFAULT`, then restart the services | Documented |
| Base image moved to trixie or alpine | Redeploy the previous image digest | n/a |
| `set_groups` in code | Set `PQ_GROUPS` to include `X25519`, or remove the call | Tested |

## Test evidence

**e2e suite, run r1117041043 (2026-11-16, LocalStack Pro 2026.10.6):** 65 Python cases, all PASS: 59 client cases (Lambda 35, ECS on Fargate 13, ECS on EC2 3, EC2 8) and 6 load balancer target cases. PASS means the observed result matched the expectation in the case file; for a baseline case the expectation is "classical". Each client case connects to observer listeners: hybrid, PQ-only, mTLS, EC certificate, TLS 1.2-only, and three ML-DSA certificate listeners.

| Compute | Mode | Cases | Result |
| --- | --- | --- | --- |
| Lambda zip | Baseline, python3.9 to 3.14 | 6 | Classical X25519; PQ-only server refused |
| Lambda zip | Bundled `openssl-pq.cnf` + `OPENSSL_CONF`, python3.12 to 3.14 | 3 | X25519MLKEM768 on hybrid, PQ-only, mTLS and EC-cert listeners |
| Lambda zip | Bundled shim + pyOpenSSL/cryptography/idna, python3.9 to 3.11 | 3 | X25519MLKEM768 |
| Lambda zip | Shim without `idna` (pitfall regression) | 1 | Every request fails with the `idna` import error, as documented |
| Lambda zip | `pq-tls` layer: python3.9 to 3.14, combined layer, existing wrapper chained | 8 | X25519MLKEM768 |
| Lambda zip | Layer limits: stdlib `http.client` on 3.11, function's own `OPENSSL_CONF`, `PQ_TLS_DISABLE=1` | 3 | Classical, as documented |
| Lambda zip | `pq-egress` extension, python3.9 to 3.14, plus stdlib on 3.11 via the combined layer | 7 | X25519MLKEM768 |
| Lambda image | `public.ecr.aws/lambda/python:3.12`, `:3.13`, baseline and `ENV OPENSSL_CONF` | 4 | Baseline classical; fixed X25519MLKEM768 |
| ECS on Fargate | AL2023 python3.11 to 3.14, baseline and task-definition `OPENSSL_CONF` | 8 | Baseline classical; fixed X25519MLKEM768 |
| ECS on Fargate | AL2023 image with `DEFAULT:PQ` | 1 | X25519MLKEM768 |
| ECS on Fargate | `python:3.12-slim-trixie`, `3.13-slim-trixie`, `3.12-alpine`, no change | 3 | X25519MLKEM768 |
| ECS on Fargate | `python:3.12-slim-bookworm`, no change | 1 | Classical |
| ECS on EC2 | AL2023 python3.12 baseline and `OPENSSL_CONF`; `python:3.13-slim-trixie` | 3 | Classical; X25519MLKEM768; X25519MLKEM768 |
| EC2 | AL2023 python3.11 to 3.14 baseline | 4 | Classical |
| EC2 | AL2023 one service `OPENSSL_CONF` (3.12); host `DEFAULT:PQ` (3.11, 3.13) | 3 | X25519MLKEM768 |
| EC2 | Amazon Linux 2 python3.7, OpenSSL 1.0.2k | 1 | TLS 1.2 only, P-256; PQ-only refused |
| Load balancer target (Fargate, ECS on EC2) | `ssl`-module HTTPS server: AL2023 baseline, `OPENSSL_CONF` (2), `DEFAULT:PQ`, trixie 3.13, bookworm 3.12 | 6 | PQ backend policy: X25519MLKEM768 for the fixed and trixie servers, classical for AL2023 baseline and bookworm. Classic backend policy: TLS 1.2 everywhere |

What the suite also showed:

- The TLS 1.2-only listener stayed classical in every case: ML-KEM needs TLS 1.3.
- ML-DSA certificates were accepted with `DEFAULT:PQ`, on trixie and alpine, and through the shim, but **not** with `openssl-pq.cnf` alone on AL2023 or Lambda: that file changes only `Groups`, so ML-DSA also needs `SignatureAlgorithms` (guide chapter: Certificates (ML-DSA)). The extension cases did not run the ML-DSA listeners.

**Not covered by e2e:** Lambda python3.15 (covered by the container tests below), EKS (ECS on EC2 uses the same images), real AWS, FIPS mode, and the library-level and case C to F matrices, which ran in containers instead.

**Test code and outputs:**

- e2e case definitions and expectations: [e2e/cases/python.py](REPO/e2e/cases/python.py)
- e2e client probe (urllib3 path, or `http.client` with `PQC_PY_STACK=stdlib`): [e2e/clients/python/probe.py](REPO/e2e/clients/python/probe.py)
- e2e packaging (shim builds per version, the no-idna regression package): [e2e/build/python.sh](REPO/e2e/build/python.sh); layers: [e2e/build/layers.sh](REPO/e2e/build/layers.sh)
- e2e results: [e2e/results/latest/summary.md](REPO/e2e/results/latest/summary.md), [e2e/results/latest/results.json](REPO/e2e/results/latest/results.json)
- Library matrix on Lambda, trixie, bookworm and AL2023 images (2026-11-14): [tests/deep/python/run-python.sh](REPO/tests/deep/python/run-python.sh), [tests/deep/python/pyclients.py](REPO/tests/deep/python/pyclients.py), outputs in [tests/deep/python/out](REPO/tests/deep/python/out)
- Cases C to F and the shim with custom trust: [tests/deep/python/v2/run-v2.sh](REPO/tests/deep/python/v2/run-v2.sh), [tests/deep/python/v2/cases.py](REPO/tests/deep/python/v2/cases.py), outputs in [tests/deep/python/v2/out](REPO/tests/deep/python/v2/out)
- Lambda base-image and container checks: [tests/lambda/run-py-legacy.sh](REPO/tests/lambda/run-py-legacy.sh), [tests/lambda/run-containers.sh](REPO/tests/lambda/run-containers.sh), [tests/lambda/containers.out](REPO/tests/lambda/containers.out)
- `OPENSSL_CONF=/dev/null` on Lambda python3.12 and 3.15 images (2026-11-16): a one-off run of a stdlib client against PQ-only and X25519-only `s_server` instances (OpenSSL 3.5.7); both images negotiated X25519MLKEM768. The earlier [tests/lambda/run-envonly.sh](REPO/tests/lambda/run-envonly.sh) covers the same question through the Lambda emulator.

## Full configuration files

Every file the sections above reference, complete. Paths are relative to the repository or package root unless they start with `/`.

Files marked Tested ran as shown in the container tests. The IaC, task definition, pod spec, systemd unit and SSM document were not deployed (no AWS account in the test lab): only their PQ lines (`OPENSSL_CONF`, `PYTHONPATH`, `update-crypto-policies --set DEFAULT:PQ`) carry tested behaviour. Validate them with `sam validate`, `cfn-lint` or `terraform validate` before use.

`pq-tls/openssl-pq.cnf` (Lambda python3.12+, Lambda images, AL2023 containers and hosts; Tested)

``` ini
# Keeps the AL2023 defaults and only changes the key-exchange group list, PQ hybrid first.
# Ship it in the package or image and point OPENSSL_CONF at it.
openssl_conf = openssl_init

.include /etc/pki/tls/openssl.d

[openssl_init]
ssl_conf = ssl_module
providers = provider_sect

[provider_sect]
default = default_sect

[default_sect]
activate = 1

[ssl_module]
system_default = pq_system_default

[pq_system_default]
.include = /etc/crypto-policies/back-ends/opensslcnf.config
Groups = *X25519MLKEM768:*X25519:secp256r1:X448:secp521r1:secp384r1:ffdhe2048:ffdhe3072:ffdhe4096:ffdhe6144:ffdhe8192
```

`pq-tls/pyshim/sitecustomize.py` (Lambda python3.9 to 3.11 bridge only; Tested on Lambda base images 3.9 and 3.11)

``` python
# pq-tls shim for Lambda Python 3.9-3.11 (system OpenSSL 1.1.1, no ML-KEM).
# Routes urllib3 (requests) and botocore (boto3) through pyOpenSSL, whose bundled
# OpenSSL (from the cryptography wheel) offers X25519MLKEM768 by default.
# Python's own ssl module, http.client and aiohttp are NOT covered.
#
# sitecustomize runs before the Lambda bootstrap has put /var/runtime and the layer's
# site-packages on sys.path, so patching is deferred until each module is first imported.
# Whichever copy the function resolves (its own bundled one or the runtime's) is patched.
import os
import sys

if os.environ.get("PQ_TLS_DISABLE") != "1":
    import importlib.abc
    import importlib.util

    def _log(msg):
        print("pq-tls: python legacy shim: " + msg, file=sys.stderr)

    def _patch_urllib3(module):
        # Append the function package and the layer's site-packages (at the end, so
        # precedence is unchanged) so pyOpenSSL is found in the package or a layer.
        for site in (os.environ.get("LAMBDA_TASK_ROOT", "/var/task"),
                     "/opt/python/lib/python%d.%d/site-packages" % sys.version_info[:2]):
            if site not in sys.path:
                sys.path.append(site)
        import urllib3.contrib.pyopenssl as p
        p.inject_into_urllib3()
        from cryptography.hazmat.backends.openssl.backend import backend
        _log("urllib3 -> pyOpenSSL (%s)" % backend.openssl_version_text())

    def _patch_botocore(module):
        # botocore deliberately keeps the stdlib SSLContext even when urllib3 is patched.
        import urllib3.contrib.pyopenssl as p
        module.SSLContext = p.PyOpenSSLContext
        _log("botocore -> pyOpenSSL")

    _PATCHES = {"urllib3": _patch_urllib3, "botocore.httpsession": _patch_botocore}

    class _Hook(importlib.abc.MetaPathFinder):
        def find_spec(self, name, path, target=None):
            patch = _PATCHES.pop(name, None)
            if patch is None:
                return None
            sys.meta_path.remove(self)
            try:
                spec = importlib.util.find_spec(name)
            finally:
                if _PATCHES and self not in sys.meta_path:
                    sys.meta_path.insert(0, self)
            if spec is None or spec.loader is None:
                return spec
            exec_module = spec.loader.exec_module

            def exec_and_patch(module):
                exec_module(module)
                try:
                    patch(module)
                except Exception as e:  # never break the function
                    _log("not active for %s: %s: %s" % (name, type(e).__name__, e))

            spec.loader.exec_module = exec_and_patch
            return spec

    sys.meta_path.insert(0, _Hook())
```

`template.yaml` (AWS SAM, Lambda zip, python3.13)

``` yaml
AWSTemplateFormatVersion: "2010-09-09"
Transform: AWS::Serverless-2016-10-31
Resources:
  OrdersFn:
    Type: AWS::Serverless::Function
    Properties:
      Runtime: python3.13
      Architectures: [arm64]
      Handler: app.handler
      CodeUri: build/            # contains app.py, your deps and pq-tls/openssl-pq.cnf
      Timeout: 30
      Environment:
        Variables:
          OPENSSL_CONF: /var/task/pq-tls/openssl-pq.cnf
```

`cfn/lambda.yaml` (CloudFormation, Lambda zip)

``` yaml
AWSTemplateFormatVersion: "2010-09-09"
Parameters:
  CodeBucket: {Type: String}
  CodeKey: {Type: String}
  RoleArn: {Type: String}
Resources:
  OrdersFn:
    Type: AWS::Lambda::Function
    Properties:
      Runtime: python3.13
      Architectures: [arm64]
      Handler: app.handler
      Role: !Ref RoleArn
      Code: {S3Bucket: !Ref CodeBucket, S3Key: !Ref CodeKey}
      Environment:
        Variables:
          OPENSSL_CONF: /var/task/pq-tls/openssl-pq.cnf
```

`terraform/lambda.tf` (Lambda zip)

``` hcl
data "archive_file" "orders" {
  type        = "zip"
  source_dir  = "${path.module}/build" # app.py, deps, pq-tls/openssl-pq.cnf
  output_path = "${path.module}/orders.zip"
}

resource "aws_lambda_function" "orders" {
  function_name    = "orders"
  role             = var.role_arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "app.handler"
  filename         = data.archive_file.orders.output_path
  source_code_hash = data.archive_file.orders.output_base64sha256

  environment {
    variables = {
      OPENSSL_CONF = "/var/task/pq-tls/openssl-pq.cnf"
    }
  }
}
```

`terraform/lambda-legacy.tf` (python3.11 bridge until the upgrade; in CloudFormation or SAM set the same `PYTHONPATH` variable)

``` hcl
resource "aws_lambda_function" "legacy" {
  function_name    = "legacy"
  role             = var.role_arn
  runtime          = "python3.11"
  handler          = "app.handler"
  filename         = "legacy.zip" # app.py, pyopenssl + cryptography (built for the arch), pq-tls/pyshim/
  source_code_hash = filebase64sha256("legacy.zip")
  environment {
    variables = {
      PYTHONPATH = "/var/task/pq-tls/pyshim"
    }
  }
}
```

`Dockerfile.lambda` (Lambda container image)

``` dockerfile
FROM public.ecr.aws/lambda/python:3.13
COPY requirements.txt ${LAMBDA_TASK_ROOT}/
RUN pip install --no-cache-dir -r ${LAMBDA_TASK_ROOT}/requirements.txt -t ${LAMBDA_TASK_ROOT}
COPY app.py ${LAMBDA_TASK_ROOT}/
COPY pq-tls/openssl-pq.cnf ${LAMBDA_TASK_ROOT}/pq-tls/openssl-pq.cnf
ENV OPENSSL_CONF=/var/task/pq-tls/openssl-pq.cnf
CMD ["app.handler"]
```

`Dockerfile` (Fargate / ECS / EKS, Debian 13 trixie: PQ with no extra setting)

``` dockerfile
FROM python:3.13-slim-trixie
RUN useradd -r -u 10001 app
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
# Fails the build if this image's OpenSSL cannot do ML-KEM.
RUN python -c "import ssl,sys; sys.exit(0 if ssl.OPENSSL_VERSION_INFO >= (3,5) else 'OpenSSL < 3.5')"
USER app
EXPOSE 8443
CMD ["gunicorn", "-c", "gunicorn.conf.py", "app:wsgi"]
```

`Dockerfile.al2023` (Fargate / ECS / EKS on Amazon Linux 2023)

``` dockerfile
FROM public.ecr.aws/amazonlinux/amazonlinux:2023
RUN dnf -y install python3.12 python3.12-pip && dnf clean all
WORKDIR /app
COPY requirements.txt .
RUN python3.12 -m pip install --no-cache-dir -r requirements.txt
COPY . .
# Option A (image-wide): switch the crypto policy.
#   RUN dnf -y install crypto-policies-scripts && update-crypto-policies --set DEFAULT:PQ
# Option B (this process only): ship the config file.
COPY pq-tls/openssl-pq.cnf /etc/pq-tls/openssl-pq.cnf
ENV OPENSSL_CONF=/etc/pq-tls/openssl-pq.cnf
CMD ["python3.12", "-m", "gunicorn", "-c", "gunicorn.conf.py", "app:wsgi"]
```

`ecs/taskdef.json` (Fargate)

``` json
{
  "family": "orders",
  "requiresCompatibilities": ["FARGATE"],
  "networkMode": "awsvpc",
  "cpu": "512",
  "memory": "1024",
  "runtimePlatform": {"cpuArchitecture": "ARM64", "operatingSystemFamily": "LINUX"},
  "executionRoleArn": "arn:aws:iam::111122223333:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "orders",
      "image": "111122223333.dkr.ecr.us-east-1.amazonaws.com/orders@sha256:<digest>",
      "essential": true,
      "portMappings": [{"containerPort": 8443, "protocol": "tcp"}],
      "environment": [
        {"name": "OPENSSL_CONF", "value": "/etc/pq-tls/openssl-pq.cnf"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/orders",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "orders"
        }
      }
    }
  ]
}
```

`k8s/deployment.yaml` (EKS)

``` yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders
spec:
  replicas: 2
  selector:
    matchLabels: {app: orders}
  template:
    metadata:
      labels: {app: orders}
    spec:
      containers:
        - name: orders
          image: 111122223333.dkr.ecr.us-east-1.amazonaws.com/orders@sha256:<digest>
          ports:
            - containerPort: 8443
          env:
            - name: OPENSSL_CONF          # AL2023-based image only; trixie/alpine need nothing
              value: /etc/pq-tls/openssl-pq.cnf
          readinessProbe:
            tcpSocket: {port: 8443}
```

`gunicorn.conf.py` (gunicorn terminates TLS; Tested on 3.12, 3.13 and 3.15; set_groups applies on 3.15 only)

``` python
import os
import ssl

bind = "0.0.0.0:8443"
workers = 2
certfile = "/etc/tls/server.pem"
keyfile = "/etc/tls/server.key"


def ssl_context(conf, default_ssl_context_factory):
    ctx = default_ssl_context_factory()
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    if hasattr(ctx, "set_groups"):  # Python 3.15+
        # PQ hybrid first, classical fallback kept. Set PQ_GROUPS=X25519MLKEM768 to refuse classical clients.
        ctx.set_groups(os.environ.get("PQ_GROUPS", "X25519MLKEM768:X25519:secp256r1"))
    return ctx
```

`serve_uvicorn.py` (uvicorn terminates TLS with an explicit group list; Tested on 3.15: PQ-first and PQ-only)

``` python
import os
import ssl

import uvicorn

config = uvicorn.Config(
    "app:asgi",
    host="0.0.0.0",
    port=int(os.environ.get("PORT", "8443")),
    ssl_certfile=os.environ.get("TLS_CERT", "/etc/tls/server.pem"),
    ssl_keyfile=os.environ.get("TLS_KEY", "/etc/tls/server.key"),
)
config.load()  # builds config.ssl; Server.run() skips load() when already loaded
config.ssl.minimum_version = ssl.TLSVersion.TLSv1_2
if hasattr(config.ssl, "set_groups"):
    config.ssl.set_groups(os.environ.get("PQ_GROUPS", "X25519MLKEM768:X25519:secp256r1"))
uvicorn.Server(config).run()
```

`/etc/systemd/system/orders.service` (EC2, AL2023; scope the config to one service)

``` ini
[Unit]
Description=orders API (gunicorn)
After=network-online.target
Wants=network-online.target

[Service]
User=orders
WorkingDirectory=/opt/orders
Environment=OPENSSL_CONF=/etc/pq-tls/openssl-pq.cnf
ExecStart=/opt/orders/venv/bin/gunicorn -c /opt/orders/gunicorn.conf.py app:wsgi
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

`ssm/pq-crypto-policy.yaml` (SSM Command document for AL2023 hosts; run from a State Manager association)

``` yaml
schemaVersion: "2.2"
description: Set the AL2023 crypto policy to DEFAULT:PQ and restart listed services.
parameters:
  Services:
    type: String
    default: "orders"
    description: Space-separated systemd units to restart after the change.
mainSteps:
  - action: aws:runShellScript
    name: setPqPolicy
    precondition:
      StringEquals: [platformType, Linux]
    inputs:
      runCommand:
        - set -euo pipefail
        - . /etc/os-release
        - '[ "$ID" = amzn ] && [ "$VERSION_ID" = 2023 ] || { echo "not AL2023, skipping"; exit 0; }'
        - dnf -y install crypto-policies-scripts
        - '[ "$(update-crypto-policies --show)" = DEFAULT:PQ ] || update-crypto-policies --set DEFAULT:PQ'
        - for s in {{ Services }}; do systemctl restart "$s"; done
        - update-crypto-policies --show
```

`pq_probe.py` (posture and live check; run inside the same image, env and user as the service; Tested on 3.15)

``` python
"""pq_probe.py - report whether this Python process negotiates hybrid PQ TLS.

Usage:  python3 pq_probe.py [host[:port] ...]     default: kms.us-east-1.amazonaws.com:443
Exit code 0 = every target negotiated X25519MLKEM768 (3.15+) or connected (older: see note).
"""
import os
import socket
import ssl
import sys

targets = sys.argv[1:] or ["kms.us-east-1.amazonaws.com:443"]
print("python   ", sys.version.split()[0])
print("openssl  ", ssl.OPENSSL_VERSION)
print("OPENSSL_CONF", os.environ.get("OPENSSL_CONF", "(unset)"))
major, minor = ssl.OPENSSL_VERSION_INFO[:2]
if (major, minor) < (3, 5):
    print("RESULT    classical: OpenSSL < 3.5 has no ML-KEM; no setting can add it")
    sys.exit(2)
rc = 0
for t in targets:
    host, _, port = t.partition(":")
    ctx = ssl.create_default_context()
    try:
        with socket.create_connection((host, int(port or 443)), timeout=5) as raw:
            with ctx.wrap_socket(raw, server_hostname=host) as s:
                if hasattr(s, "group"):  # Python 3.15+
                    g = s.group()
                    print("RESULT    %s %s group=%s" % (t, s.version(), g))
                    rc |= 0 if g and "MLKEM" in g.upper() else 1
                else:
                    print("RESULT    %s %s connected (group not visible before Python 3.15;"
                          " point this at a PQ-only test server to prove the offer)" % (t, s.version()))
    except Exception as e:
        print("RESULT    %s FAIL %s: %s" % (t, type(e).__name__, e))
        rc |= 1
sys.exit(rc)
```

`gunicorn-enc.conf.py` (gunicorn with an encrypted key; Tested on 3.12, 3.13, AL2023 3.12 + config)

```python
# gunicorn.conf.py for an encrypted private key (gunicorn has no key-password option).
# The ssl_context hook builds the context itself and passes the password from the environment
# (for example injected from Secrets Manager by ECS "secrets" or an EKS CSI driver).
import os
import ssl

bind = os.environ.get("BIND", "0.0.0.0:8443")
workers = 2
certfile = os.environ.get("TLS_CERT", "/etc/tls/server.pem")
keyfile = os.environ.get("TLS_KEY", "/etc/tls/server-enc.key")  # must be set so gunicorn turns TLS on


def ssl_context(conf, default_ssl_context_factory):
    # Do not call default_ssl_context_factory(): it loads the key without a password and fails.
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(conf.certfile, conf.keyfile, password=os.environ["TLS_KEY_PASSWORD"])
    if conf.ca_certs:  # mTLS: --ca-certs plus --cert-reqs 2
        ctx.load_verify_locations(conf.ca_certs)
        ctx.verify_mode = ssl.VerifyMode(conf.cert_reqs)
    return ctx
```

`p12_to_pem.py` (convert a PKCS#12/PFX at startup; Tested with cryptography 50.0.2: the converted pair served X25519MLKEM768, key file mode 0600)

```python
"""p12_to_pem.py - load a PKCS#12 file and write PEM cert chain + key for ssl.load_cert_chain.
Usage: python3 p12_to_pem.py server.p12 /run/tls   (password in env P12_PASSWORD)
Writes /run/tls/server.pem (leaf + chain) and /run/tls/server.key (PKCS#8, mode 0600).
"""
import os, sys
from cryptography.hazmat.primitives.serialization import pkcs12, Encoding, PrivateFormat, NoEncryption

src, out = sys.argv[1], sys.argv[2]
key, cert, chain = pkcs12.load_key_and_certificates(open(src, "rb").read(), os.environ["P12_PASSWORD"].encode())
os.makedirs(out, exist_ok=True)
with open(os.path.join(out, "server.pem"), "wb") as f:
    f.write(cert.public_bytes(Encoding.PEM) + b"".join(c.public_bytes(Encoding.PEM) for c in chain or []))
fd = os.open(os.path.join(out, "server.key"), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "wb") as f:
    f.write(key.private_bytes(Encoding.PEM, PrivateFormat.PKCS8, NoEncryption()))
```

`ci/pq-tls-lint.sh` (CI guardrail for case F; Tested)

```sh
#!/bin/sh
# ci/pq-tls-lint.sh - fail the build on Python TLS settings that block hybrid PQ key exchange.
# Usage: sh ci/pq-tls-lint.sh [dir]   (default .)   Exit 1 = blocking setting found, 0 = clean.
# Allow a reviewed line by adding the comment "pq-tls: allow" on that line.
DIR=${1:-.}
PAT='set_ecdh_curve\(|maximum_version *= *ssl\.TLSVersion\.TLSv1(_[012])?\b|ssl_maximum_version *= *ssl\.TLSVersion\.TLSv1|OP_NO_TLSv1_3|PROTOCOL_TLSv1(_[12])?\b|ssl_version *= *ssl\.PROTOCOL_TLSv1|set_groups\(["'"'"'][^"'"'"']*["'"'"']\)|ssl\.curves\.list|OPENSSL_CONF *= */dev/null'
HITS=$(grep -rnE --include='*.py' --include='*.cfg' --include='*.ini' --include='*.toml' --include='*.yaml' --include='*.yml' \
        --include='*.json' --include='Dockerfile*' --include='*.env' "$PAT" "$DIR" 2>/dev/null | grep -v 'pq-tls: allow')
# set_groups / ssl.curves.list are only a problem when the list has no ML-KEM group
HITS=$(printf '%s\n' "$HITS" | grep -vE '(set_groups|ssl\.curves\.list).*MLKEM' | grep -v '^$')
if [ -n "$HITS" ]; then
  echo "pq-tls-lint: settings that can block X25519MLKEM768 (see the Python tab, case F):"
  printf '%s\n' "$HITS"
  exit 1
fi
echo "pq-tls-lint: clean"
```

`pq-harness.sh` (PQ-only, classical-only and mTLS test servers; Tested as `srv2.sh` + `mkcerts.sh`)

```sh
#!/bin/sh
# pq-harness.sh - throw-away CA plus PQ-only, classical-only and mTLS test servers (OpenSSL 3.5).
# Run in python:3.13-slim-trixie or debian:trixie-slim with /certs mounted, network alias "pqsrv":
#   docker run -d --name pqsrv --network ci -v $PWD/certs:/certs -v $PWD/pq-harness.sh:/h.sh debian:trixie-slim sh /h.sh
#   8443 PQ-only (X25519MLKEM768, TLS 1.3)       8444 classical-only (X25519)
#   8451 PQ-only, client cert required          8452 classical-only, client cert required
# Clients trust /certs/ca.pem; the mTLS client cert is /certs/client.pem + /certs/client.key.
set -e
command -v openssl >/dev/null || { apt-get update -qq && apt-get install -y -qq openssl >/dev/null; }
C=/certs; mkdir -p $C; cd $C
if [ ! -f ca.pem ]; then
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 7 -subj /CN=pq-harness-ca \
    -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign -keyout ca.key -out ca.pem 2>/dev/null
  for n in server client; do
    eku=serverAuth; [ $n = client ] && eku=clientAuth
    openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj /CN=$n -keyout $n.key -out $n.csr 2>/dev/null
    printf 'subjectAltName=DNS:pqsrv,DNS:localhost\nextendedKeyUsage=%s\n' $eku > $n.ext
    openssl x509 -req -in $n.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 7 -extfile $n.ext -out $n.pem 2>/dev/null
  done
  rm -f *.csr *.ext; chmod 644 *.pem client.key
fi
S="openssl s_server -cert $C/server.pem -key $C/server.key -www -brief"
$S -accept 8443 -groups X25519MLKEM768 -tls1_3 &
$S -accept 8444 -groups X25519 &
$S -accept 8451 -groups X25519MLKEM768 -tls1_3 -Verify 1 -CAfile $C/ca.pem &
$S -accept 8452 -groups X25519 -Verify 1 -CAfile $C/ca.pem &
echo "pq-harness up: $(openssl version)"
wait
```

`probe-server.sh` (server-side check; Tested as the probe in `run-v2.sh`)

```sh
#!/bin/sh
# probe-server.sh - check that a TLS server accepts hybrid PQ and still accepts classical clients.
# Usage: sh probe-server.sh host:port [extra s_client args, e.g. -cert client.pem -key client.key -CAfile ca.pem]
# Needs OpenSSL 3.5+ (debian:trixie-slim, python:3.13-slim-trixie, alpine:3.24). Exit 0 = both checks passed.
T=$1; shift
H=${T%:*}
pq=$(echo Q | openssl s_client -connect "$T" -servername "$H" -groups X25519MLKEM768 -tls1_3 -brief "$@" 2>&1)
cl=$(echo Q | openssl s_client -connect "$T" -servername "$H" -groups X25519 -brief "$@" 2>&1)
echo "$pq" | grep -q 'Negotiated TLS1.3 group: X25519MLKEM768' && r1=PASS || r1=FAIL
echo "$cl" | grep -q 'Protocol version' && r2=PASS || r2=FAIL
echo "$r1 PQ client      ($T): $(echo "$pq" | grep -E 'Negotiated TLS1.3 group|alert|errno' | head -1)"
echo "$r2 classical client ($T): $(echo "$cl" | grep -E 'Protocol version|alert|errno' | head -1)"
[ $r1 = PASS ] && [ $r2 = PASS ]
```
