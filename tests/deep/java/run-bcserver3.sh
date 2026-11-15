#!/bin/bash
# Hypothesis: BCJSSE (server) only selects an ECDSA P-256 certificate when the client's
# supported_groups includes secp256r1 (TLS 1.2 rule applied to TLS 1.3). Earlier tests used
# clients offering ONLY X25519MLKEM768 or ONLY X25519.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"
KIT="$W/../../lambda-pq/fn/java-bundled/pq-tls"
L=run=pqc-deep-java-r3
NET=pqnet-java-r3
J21=$(docker image inspect --format '{{index .RepoDigests 0}}' eclipse-temurin:21-jre)
docker pull -q debian:trixie-slim >/dev/null
DEB=$(docker image inspect --format '{{index .RepoDigests 0}}' debian:trixie-slim)
docker network create --label $L $NET >/dev/null 2>&1
CLI="openssl s_client"
for v in ec rsa; do
  if [ $v = ec ]; then CERTS="$W/certs"; else CERTS="$W/certs-alt/rsa"; fi
  echo "### Tomcat 11.0.29, JDK 21 + BCJSSE agent, cert=$v"
  docker rm -f bcsrv3 >/dev/null 2>&1
  docker run -d --label $L --name bcsrv3 --network $NET -v "$W":/w:ro -v "$CERTS":/w/certs:ro -v "$KIT":/agent:ro \
    --entrypoint sh "$J21" -c "java -javaagent:/agent/pq-tls-agent.jar -cp /w/classes:/w/lib-new/* Probe server tomcat 9443" >/dev/null
  docker run --rm --label $L --network $NET "$DEB" bash -c '
    apt-get -qq update >/dev/null 2>&1; apt-get -qq install -y openssl >/dev/null 2>&1
    for i in $(seq 80); do (echo > /dev/tcp/bcsrv3/9443) 2>/dev/null && break; sleep 0.5; done; sleep 1
    for g in X25519MLKEM768 X25519 X25519MLKEM768:X25519:P-256 X25519MLKEM768:P-256 X25519:P-256 DEFAULT; do
      if [ $g = DEFAULT ]; then a=""; else a="-groups $g"; fi
      r=$(echo | timeout 8 openssl s_client -connect bcsrv3:9443 -tls1_3 -brief $a 2>&1)
      echo "   client groups=$g: $(echo "$r" | grep -m1 -oE "Negotiated TLS1.3 group: .*|group: .*|alert [a-z ]+" )"; done'
  docker logs bcsrv3 2>&1 | grep -m2 -iE "selectable|credentials|TlsFatal" | cut -c1-200 | sed 's/^/   log: /'
  docker rm -f bcsrv3 >/dev/null
done 2>&1 | tee "$W/out/bcserver3.txt"
docker network rm $NET >/dev/null
docker ps -a --filter label=$L --format '{{.Names}}'
