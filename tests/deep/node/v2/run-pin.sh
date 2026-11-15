#!/bin/bash
# Case I: SPKI pinning with the PQ setup, on 4 runtimes. Needs node2-ossl (start-ossl.sh).
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
V="$(cd "$(dirname "$0")" && pwd)"; K="$(cd "$V/../../../lambda-pq/layer/pq-tls" && pwd)"
d() { grep "^$1 " "$V/digests.txt" | cut -d' ' -f2; }
while read -r lab img conf; do
  e=(); [ "$conf" != "-" ] && e=(-e "OPENSSL_CONF=$conf")
  echo "## $lab"
  perl -e 'alarm 60; exec @ARGV' docker run --rm --name node2-cli --label run=pqc-lang2-node --network node2net --entrypoint "" \
    -v "$V":/w:ro -v "$K":/k:ro "${e[@]}" "$img" node /w/pin.cjs
done <<LIST
node22 $(d node:22) -
node24 $(d node:24) -
lambda22-pq $(d lambda/nodejs:22) /k/openssl-pq-node.cnf
lambda24-pq $(d lambda/nodejs:24) /k/openssl-pq-node.cnf
LIST
