#!/bin/bash
# Build the v2 kit (agent with the key-manager fix) and the test classes; make client certs for mTLS.
set -euo pipefail
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
V="$(cd "$(dirname "$0")" && pwd)"; J="$V/.."
BCJARS="$J/../../lambda-pq/fn/java-bundled/pq-tls"
L=run=pqc-lang2-java
JDK=$(docker image inspect --format '{{index .RepoDigests 0}}' eclipse-temurin:21)
DEB=$(docker image inspect --format '{{index .RepoDigests 0}}' debian:trixie-slim)
echo "images: $JDK $DEB"
mkdir -p "$V/kit/pq-tls" "$V/kit/pq-tls-layer" "$V/c"
cp "$BCJARS"/b*-jdk18on-1.87.jar "$V/kit/pq-tls/"
cp "$V/kit/pq-tls/pq-tls.security" "$V/kit/pq-tls-layer/"
printf 'Premain-Class: PqTlsAgent\nClass-Path: bcprov-jdk18on-1.87.jar bctls-jdk18on-1.87.jar bcutil-jdk18on-1.87.jar\n' > "$V/kit/MANIFEST.MF"
printf 'Premain-Class: PqTlsAgent\nClass-Path: ../java/lib/bcprov-jdk18on-1.87.jar ../java/lib/bctls-jdk18on-1.87.jar ../java/lib/bcutil-jdk18on-1.87.jar\n' > "$V/kit/MANIFEST-layer.MF"
cp "$J"/ks/c/{ca.crt,ca.key,ec-main.p12,rsa-main.p12,ec-alt.p12,ec-ossl.crt,ec-ossl.key,mixed.p12,multi.p12,ec.jks,trust.p12} "$V/c/"

docker run --rm --label $L --name java2-build -v "$V":/v -v "$J/lib-new":/deps:ro "$JDK" sh -ec '
  cd /v/kit && rm -rf cls && mkdir cls
  javac -nowarn --release 8 -cp "pq-tls/*" -d cls src/PqTlsAgent.java 2>&1 | grep -v "warning" || true
  jar cfm pq-tls/pq-tls-agent.jar MANIFEST.MF -C cls PqTlsAgent.class
  jar cfm pq-tls-layer/pq-tls-agent.jar MANIFEST-layer.MF -C cls PqTlsAgent.class
  cd /v && rm -rf cls && javac --release 17 -cp "/deps/*" -d cls V2Test.java && echo compiled'

docker run --rm --label $L --name java2-certs -v "$V":/v "$DEB" sh -ec '
  apt-get -qq update >/dev/null 2>&1; apt-get -qq install -y openssl >/dev/null 2>&1; openssl version
  cd /v/c
  mk() { # name keyalg eku
    if [ $2 = ec ]; then openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj /CN=$1 -keyout $1.key -out $1.csr 2>/dev/null
    else openssl req -newkey rsa:2048 -nodes -subj /CN=$1 -keyout $1.key -out $1.csr 2>/dev/null; fi
    printf "extendedKeyUsage=%s\n" $3 > $1.ext
    openssl x509 -req -in $1.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 30 -extfile $1.ext -out $1.crt 2>/dev/null
    openssl pkcs12 -export -in $1.crt -inkey $1.key -certfile ca.crt -name $1 -passout pass:changeit -out $1.p12; }
  mk client-ec ec clientAuth; mk client-rsa rsa clientAuth
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 -subj /CN=rogue-ca -keyout rogue-ca.key -out rogue-ca.crt 2>/dev/null
  openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj /CN=client-rogue -keyout client-rogue.key -out client-rogue.csr 2>/dev/null
  printf "extendedKeyUsage=clientAuth\n" > client-rogue.ext
  openssl x509 -req -in client-rogue.csr -CA rogue-ca.crt -CAkey rogue-ca.key -CAcreateserial -days 30 -extfile client-rogue.ext -out client-rogue.crt 2>/dev/null
  chmod -R a+rwX /v/c; ls /v/c | tr "\n" " "'
ls -l "$V/kit/pq-tls" "$V/kit/pq-tls-layer"
