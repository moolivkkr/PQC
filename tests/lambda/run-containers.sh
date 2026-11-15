#!/bin/bash
# Container base images (Fargate / ECS / EKS / EC2): which are PQ by default, and what fixes the rest.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"; LBL=run=pqc-lambda-probe
docker network create --label $LBL pqnet-lambda >/dev/null
docker run -d --label $LBL --name pqsrv --network pqnet-lambda -v "$W":/w --entrypoint node public.ecr.aws/lambda/nodejs:24 /w/server.js >/dev/null; sleep 3
r() { local label=$1; shift; out=$(docker run --rm --label $LBL --network pqnet-lambda -v "$W":/w:ro "$@" 2>&1 | grep -E "PQ-only|classical-only|OpenSSL|version|FAIL|OK" | tr '\n' ' '); printf '%-40s %s\n' "$label" "$out"; }
PY='import ssl;print("OpenSSL:",ssl.OPENSSL_VERSION)'
for img in python:3.12-slim-bookworm python:3.12-slim-trixie python:3.11-slim-trixie python:3.12-alpine; do
  r "$img" --entrypoint sh $img -c "python3 -c '$PY'; python3 /w/client.py py"; done
r "amazonlinux:2023 python3 default" --entrypoint sh amazonlinux:2023 -c "python3 -c '$PY'; python3 /w/client.py py"
r "amazonlinux:2023 python3 +OPENSSL_CONF" -e OPENSSL_CONF=/w/layer/pq-tls/openssl-pq.cnf --entrypoint sh amazonlinux:2023 -c "python3 /w/client.py py"
r "amazonlinux:2023 python3 +DEFAULT:PQ" --entrypoint sh amazonlinux:2023 -c "dnf -y -q install crypto-policies-scripts >/dev/null 2>&1; update-crypto-policies --set DEFAULT:PQ >/dev/null 2>&1; python3 /w/client.py py"
for img in node:20-slim node:22-slim node:24-slim node:22-alpine; do
  r "$img" --entrypoint sh $img -c 'node -e "console.log(\"OpenSSL:\",process.version,process.versions.openssl)"; node /w/client.js node'; done
for img in eclipse-temurin:21-jre eclipse-temurin:25-jre amazoncorretto:21 amazoncorretto:25; do
  r "$img" --entrypoint sh $img -c 'java -version 2>&1 | head -1 | sed "s/^/version: /"; cp /w/Client.java /tmp/ && cd /tmp && java Client.java java' ; done
r "amazoncorretto:21 +agent" -e JAVA_TOOL_OPTIONS=-javaagent:/w/layer/pq-tls/pq-tls-agent.jar --entrypoint sh amazoncorretto:21 -c 'cp /w/Client.java /tmp/ && cd /tmp && java Client.java java'
for img in mcr.microsoft.com/dotnet/runtime:8.0 mcr.microsoft.com/dotnet/runtime:8.0-alpine mcr.microsoft.com/dotnet/runtime:10.0 mcr.microsoft.com/dotnet/runtime:10.0-alpine; do
  r "$img" --entrypoint sh $img -c '(. /etc/os-release; echo "version: $PRETTY_NAME"); ls /usr/lib/*/libssl.so.* /usr/lib/libssl.so.* /lib/libssl.so.* 2>/dev/null | sed "s/^/OpenSSL: /" | head -1; dotnet /w/dotnet/out/probe.dll | sed "s/pq_only/PQ-only/"'; done
docker rm -f $(docker ps -aq --filter label=run=pqc-lambda-probe) >/dev/null; docker network rm pqnet-lambda >/dev/null
echo DONE
