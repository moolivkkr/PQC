#!/bin/bash
# What happens to BCJSSE (agent, JDK 21) when apps bring their own keystores / truststores?
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
X="$(cd "$(dirname "$0")" && pwd)"
KIT="$X/../../../lambda-pq/fn/java-bundled/pq-tls"
L=run=pqc-deep-java-ks; N=pqnet-java-ks
JDK=$(docker image inspect --format '{{index .RepoDigests 0}}' eclipse-temurin:21)
DEB=$(docker image inspect --format '{{index .RepoDigests 0}}' debian:trixie-slim)
printf 'ssl.KeyManagerFactory.algorithm=PKIX\n' > "$X/bc-kmf.security"
docker network create --label $L $N >/dev/null 2>&1
docker rm -f ks-ossl ks-java >/dev/null 2>&1
docker run -d --label $L --name ks-ossl --network $N -v "$X":/x "$DEB" sleep 3000 >/dev/null
docker run -d --label $L --name ks-java --network $N -v "$X":/x -v "$KIT":/agent:ro "$JDK" sleep 3000 >/dev/null
docker exec ks-ossl sh -c 'apt-get -qq update >/dev/null 2>&1; apt-get -qq install -y openssl >/dev/null 2>&1'

echo "== certs (one private CA; EC + RSA for ks-java, EC for alt-host)"
docker exec -w /x ks-ossl sh -ec '
  rm -rf c; mkdir c; cd c
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 -subj /CN=ks-ca -keyout ca.key -out ca.crt 2>/dev/null
  mk() { # name keyalg san
    if [ $2 = ec ]; then openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj /CN=$1 -keyout $1.key -out $1.csr 2>/dev/null
    else openssl req -newkey rsa:2048 -nodes -subj /CN=$1 -keyout $1.key -out $1.csr 2>/dev/null; fi
    printf "subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\n" $3 > $1.ext
    openssl x509 -req -in $1.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 30 -extfile $1.ext -out $1.crt 2>/dev/null
    openssl pkcs12 -export -in $1.crt -inkey $1.key -certfile ca.crt -name $1 -passout pass:changeit -out $1.p12; }
  mk ec-main ec ks-java; mk rsa-main rsa ks-java; mk ec-alt ec alt-host; mk ec-ossl ec ks-ossl
  chmod -R a+rwX /x/c'
docker exec -w /x/c ks-java sh -ec '
  imp() { keytool -importkeystore -noprompt -srckeystore $1 -srcstoretype PKCS12 -srcstorepass changeit -destkeystore $2 -deststoretype $3 -deststorepass changeit >/dev/null 2>&1; }
  rm -f mixed.p12 multi.p12 ec.jks trust.p12
  imp rsa-main.p12 mixed.p12 PKCS12; imp ec-main.p12 mixed.p12 PKCS12        # RSA added first, then EC
  imp ec-main.p12 multi.p12 PKCS12;  imp ec-alt.p12 multi.p12 PKCS12         # two EC certs, two hostnames
  imp ec-main.p12 ec.jks JKS                                                 # legacy JKS
  keytool -importcert -noprompt -alias ks-ca -file ca.crt -keystore trust.p12 -storetype PKCS12 -storepass changeit >/dev/null 2>&1
  cd /x && javac -d /x/cls KsTest.java && echo compiled'

AG="-javaagent:/agent/pq-tls-agent.jar"; FIX="-Djava.security.properties=/x/bc-kmf.security"
start() { # port "java opts" args...
  p=$1; o=$2; shift 2
  docker exec -d ks-java sh -c "java $o $AG -cp /x/cls KsTest server $* $p > /x/srv-$p.log 2>&1"; }
