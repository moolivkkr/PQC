#!/bin/sh
# PQ-only and classical-only TLS test servers (OpenSSL 3.5 s_server), one port pair per client family
# so the server log for each port says which handshakes completed and with which group.
#   even port = PQ-only (X25519MLKEM768, TLS 1.3), odd port = classical-only (X25519, TLS 1.2/1.3)
set -e
C=/w/certs; O=/w/out/srv; mkdir -p $C $O
if [ ! -f $C/leaf.pem ]; then
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 -subj /CN=pq-test-ca -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign \
    -keyout $C/ca.key -out $C/ca.pem 2>/dev/null
  openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj /CN=pqsrv \
    -keyout $C/leaf.key -out $C/leaf.csr 2>/dev/null
  printf 'subjectAltName=DNS:pqsrv,DNS:pgsrv,DNS:pyc,DNS:localhost\nbasicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid\nextendedKeyUsage=serverAuth\n' > $C/ext.cnf
  openssl x509 -req -in $C/leaf.csr -CA $C/ca.pem -CAkey $C/ca.key -CAcreateserial -days 30 \
    -extfile $C/ext.cnf -out $C/leaf.pem 2>/dev/null
  chmod 644 $C/*.key
fi
S="stdbuf -oL -eL openssl s_server -cert $C/leaf.pem -key $C/leaf.key -www -brief -alpn h2,http/1.1"
$S -accept 8443 -groups X25519MLKEM768 -tls1_3 > $O/http-pq.log 2>&1 &
$S -accept 8444 -groups X25519 > $O/http-classical.log 2>&1 &
# non-HTTP families: no -www, so -brief logs every handshake (stdin held open by sleep)
B="stdbuf -oL -eL openssl s_server -cert $C/leaf.pem -key $C/leaf.key -brief -alpn h2,http/1.1"
for pair in "8445 8446 grpc" "8447 8448 kafka" "8449 8450 redis"; do
  set -- $pair
  sleep 1000000 | $B -accept $1 -groups X25519MLKEM768 -tls1_3 > $O/$3-pq.log 2>&1 &
  sleep 1000000 | $B -accept $2 -groups X25519 > $O/$3-classical.log 2>&1 &
done
echo "servers up: $(openssl version)"
wait
