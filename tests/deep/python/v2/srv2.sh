#!/bin/sh
# OpenSSL 3.5 test servers for the Python v2 cases (run in python:3.13-slim-trixie, which ships openssl 3.5).
#   8443 PQ-only (X25519MLKEM768, TLS 1.3)          8444 classical-only (X25519)
#   8451 PQ-only + client cert required (mTLS)     8452 classical-only + client cert required
#   8453 PQ-only + client cert required, no -www (gRPC client; handshake logged)
set -e
sh /w2/mkcerts.sh
C=/w2/certs; O=/w2/out/srv; mkdir -p $O
S="stdbuf -oL -eL openssl s_server -cert $C/ec.pem -key $C/ec.key -www -brief -alpn h2,http/1.1"
$S -accept 8443 -groups X25519MLKEM768 -tls1_3 > $O/pq.log 2>&1 &
$S -accept 8444 -groups X25519 > $O/classical.log 2>&1 &
$S -accept 8451 -groups X25519MLKEM768 -tls1_3 -Verify 1 -CAfile $C/ca.pem > $O/mtls-pq.log 2>&1 &
$S -accept 8452 -groups X25519 -Verify 1 -CAfile $C/ca.pem > $O/mtls-classical.log 2>&1 &
sleep 1000000 | stdbuf -oL -eL openssl s_server -cert $C/ec.pem -key $C/ec.key -brief -alpn h2 -accept 8453 \
  -groups X25519MLKEM768 -tls1_3 -Verify 1 -CAfile $C/ca.pem > $O/mtls-grpc-pq.log 2>&1 &
echo "servers up: $(openssl version)"
wait
