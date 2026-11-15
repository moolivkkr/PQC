#!/bin/sh
# Runs inside debian:trixie-slim (OpenSSL 3.5.x), by digest. /b = Go binaries, /src = v2 dir.
# Everything talks over localhost inside this one container.
set -u
command -v openssl >/dev/null || { apt-get update -qq >/dev/null && apt-get install -y -qq --no-install-recommends openssl >/dev/null 2>&1; }
openssl version
sh /src/gen-certs.sh >/tmp/gen.log 2>&1 || { echo GEN-FAIL; cat /tmp/gen.log; exit 1; }
cd /certs
echo "== key files"; for f in srv-rsa-legacyenc.key srv-ec-pkcs8enc.key; do echo "$f: $(head -3 $f | tr '\n' ' ' | cut -c1-90)"; done
for f in srv-ec-modern.p12 srv-rsa-legacy.p12; do echo "$f: $(openssl pkcs12 -in $f -info -noout -passin pass:changeit 2>&1 | tr '\n' ' ' | cut -c1-200)"; done

srv() { port=$1; shift; openssl s_server -quiet -accept $port -cert srv-ec.pem -key srv-ec.key -www "$@" >/tmp/s$port.log 2>&1 & }
srv 8443 -tls1_3 -groups X25519MLKEM768
srv 8444 -groups X25519
srv 8445 -tls1_3 -groups X25519MLKEM768 -Verify 1 -CAfile ca.pem
srv 8446 -groups X25519 -Verify 1 -CAfile ca.pem
sleep 1

# s_client probe of a Go server: label port groups [extra s_client args]
sc() {
  label=$1; port=$2; groups=$3; shift 3
  out=$(perl -e 'alarm shift; exec @ARGV' 8 openssl s_client -brief -connect localhost:$port -CAfile ca.pem -verify_return_error -groups $groups "$@" 2>&1 </dev/null)
  g=$(echo "$out" | grep -m1 -E 'Negotiated TLS1.3 group|Server Temp Key' | sed 's/^ *//')
  pv=$(echo "$out" | grep -m1 -E '^Protocol version' | sed 's/Protocol version: //')
  pc=$(echo "$out" | grep -m1 -E '^Peer certificate' | sed 's/Peer certificate: //')
  pk=$(echo "$out" | grep -m1 -E 'Peer signature type|Signature type' | sed 's/^ *//')
  if [ -n "$pv" ] && ! echo "$out" | grep -qiE 'alert|handshake failure|errno|error:'; then r=OK; else r=FAIL; fi
  err=""; [ $r = FAIL ] && err=$(echo "$out" | grep -m1 -iE 'alert|error' | cut -c1-90)
  echo "  probe $label | -groups $groups $* | $r | $pv | $g | cert=$pc | $pk $err"
}

PQ="X25519MLKEM768 -tls1_3"
probe_cases() {
  for port in 9443 9444; do sc "C single cert" $port $PQ; sc "C single cert" $port X25519; done
  for port in 9445 9446; do
    sc "C two certs" $port $PQ
    sc "C two certs, RSA-only sigalgs" $port $PQ -sigalgs 'rsa_pss_rsae_sha256:rsa_pkcs1_sha256'
    sc "C two certs, ECDSA-only sigalgs" $port $PQ -sigalgs 'ecdsa_secp256r1_sha256'
  done
  for port in 9447 9448; do
    sc "C SNI a.test" $port $PQ -servername a.test; sc "C SNI b.test" $port $PQ -servername b.test
    sc "C SNI b.test classical" $port X25519 -servername b.test; sc "C SNI unknown" $port $PQ -servername c.test
  done
  sc "C legacy-encrypted key" 9449 $PQ; sc "C legacy-encrypted key" 9449 X25519
  sc "E mTLS RSA client" 9450 $PQ -cert cli-rsa.pem -key cli-rsa.key
  sc "E mTLS EC client" 9450 $PQ -cert cli-ec.pem -key cli-ec.key
  sc "E mTLS EC client classical" 9450 X25519 -cert cli-ec.pem -key cli-ec.key
  sc "E mTLS no client cert (neg)" 9450 $PQ
  sc "F server CurvePreferences{X25519,P256}" 9451 $PQ; sc "F server CurvePreferences{X25519,P256}" 9451 X25519MLKEM768:X25519
  sc "F server MaxVersion 1.2" 9452 X25519MLKEM768; sc "F server MaxVersion 1.2" 9452 X25519
  sc "F server CipherSuites" 9453 $PQ; sc "F server CipherSuites" 9453 X25519 -tls1_2
  sc "F server PQ-only" 9454 $PQ; sc "F server PQ-only" 9454 X25519
  sc "C env PEM" 9455 $PQ; sc "C env PEM" 9455 X25519
}

for b in /b/cases-*; do
  v=$(basename $b)
  echo; echo "################ $v"
  echo "-- D: default RootCAs with env"
  SSL_CERT_FILE=/certs/ca.pem TRUST_LABEL=SSL_CERT_FILE $b client-default
  SSL_CERT_DIR=/certs/cadir TRUST_LABEL=SSL_CERT_DIR $b client-default
  TRUST_LABEL="no env, negative" $b client-default
  echo "-- D/E/F client cases"
  $b client
  echo "-- C/E/F server cases"
  TLS_KEY_PASS=changeit TLS_CERT_PEM="$(cat srv-rsa.pem)" TLS_KEY_PEM="$(cat srv-rsa.key)" $b server >/tmp/srv-$v.log 2>&1 &
  pid=$!; sleep 1
  probe_cases
  kill $pid; sleep 0.3
  echo "-- server log ($v)"; sed 's/^/  /' /tmp/srv-$v.log
done

echo; echo "################ GODEBUG overrides at run time (client F/D subset)"
echo "-- cases-1.24-mod1.22 GODEBUG=tlsmlkem=1"; GODEBUG=tlsmlkem=1 /b/cases-1.24-mod1.22 client | grep -E 'RootCAs = NewCertPool|CurvePreferences'
echo "-- cases-1.26-mod1.26 GODEBUG=tlsmlkem=0"; GODEBUG=tlsmlkem=0 /b/cases-1.26-mod1.26 client | grep -E 'RootCAs = NewCertPool|CurvePreferences'

echo; echo "################ deps: PKCS#12 and encrypted PKCS#8 (Go 1.26.11)"
TLS_KEY_PASS=changeit /b/deps-1.26-mod1.26 server >/tmp/deps-srv.log 2>&1 &
pid=$!; sleep 1
for port in 9460 9461 9462; do sc "C deps" $port $PQ; sc "C deps" $port X25519; done
kill $pid; sleep 0.3; sed 's/^/  /' /tmp/deps-srv.log

echo; echo "################ H: libraries with custom tls.Config (Go 1.26.11)"
/b/deps-1.26-mod1.26 h
echo "-- AWS_CA_BUNDLE"
AWS_CA_BUNDLE=/certs/ca.pem /b/deps-1.26-mod1.26 h-awsenv
echo "-- H with GODEBUG=tlsmlkem=0 (should fail against PQ-only)"
GODEBUG=tlsmlkem=0 /b/deps-1.26-mod1.26 h | grep -vE 'CurvePreferences|8446'
echo DONE
