#!/bin/bash
# Cases C, D, E, F for one Node runtime. Usage: run-cases.sh <label> <image@digest> [OPENSSL_CONF value | -]
#   label e.g. node22, node24, lambda22-pq, lambda24-pq, lambda24-aws
# Needs: network node2net, container node2-ossl (OpenSSL 3.5 s_servers on 4431-4434), certs from gen-certs.sh.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
V="$(cd "$(dirname "$0")" && pwd)"; N="$(dirname "$V")"; K="$(cd "$N/../../lambda-pq/layer/pq-tls" && pwd)"
LBL=run=pqc-lang2-node; label=$1; img=$2; conf=${3:--}
envs=(); [ "$conf" != "-" ] && envs=(-e OPENSSL_CONF="$conf")
run() { docker run --rm --label $LBL --network node2net --entrypoint "" -v "$V":/w:ro -v "$N":/n:ro -v "$K":/k:ro "${envs[@]}" "$@" "$img"; }
al() { perl -e 'alarm shift; exec @ARGV' "$@"; }

echo "######## $label  image=$img  OPENSSL_CONF=${conf}"
echo "#### server side (C, E, F): node2-srv probed by openssl s_client 3.5"
docker run -d --label $LBL --name node2-srv --network node2net --network-alias node2srv --entrypoint "" \
  -v "$V":/w:ro -v "$N":/n:ro -v "$K":/k:ro "${envs[@]}" "$img" node /w/srv.cjs >/dev/null
sleep 4; docker logs node2-srv 2>&1 | grep -E '^(node|failed)'
sc() { echo | al 10 docker exec -i node2-ossl openssl s_client -connect node2srv:$1 -CAfile /w/certs/ca.pem -verify_return_error -brief "${@:2}" 2>&1 \
  | grep -E 'Negotiated TLS1.3 group|Peer Temp Key|Peer certificate|Verification|alert|error|refused' | grep -vE 'verify return' \
  | sed -E 's/^(Peer certificate: ).*CN ?= ?([A-Za-z0-9.-]+).*/cert=\2/; s/Negotiated TLS1.3 group: /group=/; s/Peer Temp Key: ([^,]+).*/group=\1 (TLS1.2 or classical)/; s/Verification: /verify=/' | tr '\n' ' '; }
hp() { printf "GET / HTTP/1.0\r\n\r\n" | al 10 docker exec -i node2-ossl openssl s_client -quiet -connect node2srv:$1 -CAfile /w/certs/ca.pem "${@:2}" 2>&1 | grep -oE "cn=[a-z.-]+|alert [a-z ]+" | head -1; }
pq=(-groups X25519MLKEM768 -tls1_3); cl=(-groups X25519:secp256r1)
for p in $(docker logs node2-srv 2>&1 | awk '/^listening/{print $2}'); do
  what=$(docker logs node2-srv 2>&1 | awk -v p=$p '$1=="listening" && $2==p {$1="";$2="";print}')
  echo "-- $p$what"
  case $p in
    9103) echo "   PQ client:        $(sc $p "${pq[@]}")"; echo "   classical client: $(sc $p "${cl[@]}")"
          echo "   RSA-only sigalgs: $(sc $p "${pq[@]}" -sigalgs 'RSA-PSS+SHA256:RSA+SHA256')"
          echo "   ECDSA-only:       $(sc $p "${pq[@]}" -sigalgs 'ECDSA+SHA256')" ;;
    9109|9110|9113) for sn in a.test b.test c.test node2srv; do echo "   SNI $sn PQ: $(sc $p "${pq[@]}" -servername $sn) | classical: $(sc $p "${cl[@]}" -servername $sn)"; done ;;
    9114) echo "   PQ + client cert: $(sc $p "${pq[@]}" -cert /w/certs/client.pem -key /w/certs/client.key) app reply: $(hp $p "${pq[@]}" -cert /w/certs/client.pem -key /w/certs/client.key)"
          echo "   PQ, no cert:      app reply: $(hp $p "${pq[@]}")"
          echo "   classical + cert: $(sc $p "${cl[@]}" -cert /w/certs/client.pem -key /w/certs/client.key)" ;;
    *) echo "   PQ client:        $(sc $p "${pq[@]}")"; echo "   classical client: $(sc $p "${cl[@]}")"; echo "   TLS1.2 client:    $(sc $p -tls1_2)" ;;
  esac
done
docker rm -f node2-srv >/dev/null

echo "#### client side (D, E, F) against s_server PQ-only/classical"
c() { docker rm -f node2-cli >/dev/null 2>&1; al 90 docker run --rm --name node2-cli --label $LBL --network node2net --entrypoint "" -v "$V":/w:ro -v "$N":/n:ro -v "$K":/k:ro "${envs[@]}" "$@" 2>&1 | grep --line-buffered -vE "ExperimentalWarning|trace-warnings"; docker rm -f node2-cli >/dev/null 2>&1; }
c "$img" node /w/cli.cjs trust-none
c "$img" node /w/cli.cjs trust-ca-option
c -e NODE_EXTRA_CA_CERTS=/w/certs/ca.pem "$img" node /w/cli.cjs trust-env
c -e NODE_EXTRA_CA_CERTS=/w/certs/bundle-with-private.pem "$img" node /w/cli.cjs trust-env
c -e SSL_CERT_FILE=/w/certs/bundle-with-private.pem "$img" node --use-openssl-ca /w/cli.cjs trust-env
c -e SSL_CERT_FILE=/w/certs/bundle-with-private.pem "$img" node --use-system-ca /w/cli.cjs trust-env
c -e SSL_CERT_FILE=/w/certs/bundle-with-private.pem -e NODE_USE_SYSTEM_CA=1 "$img" node /w/cli.cjs trust-env
c -e SSL_CERT_FILE=/w/certs/bundle-with-private.pem -e NODE_OPTIONS=--use-openssl-ca "$img" node /w/cli.cjs trust-env
# private CA installed into the image's system trust store (Debian: update-ca-certificates; AL2023: update-ca-trust)
c "$img" sh -c 'if command -v update-ca-certificates >/dev/null; then cp /w/certs/ca.pem /usr/local/share/ca-certificates/private.crt && update-ca-certificates >/dev/null 2>&1; S=debian;
  elif command -v update-ca-trust >/dev/null; then cp /w/certs/ca.pem /etc/pki/ca-trust/source/anchors/private.pem && update-ca-trust extract; S=al2023;
  else S=none; fi; echo "{\"systemStore\":\"$S\"}";
  echo "## --use-system-ca"; node --use-system-ca /w/cli.cjs trust-env; echo "## --use-openssl-ca"; node --use-openssl-ca /w/cli.cjs trust-env; echo "## bundled (default)"; node /w/cli.cjs trust-none'
c "$img" node /w/cli.cjs trust-api
c "$img" node /w/cli.cjs mtls
c "$img" node /w/cli.cjs block
c "$img" node /w/cli.cjs block-defaults
c -e NODE_OPTIONS=--tls-max-v1.2 "$img" node /w/cli.cjs flags
c -e NODE_OPTIONS=--tls-cipher-list=ECDHE-RSA-AES128-GCM-SHA256 "$img" node /w/cli.cjs flags
c -e NODE_OPTIONS=--tls-min-v1.3 "$img" node /w/cli.cjs flags
echo "######## end $label"
