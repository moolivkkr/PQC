#!/bin/bash
# Host/client PQ tests. All containers labelled run=pqc-deep-hosts.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
D=/private/tmp/claude-501/-Users-kishoremooli-development-cybersecurity/21fa377a-bc06-46f9-9e49-4588545ba6c2/scratchpad/deep/hosts
L="--label run=pqc-deep-hosts"
NET=pqhosts-net
T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
dig() { docker pull -q "$1" >/dev/null 2>&1 && docker image inspect --format '{{index .RepoDigests 0}}' "$1"; }
cp "$D/../../lambda-pq/layer/pq-tls/openssl-pq.cnf" "$D/openssl-pq.cnf"
docker network create $L $NET >/dev/null 2>&1
SRV=$(dig debian:trixie-slim); echo "srv image $SRV"
docker run -d $L --name pqhosts-srv --network $NET --network-alias srv -v "$D:/t:ro" "$SRV" sh /t/srv-setup.sh >/dev/null
for i in $(seq 1 60); do docker logs pqhosts-srv 2>&1 | grep -q READY && break; sleep 2; done
docker logs pqhosts-srv 2>&1 | head -5
run() { # image profile
  local img=$(dig "$1"); if [ -z "$img" ]; then echo "##### $1 : PULL FAILED"; return; fi
  echo "##### $1 ($img) profile=$2"
  T 400 docker run --rm $L --network $NET -v "$D:/t:ro" --entrypoint /bin/sh "$img" /t/probe.sh "$2" 2>&1
}
run amazonlinux:2023 al2023
for im in debian:trixie-slim debian:bookworm-slim ubuntu:24.04 ubuntu:26.04 alpine:3.24 alpine:3.21; do run $im ssh-curl-wget; done
run alpine:3.24 busybox-wget
run curlimages/curl:latest curlimage "" ""
run debian:trixie-slim git
run alpine:3.24 git
run amazon/aws-cli:latest awscli2 /bin/sh ""
run python:3.13-slim awscli1
run python:3.12-slim-bookworm awscli1
for k in alpine/k8s:1.34.1 alpine/k8s:1.33.5; do docker pull -q $k >/dev/null 2>&1 && { run $k kubectl /bin/sh ""; break; }; done
run alpine/helm:latest helm /bin/sh ""
echo "##### go version -m (Go toolchain and DefaultGODEBUG of CLI binaries)"
mkdir -p "$D/bins"
cpb() { local img=$(dig "$1"); [ -z "$img" ] && { echo "pull failed $1"; return; }; local c=$(docker create $L "$img"); docker cp "$c:$2" "$D/bins/$3" >/dev/null 2>&1; docker rm "$c" >/dev/null; echo "$3 from $img"; }
cpb alpine/k8s:1.34.1 /usr/bin/kubectl kubectl
cpb alpine/helm:latest /usr/bin/helm helm
cpb hashicorp/terraform:latest /bin/terraform terraform
GO=$(dig golang:1.25-alpine)
T 120 docker run --rm $L -v "$D/bins:/b:ro" "$GO" sh -c 'for f in kubectl helm terraform; do echo "== $f"; go version -m /b/$f 2>&1 | grep -E "^/b|DefaultGODEBUG|tlsmlkem" | head -3; done'
echo "##### server logs"; docker exec pqhosts-srv sh -c 'tail -5 /tmp/sshd22.log; tail -3 /tmp/sshd2222.log' 2>&1
echo DONE
