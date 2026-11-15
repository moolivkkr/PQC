#!/usr/bin/env bash
# PQ tests for web servers/proxies: inbound (PQ client, default client, classical client, TLS1.2 client)
# and upstream (proxy -> PQ-only backend, proxy -> classical-only backend).
# Usage: bash run-tests.sh [product ...]   Output: out/results.txt (+ per-product logs)
set -u
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"
L=run=pqc-deep-websrv
NET=pqc-deep-websrv-net
d(){ docker image inspect --format '{{index .RepoDigests 0}}' "$1"; }
TOOLS=pqc-websrv-tools:local
OUT="$W/out/results.txt"
al(){ perl -e 'alarm shift; exec @ARGV' "$@"; }

docker network inspect $NET >/dev/null 2>&1 || docker network create --label $L $NET >/dev/null
docker image inspect $TOOLS >/dev/null 2>&1 || docker build -q -t $TOOLS -f "$W/tools.Dockerfile" "$W" >/dev/null

# Backend: PQ-only on 8443, classical-only on 9443 (OpenSSL 3.5, Debian 13)
if ! docker ps --format '{{.Names}}' | grep -qx be; then
  docker run -d --rm --name be --network $NET --label $L -v "$W/certs:/certs:ro" $TOOLS sh -c '
    openssl s_server -accept 8443 -www -tls1_3 -groups X25519MLKEM768 -cert /certs/server.crt -key /certs/server.key -quiet &
    openssl s_server -accept 9443 -www -tls1_3 -groups X25519        -cert /certs/server.crt -key /certs/server.key -quiet &
    wait' >/dev/null
fi
docker ps --format '{{.Names}}' | grep -qx cl || docker run -d --rm --name cl --network $NET --label $L $TOOLS sleep 3600 >/dev/null
sleep 2

res(){ printf '%-14s %-44s %s\n' "$1" "$2" "$3" | tee -a "$OUT"; }

sc(){ # $1=product $2=label $3=expect(group name|FAIL) args...
  local p=$1 lab=$2 exp=$3; shift 3
  local o; o=$(docker exec cl sh -c "echo Q | perl -e 'alarm 10; exec @ARGV' openssl s_client -connect srv:8443 -servername srv $* 2>&1")
  echo "### $p $lab: openssl s_client $*" >> "$W/out/$p.log"; echo "$o" | grep -E 'Negotiated|Protocol|error|alert|Cipher is' | head -5 >> "$W/out/$p.log"
  local g; g=$(echo "$o" | sed -n 's/.*Negotiated TLS1.3 group: \([A-Za-z0-9-]*\).*/\1/p;s/^Peer Temp Key: \([A-Za-z0-9-]*\),.*/\1/p' | head -1)
  echo "$o" | grep -E 'Peer Temp Key' >> "$W/out/$p.log"
  # one real HTTPS request so access logs record protocol/group (curl 8.14 on trixie supports --curves)
  docker exec cl curl -sk -o /dev/null -m 5 "https://srv:8443/" $(echo "$*" | sed -n 's/.*-groups \([^ ]*\).*/--curves \1/p') >/dev/null 2>&1
  local v; v=$(echo "$o" | sed -n 's/^ *Protocol *: *\(.*\)/\1/p;s/^New, \(TLSv[0-9.]*\),.*/\1/p' | head -1)
  if [ "$exp" = FAIL ]; then
    if echo "$o" | grep -qE 'Cipher is \(NONE\)|alert|error'; then res "$p" "$lab" "PASS (refused as expected)"; else res "$p" "$lab" "FAIL (connected: $v $g)"; fi
  else
    if [ "$g" = "$exp" ]; then res "$p" "$lab" "PASS (group=$g)"; else res "$p" "$lab" "FAIL (group='$g' want $exp)"; fi
  fi
}
up(){ # $1=product $2=path $3=expect http code
  local c; c=$(docker exec cl curl -s -o /dev/null -m 10 -w '%{http_code}' "http://srv:8080$2")
  if [ "$c" = "$3" ]; then res "$1" "upstream $2 -> http $3" "PASS (http=$c)"; else res "$1" "upstream $2 -> http $3" "FAIL (http=$c)"; fi
}

