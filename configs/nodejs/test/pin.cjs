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
