#!/bin/bash
# Tomcat 11.0.29 SSLHostConfig keyManagerAlgorithm, and Spring Boot 3.x SSL bundle (EC PKCS#12),
# both on JDK 21 + pq-tls kit v2 (agent + pq-tls.security).
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
V="$(cd "$(dirname "$0")" && pwd)"
L=run=pqc-lang2-java; N=pqnet-java2
JDK=$(docker image inspect --format '{{index .RepoDigests 0}}' eclipse-temurin:21-jre)
MVN=$(docker image inspect --format '{{index .RepoDigests 0}}' maven:3.9-eclipse-temurin-21)
DEB=$(docker image inspect --format '{{index .RepoDigests 0}}' debian:trixie-slim)
KIT="-Djava.security.properties=/kit/pq-tls/pq-tls.security -javaagent:/kit/pq-tls/pq-tls-agent.jar"
echo "== images: $JDK $MVN"
echo "== build Spring Boot 3.x app"
docker run --rm --label $L --name java2-mvn -v "$V/sb":/sb -v "$V/m2":/root/.m2 "$MVN" sh -ec '
  SB=$(curl -fsSL https://repo1.maven.org/maven2/org/springframework/boot/spring-boot/maven-metadata.xml | grep -oE "<version>3\.5\.[0-9]+</version>" | sed "s/<[^>]*>//g" | sort -t. -k3 -n | tail -1)
  echo "spring boot $SB"; cd /sb && mvn -q -B -Dsb.version=$SB -DskipTests package 2>&1 | tail -5
  ls target/*.jar
  cd /tmp && jar xf /sb/target/sbtls-1.jar BOOT-INF/lib && J=$(ls BOOT-INF/lib/spring-boot-3*.jar) && echo "jar: $J"
  for c in org.springframework.boot.ssl.SslManagerBundle org.springframework.boot.ssl.DefaultSslManagerBundle; do
    echo "$c: $(javap -c -p -cp $J $c 2>/dev/null | grep -oE "KeyManagerFactory.getDefaultAlgorithm|KeyManagerFactory.getInstance|TrustManagerFactory.getDefaultAlgorithm" | sort | uniq -c | tr "\n" " ")"; done'
docker network create --label $L $N >/dev/null 2>&1
docker rm -f java2-ossl java2-jvm >/dev/null 2>&1
docker run -d --label $L --name java2-ossl --network $N -v "$V":/v "$DEB" sleep 600 >/dev/null
docker run -d --label $L --name java2-jvm --network $N --network-alias ks-java \
  -v "$V":/v -v "$V/kit":/kit:ro -v "$V/../lib-new":/deps:ro "$JDK" sleep 600 >/dev/null
docker exec java2-ossl sh -c 'apt-get -qq update >/dev/null 2>&1; apt-get -qq install -y openssl >/dev/null 2>&1'
run() { # port "JAVA_TOOL_OPTIONS" cmd
  docker exec -d -e JAVA_TOOL_OPTIONS="$2" java2-jvm sh -c "$3 > /v/out/tc-$1.log 2>&1"; }
run 9020 "$KIT" 'java -cp "/v/cls:/deps/*" V2Test tomcat /v/c/ec-main.p12 9020 default'
run 9021 "$KIT" 'java -cp "/v/cls:/deps/*" V2Test tomcat /v/c/ec-main.p12 9021 SunX509'
run 9022 "-javaagent:/kit/pq-tls/pq-tls-agent.jar -Dpq.tls.keyManagerAlgorithm=keep" 'java -cp "/v/cls:/deps/*" V2Test tomcat /v/c/ec-main.p12 9022 PKIX'
run 9443 "$KIT" 'java -jar /v/sb/target/sbtls-1.jar'
run 9444 "-javaagent:/kit/pq-tls/pq-tls-agent.jar -Dpq.tls.keyManagerAlgorithm=keep" 'java -jar /v/sb/target/sbtls-1.jar --server.port=9444'
sleep 25
probe() {
  r=$(docker exec java2-ossl sh -c "echo | timeout 8 openssl s_client -connect ks-java:$2 -brief $3 2>&1")
  printf "  %-62s | %-22s | %s %s\n" "$1" "$(echo "$r" | grep -m1 -oE 'group: [A-Za-z0-9]+')" "$(echo "$r" | grep -m1 -oE 'Peer certificate: .*' | grep -oE 'CN ?= ?[a-z-]+')" "$(echo "$r" | grep -m1 -oE 'alert [a-z ]+' | head -1)"; }
echo "== Tomcat 11.0.29 embedded, EC P-256 PKCS#12, JDK 21 + kit v2"
probe "9020 keyManagerAlgorithm not set (kit sets default PKIX)" 9020 ""
probe "9020 same, classical-only client"                         9020 "-groups X25519"
probe "9021 keyManagerAlgorithm=SunX509"                         9021 ""
probe "9022 keyManagerAlgorithm=PKIX, kit fix switched off"      9022 ""
echo "== Spring Boot SSL bundle (jks bundle, PKCS#12 EC), JDK 21"
probe "9443 kit v2 (agent + pq-tls.security)"                    9443 ""
probe "9443 kit v2, classical-only client"                       9443 "-groups X25519"
probe "9444 agent with fix switched off (keep = SunX509)"        9444 ""
for p in 9020 9021 9022 9443 9444; do echo "  $p: $(grep -m1 -E 'pq-tls agent' /dev/stdin < $V/out/tc-$p.log | cut -c1-140) | $(grep -m1 -oE 'keyManagerAlgorithm=[A-Za-z0-9]+|getDefaultAlgorithm\(\)=[A-Za-z0-9]+' $V/out/tc-$p.log)"; done
grep -m2 -hE 'Spring Boot ::|Tomcat started' $V/out/tc-9443.log
docker rm -f java2-ossl java2-jvm >/dev/null; docker network rm $N >/dev/null
echo "left: $(docker ps -a --filter label=$L --format '{{.Names}}' | wc -l | tr -d ' ')"
