#!/bin/sh
# pq-harness.sh - throw-away CA plus PQ-only, classical-only and mTLS test servers (OpenSSL 3.5).
# Run in python:3.13-slim-trixie or debian:trixie-slim with /certs mounted, network alias "pqsrv":
#   docker run -d --name pqsrv --network ci -v $PWD/certs:/certs -v $PWD/pq-harness.sh:/h.sh debian:trixie-slim sh /h.sh
#   8443 PQ-only (X25519MLKEM768, TLS 1.3)       8444 classical-only (X25519)
#   8451 PQ-only, client cert required          8452 classical-only, client cert required
# Clients trust /certs/ca.pem; the mTLS client cert is /certs/client.pem + /certs/client.key.
set -e
command -v openssl >/dev/null || { apt-get update -qq && apt-get install -y -qq openssl >/dev/null; }
C=/certs; mkdir -p $C; cd $C
if [ ! -f ca.pem ]; then
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 7 -subj /CN=pq-harness-ca \
    -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign -keyout ca.key -out ca.pem 2>/dev/null
  for n in server client; do
    eku=serverAuth; [ $n = client ] && eku=clientAuth
    openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj /CN=$n -keyout $n.key -out $n.csr 2>/dev/null
    printf 'subjectAltName=DNS:pqsrv,DNS:localhost\nextendedKeyUsage=%s\n' $eku > $n.ext
    openssl x509 -req -in $n.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 7 -extfile $n.ext -out $n.pem 2>/dev/null
  done
  rm -f *.csr *.ext; chmod 644 *.pem client.key
fi
S="openssl s_server -cert $C/server.pem -key $C/server.key -www -brief"
$S -accept 8443 -groups X25519MLKEM768 -tls1_3 &
$S -accept 8444 -groups X25519 &
$S -accept 8451 -groups X25519MLKEM768 -tls1_3 -Verify 1 -CAfile $C/ca.pem &
$S -accept 8452 -groups X25519 -Verify 1 -CAfile $C/ca.pem &
echo "pq-harness up: $(openssl version)"
wait
