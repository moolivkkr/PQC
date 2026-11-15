#!/bin/bash
# Java custom keystores (case C), private CA trust (case D) and mutual TLS (case E) with and without
# the key-manager fix. One JDK image and one mode per run.
#   run-v2.sh <image tag> <mode>
#   image: eclipse-temurin:17-jre | eclipse-temurin:21-jre | eclipse-temurin:25-jre
#   mode:  v1nofix (kit agent v1, no fix) | v1file (v1 + -Djava.security.properties=pq-tls.security)
#          v2agent (v2 agent alone, no file) | v2kit (v2 agent + pq-tls.security, as packaged) | none (no agent)
# Agent and fix go in JAVA_TOOL_OPTIONS, as in the packaging; app options go on the command line.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
V="$(cd "$(dirname "$0")" && pwd)"; AG1="$V/../../../lambda-pq/fn/java-bundled/pq-tls"
IMG=$1; MODE=$2; TAG=$(echo "$IMG" | tr ':/' '__')
L=run=pqc-lang2-java; N=pqnet-java2
JDK=$(docker image inspect --format '{{index .RepoDigests 0}}' "$IMG")
DEB=$(docker image inspect --format '{{index .RepoDigests 0}}' debian:trixie-slim)
case $MODE in
  v1nofix) JTO="-javaagent:/agent1/pq-tls-agent.jar" ;;
  v1file)  JTO="-Djava.security.properties=/kit/pq-tls/pq-tls.security -javaagent:/agent1/pq-tls-agent.jar" ;;
  v2agent) JTO="-javaagent:/kit/pq-tls/pq-tls-agent.jar" ;;
  v2kit)   JTO="-Djava.security.properties=/kit/pq-tls/pq-tls.security -javaagent:/kit/pq-tls/pq-tls-agent.jar" ;;
  none)    JTO="" ;;
  file)    JTO="-Djava.security.properties=/kit/pq-tls/pq-tls.security" ;;
esac
echo "== $IMG ($JDK) mode=$MODE JAVA_TOOL_OPTIONS='$JTO'"
docker network create --label $L $N >/dev/null 2>&1
docker rm -f java2-ossl java2-jvm >/dev/null 2>&1
docker run -d --label $L --name java2-ossl --network $N -v "$V":/v "$DEB" sleep 900 >/dev/null
docker run -d --label $L --name java2-jvm --network $N --network-alias ks-java --network-alias alt-host \
  -v "$V":/v -v "$V/kit":/kit:ro -v "$AG1":/agent1:ro -v "$V/../lib-new":/deps:ro "$JDK" sleep 900 >/dev/null
docker exec java2-ossl sh -c 'apt-get -qq update >/dev/null 2>&1; apt-get -qq install -y openssl >/dev/null 2>&1'
printf 'jdk.tls.ephemeralDHKeySize=2048\n' > "$V/app.security"   # stands in for an app that ships its own security file

