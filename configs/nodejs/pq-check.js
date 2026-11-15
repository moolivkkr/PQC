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
