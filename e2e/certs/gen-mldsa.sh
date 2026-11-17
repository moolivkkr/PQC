#!/bin/bash
# ML-DSA test PKI for the e2e suite (throwaway; never commit the output). Written to e2e/.work/certs/ next to gen.sh's files.
#   ca-mldsa.crt         ML-DSA-65 root CA
#   server-mldsa.*       ML-DSA-44 server leaf, SAN pq-observer (served by pq-mldsa on :8448-8450)
#   client-mldsa.*       ML-DSA-44 client leaf (CN=pqc-client-mldsa) for ML-DSA mutual TLS (user / workload identity)
#   client-mldsa.p12     client-mldsa cert + key, PKCS#12 (password changeit) - Java/.NET keystore case
#   ca-both.crt          ca.crt + ca-mldsa.crt: the trust bundle every client uses for the ML-DSA targets
#   truststore-both.p12  both roots, PKCS#12 with Java trust attribute (password changeit)
# Needs OpenSSL 3.5+ (Debian 13): ML-DSA keys and signatures.
set -euo pipefail
E2E="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$E2E/.work/certs"
[ -f "$OUT/ca.crt" ] || { echo "run gen.sh first" >&2; exit 1; }
[ -f "$OUT/ca-mldsa.crt" ] && { echo "ML-DSA certs exist: $OUT"; exit 0; }
docker run --rm --label project=pqc-e2e -v "$OUT":/o -w /o \
  debian@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2 bash -euc '
apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends openssl >/dev/null
openssl version
openssl req -x509 -newkey ML-DSA-65 -nodes -keyout ca-mldsa.key -out ca-mldsa.crt -days 825 -subj "/CN=pqc-e2e ML-DSA test CA" \
  -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign
leaf() { # name cn ext
  openssl req -newkey ML-DSA-44 -nodes -keyout $1.key -out $1.csr -subj "/CN=$2"
  openssl x509 -req -in $1.csr -CA ca-mldsa.crt -CAkey ca-mldsa.key -CAcreateserial -out $1.crt -days 825 -extfile <(printf "%s\n" "$3")
  rm -f $1.csr
}
leaf server-mldsa pq-observer "subjectAltName=DNS:pq-observer,DNS:localhost,IP:10.250.0.20
keyUsage=critical,digitalSignature
extendedKeyUsage=serverAuth"
leaf client-mldsa pqc-client-mldsa "keyUsage=critical,digitalSignature
extendedKeyUsage=clientAuth"
cat ca.crt ca-mldsa.crt > ca-both.crt
openssl pkcs12 -export -in client-mldsa.crt -inkey client-mldsa.key -certfile ca-mldsa.crt -name pqc-client-mldsa \
  -out client-mldsa.p12 -passout pass:changeit
openssl pkcs12 -export -nokeys -in ca-both.crt -jdktrust anyExtendedKeyUsage -name pqc-ca -out truststore-both.p12 -passout pass:changeit
openssl verify -CAfile ca-mldsa.crt server-mldsa.crt client-mldsa.crt
chmod 644 *
'
ls -1 "$OUT" | grep -E "mldsa|both"
