#!/bin/bash
set -u
L="--label run=pqc-deep-edge"; NET=pqc-deep-edge-net
DEB=$(docker image inspect --format '{{index .RepoDigests 0}}' debian:trixie-slim)
WAF=$(docker image inspect --format '{{index .RepoDigests 0}}' owasp/modsecurity-crs:nginx)
docker network create $L $NET >/dev/null
# PQ-only upstream
docker run -d $L --network $NET --name edge-pqonly $DEB bash -c '
apt-get -qq update >/dev/null 2>&1; apt-get -qq install -y openssl >/dev/null 2>&1
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout /k.pem -out /c.pem -subj /CN=pqonly -days 2 2>/dev/null
exec openssl s_server -accept 4433 -cert /c.pem -key /k.pem -tls1_3 -groups X25519MLKEM768 -www' >/dev/null
for i in $(seq 1 60); do docker logs edge-pqonly 2>&1 | grep -q ACCEPT && break; sleep 2; done
# ModSecurity CRS nginx in front of it
docker run -d $L --network $NET --name edge-modsec -e BACKEND=https://edge-pqonly:4433 -e PROXY_SSL_VERIFY=off $WAF >/dev/null
sleep 8
# client leg: PQ-only, classical, TLS 1.2
docker run --rm $L --network $NET $DEB bash -c '
apt-get -qq update >/dev/null 2>&1; apt-get -qq install -y openssl >/dev/null 2>&1
echo | openssl s_client -connect edge-modsec:8443 -groups X25519MLKEM768 -tls1_3 2>&1 | grep "Negotiated TLS1.3 group"
echo | openssl s_client -connect edge-modsec:8443 -groups X25519 2>&1 | grep "^Protocol"
echo | openssl s_client -connect edge-modsec:8443 -tls1_2 2>&1 | grep "^Protocol"'
# origin leg: through the WAF to the PQ-only upstream
docker run --rm $L --network $NET $DEB bash -c 'apt-get -qq update >/dev/null 2>&1; apt-get -qq install -y curl >/dev/null 2>&1; curl -sk -o /dev/null -w "HTTP %{http_code}\n" https://edge-modsec:8443/'
docker rm -f edge-pqonly edge-modsec >/dev/null; docker network rm $NET >/dev/null
