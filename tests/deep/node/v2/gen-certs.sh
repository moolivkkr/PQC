#!/bin/bash
# Runs inside the OpenSSL 3.5 container (pqc-deep-node/ossl) with /w = this v2 dir.
# Private CA + RSA and EC server certs (several SANs for SNI), an encrypted key, PFX files and a client cert.
set -euo pipefail
cd /w; rm -rf certs; mkdir certs; cd certs
openssl req -x509 -newkey rsa:3072 -nodes -keyout ca.key -out ca.pem -days 30 -subj "/CN=Test Private Root CA" \
  -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign 2>/dev/null
sign() { # name keyfile san eku
  openssl req -new -key "$2" -out "$1.csr" -subj "/CN=$1" 2>/dev/null
  printf 'subjectAltName=%s\nextendedKeyUsage=%s\n' "$3" "$4" > "$1.ext"
  openssl x509 -req -in "$1.csr" -CA ca.pem -CAkey ca.key -CAcreateserial -days 30 -out "$1.pem" -extfile "$1.ext" 2>/dev/null
}
openssl genrsa -out rsa.key 2048 2>/dev/null;                      sign rsa rsa.key "DNS:node2srv,DNS:node2ossl,DNS:rsa.test,DNS:a.test" serverAuth
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out ec.key; sign ec ec.key "DNS:node2srv,DNS:ec.test,DNS:b.test" serverAuth
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 -out ec384.key; sign ec384 ec384.key "DNS:c.test" serverAuth
# Encrypted key (PKCS#8, AES-256) and a traditional encrypted PEM (BEGIN RSA PRIVATE KEY + DEK-Info)
openssl pkcs8 -topk8 -in ec.key -out ec-enc.key -v2 aes-256-cbc -passout pass:s3cret
openssl rsa -in rsa.key -aes256 -traditional -out rsa-enc-trad.key -passout pass:s3cret 2>/dev/null
# PFX: OpenSSL 3 default (AES-256/PBKDF2) and legacy (RC2-40/3DES, as old Windows exports)
openssl pkcs12 -export -inkey rsa.key -in rsa.pem -certfile ca.pem -out rsa.pfx -passout pass:s3cret
openssl pkcs12 -export -inkey ec.key -in ec.pem -certfile ca.pem -out ec.pfx -passout pass:s3cret
openssl pkcs12 -export -legacy -inkey rsa.key -in rsa.pem -certfile ca.pem -out rsa-legacy.pfx -passout pass:s3cret
# Client cert for mutual TLS (EC) and an RSA one
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out client.key; sign client client.key "DNS:client.test" clientAuth
openssl genrsa -out client-rsa.key 2048 2>/dev/null; sign client-rsa client-rsa.key "DNS:client-rsa.test" clientAuth
openssl pkcs12 -export -inkey client.key -in client.pem -out client.pfx -passout pass:s3cret
# A CA bundle file = public roots + private CA (what SSL_CERT_FILE would point at)
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout other-ca.key -out other-ca.pem -days 30 -subj "/CN=Unrelated Root" 2>/dev/null; cat other-ca.pem ca.pem > bundle-with-private.pem
chmod 644 *; ls
