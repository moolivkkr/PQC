#!/bin/sh
# pq-servers.sh: start the four OpenSSL 3.5 test servers (run in debian:trixie-slim after gen-certs.sh).
#   8443 PQ-only           8444 classical-only (TLS 1.2 and 1.3)
#   8445 PQ-only + mTLS    8446 classical-only + mTLS   (client cert must chain to ca.pem)
set -e
cd /certs
command -v openssl >/dev/null || { apt-get update -qq && apt-get install -y -qq --no-install-recommends openssl; }
srv() { port=$1; shift; openssl s_server -quiet -accept "$port" -cert srv-ec.pem -key srv-ec.key -www "$@" >/tmp/s"$port".log 2>&1 & }
srv 8443 -tls1_3 -groups X25519MLKEM768
srv 8444 -groups X25519:P-256
srv 8445 -tls1_3 -groups X25519MLKEM768 -Verify 1 -CAfile ca.pem
srv 8446 -groups X25519:P-256 -Verify 1 -CAfile ca.pem
sleep 1; echo "servers up: 8443 8444 8445 8446 (logs in /tmp/s<port>.log)"
