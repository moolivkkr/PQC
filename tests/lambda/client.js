const tls = require('tls');
const label = process.argv[2] || 'node';
const one = (port, name) => new Promise((done) => {
  const s = tls.connect({ host: 'pqsrv', port, rejectUnauthorized: false }, () => {
    console.log(`${label}: ${name}: OK ${s.getProtocol()}`); s.destroy(); done();
  });
  s.on('error', (e) => { console.log(`${label}: ${name}: FAIL ${e.code || e.message}`); done(); });
  s.setTimeout(5000, () => { console.log(`${label}: ${name}: FAIL timeout`); s.destroy(); done(); });
});
(async () => { await one(8443, 'PQ-only'); await one(8444, 'classical-only'); })();
