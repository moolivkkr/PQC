'use strict';
const fs = require('node:fs');
const https = require('node:https');
const express = require('express');

const app = express();
app.get('/healthz', (req, res) => res.send('ok'));
app.get('/', (req, res) => res.send(`tls ${req.socket.getProtocol()}`));

const opts = {
  key: fs.readFileSync(process.env.TLS_KEY || '/etc/app/tls/server.key'),
  cert: fs.readFileSync(process.env.TLS_CERT || '/etc/app/tls/server.pem'),
  minVersion: process.env.TLS_MIN_VERSION || 'TLSv1.2', // 'TLSv1.3' to refuse TLS 1.2 clients
};
// Optional explicit list. Must start with X25519MLKEM768, or PQ clients are silently downgraded.
if (process.env.TLS_ECDH_CURVE) opts.ecdhCurve = process.env.TLS_ECDH_CURVE;

https.createServer(opts, app).listen(Number(process.env.PORT || 8443), () =>
  console.log(JSON.stringify({ msg: 'listening', node: process.version, openssl: process.versions.openssl,
    ecdhCurve: opts.ecdhCurve || 'default', minVersion: opts.minVersion })));
