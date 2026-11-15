## Client side (app level)

Rule of thumb: for the `ssl` family, fix the platform (base image, `OPENSSL_CONF` or crypto policy) and leave the code alone. For bundled-TLS wheels, keep the wheel current. Code changes are only needed to pin the group list (3.15+) or to log the negotiated group.

| Library (tested version) | TLS stack | What to set | Evidence |
| --- | --- | --- | --- |
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

### Excerpts

Pin the group list for requests on Python 3.15+ (most services should not need this):

```python
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

```python
with socket.create_connection((host, 443)) as raw, ctx.wrap_socket(raw, server_hostname=host) as s:
    log.info("tls", extra={"host": host, "version": s.version(), "group": s.group()})
```

awscrt, explicit PQ policy (not needed with the current default):

```python
from awscrt import io
opts = io.TlsContextOptions()
opts.cipher_pref = io.TlsCipherPref.PQ_DEFAULT
```

confluent-kafka, explicit group list:

```python
Producer({"bootstrap.servers": "b-1.msk.example:9094", "security.protocol": "SSL",
          "ssl.curves.list": "X25519MLKEM768:X25519"})
```

The Kafka broker or Amazon MSK must also accept ML-KEM; a client offer alone falls back to X25519.
