#!/bin/bash
# Runs inside debian:trixie-slim with --cap-add NET_ADMIN. Args: LOCAL_IP REMOTE_IP ROLE(init|resp)
L=$1 R=$2 ROLE=$3
if command -v apk >/dev/null; then apk add -q strongswan bash >/dev/null 2>&1; V=$(apk info -v 2>/dev/null | grep ^strongswan-[0-9]); else export DEBIAN_FRONTEND=noninteractive; apt-get update -qq >/dev/null && apt-get install -y -qq strongswan-swanctl strongswan-charon libstrongswan-extra-plugins libcharon-extra-plugins >/dev/null 2>&1; V=$(dpkg-query -W -f="\${Version}" strongswan-charon); fi
CHARON=$(ls /usr/lib/ipsec/charon /usr/libexec/ipsec/charon /usr/lib/strongswan/charon 2>/dev/null | head -1)
echo "== $ROLE: $V $CHARON"; ls /usr/lib/ipsec/plugins/ /usr/lib/strongswan/plugins/ 2>/dev/null | grep -E 'ml|openssl|botan|wolf' | tr '\n' ' '; echo
sed -e "s/LOCAL/$L/g" -e "s/REMOTE/$R/g" /cfg/swanctl.conf > /etc/swanctl/conf.d/pq.conf
cat > /etc/strongswan.d/zz-log.conf <<'EOF'
charon {
  filelog {
    pq {
      path = /tmp/charon.log
      default = 1
      ike = 2
      cfg = 2
    }
  }
}
EOF
$CHARON >/dev/null 2>&1 &
sleep 3
swanctl --list-algs | grep -iE "ML_KEM" | head -3; swanctl --load-all 2>&1
if [ "$ROLE" = init ]; then
  sleep 5
  swanctl --initiate --child net --timeout 20 2>&1 | grep -E 'IKE_SA|CHILD_SA|INTERMEDIATE|failed' | head -8
  echo "== list-sas"; swanctl --list-sas 2>&1 | head -6
  echo "== log"; grep -E 'selected proposal|IKE_INTERMEDIATE|KE1|ML_KEM' /tmp/charon.log | head -6
  cp /tmp/charon.log /cfg/init-charon.log; touch /cfg/init.done
else
  for i in $(seq 1 60); do [ -f /cfg/init.done ] && break; sleep 1; done
  cp /tmp/charon.log /cfg/resp-charon.log; echo "== responder log"; grep -E 'selected proposal|ML_KEM' /tmp/charon.log | head -3
fi
