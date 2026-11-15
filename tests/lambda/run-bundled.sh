#!/bin/bash
# Config file shipped inside the deployment package (/var/task), set by env var in IaC. No layer.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"; LBL=run=pqc-lambda-probe
docker network create --label $LBL pqnet-lambda >/dev/null
docker run -d --label $LBL --name pqsrv --network pqnet-lambda -v "$W":/w --entrypoint node public.ecr.aws/lambda/nodejs:24 /w/server.js >/dev/null
port=18760
run() { # image fndir handler conf
  docker run -d --label $LBL --name pqfn-$port --network pqnet-lambda -p 127.0.0.1:$port:8080 -v "$W/fn/$2":/var/task:ro -e OPENSSL_CONF=/var/task/pq-tls/$4 public.ecr.aws/lambda/$1 $3 >/dev/null
  r=$(curl -s --retry-connrefused --retry 20 --retry-delay 1 --max-time 60 -XPOST "http://127.0.0.1:$port/2015-03-31/functions/function/invocations" -d '{}')
  printf '%-12s %s\n' "$1" "$r"; port=$((port+1))
}
for v in 3.12 3.13 3.14; do run python:$v python app.handler openssl-pq.cnf; done
for v in 22 24; do run nodejs:$v node index.handler openssl-pq-node.cnf; done
