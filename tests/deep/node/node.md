# Node.js runbook

## What decides PQ here

The OpenSSL that the `node` binary uses decides, and then the OpenSSL config file Node reads. Official Node builds bundle OpenSSL: 22.20.0+ and 24.5.0+ carry OpenSSL 3.5 and offer X25519MLKEM768 first by default, on any OS. Distro builds (AL2023 `dnf`, Debian `apt`, Alpine `apk`) link the system OpenSSL and follow the system config. Three things turn PQ off again: a config file whose `Groups` omits ML-KEM (the Lambda bootstrap sets one), an explicit `ecdhCurve` / `tls.DEFAULT_ECDH_CURVE` without `X25519MLKEM768`, and a TLS 1.2 cap. Every client library tested (fetch, undici, axios, got, node-fetch, AWS SDK v3, grpc-js, pg, mysql2, ioredis, kafkajs) inherits Node's defaults.

Node reads the `nodejs_conf` section of the file named by `--openssl-config` or `OPENSSL_CONF` (the flag wins); `--openssl-shared-config` makes it read `openssl_conf` instead ([Node CLI docs](https://nodejs.org/api/cli.html#--openssl-shared-config), Documented). Both flags are allowed in `NODE_OPTIONS`.

## Status matrix

All rows Tested 2026-11-14 against a PQ-only server (`-groups X25519MLKEM768 -tls1_3`, OpenSSL 3.5.7) and a classical-only server (`X25519`). "PQ default" = PQ-only server accepted with no setting; classical server still worked in every PQ row.

| Node build | OpenSSL | Lambda zip | Lambda image | Fargate / ECS / EKS | EC2 | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| Official 24.5.0+ (tested 24.5.0, 24.9.0, 24.22.3) | 3.5.1+ | `nodejs24.x`: classical until you override the bootstrap config | `lambda/nodejs:24`: same override | `node:24-slim`, `node:24-alpine`: PQ default | Official tarball: PQ default | Tested |
| Official 22.20.0+ (tested 22.20.0, 22.23.5) | 3.5.2+ | `nodejs22.x`: override needed | `lambda/nodejs:22`: override needed | `node:22-slim`, `node:22-alpine`: PQ default | PQ default | Tested |
| Official 26.x (tested 26.13.1) | 3.5.9 | `nodejs26.x` is public preview; not tested | not tested | `node:26-slim`: PQ default | PQ default | Tested (container) |
| Official 22.0–22.19, 24.0–24.4 | 3.0.x (22.19.0 = 3.0.17, 24.4.1 = 3.0.16) | only if runtime updates are pinned (Manual mode); check | rebuild on current base | upgrade the image tag | upgrade | Tested |
| Official 20.x, 18.x | 3.0.x | `nodejs20.x` deprecated Apr 30 2026, updates blocked Aug 31 2027: upgrade | upgrade | `node:20-*`: classical, no setting adds PQ | upgrade | Tested (`node:20-slim`, `node:20-alpine` 20.20.2) |
| AL2023 `dnf install nodejs22` (22.23.4, shared OpenSSL 3.5.8) | system | n/a | n/a | classical until `update-crypto-policies --set DEFAULT:PQ` or `OPENSSL_CONF` | same | Tested (`amazonlinux:2023`) |
| Debian 13 `apt install nodejs` (20.19.2, system OpenSSL 3.5.7) | system | n/a | n/a | PQ default | PQ default | Tested (`debian:trixie-slim`) |
| Alpine 3.22 `apk add nodejs` (22.23.5, system OpenSSL 3.5.9) | system | n/a | n/a | PQ default | n/a | Tested (`alpine:3.22`) |
| Deno 2.9.8 / Bun 1.4.4 | rustls / BoringSSL | n/a | custom image | PQ default (`fetch`, Bun also `node:tls`) | same | Tested (`denoland/deno`, `oven/bun`) |

Version floor: AWS's SDK guide says 22.20 and 24.9.0 ([AWS SDK PQ TLS guide](https://docs.aws.amazon.com/sdkref/latest/guide/pqtls-details.html)). Node's own release notes put the OpenSSL 3.5 upgrade in 24.5.0 ([v24.5.0 release](https://nodejs.org/en/blog/release/v24.5.0)), and 24.5.0 negotiated X25519MLKEM768 here. Use 24.9+ as the policy floor (matches AWS), but don't flag 24.5–24.8 as classical.

Client libraries, same servers. Library versions: undici 8.12.4, axios 1.21.1, got 16.2.0, node-fetch 3.3.2, @aws-sdk/client-s3 3.1169.0 with @smithy/node-http-handler 4.14.2, @grpc/grpc-js 1.14.7, pg 8.23.1, mysql2 3.24.6, ioredis 6.0.0, kafkajs 2.2.4.

| Client | Node 22.20+ / 24.5+ / 26 default | Node 20 | Server used | Evidence |
| --- | --- | --- | --- | --- |
| `tls.connect`, `https.get` | PQ | classical | OpenSSL s_server | Tested |
| global `fetch` | PQ | classical | s_server | Tested |
| undici `Agent` | PQ | undici 8 doesn't load on Node 20 | s_server | Tested |
| axios, got, node-fetch | PQ | classical | s_server | Tested |
| AWS SDK v3 (`NodeHttpHandler`) | PQ | classical | s_server (handshake, then expected parse error) | Tested |
| @grpc/grpc-js | PQ | classical | grpc-js server, Node 24 | Tested |
| pg | PQ | classical | PostgreSQL 18.7, `ssl_groups` | Tested |
| mysql2 | PQ | classical | MariaDB 11.8.6, group list from OpenSSL config | Tested |
| ioredis | PQ | classical | Redis 8.0.2, group list from OpenSSL config | Tested |
| kafkajs | PQ (TLS handshake level) | classical | s_server, not a broker | Tested (handshake only) |

## Client side (app level)

Default rule: on 22.20+/24.5+ set nothing. Find and fix anything that narrows the group list or the protocol. Each excerpt below was run against the PQ-only server.

| Client | Where TLS options go | PQ-safe setting | Evidence |
| --- | --- | --- | --- |
| `tls.connect` | options object | omit `ecdhCurve`, or `ecdhCurve: 'X25519MLKEM768:X25519:P-256:P-384'` | Tested |
| `https` / `https.Agent` | `new https.Agent({...})` | same | Tested (`ecdhCurve: 'X25519:P-256'` failed PQ-only) |
| global `fetch` | none (bundled undici) | nothing; or `dispatcher` from npm undici | Tested |
| undici | `new Agent({ connect: {...} })` | omit `ecdhCurve` or PQ-first | Tested (`connect.ecdhCurve: 'X25519'` failed PQ-only) |
| axios | `httpsAgent` | default agent or a PQ-safe `https.Agent` | Tested |
| got | `https: {...}` or `agent: { https }` | default | Tested (default only) |
| node-fetch | `agent` | PQ-safe `https.Agent` | Tested |
| AWS SDK v3 | `requestHandler: new NodeHttpHandler({ httpsAgent })` | default or PQ-safe agent | Tested |
| @grpc/grpc-js | `credentials.createSsl(ca)` | default; no group option exposed | Tested |
| pg | `ssl: {...}` (passed to `tls.connect`) | default | Tested |
| mysql2 | `ssl: {...}` | default | Tested; not checked whether it passes `ecdhCurve` through |
| ioredis | `tls: {...}` | default | Tested |
| kafkajs | `ssl: {...}` | default | Tested (handshake) |

The pitfall pattern, and the fix:

```js
// BAD: pins classical groups; a PQ-only server rejects it, a hybrid server is downgraded to X25519
const agent = new https.Agent({ ecdhCurve: 'X25519:P-256' });
// GOOD: omit ecdhCurve. If a policy forces a list, put the hybrid group first
const agent = new https.Agent({ keepAlive: true }); // or ecdhCurve: 'X25519MLKEM768:X25519:P-256:P-384'
```

```js
// AWS SDK for JavaScript v3 with a custom agent (proxy, keep-alive, CA bundle)
const { S3Client } = require('@aws-sdk/client-s3');
const { NodeHttpHandler } = require('@smithy/node-http-handler');
const s3 = new S3Client({ requestHandler: new NodeHttpHandler({ httpsAgent: new https.Agent({ keepAlive: true }) }) });
```

```js
// undici / fetch with an explicit dispatcher
const { Agent, setGlobalDispatcher } = require('undici');
setGlobalDispatcher(new Agent({ connect: { /* no ecdhCurve, or PQ-first list */ } }));
```

A PQ-first `ecdhCurve` string throws `ERR_CRYPTO_OPERATION_FAILED: Failed to set ECDH curve` on Node 20 and other OpenSSL 3.0 builds (Tested). Shared code that must run on both should use the helper in `src/tls-pq.js` (full file below), which feature-detects before adding the group.

`tls.DEFAULT_ECDH_CURVE` is documented as the server default ([Node TLS docs](https://nodejs.org/api/tls.html#tlsdefault_ecdh_curve)), but in these tests it also changed client connections: setting it to `X25519:P-256` broke PQ for `tls.connect` and `https.get`, and setting it PQ-first restored PQ on Lambda even with AWS's config file (Tested). There is no `--tls-default-ecdh-curve` flag (checked `node --help` on 24.22.3).

## Server side

Node servers accept X25519MLKEM768 by default on 22.20+/24.5+ and still serve classical and TLS 1.2 clients. Tested with `openssl s_client` (OpenSSL 3.5.7) against each server on `node:24-slim`, `node:22-alpine`, `node:24.5-alpine` and `node:20-slim`.

| Server | PQ-only client | Classical client | Default 3.5 client gets | Evidence |
| --- | --- | --- | --- | --- |
| `https.createServer({ key, cert })` | X25519MLKEM768 | X25519 | X25519MLKEM768 | Tested |
| same + `ecdhCurve: 'X25519:P-256'` | handshake failure | X25519 | X25519 (silent downgrade) | Tested |
| same + `ecdhCurve: 'X25519MLKEM768:X25519:P-256:P-384'` | X25519MLKEM768 | X25519 | X25519MLKEM768 | Tested |
| `http2.createSecureServer` | X25519MLKEM768 | X25519 | X25519MLKEM768 | Tested |
| Express 5.3.0 on `https.createServer` | X25519MLKEM768 | X25519 | X25519MLKEM768 | Tested |
| Fastify 5.12.8 `fastify({ https })` | X25519MLKEM768 | X25519 | X25519MLKEM768 | Tested |
| `tls.createServer({ minVersion: 'TLSv1.3' })` | X25519MLKEM768 | X25519 | X25519MLKEM768 | Tested |
| grpc-js `ServerCredentials.createSsl` | X25519MLKEM768 | X25519 | X25519MLKEM768 | Tested |
| NestJS `NestFactory.create(App, { httpsOptions })` | same options reach `https.createServer` | | | Not tested |
| Any of the above on Node 20 | handshake failure | X25519 | X25519 | Tested; a PQ-first `ecdhCurve` crashes startup |

Excerpts:

```js
https.createServer({ key, cert, minVersion: 'TLSv1.2' }, app);           // Express; no ecdhCurve
fastify({ https: { key, cert } });                                       // Fastify
http2.createSecureServer({ key, cert, allowHTTP1: true }, handler);      // HTTP/2
```

Behind a load balancer the client-facing handshake belongs to the load balancer, not Node: see the Load balancers tab for ALB/NLB policies. With an NLB TCP (pass-through) listener, Node terminates TLS and the table above applies. Whether an ALB offers ML-KEM on its re-encrypted connection to an HTTPS target was not checked here. For nginx or Envoy in front of Node, see Web servers and proxies; for mesh sidecars, see Service mesh.

The server side has no API for the negotiated group: `getEphemeralKeyInfo()` returns `null` on server sockets ([Node TLS docs](https://nodejs.org/api/tls.html#tlssocketgetephemeralkeyinfo)). Probe the server with `s_client` instead (Verify).

## Packaging per compute type

### Lambda zip (nodejs22.x, nodejs24.x)

The bootstrap sets `OPENSSL_CONF=/var/runtime/openssl_conf/openssl.cnf` when the variable is unset, and that file's `Groups` omits ML-KEM. The bootstrap's own comment says "Customers can opt-in to PQC by setting OPENSSL_CONF=/dev/null" (read from `/var/runtime/bootstrap` in `public.ecr.aws/lambda/nodejs:22`). Four tested ways to turn PQ on, all run under the image's Runtime Interface Emulator with the real bootstrap:

| Method | Setting | Result | Evidence |
| --- | --- | --- | --- |
| Ship the PQ config (recommended) | `OPENSSL_CONF=/var/task/pq-tls/openssl-pq-node.cnf` | PQ, classical fallback OK | Tested (RIE, 22 and 24) |
| Command-line flag | `NODE_OPTIONS=--openssl-config=/var/task/pq-tls/openssl-pq-node.cnf` | PQ | Tested (RIE) |
| AWS's opt-in | `OPENSSL_CONF=/dev/null` | PQ (OpenSSL built-in defaults) | Tested (RIE) |
| In code | `tls.DEFAULT_ECDH_CURVE = 'X25519MLKEM768:X25519:P-256:P-384'` before the first connection | PQ | Tested (container with AWS's file set) |
| No change | bootstrap default | PQ-only server fails | Tested (RIE) |

Prefer the shipped file: it keeps AWS's structure, so review sees any future AWS setting. Layout of the zip:

```text
function.zip
├── index.mjs
├── node_modules/...
└── pq-tls/openssl-pq-node.cnf
```

IaC excerpts (full files below):

```yaml
# SAM
Environment:
  Variables:
    OPENSSL_CONF: /var/task/pq-tls/openssl-pq-node.cnf
```

```hcl
# Terraform
environment { variables = { OPENSSL_CONF = "/var/task/pq-tls/openssl-pq-node.cnf" } }
```

Without code changes, the `pq-tls` layer with `AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper` sets the same variable to `/opt/pq-tls/openssl-pq-node.cnf` and leaves a function's own `OPENSSL_CONF` alone (Tested 2026-11-12). nodejs18.x and nodejs20.x have no fix: change `Runtime` to `nodejs22.x` or `nodejs24.x` ([Lambda runtimes](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html): nodejs20.x deprecated Apr 30 2026, update block Aug 31 2027).

### Lambda container image

On `public.ecr.aws/lambda/nodejs:22` or `:24`, copy the file and set `ENV OPENSSL_CONF`; the bootstrap keeps a value that is already set (Tested). Full `Dockerfile.lambda` below.

### Fargate, ECS, EKS

Official `node:22`/`node:24`/`node:26` images (Debian or Alpine) need nothing: no `OPENSSL_CONF` is set and the bundled OpenSSL is 3.5 (Tested). The host OS and its crypto policy don't matter for these images. Pin the image by digest and keep it at 22.20+/24.9+. For an AL2023-based image with `dnf install nodejs22`, run `update-crypto-policies --set DEFAULT:PQ` in the Dockerfile ([AL2023 PQ guide](https://docs.aws.amazon.com/linux/al2023/ug/crypto-policies-pq.html), Documented; Tested here) or set `OPENSSL_CONF` to `openssl-pq-node-system.cnf`. Task definition and pod spec need no TLS setting; the full files below show where `OPENSSL_CONF` would go and assert that `NODE_OPTIONS` carries no `--tls-max-v1.2`.

### EC2

Install official Node 22.20+/24.9+ binaries: PQ by default, crypto policy not involved. With AL2023's `nodejs22` package, set the host policy (`update-crypto-policies --set DEFAULT:PQ`, then restart services) or add `Environment=OPENSSL_CONF=...` to the unit. Debian 13 packages are PQ by default. Full systemd unit and an SSM posture document below.

## Verify

1. **Posture (per runtime):** `node -p "process.version + ' ' + process.versions.openssl"` must show 22.20+/24.5+ and 3.5+ (or a distro build linked to 3.5+). On Lambda also check `OPENSSL_CONF` or `NODE_OPTIONS`. `pq-check.js` (below) prints both and whether the runtime can parse `X25519MLKEM768`. Capable is not the same as enabled: Lambda with AWS's file reports capable and still sends classical.
2. **Live test (client):** `node pq-check.js pq-only.example.internal:443 classical.example.internal:443`. The PQ-only target must report `"pq":true`; the classical target must connect (it reports `"pq":false`, which is the expected fallback). Stand up the two targets with `openssl s_server -groups X25519MLKEM768 -tls1_3` and `-groups X25519`.
3. **Live test (server):** `openssl s_client -connect host:443 -groups X25519MLKEM768 -tls1_3 -brief` prints `Negotiated TLS1.3 group: X25519MLKEM768`; `-groups X25519` must still connect.
4. **Observed signal:** in the client, `socket.getEphemeralKeyInfo()` returns `{"type":"TLSGroup","name":"X25519MLKEM768"}` on Node 24 and 26, `{}` on Node 22 (TLS 1.3, no EC key = the hybrid group), and `{"type":"ECDH","name":"X25519"}` when classical (Tested). For AWS calls, CloudTrail `tlsDetails.keyExchange` shows the group for KMS, STS, IAM, Secrets Manager, ACM and Payment Cryptography (see AWS service endpoints).
5. **Code and dependency scan:** `grep -rnE "ecdhCurve|DEFAULT_ECDH_CURVE|maxVersion|secureProtocol|TLSv1_2_method|tls-max-v1\.2" --include='*.js' --include='*.mjs' --include='*.cjs' --include='*.ts' .` including `node_modules` (a dependency can set it too).
6. **Fleet inventory:** `aws lambda list-functions --query "Functions[?starts_with(Runtime,'nodejs')].[FunctionName,Runtime,Environment.Variables.OPENSSL_CONF]" --output text` lists runtimes and overrides; the Enforcement and guardrails tab covers blocking old runtimes.

## Pitfalls and rollback

| Pitfall | Effect | Fix | Evidence |
| --- | --- | --- | --- |
| Explicit classical `ecdhCurve` on a client | PQ-only server rejects; others downgrade | remove it or put `X25519MLKEM768` first | Tested |
| Explicit classical `ecdhCurve` on a server | every client silently gets X25519 | same | Tested |
| PQ-first `ecdhCurve` on Node 20 / OpenSSL 3.0 | throws at startup; a server process crashes | upgrade, or feature-detect (`tls-pq.js`) | Tested |
| `tls.DEFAULT_ECDH_CURVE` set classical | clients and servers lose PQ | remove it | Tested |
| `--tls-max-v1.2`, `maxVersion: 'TLSv1.2'`, `secureProtocol: 'TLSv1_2_method'` | no TLS 1.3, so no ML-KEM | remove the cap | Tested (`--tls-max-v1.2`) |
| Lambda bootstrap config | nodejs22/24 classical | ship `openssl-pq-node.cnf` | Tested |
| Function already sets `OPENSSL_CONF` (FIPS, custom CA) | your file replaces theirs | merge `Groups` into their file instead | Unverified (not tested with a FIPS config) |
| AL2023 `dnf` Node | follows the system crypto policy, classical by default | `DEFAULT:PQ` or `OPENSSL_CONF` | Tested |
| "Node 20 is never PQ" | wrong for Debian 13's 20.19.2 (system OpenSSL 3.5.7) | check `process.versions.openssl`, not the major | Tested |
| Bun reports `process.versions.openssl` = `1.1.0` | version-based posture checks misread it | live test instead | Tested (Bun 1.4.4 is PQ) |
| Lambda runtime pinned in Manual update mode | could stay below 22.20 | check the runtime version ARN | Unverified |
| Larger ClientHello (~1.2 KB more key share) | some middleboxes drop it | live test through the real path | not observed here |

Rollback: remove `OPENSSL_CONF`/`NODE_OPTIONS` from the function (back to AWS's classical file); remove the `ENV` line in a Lambda image; redeploy the previous image digest for containers; `update-crypto-policies --set DEFAULT` on AL2023; on a server, set `TLS_ECDH_CURVE=X25519:P-256:P-384` in `server.js` (below) as a temporary classical-only switch. Each is a config change with no code rollback.

## Full configuration files

Every file referenced above. The two `.cnf` files, `tls-pq.js`, `pq-check.js` and `server.js` were run in the tests; the IaC files are written to the documented resource schemas and were not deployed (no AWS account in the test lab).

`pq-tls/openssl-pq-node.cnf` (Lambda nodejs22/24: AWS's file with the hybrid group added first; Tested)

```ini
# Replaces the Lambda Node.js runtime's /var/runtime/openssl_conf/openssl.cnf (same structure),
# with the hybrid post-quantum group first. Node reads the nodejs_conf section.
nodejs_conf = openssl_init

[openssl_init]
ssl_conf = ssl_sect

[ssl_sect]
system_default = system_default_sect

[system_default_sect]
Groups = *X25519MLKEM768:*X25519:secp256r1:X448:secp521r1:secp384r1:ffdhe2048:ffdhe3072:ffdhe4096:ffdhe6144:ffdhe8192
```

`/etc/app/openssl-pq-node-system.cnf` (distro Node on system OpenSSL 3.5+, when you can't change the host policy; Tested on AL2023 nodejs22)

```ini
# Node reads nodejs_conf by default and openssl_conf with --openssl-shared-config; both point here.
openssl_conf = pq_init
nodejs_conf = pq_init

[pq_init]
ssl_conf = pq_ssl

[pq_ssl]
system_default = pq_system_default

[pq_system_default]
Groups = *X25519MLKEM768:*X25519:secp256r1:X448:secp521r1:secp384r1:ffdhe2048:ffdhe3072:ffdhe4096:ffdhe6144:ffdhe8192
```

`check-lambda-node-conf.sh` (pipeline check: fail when AWS changes its file in a way ours doesn't mirror)

```bash
#!/bin/bash
# Usage: check-lambda-node-conf.sh 24   -> compares AWS's file in the current base image with ours, ignoring Groups.
set -euo pipefail
img="public.ecr.aws/lambda/nodejs:${1:?node major}"
norm() { grep -vE '^\s*(#|$)' | grep -v '^Groups' ; }
diff <(docker run --rm --entrypoint cat "$img" /var/runtime/openssl_conf/openssl.cnf | norm) \
     <(norm < pq-tls/openssl-pq-node.cnf) && echo "OK: only Groups differs"
docker run --rm --entrypoint grep "$img" -n 'OPENSSL_CONF' /var/runtime/bootstrap
```

`src/tls-pq.js` (shared TLS options with feature detection; Tested on Node 20, 22, 24)

```js
'use strict';
const tls = require('node:tls');
const https = require('node:https');

const PQ_GROUPS = 'X25519MLKEM768:X25519:P-256:P-384';

function pqCapable() {
  try { tls.createSecureContext({ ecdhCurve: 'X25519MLKEM768' }); return true; } catch { return false; }
}

// Spread into tls.connect / https.Agent / undici connect / pg ssl / ioredis tls / kafkajs ssl.
function tlsOptions(extra = {}) {
  const o = { minVersion: 'TLSv1.2', ...extra };
  if (o.ecdhCurve && pqCapable() && !o.ecdhCurve.includes('MLKEM')) {
    o.ecdhCurve = `X25519MLKEM768:${o.ecdhCurve}`; // pinned list: hybrid first, theirs as fallback
  }
  return o;
}

function httpsAgent(extra = {}) {
  return new https.Agent({ keepAlive: true, ...tlsOptions(extra) });
}

function report() {
  return { node: process.version, openssl: process.versions.openssl, pqCapable: pqCapable(),
    OPENSSL_CONF: process.env.OPENSSL_CONF || null, NODE_OPTIONS: process.env.NODE_OPTIONS || null,
    DEFAULT_ECDH_CURVE: tls.DEFAULT_ECDH_CURVE };
}

module.exports = { PQ_GROUPS, pqCapable, tlsOptions, httpsAgent, report };
```

`pq-check.js` (posture + live check; exit 1 if any target is not PQ; Tested)

```js
#!/usr/bin/env node
'use strict';
const tls = require('node:tls');
let pq = false;
try { tls.createSecureContext({ ecdhCurve: 'X25519MLKEM768' }); pq = true; } catch {}
console.log(JSON.stringify({ posture: { node: process.version, openssl: process.versions.openssl, pqCapable: pq,
  OPENSSL_CONF: process.env.OPENSSL_CONF || null, NODE_OPTIONS: process.env.NODE_OPTIONS || null,
  DEFAULT_ECDH_CURVE: tls.DEFAULT_ECDH_CURVE } }));
let bad = !pq;
const one = (t) => new Promise((done) => {
  const [host, port = '443'] = t.split(':');
  const s = tls.connect({ host, port: Number(port), servername: host }, () => {
    const k = s.getEphemeralKeyInfo() || {};
    // Node 24+: {type:'TLSGroup',name:'X25519MLKEM768'}; Node 22: {} for ML-KEM; classical: {type:'ECDH',name:'X25519'}
    const group = k.name || (s.getProtocol() === 'TLSv1.3' && !k.type ? 'non-EC group (ML-KEM hybrid on Node 22)' : 'unknown');
    const ok = /MLKEM|non-EC/.test(group);
    if (!ok) bad = true;
    console.log(JSON.stringify({ target: t, protocol: s.getProtocol(), group, pq: ok }));
    s.end(); done();
  });
  s.setTimeout(8000, () => s.destroy(new Error('timeout')));
  s.on('error', (e) => { bad = true; console.log(JSON.stringify({ target: t, error: e.code || e.message })); done(); });
});
(async () => { for (const t of process.argv.slice(2)) await one(t); process.exit(bad ? 1 : 0); })();
```

`server.js` (Express on HTTPS; Tested on node:24-slim: PQ client X25519MLKEM768, classical client X25519, TLS 1.2 client OK)

```js
'use strict';
const fs = require('node:fs');
const https = require('node:https');
const express = require('express');

const app = express();
app.get('/healthz', (req, res) => res.send('ok'));
app.get('/', (req, res) => res.send(`tls ${req.socket.getProtocol()}`));

const opts = {
  key: fs.readFileSync(process.env.TLS_KEY || '/etc/app/tls/server.key'),
  cert: fs.readFileSync(process.env.TLS_CERT || '/etc/app/tls/server.pem'),
  minVersion: process.env.TLS_MIN_VERSION || 'TLSv1.2', // 'TLSv1.3' to refuse TLS 1.2 clients
};
// Optional explicit list. Must start with X25519MLKEM768, or PQ clients are silently downgraded.
if (process.env.TLS_ECDH_CURVE) opts.ecdhCurve = process.env.TLS_ECDH_CURVE;

https.createServer(opts, app).listen(Number(process.env.PORT || 8443), () =>
  console.log(JSON.stringify({ msg: 'listening', node: process.version, openssl: process.versions.openssl,
    ecdhCurve: opts.ecdhCurve || 'default', minVersion: opts.minVersion })));
```

`template.yaml` (SAM, Lambda zip)

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Globals:
  Function:
    Runtime: nodejs24.x
    Architectures: [arm64]
    Environment:
      Variables:
        OPENSSL_CONF: /var/task/pq-tls/openssl-pq-node.cnf
Resources:
  OrdersFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: build/   # contains index.mjs, node_modules/, pq-tls/openssl-pq-node.cnf
      Handler: index.handler
      Timeout: 10
```

`lambda-cfn.yaml` (plain CloudFormation, Lambda zip)

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Parameters:
  CodeBucket: { Type: String }
  CodeKey: { Type: String }
  RoleArn: { Type: String }
Resources:
  OrdersFunction:
    Type: AWS::Lambda::Function
    Properties:
      Runtime: nodejs24.x
      Architectures: [arm64]
      Handler: index.handler
      Role: !Ref RoleArn
      Code: { S3Bucket: !Ref CodeBucket, S3Key: !Ref CodeKey }
      Environment:
        Variables:
          OPENSSL_CONF: /var/task/pq-tls/openssl-pq-node.cnf
```

`lambda.tf` (Terraform, Lambda zip)

```hcl
resource "aws_lambda_function" "orders" {
  function_name    = "orders"
  runtime          = "nodejs24.x"
  architectures    = ["arm64"]
  handler          = "index.handler"
  role             = aws_iam_role.orders.arn
  filename         = "build/function.zip" # includes pq-tls/openssl-pq-node.cnf
  source_code_hash = filebase64sha256("build/function.zip")

  environment {
    variables = {
      OPENSSL_CONF = "/var/task/pq-tls/openssl-pq-node.cnf"
      # Alternative (Tested): NODE_OPTIONS = "--openssl-config=/var/task/pq-tls/openssl-pq-node.cnf"
    }
  }
}
```

`Dockerfile.lambda` (Lambda container image)

```dockerfile
FROM public.ecr.aws/lambda/nodejs:24@sha256:eb0de3ee81b4638149f0b1bcab2c657603a23a0c221a4b5678be29b48265bd31
COPY package.json package-lock.json ${LAMBDA_TASK_ROOT}/
RUN npm ci --omit=dev
COPY index.mjs ${LAMBDA_TASK_ROOT}/
COPY pq-tls/openssl-pq-node.cnf ${LAMBDA_TASK_ROOT}/pq-tls/openssl-pq-node.cnf
# The bootstrap only sets its own (classical) file when OPENSSL_CONF is unset.
ENV OPENSSL_CONF=/var/task/pq-tls/openssl-pq-node.cnf
CMD ["index.handler"]
```

`Dockerfile` (Fargate / ECS / EKS, official image: nothing PQ-specific)

```dockerfile
FROM node:24-slim@sha256:dc26ae92c9fb15cf6b1d63e20f0944b2efe0f115b20e00be48fb23fceb061c54
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY . .
ENV NODE_ENV=production
# Build-time guard: fail the build if this Node can't do ML-KEM.
RUN node pq-check.js
USER node
EXPOSE 8443
CMD ["node", "server.js"]
```

`Dockerfile.al2023` (AL2023 base with the distro Node package; Tested)

```dockerfile
FROM public.ecr.aws/amazonlinux/amazonlinux:2023
RUN dnf -y install nodejs22 crypto-policies-scripts shadow-utils \
 && update-crypto-policies --set DEFAULT:PQ \
 && dnf clean all && useradd -r app
WORKDIR /app
COPY --chown=app package.json package-lock.json ./
RUN npm ci --omit=dev
COPY --chown=app . .
RUN node pq-check.js
USER app
CMD ["node", "server.js"]
```

`taskdef.json` (ECS / Fargate; no TLS setting needed)

```json
{
  "family": "orders",
  "requiresCompatibilities": ["FARGATE"],
  "networkMode": "awsvpc",
  "cpu": "512",
  "memory": "1024",
  "runtimePlatform": { "cpuArchitecture": "ARM64", "operatingSystemFamily": "LINUX" },
  "executionRoleArn": "arn:aws:iam::111122223333:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "orders",
      "image": "111122223333.dkr.ecr.eu-west-1.amazonaws.com/orders@sha256:<digest>",
      "essential": true,
      "portMappings": [{ "containerPort": 8443, "protocol": "tcp" }],
      "environment": [
        { "name": "NODE_ENV", "value": "production" },
        { "name": "TLS_MIN_VERSION", "value": "TLSv1.2" }
      ],
      "healthCheck": { "command": ["CMD", "node", "-e", "require('https').get({host:'localhost',port:8443,path:'/healthz',rejectUnauthorized:false},r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"], "interval": 30, "timeout": 5, "retries": 3 }
    }
  ]
}
```

`ecs.tf` (Terraform; distro-Node images only need the commented line)

```hcl
resource "aws_ecs_task_definition" "orders" {
  family                   = "orders"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_exec.arn
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
  container_definitions = jsonencode([{
    name         = "orders"
    image        = "${aws_ecr_repository.orders.repository_url}@${var.image_digest}"
    essential    = true
    portMappings = [{ containerPort = 8443, protocol = "tcp" }]
    environment = [
      { name = "NODE_ENV", value = "production" },
      # { name = "OPENSSL_CONF", value = "/etc/app/openssl-pq-node-system.cnf" }, # distro Node without DEFAULT:PQ
    ]
  }])
}
```

`ecs-cfn.yaml` (CloudFormation)

```yaml
Resources:
  OrdersTask:
    Type: AWS::ECS::TaskDefinition
    Properties:
      Family: orders
      RequiresCompatibilities: [FARGATE]
      NetworkMode: awsvpc
      Cpu: '512'
      Memory: '1024'
      ExecutionRoleArn: !Ref ExecRoleArn
      RuntimePlatform: { CpuArchitecture: ARM64, OperatingSystemFamily: LINUX }
      ContainerDefinitions:
        - Name: orders
          Image: !Sub '${AWS::AccountId}.dkr.ecr.${AWS::Region}.amazonaws.com/orders@${ImageDigest}'
          Essential: true
          PortMappings: [{ ContainerPort: 8443, Protocol: tcp }]
          Environment:
            - { Name: NODE_ENV, Value: production }
Parameters:
  ExecRoleArn: { Type: String }
  ImageDigest: { Type: String }
```

`deployment.yaml` (EKS)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: orders }
spec:
  replicas: 2
  selector: { matchLabels: { app: orders } }
  template:
    metadata: { labels: { app: orders } }
    spec:
      containers:
        - name: orders
          image: 111122223333.dkr.ecr.eu-west-1.amazonaws.com/orders@sha256:<digest>
          ports: [{ containerPort: 8443 }]
          env:
            - { name: NODE_ENV, value: production }
            # Distro Node without DEFAULT:PQ only:
            # - { name: OPENSSL_CONF, value: /etc/app/openssl-pq-node-system.cnf }
          volumeMounts: [{ name: tls, mountPath: /etc/app/tls, readOnly: true }]
          readinessProbe: { httpGet: { path: /healthz, port: 8443, scheme: HTTPS } }
      volumes:
        - name: tls
          secret: { secretName: orders-tls }
```

`/etc/systemd/system/orders.service` (EC2)

```ini
[Unit]
Description=orders API (Node.js)
After=network-online.target
Wants=network-online.target

[Service]
User=app
WorkingDirectory=/srv/orders
# Official binaries 22.20+/24.9+: nothing else needed.
ExecStart=/opt/node-v24/bin/node /srv/orders/server.js
Environment=NODE_ENV=production
Environment=TLS_KEY=/etc/app/tls/server.key
Environment=TLS_CERT=/etc/app/tls/server.pem
# AL2023 dnf nodejs22 without the DEFAULT:PQ host policy:
# Environment=OPENSSL_CONF=/etc/app/openssl-pq-node-system.cnf
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

`pq-node-posture.json` (SSM Command document: reports every running Node process)

```json
{
  "schemaVersion": "2.2",
  "description": "Report Node.js version, OpenSSL version and TLS-relevant environment for every running node process.",
  "mainSteps": [
    {
      "action": "aws:runShellScript",
      "name": "nodePqPosture",
      "inputs": {
        "runCommand": [
          "command -v update-crypto-policies >/dev/null && echo \"crypto-policy: $(update-crypto-policies --show)\"",
          "for pid in $(pgrep -x node); do exe=$(readlink /proc/$pid/exe); echo pid=$pid exe=$exe; $exe -e 'console.log(process.version, process.versions.openssl)'; tr '\\0' '\\n' < /proc/$pid/environ | grep -E '^(OPENSSL_CONF|NODE_OPTIONS)=' || true; done"
        ]
      }
    }
  ]
}
```
