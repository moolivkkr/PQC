#!/bin/bash
# Fix test: make the default KeyManagerFactory algorithm PKIX so BCJSSE's own key manager
# (which understands key type 'EC/secp256r1') is used instead of SunJSSE's SunX509.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"; KIT="$W/../../lambda-pq/fn/java-bundled/pq-tls"
L=run=pqc-deep-java-r3; NET=pqnet-java-r3
DEB=$(docker image inspect --format '{{index .RepoDigests 0}}' debian:trixie-slim)
docker network create --label $L $NET >/dev/null 2>&1
for jv in 17 21; do
 J=$(docker image inspect --format '{{index .RepoDigests 0}}' eclipse-temurin:$jv-jre)
 for impl in tomcat jetty jdk-httpsserver; do
  for fix in none kmf-pkix; do
   [ $fix = none ] && P="" || P="-Djava.security.properties=/w/bc-kmf.security"
   docker rm -f bcsrv4 >/dev/null 2>&1
   docker run -d --label $L --name bcsrv4 --network $NET -v "$W":/w:ro -v "$KIT":/agent:ro --entrypoint sh "$J" \
     -c "java $P -Djava.util.logging.config.file=/w/bc-logging.properties -javaagent:/agent/pq-tls-agent.jar -cp /w/classes:/w/lib-new/* Probe server $impl 9443" >/dev/null
   res=$(docker run --rm --label $L --network $NET "$DEB" bash -c 'command -v openssl >/dev/null || { apt-get -qq update >/dev/null 2>&1; apt-get -qq install -y openssl >/dev/null 2>&1; }
     for i in $(seq 80); do (echo > /dev/tcp/bcsrv4/9443) 2>/dev/null && break; sleep 0.5; done; sleep 2
     for g in X25519MLKEM768 X25519 DEFAULT; do [ $g = DEFAULT ] && a="" || a="-groups $g"
       r=$(echo | timeout 8 openssl s_client -connect bcsrv4:9443 -brief $a 2>&1)
       printf "%s=%s; " $g "$(echo "$r" | grep -m1 -oE "group: [A-Za-z0-9]+|alert [a-z ]+|Protocol version: TLSv1.[23]" | tr -d "\n")"; done')
   km=$(docker logs bcsrv4 2>&1 | grep -m1 -oE "Importing X509KeyManager implementation: [A-Za-z0-9.]+|ProvX509KeyManager[A-Za-z]*" )
   echo "JDK $jv $impl fix=$fix | $res | km: ${km:-BC native}"
   docker rm -f bcsrv4 >/dev/null
  done
 done
done 2>&1 | tee "$W/out/bcserver4.txt"
docker network rm $NET >/dev/null; docker ps -a --filter label=$L --format '{{.Names}}'
