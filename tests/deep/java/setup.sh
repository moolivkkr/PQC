#!/bin/bash
# Build the probe and test PKI. Everything runs in containers; nothing is installed on the host.
set -e
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"
L=run=pqc-deep-java
mkdir -p "$W/certs" "$W/m2" "$W/out"

# 1. Test CA + server cert (SAN pqsrv, javasrv, pg) + Java trust store + server PKCS12.
docker run --rm --label $L -v "$W/certs":/c pqc-deep-java/ossl sh -ec '
cd /c
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 -subj /CN=pq-test-ca -keyout ca.key -out ca.crt 2>/dev/null
openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj /CN=pqsrv -keyout srv.key -out srv.csr 2>/dev/null
printf "subjectAltName=DNS:pqsrv,DNS:javasrv,DNS:pg\nextendedKeyUsage=serverAuth\n" > ext.cnf
openssl x509 -req -in srv.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 30 -extfile ext.cnf -out srv.crt 2>/dev/null
openssl pkcs12 -export -in srv.crt -inkey srv.key -certfile ca.crt -name server -passout pass:changeit -out server.p12
openssl pkcs12 -export -nokeys -in ca.crt -jdktrust anyExtendedKeyUsage -passout pass:changeit -out trust.p12
chmod 644 *; ls'

# 2. Which aws-crt version does each SDK release pin?
docker run --rm --label $L pqc-deep-java/ossl sh -c '
for v in 2.35.10 2.35.11 2.59.1; do printf "sdk %s awscrt " $v; curl -s https://repo1.maven.org/maven2/software/amazon/awssdk/aws-sdk-java-pom/$v/aws-sdk-java-pom-$v.pom | grep -o "<awscrt.version>[^<]*" | sed "s/<awscrt.version>//"; done' | tee "$W/out/crt-versions.txt"
