#!/bin/sh
# Two PostgreSQL 18 clusters in one container: 5432 PQ-only (ssl_groups = X25519MLKEM768, TLS 1.3 only),
# 5433 classical-only (ssl_groups = X25519). Clients must use sslmode=verify-full.
set -e
for spec in "5432 X25519MLKEM768 TLSv1.3" "5433 X25519 TLSv1.2"; do
  set -- $spec
  D=/tmp/pg$1
  mkdir -p $D && chown postgres $D
  su postgres -c "initdb -D $D -A trust -U postgres" >/dev/null
  cp /w/certs/leaf.pem $D/server.crt; cp /w/certs/leaf.key $D/server.key
  chown postgres $D/server.*; chmod 600 $D/server.key
  cat >> $D/postgresql.conf <<EOF
listen_addresses = '*'
port = $1
ssl = on
ssl_groups = '$2'
ssl_min_protocol_version = '$3'
log_connections = on
EOF
  echo "hostssl all all 0.0.0.0/0 trust" >> $D/pg_hba.conf
  su postgres -c "pg_ctl -D $D -l /w/out/srv/pg$1.log start" >/dev/null
done
echo "pg up"
sleep infinity
