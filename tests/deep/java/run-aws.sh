#!/bin/bash
# AWS SDK for Java v2 HTTP clients (+ Netty tcnative, JDK 25 HttpClient for reference) against nginx
# with a PQ-only listener (:8443) and a classical-only listener (:8444). nginx logs the negotiated
# group per request ($ssl_curve), which is the server-side evidence.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"
KIT="$W/../../lambda-pq/fn/java-bundled/pq-tls"
L=run=pqc-deep-java
NET=pqnet-java
docker network inspect $NET >/dev/null 2>&1 || docker network create --label $L $NET >/dev/null
digest() { docker pull -q "$1" >/dev/null; docker image inspect --format '{{index .RepoDigests 0}}' "$1"; }
NG=$(digest nginx:latest)
docker rm -f pqsrv >/dev/null 2>&1
docker run -d --label $L --name pqsrv --network $NET -v "$W/certs":/c:ro -v "$W/nginx-pq.conf":/etc/nginx/nginx.conf:ro "$NG" >/dev/null
TRUST="-Djavax.net.ssl.trustStore=/w/certs/trust.p12 -Djavax.net.ssl.trustStorePassword=changeit -Djavax.net.ssl.trustStoreType=PKCS12"
run() { # image label lib-dir opts libs
  local d; d=$(digest "$1")
  echo "### $2  image=$d opts=[$4]"
  docker run --rm --label $L --network $NET -v "$W":/w:ro -v "$KIT":/agent:ro --entrypoint sh "$d" -c "
    cp /w/certs/ca.crt /usr/local/share/ca-certificates/pq-test-ca.crt && update-ca-certificates >/dev/null 2>&1
    for l in $5; do java $TRUST $4 -Daws.java.v2.log=off -cp /w/classes:/w/$3/* Probe client \$l pqsrv 8443 8444 2>/dev/null; done"
  docker logs pqsrv 2>/dev/null | grep 'group=' | tail -n +$((SEEN+1)) | cut -c1-200 | sed 's/^/   srv: /'
  SEEN=$(docker logs pqsrv 2>/dev/null | grep -c 'group=')
}
SEEN=0
{
echo "nginx: $NG ($(docker exec pqsrv nginx -V 2>&1 | grep -o 'OpenSSL [0-9.]*' | head -1))"
run eclipse-temurin:17-jre "Temurin 17 baseline, SDK 2.59.1" lib-new "" "aws-apache aws-netty aws-crt netty-tcnative"
run eclipse-temurin:21-jre "Temurin 21 baseline, SDK 2.59.1" lib-new "" "aws-apache aws-netty aws-crt"
run eclipse-temurin:21-jre "Temurin 21 + BC agent, SDK 2.59.1" lib-new "-javaagent:/agent/pq-tls-agent.jar" "aws-apache aws-netty aws-crt"
run eclipse-temurin:25-jre "Temurin 25 baseline, SDK 2.59.1" lib-new "" "aws-apache aws-netty aws-crt jdk-httpclient"
run eclipse-temurin:21-jre "Temurin 21 baseline, SDK 2.35.10 / aws-crt 0.38.9" lib-old "" "aws-crt"
echo "### nginx access log (group per request)"
docker logs pqsrv 2>/dev/null | grep -E 'group=' | sed -E 's/^([0-9.]+) /\1 /' | sort | uniq -c
} 2>&1 | tee "$W/out/aws.txt"
docker rm -f pqsrv >/dev/null
