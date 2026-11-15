const agent = new https.Agent({ ecdhCurve: 'X25519MLKEM768:X25519:P-256:P-384' });
const b = new https.Agent({ ecdhCurve: 'auto', minVersion: 'TLSv1.2', maxVersion: 'TLSv1.3' });
const legacy = { ecdhCurve: 'X25519:P-256' }; // pq-tls-ok: talks to an appliance without ML-KEM, ticket SEC-123
