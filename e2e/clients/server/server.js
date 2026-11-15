// Load balancer target probe - Node.js (https.createServer; the stack Express/Fastify use for TLS).
'use strict';
const https = require('https'), http = require('http'), fs = require('fs'), path = require('path');
const caseId = process.env.PQC_CASE_ID || 'adhoc', port = +(process.env.PQC_SERVER_PORT || 9443);
const obs = process.env.PQC_OBSERVER || 'pq-observer';
const targets = (process.env.PQC_TARGETS || 'alb-pq,alb-classic').split(',').filter(Boolean);
const srv = https.createServer({ cert: fs.readFileSync(path.join(__dirname, 'server-rsa.crt')),
  key: fs.readFileSync(path.join(__dirname, 'server-rsa.key')) },
  (req, res) => { res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({ ok: true, server: 'node' })); });
const get = (url) => new Promise((ok, ko) => http.get(url, { timeout: 30000 }, (r) => {
  let b = ''; r.on('data', (d) => b += d); r.on('end', () => { try { ok(JSON.parse(b)); } catch (e) { ko(e); } });
}).on('error', ko));
srv.listen(port, '0.0.0.0', async () => {
  const out = { case_id: caseId, lang: 'node', role: 'server', runtime: process.version, openssl: process.versions.openssl,
    compute: process.env.PQC_COMPUTE || 'unknown', mode: process.env.PQC_MODE || 'baseline', results: {} };
  for (const t of targets) {
    let res;
    try { res = await get(`http://${obs}:8080/dialback?id=${caseId}&port=${port}&policy=${t}`); }
    catch (e) { res = { ok: false, error: String(e) }; }
    res.pq_status = !res.ok ? 'failed' : (res.pq ? 'pq' : 'classical');
    out.results[t] = res;
    console.log(JSON.stringify({ event: 'tls_handshake', role: 'server', case_id: caseId, lang: 'node', runtime: out.runtime,
      compute: out.compute, mode: out.mode, target: t, ...res }));
  }
  console.log('PQC_RESULT ' + JSON.stringify(out));
  srv.close(); process.exit(0);
});
