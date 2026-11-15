#!/bin/bash
# Lambda nodejs22/24 base images under the Runtime Interface Emulator (real /var/runtime/bootstrap):
# NODE_EXTRA_CA_CERTS + the PQ OPENSSL_CONF override, against PQ-only s_servers (node2-ossl).
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
V="$(cd "$(dirname "$0")" && pwd)"; port=18661
for v in 22 24; do
  img=$(grep "^lambda/nodejs:$v " "$V/digests.txt" | cut -d' ' -f2)
  for mode in pq+xca aws+xca pq-noxca; do
    env=()
    case $mode in
      pq+xca)   env=(-e OPENSSL_CONF=/var/task/pq-tls/openssl-pq-node.cnf -e NODE_EXTRA_CA_CERTS=/var/task/certs/ca.pem) ;;
      aws+xca)  env=(-e NODE_EXTRA_CA_CERTS=/var/task/certs/ca.pem) ;;
      pq-noxca) env=(-e OPENSSL_CONF=/var/task/pq-tls/openssl-pq-node.cnf) ;;
    esac
    docker run -d --label run=pqc-lang2-node --name node2-fn --network node2net -p 127.0.0.1:$port:8080 -v "$V/fn":/var/task:ro "${env[@]}" "$img" index.handler >/dev/null
    res=$(curl -s --retry-connrefused --retry 20 --retry-delay 1 --max-time 60 -XPOST "http://127.0.0.1:$port/2015-03-31/functions/function/invocations" -d '{}')
    printf 'nodejs%-3s %-9s %s\n' "$v" "$mode" "$res"
    docker rm -f node2-fn >/dev/null; port=$((port+1))
  done
done
