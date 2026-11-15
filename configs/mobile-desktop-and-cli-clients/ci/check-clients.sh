#!/bin/sh
# Fails if a tool in this image can't offer X25519MLKEM768.
set -e
curl -V | head -1 | grep -q 'OpenSSL/3\.[5-9]' || { echo "curl not on OpenSSL >= 3.5"; exit 1; }
if command -v git >/dev/null; then
  ldd "$(git --exec-path)/git-remote-https" 2>/dev/null | grep -q gnutls && { echo "git uses GnuTLS (no ML-KEM)"; exit 1; }
fi
if command -v wget >/dev/null; then
  wget --version | grep -q -- '+ssl/gnutls' && { echo "wget uses GnuTLS (no ML-KEM)"; exit 1; }
fi
ssh -V 2>&1 | grep -Eq 'OpenSSH_(9\.9|1[0-9])' || { echo "OpenSSH < 9.9"; exit 1; }
echo "client posture OK"
