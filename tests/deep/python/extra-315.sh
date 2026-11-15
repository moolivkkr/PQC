#!/bin/bash
# Python 3.15 extras: uvicorn with set_groups (PQ-first and PQ-only) and pq_probe.py against the test servers.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"; LBL=run=pqc-deep-python; NET=pqdeep-py
IMG=$(docker image inspect --format '{{index .RepoDigests 0}}' python:3.15-slim-trixie)
docker rm -f pydeep-c >/dev/null 2>&1
docker run -d --label $LBL --name pydeep-c --network-alias pyc --network $NET -v "$W":/w -e PYTHONPATH=/w/site/t315 --entrypoint sleep $IMG 600 >/dev/null
docker exec -d pydeep-c sh -c 'cd /w; PORT=9451 python3 serve_uvicorn.py > /w/out/x315-uv-first.log 2>&1 & PORT=9452 PQ_GROUPS=X25519MLKEM768 python3 serve_uvicorn.py > /w/out/x315-uv-only.log 2>&1 & wait'
sleep 6
for spec in "9451 uvicorn+set_groups:PQ-first" "9452 uvicorn+set_groups:PQ-only"; do
  set -- $spec
  for g in X25519MLKEM768 X25519; do
    r=$(docker exec pydeep-srv sh -c "echo | openssl s_client -connect pyc:$1 -servername pyc -CAfile /w/certs/ca.pem -groups $g -brief 2>&1" | grep -E 'Negotiated TLS1.3 group|Protocol version|alert' | tr '\n' ' ' | cut -c1-140)
    printf 'x315 | server %-30s | client offers %-15s | %s\n' "$2" "$g" "${r:-no output}"
  done
done
echo "x315 | pq_probe.py (PQ-only server, then classical-only server):"
docker exec -e SSL_CERT_FILE=/w/certs/ca.pem pydeep-c python3 /w/pq_probe.py pqsrv:8443 pqsrv:8444; echo "x315 | pq_probe exit=$?"
docker rm -f pydeep-c >/dev/null
