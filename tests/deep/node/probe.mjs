// Client-library probe: each library connects to a PQ-only endpoint and a classical-only endpoint.
// PASS criterion for PQ: the TLS handshake completes against a server that accepts ONLY X25519MLKEM768.
// Usage: node probe.mjs [libs...]   (default: all). CA via NODE_EXTRA_CA_CERTS or /w/certs/ca.pem.
import { createRequire } from 'node:module';
import fs from 'node:fs';
const require = createRequire('/w/app/package.json');
const ca = fs.readFileSync('/w/certs/ca.pem');
const tls = require('node:tls');
const https = require('node:https');
if (process.env.SET_DEFAULT_ECDH_CURVE) tls.DEFAULT_ECDH_CURVE = process.env.SET_DEFAULT_ECDH_CURVE;
const H = process.env.PQHOST || 'pqsrv';
const EP = {
  http: { pq: `https://${H}:8443/`, cl: `https://${H}:8444/` },
  tcp: { pq: [H, 8443], cl: [H, 8444] },
  grpc: { pq: 'grpcsrv:50051', cl: 'grpcsrv:50052' },
  pg: { pq: 5432, cl: 5433 }, redis: { pq: 6380, cl: 6381 }, mysql: { pq: 3306, cl: 3307 },
};
const tlsErr = (e) => {
  const s = `${e?.code || ''} ${e?.message || e} ${e?.cause?.code || ''} ${e?.cause?.message || ''}`;
  return /SSL|handshake|alert|EPROTO|ECONNRESET|socket hang up|other side closed|ERR_TLS/i.test(s) ? s.replace(/\s+/g, ' ').trim().slice(0, 90) : null;
};
const withTimeout = (p, ms = 8000) => Promise.race([p, new Promise((_, r) => setTimeout(() => r(new Error('TIMEOUT')), ms))]);

