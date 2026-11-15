# Python

## Problem statement

A Python service that runs on the wrong base image talks classical TLS today: it negotiates X25519 or P-256 with no ML-KEM, so traffic it sends or receives can be recorded now and decrypted later by a quantum computer (harvest-now-decrypt-later). Nothing fails, so nobody notices. Python itself has no PQ switch. The handshake is controlled by whichever TLS library each package uses:

- **The `ssl` family** (`ssl`, `http.client`, `urllib`, requests, urllib3, boto3/botocore, httpx, aiohttp, redis-py, PyMySQL, uvicorn, gunicorn, hypercorn): the OpenSSL that the interpreter links, from the base image or host, plus that OpenSSL's config (`OPENSSL_CONF`, the AL2023 crypto policy). PQ needs OpenSSL 3.5+ with ML-KEM in the group list.
- **Wheels that bundle their own TLS** (grpcio, awscrt, confluent-kafka, psycopg `[binary]`, psycopg2-binary, pyOpenSSL via cryptography): the wheel version. Current wheels are already PQ on every base image tested.

The fix for most teams is a base-image change or one environment variable. Existing certificates, key files, PKCS#12 stores and CA bundles do not change: key exchange is negotiated separately from the certificate (cases C and D, Tested).

In Python the TLS library, not the Python version, decides whether a connection offers X25519MLKEM768. There are two families, and each package belongs to one of them:

| Family | Packages | Who controls the key exchange | PQ when |
|----|----|----|----|
| Linked to the system OpenSSL through the `ssl` module | `ssl`, `http.client`, `urllib`, requests, urllib3, boto3/botocore (default), httpx, aiohttp, redis-py, PyMySQL, uvicorn, gunicorn, hypercorn, Flask/Django/FastAPI servers | The OpenSSL the interpreter links (base image or host) plus its config (`OPENSSL_CONF`, AL2023 crypto policy) | OpenSSL 3.5+ and the config keeps ML-KEM in the group list |
| Bundles its own TLS library in the wheel | grpcio (BoringSSL), awscrt (s2n-tls + AWS-LC), confluent-kafka (static OpenSSL 3.5.8 in librdkafka 2.16.0), psycopg\[binary\] and psycopg2-binary (their own libpq + libssl), pyOpenSSL (the OpenSSL in the cryptography wheel) | The wheel version | Already PQ in current wheels, on any base image, including Debian 12 with OpenSSL 3.0 (Tested) |

So the first question for any service is which family each outbound connection uses. A requests call on Debian 12 is classical, while a grpcio call from the same container is PQ.

