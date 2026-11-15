#!/bin/bash
# BCJSSE as server (agent, JDK 21): does the key type / PKCS12 encoding matter?
#   rsa        RSA-2048 key, OpenSSL 3.5 default PKCS12 (AES-256 + HMAC-SHA256)
#   ec-legacy  same EC P-256 key as the main tests, legacy PKCS12 (3DES + SHA1 MAC)
#   ec-jks     same EC key converted to a JKS-free PKCS12 by keytool (Java's own encoding)
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"
KIT="$W/../../lambda-pq/fn/java-bundled/pq-tls"
L=run=pqc-deep-java
J21=$(docker image inspect --format '{{index .RepoDigests 0}}' eclipse-temurin:21-jre)
mkdir -p "$W/certs-alt/rsa" "$W/certs-alt/ec-legacy" "$W/certs-alt/ec-keytool"
docker run --rm --label $L -v "$W/certs":/c:ro -v "$W/certs-alt":/o pqc-deep-java/ossl sh -ec '
  cd /o/rsa
  openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj /CN=javasrv -addext subjectAltName=DNS:javasrv -keyout k.pem -out c.pem 2>/dev/null
  openssl pkcs12 -export -in c.pem -inkey k.pem -name server -passout pass:changeit -out server.p12
  openssl pkcs12 -export -legacy -in /c/srv.crt -inkey /c/srv.key -name server -passout pass:changeit -out /o/ec-legacy/server.p12
  chmod -R a+rX /o'
docker run --rm --label $L -v "$W/certs":/c:ro -v "$W/certs-alt":/o --entrypoint sh "$J21" -c '
  keytool -importkeystore -srckeystore /c/server.p12 -srcstoretype PKCS12 -srcstorepass changeit \
    -destkeystore /o/ec-keytool/server.p12 -deststoretype PKCS12 -deststorepass changeit -noprompt >/dev/null 2>&1; chmod -R a+rX /o'
for v in rsa ec-legacy ec-keytool; do
  echo "### Tomcat 11.0.29, JDK 21 + agent, keystore=$v"
  docker rm -f javasrv >/dev/null 2>&1
  docker run -d --label $L --name javasrv --network pqnet-java -v "$W":/w:ro -v "$W/certs-alt/$v":/w/certs:ro -v "$KIT":/agent:ro \
    --entrypoint sh "$J21" -c "java -javaagent:/agent/pq-tls-agent.jar -cp /w/classes:/w/lib-new/* Probe server tomcat 9443" >/dev/null
  docker run --rm --label $L --network pqnet-java pqc-deep-java/ossl bash -c '
    for i in $(seq 60); do (echo > /dev/tcp/javasrv/9443) 2>/dev/null && break; sleep 0.5; done; sleep 1
    for g in X25519MLKEM768 X25519; do r=$(echo | timeout 8 openssl s_client -connect javasrv:9443 -brief -groups $g 2>&1)
      echo "   s_client -groups $g: $(echo "$r" | grep -m1 -oE "group: .*|alert [a-z ]+|CONNECTION ESTABLISHED")"; done'
  docker logs javasrv 2>&1 | grep -m1 -E "selectable|TlsFatal" | cut -c1-200 | sed 's/^/   log: /'
  docker rm -f javasrv >/dev/null
done 2>&1 | tee "$W/out/bcserver2.txt"
