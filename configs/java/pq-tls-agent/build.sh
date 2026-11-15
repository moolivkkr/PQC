#!/bin/bash
set -euo pipefail
BC=1.87
mkdir -p out/pq-tls out/layer/pq-tls out/layer/java/lib out/classes
for a in bcprov bctls bcutil; do
  curl -fsSLo out/pq-tls/$a-jdk18on-$BC.jar \
    https://repo1.maven.org/maven2/org/bouncycastle/$a-jdk18on/$BC/$a-jdk18on-$BC.jar
  want=$(curl -fsSL https://repo1.maven.org/maven2/org/bouncycastle/$a-jdk18on/$BC/$a-jdk18on-$BC.jar.sha1)
  got=$(sha1sum out/pq-tls/$a-jdk18on-$BC.jar | cut -d' ' -f1)
  [ "$want" = "$got" ] || { echo "checksum mismatch: $a"; exit 1; }
done
javac --release 8 -cp "out/pq-tls/*" -d out/classes src/PqTlsAgent.java
jar cfm out/pq-tls/pq-tls-agent.jar MANIFEST.MF -C out/classes PqTlsAgent.class
cp pq-tls.security out/pq-tls/
# Lambda layer: /opt/pq-tls (agent, wrapper, security file) + /opt/java/lib (BC jars)
jar cfm out/layer/pq-tls/pq-tls-agent.jar MANIFEST-layer.MF -C out/classes PqTlsAgent.class
cp pq-tls.security wrapper out/layer/pq-tls/ && chmod 755 out/layer/pq-tls/wrapper
cp out/pq-tls/b*-jdk18on-$BC.jar out/layer/java/lib/
(cd out/layer && zip -qr ../pq-tls-layer.zip .)
tar -czf out/pq-tls-$BC.tgz -C out/pq-tls .
ls -l out/pq-tls out/layer/pq-tls out/pq-tls-layer.zip out/pq-tls-$BC.tgz
