<!--
Node.js tab, v2 restructure (BRIEF-LANG-V2). Doc 44a97a0f-a862-42b5-a154-764d72d41549, tab d69fae22-fa1f, body d02c414f-ccd4, read at rev 12.
How to apply:
  * Keep the H1 block mttvddjsrgd.0.
  * [MOVED: ids] = move those existing blocks (keep ids/comments) to this spot, in the order listed. Full ids carry the prefix mttvddjsrgd (e.g. .3667 = mttvddjsrgd.3667).
  * [DELETE: ids] at the end lists old headings/blocks that become duplicates.
  * Everything else is new text to insert.
  * Pitfalls: keep table .17875 and add the rows listed under "Pitfalls and rollback" (row insert at its end).
Evidence for every "Tested" claim in cases C-F and I: scratchpad/deep/node/v2/out-*.txt, matrix.md (summary), out-lambda-rie.txt, out-pin.txt, out-legacy-pfx.txt, ci-check.out.
-->

# Node.js runbook  [KEEP: mttvddjsrgd.0]

## Problem statement

Most Node.js services on AWS already negotiate hybrid post-quantum key exchange (X25519MLKEM768) without any change, but three groups don't: Lambda nodejs22.x/24.x functions, anything on Node 20 or older (or 22.0–22.19, 24.0–24.4), and code that pins TLS groups or caps TLS at 1.2. On those paths the session keys come from classical X25519 or P-256 alone. An attacker who records the traffic today can decrypt it once a large quantum computer exists ("harvest now, decrypt later"). Data with a long confidentiality life (credentials, personal data, payment data) is at risk now, not later.

Who controls the handshake: the OpenSSL inside the `node` process (bundled in official builds, the system library in distro builds), then the OpenSSL config file Node reads, then the TLS options in code. The OS crypto policy matters only for distro-built Node. Certificates, private keys, key stores, CA bundles and client certificates do not take part in the key-exchange choice: every existing-certificate, custom-trust and mutual-TLS setup tested below kept working unchanged (cases C, D, E).

[MOVED: .3667, .3994, .4335]

## Versions and native support

Tested 2026-11-14 against an OpenSSL 3.5.7 PQ-only server (`-groups X25519MLKEM768 -tls1_3`) and a classical-only server (`-groups X25519`). "Yes" = the PQ-only server was accepted with no setting, and the classical server still worked.

| Version | TLS stack | PQ client by default (Lambda / container image / EC2 or AL2023) | PQ server by default | API to set groups | FIPS-mode behaviour | Proposed solution | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Official 24.5+ (tested 24.5.0, 24.9.0, 24.22.3) | Bundled OpenSSL 3.5.x (24.22.3 = 3.5.9) | Lambda `nodejs24.x`: **No** (bootstrap config) / `node:24`, `-slim`, `-alpine`: Yes / official tarball on EC2: Yes | Yes; on Lambda No (same config) | `ecdhCurve` option, `tls.DEFAULT_ECDH_CURVE`, OpenSSL `Groups` via `OPENSSL_CONF` or `--openssl-config` | `--enable-fips` needs an OpenSSL FIPS provider you configure; official builds ship none. ML-KEM under FIPS: not tested | Lambda: ship `openssl-pq-node.cnf` (or the `pq-tls` layer). Elsewhere: nothing | Tested |
| Official 22.20+ (tested 22.20.0, 22.23.5) | Bundled OpenSSL 3.5.x (22.23.5 = 3.5.9) | Lambda `nodejs22.x`: **No** / `node:22` images: Yes / EC2: Yes | Yes; Lambda No | same | same | same | Tested |
| Official 26.x (tested 26.13.1) | Bundled OpenSSL 3.5.9 | `nodejs26.x` preview: not tested / `node:26-slim`: Yes / EC2: Yes | Yes | same | same | nothing | Tested (container) |
| Official 22.0–22.19, 24.0–24.4 | Bundled OpenSSL 3.0.x | No / No / No | No | `ecdhCurve`; a PQ-first string throws `ERR_CRYPTO_OPERATION_FAILED` | n/a | Upgrade to 22.20+ or 24.9+ | Tested (22.19.0, 24.4.1) |
| 20.x, 18.x (`nodejs20.x` deprecated Apr 30 2026) | Bundled OpenSSL 3.0.x | No / No / No | No | as above, PQ-first throws | n/a | Upgrade; no setting adds PQ | Tested (`node:20-slim`, `node:20-alpine` 20.20.2) |
| AL2023 `dnf install nodejs22` (22.23.4) | System OpenSSL 3.5.8 + crypto policy | n/a / No / No until `update-crypto-policies --set DEFAULT:PQ` | No (same policy) | as above, plus the crypto policy | AL2023 FIPS mode uses the system FIPS provider; ML-KEM there not tested | `DEFAULT:PQ`, or `OPENSSL_CONF` = `openssl-pq-node-system.cnf` | Tested (`amazonlinux:2023`) |
| Debian 13 `apt install nodejs` (20.19.2) | System OpenSSL 3.5.7 | n/a / Yes / Yes | Yes | as above | not tested | nothing (check `process.versions.openssl`, not the major) | Tested (`debian:trixie-slim`) |
| Alpine 3.22 `apk add nodejs` (22.23.5) | System OpenSSL 3.5.9 | n/a / Yes / n/a | Yes | as above | not tested | nothing | Tested (`alpine:3.22`) |
| Deno 2.9.8 / Bun 1.4.4 | rustls / BoringSSL | n/a / Yes (client) / Yes | not tested | runtime-specific | not tested | nothing | Tested (client, `denoland/deno`, `oven/bun`) |