TS="-Djavax.net.ssl.trustStore=/v/c/trust.p12 -Djavax.net.ssl.trustStorePassword=changeit -Djavax.net.ssl.trustStoreType=PKCS12"
KS() { echo "-Djavax.net.ssl.keyStore=/v/c/$1 -Djavax.net.ssl.keyStorePassword=changeit -Djavax.net.ssl.keyStoreType=PKCS12"; }
LOG="$V/out/srv-$TAG-$MODE"; rm -f "$LOG"-*.log
start() { # port "app opts" args...
  p=$1; o=$2; shift 2
  docker exec -d -e JAVA_TOOL_OPTIONS="$JTO" java2-jvm sh -c "java $o -cp "/v/cls:/deps/*" V2Test server $* $p > /v/out/srv-$TAG-$MODE-$p.log 2>&1"; }
start 9001 "" /v/c/ec-main.p12 PKCS12 default
start 9002 "" /v/c/mixed.p12 PKCS12 default
start 9003 "" /v/c/mixed2.p12 PKCS12 default
start 9004 "" /v/c/multi.p12 PKCS12 default
start 9005 "" /v/c/ec.jks JKS default
start 9006 "" /v/c/ec-main.p12 PKCS12 SunX509
start 9007 "$(KS ec-main.p12)" default x x
start 9009 "" /v/c/rsa-main.p12 PKCS12 default
start 9010 "-DneedClientAuth=true $TS" /v/c/ec-main.p12 PKCS12 default
start 9011 "-DneedClientAuth=true $TS -Djdk.tls.namedGroups=X25519MLKEM768" /v/c/ec-main.p12 PKCS12 default
start 9012 "-Djava.security.properties=/v/app.security $(KS ec-main.p12)" default x x
docker exec -d java2-ossl sh -c 'openssl s_server -accept 8443 -tls1_3 -groups X25519MLKEM768 -cert /v/c/ec-ossl.crt -key /v/c/ec-ossl.key -Verify 1 -CAfile /v/c/ca.crt -www > /v/out/ossl-verify.log 2>&1'
docker exec -d java2-ossl sh -c 'openssl s_server -accept 8444 -tls1_3 -groups X25519MLKEM768 -cert /v/c/ec-ossl.crt -key /v/c/ec-ossl.key -www > /v/out/ossl-pqonly.log 2>&1'
sleep 8

probe() { # label port args
  r=$(docker exec java2-ossl sh -c "echo | timeout 8 openssl s_client -connect ks-java:$2 -brief $3 2>&1")
  g=$(echo "$r" | grep -m1 -oE 'group: [A-Za-z0-9]+')
  cn=$(echo "$r" | grep -m1 -oE 'Peer certificate: .*' | grep -oE 'CN ?= ?[a-z-]+')
  al=$(echo "$r" | grep -m1 -oE 'alert [a-z ]+' | head -1)
  printf "  %-58s | %-22s | %-14s | %s\n" "$1" "${g:-no group}" "${cn:-no cert}" "$al"; }
echo "-- C. server keystores (OpenSSL 3.5 s_client -> JVM server)"
probe "9001 EC P-256 only (PKCS#12)"                     9001 ""
probe "9001 EC only, classical-only client -groups X25519" 9001 "-groups X25519"
probe "9009 RSA only (PKCS#12)"                          9009 ""
probe "9002 RSA+EC in one PKCS#12"                       9002 ""
probe "9003 RSA(self-signed)+EC, RSA-only client sigalgs" 9003 "-sigalgs rsa_pss_rsae_sha256:rsa_pkcs1_sha256"
probe "9004 two EC certs, SNI ks-java"                   9004 "-servername ks-java"
probe "9004 two EC certs, SNI alt-host"                  9004 "-servername alt-host"
probe "9005 EC in JKS"                                   9005 ""
probe "9006 code hard-codes KeyManagerFactory SunX509"   9006 ""
probe "9007 -Djavax.net.ssl.keyStore (default context)"  9007 ""
probe "9012 app's own -Djava.security.properties + keyStore" 9012 ""
echo "-- E1. JVM server requires client cert (needClientAuth, trustStore=private CA)"
probe "9010 client EC cert, PQ group"     9010 "-groups X25519MLKEM768 -cert /v/c/client-ec.crt -key /v/c/client-ec.key"
probe "9010 client RSA cert, default"     9010 "-cert /v/c/client-rsa.crt -key /v/c/client-rsa.key"
probe "9010 no client cert (must fail)"   9010 ""
probe "9010 cert from unknown CA (must fail)" 9010 "-cert /v/c/client-rogue.crt -key /v/c/client-rogue.key"
probe "9011 PQ-only JVM server, EC client cert" 9011 "-cert /v/c/client-ec.crt -key /v/c/client-ec.key"
probe "9011 PQ-only JVM server, X25519-only client (must fail)" 9011 "-groups X25519 -cert /v/c/client-ec.crt -key /v/c/client-ec.key"
sleep 1
echo "   server 9010 log: $(grep -oE 'client-cert=[^ ]+|handshake failed: [^:]+: [a-z_()0-9]+' $LOG-9010.log | tr '\n' ' ')"
echo "   server 9011 log: $(grep -oE 'client-cert=[^ ]+|handshake failed: [^:]+: [a-z_()0-9]+' $LOG-9011.log | tr '\n' ' ')"

cli() { # label host port "app opts"
  r=$(docker exec -e JAVA_TOOL_OPTIONS="$JTO" java2-jvm sh -c "java $4 -cp "/v/cls:/deps/*" V2Test client $2 $3 2>/dev/null" | grep -E '^client')
  printf "  %-58s | %s\n" "$1" "$(echo "$r" | cut -c1-190)"; }
echo "-- D. JVM client trust -> PQ-only OpenSSL server, private-CA cert"
cli "no private CA configured (must fail)"            java2-ossl 8444 ""
cli "-Djavax.net.ssl.trustStore=trust.p12"            java2-ossl 8444 "$TS"
echo "-- E2. JVM client presents cert -> OpenSSL 3.5 PQ-only s_server -Verify 1"
cli "keyStore=client-ec.p12"                          java2-ossl 8443 "$TS $(KS client-ec.p12)"
cli "keyStore=client-rsa.p12"                         java2-ossl 8443 "$TS $(KS client-rsa.p12)"
cli "no keyStore (must fail)"                         java2-ossl 8443 "$TS"
echo "   s_server verify log: $(grep -oE 'depth=0 CN ?= ?[a-z-]+|peer did not return a certificate|alert [a-z ]+' $V/out/ossl-verify.log | tr '\n' ';')"
echo "-- E3. JVM client cert -> PQ-only JVM server (9011, jdk.tls.namedGroups=X25519MLKEM768)"
cli "keyStore=client-ec.p12"                          ks-java 9011 "$TS $(KS client-ec.p12)"
echo "-- server startup lines"
for p in 9001 9006 9007 9012; do echo "  $p: $(grep -m1 -E 'kmfDefault' $LOG-$p.log) $(grep -m1 -oE 'kmf=[^ ]+' $LOG-$p.log) $(grep -m1 'pq-tls agent' $LOG-$p.log)"; done
docker rm -f java2-ossl java2-jvm >/dev/null; docker network rm $N >/dev/null
echo "left: $(docker ps -a --filter label=$L --format '{{.Names}}' | wc -l | tr -d ' ')"
