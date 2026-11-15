'use strict';
// Server-side probe for case C (existing certs/keys), E (server requires client certs) and F (server settings).
// One Node process, one listener per variant. Probed by openssl s_client 3.5 (run-cases.sh).
const fs = require('node:fs');
const tls = require('node:tls');
const https = require('node:https');
const http2 = require('node:http2');
const N = '/n/app/node_modules/';
const C = (f) => fs.readFileSync('/w/certs/' + f);
const rsa = { key: C('rsa.key'), cert: C('rsa.pem') };
const ec = { key: C('ec.key'), cert: C('ec.pem') };
const ec384 = { key: C('ec384.key'), cert: C('ec384.pem') };
const hello = (req, res) => res.end('ok\n');
const up = (p, what) => console.log(`listening ${p} ${what}`);
function L(port, what, mk) {
  try { const s = mk(); s.on('tlsClientError', () => {}); s.listen(port, () => up(port, what)); }
  catch (e) { console.log(`failed ${port} ${what} :: ${e.code || ''} ${e.message.split('\n')[0]}`); }
}
// ---- Case C: existing certificates
L(9101, 'C RSA PEM key/cert', () => https.createServer({ ...rsa }, hello));
L(9102, 'C EC P-256 PEM key/cert', () => https.createServer({ ...ec }, hello));
L(9103, 'C RSA+EC in one context (key/cert arrays)', () => https.createServer({ key: [rsa.key, ec.key], cert: [rsa.cert, ec.cert] }, hello));
L(9104, 'C encrypted PKCS#8 EC key + passphrase', () => https.createServer({ key: C('ec-enc.key'), cert: ec.cert, passphrase: 's3cret' }, hello));
L(9105, 'C encrypted traditional RSA key + passphrase', () => https.createServer({ key: C('rsa-enc-trad.key'), cert: rsa.cert, passphrase: 's3cret' }, hello));
L(9106, 'C pfx RSA (AES/PBKDF2) + passphrase', () => https.createServer({ pfx: C('rsa.pfx'), passphrase: 's3cret' }, hello));
L(9107, 'C pfx EC + passphrase', () => https.createServer({ pfx: C('ec.pfx'), passphrase: 's3cret' }, hello));
L(9108, 'C pfx legacy RC2/3DES + passphrase', () => https.createServer({ pfx: C('rsa-legacy.pfx'), passphrase: 's3cret' }, hello));
const sni = { 'a.test': tls.createSecureContext(rsa), 'b.test': tls.createSecureContext(ec), 'c.test': tls.createSecureContext(ec384) };
L(9109, 'C SNICallback a=RSA b=EC c=EC384 default=RSA', () => https.createServer({ ...rsa, SNICallback: (name, cb) => cb(null, sni[name]) }, hello));
L(9110, 'C addContext b.test=EC pfx, default RSA', () => { const s = https.createServer({ ...rsa }, hello); s.addContext('b.test', { pfx: C('ec.pfx'), passphrase: 's3cret' }); return s; });
L(9111, 'C Express 5 on https EC', () => { const app = require(N + 'express')(); app.get('/', (q, r) => r.send('ok')); return https.createServer({ ...ec }, app); });
L(9113, 'C http2.createSecureServer EC + SNICallback', () => http2.createSecureServer({ ...ec, allowHTTP1: true, SNICallback: (n, cb) => cb(null, sni[n]) }, hello));
try {
  const f = require(N + 'fastify')({ https: { pfx: C('rsa.pfx'), passphrase: 's3cret' } });
  f.get('/', async () => 'ok');
  f.listen({ port: 9112, host: '0.0.0.0' }).then(() => up(9112, 'C Fastify 5 https pfx + passphrase')).catch((e) => console.log('failed 9112 fastify', e.message));
} catch (e) { console.log('failed 9112 fastify', e.message); }
// ---- Case E: server requires a client certificate
L(9114, 'E https requestCert+rejectUnauthorized, ca=private CA', () => https.createServer({ ...ec, ca: C('ca.pem'), requestCert: true, rejectUnauthorized: true }, (q, r) => r.end('cn=' + q.socket.getPeerCertificate().subject.CN + '\n')));
// ---- Case F: server-side settings
L(9121, 'F ecdhCurve X25519:P-256', () => https.createServer({ ...ec, ecdhCurve: 'X25519:P-256' }, hello));
L(9122, 'F ecdhCurve auto', () => https.createServer({ ...ec, ecdhCurve: 'auto' }, hello));
L(9123, 'F ecdhCurve PQ-first', () => https.createServer({ ...ec, ecdhCurve: 'X25519MLKEM768:X25519:P-256:P-384' }, hello));
L(9124, 'F ciphers TLS1.2-only list', () => https.createServer({ ...ec, ciphers: 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256' }, hello));
L(9125, 'F maxVersion TLSv1.2', () => https.createServer({ ...ec, maxVersion: 'TLSv1.2' }, hello));
L(9126, 'F secureProtocol TLSv1_2_method', () => https.createServer({ ...ec, secureProtocol: 'TLSv1_2_method' }, hello));
L(9127, 'F ecdhCurve X25519MLKEM768 only (PQ-only server)', () => https.createServer({ ...ec, ecdhCurve: 'X25519MLKEM768', minVersion: 'TLSv1.3' }, hello));
console.log(`node ${process.version} openssl ${process.versions.openssl} OPENSSL_CONF=${process.env.OPENSSL_CONF || ''}`);
