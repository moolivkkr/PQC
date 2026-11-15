#!/bin/bash
# Valkey 8 (trixie) with OPENSSL_CONF: PQ-first list and PQ-only enforcement.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"; D=$(cd "$(dirname "$0")" && pwd); cd "$D"
L="--label run=pqc-deep-data"; NET=pqnet-data; dig() { grep "^$1 " digests.txt | awk '{print $2}' | head -1; }
PG=$(dig postgres:18); VK=$(dig valkey/valkey:8); T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
sc() { echo "--- s_client groups=$1"; T 20 docker run --rm $L --network $NET --entrypoint sh $PG -c "echo | openssl s_client -connect vk:6380 -groups $1 2>&1 | grep -E 'Negotiated TLS1.3 group|Peer Temp Key|alert' | head -2"; }
T 30 docker run --rm $L -v $D/conf:/conf --entrypoint sh $PG -c 'openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 2 -subj /CN=vk -keyout /conf/vk.key -out /conf/vk.crt 2>/dev/null; chmod 644 /conf/vk.key'
for C in openssl-groups.cnf openssl-pq-only.cnf; do echo "=== valkey with OPENSSL_CONF=$C"
  docker rm -f vk >/dev/null 2>&1
  docker run -d $L --name vk --network $NET -v $D/conf:/etc/valkey-tls:ro -e OPENSSL_CONF=/etc/valkey-tls/$C $VK \
    valkey-server --port 0 --tls-port 6380 --tls-cert-file /etc/valkey-tls/vk.crt --tls-key-file /etc/valkey-tls/vk.key --tls-auth-clients no >/dev/null
  sleep 3
  sc X25519MLKEM768; sc X25519; sc X25519:X25519MLKEM768
done
docker rm -f vk >/dev/null; rm -f conf/vk.key conf/vk.crt
