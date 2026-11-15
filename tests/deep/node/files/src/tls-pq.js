// src/tls-pq.js — one place for TLS key-exchange settings. Import it instead of setting ecdhCurve ad hoc.
// Rule: on Node 22.20+/24.5+ leave ecdhCurve unset (the default already prefers X25519MLKEM768).
// Use PQ_GROUPS only when a library or policy forces you to set a list; it is never passed on a runtime that
// cannot parse it (Node 20 and older throw ERR_CRYPTO_OPERATION_FAILED "Failed to set ECDH curve").
'use strict';
const tls = require('node:tls');
const https = require('node:https');

const PQ_GROUPS = 'X25519MLKEM768:X25519:P-256:P-384';

function pqCapable() {
  try { tls.createSecureContext({ ecdhCurve: 'X25519MLKEM768' }); return true; } catch { return false; }
}

// Options to spread into tls.connect / https.Agent / undici connect / pg ssl / ioredis tls / kafkajs ssl.
function tlsOptions(extra = {}) {
  const o = { minVersion: 'TLSv1.2', ...extra };
  if (o.ecdhCurve && pqCapable() && !o.ecdhCurve.includes('MLKEM')) {
    // A caller pinned classical groups: put the hybrid group first, keep theirs as fallback.
    o.ecdhCurve = `X25519MLKEM768:${o.ecdhCurve}`;
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
