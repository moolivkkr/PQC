#!/bin/bash
# Starts the OpenSSL 3.5 test servers used by run-cases.sh (container node2-ossl on network node2net).
#   4431 PQ-only  4432 classical-only  4433 PQ-only + client cert required  4434 classical + client cert required
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
V="$(cd "$(dirname "$0")" && pwd)"
docker network inspect node2net >/dev/null 2>&1 || docker network create --label run=pqc-lang2-node node2net >/dev/null
docker rm -f node2-ossl >/dev/null 2>&1
docker run -d --label run=pqc-lang2-node --name node2-ossl --network node2net --network-alias node2ossl -v "$V":/w:ro \
  --entrypoint bash pqc-deep-node/ossl -c '
cd /w/certs
openssl s_server -quiet -accept 4431 -cert rsa.pem -key rsa.key -groups X25519MLKEM768 -tls1_3 -www > /tmp/4431.log 2>&1 &
openssl s_server -quiet -accept 4432 -cert rsa.pem -key rsa.key -groups X25519 -www > /tmp/4432.log 2>&1 &
openssl s_server -quiet -accept 4433 -cert rsa.pem -key rsa.key -groups X25519MLKEM768 -tls1_3 -Verify 1 -verify_return_error -CAfile ca.pem -www > /tmp/4433.log 2>&1 &
openssl s_server -quiet -accept 4434 -cert rsa.pem -key rsa.key -groups X25519 -Verify 1 -verify_return_error -CAfile ca.pem -www > /tmp/4434.log 2>&1 &
sleep infinity' >/dev/null
sleep 2
docker exec node2-ossl sh -c 'for p in 4431 4432; do echo | openssl s_client -connect node2ossl:$p -CAfile /w/certs/ca.pem -verify_hostname node2ossl -brief 2>&1 | grep -E "group|Temp Key|Verification"; done'
