#!/bin/bash
# MySQL 26 (PQC variables) and MariaDB latest (Ubuntu 26.04, OpenSSL 3.5)
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"; cd "$(dirname "$0")"; L="--label run=pqc-deep-data"; NET=pqnet-data
dig() { grep "^$1 " digests.txt | awk '{print $2}' | head -1; }
PG=$(dig postgres:18); MY=$(dig mysql:26); MDB=$(dig mariadb:latest); T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
sc() { echo "--- s_client $1 groups=$2 $3"; T 25 docker run --rm $L --network $NET --entrypoint sh $PG -c "echo | openssl s_client -connect $1 -groups $2 $3 2>&1 | grep -E '^Protocol|Negotiated TLS1.3 group|Peer Temp Key|alert|CONNECTED' | head -4"; }
echo "=== mysql:26"
docker rm -f mydb >/dev/null 2>&1
docker run -d $L --name mydb --network $NET -e MYSQL_ROOT_PASSWORD=pw $MY >/dev/null
for i in $(seq 1 60); do docker exec mydb mysql -uroot -ppw -e 'select 1' >/dev/null 2>&1 && break; sleep 2; done
docker exec mydb mysql -uroot -ppw -Ne "select @@version; show variables like '%kex%'; show variables like '%pqc%'" 2>/dev/null
sc mydb:3306 X25519MLKEM768 "-starttls mysql -tls1_3"
sc mydb:3306 X25519 "-starttls mysql"
sc mydb:3306 P-256 "-starttls mysql"
echo "--- mysql 26 client (default) status"
T 25 docker run --rm $L --network $NET $MY mysql -h mydb -uroot -ppw --ssl-mode=REQUIRED -Ne "show session status like 'Tls_key_exchange_algorithm'; show session status like 'Tls_sign_algorithm'; show session status like 'Ssl_version'" 2>&1 | grep -v Warning
echo "--- force_pqc=ON then classical client"
docker exec mydb mysql -uroot -ppw -Ne "SET PERSIST force_pqc=ON; select @@force_pqc" 2>&1 | grep -v Warning
sc mydb:3306 X25519 "-starttls mysql"
sc mydb:3306 X25519MLKEM768 "-starttls mysql"
T 25 docker run --rm $L --network $NET $MY mysql -h mydb -uroot -ppw --ssl-mode=REQUIRED --tls-kex=X25519 -Ne "select 'classical-client-connected'" 2>&1 | grep -v Warning
T 25 docker run --rm $L --network $NET $MY mysql --help 2>/dev/null | grep -E 'tls-kex|force-pqc|use-pqc' | head -5
docker rm -f mydb >/dev/null
echo "=== mariadb:latest"
docker rm -f mdb >/dev/null 2>&1
docker run -d $L --name mdb --network $NET -e MARIADB_ROOT_PASSWORD=pw $MDB >/dev/null
for i in $(seq 1 60); do docker exec mdb mariadb -uroot -ppw -e 'select 1' >/dev/null 2>&1 && break; sleep 2; done
docker exec mdb mariadb -uroot -ppw -Ne "select @@version, @@have_ssl, @@tls_version, @@version_ssl_library; show variables like '%curve%'; show variables like '%group%' " 2>&1 | grep -iE 'maria|curve|ssl_|tls' | head
sc mdb:3306 X25519MLKEM768 "-starttls mysql -tls1_3"
sc mdb:3306 X25519 "-starttls mysql"
echo "--- mariadb client"
T 25 docker run --rm $L --network $NET $MDB mariadb -h mdb -uroot -ppw --ssl --ssl-verify-server-cert=0 -Ne "show session status like 'Ssl_version'; show session status like 'Ssl_cipher'" 2>&1
docker rm -f mdb >/dev/null
echo DONE
