#!/bin/bash
# Java 8/11/17 on the AL2023 Lambda images, with and without the pq-tls layer.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"
LBL=run=pqc-lambda-probe
# Recompile probe and agent for Java 8 bytecode so one build runs on every JDK.
docker run --rm --label $LBL -v "$W":/w --entrypoint /bin/sh public.ecr.aws/lambda/java:11 -c \
  'javac --release 8 -d /w/fn/java /w/fn/java/Probe.java && cd /w/agent && javac --release 8 -cp "/w/layer/java/lib/*" -d . PqTlsAgent.java && jar cfm /w/layer/pq-tls/pq-tls-agent.jar MANIFEST.MF PqTlsAgent.class' || exit 1
docker network inspect pqnet-lambda >/dev/null 2>&1 || docker network create --label $LBL pqnet-lambda >/dev/null
docker inspect pqsrv >/dev/null 2>&1 || docker run -d --label $LBL --name pqsrv --network pqnet-lambda -v "$W":/w --entrypoint node public.ecr.aws/lambda/nodejs:24 /w/server.js >/dev/null
port=18670
for t in 8.al2023 11.al2023 17.al2023 21 25; do
  for mode in baseline layer; do
    args=(-v "$W/fn/java":/var/task:ro)
    [ "$mode" = layer ] && args+=(-v "$W/layer":/opt:ro -e AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper)
    docker run -d --label $LBL --name pqfn-$port --network pqnet-lambda -p 127.0.0.1:$port:8080 "${args[@]}" public.ecr.aws/lambda/java:$t Probe::handleRequest >/dev/null
    res=$(curl -s --retry-connrefused --retry 20 --retry-delay 1 --max-time 60 -XPOST "http://127.0.0.1:$port/2015-03-31/functions/function/invocations" -d '{}')
    printf '%-14s %-8s %s\n' "java:$t" "$mode" "$res"
    [ "$mode" = layer ] && docker logs pqfn-$port 2>&1 | grep -m1 "pq-tls" | sed 's/^/      log: /'
    docker stop pqfn-$port >/dev/null
    port=$((port+1))
  done
done
