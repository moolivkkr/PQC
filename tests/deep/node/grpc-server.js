// Minimal grpc-js TLS server (no .proto). Port from argv. Group restriction comes from OPENSSL_CONF (nodejs_conf).
const fs = require('fs');
const grpc = require('/w/app/node_modules/@grpc/grpc-js');
const port = process.argv[2];
const id = (x) => x;
const s = new grpc.Server();
s.addService({ Ping: { path: '/t.T/Ping', requestStream: false, responseStream: false,
  requestSerialize: id, requestDeserialize: id, responseSerialize: id, responseDeserialize: id } },
  { Ping: (call, cb) => cb(null, Buffer.from('pong')) });
const creds = grpc.ServerCredentials.createSsl(null, [{ private_key: fs.readFileSync('/w/certs/server.key'), cert_chain: fs.readFileSync('/w/certs/server.pem') }], false);
s.bindAsync(`0.0.0.0:${port}`, creds, (e) => { if (e) throw e; console.log(`grpc ${port} node ${process.version} OPENSSL_CONF=${process.env.OPENSSL_CONF}`); });
