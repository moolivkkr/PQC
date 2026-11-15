#!/bin/bash
# No layer: can OPENSSL_CONF=/dev/null alone enable PQ for Python 3.12+/Node 22+ on Lambda?
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"; LBL=run=pqc-lambda-probe
docker network create --label $LBL pqnet-lambda >/dev/null
docker run -d --label $LBL --name pqsrv --network pqnet-lambda -v "$W":/w --entrypoint node public.ecr.aws/lambda/nodejs:24 /w/server.js >/dev/null
port=18720
run() { # image dir handler mode
  args=(-v "$W/fn/$2":/var/task:ro); [ "$4" = devnull ] && args+=(-e OPENSSL_CONF=/dev/null)
  docker run -d --label $LBL --name pqfn-$port --network pqnet-lambda -p 127.0.0.1:$port:8080 "${args[@]}" public.ecr.aws/lambda/$1 $3 >/dev/null
  r=$(curl -s --retry-connrefused --retry 20 --retry-delay 1 --max-time 60 -XPOST "http://127.0.0.1:$port/2015-03-31/functions/function/invocations" -d '{}')
  printf '%-12s %-8s %s\n' "$1" "$4" "$r"; port=$((port+1))
}
for img in python:3.12 python:3.14; do for m in none devnull; do run $img python app.handler $m; done; done
for img in nodejs:22 nodejs:24; do for m in none devnull; do run $img node index.handler $m; done; done