const libs = {
  async 'tls.connect'(side) {
    const [host, port] = EP.tcp[side];
    return new Promise((ok, no) => {
      const s = tls.connect({ host, port, ca, servername: host }, () => {
        const k = s.getEphemeralKeyInfo(); s.destroy();
        ok(`${s.getProtocol()} ephemeralKeyInfo=${JSON.stringify(k)}`);
      });
      s.on('error', no);
    });
  },
  async 'tls.connect ecdhCurve=X25519:P-256'(side) {
    const [host, port] = EP.tcp[side];
    return new Promise((ok, no) => {
      const s = tls.connect({ host, port, ca, servername: host, ecdhCurve: 'X25519:P-256' }, () => { s.destroy(); ok(s.getProtocol()); });
      s.on('error', no);
    });
  },
  async 'tls.connect ecdhCurve=X25519MLKEM768:X25519:P-256'(side) {
    const [host, port] = EP.tcp[side];
    return new Promise((ok, no) => {
      const s = tls.connect({ host, port, ca, servername: host, ecdhCurve: 'X25519MLKEM768:X25519:P-256' }, () => { s.destroy(); ok(s.getProtocol()); });
      s.on('error', no);
    });
  },
  async 'https.get'(side) {
    return new Promise((ok, no) => {
      https.get(EP.http[side], { ca }, (r) => { let b = ''; r.on('data', (d) => (b += d)); r.on('end', () => ok(`HTTP ${r.statusCode} ${(b.match(/Negotiated TLS1.3 group: \S+/) || [''])[0]}`)); }).on('error', no);
    });
  },
  async 'https.Agent ecdhCurve=X25519:P-256'(side) {
    const agent = new https.Agent({ ca, ecdhCurve: 'X25519:P-256' });
    return new Promise((ok, no) => { https.get(EP.http[side], { agent }, (r) => { r.resume(); ok(`HTTP ${r.statusCode}`); }).on('error', no); });
  },
  async 'fetch (global)'(side) {
    const r = await fetch(EP.http[side]); await r.text(); return `HTTP ${r.status}`; // CA via NODE_EXTRA_CA_CERTS
  },
  async 'undici Agent connect.ecdhCurve PQ-first'(side) {
    const { Agent, request } = require('undici');
    const dispatcher = new Agent({ connect: { ca, ecdhCurve: 'X25519MLKEM768:X25519:P-256' } });
    const r = await request(EP.http[side], { dispatcher }); await r.body.text(); return `HTTP ${r.statusCode}`;
  },
  async 'undici Agent connect.ecdhCurve=X25519'(side) {
    const { Agent, request } = require('undici');
    const dispatcher = new Agent({ connect: { ca, ecdhCurve: 'X25519' } });
    const r = await request(EP.http[side], { dispatcher }); await r.body.text(); return `HTTP ${r.statusCode}`;
  },
  async axios(side) {
    const axios = require('axios');
    const r = await axios.get(EP.http[side], { httpsAgent: new https.Agent({ ca }) }); return `HTTP ${r.status}`;
  },
  async got(side) {
    const { default: got } = await import(require.resolve('got'));
    const r = await got(EP.http[side], { https: { certificateAuthority: ca }, retry: { limit: 0 } }); return `HTTP ${r.statusCode}`;
  },
  async 'node-fetch'(side) {
    const { default: nf } = await import(require.resolve('node-fetch'));
    const r = await nf(EP.http[side], { agent: new https.Agent({ ca }) }); await r.text(); return `HTTP ${r.status}`;
  },
  async 'aws-sdk v3 S3 (NodeHttpHandler)'(side) {
    const { S3Client, ListBucketsCommand } = require('@aws-sdk/client-s3');
    const { NodeHttpHandler } = require('@smithy/node-http-handler');
    const c = new S3Client({ region: 'us-east-1', endpoint: EP.http[side].slice(0, -1), forcePathStyle: true, maxAttempts: 1,
      credentials: { accessKeyId: 'AKIDEXAMPLE', secretAccessKey: 'x' },
      requestHandler: new NodeHttpHandler({ httpsAgent: new https.Agent({ ca, keepAlive: true }) }) });
    try { await c.send(new ListBucketsCommand({})); return 'response'; }
    catch (e) { if (tlsErr(e)) throw e; return `TLS up; app-layer error as expected (${(e.name || '').slice(0, 30)})`; }
  },
  async 'grpc-js'(side) {
    const grpc = require('@grpc/grpc-js');
    const Client = grpc.makeGenericClientConstructor({ Ping: { path: '/t.T/Ping', requestStream: false, responseStream: false,
      requestSerialize: (x) => x, requestDeserialize: (x) => x, responseSerialize: (x) => x, responseDeserialize: (x) => x } }, 'T');
    const c = new Client(EP.grpc[side], grpc.credentials.createSsl(ca));
    return new Promise((ok, no) => c.Ping(Buffer.from('hi'), { deadline: Date.now() + 5000 }, (e, r) => { c.close(); e ? no(e) : ok(`reply=${r}`); }));
  },
  async pg(side) {
    const { Client } = require('pg');
    const c = new Client({ host: 'dbsrv', port: EP.pg[side], user: 'postgres', database: 'postgres', ssl: { ca, servername: 'dbsrv' }, connectionTimeoutMillis: 5000 });
    await c.connect(); const r = await c.query('select version, ssl from pg_stat_ssl where pid = pg_backend_pid()'); await c.end();
    return JSON.stringify(r.rows[0]);
  },
  async mysql2(side) {
    const mysql = require('mysql2/promise');
    const c = await mysql.createConnection({ host: 'dbsrv', port: EP.mysql[side], user: 't', password: 't', ssl: { ca }, connectTimeout: 5000 });
    const [rows] = await c.query("show status like 'Ssl_version'"); await c.end(); return JSON.stringify(rows[0]);
  },
  async ioredis(side) {
    const Redis = require('ioredis'); const Ctor = Redis.default || Redis;
    const c = new Ctor({ host: 'dbsrv', port: EP.redis[side], tls: { ca, servername: 'dbsrv' }, maxRetriesPerRequest: 0, retryStrategy: () => null, lazyConnect: true });
    try { await c.connect(); const r = await c.ping(); return r; } finally { c.disconnect(); }
  },
  async kafkajs(side) {
    // No Kafka broker here: the endpoint is a TLS server that does not speak Kafka. A completed handshake shows up
    // as a request/connection error AFTER TLS; a failed handshake shows up as an SSL alert.
    const { Kafka, logLevel } = require('kafkajs');
    const [host, port] = EP.tcp[side];
    const k = new Kafka({ brokers: [`${host}:${port}`], ssl: { ca }, connectionTimeout: 3000, requestTimeout: 3000, retry: { retries: 0 }, logLevel: logLevel.NOTHING });
    const a = k.admin();
    try { await a.connect(); await a.listTopics(); return 'response'; }
    catch (e) { if (tlsErr(e)) throw e; return `TLS up; app-layer error as expected (${(e.name || '').slice(0, 40)})`; }
    finally { await a.disconnect().catch(() => {}); }
  },
};

const want = process.argv.slice(2);
const label = process.env.LABEL || `node ${process.version}`;
console.log(`# ${label} node=${process.version} openssl=${process.versions.openssl} OPENSSL_CONF=${process.env.OPENSSL_CONF || '-'}`);
for (const [name, fn] of Object.entries(libs)) {
  if (want.length && !want.some((w) => name.startsWith(w))) continue;
  const res = [];
  for (const side of ['pq', 'cl']) {
    try { res.push(`${side}=OK ${await withTimeout(fn(side))}`); }
    catch (e) {
      const t = tlsErr(e);
      res.push(`${side}=${t ? 'FAIL ' + t : 'ERR ' + String(e?.code || '') + ' ' + String(e?.message || e).slice(0, 80)}`);
    }
  }
  console.log(`${name.padEnd(46)} | ${res[0]} | ${res[1]}`);
}
process.exit(0);
