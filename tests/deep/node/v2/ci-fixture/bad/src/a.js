const agent = new https.Agent({ ecdhCurve: 'X25519:P-256' });
tls.DEFAULT_ECDH_CURVE = "prime256v1";
https.createServer({ key, cert, maxVersion: 'TLSv1.2' });
tls.connect({ secureProtocol: 'TLSv1_2_method' });
