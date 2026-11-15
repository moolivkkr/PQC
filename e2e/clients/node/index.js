'use strict';
// PQ TLS probe - Node.js. Same file on Lambda (exports.handler), ECS and EC2 (CLI: node index.js [case-id]).
// No PQ-specific settings: the probe never sets ecdhCurve, groups or TLS versions. Whatever the runtime, its
// OpenSSL, the OpenSSL config file (OPENSSL_CONF / --openssl-config), NODE_OPTIONS and the platform give is measured.
//
// Client stack: node:https (https.request, default global agent), the path most applications and SDKs use.
// Trust (PQC_NODE_TRUST):  ca  (default) -> `ca: ca.crt` option, the test CA only
//                          env           -> no `ca` option; trust must come from NODE_EXTRA_CA_CERTS & co.
// mTLS client cert (PQC_NODE_CLIENT_CERT, mtls target only):
//                          pem (default) -> cert: client.crt, key: client.key
//                          pfx           -> pfx: client.p12 (AES-256/PBKDF2), passphrase changeit
//                          pfx-legacy    -> pfx: client-legacy.p12 (RC2-40/3DES, `openssl pkcs12 -legacy`)
// PQC_NODE_STACK=fetch uses the global fetch (bundled undici) instead of https; it has no per-request ca/cert,
// so it needs PQC_NODE_TRUST=env and does not do mTLS.
//
// Every result is also printed as one JSON line {"event":"tls_handshake",...} for the CloudWatch Logs filter.
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const https = require('node:https');

const TARGETS = { hybrid: 8443, pqonly: 8444, mtls: 8445, eccert: 8446, tls12: 8447 };
const env = process.env;

function certsDir() {
  for (const d of [env.PQC_CERTS || '', path.join(__dirname, 'certs'), '/opt/pqc-certs', '/etc/pqc/certs']) {
    if (d && fs.existsSync(path.join(d, 'ca.crt'))) return d;
  }
  throw new Error('test CA not found (set PQC_CERTS)');
}

function errText(e) {
  const x = e && e.cause && (e.cause.code || e.cause.message) ? e.cause : e; // fetch wraps the TLS error in .cause
  return `${(x && (x.code || x.name)) || 'Error'}: ${String((x && x.message) || x).slice(0, 300)}`;
}

function viaExtension(name, caseId) {
  // Extension mode: plain HTTP to the pq-egress extension, which originates the (PQ) TLS connection upstream.
  return new Promise((resolve, reject) => {
    const req = http.get({ host: '127.0.0.1', port: Number(env.PQC_EGRESS_PORT), path: `/${name}/probe?id=${encodeURIComponent(caseId)}`,
      timeout: 10000 }, (res) => {
      let body = ''; res.setEncoding('utf8'); res.on('data', (d) => (body += d));
      res.on('end', () => {
        try { resolve({ obs: JSON.parse(body), stack: 'extension:pq-egress' }); } catch (e) { reject(new Error(`HTTP ${res.statusCode}: ${body.slice(0, 200)}`)); }
      });
    });
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', reject);
  });
}

function viaHttps(host, name, port, caseId, certs) {
  const opts = { host, port, path: `/probe?id=${encodeURIComponent(caseId)}`, method: 'GET', timeout: 10000 };
  const trust = env.PQC_NODE_TRUST || 'ca';
  if (trust === 'ca') opts.ca = fs.readFileSync(path.join(certs, 'ca.crt'));
  if (name === 'mtls') {
    const cc = env.PQC_NODE_CLIENT_CERT || 'pem';
    if (cc === 'pem') {
      opts.cert = fs.readFileSync(path.join(certs, 'client.crt'));
      opts.key = fs.readFileSync(path.join(certs, 'client.key'));
    } else {
      opts.pfx = fs.readFileSync(path.join(certs, cc === 'pfx-legacy' ? 'client-legacy.p12' : 'client.p12'));
      opts.passphrase = 'changeit';
    }
  }
  return new Promise((resolve, reject) => {
    let req;
    try {
      req = https.request(opts, (res) => {
        const sock = res.socket;
        const info = { protocol: sock.getProtocol && sock.getProtocol(), key: sock.getEphemeralKeyInfo ? sock.getEphemeralKeyInfo() : null };
        let body = ''; res.setEncoding('utf8'); res.on('data', (d) => (body += d));
        res.on('end', () => {
          try { resolve({ obs: JSON.parse(body), info, stack: `https (trust=${trust})` }); } catch (e) { reject(new Error(`HTTP ${res.statusCode}: ${body.slice(0, 200)}`)); }
        });
      });
    } catch (e) { return reject(e); } // e.g. pfx parse errors are thrown synchronously
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', reject);
    req.end();
  });
}

