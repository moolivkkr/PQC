#!/bin/bash
# .NET PQ TLS test matrix: clients (SslStream + HttpClient), Kestrel server, Confluent.Kafka, Npgsql, Native AOT.
# PQ-only server = openssl s_server -groups X25519MLKEM768 -tls1_3 (8443); classical-only = -groups X25519 (8444).
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"; KIT="$W/../../lambda-pq/layer/pq-tls"; LBL=run=pqc-deep-dotnet; NET=pqnet-dotnet
cp "$KIT/openssl-pq.cnf" "$W/openssl-pq.cnf"
dg() { docker pull -q "$1" >/dev/null 2>&1; docker image inspect --format '{{index .RepoDigests 0}}' "$1"; }
MCR=mcr.microsoft.com/dotnet/aspnet
IMGS="$MCR:8.0 $MCR:8.0-alpine $MCR:10.0 $MCR:10.0-alpine $MCR:10.0-azurelinux3.0 $MCR:10.0-resolute"
CHISELED="$MCR:10.0-noble-chiseled $MCR:10.0-resolute-chiseled"
TRIXIE=$(dg debian:trixie-slim)
docker build -q --label $LBL -t pqc-deep-dotnet-al2023:test -f "$W/Dockerfile.al2023-test" "$W" >/dev/null && echo "al2023 test image built"
AL=pqc-deep-dotnet-al2023:test

docker network create --label $LBL $NET >/dev/null
docker run -d --label $LBL --name pqsrv-dotnet --network $NET --network-alias pqsrv -v "$W/certs":/certs "$TRIXIE" sh -c '
  apt-get update -qq >/dev/null && apt-get install -y -qq openssl >/dev/null 2>&1
  cd /certs; if [ ! -f server.pfx ]; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 -subj /CN=pqsrv \
      -addext "subjectAltName=DNS:pqsrv,DNS:kestrel,DNS:pg" -keyout server.key -out server.crt 2>/dev/null
    openssl pkcs12 -export -in server.crt -inkey server.key -out server.pfx -passout pass:changeit; chmod 644 *; fi
  openssl version > /certs/ready
  openssl s_server -accept 8443 -groups X25519MLKEM768 -tls1_3 -cert server.crt -key server.key -www -quiet &
  openssl s_server -accept 8444 -groups X25519 -cert server.crt -key server.key -www -quiet &
  wait' >/dev/null
for i in $(seq 1 60); do [ -f "$W/certs/ready" ] && break; sleep 2; done
echo "pqsrv: $(cat "$W/certs/ready")"
echo; echo "=== CLIENT (SslStream + HttpClient) ==="
osinfo='(. /etc/os-release; printf "%s | " "$PRETTY_NAME"); (openssl version 2>/dev/null || ls /usr/lib/*/libssl.so.* /usr/lib/libssl.so.* /usr/lib64/libssl.so.* 2>/dev/null | head -1) | tr "\n" " "; printf "| "; '
for img in $IMGS; do d=$(dg $img); printf '%-48s %s\n' "$img" "$(docker run --rm --label $LBL --network $NET -v "$W":/w:ro --entrypoint sh $d -c "$osinfo dotnet /w/client/out/client.dll")"; done
for img in $CHISELED; do d=$(dg $img); printf '%-48s %s\n' "$img" "$(docker run --rm --label $LBL --network $NET -v "$W":/w:ro --entrypoint dotnet $d /w/client/out/client.dll)"; done
printf '%-48s %s\n' "AL2023 dnf aspnetcore-8 (default)" "$(docker run --rm --label $LBL --network $NET -v "$W":/w:ro --entrypoint sh $AL -c "$osinfo dotnet /w/client/out/client.dll")"
printf '%-48s %s\n' "AL2023 dnf aspnetcore-8 + OPENSSL_CONF" "$(docker run --rm --label $LBL --network $NET -v "$W":/w:ro -e OPENSSL_CONF=/etc/pq-tls/openssl-pq.cnf --entrypoint sh $AL -c "$osinfo dotnet /w/client/out/client.dll")"
printf '%-48s %s\n' "AL2023 dnf aspnetcore-8 + DEFAULT:PQ policy" "$(docker run --rm --label $LBL --network $NET -v "$W":/w:ro --entrypoint sh $AL -c "update-crypto-policies --set DEFAULT:PQ >/dev/null 2>&1; update-crypto-policies --show | tr '\n' ' '; dotnet /w/client/out/client.dll")"

echo; echo "=== NATIVE AOT (built on AL2023) in public.ecr.aws/lambda/provided:al2023 ==="
PA=$(dg public.ecr.aws/lambda/provided:al2023)
printf '%-48s %s\n' "provided.al2023 AOT (default)" "$(docker run --rm --label $LBL --network $NET -v "$W":/w:ro --entrypoint /w/aot/out/bootstrap $PA)"
printf '%-48s %s\n' "provided.al2023 AOT + OPENSSL_CONF" "$(docker run --rm --label $LBL --network $NET -v "$W":/w:ro -e OPENSSL_CONF=/w/openssl-pq.cnf --entrypoint /w/aot/out/bootstrap $PA)"

