#!/bin/sh
# Runs inside debian:trixie-slim. PQ-only TLS (4433), classical-only TLS (4434),
# sshd mlkem-only (22), sshd sntrup-only (2222).
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq openssl openssh-server >/dev/null
openssl version
ssh -V 2>&1
cd /tmp
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj /CN=srv -days 2 -keyout k.pem -out c.pem 2>/dev/null
nohup openssl s_server -accept 4433 -cert c.pem -key k.pem -groups X25519MLKEM768 -tls1_3 -www >/tmp/pq.log 2>&1 &
nohup openssl s_server -accept 4434 -cert c.pem -key k.pem -groups X25519 -www >/tmp/cl.log 2>&1 &
mkdir -p /run/sshd
ssh-keygen -A >/dev/null
/usr/sbin/sshd -p 22 -o KexAlgorithms=mlkem768x25519-sha256 -E /tmp/sshd22.log
/usr/sbin/sshd -p 2222 -o KexAlgorithms=sntrup761x25519-sha512@openssh.com -E /tmp/sshd2222.log
echo READY
sleep 3600
