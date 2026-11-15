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