start(){ # $1=product, rest = docker run args
  local p=$1; shift
  docker rm -f srv >/dev/null 2>&1
  : > "$W/out/$p.log"
  docker run -d --name srv --network $NET --label $L -v "$W/certs:/certs:ro" "$@" >/dev/null
  sleep "${WAIT:-4}"
  if ! docker ps --format '{{.Names}}' | grep -qx srv; then res "$p" "server start" "FAIL (exited)"; docker logs srv >> "$W/out/$p.log" 2>&1; docker rm -f srv >/dev/null 2>&1; return 1; fi
  return 0
}
stop(){ docker logs srv >> "$W/out/$1.log" 2>&1; docker rm -f srv >/dev/null 2>&1; }

inbound(){ # $1=product $2=tls12-expect (FAIL for 1.3-only)
  sc "$1" "in: PQ-only client"        X25519MLKEM768 -tls1_3 -groups X25519MLKEM768
  sc "$1" "in: default OpenSSL3.5 client" X25519MLKEM768 -tls1_3
  sc "$1" "in: classical client X25519"  X25519 -tls1_3 -groups X25519
  sc "$1" "in: TLS1.2 client (1.3-only)" FAIL -tls1_2
}
upstream(){ up "$1" /pq/ "${2:-200}"; up "$1" /classic/ 200; }

