#!/bin/bash
# Client matrix: Java HTTP/TLS libraries x JDK x (baseline | Bouncy Castle agent) against
# a PQ-only server (:8443, X25519MLKEM768 only, TLS 1.3) and a classical-only server (:8444, X25519).
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"
KIT="$W/../../lambda-pq/fn/java-bundled/pq-tls"
L=run=pqc-deep-java
NET=pqnet-java
docker network inspect $NET >/dev/null 2>&1 || docker network create --label $L $NET >/dev/null
docker rm -f pqsrv >/dev/null 2>&1 || true
docker run -d --label $L --name pqsrv --network $NET -v "$W/certs":/c:ro pqc-deep-java/ossl sh -c '
  openssl s_server -quiet -www -accept 8443 -cert /c/srv.crt -key /c/srv.key -tls1_3 -groups X25519MLKEM768 &
  openssl s_server -quiet -www -accept 8444 -cert /c/srv.crt -key /c/srv.key -groups X25519 &
  wait' >/dev/null

digest() { docker pull -q "$1" >/dev/null; docker image inspect --format '{{index .RepoDigests 0}}' "$1"; }

LIBS="jdk-httpclient urlconnection apache5 apache4 okhttp netty-jdk netty-tcnative netty-tcnative-groups aws-apache aws-netty aws-crt"
TRUST="-Djavax.net.ssl.trustStore=/w/certs/trust.p12 -Djavax.net.ssl.trustStorePassword=changeit -Djavax.net.ssl.trustStoreType=PKCS12"

# run <image> <label> <lib-dir> <extra JVM opts> <libs>
run() {
  local img=$1 label=$2 lib=$3 opts=$4 libs=$5 d
  d=$(digest "$img")
  echo "### $label  image=$d  opts=[$opts]"
  docker run --rm --label $L --network $NET -v "$W":/w:ro -v "$KIT":/agent:ro --entrypoint sh "$d" -c "
    (cp /w/certs/ca.crt /usr/local/share/ca-certificates/pq-test-ca.crt && update-ca-certificates >/dev/null 2>&1) ||
    (cp /w/certs/ca.crt /etc/pki/ca-trust/source/anchors/ && update-ca-trust) 2>/dev/null
    java -version 2>&1 | head -1
    for l in $libs; do java $TRUST $opts -cp /w/classes:/w/$lib/* Probe client \$l pqsrv 8443 8444 2>/dev/null; done"
}

AGENT="-javaagent:/agent/pq-tls-agent.jar"
{
run eclipse-temurin:17-jre "Temurin 17 baseline" lib-new "" "$LIBS"
run eclipse-temurin:17-jre "Temurin 17 + BC agent" lib-new "$AGENT" "$LIBS"
run eclipse-temurin:21-jre "Temurin 21 baseline" lib-new "" "$LIBS"
run eclipse-temurin:21-jre "Temurin 21 + BC agent" lib-new "$AGENT" "$LIBS"
run eclipse-temurin:25-jre "Temurin 25 baseline" lib-new "" "$LIBS"
run eclipse-temurin:25-jre "Temurin 25, jdk.tls.namedGroups=x25519,secp256r1 (pitfall)" lib-new "-Djdk.tls.namedGroups=x25519,secp256r1" "jdk-httpclient"
run amazoncorretto:25 "Corretto 25 baseline" lib-new "" "jdk-httpclient urlconnection okhttp"
run eclipse-temurin:21-jre "Temurin 21, AWS SDK 2.35.10 / aws-crt 0.38.9" lib-old "" "aws-crt"
} 2>&1 | tee "$W/out/clients.txt"
docker rm -f pqsrv >/dev/null
