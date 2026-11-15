#!/bin/sh
# probe-server.sh - check that a TLS server accepts hybrid PQ and still accepts classical clients.
# Usage: sh probe-server.sh host:port [extra s_client args, e.g. -cert client.pem -key client.key -CAfile ca.pem]
# Needs OpenSSL 3.5+ (debian:trixie-slim, python:3.13-slim-trixie, alpine:3.24). Exit 0 = both checks passed.
T=$1; shift
H=${T%:*}
pq=$(echo Q | openssl s_client -connect "$T" -servername "$H" -groups X25519MLKEM768 -tls1_3 -brief "$@" 2>&1)
cl=$(echo Q | openssl s_client -connect "$T" -servername "$H" -groups X25519 -brief "$@" 2>&1)
echo "$pq" | grep -q 'Negotiated TLS1.3 group: X25519MLKEM768' && r1=PASS || r1=FAIL
echo "$cl" | grep -q 'Protocol version' && r2=PASS || r2=FAIL
echo "$r1 PQ client      ($T): $(echo "$pq" | grep -E 'Negotiated TLS1.3 group|alert|errno' | head -1)"
echo "$r2 classical client ($T): $(echo "$cl" | grep -E 'Protocol version|alert|errno' | head -1)"
[ $r1 = PASS ] && [ $r2 = PASS ]
