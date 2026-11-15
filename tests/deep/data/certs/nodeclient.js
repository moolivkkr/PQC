// Node client: TLS to the dual-cert nginx with both roots trusted; report which leaf it got.
const tls = require('tls');
const fs = require('fs');
console.log('node', process.version, 'openssl', process.versions.openssl);
const s = tls.connect({ host: 'web', port: 443, servername: 'web', ca: fs.readFileSync('/work/roots-both.crt') }, () => {
  const c = s.getPeerX509Certificate();
  console.log('tls ok:', s.getProtocol(), 'authorized=', s.authorized, 'leafKey=', c.publicKey.asymmetricKeyType, 'group=', s.getEphemeralKeyInfo && JSON.stringify(s.getEphemeralKeyInfo()));
  s.end();
});
s.on('error', (e) => console.log('tls FAIL', e.message));