echo; echo "=== KESTREL SERVER (appsettings.json endpoint; probed with openssl 3.5 s_client) ==="
probe() { # $1 label
  for i in $(seq 1 30); do docker logs kestrel-dotnet 2>&1 | grep -q "Now listening" && break; sleep 1; done
  pq=$(docker exec pqsrv-dotnet sh -c 'echo | openssl s_client -connect kestrel:8443 -groups X25519MLKEM768 -tls1_3 -brief 2>&1' | grep -E "Negotiated TLS1.3 group|Protocol version|alert number" | head -3 | tr '\n' ' ')
  cl=$(docker exec pqsrv-dotnet sh -c 'echo | openssl s_client -connect kestrel:8443 -groups X25519 -brief 2>&1' | grep -E "Negotiated TLS1.3 group|Protocol version|alert number" | head -3 | tr '\n' ' ')
  printf '%-48s PQ-client: %s|| classical-client: %s\n' "$1" "$pq" "$cl"
  docker rm -f kestrel-dotnet >/dev/null 2>&1
}
for img in $IMGS; do d=$(dg $img); docker run -d --label $LBL --name kestrel-dotnet --network $NET --network-alias kestrel -w /app -v "$W/kestrel/out":/app:ro -v "$W/certs":/certs:ro --entrypoint dotnet $d /app/kestrel.dll >/dev/null; probe "$img"; done
for img in $CHISELED; do d=$(dg $img); docker run -d --label $LBL --name kestrel-dotnet --network $NET --network-alias kestrel -w /app -v "$W/kestrel/out":/app:ro -v "$W/certs":/certs:ro --entrypoint dotnet $d /app/kestrel.dll >/dev/null; probe "$img"; done
docker run -d --label $LBL --name kestrel-dotnet --network $NET --network-alias kestrel -w /app -v "$W/kestrel/out":/app:ro -v "$W/certs":/certs:ro --entrypoint dotnet $AL /app/kestrel.dll >/dev/null; probe "AL2023 aspnetcore-8 (default)"
docker run -d --label $LBL --name kestrel-dotnet --network $NET --network-alias kestrel -w /app -v "$W/kestrel/out":/app:ro -v "$W/certs":/certs:ro -e OPENSSL_CONF=/etc/pq-tls/openssl-pq.cnf --entrypoint dotnet $AL /app/kestrel.dll >/dev/null; probe "AL2023 aspnetcore-8 + OPENSSL_CONF"
d=$(dg $MCR:10.0-alpine); docker run -d --label $LBL --name kestrel-dotnet --network $NET --network-alias kestrel -w /app -v "$W/kestrel/out":/app:ro -v "$W/certs":/certs:ro -e Kestrel__Endpoints__Https__SslProtocols__0=Tls12 -e Kestrel__Endpoints__Https__SslProtocols__1=Tls12 --entrypoint dotnet $d /app/kestrel.dll >/dev/null; probe "10.0-alpine, SslProtocols=Tls12 only (pitfall)"
d=$(dg $MCR:10.0-alpine); docker run -d --label $LBL --name kestrel-dotnet --network $NET --network-alias kestrel -w /app -v "$W/kestrel/out":/app:ro -v "$W/certs":/certs:ro --entrypoint dotnet $d /app/kestrel.dll >/dev/null
for i in $(seq 1 30); do docker logs kestrel-dotnet 2>&1 | grep -q "Now listening" && break; sleep 1; done
echo "curl through PQ (alpine kestrel): $(docker exec pqsrv-dotnet sh -c 'apt-get install -y -qq curl >/dev/null 2>&1; curl -sk https://kestrel:8443/ --curves X25519MLKEM768 -w "curl-http=%{http_code}"')"
docker rm -f kestrel-dotnet >/dev/null 2>&1

echo; echo "=== CONFLUENT.KAFKA (librdkafka bundled OpenSSL) against s_server ==="
for img in $MCR:8.0 $MCR:10.0; do d=$(dg $img)
  for port in 8443 8444; do for curves in "" "X25519"; do
    out=$(docker run --rm --label $LBL --network $NET -v "$W":/w:ro -e KAFKA_CURVES=$curves --entrypoint sh $d -c "dotnet /w/kafka/out/kafka.dll $port 2>&1" | grep -E "SSL handshake|handshake failed|Connected to|ApiVersion|alert" | tr '\n' ' ' | cut -c1-400)
    printf '%-22s port=%s curves=%-7s %s\n' "${img##*/}" $port "${curves:-default}" "$out"; done; done; done


echo; echo "=== cleanup (own label only) ==="
n=$(docker ps -aq --filter label=$LBL | wc -l | tr -d ' '); docker rm -f $(docker ps -aq --filter label=$LBL) >/dev/null 2>&1
docker network rm $NET >/dev/null; rm -f "$W/certs/ready"; echo "removed containers=$n network=$NET"
