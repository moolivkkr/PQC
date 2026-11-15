#!/bin/bash
# Lambda nodejs22/24 base images under the built-in Runtime Interface Emulator (real /var/runtime/bootstrap),
# invoked over HTTP. Function code = kit fn/node/index.js (reads pqsrv:8443 PQ-only, :8444 classical-only).
# Modes: baseline | OPENSSL_CONF to the file shipped in /var/task | NODE_OPTIONS=--openssl-config | OPENSSL_CONF=/dev/null
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
D="$(cd "$(dirname "$0")" && pwd)"; L=run=pqc-deep-node
FN=/private/tmp/claude-501/-Users-kishoremooli-development-cybersecurity/21fa377a-bc06-46f9-9e49-4588545ba6c2/scratchpad/lambda-pq/fn/node
mkdir -p "$D/fn" && cp "$FN/index.js" "$D/fn/" && mkdir -p "$D/fn/pq-tls" && cp "$D/conf/openssl-pq-node.cnf" "$D/fn/pq-tls/"
port=18651
for v in 22 24; do
  img=$(grep "^public.ecr.aws/lambda/nodejs:$v " "$D/digests.txt" | cut -d' ' -f2)
  for mode in baseline conf node_options devnull; do
    env=()
    case $mode in
      conf) env=(-e OPENSSL_CONF=/var/task/pq-tls/openssl-pq-node.cnf) ;;
      node_options) env=(-e NODE_OPTIONS=--openssl-config=/var/task/pq-tls/openssl-pq-node.cnf) ;;
      devnull) env=(-e OPENSSL_CONF=/dev/null) ;;
    esac
    name=pqnode-fn-$port
    docker run -d --label $L --name $name --network pqnet-node -p 127.0.0.1:$port:8080 -v "$D/fn":/var/task:ro "${env[@]}" "$img" index.handler >/dev/null
    res=$(curl -s --retry-connrefused --retry 20 --retry-delay 1 --max-time 60 -XPOST "http://127.0.0.1:$port/2015-03-31/functions/function/invocations" -d '{}')
    printf 'nodejs%-3s %-13s %s\n' "$v" "$mode" "$res"
    docker rm -f $name >/dev/null
    port=$((port+1))
  done
done
