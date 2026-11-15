#!/bin/bash
# Server matrix: Java TLS servers x JDK x (baseline | groups setting | BC agent), probed with
# OpenSSL 3.5.7 s_client: PQ-only client, classical-only client, and a default client (offers both).
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"
KIT="$W/../../lambda-pq/fn/java-bundled/pq-tls"
L=run=pqc-deep-java
NET=pqnet-java
docker network inspect $NET >/dev/null 2>&1 || docker network create --label $L $NET >/dev/null
digest() { docker pull -q "$1" >/dev/null; docker image inspect --format '{{index .RepoDigests 0}}' "$1"; }

probe() {
  docker run --rm --label $L --network $NET pqc-deep-java/ossl bash -c '
    for i in $(seq 60); do (echo > /dev/tcp/javasrv/9443) 2>/dev/null && break; sleep 0.5; done
    t() { r=$(echo | timeout 8 openssl s_client -connect javasrv:9443 -servername javasrv -brief "$@" 2>&1);
          g=$(echo "$r" | grep -m1 -o "group: .*" ); p=$(echo "$r" | grep -m1 -o "Protocol version: .*");
          if echo "$r" | grep -q "CONNECTION ESTABLISHED"; then echo "OK   $p $g"; else echo "FAIL $(echo "$r" | grep -m1 -iE "alert|error" | cut -c1-110)"; fi; }
    printf "   %-34s %s\n" "s_client -groups X25519MLKEM768:" "$(t -tls1_3 -groups X25519MLKEM768)"
    printf "   %-34s %s\n" "s_client -groups X25519:" "$(t -groups X25519)"
    printf "   %-34s %s\n" "s_client default (both offered):" "$(t)"'
}

# srv <image> <label> <impl> <JVM opts> [groups]
srv() {
  local d; d=$(digest "$1")
  echo "### $2  [$3]  image=$d  opts=[$4]  groups=[${5:-}]"
  docker rm -f javasrv >/dev/null 2>&1
  docker run -d --label $L --name javasrv --network $NET -v "$W":/w:ro -v "$KIT":/agent:ro --entrypoint sh "$d" -c \
    "java $4 -cp /w/classes:/w/lib-new/* Probe server $3 9443 $5" >/dev/null
  probe
  docker logs javasrv 2>&1 | grep -E "^server|pq-tls agent|netty openssl|Exception" | head -3 | sed 's/^/   log: /'
  docker rm -f javasrv >/dev/null
}

AGENT="-javaagent:/agent/pq-tls-agent.jar"
{
srv eclipse-temurin:25-jre "Tomcat 11.0.29, JDK 25 default" tomcat ""
srv eclipse-temurin:25-jre "Tomcat 11.0.29, JDK 25, SSLHostConfig groups=x25519,secp256r1" tomcat "" "x25519,secp256r1"
srv eclipse-temurin:25-jre "Tomcat 11.0.29, JDK 25, -Djdk.tls.namedGroups=X25519MLKEM768 (PQ-only server)" tomcat "-Djdk.tls.namedGroups=X25519MLKEM768"
srv eclipse-temurin:21-jre "Tomcat 11.0.29, JDK 21 default" tomcat ""
srv eclipse-temurin:21-jre "Tomcat 11.0.29, JDK 21, groups=X25519MLKEM768,x25519" tomcat "" "X25519MLKEM768,x25519"
srv eclipse-temurin:21-jre "Tomcat 11.0.29, JDK 21 + BC agent" tomcat "$AGENT"
srv eclipse-temurin:17-jre "Tomcat 11.0.29, JDK 17 + BC agent" tomcat "$AGENT"
srv eclipse-temurin:25-jre "Jetty 12.1.15, JDK 25 default" jetty ""
srv eclipse-temurin:21-jre "Jetty 12.1.15, JDK 21 default" jetty ""
srv eclipse-temurin:21-jre "Jetty 12.1.15, JDK 21 + BC agent" jetty "$AGENT"
srv eclipse-temurin:25-jre "JDK HttpsServer, JDK 25 default" jdk-httpsserver ""
srv eclipse-temurin:21-jre "Netty 4.2.20 + tcnative-boringssl 2.0.85, default groups" netty-tcnative ""
srv eclipse-temurin:21-jre "Netty 4.2.20 + tcnative-boringssl 2.0.85, GROUPS option" netty-tcnative "" "X25519MLKEM768,X25519"
srv eclipse-temurin:25-jre "Netty 4.2.20 JDK SslProvider, JDK 25" netty-jdk ""
} 2>&1 | tee "$W/out/servers.txt"
