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