C="$W/conf"
for p in "${@:-nginx nginx-alpine httpd httpd-alpine haproxy haproxy-alpine envoy envoy-default caddy traefik tomcat}"; do
for p in $p; do
case $p in
  nginx)          start $p -v "$C/nginx.conf:/etc/nginx/nginx.conf:ro" "$(d nginx:latest)" && { inbound $p; upstream $p; stop $p; } ;;
  nginx-alpine)   start $p -v "$C/nginx.conf:/etc/nginx/nginx.conf:ro" "$(d nginx:alpine)" && { inbound $p; upstream $p; stop $p; } ;;
  httpd)          start $p -v "$C/httpd.conf:/usr/local/apache2/conf/httpd.conf:ro" "$(d httpd:2.4)" && { inbound $p; upstream $p; stop $p; } ;;
  httpd-alpine)   start $p -v "$C/httpd.conf:/usr/local/apache2/conf/httpd.conf:ro" "$(d httpd:2.4-alpine)" && { inbound $p; upstream $p; stop $p; } ;;
  haproxy)        start $p -v "$C/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro" "$(d haproxy:latest)" && { inbound $p; upstream $p; stop $p; } ;;
  haproxy-alpine) start $p -v "$C/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro" "$(d haproxy:lts-alpine)" && { inbound $p; upstream $p; stop $p; } ;;
  envoy)          start $p -v "$C/envoy.yaml:/etc/envoy/envoy.yaml:ro" "$(d envoyproxy/envoy:v1.36-latest)" -c /etc/envoy/envoy.yaml && { inbound $p; upstream $p
                    docker exec cl curl -s http://srv:9901/stats | grep -E 'ssl\.(curves|versions)' >> "$W/out/$p.log"; stop $p; } ;;
  envoy-default)  grep -v ecdh_curves "$C/envoy.yaml" > "$W/out/envoy-default.yaml"
                  start $p -v "$W/out/envoy-default.yaml:/etc/envoy/envoy.yaml:ro" "$(d envoyproxy/envoy:v1.36-latest)" -c /etc/envoy/envoy.yaml && {
                    sc $p "in: PQ-only client (no ecdh_curves)" FAIL -tls1_3 -groups X25519MLKEM768
                    sc $p "in: default client (no ecdh_curves)" X25519 -tls1_3
                    up $p /pq/ 503; up $p /classic/ 200; stop $p; } ;;
  caddy)          start $p -v "$C/Caddyfile:/etc/caddy/Caddyfile:ro" "$(d caddy:2)" && { inbound $p; upstream $p; stop $p; } ;;
  traefik)        start $p -v "$C/traefik.yml:/etc/traefik/traefik.yml:ro" -v "$C/dynamic.yml:/etc/traefik/dynamic.yml:ro" "$(d traefik:v3)" && { inbound $p; upstream $p; stop $p; } ;;
  tomcat)         WAIT=12 start $p -v "$C/server.xml:/usr/local/tomcat/conf/server.xml:ro" "$(d tomcat:11-jdk25-temurin)" && { inbound $p; stop $p; } ;;
  tomcat-openssl) WAIT=12 start $p -v "$C/server-openssl.xml:/usr/local/tomcat/conf/server.xml:ro" "$(d tomcat:11-jdk25-temurin)" && { inbound $p; stop $p; } ;;
  nginx-default)  start $p -v "$W/out/nginx-default.conf:/etc/nginx/nginx.conf:ro" "$(d nginx:latest)" && { inbound $p; upstream $p; stop $p; } ;;
  haproxy-default) start $p -v "$W/out/haproxy-default.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro" "$(d haproxy:latest)" && { inbound $p; upstream $p; stop $p; } ;;
  al2023-nginx-default) WAIT=60 start $p -v "$W/out/nginx-default.conf:/etc/nginx/t.conf:ro" --entrypoint sh "$(d amazonlinux:2023)" -c 'dnf -q -y install nginx openssl >/dev/null 2>&1; openssl version; nginx -V 2>&1 | grep -i openssl; exec nginx -c /etc/nginx/t.conf -g "daemon off;"' && { inbound $p; upstream $p; stop $p; } ;;
  al2023-nginx)   WAIT=60 start $p -v "$C/nginx.conf:/etc/nginx/t.conf:ro" --entrypoint sh "$(d amazonlinux:2023)" -c 'dnf -q -y install nginx openssl >/dev/null 2>&1; exec nginx -c /etc/nginx/t.conf -g "daemon off;"' && { inbound $p; upstream $p; stop $p; } ;;
  ingress-nginx)  start $p -v "$C/nginx.conf:/etc/nginx/t.conf:ro" --entrypoint /usr/bin/nginx "$(d registry.k8s.io/ingress-nginx/controller:v1.14.0)" -c /etc/nginx/t.conf -g "pid /tmp/n.pid; daemon off;" && { inbound $p; upstream $p; stop $p; } ;;
  istio-envoy)    start $p -v "$C/envoy.yaml:/etc/envoy/envoy.yaml:ro" --entrypoint /usr/local/bin/envoy "$(d istio/proxyv2:1.28.0)" -c /etc/envoy/envoy.yaml && { inbound $p; upstream $p; stop $p; } ;;
  al2023-httpd)   WAIT=60 start $p -v "$W/out/httpd-al2023.conf:/etc/httpd/t.conf:ro" --entrypoint sh "$(d amazonlinux:2023)" -c 'dnf -q -y install httpd mod_ssl >/dev/null 2>&1; rpm -q httpd; exec httpd -f /etc/httpd/t.conf -DFOREGROUND' && { inbound $p; upstream $p; stop $p; } ;;
  al2023-httpd-pqpolicy) WAIT=60 start $p -v "$W/out/httpd-al2023.conf:/etc/httpd/t.conf:ro" --entrypoint sh "$(d amazonlinux:2023)" -c 'dnf -q -y install httpd mod_ssl crypto-policies-scripts >/dev/null 2>&1; update-crypto-policies --set DEFAULT:PQ; update-crypto-policies --show; exec httpd -f /etc/httpd/t.conf -DFOREGROUND' && { inbound $p; upstream $p; stop $p; } ;;
  *) echo "unknown $p";;
esac
done; done
