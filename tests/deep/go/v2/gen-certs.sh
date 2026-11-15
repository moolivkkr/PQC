#!/bin/sh
# Test PKI for the Go cases: private CA, RSA and EC server certs, SNI certs, client certs,
# encrypted keys (legacy PEM and PKCS#8) and PKCS#12 files (modern and legacy). Needs OpenSSL 3.
set -e
mkdir -p /certs/cadir; cd /certs
O=openssl
$O req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout ca.key -out ca.pem -days 3 \
  -subj "/CN=Test Private CA" -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign
leaf() { # name alg san eku
  if [ "$2" = rsa ]; then $O req -newkey rsa:2048 -nodes -keyout $1.key -out $1.csr -subj "/CN=$1"
  else $O req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout $1.key -out $1.csr -subj "/CN=$1"; fi
  printf 'subjectAltName=%s\nextendedKeyUsage=%s\n' "$3" "$4" > $1.ext
  $O x509 -req -in $1.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 2 -extfile $1.ext -out $1.pem
}
leaf srv-rsa rsa DNS:localhost,DNS:pqsrv serverAuth
leaf srv-ec ec DNS:localhost,DNS:pqsrv serverAuth
leaf a.test ec DNS:a.test serverAuth
leaf b.test rsa DNS:b.test serverAuth
leaf cli-rsa rsa DNS:cli-rsa clientAuth
leaf cli-ec ec DNS:cli-ec clientAuth
# Encrypted keys: legacy "Proc-Type: 4,ENCRYPTED" PEM, and PKCS#8 "BEGIN ENCRYPTED PRIVATE KEY"
$O rsa -in srv-rsa.key -aes256 -traditional -passout pass:changeit -out srv-rsa-legacyenc.key
$O pkcs8 -topk8 -in srv-ec.key -v2 aes-256-cbc -passout pass:changeit -out srv-ec-pkcs8enc.key
# PKCS#12: OpenSSL 3 default (AES-256-CBC, PBKDF2, SHA-256 MAC) with chain; and legacy 3DES/SHA-1
$O pkcs12 -export -in srv-ec.pem -inkey srv-ec.key -certfile ca.pem -passout pass:changeit -out srv-ec-modern.p12
$O pkcs12 -export -in srv-rsa.pem -inkey srv-rsa.key -passout pass:changeit \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -out srv-rsa-legacy.p12
cp ca.pem cadir/private-ca.pem