FIPS source: [Node CLI docs, `--enable-fips`](https://nodejs.org/api/cli.html#--enable-fips) ("a configured provider named `fips` must be available", Documented). The upstream OpenSSL 3.5.4 FIPS module was submitted for FIPS 140-3 validation in October 2025 ([OpenSSL announcement](https://mirror.openssl-library.org/post/2025-10-09-ossl3.5.4-fips-submission/)); I found no issued certificate, so a FIPS-validated ML-KEM path for Node is not confirmed.

[MOVED: .6494]

Decision guide:

- Lambda `nodejs22.x` or `nodejs24.x`: set `OPENSSL_CONF=/var/task/pq-tls/openssl-pq-node.cnf` (or attach the `pq-tls` layer). Nothing else in the function changes.
- Lambda `nodejs18.x`/`nodejs20.x`, or any Node below 22.20 / 24.5: upgrade the runtime or base image. There is no setting.
- Container or EC2 on official Node 22.20+/24.5+: nothing to change. Run the CI check (case F) to make sure no code pins groups or TLS 1.2.
- Distro Node on AL2023: set the host or image crypto policy to `DEFAULT:PQ`, or ship the system config file.
- Your code sets `ecdhCurve`, `tls.DEFAULT_ECDH_CURVE`, `maxVersion: 'TLSv1.2'`, `secureProtocol: 'TLSv1_2_method'` or `--tls-max-v1.2`: change it (case F).
- You load your own certificates, keys, PFX files, CA bundles or client certificates: nothing to change in them (cases C, D, E). The one exception found: legacy RC2/3DES PFX files fail on every Node 17+ build regardless of PQ; re-export them (case C).

## Cases: what to change

Find your situation below. Each case names who it applies to, what happens today, what to change and the test behind it. Unless a row says otherwise, "Tested" means all four runtimes gave the same result: `node:22` (22.23.5, `node@sha256:e13726ca…`), `node:24` (24.22.3, `node@sha256:9d266751…`), and `public.ecr.aws/lambda/nodejs:22` / `:24` (22.23.5 / 24.22.3) with `OPENSSL_CONF` set to the kit's `openssl-pq-node.cnf`. The same Lambda images with AWS's own file (`/var/runtime/openssl_conf/openssl.cnf`) were run as the "before" baseline.

### A. Simple client (default fetch, HTTP client, AWS SDK, DB driver)

**Who this is:** you call `fetch`, axios, got, node-fetch, the AWS SDK v3, a database or cache driver, and pass no TLS options. `grep -rnE "ecdhCurve|DEFAULT_ECDH_CURVE|maxVersion|secureProtocol|tls-max-v1" src/` finds nothing.

**What happens today:** PQ on official Node 22.20+/24.5+ in containers and EC2; classical on Lambda nodejs22/24 until the config is overridden; classical on Node 20 and older. Every tested library inherits Node's defaults (Tested).

**What to change:** nothing, except on Lambda (see Solution and automation) and on old runtimes (upgrade).

**Side effects:** the ClientHello grows by about 1.2 KB (the ML-KEM key share). Classical-only servers still negotiate X25519 (Tested).

[MOVED: .6814, .7154, .7967, .8095, .8251, .9724, .10042]

### B. Simple server (https, http2, Express, Fastify, grpc-js)

**Who this is:** `https.createServer`, `http2.createSecureServer`, `tls.createServer`, Express or Fastify over HTTPS, or a grpc-js server, configured with only a key and certificate.

**What happens today:** on 22.20+/24.5+ the server accepts X25519MLKEM768 and still serves classical and TLS 1.2 clients (Tested). Inside a Lambda function with AWS's config, a Node TLS server is classical too: PQ-only clients were refused on all servers in the case C matrix (Tested, baseline run).

**What to change:** nothing. Behind an ALB the client-facing handshake is the load balancer's.

[MOVED: .10848, .11090, .12107, .12372, .12754]

### C. Existing server certificates, keys and PFX files

**Who this is:** your server loads its own certificate and key, from files, a mounted secret, Secrets Manager, or env vars that point at files. Find it with:

```bash
grep -rnE "pfx|passphrase|SNICallback|addContext|createSecureContext|(key|cert)[[:space:]]*:[[:space:]]*(fs\.)?readFileSync|\.(pem|key|crt|pfx|p12)['\"]" --include='*.js' --include='*.mjs' --include='*.cjs' --include='*.ts' src/
```

Node has no global key store: there is no equivalent of `javax.net.ssl.keyStore`. Certificates always reach `tls.createSecureContext` as PEM or PFX buffers, whether a framework reads them for you (Fastify `https`, NestJS `httpsOptions`) or your code does. So the tests below cover every source: they differ only in where the bytes come from.

**What changes in the store: nothing.** The key exchange group is chosen separately from the certificate. The same files served X25519MLKEM768 to a PQ client and X25519 to a classical client, with no edit.

**What happens today (Tested):** each row is one Node server, probed with `openssl s_client` 3.5.7 as a PQ-only client (`-groups X25519MLKEM768 -tls1_3`), a classical client (`-groups X25519:secp256r1`) and a TLS 1.2 client. All four runtimes gave identical results; with AWS's Lambda file every PQ-only probe failed (handshake failure) and every classical probe passed.

| Server setup (code excerpt) | PQ-only client | Classical / TLS 1.2 client | Change needed |
| --- | --- | --- | --- |
| RSA 2048 PEM: `{ key, cert }` | X25519MLKEM768, RSA cert | X25519, RSA cert | none |
| EC P-256 PEM | X25519MLKEM768, EC cert | X25519, EC cert | none |
| RSA + EC in one context: `{ key: [rsaKey, ecKey], cert: [rsaCert, ecCert] }` | X25519MLKEM768, EC cert by default; RSA cert to an RSA-only client (`-sigalgs RSA-PSS+SHA256:RSA+SHA256`) | X25519, EC cert | none |
| Encrypted PKCS#8 EC key: `{ key, cert, passphrase }` | X25519MLKEM768 | X25519 | none |
| Encrypted traditional RSA PEM (`Proc-Type`/`DEK-Info`) + `passphrase` | X25519MLKEM768 | X25519 | none |
| PFX, RSA or EC, OpenSSL 3 default encryption (AES-256, PBKDF2): `{ pfx, passphrase }` | X25519MLKEM768 | X25519 | none |
| Legacy PFX (RC2-40 / 3DES, as exported by older Windows and Java tools) | server fails to start: `ERR_CRYPTO_UNSUPPORTED_OPERATION Unsupported PKCS12 PFX data` | same | Re-export the PFX (below). Not caused by the PQ change: it fails the same with AWS's file and on Node 20 |
| `SNICallback` picking RSA (a.test), EC P-256 (b.test), EC P-384 (c.test), RSA default | right cert per name, X25519MLKEM768 | right cert, X25519 | none |
| `server.addContext('b.test', { pfx, passphrase })` with an RSA default | right cert per name, X25519MLKEM768 | right cert, X25519 | none |
| Express 5.3.0 on `https.createServer` (EC) | X25519MLKEM768 | X25519 | none |
| Fastify 5.12.8 `fastify({ https: { pfx, passphrase } })` | X25519MLKEM768 | X25519 | none |
| `http2.createSecureServer({ key, cert, allowHTTP1, SNICallback })` | X25519MLKEM768 for every name | X25519 | none (see note) |

```js
// Existing patterns that need no change (all Tested with X25519MLKEM768)
https.createServer({ key: fs.readFileSync(process.env.TLS_KEY), cert: fs.readFileSync(process.env.TLS_CERT) }, app);
https.createServer({ key: [rsaKey, ecKey], cert: [rsaCert, ecCert] }, app);           // RSA + EC
https.createServer({ key: encryptedPem, cert, passphrase: process.env.TLS_KEY_PASS }, app);
https.createServer({ pfx: fs.readFileSync('/etc/app/tls/server.pfx'), passphrase }, app);
const ctx = { 'a.test': tls.createSecureContext(rsa), 'b.test': tls.createSecureContext(ec) };
https.createServer({ ...rsa, SNICallback: (name, cb) => cb(null, ctx[name]) }, app);   // SNI
```

Legacy PFX fix (Tested: the converted file loads on all four runtimes; the original loads on official Node only with `--openssl-legacy-provider`, and not on the Lambda nodejs24 image even with that flag ("Unable to load legacy provider")):

```bash
openssl pkcs12 -in old.pfx -legacy -nodes -passin env:PFX_PASS -out tmp.pem
openssl pkcs12 -export -in tmp.pem -out new.pfx -passout env:PFX_PASS && shred -u tmp.pem
```

Note on http2 with `SNICallback`: on Node 22.23.5 the RSA context returned for a.test was not used and the EC default was served; Node 24.22.3 served the RSA cert. This was the same with and without the PQ config, so it is not PQ-related. Not investigated further.

**Side effects:** none observed. The `passphrase`, PFX, SNI and multi-certificate behaviour is identical before and after the change.

**Proof:** `srv.cjs` and `run-cases.sh` (Full configuration files); outputs `out-node22.txt`, `out-node24.txt`, `out-lambda22-pq.txt`, `out-lambda24-pq.txt`, baseline `out-lambda2{2,4}-aws.txt`, legacy PFX `out-legacy-pfx.txt`.

### D. Custom CA trust (private CA, bundles, system store)

**Who this is:** your client trusts a private CA. Find it with:

```bash
grep -rnE "NODE_EXTRA_CA_CERTS|SSL_CERT_FILE|SSL_CERT_DIR|use-openssl-ca|use-system-ca|NODE_USE_SYSTEM_CA|setDefaultCACertificates|[^a-zA-Z]ca[[:space:]]*:" src/ Dockerfile* *.tf *.yaml *.json 2>/dev/null
```

**What changes in the trust store: nothing.** The PQ change touches only the key-exchange group list. The Lambda override file holds nothing but a `Groups` line, so it cannot change trust. Every trust method below verified the private-CA server and negotiated X25519MLKEM768.

**What happens today (Tested):** client connections to the PQ-only and classical servers, whose certificate chains to a private CA that is not in Node's bundled Mozilla list. Clients tried: `tls.connect`, `https.get` (default agent), global `fetch`, and an npm undici `Agent`.

| Trust method | node:22, node:24 | Lambda 22/24 with `openssl-pq-node.cnf` | Change needed |
| --- | --- | --- | --- |
| `ca: fs.readFileSync('ca.pem')` in `tls.connect`, `https.Agent`, undici `connect` | PQ, verified | PQ, verified | none |
| `NODE_EXTRA_CA_CERTS=/path/ca.pem` (CA alone, or a bundle with several CAs) | PQ, verified | PQ, verified; also under the Runtime Interface Emulator with the real bootstrap | none |
| `--use-openssl-ca` (flag or in `NODE_OPTIONS`) + `SSL_CERT_FILE=bundle.pem` | PQ, verified | PQ, verified | none |
| `--use-system-ca` + `SSL_CERT_FILE` | PQ, verified | PQ, verified | none |
| `NODE_USE_SYSTEM_CA=1` + `SSL_CERT_FILE` | PQ, verified | PQ, verified | none |
| CA added to the OS store (`update-ca-certificates` on Debian, `update-ca-trust` on AL2023), then `--use-system-ca` or `--use-openssl-ca`, no `SSL_CERT_FILE` | PQ, verified (Debian store) | **fails** `UNABLE_TO_VERIFY_LEAF_SIGNATURE`, before and after the PQ change | Lambda only: also set `SSL_CERT_FILE=/etc/pki/tls/certs/ca-bundle.crt` (see below) |
| `tls.setDefaultCACertificates([...tls.getCACertificates('default'), pem])` at startup | PQ, verified (tls and fetch) | PQ, verified | none |
| No private CA anywhere (negative test) | fails verification, as expected | fails verification | n/a |

The Lambda system-store finding: the Lambda Node binary links AWS's own shared OpenSSL, whose default certificate directory is a build path. Node prints `Cannot open directory /local/p4clients/pkgbuild-const/workspace/src/Openssl/build/private/install/ssl/certs to load OpenSSL certificates.` and `tls.getCACertificates('system')` returns 0 certificates. With `SSL_CERT_FILE=/etc/pki/tls/certs/ca-bundle.crt` it returns 136 (Tested, nodejs24 image). This is independent of PQ. The real runtime may differ from the base image here; I'm not sure, as no AWS account was available.

Lambda bootstrap and `NODE_EXTRA_CA_CERTS`: the bootstrap keeps your value. It sets its own value (`/etc/pki/tls/certs/ca-bundle.crt`) only when the variable is unset and the region name has three dashes (read from `/var/runtime/bootstrap` in both images). Under the emulator with the real bootstrap (Tested, `out-lambda-rie.txt`):

| nodejs22 and nodejs24 | PQ-only server, CA via `NODE_EXTRA_CA_CERTS` | PQ-only server with mTLS | Classical server |
| --- | --- | --- | --- |
| `OPENSSL_CONF` = PQ file + `NODE_EXTRA_CA_CERTS` | OK, X25519MLKEM768 | OK, X25519MLKEM768 | OK, X25519 |
| AWS default config + `NODE_EXTRA_CA_CERTS` | handshake failure | handshake failure | OK, X25519 |
| PQ file, no `NODE_EXTRA_CA_CERTS` (negative) | `UNABLE_TO_VERIFY_LEAF_SIGNATURE` | `SELF_SIGNED_CERT_IN_CHAIN` | `UNABLE_TO_VERIFY_LEAF_SIGNATURE` |

Flag availability (checked, not assumed): `--use-system-ca`, `--use-openssl-ca` and `--use-bundled-ca` all appear in `node --help` on 22.23.5 and 24.22.3, and `--use-system-ca` works on Linux on both. The docs say `--use-system-ca` was added in v23.8.0, with non-Windows/macOS support in v23.9.0, and list no v22 backport; `NODE_USE_SYSTEM_CA=1` was added in v24.6.0 and v22.19.0 ([Node CLI docs](https://nodejs.org/api/cli.html#--use-system-ca), Documented). So on 22.x, check that your exact version has the flag (`node --help | grep use-system-ca`). `NODE_EXTRA_CA_CERTS` is read only at process start, and is ignored when code passes `ca:` explicitly (Documented, same page).

```js
// Existing trust patterns that need no change (Tested with X25519MLKEM768)
https.request({ host, ca: fs.readFileSync('/etc/app/ca/private-ca.pem') });   // ca option
new undici.Agent({ connect: { ca: privateCa } });                              // undici / fetch dispatcher
// NODE_EXTRA_CA_CERTS=/etc/app/ca/private-ca.pem node server.js               // env var
// SSL_CERT_FILE=/etc/app/ca/bundle.pem node --use-openssl-ca server.js        // OpenSSL store
tls.setDefaultCACertificates([...tls.getCACertificates('default'), privateCaPem]);
```

**Side effects:** none from the PQ change. Note `ca:` replaces the default roots for that connection; that is existing Node behaviour, unchanged.

**Proof:** `cli.cjs` groups `trust-none`, `trust-ca-option`, `trust-env`, `trust-api`; `run-cases.sh`; `run-lambda-rie.sh` + `fn/index.js`; outputs as in case C plus `out-lambda-rie.txt`.

### E. Mutual TLS (client certificates)

**Who this is:** your client sends a certificate (`key`/`cert` or `pfx` in `tls.connect`, `https.Agent`, undici `connect`, an AWS SDK `NodeHttpHandler` agent), or your server sets `requestCert: true`.

**What happens today (Tested):** against an OpenSSL PQ-only server that requires and verifies a client certificate (`-Verify 1 -verify_return_error`), and a classical one:

| Client | PQ-only server, cert required | Classical server, cert required | Without a cert |
| --- | --- | --- | --- |
| `tls.connect({ key, cert, ca })`, EC P-256 client cert | X25519MLKEM768 | X25519 | `ERR_SSL_TLSV13_ALERT_CERTIFICATE_REQUIRED` |
| same with an RSA client cert | X25519MLKEM768 | | |
| encrypted PKCS#8 key + `passphrase` | X25519MLKEM768 | | |
| `pfx` + `passphrase` | X25519MLKEM768 | | |
| `https.Agent({ key, cert, ca })` + `https.get` | 200, X25519MLKEM768, server saw the cert | | |
| npm undici `Agent({ connect: { key, cert, ca } })` with `undici.request` or `undici.fetch` | 200 | | |
| Global `fetch` with an npm undici 8.12.4 `Agent` as `dispatcher` | **fails** `UND_ERR_INVALID_ARG: invalid onRequestStart method` | | Not PQ: Node bundles undici 6.29.1 (22) / 7.30.2 (24). Use `fetch` from the same undici package as the `Agent` |
| AWS SDK v3 `S3Client` with `requestHandler: new NodeHttpHandler({ httpsAgent: new https.Agent({ key, cert, ca }) })` | 200 (GetObject) | | `ERR_SSL_TLSV13_ALERT_CERTIFICATE_REQUIRED` |

Server side: `https.createServer({ key, cert, ca, requestCert: true, rejectUnauthorized: true })`: a PQ client with a valid cert got X25519MLKEM768 and the app saw `cn=client`; a PQ client without a cert got `alert certificate required`; a classical client with a cert got X25519 (Tested).

Under the Lambda emulator, mTLS to the PQ-only server worked with the PQ file and failed with AWS's file (table in case D).

**What to change:** nothing in the certificates, keys or agents.

**Side effects:** TLS 1.3 behaviour to know: the client's `secureConnect` fires before the server checks the client cert, so a missing cert shows up as an error on the first read, not on connect (Tested: the no-cert `tls.connect` first reported success, then `CERTIFICATE_REQUIRED`). Health checks that only wait for `secureConnect` can report false success. This is TLS 1.3, not PQ.

```js
// mTLS client patterns that need no change (Tested with X25519MLKEM768)
const mtls = { key: fs.readFileSync('client.key'), cert: fs.readFileSync('client.pem'), ca: privateCa };
https.get({ host, agent: new https.Agent(mtls) });
const { Agent, fetch } = require('undici');            // fetch and Agent from the same package
await fetch(url, { dispatcher: new Agent({ connect: mtls }) });
new S3Client({ requestHandler: new NodeHttpHandler({ httpsAgent: new https.Agent(mtls) }) });
```

### F. Explicit TLS settings that block PQ

**Who this is:** code or config sets `ecdhCurve`, `tls.DEFAULT_ECDH_CURVE`, `maxVersion`, `secureProtocol`, `tls.DEFAULT_MAX_VERSION`, `ciphers`, or a `--tls-*` flag in `NODE_OPTIONS`. Find them with `ci/check-node-tls.sh` (below) or the grep in How to test.

**What happens today (Tested, client and server, all four runtimes):**

| Setting | Client → PQ-only server | Client → classical server | Server ← PQ-only client | Change to |
| --- | --- | --- | --- | --- |
| `ecdhCurve: 'X25519:P-256'` | handshake failure | X25519 | handshake failure; every PQ client silently downgraded to X25519 | remove, or `'X25519MLKEM768:X25519:P-256:P-384'` |
| `tls.DEFAULT_ECDH_CURVE = 'X25519:P-256'` | handshake failure (also global `fetch`) | | | remove |
| `ecdhCurve: 'auto'` | PQ | X25519 | PQ | nothing (follows the OpenSSL config; on Lambda with AWS's file it stays classical) |
| `ecdhCurve: 'X25519MLKEM768:X25519:P-256:P-384'` | PQ, even with AWS's Lambda file | X25519 | PQ | recommended when a list is required |
| server `ecdhCurve: 'X25519MLKEM768'`, `minVersion: 'TLSv1.3'` | | | PQ only; classical and TLS 1.2 clients refused | only for deliberate PQ-only enforcement |
| `ciphers` with only TLS 1.2 suites, or `--tls-cipher-list=...` | PQ (TLS 1.3 suites are separate) | X25519 | PQ | nothing |
| `ciphers: 'TLS_AES_256_GCM_SHA384'` | PQ | X25519 | | nothing |
| `maxVersion: 'TLSv1.2'`, `tls.DEFAULT_MAX_VERSION = 'TLSv1.2'`, `--tls-max-v1.2` | `protocol version` alert | TLS 1.2, X25519 | `protocol version` alert | remove the cap, or `maxVersion: 'TLSv1.3'` |
| `secureProtocol: 'TLSv1_2_method'` | `protocol version` alert | TLS 1.2 | `protocol version` alert | replace with `minVersion: 'TLSv1.2'` |
| `secureProtocol: 'TLS_method'` | PQ | X25519 | | nothing |
| `secureProtocol: 'TLSv1_3_method'` | throws `ERR_TLS_INVALID_PROTOCOL_METHOD` | throws | | use `minVersion: 'TLSv1.3'` |
| `minVersion: 'TLSv1.3'`, `--tls-min-v1.3` | PQ | X25519 (server supports 1.3) | | nothing |
| `sigalgs: 'ECDSA+SHA256:RSA-PSS+SHA256'` | PQ | X25519 | | nothing (no effect on groups) |

[MOVED: .9343, .9376, .10235, .10489]

### G. FIPS mode

**Who this is:** you start Node with `--enable-fips` or `--force-fips`, call `crypto.setFips(true)`, or point `OPENSSL_CONF` at a config that activates a FIPS provider.

**What happens today:** official Node builds include no FIPS provider; FIPS mode needs one you install and configure ([Node CLI docs](https://nodejs.org/api/cli.html#--enable-fips), Documented). Whether X25519MLKEM768 is negotiated under a FIPS provider was not tested here. A FIPS-validated OpenSSL 3.5 module with ML-KEM is not confirmed (submitted October 2025, [OpenSSL](https://mirror.openssl-library.org/post/2025-10-09-ossl3.5.4-fips-submission/)).

**What to change:** if you already set `OPENSSL_CONF` for FIPS, don't replace it with the kit file (the layer leaves your value alone). Add the `Groups` line to a `system_default` section of your own file, then test with the PQ-only server. Unverified.

**Side effects:** for AWS endpoints in FIPS mode, see the AWS service endpoints tab: the FIPS endpoints' PQ support is separate.

### H. Libraries and agents with their own TLS stack

| Component | TLS stack | PQ follows Node? | Evidence |
| --- | --- | --- | --- |
| fetch/undici, axios, got, node-fetch, AWS SDK v3 (`NodeHttpHandler`), @grpc/grpc-js, pg, mysql2, ioredis, kafkajs | `node:tls` | yes | Tested (case A table) |
| Native addons with their own OpenSSL or TLS: node-rdkafka (librdkafka), oracledb Thick mode (Oracle Client), `aws-crt` (AWS CRT, s2n-tls on Linux), older Prisma engines | their own | not necessarily | Not tested. Find them with `find node_modules -name '*.node'` and probe each against the PQ-only server |
| Child processes: `curl`, `git`, `wget` from `child_process` | the binary's library | GnuTLS builds have no ML-KEM; OpenSSL-linked curl works | Tested by the lead (GnuTLS on Debian 13, Ubuntu 26.04) |
| APM and tracing exporters (dd-trace, OpenTelemetry OTLP/HTTP) | `node:http(s)` | expected yes | Unverified |
| Deno, Bun | rustls / BoringSSL | own defaults (PQ) | Tested (client) |

### I. Certificate or key pinning, HSM and KMS-backed keys

**Pinning:** an SPKI SHA-256 pin checked in `checkServerIdentity` keeps working with X25519MLKEM768, and a wrong pin is still rejected (Tested, all four runtimes, `pin.cjs`). The key exchange doesn't change the server's certificate or key, so existing pins stay valid. Pins on ML-DSA certificates are a separate change (see Certificates (ML-DSA)).

**HSM / PKCS#11 / KMS:** the server's private key only signs the handshake; the ML-KEM key exchange is ephemeral and doesn't use it. Node can load keys through OpenSSL engines (`privateKeyEngine`, `privateKeyIdentifier`, `clientCertEngine`); engines are deprecated in OpenSSL 3 and this path was not tested. Node has no hook for a KMS-held TLS key: terminate TLS at an ALB/NLB with ACM instead (see Load balancers). Unverified for HSM-backed keys.

### J. Other cases

- **HTTPS proxy (`HTTPS_PROXY`, CONNECT tunnel):** the TLS session runs end to end from Node through the tunnel, so the PQ outcome is Node's. A TLS-inspecting proxy re-terminates and its own stack decides (see Network devices and egress). Not tested here.
- **HTTP/2 and gRPC servers:** covered in B and C (Tested).
- **WebSockets (`wss://` with `ws`):** uses `node:tls`, expected to follow Node. Not tested.
- **Service mesh sidecar:** the app speaks plaintext to the sidecar; the mesh decides (see Service mesh).
- **`NODE_TLS_REJECT_UNAUTHORIZED=0` or `rejectUnauthorized: false`:** doesn't affect PQ, but turns off the trust checks that cases D and E rely on. Remove it while you are in the code.

## Solution and automation

1. **Inventory and detect.** List Lambda runtimes and overrides, report every Node process on EC2 with the SSM document, and scan repositories with the CI check.

[MOVED: list item 6 of .15977 (aws lambda list-functions) — or keep it in How to test and reference it]

2. **Change: packaging per compute type.** Lambda zip and image need the config file; containers and EC2 on official Node need nothing.

[MOVED: .12952, .12988, .13393, .13970, .14125, .14204, .14331, .14429, .14726, .14749, .14920, .14938, .15188, .15591, .15595]

3. **CI guardrails.** Run `ci/check-node-tls.sh` on every repository. It fails the build on classical `ecdhCurve` / `DEFAULT_ECDH_CURVE` lists, TLS 1.2 caps, `nodejs18.x`/`nodejs20.x`, `OPENSSL_CONF` pointing at AWS's file, and `node` base images below 22.20 / 24.5, and warns on `node_modules` that set these options. Tested against fixtures: 9 findings in the bad set, none in the good set (`ci-check.out`). A reviewed exception carries `pq-tls-ok` on the same line. Add `RUN node pq-check.js` in Dockerfiles, and `check-lambda-node-conf.sh` in the pipeline that bumps the Lambda base image.

```yaml
# GitHub Actions step
- name: PQ TLS guardrail (Node.js)
  run: bash ci/check-node-tls.sh .
```

4. **Fleet rollout with canary and rollback.**
    - Lambda: publish a version with `OPENSSL_CONF` set, shift 10% with alias weighted routing ([Lambda alias routing](https://docs.aws.amazon.com/lambda/latest/dg/configuring-alias-routing.html), Documented), watch errors and latency, then move to 100%. Rollback = shift the alias back.
    - ECS/Fargate: the official-image services need no change. For distro-Node images, deploy with the deployment circuit breaker and rollback on. EKS: a rolling update with a readiness probe on the TLS port.
    - EC2: change the systemd unit or the crypto policy on one instance per Auto Scaling group first, then the launch template.
    - Signal: CloudTrail `tlsDetails.keyExchange` for KMS, STS, IAM, Secrets Manager and ACM calls from the canary role.

## How to test

[MOVED: .15977]  (the existing 6-step Verify list: posture, live client test, live server test, observed signal, code scan, fleet inventory)

Case tests (each script is in Full configuration files; run them on a laptop or CI runner with Docker; no AWS account needed):

1. Create a private CA, RSA/EC server certs, encrypted keys, PFX files and client certs: `bash gen-certs.sh` inside an OpenSSL 3.5 container (debian:trixie-slim with `openssl`). Replace them with copies of your own files to test your real store.
2. Start the four reference servers: `bash start-ossl.sh` (PQ-only 4431, classical 4432, PQ-only with client cert required 4433, classical with client cert 4434).
3. Run the whole case matrix for one runtime: `bash run-cases.sh node24 node@sha256:<digest> -`, and for Lambda `bash run-cases.sh lambda24-pq public.ecr.aws/lambda/nodejs@sha256:<digest> /k/openssl-pq-node.cnf`. Expect: every PQ-only probe shows `X25519MLKEM768`, every classical probe `X25519`, the case F blockers fail, the legacy PFX fails.
4. Case C on your own server: start it in the same Docker network and probe with `openssl s_client -connect <host>:<port> -groups X25519MLKEM768 -tls1_3 -brief` (must print `Negotiated TLS1.3 group: X25519MLKEM768` and your certificate), then `-groups X25519` (must connect), then `-tls1_2` (must connect if you support TLS 1.2). For SNI add `-servername <name>`; for an RSA+EC store add `-sigalgs RSA-PSS+SHA256:RSA+SHA256` to see the RSA cert.
5. Case D with your trust setup: run `node cli.cjs trust-env` with your `NODE_EXTRA_CA_CERTS` / `SSL_CERT_FILE` / flags, against servers whose cert chains to your CA. `trust-none` must fail.
6. Case E: `node cli.cjs mtls` with your client cert files in place of `client.pem`/`client.key`. The negative rows must fail with `CERTIFICATE_REQUIRED`.
7. Lambda with the real bootstrap: `bash run-lambda-rie.sh` (Runtime Interface Emulator, host port 18661+).
8. Rollback test: rerun step 3 or 7 without `OPENSSL_CONF`. PQ-only targets must fail and classical ones must still pass; that proves the setting was what made the difference.

Results of this run, 2026-11-14: about 170 checks on each of 6 runtime setups (node:22, node:24, Lambda 22 and 24 with and without the PQ file), plus 6 emulator invocations, 8 pinning checks, 4 PFX checks and the CI fixtures. All matched the expected result except three findings that are not caused by PQ: legacy PFX, global `fetch` with an npm undici 8 dispatcher, and the Lambda image's empty system store.

## Pitfalls and rollback

[KEEP: .17853 heading, .17875 table, .19408 rollback paragraph]

Add these rows to table .17875 (columns: Pitfall | Effect | Fix | Evidence):

| Pitfall | Effect | Fix | Evidence |
| --- | --- | --- | --- |
| Legacy PFX (RC2-40/3DES) | server or mTLS client fails to start: `Unsupported PKCS12 PFX data`; the Lambda nodejs24 image cannot load the legacy provider (`Unable to load legacy provider`) | re-export with `openssl pkcs12 -legacy` then `-export` | Tested |
| Global `fetch` with a `dispatcher` from a different undici major | `UND_ERR_INVALID_ARG: invalid onRequestStart method` | import `fetch` and `Agent` from the same `undici` package | Tested (undici 8.12.4 on Node 22/24) |
| Lambda image: CA added to the OS store, `--use-system-ca`/`--use-openssl-ca` without `SSL_CERT_FILE` | no system CAs load; private CA not trusted | set `SSL_CERT_FILE=/etc/pki/tls/certs/ca-bundle.crt`, or use `NODE_EXTRA_CA_CERTS` | Tested (base image; real runtime not checked) |
| TLS 1.3 mTLS without a client cert | `secureConnect` fires, error arrives on first read | check the first response, not just the connect | Tested |
| `secureProtocol: 'TLSv1_3_method'` | throws `ERR_TLS_INVALID_PROTOCOL_METHOD` | `minVersion: 'TLSv1.3'` | Tested |
| Lambda AWS config also governs Node servers inside the function | PQ-only clients refused | same `OPENSSL_CONF` fix | Tested |
| Your own `OPENSSL_CONF` (FIPS or other) | the kit file would replace it | merge the `Groups` line into your file | Unverified (carried over) |

## Full configuration files

[KEEP: .19783 heading through .32339, unchanged]

Append the following new files at the end of the tab (after .32339). All were run in this pass except where noted.

The test scripts expect the test directory mounted at `/w` (certs in `/w/certs`) and an npm project mounted at `/n/app` with express, fastify, undici, @aws-sdk/client-s3 and @smithy/node-http-handler installed (`npm i` inside a node container). `run-cases.sh` also mounts the kit dir `pq-tls/` at `/k`.


`ci/check-node-tls.sh` (CI guardrail; Tested against fixtures, ci-check.out)

```bash
#!/bin/bash
# CI guardrail: fail the build when Node.js code, config or IaC carries a setting that blocks hybrid PQ key exchange.
# Usage: ci/check-node-tls.sh [repo-dir]     (exit 1 on findings; add "pq-tls-ok" on a line to allow it after review)
set -uo pipefail
root="${1:-.}"; rc=0
src=(--include='*.js' --include='*.mjs' --include='*.cjs' --include='*.ts' --include='*.mts' --include='*.cts')
cfg=(--include='*.json' --include='*.yaml' --include='*.yml' --include='*.tf' --include='Dockerfile*' --include='*.env' --include='*.service' --include='*.sh')
skip=(--exclude-dir=.git --exclude-dir=dist --exclude-dir=coverage)
hit() { # label, grep args...
  local label=$1; shift
  local out; out=$(grep -rnE "$@" "$root" 2>/dev/null | grep -v 'pq-tls-ok')
  [ -n "$out" ] && { echo "::error::$label"; echo "$out" | head -50; rc=1; }
}
# 1. Pinned group lists without the hybrid group (client or server, ecdhCurve or the module default)
#    (a list that starts with a classical group; 'auto' and lists starting X25519MLKEM768 pass)
hit "ecdhCurve / DEFAULT_ECDH_CURVE starts with a classical group" "${src[@]}" "${skip[@]}" --exclude-dir=node_modules \
    -e "(ecdhCurve|DEFAULT_ECDH_CURVE|TLS_ECDH_CURVE)[\"']?[[:space:]]*[:=][[:space:]]*['\"\`](X25519[:'\"\`]|x25519|X448|P-|prime|secp|brainpool|ffdhe)"
# 2. TLS 1.2 caps (no TLS 1.3 = no ML-KEM)
hit "TLS 1.2 cap (maxVersion / secureProtocol / DEFAULT_MAX_VERSION / --tls-max-v1.2)" "${src[@]}" "${cfg[@]}" "${skip[@]}" --exclude-dir=node_modules \
    -e "maxVersion[[:space:]]*:[[:space:]]*['\"]TLSv1(\.[012])?['\"]" -e "DEFAULT_MAX_VERSION[[:space:]]*=[[:space:]]*['\"]TLSv1(\.[012])?['\"]" \
    -e "secureProtocol[[:space:]]*:[[:space:]]*['\"]TLSv1(_[12])?_(client_|server_)?method['\"]" -e "tls-max-v1\.[0-2]"
# 3. Lambda: OPENSSL_CONF pointing at AWS's classical file, or Node runtimes with no fix
hit "Lambda nodejs18.x/20.x runtime (OpenSSL 3.0: no PQ)" "${cfg[@]}" "${skip[@]}" --exclude-dir=node_modules -e "nodejs(18|20)\.x"
hit "OPENSSL_CONF set to the Lambda runtime's classical file" "${cfg[@]}" "${skip[@]}" -e "OPENSSL_CONF.{0,20}/var/runtime/openssl_conf"
# 4. Base images below the PQ floor (22.20 / 24.5; 20 and older never)
hit "node base image below 22.20 / 24.5" --include='Dockerfile*' "${skip[@]}" \
    -e "FROM[[:space:]]+(docker\.io/)?(library/)?node:(1[0-9]|20|21|23)([.-]|$|@|[[:space:]])" \
    -e "FROM[[:space:]]+(docker\.io/)?(library/)?node:22\.(1?[0-9])([.-]|@|[[:space:]]|$)" \
    -e "FROM[[:space:]]+(docker\.io/)?(library/)?node:24\.[0-4]([.-]|@|[[:space:]]|$)" \
    -e "FROM[[:space:]]+public\.ecr\.aws/lambda/nodejs:(18|20)"
# 5. Dependencies that set these options too (report only; review, don't fail)
dep=$(grep -rlE "ecdhCurve[[:space:]]*:|DEFAULT_ECDH_CURVE[[:space:]]*=|maxVersion[[:space:]]*:[[:space:]]*['\"]TLSv1\.2" "$root/node_modules" \
      --include='*.js' --include='*.cjs' --include='*.mjs' 2>/dev/null | grep -vE '/(test|tests|docs?)/|@types/' | head -20)
[ -n "$dep" ] && { echo "::warning::node_modules files that set ecdhCurve/maxVersion (review):"; echo "$dep"; }
[ $rc = 0 ] && echo "check-node-tls: no PQ-blocking settings found"
exit $rc
```

`test/gen-certs.sh` (private CA, RSA/EC server certs, encrypted keys, PFX files, client certs; run inside an OpenSSL 3.5 container with this dir at /w)

```bash
#!/bin/bash
# Runs inside the OpenSSL 3.5 container (pqc-deep-node/ossl) with /w = this v2 dir.
# Private CA + RSA and EC server certs (several SANs for SNI), an encrypted key, PFX files and a client cert.
set -euo pipefail
cd /w; rm -rf certs; mkdir certs; cd certs
openssl req -x509 -newkey rsa:3072 -nodes -keyout ca.key -out ca.pem -days 30 -subj "/CN=Test Private Root CA" \
  -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign 2>/dev/null
sign() { # name keyfile san eku
  openssl req -new -key "$2" -out "$1.csr" -subj "/CN=$1" 2>/dev/null
  printf 'subjectAltName=%s\nextendedKeyUsage=%s\n' "$3" "$4" > "$1.ext"
  openssl x509 -req -in "$1.csr" -CA ca.pem -CAkey ca.key -CAcreateserial -days 30 -out "$1.pem" -extfile "$1.ext" 2>/dev/null
}
openssl genrsa -out rsa.key 2048 2>/dev/null;                      sign rsa rsa.key "DNS:node2srv,DNS:node2ossl,DNS:rsa.test,DNS:a.test" serverAuth
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out ec.key; sign ec ec.key "DNS:node2srv,DNS:ec.test,DNS:b.test" serverAuth
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 -out ec384.key; sign ec384 ec384.key "DNS:c.test" serverAuth
# Encrypted key (PKCS#8, AES-256) and a traditional encrypted PEM (BEGIN RSA PRIVATE KEY + DEK-Info)
openssl pkcs8 -topk8 -in ec.key -out ec-enc.key -v2 aes-256-cbc -passout pass:s3cret
openssl rsa -in rsa.key -aes256 -traditional -out rsa-enc-trad.key -passout pass:s3cret 2>/dev/null
# PFX: OpenSSL 3 default (AES-256/PBKDF2) and legacy (RC2-40/3DES, as old Windows exports)
openssl pkcs12 -export -inkey rsa.key -in rsa.pem -certfile ca.pem -out rsa.pfx -passout pass:s3cret
openssl pkcs12 -export -inkey ec.key -in ec.pem -certfile ca.pem -out ec.pfx -passout pass:s3cret
openssl pkcs12 -export -legacy -inkey rsa.key -in rsa.pem -certfile ca.pem -out rsa-legacy.pfx -passout pass:s3cret
# Client cert for mutual TLS (EC) and an RSA one
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out client.key; sign client client.key "DNS:client.test" clientAuth
openssl genrsa -out client-rsa.key 2048 2>/dev/null; sign client-rsa client-rsa.key "DNS:client-rsa.test" clientAuth
openssl pkcs12 -export -inkey client.key -in client.pem -out client.pfx -passout pass:s3cret
# A CA bundle file = public roots + private CA (what SSL_CERT_FILE would point at)
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout other-ca.key -out other-ca.pem -days 30 -subj "/CN=Unrelated Root" 2>/dev/null; cat other-ca.pem ca.pem > bundle-with-private.pem
chmod 644 *; ls
```

`test/start-ossl.sh` (the four reference servers: PQ-only, classical, and both with client certs required)

```bash
#!/bin/bash
# Starts the OpenSSL 3.5 test servers used by run-cases.sh (container node2-ossl on network node2net).
#   4431 PQ-only  4432 classical-only  4433 PQ-only + client cert required  4434 classical + client cert required
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
V="$(cd "$(dirname "$0")" && pwd)"
docker network inspect node2net >/dev/null 2>&1 || docker network create --label run=pqc-lang2-node node2net >/dev/null
docker rm -f node2-ossl >/dev/null 2>&1
docker run -d --label run=pqc-lang2-node --name node2-ossl --network node2net --network-alias node2ossl -v "$V":/w:ro \
  --entrypoint bash pqc-deep-node/ossl -c '
cd /w/certs
openssl s_server -quiet -accept 4431 -cert rsa.pem -key rsa.key -groups X25519MLKEM768 -tls1_3 -www > /tmp/4431.log 2>&1 &
openssl s_server -quiet -accept 4432 -cert rsa.pem -key rsa.key -groups X25519 -www > /tmp/4432.log 2>&1 &
openssl s_server -quiet -accept 4433 -cert rsa.pem -key rsa.key -groups X25519MLKEM768 -tls1_3 -Verify 1 -verify_return_error -CAfile ca.pem -www > /tmp/4433.log 2>&1 &
openssl s_server -quiet -accept 4434 -cert rsa.pem -key rsa.key -groups X25519 -Verify 1 -verify_return_error -CAfile ca.pem -www > /tmp/4434.log 2>&1 &
sleep infinity' >/dev/null
sleep 2
docker exec node2-ossl sh -c 'for p in 4431 4432; do echo | openssl s_client -connect node2ossl:$p -CAfile /w/certs/ca.pem -verify_hostname node2ossl -brief 2>&1 | grep -E "group|Temp Key|Verification"; done'
```

`test/srv.cjs` (server probe for cases C, E (server side) and F)

```js
'use strict';
// Server-side probe for case C (existing certs/keys), E (server requires client certs) and F (server settings).
// One Node process, one listener per variant. Probed by openssl s_client 3.5 (run-cases.sh).
const fs = require('node:fs');
const tls = require('node:tls');
const https = require('node:https');
const http2 = require('node:http2');
const N = '/n/app/node_modules/';
const C = (f) => fs.readFileSync('/w/certs/' + f);
const rsa = { key: C('rsa.key'), cert: C('rsa.pem') };
const ec = { key: C('ec.key'), cert: C('ec.pem') };
const ec384 = { key: C('ec384.key'), cert: C('ec384.pem') };
const hello = (req, res) => res.end('ok\n');
const up = (p, what) => console.log(`listening ${p} ${what}`);
function L(port, what, mk) {
  try { const s = mk(); s.on('tlsClientError', () => {}); s.listen(port, () => up(port, what)); }
  catch (e) { console.log(`failed ${port} ${what} :: ${e.code || ''} ${e.message.split('\n')[0]}`); }
}
// ---- Case C: existing certificates
L(9101, 'C RSA PEM key/cert', () => https.createServer({ ...rsa }, hello));
L(9102, 'C EC P-256 PEM key/cert', () => https.createServer({ ...ec }, hello));
L(9103, 'C RSA+EC in one context (key/cert arrays)', () => https.createServer({ key: [rsa.key, ec.key], cert: [rsa.cert, ec.cert] }, hello));
L(9104, 'C encrypted PKCS#8 EC key + passphrase', () => https.createServer({ key: C('ec-enc.key'), cert: ec.cert, passphrase: 's3cret' }, hello));
L(9105, 'C encrypted traditional RSA key + passphrase', () => https.createServer({ key: C('rsa-enc-trad.key'), cert: rsa.cert, passphrase: 's3cret' }, hello));
L(9106, 'C pfx RSA (AES/PBKDF2) + passphrase', () => https.createServer({ pfx: C('rsa.pfx'), passphrase: 's3cret' }, hello));
L(9107, 'C pfx EC + passphrase', () => https.createServer({ pfx: C('ec.pfx'), passphrase: 's3cret' }, hello));
L(9108, 'C pfx legacy RC2/3DES + passphrase', () => https.createServer({ pfx: C('rsa-legacy.pfx'), passphrase: 's3cret' }, hello));
const sni = { 'a.test': tls.createSecureContext(rsa), 'b.test': tls.createSecureContext(ec), 'c.test': tls.createSecureContext(ec384) };
L(9109, 'C SNICallback a=RSA b=EC c=EC384 default=RSA', () => https.createServer({ ...rsa, SNICallback: (name, cb) => cb(null, sni[name]) }, hello));
L(9110, 'C addContext b.test=EC pfx, default RSA', () => { const s = https.createServer({ ...rsa }, hello); s.addContext('b.test', { pfx: C('ec.pfx'), passphrase: 's3cret' }); return s; });
L(9111, 'C Express 5 on https EC', () => { const app = require(N + 'express')(); app.get('/', (q, r) => r.send('ok')); return https.createServer({ ...ec }, app); });
L(9113, 'C http2.createSecureServer EC + SNICallback', () => http2.createSecureServer({ ...ec, allowHTTP1: true, SNICallback: (n, cb) => cb(null, sni[n]) }, hello));
try {
  const f = require(N + 'fastify')({ https: { pfx: C('rsa.pfx'), passphrase: 's3cret' } });
  f.get('/', async () => 'ok');
  f.listen({ port: 9112, host: '0.0.0.0' }).then(() => up(9112, 'C Fastify 5 https pfx + passphrase')).catch((e) => console.log('failed 9112 fastify', e.message));
} catch (e) { console.log('failed 9112 fastify', e.message); }
// ---- Case E: server requires a client certificate
L(9114, 'E https requestCert+rejectUnauthorized, ca=private CA', () => https.createServer({ ...ec, ca: C('ca.pem'), requestCert: true, rejectUnauthorized: true }, (q, r) => r.end('cn=' + q.socket.getPeerCertificate().subject.CN + '\n')));
// ---- Case F: server-side settings
L(9121, 'F ecdhCurve X25519:P-256', () => https.createServer({ ...ec, ecdhCurve: 'X25519:P-256' }, hello));
L(9122, 'F ecdhCurve auto', () => https.createServer({ ...ec, ecdhCurve: 'auto' }, hello));
L(9123, 'F ecdhCurve PQ-first', () => https.createServer({ ...ec, ecdhCurve: 'X25519MLKEM768:X25519:P-256:P-384' }, hello));
L(9124, 'F ciphers TLS1.2-only list', () => https.createServer({ ...ec, ciphers: 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256' }, hello));
L(9125, 'F maxVersion TLSv1.2', () => https.createServer({ ...ec, maxVersion: 'TLSv1.2' }, hello));
L(9126, 'F secureProtocol TLSv1_2_method', () => https.createServer({ ...ec, secureProtocol: 'TLSv1_2_method' }, hello));
L(9127, 'F ecdhCurve X25519MLKEM768 only (PQ-only server)', () => https.createServer({ ...ec, ecdhCurve: 'X25519MLKEM768', minVersion: 'TLSv1.3' }, hello));
console.log(`node ${process.version} openssl ${process.versions.openssl} OPENSSL_CONF=${process.env.OPENSSL_CONF || ''}`);
```

`test/cli.cjs` (client probe for cases D, E and F)

```js
'use strict';
// Client-side probe for cases D (trust), E (mutual TLS) and F (PQ-blocking settings).
// Targets are OpenSSL 3.5 s_server instances on host node2ossl:
//   4431 PQ-only (X25519MLKEM768, TLS 1.3)   4432 classical-only (X25519, TLS 1.2+1.3)
//   4433 PQ-only + client cert required       4434 classical-only + client cert required
// Usage: node cli.cjs <group>   group = trust-none | trust-ca-option | trust-env | trust-store | mtls | block | flags
const fs = require('node:fs');
const tls = require('node:tls');
const https = require('node:https');
const N = '/n/app/node_modules/';
const C = (f) => fs.readFileSync('/w/certs/' + f);
const H = 'node2ossl';
const out = (o) => console.log(JSON.stringify(o));
const groupOf = (s) => {
  const k = s.getEphemeralKeyInfo() || {};
  return k.name || (s.getProtocol() === 'TLSv1.3' && !k.type ? 'X25519MLKEM768 (Node 22 reports {})' : 'unknown');
};
const errOf = (e) => { if (!e) return String(e); const x = e.cause && e.cause.code ? e.cause : e; return (x.code || x.name) + (x.code === "UND_ERR_INVALID_ARG" || !x.code ? ": " + String(x.message).slice(0, 120) : ""); };

function viaTls(name, port, opts = {}) {
  return new Promise((done) => {
    let s;
    try {
      s = tls.connect({ host: H, port, servername: H, ...opts }, () => {
        out({ case: name, port, ok: true, protocol: s.getProtocol(), group: groupOf(s) });
        s.end(); done();
      });
    } catch (e) { out({ case: name, port, ok: false, threw: errOf(e) }); return done(); }
    s.setTimeout(8000, () => s.destroy(new Error('timeout')));
    s.on('error', (e) => { out({ case: name, port, ok: false, error: errOf(e) }); done(); });
  });
}

function viaHttps(name, port, agentOpts) {
  return new Promise((done) => {
    let agent;
    try { agent = agentOpts ? new https.Agent(agentOpts) : undefined; } catch (e) { out({ case: name, port, ok: false, threw: errOf(e) }); return done(); }
    const r = https.get({ host: H, port, path: '/', agent }, (res) => {
      const g = groupOf(res.socket);
      let body = ''; res.on('data', (d) => (body += d));
      res.on('end', () => { out({ case: name, port, ok: true, status: res.statusCode, group: g, clientCertSeenByServer: /Client certificate|BEGIN CERTIFICATE/.test(body) || undefined }); done(); });
    });
    r.setTimeout(8000, () => r.destroy(new Error('timeout')));
    r.on('error', (e) => { out({ case: name, port, ok: false, error: errOf(e) }); done(); });
  });
}

async function viaFetch(name, port, init = {}) {
  try {
    const r = await fetch(`https://${H}:${port}/`, init);
    await r.text(); out({ case: name, port, ok: true, status: r.status });
  } catch (e) { out({ case: name, port, ok: false, error: errOf(e) }); }
}

async function viaUndici(name, port, connect) {
  try {
    const { Agent, request } = require(N + 'undici');
    const dispatcher = new Agent({ connect });
    const r = await request(`https://${H}:${port}/`, { dispatcher });
    await r.body.text(); out({ case: name, port, ok: true, status: r.statusCode });
    await dispatcher.close();
  } catch (e) { out({ case: name, port, ok: false, error: errOf(e) }); }
}

async function viaSdk(name, port, agentOpts) {
  try {
    const { S3Client, GetObjectCommand } = require(N + '@aws-sdk/client-s3');
    const { NodeHttpHandler } = require(N + '@smithy/node-http-handler');
    const s3 = new S3Client({
      region: 'us-east-1', endpoint: `https://${H}:${port}`, forcePathStyle: true, maxAttempts: 1,
      credentials: { accessKeyId: 'AKIDEXAMPLE', secretAccessKey: 'x' },
      requestHandler: new NodeHttpHandler({ httpsAgent: new https.Agent(agentOpts), connectionTimeout: 5000, requestTimeout: 8000, throwOnRequestTimeout: true }),
    });
    const r = await s3.send(new GetObjectCommand({ Bucket: "b", Key: "k" }));
    out({ case: name, port, ok: true, status: r.$metadata.httpStatusCode });
  } catch (e) {
    // HTTP-level outcome means the TLS handshake (and mTLS) succeeded.
    const st = e.$metadata && e.$metadata.httpStatusCode;
    out({ case: name, port, ok: !!st, tlsOk: !!st, status: st, error: errOf(e) });
  }
}

const ca = C('ca.pem');
const mtls = { ca, key: C('client.key'), cert: C('client.pem') };
const groups = {
  async 'trust-none'() { // no private CA anywhere: must fail verification
    await viaTls('D0 no CA', 4431);
  },
  async 'trust-ca-option'() {
    await viaTls('D2 tls ca option', 4431, { ca });
    await viaHttps('D2 https.Agent ca option', 4431, { ca });
    await viaUndici('D2 undici connect.ca', 4431, { ca });
    await viaTls('D2 classical fallback', 4432, { ca });
  },
  async 'trust-env'() { // NODE_EXTRA_CA_CERTS, --use-openssl-ca + SSL_CERT_FILE, --use-system-ca: no ca in code
    await viaTls('D tls default', 4431);
    await viaHttps('D https.get default agent', 4431);
    await viaFetch('D global fetch', 4431);
    await viaUndici('D undici Agent', 4431, {});
    await viaTls('D classical fallback', 4432);
  },
  async 'trust-api'() { // tls.setDefaultCACertificates (Node 22.19+/24.5+ per docs)
    if (typeof tls.setDefaultCACertificates !== 'function') return out({ case: 'D tls.setDefaultCACertificates', ok: false, error: 'not a function' });
    tls.setDefaultCACertificates([...tls.getCACertificates('default'), ca.toString()]);
    await viaTls('D tls.setDefaultCACertificates', 4431);
    await viaFetch('D fetch after setDefaultCACertificates', 4431);
  },
  async mtls() {
    await viaTls('E tls.connect key/cert', 4433, mtls);
    await viaTls('E tls.connect encrypted key + passphrase', 4433, { ca, cert: C('client.pem'), passphrase: 's3cret',
      key: require('node:crypto').createPrivateKey(C('client.key')).export({ type: 'pkcs8', format: 'pem', cipher: 'aes-256-cbc', passphrase: 's3cret' }) });
    await viaTls('E tls.connect pfx + passphrase', 4433, { ca, pfx: C('client.pfx'), passphrase: 's3cret' });
    await viaTls('E tls.connect RSA client cert', 4433, { ca, key: C('client-rsa.key'), cert: C('client-rsa.pem') });
    await viaHttps('E https.Agent key/cert', 4433, mtls);
    await viaUndici('E undici Agent connect key/cert', 4433, mtls);
    try {
      const { Agent } = require(N + 'undici');
      await viaFetch('E global fetch + npm undici dispatcher', 4433, { dispatcher: new Agent({ connect: mtls }) });
    } catch (e) { out({ case: 'E global fetch + npm undici dispatcher', ok: false, error: errOf(e) }); }
    try {
      const u = require(N + 'undici');
      const r = await u.fetch('https://' + H + ':4433/', { dispatcher: new u.Agent({ connect: mtls }) }); await r.text();
      out({ case: 'E npm undici.fetch + its own Agent', port: 4433, ok: true, status: r.status });
    } catch (e) { out({ case: 'E npm undici.fetch + its own Agent', ok: false, error: errOf(e) }); }
    await viaSdk('E AWS SDK v3 NodeHttpHandler httpsAgent key/cert', 4433, mtls);
    await viaTls('E classical mTLS fallback', 4434, mtls);
    await viaTls('E negative: no client cert', 4433, { ca });
    await viaSdk('E negative: SDK without client cert', 4433, { ca });
  },
  async block() {
    const cases = [
      ['F ecdhCurve X25519:P-256', { ecdhCurve: 'X25519:P-256' }],
      ['F ecdhCurve auto', { ecdhCurve: 'auto' }],
      ['F ecdhCurve PQ-first', { ecdhCurve: 'X25519MLKEM768:X25519:P-256:P-384' }],
      ['F ciphers TLS1.2-only list', { ciphers: 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256' }],
      ['F ciphers TLS1.3 suite only', { ciphers: 'TLS_AES_256_GCM_SHA384' }],
      ['F maxVersion TLSv1.2', { maxVersion: 'TLSv1.2' }],
      ['F secureProtocol TLSv1_2_method', { secureProtocol: 'TLSv1_2_method' }],
      ['F secureProtocol TLS_method', { secureProtocol: 'TLS_method' }],
      ['F secureProtocol TLSv1_3_method', { secureProtocol: 'TLSv1_3_method' }],
      ['F minVersion TLSv1.3', { minVersion: 'TLSv1.3' }],
      ['F sigalgs ECDSA+SHA256:RSA-PSS+SHA256', { sigalgs: 'ECDSA+SHA256:RSA-PSS+SHA256' }],
    ];
    for (const [n, o] of cases) { await viaTls(n + ' -> PQ-only', 4431, { ca, ...o }); await viaTls(n + ' -> classical', 4432, { ca, ...o }); }
  },
  async 'block-defaults'() { // module-level defaults set by some libraries
    tls.DEFAULT_MAX_VERSION = 'TLSv1.2';
    await viaTls('F tls.DEFAULT_MAX_VERSION=TLSv1.2 -> PQ-only', 4431, { ca });
    tls.DEFAULT_MAX_VERSION = 'TLSv1.3';
    tls.DEFAULT_ECDH_CURVE = 'X25519:P-256';
    await viaTls('F tls.DEFAULT_ECDH_CURVE=X25519:P-256 -> PQ-only', 4431, { ca });
    await viaFetch('F DEFAULT_ECDH_CURVE classical, global fetch -> PQ-only', 4431, {});
  },
  async flags() { // run with NODE_OPTIONS set by the caller
    await viaTls('F flags ' + (process.env.NODE_OPTIONS || '') + ' -> PQ-only', 4431, { ca });
    await viaTls('F flags ' + (process.env.NODE_OPTIONS || '') + ' -> classical', 4432, { ca });
  },
};
(async () => {
  const g = process.argv[2];
  out({ group: g, node: process.version, openssl: process.versions.openssl, OPENSSL_CONF: process.env.OPENSSL_CONF || null,
    NODE_EXTRA_CA_CERTS: process.env.NODE_EXTRA_CA_CERTS || null, SSL_CERT_FILE: process.env.SSL_CERT_FILE || null,
    NODE_OPTIONS: process.env.NODE_OPTIONS || null, execArgv: process.execArgv });
  await groups[g]();
})();
```

`test/pin.cjs` (case I: SPKI pinning)

```js
'use strict';
// Case I: public-key pinning in checkServerIdentity keeps working when the key exchange is X25519MLKEM768.
// Target: s_server PQ-only on node2ossl:4431 (cert rsa.pem). Usage: node pin.cjs
const fs = require('node:fs');
const tls = require('node:tls');
const crypto = require('node:crypto');
const ca = fs.readFileSync('/w/certs/ca.pem');
const spki = (pem) => crypto.createHash('sha256').update(crypto.createPublicKey(pem).export({ type: 'spki', format: 'der' })).digest('base64');
const good = spki(fs.readFileSync('/w/certs/rsa.pem'));
const bad = spki(fs.readFileSync('/w/certs/ec.pem'));
function run(name, pin) {
  return new Promise((done) => {
    const s = tls.connect({ host: 'node2ossl', port: 4431, servername: 'node2ossl', ca,
      checkServerIdentity: (host, cert) => {
        const err = tls.checkServerIdentity(host, cert);
        if (err) return err;
        const got = crypto.createHash('sha256').update(cert.pubkey).digest('base64');
        if (got !== pin) return new Error(`pin mismatch: ${got}`);
      } }, () => {
      const k = s.getEphemeralKeyInfo() || {};
      console.log(JSON.stringify({ case: name, ok: true, group: k.name || (k.type ? k.type : 'X25519MLKEM768 (Node 22 reports {})') }));
      s.end(); done();
    });
    s.on('error', (e) => { console.log(JSON.stringify({ case: name, ok: false, error: e.message.slice(0, 80) })); done(); });
  });
}
(async () => {
  console.log(JSON.stringify({ node: process.version, OPENSSL_CONF: process.env.OPENSSL_CONF || null, pin: good }));
  await run('I SPKI pin matches', good);
  await run('I SPKI pin wrong (must fail)', bad);
})();
```

`test/run-cases.sh` (runs C, D, E and F for one runtime image)

```bash
#!/bin/bash
# Cases C, D, E, F for one Node runtime. Usage: run-cases.sh <label> <image@digest> [OPENSSL_CONF value | -]
#   label e.g. node22, node24, lambda22-pq, lambda24-pq, lambda24-aws
# Needs: network node2net, container node2-ossl (OpenSSL 3.5 s_servers on 4431-4434), certs from gen-certs.sh.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
V="$(cd "$(dirname "$0")" && pwd)"; N="$(dirname "$V")"; K="$(cd "$N/../../lambda-pq/layer/pq-tls" && pwd)"
LBL=run=pqc-lang2-node; label=$1; img=$2; conf=${3:--}
envs=(); [ "$conf" != "-" ] && envs=(-e OPENSSL_CONF="$conf")
run() { docker run --rm --label $LBL --network node2net --entrypoint "" -v "$V":/w:ro -v "$N":/n:ro -v "$K":/k:ro "${envs[@]}" "$@" "$img"; }
al() { perl -e 'alarm shift; exec @ARGV' "$@"; }

echo "######## $label  image=$img  OPENSSL_CONF=${conf}"
echo "#### server side (C, E, F): node2-srv probed by openssl s_client 3.5"
docker run -d --label $LBL --name node2-srv --network node2net --network-alias node2srv --entrypoint "" \
  -v "$V":/w:ro -v "$N":/n:ro -v "$K":/k:ro "${envs[@]}" "$img" node /w/srv.cjs >/dev/null
sleep 4; docker logs node2-srv 2>&1 | grep -E '^(node|failed)'
sc() { echo | al 10 docker exec -i node2-ossl openssl s_client -connect node2srv:$1 -CAfile /w/certs/ca.pem -verify_return_error -brief "${@:2}" 2>&1 \
  | grep -E 'Negotiated TLS1.3 group|Peer Temp Key|Peer certificate|Verification|alert|error|refused' | grep -vE 'verify return' \
  | sed -E 's/^(Peer certificate: ).*CN ?= ?([A-Za-z0-9.-]+).*/cert=\2/; s/Negotiated TLS1.3 group: /group=/; s/Peer Temp Key: ([^,]+).*/group=\1 (TLS1.2 or classical)/; s/Verification: /verify=/' | tr '\n' ' '; }
hp() { printf "GET / HTTP/1.0\r\n\r\n" | al 10 docker exec -i node2-ossl openssl s_client -quiet -connect node2srv:$1 -CAfile /w/certs/ca.pem "${@:2}" 2>&1 | grep -oE "cn=[a-z.-]+|alert [a-z ]+" | head -1; }
pq=(-groups X25519MLKEM768 -tls1_3); cl=(-groups X25519:secp256r1)
for p in $(docker logs node2-srv 2>&1 | awk '/^listening/{print $2}'); do
  what=$(docker logs node2-srv 2>&1 | awk -v p=$p '$1=="listening" && $2==p {$1="";$2="";print}')
  echo "-- $p$what"
  case $p in
    9103) echo "   PQ client:        $(sc $p "${pq[@]}")"; echo "   classical client: $(sc $p "${cl[@]}")"
          echo "   RSA-only sigalgs: $(sc $p "${pq[@]}" -sigalgs 'RSA-PSS+SHA256:RSA+SHA256')"
          echo "   ECDSA-only:       $(sc $p "${pq[@]}" -sigalgs 'ECDSA+SHA256')" ;;
    9109|9110|9113) for sn in a.test b.test c.test node2srv; do echo "   SNI $sn PQ: $(sc $p "${pq[@]}" -servername $sn) | classical: $(sc $p "${cl[@]}" -servername $sn)"; done ;;
    9114) echo "   PQ + client cert: $(sc $p "${pq[@]}" -cert /w/certs/client.pem -key /w/certs/client.key) app reply: $(hp $p "${pq[@]}" -cert /w/certs/client.pem -key /w/certs/client.key)"
          echo "   PQ, no cert:      app reply: $(hp $p "${pq[@]}")"
          echo "   classical + cert: $(sc $p "${cl[@]}" -cert /w/certs/client.pem -key /w/certs/client.key)" ;;
    *) echo "   PQ client:        $(sc $p "${pq[@]}")"; echo "   classical client: $(sc $p "${cl[@]}")"; echo "   TLS1.2 client:    $(sc $p -tls1_2)" ;;
  esac
done
docker rm -f node2-srv >/dev/null

echo "#### client side (D, E, F) against s_server PQ-only/classical"
c() { docker rm -f node2-cli >/dev/null 2>&1; al 90 docker run --rm --name node2-cli --label $LBL --network node2net --entrypoint "" -v "$V":/w:ro -v "$N":/n:ro -v "$K":/k:ro "${envs[@]}" "$@" 2>&1 | grep --line-buffered -vE "ExperimentalWarning|trace-warnings"; docker rm -f node2-cli >/dev/null 2>&1; }
c "$img" node /w/cli.cjs trust-none
c "$img" node /w/cli.cjs trust-ca-option
c -e NODE_EXTRA_CA_CERTS=/w/certs/ca.pem "$img" node /w/cli.cjs trust-env
c -e NODE_EXTRA_CA_CERTS=/w/certs/bundle-with-private.pem "$img" node /w/cli.cjs trust-env
c -e SSL_CERT_FILE=/w/certs/bundle-with-private.pem "$img" node --use-openssl-ca /w/cli.cjs trust-env
c -e SSL_CERT_FILE=/w/certs/bundle-with-private.pem "$img" node --use-system-ca /w/cli.cjs trust-env
c -e SSL_CERT_FILE=/w/certs/bundle-with-private.pem -e NODE_USE_SYSTEM_CA=1 "$img" node /w/cli.cjs trust-env
c -e SSL_CERT_FILE=/w/certs/bundle-with-private.pem -e NODE_OPTIONS=--use-openssl-ca "$img" node /w/cli.cjs trust-env
# private CA installed into the image's system trust store (Debian: update-ca-certificates; AL2023: update-ca-trust)
c "$img" sh -c 'if command -v update-ca-certificates >/dev/null; then cp /w/certs/ca.pem /usr/local/share/ca-certificates/private.crt && update-ca-certificates >/dev/null 2>&1; S=debian;
  elif command -v update-ca-trust >/dev/null; then cp /w/certs/ca.pem /etc/pki/ca-trust/source/anchors/private.pem && update-ca-trust extract; S=al2023;
  else S=none; fi; echo "{\"systemStore\":\"$S\"}";
  echo "## --use-system-ca"; node --use-system-ca /w/cli.cjs trust-env; echo "## --use-openssl-ca"; node --use-openssl-ca /w/cli.cjs trust-env; echo "## bundled (default)"; node /w/cli.cjs trust-none'
c "$img" node /w/cli.cjs trust-api
c "$img" node /w/cli.cjs mtls
c "$img" node /w/cli.cjs block
c "$img" node /w/cli.cjs block-defaults
c -e NODE_OPTIONS=--tls-max-v1.2 "$img" node /w/cli.cjs flags
c -e NODE_OPTIONS=--tls-cipher-list=ECDHE-RSA-AES128-GCM-SHA256 "$img" node /w/cli.cjs flags
c -e NODE_OPTIONS=--tls-min-v1.3 "$img" node /w/cli.cjs flags
echo "######## end $label"
```

`test/fn/index.js` (Lambda handler for the emulator test)

```js
// Lambda handler for the RIE test: private-CA trust (NODE_EXTRA_CA_CERTS, no ca in code) and mTLS, PQ-only targets.
const tls = require('tls'); const fs = require('fs');
const one = (port, extra = {}) => new Promise((done) => {
  const s = tls.connect({ host: 'node2ossl', port, servername: 'node2ossl', ...extra }, () => {
    const k = s.getEphemeralKeyInfo() || {}; s.write('GET / HTTP/1.0\r\n\r\n');
    s.once('data', () => { done('OK ' + s.getProtocol() + ' ' + (k.name || (k.type ? k.type : 'X25519MLKEM768'))); s.destroy(); });
  });
  s.on('error', (e) => done('FAIL ' + (e.code || e.message)));
  s.setTimeout(5000, () => { s.destroy(); done('FAIL timeout'); });
});
exports.handler = async () => ({
  runtime: process.version, OPENSSL_CONF: process.env.OPENSSL_CONF, NODE_EXTRA_CA_CERTS: process.env.NODE_EXTRA_CA_CERTS || null,
  pq_only_trust_via_env: await one(4431),
  pq_only_mtls: await one(4433, { key: fs.readFileSync('/var/task/certs/client.key'), cert: fs.readFileSync('/var/task/certs/client.pem') }),
  classical_trust_via_env: await one(4432),
});
```

`test/run-lambda-rie.sh` (Lambda nodejs22/24 under the Runtime Interface Emulator with NODE_EXTRA_CA_CERTS and mTLS)

```bash
#!/bin/bash
# Lambda nodejs22/24 base images under the Runtime Interface Emulator (real /var/runtime/bootstrap):
# NODE_EXTRA_CA_CERTS + the PQ OPENSSL_CONF override, against PQ-only s_servers (node2-ossl).
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
V="$(cd "$(dirname "$0")" && pwd)"; port=18661
for v in 22 24; do
  img=$(grep "^lambda/nodejs:$v " "$V/digests.txt" | cut -d' ' -f2)
  for mode in pq+xca aws+xca pq-noxca; do
    env=()
    case $mode in
      pq+xca)   env=(-e OPENSSL_CONF=/var/task/pq-tls/openssl-pq-node.cnf -e NODE_EXTRA_CA_CERTS=/var/task/certs/ca.pem) ;;
      aws+xca)  env=(-e NODE_EXTRA_CA_CERTS=/var/task/certs/ca.pem) ;;
      pq-noxca) env=(-e OPENSSL_CONF=/var/task/pq-tls/openssl-pq-node.cnf) ;;
    esac
    docker run -d --label run=pqc-lang2-node --name node2-fn --network node2net -p 127.0.0.1:$port:8080 -v "$V/fn":/var/task:ro "${env[@]}" "$img" index.handler >/dev/null
    res=$(curl -s --retry-connrefused --retry 20 --retry-delay 1 --max-time 60 -XPOST "http://127.0.0.1:$port/2015-03-31/functions/function/invocations" -d '{}')
    printf 'nodejs%-3s %-9s %s\n' "$v" "$mode" "$res"
    docker rm -f node2-fn >/dev/null; port=$((port+1))
  done
done
```

`test/run-pin.sh` (runs pin.cjs on the four runtimes)

```bash
#!/bin/bash
# Case I: SPKI pinning with the PQ setup, on 4 runtimes. Needs node2-ossl (start-ossl.sh).
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
V="$(cd "$(dirname "$0")" && pwd)"; K="$(cd "$V/../../../lambda-pq/layer/pq-tls" && pwd)"
d() { grep "^$1 " "$V/digests.txt" | cut -d' ' -f2; }
while read -r lab img conf; do
  e=(); [ "$conf" != "-" ] && e=(-e "OPENSSL_CONF=$conf")
  echo "## $lab"
  perl -e 'alarm 60; exec @ARGV' docker run --rm --name node2-cli --label run=pqc-lang2-node --network node2net --entrypoint "" \
    -v "$V":/w:ro -v "$K":/k:ro "${e[@]}" "$img" node /w/pin.cjs
done <<LIST
node22 $(d node:22) -
node24 $(d node:24) -
lambda22-pq $(d lambda/nodejs:22) /k/openssl-pq-node.cnf
lambda24-pq $(d lambda/nodejs:24) /k/openssl-pq-node.cnf
LIST
```

<!-- [DELETE after moves: .3646 (H2 What decides), .4569 (H2 Status matrix), .4583 (status intro), .4847 (old status table, replaced by the Versions table), .8071 (H2 Client side), .10836 (H2 Server side), .12925 (H2 Packaging), .15970 (H2 Verify)] -->
