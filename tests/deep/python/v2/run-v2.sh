#!/bin/bash
# Python v2 cases C-F, I on Debian 13 (3.12, 3.13), AL2023 3.12 + OPENSSL_CONF, Lambda 3.11 + legacy shim.
# Usage: run-v2.sh [d312 d313 al-conf l311-shim]   Output: out/<tag>.txt (+ server logs in out/)
export LC_ALL=C; export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
V="$(cd "$(dirname "$0")" && pwd)"; W="$(dirname "$V")"
KIT=/private/tmp/claude-501/-Users-kishoremooli-development-cybersecurity/21fa377a-bc06-46f9-9e49-4588545ba6c2/scratchpad/lambda-pq/layer/pq-tls
LBL=run=pqc-lang2-python; NET=pqlang2-py
T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
dig() { docker pull -q "$1" >/dev/null 2>&1; docker image inspect --format '{{index .RepoDigests 0}}' "$1"; }
mkdir -p "$V/out/srv" "$V/extra"
SRVIMG=$(dig python:3.13-slim-trixie)
docker network inspect $NET >/dev/null 2>&1 || docker network create --label $LBL $NET >/dev/null
docker rm -f python2-srv >/dev/null 2>&1
docker run -d --label $LBL --name python2-srv --network-alias pqsrv --network-alias b.pqsrv --network $NET \
  -v "$V":/w2 --entrypoint sh $SRVIMG /w2/srv2.sh >/dev/null
sleep 5
# shared pure-python extras (truststore) and a certifi copy with the private CA appended
if [ ! -f "$V/extra/.done" ]; then
  docker exec python2-srv pip install -q --disable-pip-version-check --target /w2/extra truststore >/dev/null 2>&1 && touch "$V/extra/.done"
fi
if [ ! -f "$V/certifi-plus/certifi/cacert.pem" ]; then
  mkdir -p "$V/certifi-plus"; cp -R "$W/site/t313/certifi" "$V/certifi-plus/"
  cat "$V/certs/ca.pem" >> "$V/certifi-plus/certifi/cacert.pem"
fi

probe() {  # port name [s_client extra args...]
  local port=$1 name=$2; shift 2
  for g in X25519MLKEM768 X25519; do
    v=""; [ $g = X25519MLKEM768 ] && v="-tls1_3"
    r=$(docker exec python2-srv sh -c "echo Q | openssl s_client -connect pyc:$port -servername pyc -CAfile /w2/certs/ca.pem -groups $g $v -brief $* 2>&1" \
        | grep -aE 'Negotiated TLS1.3 group|Protocol version|Peer certificate|Signature type|alert|error|errno' | grep -v 'Peer signing' | tr '\n' ' ' | cut -c1-230)
    printf '%s | %-46s | client offers %-15s | %s\n' "$TAG" "$name" "$g" "${r:-no output}"
  done
}

start_servers() {  # python
  local PY=$1 CC="/w2/certs"
  docker exec -d python2-c sh -c "cd /w; export PYTHONPATH=/w:$PP;
    $PY /w2/servers.py > /w2/out/$TAG-servers.log 2>&1 &
    U='$PY -m uvicorn app:asgi --host 0.0.0.0'
    \$U --port 9521 --ssl-certfile $CC/rsa.pem --ssl-keyfile $CC/rsa.key > /w2/out/$TAG-uv1.log 2>&1 &
    \$U --port 9522 --ssl-certfile $CC/ec.pem --ssl-keyfile $CC/ec.key > /w2/out/$TAG-uv2.log 2>&1 &
    \$U --port 9523 --ssl-certfile $CC/rsa.pem --ssl-keyfile $CC/rsa-enc.key --ssl-keyfile-password changeit > /w2/out/$TAG-uv3.log 2>&1 &
    \$U --port 9524 --ssl-certfile $CC/ec.pem --ssl-keyfile $CC/ec-enc.key --ssl-keyfile-password changeit > /w2/out/$TAG-uv4.log 2>&1 &
    \$U --port 9525 --ssl-certfile $CC/ec.pem --ssl-keyfile $CC/ec.key --ssl-cert-reqs 2 --ssl-ca-certs $CC/ca.pem > /w2/out/$TAG-uv5.log 2>&1 &
    G='$PY -m gunicorn app:wsgi'
    \$G -b 0.0.0.0:9531 --certfile $CC/rsa.pem --keyfile $CC/rsa.key > /w2/out/$TAG-gu1.log 2>&1 &
    \$G -b 0.0.0.0:9532 --certfile $CC/ec.pem --keyfile $CC/ec.key > /w2/out/$TAG-gu2.log 2>&1 &
    \$G -b 0.0.0.0:9533 --certfile $CC/ec.pem --keyfile $CC/ec-enc.key < /dev/null > /w2/out/$TAG-gu3.log 2>&1 &
    BIND=0.0.0.0:9534 TLS_CERT=$CC/ec.pem TLS_KEY=$CC/ec-enc.key TLS_KEY_PASSWORD=changeit \$G -c /w2/gunicorn-enc.conf.py > /w2/out/$TAG-gu4.log 2>&1 &
    \$G -b 0.0.0.0:9535 --certfile $CC/ec.pem --keyfile $CC/ec.key --cert-reqs 2 --ca-certs $CC/ca.pem > /w2/out/$TAG-gu5.log 2>&1 &
    wait"
  sleep 8
}

