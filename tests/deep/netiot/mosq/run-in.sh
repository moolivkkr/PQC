#!/bin/bash
# Runs inside python:3.13-slim-trixie. Mosquitto broker + clients + AWS CRT (awscrt) PQ tests.
set -u
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null && apt-get install -y -qq mosquitto mosquitto-clients openssl >/dev/null 2>&1
pip install -q --root-user-action=ignore awsiotsdk >/dev/null 2>&1
echo "== versions"; mosquitto -h | head -1; openssl version; pip list 2>/dev/null | grep -iE 'awscrt|awsiotsdk'
python -c "import awscrt.io as i; print('TlsCipherPref:', [m.name for m in i.TlsCipherPref]); print('PQ_DEFAULT supported:', i.TlsCipherPref.PQ_DEFAULT.is_supported())"
C=/etc/mosquitto/certs; mkdir -p $C; cd $C
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 2 -subj /CN=lab-ca -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign -keyout ca.key -out ca.pem 2>/dev/null
for n in server device1; do
  san=""; [ $n = server ] && san="-addext subjectAltName=DNS:localhost"
  openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj /CN=$n $san -keyout $n.key -out $n.csr 2>/dev/null
  openssl x509 -req -in $n.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 2 -copy_extensions copyall -out $n.pem 2>/dev/null
done
chmod 644 *.key
cp /cfg/openssl-pq-only.cnf /etc/mosquitto/
sed 's/^listener 8883/listener 8884/' /cfg/mosquitto.conf > /tmp/pqonly.conf
mosquitto -c /cfg/mosquitto.conf >/tmp/b1.log 2>&1 &
OPENSSL_CONF=/etc/mosquitto/openssl-pq-only.cnf mosquitto -c /tmp/pqonly.conf >/tmp/b2.log 2>&1 &
sleep 2
cat >/tmp/classic.cnf <<'EOF'
openssl_conf = o
[o]
ssl_conf = s
[s]
system_default = d
[d]
Groups = X25519:secp256r1
EOF
pass=0; fail=0
t() { local n=$1 e=$2; shift 2; if "$@" >/tmp/t.out 2>&1; then r=ok; else r=fail; fi
  if [ "$r" = "$e" ]; then pass=$((pass+1)); s=PASS; else fail=$((fail+1)); s=FAIL; fi
  echo "[$s] $n (got $r, want $e)"; grep -E 'Negotiated|CONNECT_|Error|error' /tmp/t.out | head -2; }
SC="openssl s_client -connect localhost:8883 -CAfile $C/ca.pem -cert $C/device1.pem -key $C/device1.key -brief"
t "1 broker (default OpenSSL 3.5) negotiates X25519MLKEM768 with a PQ client" ok bash -c "echo | $SC -groups X25519MLKEM768 2>&1 | grep -q 'group: X25519MLKEM768'"
echo | $SC -groups X25519 2>&1 | grep -iE 'group|Temp Key|Protocol|error'
t "2 broker still accepts a classical-only client (X25519)" ok bash -c "echo | $SC -groups X25519 2>&1 | grep -qiE 'Temp Key: X25519|group: x25519$'"
PUB="mosquitto_pub -h localhost --cafile $C/ca.pem --cert $C/device1.pem --key $C/device1.key -t pq/t -m hi -q 1"
t "3 mosquitto_pub (default) -> PQ-only broker" ok $PUB -p 8884
t "4 mosquitto_pub with classical-only OPENSSL_CONF -> PQ-only broker must fail" fail env OPENSSL_CONF=/tmp/classic.cnf $PUB -p 8884
t "5 mosquitto_pub (default) -> default broker" ok $PUB -p 8883
CRT="python /cfg/crt_mqtt_pq.py localhost 8884 $C/ca.pem $C/device1.pem $C/device1.key"
t "6 awscrt cipher_pref=PQ_DEFAULT -> PQ-only broker" ok $CRT PQ_DEFAULT
t "7 awscrt cipher_pref=DEFAULT -> PQ-only broker (records what the default does)" ok $CRT DEFAULT
t "8 awscrt cipher_pref=TLSv1_2_2025_07 (non-PQ) -> PQ-only broker must fail" fail $CRT TLSv1_2_2025_07
t "9 awscrt PQ_DEFAULT -> default broker (classical-capable)" ok python /cfg/crt_mqtt_pq.py localhost 8883 $C/ca.pem $C/device1.pem $C/device1.key PQ_DEFAULT
echo "== broker log (PQ-only)"; tail -n 5 /tmp/b2.log
echo "RESULT pass=$pass fail=$fail"