Python 3.15 (released 9 Oct 2026) adds `SSLContext.set_groups()`, `get_groups()` and `SSLSocket.group()`. These let code set the group list and log the negotiated group. Older versions have no group API: `set_ecdh_curve("X25519MLKEM768")` raises `ValueError: unknown elliptic curve name` on 3.12, 3.13 and 3.15 (Tested). See the [3.15 ssl docs](https://docs.python.org/3.15/library/ssl.html#ssl.SSLContext.set_groups).

## Versions and native support

PQ depends on the OpenSSL under Python, so the same Python version gives different answers on Lambda, in a container and on EC2.

| Version | TLS stack (`ssl` family) | PQ client by default? | PQ server by default? | API to set groups | FIPS-mode behaviour | Proposed solution | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 3.9, 3.10, 3.11 (3.9 and 3.10 end of life upstream) | Lambda: OpenSSL 1.1.1 (AL2). Containers: whatever the image ships | Lambda: no. trixie or alpine image: yes. bookworm: no | Same as client | None. `set_ecdh_curve` takes one classical curve only | Not tested | Lambda: move to python3.12+; bridge with the legacy shim (requests, boto3 only). Containers: trixie or alpine base | Tested (Lambda 3.9/3.11 images; trixie 3.11) |
| 3.12 | Lambda and AL2023: OpenSSL 3.5.8. trixie: 3.5.7. bookworm: 3.0 | Lambda, AL2023: no (crypto policy omits ML-KEM). trixie, alpine: yes. bookworm: no | Same as client | None | Not tested | Lambda/AL2023: `OPENSSL_CONF=openssl-pq.cnf` or `DEFAULT:PQ`. bookworm: move to trixie | Tested (trixie 3.12, AL2023 3.12, Lambda 3.12) |
| 3.13 | As 3.12 | As 3.12 | As 3.12 | None | Not tested | As 3.12 | Tested (trixie 3.13, Lambda 3.13) |
| 3.14 | As 3.12 | As 3.12 | As 3.12 | None | Not tested | As 3.12 | Tested (Lambda 3.14 image) |
| 3.15 (released 9 Oct 2026; Lambda public preview) | As 3.12 | As 3.12 | As 3.12 | `SSLContext.set_groups()`, `get_groups()`, `SSLSocket.group()` | Not tested | Platform fix as 3.12; `set_groups("X25519MLKEM768:X25519")` also works without the file; log `group()` | Tested (trixie 3.15, Lambda 3.15 image) |
| Bundled-TLS wheels on any version | BoringSSL (grpcio), s2n-tls (awscrt), static OpenSSL 3.5.8 (confluent-kafka), own libssl (psycopg binary), cryptography's OpenSSL (pyOpenSSL) | Yes | grpcio server: yes | Library-specific (`ssl.curves.list`, `TlsCipherPref`) | awscrt FIPS policy `TLSv1_2_2025_07`: no PQ (docstring) | Keep wheels current; nothing else | Tested |

FIPS mode for the `ssl` family (AL2023 in FIPS mode, or a FIPS OpenSSL provider) was not tested here. Whether the FIPS provider offers ML-KEM is not confirmed; see case G.

Decision guide:

- **Base image is `python:*-slim-trixie` or `python:*-alpine` (3.24)**: nothing to do for any case below except F (code that pins old settings).
- **Lambda python3.12 to 3.15, a Lambda image, or anything on AL2023**: ship `openssl-pq.cnf` and set `OPENSSL_CONF`, or set `DEFAULT:PQ` on the host or image.
- **Lambda python3.9 to 3.11**: upgrade the runtime. If you cannot yet, the legacy shim covers requests and boto3 only.
- **`python:*-bookworm`, Ubuntu 24.04, Debian 12 or AL2 hosts**: OpenSSL is too old. Change the base image or OS; no setting helps.
- **The service only uses grpcio, awscrt, confluent-kafka or psycopg binary**: already PQ; check the peer.
- **You load your own certificate, key, PKCS#12 or CA bundle**: keep it. Only the platform fix above applies (cases C, D, E).

### By compute type (the `ssl` family: requests, boto3, httpx, aiohttp, servers)

| Compute type | Python / base | OpenSSL | PQ by default | Fix | Evidence |
|----|----|----|----|----|----|
| Lambda zip | python3.12, 3.13, 3.14 (AL2023) | 3.5.8 | No | Ship `openssl-pq.cnf`, set `OPENSSL_CONF` | Tested (3.14 image 2026-11-14; 3.12/3.13 on 2026-11-12) |
| Lambda zip | python3.15 (AL2023, public preview) | 3.5.8 | No | Same as 3.12+; or in code ctx.set_groups("X25519MLKEM768:X25519"), which worked without the file | Tested (Lambda 3.15 base image, 2026-11-14) |
| Lambda zip | python3.10, 3.11 (AL2) | 1.1.1zb | No | Upgrade to 3.12+; bridge: legacy shim (requests, boto3 only) | Tested |
| Lambda image | `public.ecr.aws/lambda/python:3.12`+ | 3.5.8 | No | Same file and variable in the Dockerfile | Tested |
| Fargate, ECS, EKS | `python:*-slim-trixie`, `python:*-alpine` | 3.5.7 / 3.5.9 | Yes | None | Tested |
| Fargate, ECS, EKS | `python:*-slim-bookworm`, Ubuntu 24.04 | 3.0.x | No | Change base image | Tested |
| Fargate, ECS, EKS | Amazon Linux 2023 + `python3.12` | 3.5.8 | No | `OPENSSL_CONF` or `DEFAULT:PQ` policy | Tested |
| EC2 | Amazon Linux 2023 | 3.5.x | No | `DEFAULT:PQ` policy (host) or `OPENSSL_CONF` (one service) | Tested in an AL2023 container; Documented for hosts |
| EC2 | Amazon Linux 2 | 1.0.2 / 1.1.1 | No | Migrate the host | Documented |

### By library (client offers ML-KEM to a PQ-only server?)

| Library | Lambda 3.11 (AL2) | Lambda 3.14 | Lambda 3.14 + conf | trixie 3.13 / 3.15 | bookworm 3.12 | AL2023 3.12 | AL2023 3.12 + conf |
|----|----|----|----|----|----|----|----|
| `ssl`, `http.client`, `urllib`, requests, urllib3, botocore, httpx, aiohttp, redis-py | No | No | Yes | Yes | No | No | Yes |
| urllib3 + `inject_into_urllib3()` (pyOpenSSL) | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| pyOpenSSL 26.4.0 | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| awscrt 0.38.1 (default and `PQ_DEFAULT`) | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| grpcio 1.85.1 client | Yes | Yes | Yes | Yes (3.13) | Yes | Yes | Yes |
| psycopg 3.3.9 binary, psycopg2-binary 2.9.13 | Yes | Yes | Yes | Yes (3.13) | Yes | Yes | Yes |
| confluent-kafka (librdkafka 2.16.0) | No wheel installed | Yes | Yes | Yes (3.13) | Yes | Yes | Yes |

All cells Tested on 2026-11-14 in containers (arm64), each client run against an OpenSSL 3.5.7 `s_server` limited to X25519MLKEM768 and one limited to X25519. Every library also connected to the classical-only server in every column, so fallback works. For grpcio, Kafka and Redis the server log confirmed the ClientHello groups and `Peer Temp Key: X25519MLKEM768`. PostgreSQL drivers were tested against PostgreSQL 18.7 with `ssl_groups = 'X25519MLKEM768'`.

Gaps: on the python3.11 Lambda image pip found no confluent-kafka wheel, so Kafka is untested there. On Python 3.15 pip chose `confluent-kafka 4.4.0b1`, whose build failed to import, so Kafka is untested on 3.15. On the python3.15 Lambda image (public preview) the results match Lambda 3.14: the ssl family is classical until OPENSSL_CONF is set, while pyOpenSSL, awscrt, grpcio and both psycopg wheels are PQ.

## Cases: what to change

All results in this section were Tested on 2026-11-14 in containers (arm64) on four platforms unless a row says otherwise:

- Debian 13 trixie with Python 3.12.16 and 3.13.18 (OpenSSL 3.5.7), no extra setting
- Amazon Linux 2023 with Python 3.12.15 and `OPENSSL_CONF=/kit/openssl-pq.cnf` (OpenSSL 3.5.8)
- Lambda `public.ecr.aws/lambda/python:3.11` (OpenSSL 1.1.1) with the legacy shim on `PYTHONPATH` (clients only)

The test servers are OpenSSL 3.5.7 `s_server` instances: a PQ-only one (`-groups X25519MLKEM768 -tls1_3`), a classical-only one (`-groups X25519`), and the same pair with a client certificate required. A Python client that reaches the PQ-only server has proved it offered X25519MLKEM768, because that server accepts nothing else. Python servers were probed with `openssl s_client`, which printed `Negotiated TLS1.3 group: X25519MLKEM768`. Scripts and outputs: `deep/python/v2/` (`run-v2.sh`, `cases.py`, `servers.py`, `srv2.sh`, `mkcerts.sh`, `out/d312.txt`, `out/d313.txt`, `out/al-conf.txt`, `out/l311-shim.txt`).

### A. Simple client

**Who this is:** code that calls requests, boto3, httpx, aiohttp, urllib or a DB/queue driver with default TLS settings. `grep -rnE "ssl\.|SSLContext|verify=|cert=" src/` finds nothing unusual.

**What happens today:** depends only on the platform and on which library family each call uses (tables in "Versions and native support"). Tested.

**What to change:** the platform fix only. No code change.

**Side effects:** none in code. `OPENSSL_CONF` is inherited by child processes (case J).

Rule of thumb: for the `ssl` family, fix the platform (base image, `OPENSSL_CONF` or crypto policy) and leave the code alone. For bundled-TLS wheels, keep the wheel current. Code changes are only needed to pin the group list (3.15+) or to log the negotiated group.

| Library (tested version) | TLS stack | What to set | Evidence |
|----|----|----|----|
| `ssl`, `http.client`, `urllib.request` (3.12, 3.13, 3.15) | System OpenSSL | Nothing in code. Platform fix only. On 3.15+ you may call `ctx.set_groups("X25519MLKEM768:X25519")`. `set_groups("X25519MLKEM768")` alone refuses classical servers. | Tested |
| requests 2.34.2, urllib3 2.8.0 | System OpenSSL via `ssl` | Nothing. To pin groups on 3.15, pass a custom context through an `HTTPAdapter` (excerpt below). | Tested |
| boto3 / botocore 1.44.3 (default HTTP path) | System OpenSSL via `ssl` | Nothing; platform fix only. botocore builds its own `SSLContext`, so `inject_into_urllib3()` alone does not reach it; the Lambda legacy shim patches both. | Tested |
| awscrt 0.38.1 (`boto3[crt]`, S3 transfer manager) | s2n-tls, bundled | Nothing: the default policy already offered ML-KEM. `TlsCipherPref.PQ_DEFAULT` also works. `PQ_TLSv1_0_2021_05` raises `AWS_IO_TLS_CIPHER_PREF_UNSUPPORTED`. `TLSv1_2_2025_07` (FIPS) allows only P-256/P-384 per its docstring, so no PQ. | Tested (default, PQ_DEFAULT); docstring for the FIPS policy |
| httpx 0.28.1 | System OpenSSL via `ssl` | Nothing. To pin groups on 3.15: `httpx.Client(verify=ctx)` with a context you built. | Tested |
| aiohttp 3.14.5 | System OpenSSL via `ssl` | Nothing. To pin groups on 3.15: `session.get(url, ssl=ctx)`. | Tested |
| pyOpenSSL 26.4.0 | OpenSSL bundled in the cryptography wheel (4.0.3 in the tested wheel) | Nothing. Offers X25519MLKEM768 even on Debian 12 and AL2023 without the config. | Tested |
| grpcio 1.85.1 (client) | BoringSSL, bundled | Nothing. The ClientHello listed `X25519MLKEM768:x25519:secp256r1:secp384r1:secp521r1` on every base image. There is no Python setting for groups, and `OPENSSL_CONF` has no effect on BoringSSL. | Tested |
| psycopg 3.3.9 `[binary]` (libpq 18.0) | libpq + libssl bundled in the wheel | Nothing; use `sslmode=verify-full`. Connected to a PG18 server set to `ssl_groups = 'X25519MLKEM768'` on every base image. | Tested |
| psycopg2-binary 2.9.13 (libpq 17) | libpq + libssl bundled in the wheel | Same as psycopg 3. | Tested |
| psycopg / psycopg2 built from source (`psycopg[c]`, `psycopg2`) | System libpq and OpenSSL | Platform fix, as for the `ssl` family. | Unverified (follows from linkage, not tested) |
| PyMySQL | System OpenSSL via `ssl` (`ssl.create_default_context`, read from source) | Platform fix. The server must also offer ML-KEM, see the Databases tab. | Tested (source read); handshake not tested |
| mysqlclient | The C client library it was compiled against | Platform fix; check which TLS library that client library uses. | Unverified |
| redis-py 8.1.0 | System OpenSSL via `ssl` | Platform fix (`ssl=True`, `ssl_ca_certs`). No group option was checked in redis-py; rely on the platform. | Tested |
| confluent-kafka 2.x (librdkafka 2.16.0) | OpenSSL 3.5.8 statically linked in the wheel | Nothing: it offered ML-KEM on every base image. `ssl.curves.list=X25519MLKEM768:X25519` also works if you want it explicit. | Tested |

Pin the group list for requests on Python 3.15+ (most services should not need this):

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

Log the negotiated group (3.15+), for example once at startup against a dependency:

``` python
with socket.create_connection((host, 443)) as raw, ctx.wrap_socket(raw, server_hostname=host) as s:
    log.info("tls", extra={"host": host, "version": s.version(), "group": s.group()})
```

awscrt, explicit PQ policy (not needed with the current default):

``` python
from awscrt import io
opts = io.TlsContextOptions()
opts.cipher_pref = io.TlsCipherPref.PQ_DEFAULT
```

confluent-kafka, explicit group list:

``` python
Producer({"bootstrap.servers": "b-1.msk.example:9094", "security.protocol": "SSL",
          "ssl.curves.list": "X25519MLKEM768:X25519"})
```

The Kafka broker or Amazon MSK must also accept ML-KEM; a client offer alone falls back to X25519.

### B. Simple server

**Who this is:** uvicorn, gunicorn, hypercorn or a grpcio server that terminates TLS in the Python process (HTTPS target group, NLB TCP passthrough, in-VPC service-to-service). If an ALB, API Gateway or CloudFront terminates TLS, Python's settings do not decide the client-facing handshake.

**What happens today:** PQ on trixie and on AL2023 with the config; classical on bookworm and on AL2023 without it. grpcio is PQ everywhere. Tested.

**What to change:** the platform fix only. On 3.15 you can also pin or enforce the group list in code (excerpts below).

**Side effects:** classical clients keep working unless you enforce PQ-only with `set_groups`.

First decide where TLS ends. If an ALB, NLB TLS listener, API Gateway or CloudFront terminates TLS, the client-facing key exchange is set by that service's security policy, not by Python: see the Load balancers and Edge and API front doors tabs. Python's server settings matter only where the Python process itself terminates TLS: a target group using HTTPS, an NLB TCP passthrough, service-to-service traffic inside the VPC, or a gRPC server.

Python servers accept ML-KEM whenever the linked OpenSSL is 3.5+ with ML-KEM in its group list. No server flag is needed for that. A server that cannot do ML-KEM still serves PQ-capable clients, which fall back to X25519, so the failure is silent.

| Server (tested version) | TLS stack | trixie 3.13 / 3.15 | bookworm 3.12 (OpenSSL 3.0) | AL2023 3.12 default | AL2023 + `OPENSSL_CONF` | Group control in code |
|----|----|----|----|----|----|----|
| uvicorn 0.54.0 (`--ssl-certfile`) | System OpenSSL | PQ | Classical only | Classical only | PQ | 3.15+: build `Config`, call `config.load()`, then `config.ssl.set_groups(...)` (Tested) |
| gunicorn 27.0.1 (`certfile`) | System OpenSSL | PQ | Classical only | Classical only | PQ | 3.15+: `ssl_context` hook in `gunicorn.conf.py` calling `set_groups` (Tested) |
| hypercorn 0.18.0 (`--certfile`) | System OpenSSL | PQ | Classical only | Classical only | PQ | No hook checked; platform only |
| grpcio 1.85.1 server (`ssl_server_credentials`) | BoringSSL, bundled | PQ | PQ | PQ | PQ | None needed |

All rows are Tested: `openssl s_client -groups X25519MLKEM768 -tls1_3` against each server, plus `-groups X25519` to prove classical clients still connect. "Classical only" means the PQ-only client was refused with a handshake alert.

- **uvicorn `--ssl-ciphers`** (default `in 0.54.0: OpenSSL's own defaults`) sets TLS 1.2 cipher suites only. It has no effect on key exchange groups.

- **gunicorn `ciphers`** is the same: cipher suites, not groups.

- **Enforcing PQ-only** on the server (refusing classical clients) needs Python 3.15 `set_groups("X25519MLKEM768")`. Tested for gunicorn and uvicorn: the X25519-only client was refused. On 3.12 and 3.13 the same hook is a no-op, so the server still accepted X25519. Only do this for internal endpoints whose every client you control.

- **Flask** development server: `app.run(ssl_context=ctx)` takes an `SSLContext`, ([Werkzeug serving docs](https://werkzeug.palletsprojects.com/en/stable/serving/), Documented), so the same `set_groups` call should work on 3.15; not tested here. Don't use it in production.

- **Django** `runserver` has no TLS. Production Django and FastAPI run under gunicorn, uvicorn or hypercorn: use those rows.

- **gRPC server** in Python is PQ on any image because grpcio carries BoringSSL. A Go or Java gRPC peer must also offer ML-KEM; see those tabs.

Excerpt from `gunicorn.conf.py` (full file at the end):

``` python
def ssl_context(conf, default_ssl_context_factory):
    ctx = default_ssl_context_factory()
    if hasattr(ctx, "set_groups"):  # Python 3.15+
        ctx.set_groups(os.environ.get("PQ_GROUPS", "X25519MLKEM768:X25519:secp256r1"))
    return ctx
```

**Behind an ALB or NLB TLS listener (e2e, 2026-11-15):** with the load balancer modelled as the client on the target leg, an `ssl`-module HTTPS target on AL2023 Python 3.12 or `python:3.12-slim-bookworm` stayed classical; `OPENSSL_CONF=openssl-pq.cnf`, `DEFAULT:PQ` or `python:3.13-slim-trixie` gave X25519MLKEM768, with the same certificate (cases `srv-python-*`, Load balancers tab).

### C. Existing server certificates and key files

**Who this is:** a Python server that loads its own certificate and key. Find it with:

```bash
grep -rnE "load_cert_chain|ssl[-_]keyfile|ssl[-_]certfile|--keyfile|--certfile|keyfile *=|certfile *=|ssl_server_credentials|pkcs12|\.p12|\.pfx" .
```

Typical forms: `ssl.SSLContext.load_cert_chain(cert, key, password=...)`, uvicorn `--ssl-certfile/--ssl-keyfile[--ssl-keyfile-password]`, gunicorn `--certfile/--keyfile` or `certfile`/`keyfile` in `gunicorn.conf.py`, hypercorn `--certfile/--keyfile`, grpcio `ssl_server_credentials`, a PKCS#12/PFX file converted at startup, and paths passed through env vars such as `TLS_CERT`/`TLS_KEY`.

**What changes in the store: nothing.** The certificate and key are used to sign the handshake; ML-KEM only changes the key exchange. The same RSA or EC certificate, the same encrypted key and the same PKCS#12 file negotiated X25519MLKEM768 once the platform fix was in place. Do not re-issue certificates for PQ key exchange (ML-DSA certificates are a separate, later step: see the Certificates (ML-DSA) tab).

**What to change:** the platform fix only (trixie/alpine base, or `OPENSSL_CONF` on AL2023 and Lambda). Two exceptions, neither about PQ:

- **gunicorn with an encrypted key.** gunicorn has no key-password option. With `--keyfile` pointing at an encrypted key, the master starts and reports `Listening at: https://...`, but each worker fails with `OSError: [Errno 22] Invalid argument` and clients get `unexpected eof` (Tested). Load the key in the `ssl_context` hook and take the password from the environment (full `gunicorn-enc.conf.py` at the end):

  ```python
  def ssl_context(conf, default_ssl_context_factory):
      ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)  # don't call the factory: it loads the key without a password
      ctx.load_cert_chain(conf.certfile, conf.keyfile, password=os.environ["TLS_KEY_PASSWORD"])
      return ctx
  ```

- **PKCS#12 / PFX.** The stdlib `ssl` module cannot read PKCS#12. pyOpenSSL 26.4.0 no longer has `OpenSSL.crypto.load_pkcs12` (Tested: `hasattr(crypto, "load_pkcs12")` is False). Convert with cryptography at startup or at build time, then call `load_cert_chain` as usual:

  ```python
  from cryptography.hazmat.primitives.serialization import pkcs12, Encoding, PrivateFormat, NoEncryption
  key, cert, chain = pkcs12.load_key_and_certificates(open("server.p12", "rb").read(), password)
  # write key.private_bytes(Encoding.PEM, PrivateFormat.PKCS8, NoEncryption()) and the cert + chain PEM
  # to a tmpfs path readable only by the service user, then ctx.load_cert_chain(cert_path, key_path)
  ```

  Or once at build/deploy time: `openssl pkcs12 -in server.p12 -nodes -out server.pem` (keep the key file mode 0600). If you prefer to keep the key encrypted on disk, use `-aes256` and `load_cert_chain(..., password=...)`.

**Tested proof** (`out/d312.txt`, `out/d313.txt`, `out/al-conf.txt`; each row: a PQ-only client negotiated X25519MLKEM768 and an X25519-only client still connected):

| Server and store | Cert served | Result with the platform fix |
| --- | --- | --- |
| `ssl.SSLContext` + `load_cert_chain`, RSA 2048 PEM | RSA (`rsa_pss_rsae_sha256`) | X25519MLKEM768; classical client OK |
| `ssl.SSLContext` + `load_cert_chain`, EC P-256 PEM | EC (`ecdsa_secp256r1_sha256`) | X25519MLKEM768; classical client OK |
| `load_cert_chain(..., password="...")`, RSA encrypted (AES-256 PKCS#8) | RSA | X25519MLKEM768; classical client OK |
| `load_cert_chain(..., password=callable)`, EC encrypted | EC | X25519MLKEM768; classical client OK |
| RSA and EC in one context (two `load_cert_chain` calls) | EC to an ECDSA-only client, RSA to an RSA-only client | X25519MLKEM768 for both |
| SNI: `sni_callback` swaps to a second EC cert for `b.pqsrv` | The cert for the requested name | X25519MLKEM768 |
| PKCS#12 converted to PEM with cryptography 50.0.2 | EC | X25519MLKEM768; classical client OK |
| PKCS#12 through pyOpenSSL `crypto.load_pkcs12` | none | Not available in pyOpenSSL 26.4.0; use cryptography |
| uvicorn 0.54.0 `--ssl-certfile/--ssl-keyfile`, RSA and EC | RSA / EC | X25519MLKEM768; classical client OK |
| uvicorn `--ssl-keyfile-password`, RSA and EC encrypted | RSA / EC | X25519MLKEM768; classical client OK |
| gunicorn 27.0.1 `--certfile/--keyfile`, RSA and EC | RSA / EC | X25519MLKEM768; classical client OK |
| gunicorn `--keyfile` with an encrypted key | none | Workers fail (`OSError: [Errno 22]`); not a PQ issue |
| gunicorn encrypted key through the `ssl_context` hook | EC | X25519MLKEM768; classical client OK |

On Debian 12 (OpenSSL 3.0) and on AL2023 without the config, the same servers were classical-only in the earlier run (`deep/python/out/b312.txt`, `out/al.txt`): the certificate never makes a difference. grpcio servers with `ssl_server_credentials` were PQ on every image (earlier run). Not tested: hypercorn with an encrypted key, keys in an HSM or KMS (case I), Windows.

**Side effects:** none on the certificate side. The RSA-plus-EC context keeps serving RSA to old clients, as before.

### D. Custom CA trust (private CA, custom bundle, system store)

**Who this is:** a client that trusts a private CA (AWS Private CA, an internal root, a TLS-inspecting proxy root). Find it with:

```bash
grep -rnE "REQUESTS_CA_BUNDLE|SSL_CERT_FILE|SSL_CERT_DIR|AWS_CA_BUNDLE|CURL_CA_BUNDLE|cafile=|capath=|load_verify_locations|verify=['\"/]|certifi|truststore|ca_certs|root_certificates|GRPC_DEFAULT_SSL_ROOTS_FILE_PATH" . ; env | grep -E "CA_BUNDLE|SSL_CERT"
```

Also check Dockerfiles for `update-ca-certificates`, `update-ca-trust` or a line that appends a PEM to certifi's `cacert.pem`.

**What changes in the trust store: nothing.** Trust decides which server certificates are accepted; key exchange is negotiated before and apart from it. Every trust method below kept working against the PQ-only server once the platform fix was in place, and failed in the same way as before where it was already wrong.

**What to change:** the platform fix only. Keep your CA file and variables. Watch two things that are not PQ issues but often surface during the change:

- requests ignores `SSL_CERT_FILE` and the OS store; it uses certifi unless `REQUESTS_CA_BUNDLE`, `verify=` or truststore says otherwise (Tested). httpx 0.28.1 honours `SSL_CERT_FILE` but not the OS store by default (Tested).
- Moving the base image (bookworm to trixie, or to AL2023) resets the OS store. Re-add the CA in the new Dockerfile:
  - Debian/Ubuntu/Alpine: `COPY corp-root.pem /usr/local/share/ca-certificates/corp-root.crt` then `RUN update-ca-certificates`
  - AL2023: `COPY corp-root.pem /etc/pki/ca-trust/source/anchors/` then `RUN update-ca-trust extract`
  - A certifi bundle with the CA appended is overwritten by every `pip install -U certifi`. Prefer `REQUESTS_CA_BUNDLE` pointing at a combined file, or truststore.

**Tested proof, platform fix in place** (Debian 13 3.12 and 3.13, AL2023 3.12 + `OPENSSL_CONF`). "OK" = reached the PQ-only server and the classical-only server:

| Trust method | Result |
| --- | --- |
| `ssl.create_default_context(cafile=ca.pem)` | OK |
| `SSL_CERT_FILE=ca.pem` with `ssl.create_default_context()` | OK |
| CA added to the OS store, `ssl.create_default_context()` | OK |
| requests `REQUESTS_CA_BUNDLE=ca.pem` | OK |
| requests `verify="ca.pem"` | OK |
| requests with a certifi copy that has the CA appended | OK |
| requests with `SSL_CERT_FILE` only | Fails certificate verification on both servers: requests uses certifi (expected, not PQ) |
| requests with CA only in the OS store | Fails the same way (expected) |
| `truststore.inject_into_ssl()` (truststore 0.10.5) + requests, CA in the OS store | OK |
| `truststore.SSLContext(ssl.PROTOCOL_TLS_CLIENT)` | OK |
| httpx `verify=ssl.create_default_context(cafile=...)` | OK |
| httpx with `SSL_CERT_FILE` | OK |
| httpx with CA only in the OS store | Fails verification (uses certifi; expected) |
| aiohttp `ssl=ssl.create_default_context(cafile=...)` | OK |
| boto3 `AWS_CA_BUNDLE=ca.pem` (endpoint_url pointed at the test server) | TLS OK on both servers (the API call then times out because the test server is not STS) |
| Negative control: requests with stock certifi | Fails verification (proves verification was on) |

**Tested proof, Lambda python3.11 with the legacy shim** (`out/l311-shim.txt`; full table under case J). requests (`REQUESTS_CA_BUNDLE`, `verify=`, certifi with the CA appended) and boto3 (`AWS_CA_BUNDLE`) keep their custom CA and reach the PQ-only server through the shim. Raw `ssl`, httpx and aiohttp stay classical on OpenSSL 1.1.1, as expected. **`truststore.inject_into_ssl()` turns the shim off for requests**: the PQ-only server then fails. On python3.9 to 3.11 with the shim, use `REQUESTS_CA_BUNDLE` instead of truststore.

**Side effects:** none from PQ. truststore replaces `ssl.SSLContext` process-wide; it keeps the OpenSSL group list, so it stays PQ where the platform is PQ.

### E. Mutual TLS (client certificates)

**Who this is:** a client that presents a certificate, or a server that requires one. `grep -rnE "cert=\(|load_cert_chain|client_cert|ssl-cert-reqs|cert_reqs|CERT_REQUIRED|ssl_channel_credentials|require_client_auth" .`

**What happens today / with the fix:** the client certificate and key are unaffected. With the platform fix every client below completed mTLS with a PQ-only server that requires a client certificate, and with a classical-only one. Tested on Debian 13 3.12/3.13 and AL2023 3.12 + config.

| Client or server | Setting | Result |
| --- | --- | --- |
| requests | `cert=("client.pem", "client.key")`, `verify=ca` | OK (PQ-only and classical) |
| requests, no cert (negative) | | Refused: `TLSV13_ALERT_CERTIFICATE_REQUIRED` |
| `ssl` | `ctx.load_cert_chain(crt, key)` | OK |
| httpx 0.28.1 | `verify=ctx` with `ctx.load_cert_chain(crt, key)` | OK |
| httpx, encrypted client key | `ctx.load_cert_chain(crt, key, password=...)` | OK |
| aiohttp 3.14.5 | `ssl=ctx` with `load_cert_chain` | OK |
| boto3 | `Config(client_cert=(crt, key))` + `AWS_CA_BUNDLE` | TLS OK with the cert (API call then times out on the test server) |
| grpcio 1.85.1 client | `grpc.ssl_channel_credentials(root, key, chain)` | Server log: `Peer Temp Key: X25519MLKEM768`, `Peer certificate: CN=pq-client`, `Verification: OK` (BoringSSL, so PQ on every image) |
| `ssl` server | `verify_mode=CERT_REQUIRED` + `load_verify_locations(ca)` | X25519MLKEM768 with the client cert; without it the client gets `certificate required` |
| uvicorn | `--ssl-cert-reqs 2 --ssl-ca-certs ca.pem` | X25519MLKEM768 with the client cert |
| gunicorn | `--cert-reqs 2 --ca-certs ca.pem` | X25519MLKEM768 with the client cert |

requests cannot take a password for an encrypted client key; build an `ssl` context or use httpx. PKCS#12 client stores: convert as in case C.

**Side effects:** none. Lambda 3.9 to 3.11 with the shim: see case J.

### F. Explicit TLS settings that block PQ

**Who this is:** code or config that sets TLS versions, curves or ciphers by hand. Find it with `ci/pq-tls-lint.sh` (full file at the end) or:

```bash
grep -rnE "set_ecdh_curve|maximum_version|ssl_maximum_version|OP_NO_TLSv1_3|PROTOCOL_TLSv1|set_ciphers|ssl[-_]ciphers|set_groups|ssl\.curves\.list|OPENSSL_CONF" .
```

**What happens today** (Tested on Debian 13 3.12/3.13 and AL2023 + config; client against the PQ-only and classical-only servers, and Python servers probed by `s_client`):

| Setting | PQ-only peer | Classical peer | What to change it to |
| --- | --- | --- | --- |
| `ctx.set_ciphers("ECDHE+AESGCM:...")` (client or server), uvicorn `--ssl-ciphers`, gunicorn `ciphers` | OK, X25519MLKEM768 | OK | Nothing. It sets TLS 1.2 suites only |
| `ctx.minimum_version = TLSVersion.TLSv1_3` | OK | OK | Nothing |
| `ctx.maximum_version = TLSVersion.TLSv1_2` (client) | Fails: `TLSV1_ALERT_PROTOCOL_VERSION` | OK, TLS 1.2 | Remove it, or set `TLSv1_3` |
| `ctx.maximum_version = TLSv1_2` (server) | Fails | Fails for a TLS 1.3-only X25519 client; TLS 1.2 clients OK | Remove it |
| `ctx.options |= ssl.OP_NO_TLSv1_3` | Fails | OK, TLS 1.2 | Remove it |
| `ssl.SSLContext(ssl.PROTOCOL_TLSv1_2)` | Fails | OK, TLS 1.2 | `ssl.create_default_context()` or `PROTOCOL_TLS_CLIENT` / `PROTOCOL_TLS_SERVER` |
| urllib3 `PoolManager(ssl_maximum_version=TLSv1_2)` | Fails | OK | Remove it |
| `ctx.set_ecdh_curve("prime256v1")` (client) | Fails: handshake failure | Fails against an X25519-only server too | Remove it |
| `ctx.set_ecdh_curve("prime256v1")` (server) | Fails | Fails for an X25519-only client | Remove it |
| `ctx.set_ecdh_curve("X25519")` | Fails | OK | Remove it |
| `ctx.set_ecdh_curve("X25519MLKEM768")` | `ValueError: unknown elliptic curve name` | same | Not a group API; use `set_groups` on 3.15+, else the platform |
| `ctx.set_groups("X25519")` (3.15+) or confluent-kafka `ssl.curves.list` without ML-KEM | Fails | OK | Put `X25519MLKEM768` first, keep `X25519`. Not tested with `"X25519"` alone; `set_groups` replacing the whole list was Tested (`deep/python/out/t315.txt`) |
| `OPENSSL_CONF=/dev/null` or a custom conf without a `Groups` line on AL2023 | Classical | OK | Merge the `Groups` line from `openssl-pq.cnf` |

`set_ecdh_curve` is the trap: on OpenSSL 3 it replaces the whole group list with one classical curve, so it removes ML-KEM on any platform. Old code often has it from TLS 1.2 tuning.

**Side effects of removing them:** clients that only speak TLS 1.2 still work, because the defaults allow TLS 1.2.

### G. FIPS mode

**Who this is:** services on AL2023 with FIPS mode enabled (`fips-mode-setup --check`), images using a FIPS OpenSSL provider, awscrt with a FIPS policy, or FIPS AWS endpoints.

**What happens today:** Not tested for the `ssl` family; whether the AL2023 FIPS provider offers ML-KEM is not confirmed here (see the Hosts and OS tab). awscrt's FIPS policy `TLSv1_2_2025_07` lists only P-256 and P-384 in its docstring, so no PQ (Documented in the package). FIPS AWS endpoints don't use ML-KEM today.

**What to change:** nothing in Python. Treat FIPS paths as classical until the platform team confirms ML-KEM in the FIPS provider, and record them as exceptions.

**Side effects:** n/a.

### H. Libraries with their own TLS stack

**Who this is:** grpcio, awscrt (`boto3[crt]`, S3 transfer manager), confluent-kafka, psycopg `[binary]`, psycopg2-binary, pyOpenSSL. `pip list | grep -Ei '^(grpcio|awscrt|confluent-kafka|psycopg|psycopg2-binary|pyopenssl|cryptography) '`.

**What happens today:** PQ on every base image, including Debian 12 and AL2023 without the config (Tested, earlier run; tables above). The platform fix has no effect on them, and `OPENSSL_CONF` does not reach BoringSSL or s2n.

**What to change:** keep the wheels current. Building from source (`psycopg[c]`, `psycopg2`, `mysqlclient`) links the system OpenSSL instead and follows the `ssl` family (Unverified, from linkage). grpcio custom trust goes through `root_certificates=` or `GRPC_DEFAULT_SSL_ROOTS_FILE_PATH`, not `SSL_CERT_FILE`.

**Side effects:** one process can be PQ on gRPC and classical on requests at the same time. Inventory by library.

### I. Pinning, HSM/PKCS#11 and KMS-backed keys

**Who this is:** code that compares the peer certificate or public-key hash, or a server whose private key lives in an HSM, CloudHSM or KMS.

**What happens today:**

- **Certificate pinning:** unaffected. A pin on the SHA-256 of the peer certificate matched on the PQ-only server (Tested, `I cert pin` rows). Pins are on certificates, not key exchange.
- **HSM / PKCS#11 / KMS keys:** the stdlib `ssl` module cannot use them without an OpenSSL provider (for example pkcs11-provider) or a TLS-terminating proxy. The key only signs; ML-KEM key exchange is done in software either way, so PQ should not change this. Not tested.

**What to change:** nothing. Re-pin only when certificates change (for example to ML-DSA later).

**Side effects:** none.

### J. Other cases

**Lambda 3.9 to 3.11 shim and custom trust or mTLS.** Lambda `python:3.11` image, OpenSSL 1.1.1, `PYTHONPATH=/kit/pyshim:...` (`out/l311-shim.txt`):

| Path | PQ-only server | Classical server | Note |
| --- | --- | --- | --- |
| requests `REQUESTS_CA_BUNDLE=ca.pem` | OK | OK | Shim log: `urllib3 -> pyOpenSSL (OpenSSL 4.0.3 ...)` |
| requests `verify="ca.pem"` | OK | OK | |
| requests, certifi with the CA appended | OK | OK | |
| requests `cert=(crt, key)` (mTLS) | OK | OK | Without a cert: refused, as expected |
| boto3 `AWS_CA_BUNDLE=ca.pem` | TLS OK | TLS OK | Shim log: `botocore -> pyOpenSSL` |
| boto3 `Config(client_cert=(crt, key))` (mTLS) | TLS OK | TLS OK | |
| grpcio mTLS | OK (server log `Peer Temp Key: X25519MLKEM768`) | | BoringSSL; no shim needed |
| **truststore `inject_into_ssl()` + requests** | **Fails** | OK | truststore replaces the shim's pyOpenSSL context with a stdlib one on OpenSSL 1.1.1. Don't combine them; use `REQUESTS_CA_BUNDLE` |
| raw `ssl` (`cafile=`, `SSL_CERT_FILE`, OS store), httpx, aiohttp | Fails | OK | Not covered by the shim (expected). Upgrade to python3.12+ |
| urllib3 `ssl_maximum_version=TLSv1_2` | Fails | OK | Case F applies through the shim too |

Python 3.11.18, OpenSSL 1.1.1zb, cryptography 50.0.2 (OpenSSL 4.0.3), pyOpenSSL 26.4.0, truststore 0.10.5. Tested 2026-11-14.

**HTTPS proxy (`HTTPS_PROXY`).** With a CONNECT proxy the TLS session runs end to end between your client and the server, so the client's PQ setting applies. A TLS-inspecting proxy terminates TLS: then the proxy decides the key exchange on both legs (see the Network devices and egress tab). Not tested here.

**WebSockets, HTTP/2.** The `websockets` package, aiohttp WebSockets and h2/httpx HTTP/2 use the `ssl` family: platform fix only (Unverified for websockets; follows from the `ssl` module).

**Service mesh sidecar.** If Envoy or Linkerd originates mTLS for the pod, the sidecar decides (Service mesh tab). The app's own TLS, if any, still follows this tab.

**Child processes.** `OPENSSL_CONF` is inherited by `subprocess`, the AWS CLI and curl. Child programs that link GnuTLS (Debian curl/git builds) get no ML-KEM at all (2026-11-14 finding).

## Solution and automation

### Step 1: inventory and detect

1. **Platform per service:** run inside the deployed image, with the deployed env:

   ```bash
   python3 -c "import ssl,os; print(ssl.OPENSSL_VERSION, os.environ.get('OPENSSL_CONF'))"
   cat /etc/os-release | head -2; (update-crypto-policies --show 2>/dev/null || true)
   ```

2. **Libraries:** `pip list | grep -Ei '^(grpcio|awscrt|confluent-kafka|psycopg|psycopg2-binary|pyopenssl|cryptography|truststore|certifi) '`.
3. **Cases C to F:** run the grep lines from each case over the repo and the deployment repo (Dockerfiles, task definitions, Helm values).
4. **Live:** `pq_probe.py` against a PQ-only test server from inside the image (How to test).

### Step 2: change (packaging per compute type)

#### Lambda zip, python3.12 to 3.14

The runtime's OpenSSL 3.5 can do ML-KEM, but the AL2023 crypto policy leaves it out. Ship one file and one variable:

``` text
build/
  app.py
  pq-tls/openssl-pq.cnf      # keeps the AL2023 policy, changes only the group list
  <your dependencies>
```

- Set `OPENSSL_CONF=/var/task/pq-tls/openssl-pq.cnf` in SAM, CloudFormation or Terraform (full templates at the end).

- If the function already sets `OPENSSL_CONF`, merge the `Groups` line into that file instead.

- Fleet option without repackaging: publish the kit's `pq-tls` layer and set `AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper`. The wrapper sets `OPENSSL_CONF` for python3.12+ and the shim for 3.9 to 3.11, and leaves a function's own `OPENSSL_CONF` alone. If the function already uses a wrapper (Datadog, OpenTelemetry), chain it with `PQ_TLS_NEXT_WRAPPER`.

SAM excerpt:

``` yaml
      Runtime: python3.13
      Environment:
        Variables:
          OPENSSL_CONF: /var/task/pq-tls/openssl-pq.cnf
```

#### Lambda zip, python3.10 and 3.11 (Amazon Linux 2, OpenSSL 1.1.1)

No config file helps the `ssl` family here. python3.10 was deprecated on 31 Oct 2026 and python3.11 is deprecated on 30 Jun 2027; updates to both are blocked from 31 Aug 2027 ([Lambda runtimes](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html)).

1.  **Preferred:** change `Runtime` to `python3.13` and follow the section above.

2.  **Bridge:** add `pq-tls/pyshim/sitecustomize.py`, plus `pyopenssl`, `cryptography` **and `idna`**, installed inside the Lambda image of the same Python version and architecture:

    ```bash
    docker run --rm --entrypoint sh -v "$PWD/build:/out" public.ecr.aws/lambda/python:3.11 \
      -c 'pip install --target /out cryptography==50.0.2 pyOpenSSL==26.4.0 idna==3.20'
    ```

    Set `PYTHONPATH=/var/task/pq-tls/pyshim`. Covers urllib3, requests and boto3 (Tested on the 3.9, 3.10 and 3.11 Lambda images; e2e `py-lambda-py39/310/311-bundled-shim`). For a layer, install into `python/lib/python3.X/site-packages` instead of the package root.

    - **`idna` is required.** pyOpenSSL's urllib3 integration uses it to encode the host name and the Lambda runtime doesn't ship it. Without it the shim still logs `urllib3 -> pyOpenSSL`, then every urllib3, requests and boto3 request raises `ModuleNotFoundError: No module named 'idna'` (Tested: e2e `py-lambda-py311-shim-noidna`). Check for `idna` in the package before rollout.
    - **Build once per Python version.** The cryptography wheel pip picks on 3.11 is abi3 and fails to import on 3.9 and 3.10 (`PyType_GetName`). `pip install --platform manylinux2014_...` also hides cryptography 50.x. Installing inside each version's image avoids both.

3.  Bundled-TLS wheels (grpcio, awscrt, confluent-kafka, psycopg binary) don't need either step: see the tables in "Versions and native support".

#### Lambda container image

Same file and variable, set in the Dockerfile on `public.ecr.aws/lambda/python:3.12` or later (full `Dockerfile.lambda` at the end):

``` dockerfile
COPY pq-tls/openssl-pq.cnf ${LAMBDA_TASK_ROOT}/pq-tls/openssl-pq.cnf
ENV OPENSSL_CONF=/var/task/pq-tls/openssl-pq.cnf
```

#### Fargate, ECS and EKS

Pick the base image first; the Python version matters much less.

| Base image | OpenSSL | `ssl` family PQ out of the box | Action |
|----|----|----|----|
| `python:3.x-slim-trixie` (Debian 13) | 3.5.7 | Yes (3.11, 3.12, 3.13, 3.15 tested) | None |
| `python:3.x-alpine` (Alpine 3.24) | 3.5.9 | Yes (3.12 tested) | None |
| `python:3.x-slim-bookworm` (Debian 12) | 3.0.x | No | Move to trixie or alpine; nothing adds ML-KEM to OpenSSL 3.0 |
| `amazonlinux:2023` + `python3.12` | 3.5.8 | No: crypto policy omits ML-KEM | Ship `openssl-pq.cnf` with `ENV OPENSSL_CONF`, or `update-crypto-policies --set DEFAULT:PQ` in the Dockerfile (both tested) |
| Ubuntu 24.04 | 3.0.x | No | Move to one of the above |

The container's env var lives in the task definition (`environment`) or pod spec (`env`) if you prefer it outside the image. Add a build-time guard so an image regression fails CI:

``` dockerfile
RUN python -c "import ssl,sys; sys.exit(0 if ssl.OPENSSL_VERSION_INFO >= (3,5) else 'OpenSSL < 3.5')"
```

On AL2023 that guard is not enough: also run `pq_probe.py` against a PQ-only test server in CI.

#### EC2

- **Amazon Linux 2023:** either one service (`Environment=OPENSSL_CONF=/etc/pq-tls/openssl-pq.cnf` in its systemd unit) or the whole host (SSM document running `update-crypto-policies --set DEFAULT:PQ`, then restart services). Both files at the end. Host-wide details are in the Hosts and OS tab.

- **Amazon Linux 2:** OpenSSL 1.1.1; migrate the host. AL2 reached end of life on 30 Jun 2026.

- **Ubuntu 24.04 / Debian 12 hosts:** OpenSSL 3.0; the `ssl` family cannot be fixed in place. Run the service in a trixie or alpine container, or move the host OS.

Existing certificates, keys and CA bundles move with the service unchanged. When you change the base image, carry over the OS-store step (case D) and any key-password plumbing (case C).

### Step 3: CI guardrails

- **Lint:** `sh ci/pq-tls-lint.sh src/` fails the build on the case F settings (full file at the end). Tested: it flagged `maximum_version=TLSv1_2`, `OP_NO_TLSv1_3`, `PROTOCOL_TLSv1_2`, `set_ecdh_curve` and `ssl_maximum_version` in the test files, and passed `set_groups("X25519MLKEM768:X25519")`. Mark a reviewed line with `# pq-tls: allow`.
- **Image gate:** the Dockerfile `RUN python -c "...OPENSSL_VERSION_INFO >= (3,5)..."` line from Step 2. On AL2023 also assert the config: `RUN test "$OPENSSL_CONF" = /etc/pq-tls/openssl-pq.cnf`.
- **Handshake gate:** in the pipeline, start the PQ-only harness (`pq-harness.sh`) as a service container and run `pq_probe.py pqsrv:8443` and, for servers, `probe-server.sh app:8443` inside the built image. Both must pass.
- **Policy:** deny base images `python:*-bookworm`, `ubuntu:24.04` and `amazonlinux:2` in your image policy (for example an ECR pull-through rule or an OPA/Kyverno check). Exact policy syntax is in the Enforcement and guardrails tab.

### Step 4: fleet rollout, canary and rollback

1. Change one service per platform type first: one Lambda (env var), one ECS service (image), one EC2 unit.
2. Deploy to one task, pod or Lambda alias (weighted alias 10%). Watch error rate and latency for a day; PQ adds about 1 KB to the ClientHello.
3. Confirm the signal: CloudTrail `tlsDetails.keyExchange = X25519MLKEM768` for KMS, STS, IAM, Secrets Manager, ACM calls from that role; or `SSLSocket.group()` logs on 3.15.
4. Widen by account or OU. Keep the rollback table (Pitfalls) with the change ticket.

## How to test

Run these in the same image, env and user as the service. Steps 1 to 4 need no AWS account.

1. **Posture and live checks.** Run these five checks:
   1.  **Posture (build or deploy time).** Run inside the same image, with the same env:

       ``` bash
       python3 -c "import ssl,os; print(ssl.OPENSSL_VERSION, os.environ.get('OPENSSL_CONF'))"
       pip list 2>/dev/null | grep -Ei '^(grpcio|awscrt|confluent-kafka|psycopg|psycopg2-binary|pyopenssl|cryptography) '
       ```

       `ssl` family: OpenSSL must be 3.5 or later. On AL2023 also check `OPENSSL_CONF` or `update-crypto-policies --show` (`DEFAULT:PQ`). Bundled-TLS wheels: compare versions with the client table.

   2.  **Live test, PQ-only server must succeed.** Start a test server: `openssl s_server -accept 8443 -cert c.pem -key k.pem -groups X25519MLKEM768 -tls1_3 -www`. Then run `pq_probe.py pqsrv:8443` (file at the end) with `SSL_CERT_FILE` pointing at the test CA. On 3.15 it prints the group: `RESULT pqsrv:8443 TLSv1.3 group=X25519MLKEM768` (Tested). Before 3.15 a successful connection is the proof, because the PQ-only server refuses anything else.

   3.  **Live test, classical-only server must still work.** Same server with `-groups X25519`. The probe prints `group=x25519` on 3.15 and must not fail (Tested). This proves fallback.

   4.  **Server side.** From any OpenSSL 3.5 host: `openssl s_client -connect svc:8443 -groups X25519MLKEM768 -tls1_3 -brief` must print `Negotiated TLS1.3 group: X25519MLKEM768`, and `-groups X25519` must still connect.

   5.  **Observed in production.**

       - CloudTrail `tlsDetails.keyExchange` on the workload's calls to KMS, STS, IAM, Secrets Manager, ACM and Payment Cryptography shows `X25519MLKEM768`. Other services don't log it.

       - On 3.15, log `SSLSocket.group()` once per dependency at startup (excerpt in case A).

       - Lambda: the legacy shim writes `pq-tls: python legacy shim: urllib3 -> pyOpenSSL` and `botocore -> pyOpenSSL` to CloudWatch Logs on cold start.

2. **Start the harness.** `pq-harness.sh` (full file at the end) starts a PQ-only server on 8443, a classical-only one on 8444, and the mTLS pair on 8451/8452, all signed by a throw-away CA. Run it in any `python:3.13-slim-trixie` or `debian:trixie-slim` container on the same Docker network.
3. **Case A/D client test:** `SSL_CERT_FILE=/certs/ca.pem python3 pq_probe.py pqsrv:8443` must print `RESULT ... connected` (or `group=X25519MLKEM768` on 3.15). `pqsrv:8444` must also connect. Repeat with your real trust setting (`REQUESTS_CA_BUNDLE`, the OS store, truststore) by pointing your own client code at the harness and trusting its CA.
4. **Case C/B server test:** start your server with its real cert and key files, then `sh probe-server.sh app:8443`. Expect `Negotiated TLS1.3 group: X25519MLKEM768` on the first line and a connection on the second.
5. **Case E:** `curl`-free check with requests: `python3 -c "import requests; print(requests.get('https://pqsrv:8451/', verify='/certs/ca.pem', cert=('/certs/client.pem','/certs/client.key')).status_code)"` must print 200. For a server that requires client certs, `sh probe-server.sh app:8443 -cert client.pem -key client.key`.
6. **Case F:** `sh ci/pq-tls-lint.sh .` must print `clean`.
7. **In the cloud:** CloudTrail `tlsDetails.keyExchange` as in Step 4 of the rollout.
8. **Rollback test:** remove `OPENSSL_CONF` (or redeploy the old image) in a test environment and rerun step 3: the PQ-only probe must now fail and the classical one pass. This proves the probe detects a regression.

The container test kit used for this tab is `run-python.sh`, `pyclients.py`, `srv.sh` and `pgsrv.sh` (work dir `deep/python/`). It runs every library above against PQ-only and classical-only servers, including PostgreSQL 18 with `ssl_groups`.

The case C to F tests for this tab are `deep/python/v2/run-v2.sh` with `cases.py`, `servers.py`, `srv2.sh` and `mkcerts.sh`.

## Pitfalls and rollback

- **Silent fallback.** Every failure mode here still connects with X25519. Nothing breaks, so only a PQ-only test or a logged group proves the change.

- **One process, two answers.** On Debian 12 or AL2023 without the config, requests and boto3 are classical while grpcio, awscrt, confluent-kafka and psycopg binary wheels are PQ (Tested). Inventory by library, not by service.

- **Building from source changes the answer.** `psycopg[c]`, `psycopg2` (not `-binary`) and `mysqlclient` link the system libraries, so they lose the bundled OpenSSL. Wheels for a new Python can also lag: on 3.15 pip picked `confluent-kafka 4.4.0b1`, whose build lacked the client classes, so Kafka was not tested on 3.15.

- **`set_ecdh_curve` is not a group API.** It rejects `X25519MLKEM768` on every version tested. Use `set_groups` on 3.15+, or the platform fix.

- **`set_groups` replaces the whole list.** `set_groups("X25519MLKEM768")` on a client refuses classical servers; on a server it refuses classical clients (both Tested). Keep `X25519` (and `secp256r1` if peers need it) unless you mean to enforce.

- **`OPENSSL_CONF` is process-wide and inherited.** Child processes (subprocess, `aws` CLI, `curl`) read it too. If the function or image already sets it, merge your Groups line into that file instead of overwriting. Don't use `OPENSSL_CONF=/dev/null`: it drops the AL2023 crypto policy.

- **`DEFAULT:PQ` on a host changes every OpenSSL, GnuTLS and NSS program.** Prefer the per-service `Environment=OPENSSL_CONF` in the systemd unit when only one service should change.

- **Legacy Lambda shim.** It covers urllib3, requests and boto3 only, overrides botocore's choice of the stdlib context, and adds pyOpenSSL plus cryptography (about 15 MB unpacked, measured) to the package. Remove it when the function moves to python3.12+.

- **FIPS.** awscrt's `TLSv1_2_2025_07` policy and FIPS endpoints don't use ML-KEM today. A FIPS requirement can block PQ for that path.

- **Python 3.15 on Lambda is a public preview** (since 25 Aug 2026), outside the Lambda SLA. Don't move production to it for `set_groups` alone.

- **`set_ecdh_curve` removes ML-KEM.** On OpenSSL 3 it replaces the group list with one curve, so a client or server that calls it is classical even on trixie (Tested). Remove the call.

- **Max TLS 1.2 anywhere removes PQ.** `maximum_version`, `OP_NO_TLSv1_3`, `PROTOCOL_TLSv1_2` and urllib3 `ssl_maximum_version` all block it (Tested).

- **gunicorn and encrypted keys.** `--keyfile` with an encrypted key looks healthy (`Listening at`) but every worker fails. Use the `ssl_context` hook (Tested).

- **pyOpenSSL has no `load_pkcs12`.** Convert PKCS#12 with cryptography (Tested on 26.4.0).

- **Base-image moves reset the OS trust store** and certifi upgrades drop an appended CA. Re-add the CA in the new Dockerfile, or use `REQUESTS_CA_BUNDLE` / truststore.

- **requests and httpx don't read the OS store** by default (Tested). That is not a PQ problem, but it shows up when the base image changes.

- **truststore and the Lambda legacy shim don't mix.** `truststore.inject_into_ssl()` puts requests back on the stdlib `ssl` module, which is OpenSSL 1.1.1 on python3.9 to 3.11, so the PQ-only server fails (Tested). Use `REQUESTS_CA_BUNDLE` until the runtime upgrade.

**Rollback** (each is one change, no code):

| Change | Roll back |
|----|----|
| `OPENSSL_CONF` in Lambda, task definition, pod spec or systemd | Remove the variable and redeploy or restart. |
| Legacy shim | Remove `PYTHONPATH=/var/task/pq-tls/pyshim`, or set `PQ_TLS_DISABLE=1`. |
| AL2023 `DEFAULT:PQ` policy | `update-crypto-policies --set DEFAULT`, then restart the services. |
| Base image moved to trixie | Redeploy the previous image digest. |
| `set_groups` in code | Set `PQ_GROUPS` to include `X25519`, or remove the call. |

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
