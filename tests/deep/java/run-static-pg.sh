#!/bin/bash
# (a) Static Bouncy Castle provider registration (java.security override, no agent) as client and server.
# (b) PostgreSQL JDBC (pgjdbc) against PostgreSQL 18 with ssl_groups=X25519MLKEM768 (PQ-only) and =X25519.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"
KIT="$W/../../lambda-pq/fn/java-bundled/pq-tls"
L=run=pqc-deep-java
NET=pqnet-java
docker network inspect $NET >/dev/null 2>&1 || docker network create --label $L $NET >/dev/null
digest() { docker pull -q "$1" >/dev/null; docker image inspect --format '{{index .RepoDigests 0}}' "$1"; }
TRUST="-Djavax.net.ssl.trustStore=/w/certs/trust.p12 -Djavax.net.ssl.trustStorePassword=changeit -Djavax.net.ssl.trustStoreType=PKCS12"
STATIC="-Djava.security.properties=/w/bc-static.security"
CP="/w/classes:/w/lib-new/*:/agent/bcprov-jdk18on-1.87.jar:/agent/bctls-jdk18on-1.87.jar:/agent/bcutil-jdk18on-1.87.jar"
J21=$(digest eclipse-temurin:21-jre); J17=$(digest eclipse-temurin:17-jre); J25=$(digest eclipse-temurin:25-jre)

jc() { # image label opts libs host pq cl
  echo "### $2  image=$1 opts=[$3]"
  docker run --rm --label $L --network $NET -v "$W":/w:ro -v "$KIT":/agent:ro --entrypoint sh "$1" -c "
    for l in $4; do java $TRUST $3 -cp '$CP' Probe client \$l $5 $6 $7 2>&1 | grep -v WARNING; done"
}
{
# --- (a) static registration, client side
docker rm -f pqsrv >/dev/null 2>&1
docker run -d --label $L --name pqsrv --network $NET -v "$W/certs":/c:ro pqc-deep-java/ossl sh -c '
  openssl s_server -quiet -www -accept 8443 -cert /c/srv.crt -key /c/srv.key -tls1_3 -groups X25519MLKEM768 &
  openssl s_server -quiet -www -accept 8444 -cert /c/srv.crt -key /c/srv.key -groups X25519 &
  wait' >/dev/null
jc $J21 "Temurin 21, static BCJSSE, BC default groups (no jdk.tls.namedGroups)" "$STATIC" "jdk-httpclient urlconnection okhttp" pqsrv 8443 8444
jc $J21 "Temurin 21, static BCJSSE + jdk.tls.namedGroups=X25519MLKEM768,x25519,secp256r1,secp384r1" "$STATIC -Djdk.tls.namedGroups=X25519MLKEM768,x25519,secp256r1,secp384r1" "jdk-httpclient urlconnection okhttp" pqsrv 8443 8444
jc $J17 "Temurin 17, static BCJSSE + namedGroups" "$STATIC -Djdk.tls.namedGroups=X25519MLKEM768,x25519,secp256r1,secp384r1" "jdk-httpclient urlconnection" pqsrv 8443 8444
jc $J21 "Temurin 21 + agent, but service pins jdk.tls.namedGroups=x25519,secp256r1 (pitfall)" "-javaagent:/agent/pq-tls-agent.jar -Djdk.tls.namedGroups=x25519,secp256r1" "jdk-httpclient" pqsrv 8443 8444
jc $J25 "Temurin 25, jdk.tls.namedGroups=x25519,secp256r1 (pitfall)" "-Djdk.tls.namedGroups=x25519,secp256r1" "jdk-httpclient netty-tcnative" pqsrv 8443 8444
jc $J21 "Temurin 21, Netty tcnative with jdk.tls.namedGroups=x25519,secp256r1 (does Netty honour it?)" "-Djdk.tls.namedGroups=x25519,secp256r1" "netty-tcnative" pqsrv 8443 8444
docker rm -f pqsrv >/dev/null

# --- (a) static registration, server side (Tomcat), probed with s_client
echo "### Tomcat 11.0.29, Temurin 21, static BCJSSE + namedGroups (server)"
docker run -d --label $L --name javasrv --network $NET -v "$W":/w:ro -v "$KIT":/agent:ro --entrypoint sh $J21 -c \
  "java $STATIC -Djdk.tls.namedGroups=X25519MLKEM768,x25519,secp256r1,secp384r1 -cp '$CP' Probe server tomcat 9443" >/dev/null
docker run --rm --label $L --network $NET pqc-deep-java/ossl bash -c '
  for i in $(seq 60); do (echo > /dev/tcp/javasrv/9443) 2>/dev/null && break; sleep 0.5; done
  for g in X25519MLKEM768 X25519; do r=$(echo | timeout 8 openssl s_client -connect javasrv:9443 -brief -groups $g 2>&1)
    echo "   s_client -groups $g: $(echo "$r" | grep -m1 -oE "group: .*|CONNECTION ESTABLISHED|alert.*")"; done'
docker logs javasrv 2>&1 | grep -m2 -E "^server|Exception" | sed 's/^/   log: /'
docker rm -f javasrv >/dev/null

# --- (b) pgjdbc against PostgreSQL 18
PG=$(digest postgres:18)
for groups in X25519MLKEM768 X25519; do
  docker run -d --label $L --name pg --network $NET -v "$W/certs":/c:ro -e POSTGRES_PASSWORD=pq --entrypoint sh $PG -c "
    cp /c/srv.crt /c/srv.key /tmp/ && chown postgres /tmp/srv.key && chmod 600 /tmp/srv.key &&
    exec docker-entrypoint.sh postgres -c ssl=on -c ssl_cert_file=/tmp/srv.crt -c ssl_key_file=/tmp/srv.key -c ssl_groups=$groups -c ssl_min_protocol_version=TLSv1.3" >/dev/null
  docker run --rm --label $L --network $NET pqc-deep-java/ossl bash -c 'for i in $(seq 60); do (echo > /dev/tcp/pg/5432) 2>/dev/null && break; sleep 0.5; done; sleep 3'
  echo "### PostgreSQL 18 ($PG) ssl_groups=$groups; pgjdbc 42.7.14 sslmode=verify-full (both columns hit the same server)"
  jc $J21 "  Temurin 21 baseline" "" pgjdbc pg 5432 5432
  jc $J21 "  Temurin 21 + BC agent" "-javaagent:/agent/pq-tls-agent.jar" pgjdbc pg 5432 5432
  jc $J25 "  Temurin 25 baseline" "" pgjdbc pg 5432 5432
  docker rm -f pg >/dev/null
done
} 2>&1 | tee "$W/out/static-pg.txt"
