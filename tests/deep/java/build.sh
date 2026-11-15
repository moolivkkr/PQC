#!/bin/bash
# Compile the probe (Java 17 bytecode) and copy dependencies, for two AWS SDK versions.
set -e
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"
L=run=pqc-deep-java
IMG=maven:3.9-eclipse-temurin-21
docker pull -q $IMG >/dev/null
D=$(docker image inspect --format '{{index .RepoDigests 0}}' $IMG); echo "maven image: $D"
for spec in new:2.59.1:0.50.0 old:2.35.10:0.38.9; do
  IFS=: read tag sdk crt <<<"$spec"
  docker run --rm --label $L -v "$W/probe":/p -v "$W/m2":/root/.m2 -v "$W":/w -w /p "$D" sh -ec "
    mvn -q -B -Daws.sdk.version=$sdk -Dcrt.version=$crt -DoutputDirectory=/w/lib-$tag compile dependency:copy-dependencies
    rm -rf /w/classes && cp -r target/classes /w/classes"
  echo "built lib-$tag (sdk $sdk, aws-crt $crt): $(ls "$W/lib-$tag" | wc -l) jars"
done
