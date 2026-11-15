#!/bin/bash
set -euo pipefail
dnf -y -q install crypto-policies-scripts
dnf -y -q update crypto-policies crypto-policies-scripts openssl openssh-server
update-crypto-policies --set DEFAULT:PQ
update-crypto-policies --show
