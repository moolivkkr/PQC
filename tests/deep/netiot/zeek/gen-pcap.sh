#!/bin/bash
# Runs inside debian:trixie-slim: capture one PQ and one classical TLS 1.3 handshake on lo.
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null && apt-get install -y -qq openssl tcpdump >/dev/null 2>&1
cd /tmp
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 2 -subj /CN=srv -keyout k.pem -out c.pem 2>/dev/null
openssl s_server -quiet -accept 8443 -cert c.pem -key k.pem >/dev/null 2>&1 &   # default groups (PQ first)
openssl s_server -quiet -accept 8444 -groups X25519 -cert c.pem -key k.pem >/dev/null 2>&1 &  # classical-only
tcpdump -i lo -w /out/tls-pq-and-classical.pcap -U 'tcp port 8443 or tcp port 8444' >/dev/null 2>&1 &
sleep 2
echo Q | openssl s_client -connect 127.0.0.1:8443 -servername pq.example -brief 2>&1 | grep group
echo Q | openssl s_client -connect 127.0.0.1:8444 -servername classic.example -brief 2>&1 | grep group
echo Q | openssl s_client -connect 127.0.0.1:8443 -servername tls12.example -tls1_2 -brief 2>&1 | grep -iE 'group|Protocol'
sleep 2; kill %3; sleep 1; ls -l /out/tls-pq-and-classical.pcap
