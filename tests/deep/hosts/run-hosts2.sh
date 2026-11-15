#!/bin/bash
# Round 2: reuse running pqhosts-srv. All containers labelled run=pqc-deep-hosts.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
D=/private/tmp/claude-501/-Users-kishoremooli-development-cybersecurity/21fa377a-bc06-46f9-9e49-4588545ba6c2/scratchpad/deep/hosts
L="--label run=pqc-deep-hosts"; NET=pqhosts-net
T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
dig() { docker image inspect --format '{{index .RepoDigests 0}}' "$1" 2>/dev/null || { docker pull -q "$1" >/dev/null 2>&1 && docker image inspect --format '{{index .RepoDigests 0}}' "$1"; }; }
run() { local img=$(dig "$1"); echo "##### $1 ($img) profile=$2"; T 400 docker run --rm $L --network $NET -v "$D:/t:ro" --entrypoint /bin/sh "$img" /t/probe2.sh "$2" 2>&1; }
run amazon/aws-cli:latest awscli
run python:3.13-slim awscli1
run alpine/k8s:1.34.1 kubectl
run alpine/helm:latest helm
run debian:trixie-slim gnutls
run ubuntu:26.04 gnutls
run amazonlinux:2023 al2023-wget-sshd
echo DONE
