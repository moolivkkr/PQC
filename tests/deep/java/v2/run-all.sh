#!/bin/bash
V="$(cd "$(dirname "$0")" && pwd)"
for r in "eclipse-temurin:21-jre v1file" "eclipse-temurin:21-jre v2agent" "eclipse-temurin:21-jre v2kit" "eclipse-temurin:17-jre v1nofix" "eclipse-temurin:17-jre v2kit" "eclipse-temurin:25-jre none"; do
  set -- $r; t=$(echo $1 | sed 's/eclipse-temurin://;s/-jre//')
  perl -e 'alarm shift; exec @ARGV' 280 bash "$V/run-v2.sh" $1 $2 > "$V/out/t$t-$2.txt" 2>&1
done
echo ALLDONE
