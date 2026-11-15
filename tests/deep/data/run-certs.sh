#!/bin/bash
# ML-DSA chain build + nginx dual-cert (ML-DSA + ECDSA) + client verification matrix.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
D=$(cd "$(dirname "$0")" && pwd); cd "$D"
L="--label run=pqc-deep-data"; NET=pqnet-data
dig() { grep "^$1 " digests.txt | awk '{print $2}' | head -1; }
OSSL=$(dig postgres:18); NGX=$(dig nginx:1.29); GO125=$(dig golang:1.25-trixie); GO127=$(dig golang:1.27-trixie)
PY=$(dig python:3.13-slim-trixie); JDK=$(dig eclipse-temurin:25-jdk); NODE=$(dig node:24-slim); PGB=$(dig postgres:18-bookworm)
T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
docker network create $L $NET >/dev/null 2>&1
W="-v $D/certs:/work"

echo "=== build chains (OpenSSL 3.5.7, trixie)"
rm -f certs/*.key certs/*.crt certs/*.csr certs/*.srl
T 120 docker run --rm $L $W --entrypoint sh $OSSL /work/mkchain.sh 2>&1

echo "=== nginx 1.29 (trixie, OpenSSL 3.5.5) dual cert"
docker rm -f web >/dev/null 2>&1
docker run -d $L --name web --network $NET -v $D/certs:/etc/nginx/pki:ro \
  -v $D/certs/nginx-dualcert.conf:/etc/nginx/conf.d/default.conf:ro $NGX >/dev/null
sleep 3; docker logs web 2>&1 | grep -iE 'emerg|error' | head -3

scl() { echo "--- openssl s_client: $1"
  T 20 docker run --rm $L --network $NET $W --entrypoint sh $OSSL -c "echo | openssl s_client -connect web:443 -servername web -CAfile /work/roots-both.crt $2 2>&1 | grep -E 'Protocol version|Peer signature type|Negotiated TLS1.3 group|Verification|^ *0 s:|a:PKEY|alert|error' | head -6"; }
scl "OpenSSL 3.5 default (offers mldsa sigalgs)" "-brief"
scl "OpenSSL 3.5 -sigalgs ecdsa_secp256r1_sha256" "-brief -sigalgs ecdsa_secp256r1_sha256"
scl "OpenSSL 3.5 -sigalgs mldsa44 only" "-brief -sigalgs mldsa44"
echo "--- OpenSSL 3.0 client (bookworm), default"
T 20 docker run --rm $L --network $NET $W --entrypoint sh $PGB -c "echo | openssl s_client -connect web:443 -servername web -CAfile /work/roots-both.crt -brief 2>&1 | grep -E 'Protocol version|Peer signature type|Verification|Server Temp|group|error' | head -5"
echo "--- curl (nginx image, trixie)"
T 20 docker run --rm $L --network $NET $W --entrypoint sh $NGX -c "curl -sS --cacert /work/roots-both.crt https://web/ -w ' http=%{http_code}\n'; echo | openssl s_client -connect web:443 -servername web -brief 2>&1 | grep 'Peer signature type'"

echo "=== Python 3.13 (trixie)"
T 30 docker run --rm $L --network $NET $W $PY python -I /work/pyclient.py 2>&1 | tail -3

for G in "$GO125" "$GO127"; do echo "=== Go client $G"
  T 180 docker run --rm $L --network $NET $W -e GOTOOLCHAIN=local -e GOFLAGS=-mod=mod $G sh -c \
    "mkdir -p /src && cp /work/goclient/main.go /src/ && cd /src && go mod init x >/dev/null 2>&1 && go run . 2>&1" | tail -5
done

echo "=== Java (Temurin 25, stock JDK)"
T 120 docker run --rm $L --network $NET $W $JDK sh -c "cd /tmp && java /work/VerifyChain.java" 2>&1 | tail -5

echo "=== Node 24"
T 30 docker run --rm $L --network $NET $W $NODE node /work/nodeclient.js 2>&1 | tail -3

docker rm -f web >/dev/null
echo DONE
