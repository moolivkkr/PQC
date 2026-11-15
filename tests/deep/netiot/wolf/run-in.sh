#!/bin/sh
# Runs inside alpine:3.24: distro wolfSSL vs OpenSSL 3.5 PQ-only and classical-only servers.
apk add -q wolfssl-dev gcc musl-dev openssl >/dev/null 2>&1
echo "== versions"; apk info -v 2>/dev/null | grep -E '^wolfssl|^openssl-3'
grep -E 'HAVE_MLKEM|WOLFSSL_WC_MLKEM|HAVE_CURVE25519|WOLFSSL_TLS13|HAVE_KYBER' /usr/include/wolfssl/options.h | head
cd /tmp
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 2 -subj /CN=localhost -addext subjectAltName=DNS:localhost -keyout k.pem -out c.pem 2>/dev/null
openssl s_server -quiet -accept 4433 -tls1_3 -groups X25519MLKEM768 -cert c.pem -key k.pem >/dev/null 2>&1 &
openssl s_server -quiet -accept 4434 -groups X25519 -cert c.pem -key k.pem >/dev/null 2>&1 &
cc /cfg/pqclient.c -lwolfssl -o pqclient 2>&1 | head -5 || exit 1
sleep 1
echo "-- PQ client -> PQ-only server";        ./pqclient localhost 4433 c.pem
echo "-- PQ client -> classical-only server";  ./pqclient localhost 4434 c.pem
echo "-- classic client -> PQ-only server (must fail)"; ./pqclient localhost 4433 c.pem classic
