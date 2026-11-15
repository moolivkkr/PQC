// Two TLS 1.3 servers: 8443 accepts ONLY X25519MLKEM768 (PQ hybrid); 8444 accepts ONLY X25519 (control).
// A client that completes a handshake on 8443 both supports and offers ML-KEM by default.
const tls = require('tls');
const fs = require('fs');
const pfx = fs.readFileSync('/w/server.p12');
for (const [port, curve] of [[8443, 'X25519MLKEM768'], [8444, 'X25519']]) {
  tls.createServer({ pfx, passphrase: 'changeit', minVersion: 'TLSv1.3', ecdhCurve: curve }, (s) => {
    s.end('ok ' + curve + '\n');
  }).on('tlsClientError', (e) => console.log(`[${curve}] client error: ${e.code || e.message}`))
    .listen(port, () => console.log(`listening ${port} ${curve} node ${process.version} openssl ${process.versions.openssl}`));
}
