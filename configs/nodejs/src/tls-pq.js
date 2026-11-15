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
