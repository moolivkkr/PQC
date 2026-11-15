#!/bin/sh
# Case I (inside debian:trixie-slim): SPKI pinning client and crypto.Signer-backed server keys.
set -u
command -v openssl >/dev/null || { apt-get update -qq >/dev/null && apt-get install -y -qq --no-install-recommends openssl >/dev/null 2>&1; }
sh /src/gen-certs.sh >/tmp/gen.log 2>&1 || { echo GEN-FAIL; exit 1; }
cd /certs
srv() { port=$1; shift; openssl s_server -quiet -accept $port -cert srv-ec.pem -key srv-ec.key -www "$@" >/tmp/s$port.log 2>&1 & }
srv 8443 -tls1_3 -groups X25519MLKEM768
srv 8444 -groups X25519
sleep 1
for b in /b/cases-1.24-mod1.24 /b/cases-1.26-mod1.26; do
  echo "== $(basename $b) client-i"; $b client-i
  echo "== $(basename $b) server-i"
  $b server-i >/tmp/srv.log 2>&1 & pid=$!; sleep 1
  for port in 9456 9457; do for g in "X25519MLKEM768 -tls1_3" "X25519"; do
    out=$(perl -e 'alarm shift; exec @ARGV' 8 openssl s_client -brief -connect localhost:$port -CAfile ca.pem -verify_return_error -groups $g 2>&1 </dev/null)
    echo "  probe :$port -groups $g | $(echo "$out" | grep -E '^Protocol version|Negotiated TLS1.3 group|Temp Key|Verification|alert' | tr '\n' ' ')"
  done; done
  kill $pid; sleep 0.3; grep -v servers-up /tmp/srv.log | sed 's/^/  /'
done
