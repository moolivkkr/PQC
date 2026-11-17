#!/usr/bin/env bash
# Zeek detection check: run Zeek 7.2 on the observer's network interface while a PQ client (OpenSSL 3.5) and a
# classical client (OpenSSL 3.0) connect, then read ssl.log. Expected: field `curve` = X25519MLKEM768 for the PQ
# client's TLS 1.3 handshakes and x25519 for the classical client and for every TLS 1.2 handshake.
# Zeek loads configs/.../pq-tls.zeek (adds ssl.log column pq, raises PQTLS::Classical_Key_Exchange) and writes JSON
# logs, the format configs/inventory/athena-views.sql reads (table zeek_ssl).
# Needs the e2e stack up (bash run.sh or docker compose up). Writes e2e/.work/zeek/ssl.log. Exit 1 on mismatch.
set -euo pipefail
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
cd "$(dirname "$0")/.."
ZEEK=zeek/zeek@sha256:5a4712846e75fab70dbf3c329dbc7191f7057fb7351de157ee18344cf1bad85a   # zeek 7.2.2
PQ=python:3.14-slim CLASSIC=python:3.11-slim-bookworm
W="$PWD/.work/zeek"; rm -rf "$W"; mkdir -p "$W"
NET=$(docker inspect pqc-e2e-observer -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')
docker rm -f pqc-e2e-zeek >/dev/null 2>&1 || true
docker run -d --name pqc-e2e-zeek --label project=pqc-e2e --network container:pqc-e2e-observer \
  --cap-add NET_RAW --cap-add NET_ADMIN -v "$W":/logs -w /logs \
  -v "$PWD/../configs/network-devices-and-egress/opt/zeek/share/zeek/site/pq-tls.zeek":/scripts/pq-tls.zeek:ro \
  "$ZEEK" zeek -C -i eth0 LogAscii::use_json=T /scripts/pq-tls.zeek >/dev/null
sleep 6
cat > "$W/client.py" <<'PY'
import socket, ssl
for port in (8443, 8447, 8448):   # hybrid, tls12, mldsa-dual
    ctx = ssl.create_default_context(cafile="/certs/ca-both.crt")
    s = ctx.wrap_socket(socket.create_connection(("10.250.0.20", port), timeout=5), server_hostname="pq-observer")
    s.sendall(b"GET /probe HTTP/1.0\r\nHost: pq-observer\r\n\r\n"); b"".join(iter(lambda: s.recv(4096), b""))
PY
for img in "$PQ" "$CLASSIC"; do
  docker run --rm --network "$NET" -v "$W":/w:ro -v "$PWD/.work/certs":/certs:ro "$img" python /w/client.py
done
sleep 4; docker stop pqc-e2e-zeek >/dev/null; docker rm pqc-e2e-zeek >/dev/null
got=$(python3 -c '
import json, sys
for l in open(sys.argv[1]):
    r = json.loads(l); print(r["id.resp_p"], r["version"], r.get("curve"), r.get("pq"))' "$W/ssl.log" | sort)
want=$(printf '%s\n' "8443 TLSv13 X25519MLKEM768 True" "8443 TLSv13 x25519 False" "8447 TLSv12 x25519 False" \
  "8447 TLSv12 x25519 False" "8448 TLSv13 X25519MLKEM768 True" "8448 TLSv13 x25519 False" | sort)
notices=$(grep -c 'PQTLS::Classical_Key_Exchange' "$W/notice.log" || true)
echo "$got"; echo "notices: $notices (want 3: one per classical server port and group, suppressed for 1h)"
[ "$got" = "$want" ] && [ "$notices" = 3 ] && echo "ZEEK CHECK PASS" || { echo "ZEEK CHECK FAIL"; exit 1; }