async function viaFetch(host, name, port, caseId) {
  const ac = new AbortController(); const t = setTimeout(() => ac.abort(), 10000);
  try {
    const r = await fetch(`https://${host}:${port}/probe?id=${encodeURIComponent(caseId)}`, { signal: ac.signal });
    return { obs: JSON.parse(await r.text()), stack: 'global fetch (trust=env)' };
  } finally { clearTimeout(t); }
}

function log(o) { process.stdout.write(JSON.stringify(o) + '\n'); }

async function run(caseId, targets) {
  caseId = caseId || env.PQC_CASE_ID || 'adhoc';
  const host = env.PQC_OBSERVER || 'pq-observer';
  const names = targets || (env.PQC_TARGETS || Object.keys(TARGETS).join(',')).split(',').filter(Boolean);
  const certs = certsDir();
  // LocalStack's Lambda emulation injects NODE_TLS_REJECT_UNAUTHORIZED=0 (real Lambda does not), which turns off
  // certificate verification for every client and would hide the trust cases (tab case D). Record it, then drop it
  // so Node's real default (verify) applies. Node reads the variable per connection, so this covers https and fetch.
  const injected = env.NODE_TLS_REJECT_UNAUTHORIZED;
  if (injected !== undefined && env.PQC_KEEP_TLS_REJECT !== '1') delete process.env.NODE_TLS_REJECT_UNAUTHORIZED;
  const out = { case_id: caseId, lang: 'node', runtime: process.version, tls_lib: `OpenSSL ${process.versions.openssl}`,
    compute: env.PQC_COMPUTE || 'unknown', mode: env.PQC_MODE || 'baseline', openssl_conf: env.OPENSSL_CONF || '',
    node_options: env.NODE_OPTIONS || '', node_extra_ca_certs: env.NODE_EXTRA_CA_CERTS || '', exec_path: process.execPath,
    // trust/TLS-relevant environment as the process sees it (the platform may inject some of these)
    tls_env: Object.fromEntries(Object.entries(env).filter(([k]) =>
      /^(NODE_TLS_REJECT_UNAUTHORIZED|NODE_EXTRA_CA_CERTS|NODE_USE_SYSTEM_CA|SSL_CERT_FILE|SSL_CERT_DIR|REQUESTS_CA_BUNDLE|CURL_CA_BUNDLE|AWS_CA_BUNDLE)$/.test(k))),
    results: {} };
  if (injected !== undefined) out.removed_env = { NODE_TLS_REJECT_UNAUTHORIZED: injected };
  for (const name of names) {
    const t0 = Date.now();
    let res;
    try {
      let r;
      if (env.PQC_EGRESS_PORT) r = await viaExtension(name, caseId);
      else if (env.PQC_NODE_STACK === 'fetch') r = await viaFetch(host, name, TARGETS[name], caseId);
      else r = await viaHttps(host, name, TARGETS[name], caseId, certs);
      const o = r.obs || {};
      res = { ok: true, tls_version: o.tls_version, group: o.group, pq: !!o.pq, offered_pq: !!o.offered_pq, stack: r.stack };
      if (r.info) res.client_view = r.info; // getProtocol + getEphemeralKeyInfo, as the client sees it
    } catch (e) {
      res = { ok: false, error: errText(e), stack: (e && e.stack ? String(e.stack).split('\n').slice(0, 3).join(' | ') : undefined) };
    }
    res.ms = Date.now() - t0;
    // string field for log filters: {$.pq_status = "classical"} (LocalStack lacks boolean JSON filters)
    res.pq_status = !res.ok ? 'failed' : (res.pq ? 'pq' : 'classical');
    out.results[name] = res;
    log({ event: 'tls_handshake', case_id: caseId, lang: 'node', runtime: out.runtime, compute: out.compute, mode: out.mode,
      target: name, ...res });
  }
  return out;
}

exports.run = run;
exports.handler = async (event) => { // Lambda
  event = event || {};
  return run(event.case_id, event.targets);
};

if (require.main === module) {
  run(process.argv[2]).then((r) => {
    process.stdout.write('PQC_RESULT ' + JSON.stringify(r) + '\n', () => process.exit(0));
  }, (e) => { console.error('probe crashed:', e); process.exit(2); });
}
