#!/bin/bash
# Follow-up: MySQL group behaviour + PQC variables; valkey-cli client offering.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
D=$(cd "$(dirname "$0")" && pwd)
L="--label run=pqc-deep-data"; NET=pqnet-data
dig() { grep "^$1 " "$D/digests.txt" | awk '{print $2}'; }
PG=$(dig postgres:18); MY84=$(dig mysql:8.4); MY9=$(dig mysql:9); VK=$(dig valkey/valkey:8)
T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
sc() { echo "--- s_client $1 groups=$2 $3"
  T 25 docker run --rm $L --network $NET --entrypoint sh $PG -c "echo | openssl s_client -connect $1 -groups $2 $3 -brief 2>&1 | grep -E 'Protocol version|Negotiated TLS1.3 group|Peer Temp Key|Signature type|error|alert|CONNECTION' | head -5"; }
for M in "mysql:8.4 $MY84" "mysql:9 $MY9"; do set -- $M
  echo "=== $1"
  docker rm -f mydb >/dev/null 2>&1
  docker run -d $L --name mydb --network $NET -e MYSQL_ROOT_PASSWORD=pw $2 >/dev/null
  for i in $(seq 1 60); do docker exec mydb mysql -uroot -ppw -e 'select 1' >/dev/null 2>&1 && break; sleep 2; done
  docker exec mydb mysql -uroot -ppw -Ne "show variables like '%kex%'; show variables like '%pqc%'; show variables like 'ssl_ca'" 2>/dev/null
  docker exec mydb sh -c 'openssl x509 -in /var/lib/mysql/server-cert.pem -noout -text | grep -E "Public Key Algorithm|Signature Algorithm" | head -2; cat /etc/crypto-policies/config 2>/dev/null; ls /etc/crypto-policies 2>/dev/null | head'
  sc mydb:3306 P-256 "-starttls mysql"
  sc mydb:3306 X25519:P-256 "-starttls mysql -tls1_2"
  sc mydb:3306 X25519MLKEM768:X25519:P-256:P-384 "-starttls mysql"
  echo "--- mysql client status (client from same image)"
  T 25 docker run --rm $L --network $NET $2 mysql -h mydb -uroot -ppw --ssl-mode=REQUIRED -Ne "show status like 'Ssl_version'; show status like 'Tls_%'" 2>&1 | grep -v Warning
  T 25 docker run --rm $L --network $NET $2 mysql --help 2>/dev/null | grep -iE 'tls-kex|pqc|tls-groups|ssl-ciphers' | head
  docker rm -f mydb >/dev/null
done
echo "=== valkey-cli client offering (PQ-only s_server)"
docker rm -f fakesrv >/dev/null 2>&1
docker run -d $L --name fakesrv --network $NET --entrypoint sh $PG -c "openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 2 -subj /CN=f -keyout /tmp/s.key -out /tmp/s.crt 2>/dev/null; exec stdbuf -oL openssl s_server -accept 6380 -cert /tmp/s.crt -key /tmp/s.key -tls1_3 -groups X25519MLKEM768 -naccept 1" >/dev/null
sleep 2
T 20 docker run --rm $L --network $NET $VK valkey-cli -h fakesrv -p 6380 --tls --insecure PING 2>&1 | head -2
sleep 1; docker logs fakesrv 2>&1 | grep -iE 'protocol|group|cipher|error|ACCEPT' | head -8
docker rm -f fakesrv >/dev/null
echo DONE
