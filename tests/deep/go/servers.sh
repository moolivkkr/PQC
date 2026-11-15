#!/bin/sh
# Runs inside debian:trixie-slim (OpenSSL 3.5.x). One s_server per key-exchange group.
set -e
cd /tmp
command -v openssl >/dev/null || { apt-get update -qq >/dev/null && apt-get install -y -qq openssl >/dev/null 2>&1; }
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout k.pem -out c.pem -days 2 -subj /CN=pqsrv -addext subjectAltName=DNS:pqsrv >/dev/null 2>&1
openssl version
srv() { port=$1; shift; openssl s_server -quiet -accept $port -cert c.pem -key k.pem -www "$@" >/tmp/s$port.log 2>&1 & }
srv 8443 -tls1_3 -groups X25519MLKEM768
srv 8444 -groups X25519
srv 8445 -tls1_3 -groups SecP256r1MLKEM768
srv 8446 -groups P-256
srv 8447 -tls1_3 -groups SecP384r1MLKEM1024
srv 8448 -tls1_3 -groups MLKEM1024
srv 8449 -tls1_3 -groups X25519MLKEM768 -alpn h2
echo servers-up
sleep 7200
