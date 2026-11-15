#!/bin/bash
# F3 follow-up: Kestrel SslProtocols=Tls12 with an EC cert. Why did a classical client offering only X25519 fail?
# Hypothesis: in TLS 1.2 the client's supported_groups list also limits the ECDSA certificate curve (P-256).
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"; LBL=run=pqc-lang2-dotnet; NET=pqnet2-dotnet-f3
A=$(docker image inspect --format '{{index .RepoDigests 0}}' mcr.microsoft.com/dotnet/aspnet:10.0-alpine)
T=$(docker image inspect --format '{{index .RepoDigests 0}}' debian:trixie-slim)
docker network create --label $LBL $NET >/dev/null
docker run -d --label $LBL --name dotnet2-tools-f3 --network $NET -v "$W/certs":/certs:ro "$T" sh -c 'apt-get update -qq >/dev/null; apt-get install -y -qq openssl >/dev/null 2>&1; touch /tmp/ready; sleep 600' >/dev/null
for i in $(seq 1 60); do docker exec dotnet2-tools-f3 test -f /tmp/ready 2>/dev/null && break; sleep 2; done
for cert in ec rsa; do
  docker run -d --label $LBL --name dotnet2-kestrel-f3 --network $NET --network-alias kestrel -e TLS12=1 \
    -e Kestrel__Endpoints__Https__Url=https://0.0.0.0:8443 -e Kestrel__Certificates__Default__Path=/certs/server-$cert.pfx -e Kestrel__Certificates__Default__Password=changeit \
    -v "$W/kserver/out":/app:ro -v "$W/certs":/certs:ro -w /app --entrypoint dotnet "$A" /app/kserver.dll >/dev/null
  for i in $(seq 1 40); do docker logs dotnet2-kestrel-f3 2>&1 | grep -q "Now listening" && break; sleep 0.5; done
  for g in X25519 X25519:P-256 X25519MLKEM768:X25519:P-256; do
    r=$(docker exec dotnet2-tools-f3 sh -c "echo | openssl s_client -connect kestrel:8443 -groups $g -brief 2>&1" | grep -E 'Protocol version|Server Temp Key|Negotiated|alert' | head -2 | tr '\n' ' ')
    echo "Tls12-only Kestrel, $cert cert, client groups $g: $r"
  done
  docker rm -f dotnet2-kestrel-f3 >/dev/null
done
docker rm -f dotnet2-tools-f3 >/dev/null; docker network rm $NET >/dev/null; echo "cleanup done"
