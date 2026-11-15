#!/bin/bash
# Test PKI for the e2e suite (throwaway; never commit the output). Written to e2e/.work/certs/.
#   ca.crt               test root CA (the "custom CA" every client must trust explicitly)
#   server-rsa.*         observer cert, RSA 2048, SAN pq-observer
#   server-ec.*          observer cert, ECDSA P-256, SAN pq-observer
#   client.crt/.key      client cert (CN=pqc-client) for mTLS
#   client.p12           client cert + key, PKCS#12 (AES-256, password changeit) - Java/.NET keystore case
#   truststore.p12       CA only, PKCS#12 with Java trust attribute (password changeit) - Java truststore case
set -euo pipefail
E2E="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$E2E/.work/certs"; mkdir -p "$OUT"
[ -f "$OUT/ca.crt" ] && { echo "certs exist: $OUT"; exit 0; }
docker run --rm -v "$OUT":/o -w /o public.ecr.aws/amazonlinux/amazonlinux:2023.12.20261109.0 bash -euc '
dnf -q -y install openssl >/dev/null
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 825 -subj "/CN=pqc-e2e test CA" \
  -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign
mk() { # name keyalg
  openssl req -newkey $2 -nodes -keyout $1.key -out $1.csr -subj "/CN=$3"
  openssl x509 -req -in $1.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out $1.crt -days 825 -extfile <(printf "%s\n" "$4")
  rm -f $1.csr
}
mk server-rsa rsa:2048 pq-observer "subjectAltName=DNS:pq-observer,DNS:localhost,IP:10.250.0.20
extendedKeyUsage=serverAuth"
mk server-ec "ec -pkeyopt ec_paramgen_curve:P-256" pq-observer "subjectAltName=DNS:pq-observer,DNS:localhost,IP:10.250.0.20
extendedKeyUsage=serverAuth"
mk client rsa:2048 pqc-client "extendedKeyUsage=clientAuth"
openssl pkcs12 -export -in client.crt -inkey client.key -certfile ca.crt -name pqc-client -out client.p12 -passout pass:changeit
openssl pkcs12 -export -nokeys -in ca.crt -jdktrust anyExtendedKeyUsage -name pqc-ca -out truststore.p12 -passout pass:changeit
chmod 644 *
'
ls -1 "$OUT"
