#!/bin/sh
# squid-entrypoint.sh - writes the bump CA from env (ECS "secrets" from Secrets Manager) and starts Squid.
# BUMP_CA_PEM / BUMP_CA_KEY: PEM text. ORIGIN_CA_BUNDLE: optional extra CAs for the server leg.
set -eu
umask 077
printf '%s\n' "$BUMP_CA_PEM" > /etc/squid/bump-ca.pem
printf '%s\n' "$BUMP_CA_KEY" > /etc/squid/bump-ca.key
if [ -n "${ORIGIN_CA_BUNDLE:-}" ]; then
  printf '%s\n' "$ORIGIN_CA_BUNDLE" > /etc/squid/origin-ca.pem
else
  cp /etc/ssl/certs/ca-certificates.crt /etc/squid/origin-ca.pem
fi
chown proxy:proxy /etc/squid/bump-ca.* /etc/squid/origin-ca.pem
[ -d /var/spool/squid/ssl_db ] || /usr/lib/squid/security_file_certgen -c -s /var/spool/squid/ssl_db -M 16MB
chown -R proxy:proxy /var/spool/squid /var/log/squid
# Optional: restrict TLS groups for both legs, e.g. OPENSSL_CONF=/etc/squid/openssl-pq-only.cnf
openssl version
exec squid -N -f /etc/squid/squid.conf
