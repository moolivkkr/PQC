const tls = require('tls');
const one = (port) => new Promise((done) => {
  const s = tls.connect({ host: 'pqsrv', port, rejectUnauthorized: false }, () => { done('OK ' + s.getProtocol()); s.destroy(); });
  s.on('error', (e) => done('FAIL ' + (e.code || e.message)));
  s.setTimeout(5000, () => { s.destroy(); done('FAIL timeout'); });
});
exports.handler = async () => ({
  runtime: process.version, openssl: process.versions.openssl,
  pq_only: await one(8443), classical_only: await one(8444),
});
