#!/bin/bash
# Software WAF test: OWASP ModSecurity CRS nginx image.
#  1. client leg: PQ-only client and classical client against the WAF's TLS port (8443)
#  2. origin leg: WAF proxies to a PQ-only upstream (openssl s_server -groups X25519MLKEM768)
set -u
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
L="--label run=pqc-deep-edge"
NET=pqc-deep-edge-net
DEB=$(docker image inspect --format '{{index .RepoDigests 0}}' debian:trixie-slim)
WAF=$(docker image inspect --format '{{index .RepoDigests 0}}' owasp/modsecurity-crs:nginx)
echo "debian: $DEB"; echo "waf: $WAF"
docker network create $L $NET >/dev/null

# PQ-only upstream
docker run -d $L --network $NET --name edge-pqonly $DEB bash -c '
apt-get -qq update >/dev/null 2>&1; apt-get -qq install -y openssl >/dev/null 2>&1
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout /k.pem -out /c.pem -subj /CN=pqonly -days 2 2>/dev/null
exec openssl s_server -accept 4433 -cert /c.pem -key /k.pem -tls1_3 -groups X25519MLKEM768 -www' >/dev/null

# ModSecurity CRS nginx in front of it
for i in $(seq 1 60); do docker logs edge-pqonly 2>&1 | grep -q ACCEPT && break; sleep 2; done
docker run -d $L --network $NET --name edge-modsec -e BACKEND=https://edge-pqonly:4433 -e PROXY_SSL_VERIFY=off $WAF >/dev/null
sleep 8
echo "--- WAF image versions"
docker exec edge-modsec sh -c 'cat /etc/os-release | grep PRETTY; nginx -V 2>&1 | grep -i "openssl\|version"; openssl version 2>/dev/null; ls /usr/lib/*/libssl* 2>/dev/null'

echo "--- client leg"
docker run --rm $L --network $NET $DEB bash -c '
apt-get -qq update >/dev/null 2>&1; apt-get -qq install -y openssl >/dev/null 2>&1
openssl version
echo | openssl s_client -connect edge-modsec:8443 -groups X25519MLKEM768 -tls1_3 2>&1 | grep -E "Negotiated TLS1.3 group|^Protocol|CONNECTED|alert|error" | head -4
echo "classical:"; echo | openssl s_client -connect edge-modsec:8443 -groups X25519 2>&1 | grep -E "Negotiated TLS1.3 group|Server Temp Key|^Protocol|alert" | head -3
echo "tls1.2:"; echo | openssl s_client -connect edge-modsec:8443 -tls1_2 2>&1 | grep -E "Protocol *:|Server Temp Key|alert" | head -3'

echo "--- origin leg (WAF -> PQ-only upstream)"
docker run --rm $L --network $NET $DEB bash -c 'apt-get -qq update >/dev/null 2>&1; apt-get -qq install -y curl >/dev/null 2>&1; curl -sk -o /dev/null -w "HTTP %{http_code}\n" https://edge-modsec:8443/'
docker logs edge-pqonly 2>&1 | tail -3
docker logs edge-modsec 2>&1 | grep -i "ssl\|upstream\|error" | tail -5

docker rm -f edge-pqonly edge-modsec >/dev/null
docker network rm $NET >/dev/null
echo "remaining labelled containers: $(docker ps -a --filter label=run=pqc-deep-edge -q | wc -l)"
