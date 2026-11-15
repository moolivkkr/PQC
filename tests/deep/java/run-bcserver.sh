#!/bin/bash
# Diagnose BCJSSE as a TLS server (agent on JDK 21): default KeyManagerFactory (SunX509) vs
# -Dssl.KeyManagerFactory.algorithm=PKIX (BCJSSE's key manager), Tomcat and Jetty.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"
KIT="$W/../../lambda-pq/fn/java-bundled/pq-tls"
L=run=pqc-deep-java
NET=pqnet-java
docker network inspect $NET >/dev/null 2>&1 || docker network create --label $L $NET >/dev/null
J21=$(docker image inspect --format '{{index .RepoDigests 0}}' eclipse-temurin:21-jre)
J17=$(docker image inspect --format '{{index .RepoDigests 0}}' eclipse-temurin:17-jre)
printf 'handlers=java.util.logging.ConsoleHandler\njava.util.logging.ConsoleHandler.level=ALL\norg.bouncycastle.jsse.level=FINE\n' > "$W/bc-logging.properties"
srv() { # image label impl opts
  echo "### $2"
  docker rm -f javasrv >/dev/null 2>&1
  docker run -d --label $L --name javasrv --network $NET -v "$W":/w:ro -v "$KIT":/agent:ro --entrypoint sh "$1" -c \
    "java -javaagent:/agent/pq-tls-agent.jar $4 -cp /w/classes:/w/lib-new/* Probe server $3 9443" >/dev/null
  docker run --rm --label $L --network $NET pqc-deep-java/ossl bash -c '
    for i in $(seq 60); do (echo > /dev/tcp/javasrv/9443) 2>/dev/null && break; sleep 0.5; done
    for g in X25519MLKEM768 X25519; do r=$(echo | timeout 8 openssl s_client -connect javasrv:9443 -brief -groups $g 2>&1)
      echo "   s_client -groups $g: $(echo "$r" | grep -m1 -oE "group: .*|alert [a-z ]+" || echo "$r" | head -1)"; done'
  docker logs javasrv 2>&1 | grep -iE "warn|sever|exception|no credentials|alias|cipher suite" | sort | uniq -c | head -6 | cut -c1-220 | sed 's/^/   log: /'
  docker rm -f javasrv >/dev/null
}
{
srv $J21 "Tomcat, JDK 21 + agent, default KMF, BC logging" tomcat "-Djava.util.logging.config.file=/w/bc-logging.properties"
srv $J21 "Tomcat, JDK 21 + agent, ssl.KeyManagerFactory.algorithm=PKIX" tomcat "-Dssl.KeyManagerFactory.algorithm=PKIX"
srv $J21 "Jetty, JDK 21 + agent, ssl.KeyManagerFactory.algorithm=PKIX" jetty "-Dssl.KeyManagerFactory.algorithm=PKIX"
srv $J21 "JDK HttpsServer, JDK 21 + agent, ssl.KeyManagerFactory.algorithm=PKIX" jdk-httpsserver "-Dssl.KeyManagerFactory.algorithm=PKIX"
srv $J17 "Tomcat, JDK 17 + agent, ssl.KeyManagerFactory.algorithm=PKIX" tomcat "-Dssl.KeyManagerFactory.algorithm=PKIX"
} 2>&1 | tee "$W/out/bcserver.txt"
