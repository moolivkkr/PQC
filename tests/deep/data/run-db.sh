#!/bin/bash
# PQ TLS tests for PostgreSQL 18, MySQL 8.4/9, MariaDB 11.8, Valkey 8.
# Usage: bash run-db.sh > db-results.txt 2>&1
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
D=$(cd "$(dirname "$0")" && pwd)
L="--label run=pqc-deep-data"
NET=pqnet-data
dig() { grep "^$1 " "$D/digests.txt" | awk '{print $2}'; }
PG=$(dig postgres:18); PGB=$(dig postgres:18-bookworm); MY84=$(dig mysql:8.4); MY9=$(dig mysql:9)
MDB=$(dig mariadb:11.8); VK=$(dig valkey/valkey:8); VKA=$(dig valkey/valkey:8-alpine); TRX=$(dig postgres:18)
T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
docker network create $L $NET >/dev/null 2>&1
# s_client from the postgres:18 (trixie, OpenSSL 3.5.7) image
sc() { # $1 host:port $2 groups $3 extra
  echo "--- s_client $1 groups=$2 $3"
  T 25 docker run --rm $L --network $NET --entrypoint sh $TRX -c "echo | openssl s_client -connect $1 -groups $2 $3 -brief 2>&1 | grep -E 'Protocol version|Negotiated TLS1.3 group|Peer Temp Key|error|alert|CONNECTION' | head -5"
}

pgrun() { # $1 name $2 ssl_groups (empty = default)
  local G=""; [ -n "$2" ] && G="-c ssl_groups=$2"
  docker rm -f $1 >/dev/null 2>&1
  docker run -d $L --name $1 --network $NET -e POSTGRES_PASSWORD=pw --entrypoint sh $PG -c "
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 2 -subj /CN=$1 -keyout /tmp/s.key -out /tmp/s.crt 2>/dev/null
    chown postgres /tmp/s.key /tmp/s.crt; chmod 600 /tmp/s.key
    exec docker-entrypoint.sh postgres -c ssl=on -c ssl_cert_file=/tmp/s.crt -c ssl_key_file=/tmp/s.key -c log_connections=on $G" >/dev/null
  for i in $(seq 1 30); do docker exec $1 pg_isready -U postgres -h 127.0.0.1 >/dev/null 2>&1 && break; sleep 1; done
}
psqlc() { # $1 image $2 host $3 label
  echo "--- psql ($3) -> $2"
  T 25 docker run --rm $L --network $NET -e PGPASSWORD=pw $1 psql "host=$2 user=postgres sslmode=require connect_timeout=5" -Atc "select 'connected', version, cipher from pg_stat_ssl where pid=pg_backend_pid()" 2>&1 | head -3
}

echo "=== PostgreSQL 18 (trixie, OpenSSL 3.5.7) default ssl_groups"
pgrun pgdef ""
docker exec pgdef psql -U postgres -Atc "show ssl_groups; show ssl_min_protocol_version; show ssl_ecdh_curve" 2>&1
sc pgdef:5432 X25519MLKEM768 "-starttls postgres -tls1_3"
sc pgdef:5432 X25519 "-starttls postgres"
psqlc $PG pgdef "trixie libpq"
docker rm -f pgdef >/dev/null

echo "=== PostgreSQL 18 ssl_groups=X25519MLKEM768:X25519:prime256v1 (PQ first)"
pgrun pgpq "X25519MLKEM768:X25519:prime256v1"
docker exec pgpq psql -U postgres -Atc "show ssl_groups" 2>&1
sc pgpq:5432 X25519MLKEM768 "-starttls postgres -tls1_3"
sc pgpq:5432 X25519MLKEM768:X25519 "-starttls postgres"
sc pgpq:5432 X25519 "-starttls postgres"
psqlc $PG pgpq "trixie libpq"
psqlc $PGB pgpq "bookworm libpq OpenSSL 3.0"
echo "--- server log connection lines"; docker logs pgpq 2>&1 | grep -E 'connection authorized' | tail -2
docker rm -f pgpq >/dev/null

echo "=== PostgreSQL 18 ssl_groups=X25519MLKEM768 (PQ only)"
pgrun pgonly "X25519MLKEM768"
sc pgonly:5432 X25519 "-starttls postgres"
psqlc $PG pgonly "trixie libpq (proves client offers ML-KEM)"
psqlc $PGB pgonly "bookworm libpq OpenSSL 3.0 (expect fail)"
docker rm -f pgonly >/dev/null

