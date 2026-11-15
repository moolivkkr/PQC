#!/bin/bash
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"; LBL=run=pqc-lambda-probe
# Per-version site-packages in the layer (cffi is version-specific), installed inside each Lambda image.
for v in 3.9 3.10 3.11; do
  [ -d "$W/layer/python/lib/python$v/site-packages/OpenSSL" ] || docker run --rm --label $LBL -v "$W/layer":/out --entrypoint /bin/sh public.ecr.aws/lambda/python:$v -c \
    "pip install -q --disable-pip-version-check --target /out/python/lib/python$v/site-packages pyopenssl cryptography 2>&1 | tail -2"
done
docker network create --label $LBL pqnet-lambda >/dev/null
docker run -d --label $LBL --name pqsrv --network pqnet-lambda -v "$W":/w --entrypoint node public.ecr.aws/lambda/nodejs:24 /w/server.js >/dev/null
port=18740
for v in 3.9 3.10 3.11; do for mode in baseline layer; do
  args=(-v "$W/fn/py-legacy":/var/task:ro)
  [ $mode = layer ] && args+=(-v "$W/layer":/opt:ro -e AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper)
  docker run -d --label $LBL --name pqfn-$port --network pqnet-lambda -p 127.0.0.1:$port:8080 "${args[@]}" public.ecr.aws/lambda/python:$v app.handler >/dev/null
  r=$(curl -s --retry-connrefused --retry 20 --retry-delay 1 --max-time 90 -XPOST "http://127.0.0.1:$port/2015-03-31/functions/function/invocations" -d '{}')
  printf '%-5s %-8s %s\n' "$v" "$mode" "$r"
  [ $mode = layer ] && docker logs pqfn-$port 2>&1 | grep "pq-tls" | sed 's/^/      log: /'
  port=$((port+1))
done; done
