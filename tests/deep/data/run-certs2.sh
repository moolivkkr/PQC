#!/bin/bash
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"; D=$(cd "$(dirname "$0")" && pwd); cd "$D"
L="--label run=pqc-deep-data"; NET=pqnet-data; dig() { grep "^$1 " digests.txt | awk '{print $2}' | head -1; }
OSSL=$(dig postgres:18); NGX=$(dig nginx:1.29); PGB=$(dig postgres:18-bookworm); W="-v $D/certs:/work"; T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
docker rm -f web >/dev/null 2>&1
docker run -d $L --name web --network $NET -v $D/certs:/etc/nginx/pki:ro -v $D/certs/nginx-dualcert.conf:/etc/nginx/conf.d/default.conf:ro $NGX >/dev/null; sleep 3
for c in "3.5-default|$OSSL|" "3.5-ecdsa-only|$OSSL|-sigalgs ecdsa_secp256r1_sha256" "3.5-mldsa44-only|$OSSL|-sigalgs mldsa44" "3.0-bookworm-default|$PGB|"; do IFS='|' read n img a <<< "$c"
 echo "--- $n"; T 20 docker run --rm $L --network $NET $W --entrypoint sh $img -c "echo | openssl s_client -connect web:443 -servername web -CAfile /work/roots-both.crt $a 2>&1 | grep -E 'a:PKEY|Peer signature type|Verify return code|Negotiated TLS1.3 group|Server Temp Key' | head -5"; done
docker rm -f web >/dev/null