for M in "mysql:8.4 $MY84" "mysql:9 $MY9"; do set -- $M
  echo "=== $1 (Oracle Linux 9.8, OpenSSL 3.5.8) default config"
  docker rm -f mydb >/dev/null 2>&1
  docker run -d $L --name mydb --network $NET -e MYSQL_ROOT_PASSWORD=pw $2 >/dev/null
  for i in $(seq 1 60); do docker exec mydb mysql -uroot -ppw -e 'select 1' >/dev/null 2>&1 && break; sleep 2; done
  docker exec mydb mysql -uroot -ppw -Ne "select @@version; show variables like 'tls_%'; show variables like 'ssl_%'" 2>/dev/null | grep -vE 'ssl_(ca|capath|crl|crlpath|key|cert)\b'
  sc mydb:3306 X25519MLKEM768 "-starttls mysql -tls1_3"
  sc mydb:3306 X25519 "-starttls mysql"
  echo "--- mysql client (same image) status"
  T 25 docker run --rm $L --network $NET $2 mysql -h mydb -uroot -ppw --ssl-mode=REQUIRED -Ne "show status like 'Ssl_version'; show status like 'Ssl_cipher'" 2>/dev/null
  docker rm -f mydb >/dev/null
done

echo "=== mariadb:11.8 (Ubuntu 24.04, OpenSSL 3.0.13)"
docker rm -f mdb >/dev/null 2>&1
docker run -d $L --name mdb --network $NET -e MARIADB_ROOT_PASSWORD=pw $MDB >/dev/null
for i in $(seq 1 60); do docker exec mdb mariadb -uroot -ppw -e 'select 1' >/dev/null 2>&1 && break; sleep 2; done
docker exec mdb mariadb -uroot -ppw -Ne "select @@version, @@have_ssl, @@tls_version" 2>&1
sc mdb:3306 X25519MLKEM768 "-starttls mysql -tls1_3"
sc mdb:3306 X25519 "-starttls mysql"
docker rm -f mdb >/dev/null

for V in "valkey:8-trixie $VK" "valkey:8-alpine $VKA"; do set -- $V
  echo "=== $1 TLS"
  docker rm -f vk >/dev/null 2>&1
  docker run -d $L --name vk --network $NET --entrypoint sh $PG -c "sleep 1" >/dev/null 2>&1; docker rm -f vk >/dev/null 2>&1
  docker run -d $L --name vk --network $NET --entrypoint sh $2 -c "
    (command -v openssl >/dev/null || (apt-get -qq update >/dev/null && apt-get -qq install -y openssl >/dev/null) || apk add -q openssl >/dev/null)
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 2 -subj /CN=vk -keyout /tmp/s.key -out /tmp/s.crt 2>/dev/null
    chmod 644 /tmp/s.key
    exec valkey-server --port 0 --tls-port 6380 --tls-cert-file /tmp/s.crt --tls-key-file /tmp/s.key --tls-auth-clients no --tls-protocols TLSv1.3" >/dev/null
  for i in $(seq 1 60); do docker logs vk 2>&1 | grep -q 'Ready to accept' && break; sleep 2; done
  docker exec vk valkey-server --version
  sc vk:6380 X25519MLKEM768 "-tls1_3"
  sc vk:6380 X25519 ""
  echo "--- valkey-cli --tls (same image) PING"
  T 25 docker exec vk valkey-cli -p 6380 --tls --insecure PING 2>&1
  docker rm -f vk >/dev/null
done

echo "=== valkey-cli client offering: PQ-only openssl s_server pretending to be valkey"
docker rm -f fakesrv >/dev/null 2>&1
docker run -d $L --name fakesrv --network $NET --entrypoint sh $PG -c "openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 2 -subj /CN=f -keyout /tmp/s.key -out /tmp/s.crt 2>/dev/null; exec openssl s_server -accept 6380 -cert /tmp/s.crt -key /tmp/s.key -tls1_3 -groups X25519MLKEM768 -brief" >/dev/null
sleep 2
T 20 docker run --rm $L --network $NET $VK valkey-cli -h fakesrv -p 6380 --tls --insecure PING 2>&1 | head -2
sleep 1; docker logs fakesrv 2>&1 | grep -E 'Protocol|group|CONNECTION|error' | head -5
docker rm -f fakesrv >/dev/null
echo DONE
