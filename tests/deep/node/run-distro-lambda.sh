#!/bin/bash
# Distro-packaged Node (system OpenSSL) and Lambda base images, run as plain containers against pqsrv.
# Needs pqnode-srv running on network pqnet-node. Output: distro-lambda.out
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
D="$(cd "$(dirname "$0")" && pwd)"; L=run=pqc-deep-node
dg() { grep "^$1 " "$D/digests.txt" | cut -d' ' -f2; }
P='node /w/probe.mjs tls.connect https.get'
r() { local label=$1; shift; echo "## $label"; perl -e 'alarm shift; exec @ARGV' 400 docker run --rm --label $L --network pqnet-node -v "$D":/w -e NODE_EXTRA_CA_CERTS=/w/certs/ca.pem "$@" 2>&1 | grep -E "^#|^tls|^https|node_shared|openssl_conf|version|nodejs|ERR|rror" | grep -v -i warn | cut -c1-200; }

AL=$(dg amazonlinux:2023)
AL_SETUP='dnf -y -q install nodejs22 >/dev/null 2>&1; N=$(ls /usr/bin/node-22 /usr/bin/node 2>/dev/null | head -1); echo "nodejs22 rpm: $(rpm -q nodejs22) bin=$N"; $N -p "\"version \"+process.version+\" openssl \"+process.versions.openssl+\" node_shared_openssl=\"+process.config.variables.node_shared_openssl"'
r "AL2023 dnf nodejs22, default policy" --entrypoint bash $AL -c "$AL_SETUP; \$N /w/probe.mjs tls.connect https.get"
r "AL2023 dnf nodejs22, DEFAULT:PQ policy" --entrypoint bash $AL -c "$AL_SETUP; dnf -y -q install crypto-policies-scripts >/dev/null 2>&1; update-crypto-policies --set DEFAULT:PQ >/dev/null 2>&1; \$N /w/probe.mjs tls.connect https.get"
r "AL2023 dnf nodejs22, DEFAULT:PQ + --openssl-shared-config" --entrypoint bash $AL -c "$AL_SETUP; dnf -y -q install crypto-policies-scripts >/dev/null 2>&1; update-crypto-policies --set DEFAULT:PQ >/dev/null 2>&1; \$N --openssl-shared-config /w/probe.mjs tls.connect https.get"
r "AL2023 dnf nodejs22, OPENSSL_CONF=openssl-pq-node-system.cnf" -e OPENSSL_CONF=/w/conf/openssl-pq-node-system.cnf --entrypoint bash $AL -c "$AL_SETUP; \$N /w/probe.mjs tls.connect https.get"

TX=$(dg debian:trixie-slim)
r "Debian 13 apt nodejs (system OpenSSL)" --entrypoint bash $TX -c 'apt-get update -qq >/dev/null; apt-get install -y -qq --no-install-recommends nodejs ca-certificates >/dev/null 2>&1; node -p "\"version \"+process.version+\" openssl \"+process.versions.openssl+\" node_shared_openssl=\"+process.config.variables.node_shared_openssl"; node /w/probe.mjs tls.connect https.get'

A=$(dg alpine:3.22)
r "Alpine 3.22 apk nodejs (system OpenSSL)" --entrypoint sh $A -c 'apk add -q nodejs >/dev/null 2>&1; node -p "\"version \"+process.version+\" openssl \"+process.versions.openssl+\" node_shared_openssl=\"+process.config.variables.node_shared_openssl"; node /w/probe.mjs tls.connect https.get'

for v in 22 24; do
  LI=$(dg public.ecr.aws/lambda/nodejs:$v); AWSCONF=/var/runtime/openssl_conf/openssl.cnf
  r "lambda nodejs$v: no OPENSSL_CONF (image only)" --entrypoint node $LI /w/probe.mjs tls.connect https.get
  r "lambda nodejs$v: OPENSSL_CONF=AWS file (as bootstrap sets)" -e OPENSSL_CONF=$AWSCONF --entrypoint node $LI /w/probe.mjs tls.connect https.get
  r "lambda nodejs$v: OPENSSL_CONF=openssl-pq-node.cnf" -e OPENSSL_CONF=/w/conf/openssl-pq-node.cnf --entrypoint node $LI /w/probe.mjs tls.connect https.get
  r "lambda nodejs$v: AWS file + NODE_OPTIONS=--openssl-config" -e OPENSSL_CONF=$AWSCONF -e NODE_OPTIONS=--openssl-config=/w/conf/openssl-pq-node.cnf --entrypoint node $LI /w/probe.mjs tls.connect https.get
  r "lambda nodejs$v: AWS file + code tls.DEFAULT_ECDH_CURVE" -e OPENSSL_CONF=$AWSCONF -e SET_DEFAULT_ECDH_CURVE=X25519MLKEM768:X25519:P-256:P-384 --entrypoint node $LI /w/probe.mjs tls.connect https.get
  r "lambda nodejs$v: AWS file + OPENSSL_CONF=/dev/null" -e OPENSSL_CONF=/dev/null --entrypoint node $LI /w/probe.mjs tls.connect https.get
done
LI=$(dg public.ecr.aws/lambda/nodejs:22); echo "## AWS lambda nodejs22 openssl.cnf:"; docker run --rm --label $L --entrypoint cat $LI /var/runtime/openssl_conf/openssl.cnf | grep -v '^#' | grep -v '^$'
docker run --rm --label $L --entrypoint sh $LI -c 'grep -rn OPENSSL_CONF /var/runtime/bootstrap* /var/runtime/*.sh 2>/dev/null | head -5'

N24=$(dg node:24-slim)
r "node:24-slim + tls.DEFAULT_ECDH_CURVE=X25519:P-256 (pitfall)" -e SET_DEFAULT_ECDH_CURVE=X25519:P-256 $N24 node /w/probe.mjs tls.connect https.get
r "node:24-slim + --tls-max-v1.2 (pitfall)" -e NODE_OPTIONS=--tls-max-v1.2 $N24 node /w/probe.mjs tls.connect https.get
