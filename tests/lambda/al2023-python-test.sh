#!/bin/bash
# Runs inside amazonlinux:2023: Python 3.11 and 3.12 from the distro, linked to the system OpenSSL.
dnf -y -q install python3.11 python3.12 crypto-policies-scripts >/dev/null 2>&1
. /etc/os-release
echo "os: $PRETTY_NAME  policy: $(cat /etc/crypto-policies/config)"
for p in python3.11 python3.12; do
  $p -c "import ssl,sys;print(sys.version.split()[0], ssl.OPENSSL_VERSION)"
  $p /w/client.py "$p default-policy" | grep PQ-only
done
for p in python3.11 python3.12; do
  OPENSSL_CONF=/w/layer/pq-tls/openssl-pq.cnf $p /w/client.py "$p OPENSSL_CONF" | grep PQ-only
done
for p in python3.11 python3.12; do
  $p /w/ecdh_curve.py "$p"
done
update-crypto-policies --set DEFAULT:PQ >/dev/null 2>&1
echo "policy now: $(cat /etc/crypto-policies/config)"
for p in python3.11 python3.12; do
  $p /w/client.py "$p DEFAULT:PQ"
done
