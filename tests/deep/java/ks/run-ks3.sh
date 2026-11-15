#!/bin/bash
# Re-run: RSA-only client vs keystore holding EC (CA-signed) + RSA (self-signed, so its chain needs no ECDSA)
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
X="$(cd "$(dirname "$0")" && pwd)"; KIT="$X/../../../lambda-pq/fn/java-bundled/pq-tls"
L=run=pqc-deep-java-ks; N=pqnet-java-ks
JDK=$(docker image inspect --format '{{index .RepoDigests 0}}' eclipse-temurin:21)
DEB=$(docker image inspect --format '{{index .RepoDigests 0}}' debian:trixie-slim)
docker network create --label $L $N >/dev/null 2>&1
docker run -d --label $L --name ks-ossl --network $N -v "$X":/x "$DEB" sleep 900 >/dev/null
docker run -d --label $L --name ks-java --network $N -v "$X":/x -v "$KIT":/agent:ro "$JDK" sleep 900 >/dev/null
docker exec ks-ossl sh -c 'apt-get -qq update >/dev/null 2>&1; apt-get -qq install -y openssl >/dev/null 2>&1
  cd /x/c && openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj /CN=rsa-self -addext subjectAltName=DNS:ks-java -keyout rsa-self.key -out rsa-self.crt 2>/dev/null &&
  openssl pkcs12 -export -in rsa-self.crt -inkey rsa-self.key -name rsa-self -passout pass:changeit -out rsa-self.p12 && chmod a+rw rsa-self.*'
docker exec -w /x/c ks-java sh -c 'rm -f mixed2.p12; for s in rsa-self ec-main; do keytool -importkeystore -noprompt -srckeystore $s.p12 -srcstoretype PKCS12 -srcstorepass changeit -destkeystore mixed2.p12 -deststoretype PKCS12 -deststorepass changeit >/dev/null 2>&1; done'
AG="-javaagent:/agent/pq-tls-agent.jar"; FIX="-Djava.security.properties=/x/bc-kmf.security"
docker exec -d ks-java sh -c "java $FIX $AG -cp /x/cls KsTest server /x/c/mixed2.p12 PKCS12 default 9002 > /x/srv2-9002.log 2>&1"
docker exec -d ks-java sh -c "java $AG -cp /x/cls KsTest server /x/c/mixed2.p12 PKCS12 default 9003 > /x/srv2-9003.log 2>&1"
sleep 6
for c in "9002 fix:-sigalgs rsa_pss_rsae_sha256:rsa_pkcs1_sha256" "9003 nofix:-sigalgs rsa_pss_rsae_sha256:rsa_pkcs1_sha256"; do
  p=${c%% *}; rest=${c#* }; lab=${rest%%:*}; args=${rest#*:}; [ "$args" = default ] && args=""
  r=$(docker exec ks-ossl sh -c "echo | timeout 8 openssl s_client -connect ks-java:$p -brief $args 2>&1")
  echo "  $p $lab client[${args:-default}] | $(echo "$r" | grep -m1 -oE 'group: [A-Za-z0-9]+') | $(echo "$r" | grep -m1 -oE 'CN ?= ?[a-z-]+') $(echo "$r" | grep -m1 -oE 'alert [a-z ]+')"
done
docker rm -f ks-ossl ks-java >/dev/null; docker network rm $N >/dev/null
echo "left: $(docker ps -a --filter label=$L --format '{{.Names}}' | wc -l)"
