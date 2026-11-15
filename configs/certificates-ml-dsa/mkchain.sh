#!/bin/sh
# mkchain.sh - root ML-DSA-87 -> intermediate ML-DSA-65 -> leaf ML-DSA-44, plus an ECDSA P-256 chain.
# Tested in postgres:18 (Debian 13, OpenSSL 3.5.7). Run in a directory that holds ca.ext.
set -e
openssl version

openssl genpkey -algorithm ML-DSA-87 -out mldsa-root.key
openssl req -x509 -new -key mldsa-root.key -subj "/CN=Example ML-DSA Root CA" -days 3650 \
  -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -out mldsa-root.crt

openssl genpkey -algorithm ML-DSA-65 -out mldsa-int.key
openssl req -new -key mldsa-int.key -subj "/CN=Example ML-DSA Issuing CA" -out mldsa-int.csr
openssl x509 -req -in mldsa-int.csr -CA mldsa-root.crt -CAkey mldsa-root.key -CAcreateserial -days 1825 \
  -extfile ca.ext -extensions v3_int -out mldsa-int.crt

openssl genpkey -algorithm ML-DSA-44 -out mldsa-leaf.key
openssl req -new -key mldsa-leaf.key -subj "/CN=web" -out mldsa-leaf.csr
openssl x509 -req -in mldsa-leaf.csr -CA mldsa-int.crt -CAkey mldsa-int.key -CAcreateserial -days 90 \
  -extfile ca.ext -extensions v3_leaf -out mldsa-leaf.crt
cat mldsa-leaf.crt mldsa-int.crt > mldsa-fullchain.crt

openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out ec-root.key
openssl req -x509 -new -key ec-root.key -subj "/CN=Example ECDSA Root CA" -days 3650 \
  -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" -out ec-root.crt
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out ec-leaf.key
openssl req -new -key ec-leaf.key -subj "/CN=web" -out ec-leaf.csr
openssl x509 -req -in ec-leaf.csr -CA ec-root.crt -CAkey ec-root.key -CAcreateserial -days 90 \
  -extfile ca.ext -extensions v3_leaf -out ec-leaf.crt
cat ec-leaf.crt > ec-fullchain.crt

cat mldsa-root.crt ec-root.crt > roots-both.crt
openssl verify -CAfile mldsa-root.crt -untrusted mldsa-int.crt mldsa-leaf.crt
