#!/bin/bash
# End-to-end test: each Lambda runtime image runs under its built-in Runtime Interface Emulator,
# invoked over HTTP, with and without the pq-tls layer (mounted at /opt) + AWS_LAMBDA_EXEC_WRAPPER.
# Function code is identical in both runs. All TLS traffic stays on a local docker network.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"
LBL=run=pqc-lambda-probe
docker network create --label $LBL pqnet-lambda >/dev/null
docker run -d --label $LBL --name pqsrv --network pqnet-lambda -v "$W":/w --entrypoint node public.ecr.aws/lambda/nodejs:24 /w/server.js >/dev/null
docker run --rm --label $LBL -v "$W/fn/java":/src --entrypoint javac public.ecr.aws/lambda/java:11 --release 11 -d /src /src/Probe.java

port=18601
for spec in python:3.11:python:app.handler python:3.12:python:app.handler python:3.13:python:app.handler python:3.14:python:app.handler \
            nodejs:18:node:index.handler nodejs:20:node:index.handler nodejs:22:node:index.handler nodejs:24:node:index.handler \
            java:11:java:Probe::handleRequest java:17:java:Probe::handleRequest java:21:java:Probe::handleRequest java:25:java:Probe::handleRequest; do
  img=$(echo "$spec" | cut -d: -f1-2); code=$(echo "$spec" | cut -d: -f3); handler=$(echo "$spec" | cut -d: -f4-)
  for mode in baseline layer; do
    args=(-v "$W/fn/$code":/var/task:ro)
    [ "$mode" = layer ] && args+=(-v "$W/layer":/opt:ro -e AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper)
    name=pqfn-$port
    docker run -d --label $LBL --name $name --network pqnet-lambda -p 127.0.0.1:$port:8080 "${args[@]}" public.ecr.aws/lambda/$img "$handler" >/dev/null
    res=$(curl -s --retry-connrefused --retry 20 --retry-delay 1 --max-time 60 -XPOST "http://127.0.0.1:$port/2015-03-31/functions/function/invocations" -d '{}')
    printf '%-14s %-8s %s\n' "$img" "$mode" "$res"
    [ "$mode" = layer ] && docker logs $name 2>&1 | grep -m1 "pq-tls:" | sed 's/^/                        log: /'
    docker rm -f $name >/dev/null
    port=$((port+1))
  done
done
docker rm -f pqsrv >/dev/null
docker network rm pqnet-lambda >/dev/null
