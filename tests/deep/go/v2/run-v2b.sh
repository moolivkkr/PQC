#!/bin/sh
# Follow-up probes (inside debian:trixie-slim): TLS 1.2 server cases with P-256 offered (an ECDSA P-256
# cert on TLS 1.2 needs P-256 in the client's groups), and server-side GODEBUG on a go-1.22 module.
set -u
command -v openssl >/dev/null || { apt-get update -qq >/dev/null && apt-get install -y -qq --no-install-recommends openssl >/dev/null 2>&1; }
sh /src/gen-certs.sh >/tmp/gen.log 2>&1 || { echo GEN-FAIL; exit 1; }
cd /certs
sc() {
  label=$1; port=$2; groups=$3; shift 3
  out=$(perl -e 'alarm shift; exec @ARGV' 8 openssl s_client -brief -connect localhost:$port -CAfile ca.pem -verify_return_error -groups $groups "$@" 2>&1 </dev/null)
  g=$(echo "$out" | grep -m1 -E 'Negotiated TLS1.3 group|Temp Key' | sed 's/^ *//')
  pv=$(echo "$out" | grep -m1 -E '^Protocol version' | sed 's/Protocol version: //')
  if [ -n "$pv" ] && ! echo "$out" | grep -qiE 'alert|handshake failure|errno|error:'; then r=OK; else r=FAIL; fi
  echo "  probe $label | -groups $groups $* | $r | $pv | $g"
}
for b in /b/cases-1.26-mod1.26 /b/cases-1.24-mod1.22; do
  for dbg in "" "tlsmlkem=1"; do
    echo "== $(basename $b) server GODEBUG=$dbg"
    GODEBUG=$dbg TLS_KEY_PASS=changeit TLS_CERT_PEM="$(cat srv-rsa.pem)" TLS_KEY_PEM="$(cat srv-rsa.key)" $b server >/tmp/srv.log 2>&1 &
    pid=$!; sleep 1
    sc "C ec default" 9444 X25519MLKEM768 -tls1_3
    sc "C ec default" 9444 X25519
    sc "F server MaxVersion 1.2" 9452 X25519MLKEM768:X25519:P-256
    sc "F server MaxVersion 1.2" 9452 X25519:P-256
    sc "F server CipherSuites" 9453 X25519:P-256 -tls1_2
    kill $pid; sleep 0.3; grep -v servers-up /tmp/srv.log | sed 's/^/  /'
  done
done
