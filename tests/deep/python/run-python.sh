#!/bin/bash
# Python PQ TLS matrix: client libraries and servers on trixie / bookworm / AL2023 (+conf) / 3.15.
# Usage: run-python.sh [tag ...]   (default: all). Output: out/<tag>.txt, server logs under out/.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"; LBL=run=pqc-deep-python; NET=pqdeep-py
KIT=/private/tmp/claude-501/-Users-kishoremooli-development-cybersecurity/21fa377a-bc06-46f9-9e49-4588545ba6c2/scratchpad/lambda-pq/layer/pq-tls
T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
dig() { docker pull -q "$1" >/dev/null 2>&1; docker image inspect --format '{{index .RepoDigests 0}}' "$1"; }
mkdir -p "$W/out/srv" "$W/site"
SRVIMG=$(dig python:3.13-slim-trixie); PGIMG=$(dig postgres:18)
docker network inspect $NET >/dev/null 2>&1 || docker network create --label $LBL $NET >/dev/null
if ! docker ps -q --filter name=^pydeep-srv$ | grep -q .; then
  docker run -d --label $LBL --name pydeep-srv --network-alias pqsrv --network $NET -v "$W":/w --entrypoint sh $SRVIMG /w/srv.sh >/dev/null
  sleep 4
fi
if ! docker ps -q --filter name=^pydeep-pg$ | grep -q .; then
  docker run -d --label $LBL --name pydeep-pg --network-alias pgsrv --network $NET -v "$W":/w --entrypoint sh $PGIMG /w/pgsrv.sh >/dev/null
  sleep 6
fi
PKGS="requests urllib3 httpx aiohttp boto3 awscrt grpcio pyopenssl cryptography psycopg[binary] psycopg2-binary pymysql redis confluent-kafka uvicorn gunicorn hypercorn"

# server-side probe: openssl s_client (3.5, in pqsrv) against servers running inside pyc
probe_servers() {  # $1 tag
  for spec in "9443 uvicorn" "9444 gunicorn" "9445 hypercorn" "9446 grpcio-server" "9447 gunicorn+ssl_context:PQ-first" "9448 gunicorn+ssl_context:PQ-only"; do
    set -- $spec; port=$1; name=$2
    for g in X25519MLKEM768 X25519; do
      v=""; [ $g = X25519MLKEM768 ] && v="-tls1_3"
      r=$(docker exec pydeep-srv sh -c "echo | openssl s_client -connect pyc:$port -servername pyc -CAfile /w/certs/ca.pem -groups $g $v -brief 2>&1" \
          | grep -E 'Negotiated TLS1.3 group|Protocol version|alert|errno|connect:' | tr '\n' ' ' | cut -c1-150)
      printf '%s | server %-34s | client offers %-15s | %s\n' "$TAG" "$name" "$g" "${r:-no output}"
    done
  done
}

start_servers() {  # $1 python, $2 extra env
  docker exec -d $2 pydeep-c sh -c "cd /w; export PYTHONPATH=/w/site/$SITE;
    $1 -m uvicorn app:asgi --host 0.0.0.0 --port 9443 --ssl-keyfile /w/certs/leaf.key --ssl-certfile /w/certs/leaf.pem > /w/out/$TAG-uvicorn.log 2>&1 &
    $1 -m gunicorn -b 0.0.0.0:9444 --certfile /w/certs/leaf.pem --keyfile /w/certs/leaf.key app:wsgi > /w/out/$TAG-gunicorn.log 2>&1 &
    $1 -m hypercorn --bind 0.0.0.0:9445 --certfile /w/certs/leaf.pem --keyfile /w/certs/leaf.key app:asgi > /w/out/$TAG-hypercorn.log 2>&1 &
    $1 grpc_server.py 9446 > /w/out/$TAG-grpcsrv.log 2>&1 &
    $1 -m gunicorn -c /w/gunicorn.conf.py app:wsgi > /w/out/$TAG-gunicorn-ctx.log 2>&1 &
    PQ_GROUPS=X25519MLKEM768 $1 -m gunicorn -c /w/gunicorn.conf.py -b 0.0.0.0:9448 app:wsgi > /w/out/$TAG-gunicorn-pqonly.log 2>&1 &
    wait"
  sleep 6
}

srvlog() {  # handshakes seen by s_server per family since restart (client offer + negotiated key)
  for f in grpc kafka redis; do for s in pq classical; do
    printf "%s | s_server log %-6s %-9s | %s\n" "$TAG" $f $s "$(grep -a -E "^(Peer Temp Key|Supported groups)" $W/out/srv/$f-$s.log | sort | uniq -c | tr -s " " | tr "\n" ";")"
  done; done
}

run_one() {  # tag image python setup [envflags]
  TAG=$1; IMG=$(dig $2); PY=$3; SETUP=$4; ENVF=$5; SITE=${SITE_OVERRIDE:-$TAG}
  docker restart pydeep-srv >/dev/null; sleep 3
  docker rm -f pydeep-c >/dev/null 2>&1
  docker run -d --label $LBL --name pydeep-c --network-alias pyc --network $NET -v "$W":/w -v "$KIT":/kit:ro $ENVF --entrypoint sleep $IMG 3000 >/dev/null
  T 900 docker exec pydeep-c sh -c "$SETUP" > "$W/out/$TAG-setup.log" 2>&1
  if [ ! -f "$W/site/$SITE/.done" ]; then
    for p in $PKGS; do T 300 docker exec pydeep-c $PY -m pip install -q --disable-pip-version-check --only-binary :all: --target /w/site/$SITE "$p" >> "$W/out/$TAG-setup.log" 2>&1 || echo "pip failed: $p" >> "$W/out/$TAG-setup.log"; done
    touch "$W/site/$SITE/.done"
  fi
  { echo "== $TAG $IMG env=[$ENVF]"
    T 240 docker exec -e PYTHONPATH=/w/site/$SITE pydeep-c $PY /w/pyclients.py $TAG 2>&1 | grep -v Warning
    srvlog
    start_servers $PY
    probe_servers
  } > "$W/out/$TAG.txt" 2>&1
  docker rm -f pydeep-c >/dev/null 2>&1
  echo "done $TAG"
}

DEB='true'
AL='dnf -y -q install python3.12 python3.12-pip openssl >/dev/null 2>&1 || dnf -y -q install python3-pip openssl >/dev/null; python3.12 --version || python3 --version'
for t in ${@:-t313 t315 b312 al al-conf}; do case $t in
  t313) run_one t313 python:3.13-slim-trixie python3 "$DEB" ;;
  t315) run_one t315 python:3.15-slim-trixie python3 "$DEB" ;;
  b312) run_one b312 python:3.12-slim-bookworm python3 "$DEB" ;;
  al)   run_one al amazonlinux:2023 python3.12 "$AL" ;;
  al-conf) SITE_OVERRIDE=al run_one al-conf amazonlinux:2023 python3.12 "$AL" "-e OPENSSL_CONF=/kit/openssl-pq.cnf" ;;
esac; done
echo ALL DONE
