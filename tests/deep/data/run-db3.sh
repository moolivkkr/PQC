#!/bin/bash
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"; cd "$(dirname "$0")"; L="--label run=pqc-deep-data"; NET=pqnet-data
PG=$(grep '^postgres:18 ' digests.txt|awk '{print $2}'); VK=$(grep '^valkey/valkey:8 ' digests.txt|awk '{print $2}'); MY=$(grep '^mysql:8.4 ' digests.txt|awk '{print $2}'); T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
for G in X25519 X25519MLKEM768; do echo "=== valkey-cli (trixie) vs s_server -groups $G -trace"
docker rm -f fakesrv >/dev/null 2>&1
docker run -d $L --name fakesrv --network $NET --entrypoint sh $PG -c "openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 2 -subj /CN=f -keyout /tmp/s.key -out /tmp/s.crt 2>/dev/null; sleep 60 | openssl s_server -accept 6380 -cert /tmp/s.crt -key /tmp/s.key -groups $G -naccept 1 -trace" >/dev/null
sleep 2; T 15 docker run --rm $L --network $NET $VK valkey-cli -h fakesrv -p 6380 --tls --insecure PING 2>&1 | head -2
sleep 1; docker logs fakesrv > fakesrv-$G.log 2>&1; grep -A14 'extension_type=supported_groups' fakesrv-$G.log | head -16
docker rm -f fakesrv >/dev/null; done
