#!/bin/sh
# Runs inside the pqsrv-go container (OpenSSL 3.5.7). Tests the Go servers at gosrv.
sc() { # label port groups [extra]
  label=$1; port=$2; groups=$3; shift 3
  out=$(perl -e 'alarm shift; exec @ARGV' 10 openssl s_client -connect gosrv:$port -servername gosrv -groups $groups "$@" 2>&1 </dev/null)
  g=$(echo "$out" | grep -m1 -E 'Negotiated TLS1.3 group|Server Temp Key' | sed 's/^ *//')
  p=$(echo "$out" | grep -m1 -E '^ *Protocol *:|^Protocol version' | sed 's/^ *//')
  a=$(echo "$out" | grep -m1 -E 'ALPN protocol' | sed 's/^ *//')
  if echo "$out" | grep -q 'Cipher is (NONE)\|handshake failure\|alert'; then r=FAIL; else r=OK; fi
  echo "$label | client groups=$groups $* | $r | $g | $p | $a"
}
sc "net/http default        :9443" 9443 X25519MLKEM768 -tls1_3
sc "net/http default        :9443" 9443 X25519
sc "net/http default        :9443" 9443 SecP256r1MLKEM768 -tls1_3
sc "net/http default        :9443" 9443 P-256 -tls1_2
sc "net/http pitfall curves :9444" 9444 X25519MLKEM768 -tls1_3
sc "net/http pitfall curves :9444" 9444 X25519MLKEM768:X25519
sc "net/http PQ-only        :9445" 9445 X25519MLKEM768 -tls1_3
sc "net/http PQ-only        :9445" 9445 X25519
sc "net/http PQ-only        :9445" 9445 X25519MLKEM768 -tls1_2
sc "gRPC default            :9446" 9446 X25519MLKEM768 -tls1_3 -alpn h2
sc "gRPC default            :9446" 9446 X25519 -alpn h2
