#!/bin/bash
# .NET (OS OpenSSL) in the Lambda dotnet images, and Go (own TLS) built with 1.23 vs current, run in provided.al2023.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"; LBL=run=pqc-lambda-probe
docker run --rm --label $LBL -v "$W/dotnet":/src -w /src mcr.microsoft.com/dotnet/sdk:8.0 sh -c 'dotnet publish -c Release -o /src/out -v q --nologo >/dev/null 2>&1 && echo dotnet-built' 
for v in 1.23 1.24 1.25; do docker run --rm --label $LBL -v "$W/goprobe":/src -w /src -e CGO_ENABLED=0 -e GOFLAGS=-mod=mod golang:$v sh -c "go mod init probe >/dev/null 2>&1; go build -o /src/probe-$v . && echo go$v-built"; done
docker network create --label $LBL pqnet-lambda >/dev/null
docker run -d --label $LBL --name pqsrv --network pqnet-lambda -v "$W":/w --entrypoint node public.ecr.aws/lambda/nodejs:24 /w/server.js >/dev/null; sleep 2
for t in 8 10; do
  for m in default pqconf; do e=(); [ $m = pqconf ] && e=(-e OPENSSL_CONF=/w/layer/pq-tls/openssl-pq.cnf)
    r=$(docker run --rm --label $LBL --network pqnet-lambda -v "$W":/w:ro "${e[@]}" --entrypoint /bin/sh public.ecr.aws/lambda/dotnet:$t -c 'echo "$(openssl version 2>/dev/null || ls /usr/lib64/libssl.so.* 2>/dev/null | head -1)|$(dotnet /w/dotnet/out/probe.dll)"')
    printf 'dotnet:%-3s %-8s %s\n' $t $m "$r"; done; done
for v in 1.23 1.24 1.25; do printf 'go%-5s provided.al2023 %s\n' $v "$(docker run --rm --label $LBL --network pqnet-lambda -v "$W/goprobe":/g:ro --entrypoint /g/probe-$v public.ecr.aws/lambda/provided:al2023)"; done
docker rm -f $(docker ps -aq --filter label=run=pqc-lambda-probe) >/dev/null; docker network rm pqnet-lambda >/dev/null