server_cases() {
  CL="-cert /w2/certs/client.pem -key /w2/certs/client.key"
  probe 9501 "C ssl.SSLContext RSA PEM"
  probe 9502 "C ssl.SSLContext EC PEM"
  probe 9503 "C ssl.SSLContext RSA encrypted key"
  probe 9504 "C ssl.SSLContext EC encrypted key (callable)"
  probe 9505 "C RSA+EC in one ctx, client ECDSA only" -sigalgs ecdsa_secp256r1_sha256
  probe 9505 "C RSA+EC in one ctx, client RSA only" -sigalgs rsa_pss_rsae_sha256:rsa_pkcs1_sha256
  probe 9506 "C SNI callback, name pyc"
  docker exec python2-srv sh -c "echo Q | openssl s_client -connect pyc:9506 -servername b.pqsrv -CAfile /w2/certs/ca.pem -groups X25519MLKEM768 -tls1_3 -brief 2>&1" \
    | grep -aE 'Negotiated TLS1.3 group|Peer certificate' | tr '\n' ' ' | sed "s/^/$TAG | C SNI callback, name b.pqsrv (PQ-only client) | /"; echo
  probe 9507 "C PKCS#12 -> PEM via cryptography"
  probe 9508 "C PKCS#12 via pyOpenSSL load_pkcs12"
  probe 9509 "C+E ssl server CERT_REQUIRED, client cert" $CL
  probe 9509 "C+E ssl server CERT_REQUIRED, no client cert"
  probe 9510 "F server set_ecdh_curve(prime256v1)"
  probe 9511 "F server maximum_version=TLSv1_2"
  probe 9512 "F server set_ciphers(ECDHE+AESGCM)"
  probe 9521 "C uvicorn RSA --ssl-keyfile"
  probe 9522 "C uvicorn EC --ssl-keyfile"
  probe 9523 "C uvicorn RSA encrypted --ssl-keyfile-password"
  probe 9524 "C uvicorn EC encrypted --ssl-keyfile-password"
  probe 9525 "E uvicorn --ssl-cert-reqs 2, client cert" $CL
  probe 9531 "C gunicorn RSA --keyfile"
  probe 9532 "C gunicorn EC --keyfile"
  probe 9533 "C gunicorn EC encrypted --keyfile only"
  probe 9534 "C gunicorn EC encrypted via ssl_context hook"
  probe 9535 "E gunicorn --cert-reqs 2, client cert" $CL
  for f in servers uv3 uv4 gu3 gu4; do echo "$TAG | log $f: $(grep -aiE 'error|fail|listening|Traceback|password|Booting worker' $V/out/$TAG-$f.log | sort | uniq -c | head -8 | tr -s ' ' | tr '\n' ';' | cut -c1-400)"; done
}

os_store() {  # add the private CA to the OS trust store of the client container
  docker exec python2-c sh -c 'if [ -d /usr/local/share/ca-certificates ]; then cp /w2/certs/ca.pem /usr/local/share/ca-certificates/pq-lang2-ca.crt && update-ca-certificates >/dev/null 2>&1;
    else cp /w2/certs/ca.pem /etc/pki/ca-trust/source/anchors/pq-lang2-ca.pem && update-ca-trust extract; fi; echo os-store rc=$?'
}

run_one() {  # tag image python setup site [docker env flags] [servers=yes]
  TAG=$1; IMG=$(dig $2); PY=$3; SETUP=$4; SITE=$5; ENVF=$6; SRV=${7:-yes}
  PP="/w/site/$SITE:/w2/extra"
  [ "$TAG" = l311-shim ] && PP="/kit/pyshim:$PP"
  docker restart python2-srv >/dev/null; sleep 4
  docker rm -f python2-c >/dev/null 2>&1
  docker run -d --label $LBL --name python2-c --network-alias pyc --network $NET -v "$W":/w -v "$V":/w2 -v "$KIT":/kit:ro \
    -e PYTHONPATH=$PP $ENVF --entrypoint sleep $IMG 3000 >/dev/null
  T 600 docker exec python2-c sh -c "$SETUP" > "$V/out/$TAG-setup.log" 2>&1
  { echo "== $TAG $IMG env=[$ENVF] PYTHONPATH=$PP"
    docker exec python2-c $PY -c "import ssl,sys,os; print(sys.version.split()[0], ssl.OPENSSL_VERSION, 'OPENSSL_CONF=%s' % os.environ.get('OPENSSL_CONF'))"
    T 400 docker exec python2-c $PY /w2/cases.py $TAG pre 2>&1 | grep -v Warning
    echo "$TAG | grpc s_server log (8453 PQ-only mTLS): $(grep -aE 'Peer Temp Key|Peer certificate|Verification|Supported groups' $V/out/srv/mtls-grpc-pq.log | sort | uniq -c | tr -s ' ' | tr '\n' ';' | cut -c1-300)"
    os_store
    T 300 docker exec python2-c $PY /w2/cases.py $TAG os 2>&1 | grep -v Warning
    if [ "$SRV" = yes ]; then start_servers $PY; server_cases; fi
  } > "$V/out/$TAG.txt" 2>&1; cp $V/out/srv/mtls-grpc-pq.log $V/out/$TAG-grpc-srv.log
  docker rm -f python2-c >/dev/null 2>&1
  echo "done $TAG"
}

AL='dnf -y -q install python3.12 openssl ca-certificates >/dev/null 2>&1; python3.12 --version'
for t in ${@:-d312 d313 al-conf l311-shim}; do case $t in
  d312) run_one d312 python:3.12-slim-trixie python3 true b312 ;;
  d313) run_one d313 python:3.13-slim-trixie python3 true t313 ;;
  al-conf) run_one al-conf amazonlinux:2023 python3.12 "$AL" al "-e OPENSSL_CONF=/kit/openssl-pq.cnf" ;;
  al-noconf) run_one al-noconf amazonlinux:2023 python3.12 "$AL" al "" ;;
  l311-shim) run_one l311-shim public.ecr.aws/lambda/python:3.11 python3.11 true l311 "" no ;;
esac; done
echo ALL DONE
