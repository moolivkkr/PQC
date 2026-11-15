#!/usr/bin/env bash
# Posture: which TLS library each server image ships. Run: bash posture.sh > out/posture.txt
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
d(){ docker image inspect --format '{{index .RepoDigests 0}}' "$1"; }
R(){ docker run --rm --label run=pqc-deep-websrv "$@"; }
echo "--- nginx"; for i in nginx:latest nginx:stable nginx:alpine; do echo "## $i"; R --entrypoint sh "$(d $i)" -c 'nginx -V 2>&1 | head -3; grep PRETTY /etc/os-release; ls /usr/lib/*/libssl.so* /usr/lib/libssl.so* /lib/libssl.so* 2>/dev/null'; done
echo "--- httpd"; for i in httpd:2.4 httpd:2.4-alpine; do echo "## $i"; R --entrypoint sh "$(d $i)" -c 'httpd -v | head -1; grep PRETTY /etc/os-release; ls /usr/lib/*/libssl.so* /usr/lib/libssl.so* /lib/libssl.so* 2>/dev/null'; done
echo "--- haproxy"; for i in haproxy:latest haproxy:lts-alpine; do echo "## $i"; R --entrypoint sh "$(d $i)" -c 'haproxy -vv | grep -iE "^HAProxy version|OpenSSL|aws-lc" | head -6; grep PRETTY /etc/os-release'; done
echo "--- envoy"; R --entrypoint envoy "$(d envoyproxy/envoy:v1.36-latest)" --version
echo "--- istio proxyv2"; R --entrypoint /usr/local/bin/envoy "$(d istio/proxyv2:1.28.0)" --version
echo "--- caddy"; R --entrypoint caddy "$(d caddy:2)" version; R --entrypoint caddy "$(d caddy:2)" build-info | head -2
echo "--- traefik"; R "$(d traefik:v3)" version
echo "--- tomcat"; R --entrypoint sh "$(d tomcat:11-jdk25-temurin)" -c 'java -version 2>&1|head -1; /usr/local/tomcat/bin/version.sh 2>/dev/null | grep -E "Server number|OS Name"; grep PRETTY /etc/os-release; openssl version; ls /usr/local/tomcat/native-jni-lib 2>/dev/null'
echo "--- ingress-nginx controller v1.14.0"; R --entrypoint sh "$(d registry.k8s.io/ingress-nginx/controller:v1.14.0)" -c 'nginx -V 2>&1 | head -3; grep PRETTY /etc/os-release; ls /usr/lib/libssl* /lib/libssl* 2>/dev/null'
