#!/bin/bash
# Runs inside debian:trixie-slim. Squid ssl-bump PQ test, both legs.
set -u
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null && apt-get install -y -qq squid-openssl openssl curl ca-certificates >/dev/null 2>&1
echo "== versions"; squid -v | head -1; openssl version; curl -V | head -1
cd /tmp
# bump CA + origin CA + origin cert (SAN localhost)
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 2 -subj /CN=bump-ca \
  -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign \
  -keyout /etc/squid/bump-ca.key -out /etc/squid/bump-ca.pem 2>/dev/null
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 2 -subj /CN=origin \
  -addext subjectAltName=DNS:localhost -keyout o.key -out o.pem 2>/dev/null
cp o.pem /etc/squid/origin-ca.pem
cp /cfg/squid.conf /etc/squid/squid.conf
/usr/lib/squid/security_file_certgen -c -s /var/spool/squid/ssl_db -M 16MB >/dev/null
chown -R proxy:proxy /var/spool/squid /var/log/squid
# origins: 4433 PQ-only, 4434 classical-only
openssl s_server -quiet -www -accept 4433 -tls1_3 -groups X25519MLKEM768 -cert o.pem -key o.key >/tmp/s4433.log 2>&1 &
openssl s_server -quiet -www -accept 4434 -groups X25519 -cert o.pem -key o.key >/tmp/s4434.log 2>&1 &
squid -k parse 2>&1 | grep -iE 'error|fatal' ; squid -N -f /etc/squid/squid.conf >/tmp/squid.out 2>&1 &
sleep 4
pass=0; fail=0
t() { # name expect(ok|fail) cmd...
  local n=$1 e=$2; shift 2
  if "$@" >/tmp/t.out 2>&1; then r=ok; else r=fail; fi
  if [ "$r" = "$e" ]; then pass=$((pass+1)); s=PASS; else fail=$((fail+1)); s=FAIL; fi
  echo "[$s] $n (got $r, want $e)"; grep -E 'Negotiated|group|curl:' /tmp/t.out | head -3
}
P="-x http://127.0.0.1:3128 --cacert /etc/squid/bump-ca.pem -s -o /dev/null --max-time 10 -w %{http_code}"
t "A PQ client -> squid -> PQ-only origin (both legs PQ)" ok curl $P --curves X25519MLKEM768 https://localhost:4433/
t "B classical client (X25519) -> squid -> PQ-only origin (squid converts)" ok curl $P --curves X25519 https://localhost:4433/
t "C PQ client -> squid -> classical-only origin (server-leg fallback)" ok curl $P --curves X25519MLKEM768 https://localhost:4434/
echo "== client-leg group as seen by an OpenSSL client through the proxy"
openssl s_client -proxy 127.0.0.1:3128 -connect localhost:4433 -servername localhost -CAfile /etc/squid/bump-ca.pem -brief </dev/null 2>&1 | grep -E 'Protocol|group|Verification'
echo "== negative control: squid restricted to X25519 by OPENSSL_CONF"
kill %3 2>/dev/null; sleep 2
cat >/tmp/classic.cnf <<'EOF'
openssl_conf = o
[o]
ssl_conf = s
[s]
system_default = d
[d]
Groups = X25519:P-256
EOF
OPENSSL_CONF=/tmp/classic.cnf squid -N -f /etc/squid/squid.conf >/tmp/squid2.out 2>&1 &
sleep 4
t "D squid limited to X25519 -> PQ-only origin must fail" fail curl $P --curves X25519MLKEM768 https://localhost:4433/
openssl s_client -proxy 127.0.0.1:3128 -connect localhost:4434 -servername localhost -CAfile /etc/squid/bump-ca.pem -brief </dev/null 2>&1 | grep -E 'group'
echo "== access.log"; tail -n 6 /var/log/squid/access.log
echo "RESULT pass=$pass fail=$fail"
