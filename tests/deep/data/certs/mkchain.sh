#!/bin/sh
# Build an ML-DSA chain (root ML-DSA-87 -> intermediate ML-DSA-65 -> leaf ML-DSA-44)
# and a parallel ECDSA P-256 chain, with OpenSSL 3.5. Run inside debian:trixie / postgres:18.
set -e
cd /work
openssl version

# --- ML-DSA root CA (ML-DSA-87, 10 years)
openssl genpkey -algorithm ML-DSA-87 -out mldsa-root.key
openssl req -x509 -new -key mldsa-root.key -subj "/CN=Example ML-DSA Root CA" -days 3650 \
  -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -out mldsa-root.crt

# --- ML-DSA intermediate (ML-DSA-65, 5 years)
openssl genpkey -algorithm ML-DSA-65 -out mldsa-int.key
openssl req -new -key mldsa-int.key -subj "/CN=Example ML-DSA Issuing CA" -out mldsa-int.csr
openssl x509 -req -in mldsa-int.csr -CA mldsa-root.crt -CAkey mldsa-root.key -CAcreateserial -days 1825 \
  -extfile ca.ext -extensions v3_int -out mldsa-int.crt

# --- ML-DSA leaf (ML-DSA-44, 90 days) for host "web"
openssl genpkey -algorithm ML-DSA-44 -out mldsa-leaf.key
openssl req -new -key mldsa-leaf.key -subj "/CN=web" -out mldsa-leaf.csr
openssl x509 -req -in mldsa-leaf.csr -CA mldsa-int.crt -CAkey mldsa-int.key -CAcreateserial -days 90 \
  -extfile ca.ext -extensions v3_leaf -out mldsa-leaf.crt
cat mldsa-leaf.crt mldsa-int.crt > mldsa-fullchain.crt

# --- ECDSA P-256 chain (classical fallback)
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out ec-root.key
openssl req -x509 -new -key ec-root.key -subj "/CN=Example ECDSA Root CA" -days 3650 \
  -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" -out ec-root.crt
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out ec-leaf.key
openssl req -new -key ec-leaf.key -subj "/CN=web" -out ec-leaf.csr
openssl x509 -req -in ec-leaf.csr -CA ec-root.crt -CAkey ec-root.key -CAcreateserial -days 90 \
  -extfile ca.ext -extensions v3_leaf -out ec-leaf.crt
cat ec-leaf.crt > ec-fullchain.crt

cat mldsa-root.crt ec-root.crt > roots-both.crt

echo "--- verify ML-DSA chain"
openssl verify -CAfile mldsa-root.crt -untrusted mldsa-int.crt mldsa-leaf.crt
openssl x509 -in mldsa-leaf.crt -noout -text | grep -E "Signature Algorithm|Public Key Algorithm" | sort -u
echo "--- sizes (bytes, DER)"
for f in mldsa-root mldsa-int mldsa-leaf ec-root ec-leaf; do
  printf "%s %s\n" $f "$(openssl x509 -in $f.crt -outform DER | wc -c)"; done
