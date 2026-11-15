#!/bin/bash
# Runs inside pqc-deep-node/db (postgres:18 on Debian 13 + redis 8.0 + MariaDB 11.8, all on system OpenSSL 3.5).
# Each server runs twice: PQ-only and classical-only. Postgres uses its own ssl_groups; Redis and MariaDB take
# the group list from the OpenSSL config file named by OPENSSL_CONF.
set -e
PQ=/w/conf/server-pq-only.cnf; CL=/w/conf/server-classical-only.cnf
mkdir -p /s && cp /w/certs/server.pem /w/certs/server.key /s/ && chown -R postgres:mysql /s 2>/dev/null || chown -R postgres /s
chmod 640 /s/server.key; chmod 755 /s
# PostgreSQL 18: ssl_groups
for p in 5432:X25519MLKEM768 5433:X25519; do port=${p%%:*}; grp=${p#*:}
  su postgres -c "initdb -D /tmp/pg$port -A trust >/dev/null && echo 'hostssl all all 0.0.0.0/0 trust' >> /tmp/pg$port/pg_hba.conf"
  su postgres -c "postgres -D /tmp/pg$port -p $port -c listen_addresses='*' -c ssl=on -c ssl_cert_file=/s/server.pem -c ssl_key_file=/s/server.key -c ssl_min_protocol_version=TLSv1.3 -c ssl_groups=$grp -k /tmp >/tmp/pg$port.log 2>&1 &"
done
# Redis 8.0: TLS-only ports
cp /s/server.key /s/redis.key; chmod 644 /s/redis.key
OPENSSL_CONF=$PQ redis-server --port 0 --tls-port 6380 --tls-cert-file /s/server.pem --tls-key-file /s/redis.key --tls-auth-clients no --protected-mode no --daemonize yes --logfile /tmp/r6380.log
OPENSSL_CONF=$CL redis-server --port 0 --tls-port 6381 --tls-cert-file /s/server.pem --tls-key-file /s/redis.key --tls-auth-clients no --protected-mode no --daemonize yes --logfile /tmp/r6381.log
# MariaDB 11.8
for p in 3306:$PQ 3307:$CL; do port=${p%%:*}; conf=${p#*:}
  mariadb-install-db --user=root --datadir=/tmp/my$port --auth-root-authentication-method=normal >/dev/null 2>&1
  OPENSSL_CONF=$conf mariadbd --user=root --datadir=/tmp/my$port --port=$port --socket=/tmp/my$port.sock --bind-address=0.0.0.0 \
    --ssl-cert=/s/server.pem --ssl-key=/s/redis.key --tls-version=TLSv1.3 --skip-grant-tables=0 >/tmp/my$port.log 2>&1 &
done
sleep 8
for port in 3306 3307; do mariadb --skip-ssl -uroot -S /tmp/my$port.sock -e "CREATE USER 't'@'%' IDENTIFIED BY 't' REQUIRE SSL; GRANT ALL ON *.* TO 't'@'%';"; done
# Self-check with s_client (server-side evidence)
for hp in 5432:postgres 5433:postgres 6380:- 6381:- 3306:mysql 3307:mysql; do port=${hp%%:*}; st=${hp#*:}
  for g in X25519MLKEM768 X25519; do
    if [ "$st" = "-" ]; then sx=""; else sx="-starttls $st"; fi
    r=$(echo | openssl s_client -connect 127.0.0.1:$port $sx -groups $g -tls1_3 -brief 2>&1 | grep -m1 -E "Negotiated TLS1.3 group|alert|error" || true)
    echo "selfcheck port=$port client-groups=$g -> ${r:-no handshake}"
  done
done
echo DB-READY
sleep infinity
