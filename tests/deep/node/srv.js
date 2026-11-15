// Server-side probe: one Node process, several TLS servers with different settings. Clients = openssl s_client.
// Ports: 9001 https default | 9002 https ecdhCurve X25519:P-256 (pitfall) | 9003 https ecdhCurve PQ-first
//        9004 http2.createSecureServer default | 9005 express on https | 9006 fastify https | 9007 tls.createServer minVersion TLSv1.3
//        9008 grpc-js server default
const fs = require('fs'); const tls = require('tls'); const https = require('https'); const http2 = require('http2');
const key = fs.readFileSync('/w/certs/server.key'), cert = fs.readFileSync('/w/certs/server.pem');
const hello = (req, res) => res.end('ok\n');
const tag = (p, what) => console.log(`listening ${p} ${what}`);
https.createServer({ key, cert }, hello).listen(9001, () => tag(9001, 'https default'));
https.createServer({ key, cert, ecdhCurve: 'X25519:P-256' }, hello).listen(9002, () => tag(9002, 'https ecdhCurve X25519:P-256'));
try { https.createServer({ key, cert, ecdhCurve: 'X25519MLKEM768:X25519:P-256:P-384' }, hello).listen(9003, () => tag(9003, 'https ecdhCurve PQ-first')); } catch (e) { console.log('9003 throws: ' + e.code + ' ' + e.message); }
http2.createSecureServer({ key, cert, allowHTTP1: true }, hello).listen(9004, () => tag(9004, 'http2 secure default'));
let express; try { express = require('/w/app/node_modules/express'); } catch {}
if (express) { const app = express(); app.get('/', (q, r) => r.send('ok')); https.createServer({ key, cert }, app).listen(9005, () => tag(9005, 'express on https')); }
let fastify; try { fastify = require('/w/app/node_modules/fastify'); } catch {}
if (fastify) { const f = fastify({ https: { key, cert } }); f.get('/', async () => 'ok'); f.listen({ port: 9006, host: '0.0.0.0' }).then(() => tag(9006, 'fastify https')).catch((e) => console.log('fastify', e.message)); }
tls.createServer({ key, cert, minVersion: 'TLSv1.3' }, (s) => s.end('ok\n')).listen(9007, () => tag(9007, 'tls.createServer minVersion TLSv1.3'));
try {
  const grpc = require('/w/app/node_modules/@grpc/grpc-js'); const id = (x) => x; const s = new grpc.Server();
  s.addService({ Ping: { path: '/t.T/Ping', requestStream: false, responseStream: false, requestSerialize: id, requestDeserialize: id, responseSerialize: id, responseDeserialize: id } }, { Ping: (c, cb) => cb(null, Buffer.from('pong')) });
  s.bindAsync('0.0.0.0:9008', grpc.ServerCredentials.createSsl(null, [{ private_key: key, cert_chain: cert }], false), (e) => e ? console.log('grpc', e.message) : tag(9008, 'grpc-js default'));
} catch (e) { console.log('grpc load', e.message); }
console.log(`node ${process.version} openssl ${process.versions.openssl}`);