start 9001 "$FIX" /x/c/ec-main.p12 PKCS12 default
start 9002 "$FIX" /x/c/mixed.p12 PKCS12 default
start 9003 ""     /x/c/mixed.p12 PKCS12 default
start 9004 "$FIX" /x/c/multi.p12 PKCS12 default
start 9005 "$FIX" /x/c/ec.jks JKS default
start 9006 "$FIX" /x/c/ec-main.p12 PKCS12 SunX509
start 9007 "$FIX -Djavax.net.ssl.keyStore=/x/c/ec-main.p12 -Djavax.net.ssl.keyStoreType=PKCS12 -Djavax.net.ssl.keyStorePassword=changeit" default x x
start 9008 "-Djavax.net.ssl.keyStore=/x/c/ec-main.p12 -Djavax.net.ssl.keyStoreType=PKCS12 -Djavax.net.ssl.keyStorePassword=changeit" default x x
sleep 6

echo "== server side: openssl 3.5 clients against BCJSSE servers"
probe() { # label port extra-args
  r=$(docker exec ks-ossl sh -c "echo | timeout 8 openssl s_client -connect ks-java:$2 -brief $3 2>&1")
  g=$(echo "$r" | grep -m1 -oE 'group: [A-Za-z0-9]+')
  cn=$(echo "$r" | grep -m1 -oE 'Peer certificate: .*' | grep -oE 'CN ?= ?[a-z-]+')
  st=$(echo "$r" | grep -m1 -oE 'Peer signature type: [a-z_0-9A-Z-]+')
  al=$(echo "$r" | grep -m1 -oE 'alert [a-z ]+')
  echo "  $1 | ${g:-no group} | ${cn:-no cert} | ${st} ${al}"; }
probe "9001 EC only, fix                        default client " 9001 ""
probe "9002 RSA+EC in one p12, fix              default client " 9002 ""
probe "9002 RSA+EC in one p12, fix              RSA-only client" 9002 "-sigalgs rsa_pss_rsae_sha256"
probe "9003 RSA+EC in one p12, NO fix           default client " 9003 ""
probe "9004 two EC certs, fix                   SNI ks-java    " 9004 "-servername ks-java"
probe "9004 two EC certs, fix                   SNI alt-host   " 9004 "-servername alt-host"
probe "9005 EC in JKS, fix                      default client " 9005 ""
probe "9006 code hardcodes SunX509, fix         default client " 9006 ""
probe "9007 javax.net.ssl.keyStore, fix         default client " 9007 ""
probe "9008 javax.net.ssl.keyStore, NO fix      default client " 9008 ""
probe "9002 RSA+EC, fix  classical-only client (X25519)       " 9002 "-groups X25519"
for p in 9001 9002 9003 9004 9005 9006 9007 9008; do echo "  srv-$p: $(grep -m1 -E 'kmf=|default SSLContext' $X/srv-$p.log | cut -c1-140)"; done

echo "== client side: BCJSSE client -> PQ-only openssl server with a private-CA cert"
docker exec -d ks-ossl sh -c 'openssl s_server -accept 8443 -cert /x/c/ec-ossl.crt -key /x/c/ec-ossl.key -tls1_3 -groups X25519MLKEM768 -www > /x/ossl.log 2>&1'
sleep 2
cli() { echo "  $1: $(docker exec ks-java sh -c "java $2 $AG -cp /x/cls KsTest client ks-ossl 8443 2>/dev/null" | cut -c1-170)"; }
cli "no CA configured                       " ""
cli "javax.net.ssl.trustStore=trust.p12     " "-Djavax.net.ssl.trustStore=/x/c/trust.p12 -Djavax.net.ssl.trustStorePassword=changeit -Djavax.net.ssl.trustStoreType=PKCS12"
docker exec ks-java sh -c 'keytool -importcert -noprompt -cacerts -storepass changeit -alias ks-ca -file /x/c/ca.crt >/dev/null 2>&1'
cli "CA imported into JDK cacerts (keytool)  " ""
cli "cacerts import + kmf fix property      " "$FIX"

docker rm -f ks-ossl ks-java >/dev/null; docker network rm $N >/dev/null
echo "left: $(docker ps -a --filter label=$L --format '{{.Names}}' | wc -l)"
