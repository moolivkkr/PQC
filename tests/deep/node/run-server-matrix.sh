#!/bin/bash
# Server-side matrix: Node TLS servers (srv.js) in each image; clients = openssl 3.5 s_client in pqnode-srv.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
D="$(cd "$(dirname "$0")" && pwd)"; L=run=pqc-deep-node
sc() { echo | perl -e 'alarm shift; exec @ARGV' 10 docker exec -i pqnode-srv openssl s_client -connect nodesrv:$1 -CAfile /w/certs/ca.pem -servername nodesrv "${@:2}" -brief 2>&1 | grep -m1 -oE "Negotiated TLS1.3 group: \S+|Peer Temp Key: \S+|alert [a-z ]+|refused|errno=[0-9]+" | tr -d ','; }
for t in "$@"; do dg=$(grep "^$t " "$D/digests.txt" | cut -d' ' -f2)
  docker run -d --label $L --name pqnode-nodesrv --network pqnet-node --network-alias nodesrv -v "$D":/w $dg node /w/srv.js >/dev/null; sleep 5
  echo "## server image $t: $(docker logs pqnode-nodesrv 2>&1 | grep -E '^node|throws' | tr '\n' ' ')"
  for p in 9001 9002 9003 9004 9005 9006 9007 9008; do
    what=$(docker logs pqnode-nodesrv 2>&1 | grep "listening $p " | cut -d' ' -f3-); x=(); [ $p = 9008 ] && x=(-alpn h2)
    printf '%-5s %-36s | PQ-only client: %-40s | classical client: %-24s | default 3.5 client: %s\n' $p "${what:-not started}" \
      "$(sc $p "${x[@]}" -groups X25519MLKEM768 -tls1_3)" "$(sc $p "${x[@]}" -groups X25519:secp256r1)" "$(sc $p "${x[@]}")"
  done
  docker rm -f pqnode-nodesrv >/dev/null; done
