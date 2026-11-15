<!--
python-v2.md: the complete restructured Python tab (doc 44a97a0f-a862-42b5-a154-764d72d41549, file 35b45b8c-c6f8, body 610684f0-aa35).
Doc rev when read: 21. Every block id below is from that rev. In the outline the short ids (.4950) are mttvddjsrgd.<n>.

HOW TO APPLY (for the lead)
1. Keep the H1 title block mttvddjsrgd.0.
2. After .0, insert one pending block per section (7 sections, in the order below). Fill each with the markdown between
   its "=== SECTION n ===" markers. Where the text says [MOVED: ids], do not retype: `move` those blocks to that spot
   (after the section's last new block written so far), in the order listed.
3. After every move is done, delete only the old headings listed in "DELETE AFTER MOVES" (guard with ifRev 21 + ifHash).
   Every other old block is moved, not deleted.
4. Two old blocks get small in-place text edits (listed in "IN-PLACE EDITS").

DELETE AFTER MOVES (old headings and one intro line that would duplicate the new structure)
- mttvddjsrgd.4950  h=034e5461  "## What decides PQ here"
- mttvddjsrgd.35568 h=19adaecb  "## Status matrix"
- mttvddjsrgd.6482  h=5c83cda5  "## Client side (app level)"
- mttvddjsrgd.9661  h=10c001f7  "### Excerpts"
- mttvddjsrgd.10892 h=95a1ce86  "## Server side"
- mttvddjsrgd.18393 h=c26d6f86  "## Packaging per compute type"   (replaced by the new "### Step 2 ..." heading)
- mttvddjsrgd.13821 h=eea2745e  "## Verify"
- mttvddjsrgd.13828 h=fd73bd49  "Check three things for each service: ..."  (replaced by the new How to test lead)

IN-PLACE EDITS (as text, keep chips/links)
- mttvddjsrgd.35582 "By compute type (the ssl family: ...)" heading: change level 3 -> 4 is NOT needed; leave as ###.
  The moved H3s (By compute type, By library, Lambda zip ..., EC2) sit under ## sections, which is correct.
- mttvddjsrgd.18420 "### Lambda zip, python3.12 to 3.14" ... these H3 headings under "Solution and automation" are fine as is.
-->

# Python runbook

=== SECTION 1 ===

## Problem statement

A Python service that runs on the wrong base image talks classical TLS today: it negotiates X25519 or P-256 with no ML-KEM, so traffic it sends or receives can be recorded now and decrypted later by a quantum computer (harvest-now-decrypt-later). Nothing fails, so nobody notices. Python itself has no PQ switch. The handshake is controlled by whichever TLS library each package uses:

- **The `ssl` family** (`ssl`, `http.client`, `urllib`, requests, urllib3, boto3/botocore, httpx, aiohttp, redis-py, PyMySQL, uvicorn, gunicorn, hypercorn): the OpenSSL that the interpreter links, from the base image or host, plus that OpenSSL's config (`OPENSSL_CONF`, the AL2023 crypto policy). PQ needs OpenSSL 3.5+ with ML-KEM in the group list.
- **Wheels that bundle their own TLS** (grpcio, awscrt, confluent-kafka, psycopg `[binary]`, psycopg2-binary, pyOpenSSL via cryptography): the wheel version. Current wheels are already PQ on every base image tested.

The fix for most teams is a base-image change or one environment variable. Existing certificates, key files, PKCS#12 stores and CA bundles do not change: key exchange is negotiated separately from the certificate (cases C and D, Tested).

[MOVED: mttvddjsrgd.4971, mttvddjsrgd.5139, mttvddjsrgd.5969, mttvddjsrgd.6148]
<!-- .4971 "In Python the TLS library, not the Python version, decides...", .5139 family table, .5969 "So the first question...", .6148 "Python 3.15 (released 9 Oct 2026) adds set_groups()..." -->

=== SECTION 2 ===

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

[MOVED: mttvddjsrgd.35582, mttvddjsrgd.35657, mttvddjsrgd.36750, mttvddjsrgd.36805, mttvddjsrgd.37509, mttvddjsrgd.37962]
<!-- "### By compute type" + table, "### By library" + table, the test note, the Gaps note -->

=== SECTION 3 ===

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

[MOVED: mttvddjsrgd.6506, mttvddjsrgd.6767, mttvddjsrgd.9670, mttvddjsrgd.9756, mttvddjsrgd.10182, mttvddjsrgd.10266, mttvddjsrgd.10452, mttvddjsrgd.10518, mttvddjsrgd.10617, mttvddjsrgd.10655, mttvddjsrgd.10793]
<!-- rule of thumb, client library table, the excerpts (pin groups for requests on 3.15, log group, awscrt, confluent-kafka) -->

### B. Simple server

**Who this is:** uvicorn, gunicorn, hypercorn or a grpcio server that terminates TLS in the Python process (HTTPS target group, NLB TCP passthrough, in-VPC service-to-service). If an ALB, API Gateway or CloudFront terminates TLS, Python's settings do not decide the client-facing handshake.

**What happens today:** PQ on trixie and on AL2023 with the config; classical on bookworm and on AL2023 without it. grpcio is PQ everywhere. Tested.

**What to change:** the platform fix only. On 3.15 you can also pin or enforce the group list in code (excerpts below).

**Side effects:** classical clients keep working unless you enforce PQ-only with `set_groups`.

[MOVED: mttvddjsrgd.10904, mttvddjsrgd.11348, mttvddjsrgd.11596, mttvddjsrgd.12298, mttvddjsrgd.12528, mttvddjsrgd.13428, mttvddjsrgd.13482]
<!-- where TLS ends, server table, test note, uvicorn/gunicorn ciphers bullets, gunicorn excerpt -->

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

**Child processes.** `OPENSSL_CONF` is inherited by `subprocess`, the AWS CLI and curl. Child programs that link GnuTLS (Debian curl/git builds) get no ML-KEM at all (lead's 2026-11-14 finding).

=== SECTION 4 ===

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

[MOVED: mttvddjsrgd.18420, mttvddjsrgd.18451, mttvddjsrgd.18568, mttvddjsrgd.18690, mttvddjsrgd.19239, mttvddjsrgd.19252, mttvddjsrgd.19372, mttvddjsrgd.19436, mttvddjsrgd.19628, mttvddjsrgd.20157, mttvddjsrgd.20180, mttvddjsrgd.20309, mttvddjsrgd.20427, mttvddjsrgd.20448, mttvddjsrgd.20513, mttvddjsrgd.21081, mttvddjsrgd.21258, mttvddjsrgd.21360, mttvddjsrgd.21454, mttvddjsrgd.21458]
<!-- Lambda zip 3.12-3.14 (+SAM excerpt), Lambda zip 3.10/3.11, Lambda container image, Fargate/ECS/EKS (+base image table, build guard), EC2 -->

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

=== SECTION 5 ===

## How to test

Run these in the same image, env and user as the service. Steps 1 to 4 need no AWS account.

1. **Posture.**

   [MOVED: mttvddjsrgd.13956]
   <!-- the old 5-step Verify list moves here whole: posture, PQ-only must succeed, classical must still work, server side, observed in production -->

2. **Start the harness.** `pq-harness.sh` (full file at the end) starts a PQ-only server on 8443, a classical-only one on 8444, and the mTLS pair on 8451/8452, all signed by a throw-away CA. Run it in any `python:3.13-slim-trixie` or `debian:trixie-slim` container on the same Docker network.
3. **Case A/D client test:** `SSL_CERT_FILE=/certs/ca.pem python3 pq_probe.py pqsrv:8443` must print `RESULT ... connected` (or `group=X25519MLKEM768` on 3.15). `pqsrv:8444` must also connect. Repeat with your real trust setting (`REQUESTS_CA_BUNDLE`, the OS store, truststore) by pointing your own client code at the harness and trusting its CA.
4. **Case C/B server test:** start your server with its real cert and key files, then `sh probe-server.sh app:8443`. Expect `Negotiated TLS1.3 group: X25519MLKEM768` on the first line and a connection on the second.
5. **Case E:** `curl`-free check with requests: `python3 -c "import requests; print(requests.get('https://pqsrv:8451/', verify='/certs/ca.pem', cert=('/certs/client.pem','/certs/client.key')).status_code)"` must print 200. For a server that requires client certs, `sh probe-server.sh app:8443 -cert client.pem -key client.key`.
6. **Case F:** `sh ci/pq-tls-lint.sh .` must print `clean`.
7. **In the cloud:** CloudTrail `tlsDetails.keyExchange` as in Step 4 of the rollout.
8. **Rollback test:** remove `OPENSSL_CONF` (or redeploy the old image) in a test environment and rerun step 3: the PQ-only probe must now fail and the classical one pass. This proves the probe detects a regression.

[MOVED: mttvddjsrgd.15660]
<!-- "The container test kit used for this tab is run-python.sh ..." -->

The case C to F tests for this tab are `deep/python/v2/run-v2.sh` with `cases.py`, `servers.py`, `srv2.sh` and `mkcerts.sh`.

=== SECTION 6 ===

## Pitfalls and rollback

[MOVED: keep in place mttvddjsrgd.15891 (heading), mttvddjsrgd.15913 (list), mttvddjsrgd.17906, mttvddjsrgd.17946]

Add these bullets to the end of list mttvddjsrgd.15913:

- **`set_ecdh_curve` removes ML-KEM.** On OpenSSL 3 it replaces the group list with one curve, so a client or server that calls it is classical even on trixie (Tested). Remove the call.
- **Max TLS 1.2 anywhere removes PQ.** `maximum_version`, `OP_NO_TLSv1_3`, `PROTOCOL_TLSv1_2` and urllib3 `ssl_maximum_version` all block it (Tested).
- **gunicorn and encrypted keys.** `--keyfile` with an encrypted key looks healthy (`Listening at`) but every worker fails. Use the `ssl_context` hook (Tested).
- **pyOpenSSL has no `load_pkcs12`.** Convert PKCS#12 with cryptography (Tested on 26.4.0).
- **Base-image moves reset the OS trust store** and certifi upgrades drop an appended CA. Re-add the CA in the new Dockerfile, or use `REQUESTS_CA_BUNDLE` / truststore.
- **requests and httpx don't read the OS store** by default (Tested). That is not a PQ problem, but it shows up when the base image changes.
- **truststore and the Lambda legacy shim don't mix.** `truststore.inject_into_ssl()` puts requests back on the stdlib `ssl` module, which is OpenSSL 1.1.1 on python3.9 to 3.11, so the PQ-only server fails (Tested). Use `REQUESTS_CA_BUNDLE` until the runtime upgrade.

=== SECTION 7 ===

## Full configuration files

[MOVED: keep in place mttvddjsrgd.21994 ... mttvddjsrgd.33673, all existing files]

Append after mttvddjsrgd.33673 (pq_probe.py):

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
