#!/bin/bash
# .NET PQ v2 matrix: cases C (Kestrel certificates), D (trust), E (mTLS), F (TLS settings)
# on aspnet 8.0 (Debian 12), 8.0-alpine, 10.0-alpine, 10.0-resolute (Ubuntu 26.04), AL2023 + OPENSSL_CONF.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"; LBL=run=pqc-lang2-dotnet; NET=pqnet2-dotnet
ONLY="${1:-all}"   # all | client | server
dg() { docker pull -q "$1" >/dev/null 2>&1; docker image inspect --format '{{index .RepoDigests 0}}' "$1"; }
MCR=mcr.microsoft.com/dotnet/aspnet
cp "$W/../../../lambda-pq/layer/pq-tls/openssl-pq.cnf" "$W/openssl-pq.cnf"
cp "$W/../Dockerfile.al2023-test" "$W/Dockerfile.al2023-test"
docker build -q --label $LBL -t pqc-lang2-dotnet-al2023:test -f "$W/Dockerfile.al2023-test" "$W" >/dev/null && echo "al2023 test image built"
declare -a NAMES DIGS ENVS
i=0; for t in 8.0 8.0-alpine 10.0-alpine 10.0-resolute; do NAMES[$i]="aspnet:$t"; DIGS[$i]=$(dg $MCR:$t); ENVS[$i]="-e X=1"; i=$((i+1)); done
NAMES[$i]="AL2023 aspnetcore-8 + OPENSSL_CONF"; DIGS[$i]=pqc-lang2-dotnet-al2023:test; ENVS[$i]="-e OPENSSL_CONF=/etc/pq-tls/openssl-pq.cnf"
for k in "${!NAMES[@]}"; do echo "image ${NAMES[$k]} = ${DIGS[$k]}"; done
TRIXIE=$(dg debian:trixie-slim); echo "tools = $TRIXIE"

docker network create --label $LBL $NET >/dev/null
docker run -d --label $LBL --name dotnet2-tools --network $NET --network-alias pqsrv --network-alias clsrv -v "$W/certs":/certs "$TRIXIE" sh -c '
  apt-get update -qq >/dev/null && apt-get install -y -qq openssl >/dev/null 2>&1
  mkdir -p /certs/hashdir && cp /certs/ca.crt /certs/hashdir/ && openssl rehash /certs/hashdir
  cd /certs; S="-cert server-ec.crt -key server-ec.key -cert_chain ca.crt -www -quiet"
  openssl s_server -accept 8443 -groups X25519MLKEM768 -tls1_3 $S &
  openssl s_server -accept 8444 -groups X25519 $S &
  openssl s_server -accept 8445 -groups X25519MLKEM768 -tls1_3 $S -Verify 1 -CAfile ca.crt -verify_return_error &
  openssl s_server -accept 8446 -groups X25519 $S -Verify 1 -CAfile ca.crt -verify_return_error &
  openssl version > /certs/ready; wait' >/dev/null
for n in $(seq 1 60); do [ -f "$W/certs/ready" ] && break; sleep 2; done
echo "tools openssl: $(cat "$W/certs/ready")"

if [ "$ONLY" != server ]; then
echo; echo "=========== CLIENT CASES D, E, F ==========="
for k in "${!NAMES[@]}"; do
  echo; echo "--- ${NAMES[$k]}"
  docker run --rm --label $LBL --name dotnet2-client --network $NET ${ENVS[$k]} -v "$W":/w:ro -v "$W/certs":/certs:ro \
    --entrypoint sh "${DIGS[$k]}" -c '(. /etc/os-release; echo "  os=$PRETTY_NAME dotnet=$(ls /usr/share/dotnet/shared/Microsoft.NETCore.App 2>/dev/null || ls /usr/lib64/dotnet/shared/Microsoft.NETCore.App 2>/dev/null)"); sh /w/client-cases.sh' 2>&1
done
fi

if [ "$ONLY" != client ]; then
echo; echo "=========== KESTREL SERVER CASES C, E, F (probed with OpenSSL 3.5 s_client) ==========="
probe() { # $1 sni  $2 groups  $3 extra s_client args
  docker exec dotnet2-tools sh -c "printf 'GET / HTTP/1.1\r\nHost: $1\r\nConnection: close\r\n\r\n' | openssl s_client -connect kestrel:8443 -servername $1 -groups $2 -CAfile /certs/ca.crt -verify_return_error -brief -ign_eof $3 2>&1" \
    | grep -E 'Negotiated TLS1.3 group|Signature type|Protocol version|^ok |alert|error' | grep -v '^DONE' | sed 's/^/      /' | tr '\n' ' ' | sed 's/  */ /g'
}
K="-e Kestrel__Endpoints__Https__Url=https://0.0.0.0:8443"
PFX_EC="-e Kestrel__Certificates__Default__Path=/certs/server-ec.pfx -e Kestrel__Certificates__Default__Password=changeit"
declare -a MODES=(
  "C1 PFX, EC key (Certificates:Default Path+Password)|$PFX_EC|ec.test|"
  "C2 PFX, RSA key|-e Kestrel__Certificates__Default__Path=/certs/server-rsa.pfx -e Kestrel__Certificates__Default__Password=changeit|rsa.test|"
  "C3 PEM pair, EC (Path+KeyPath, chain in Path)|-e Kestrel__Certificates__Default__Path=/certs/server-ec-chain.crt -e Kestrel__Certificates__Default__KeyPath=/certs/server-ec.key|ec.test|"
  "C4 PEM pair, RSA, encrypted PKCS#8 key (KeyPath+Password)|-e Kestrel__Certificates__Default__Path=/certs/server-rsa-chain.crt -e Kestrel__Certificates__Default__KeyPath=/certs/server-rsa-enc.key -e Kestrel__Certificates__Default__Password=changeit|rsa.test|"
  "C5a ServerCertificateSelector (code), SNI ec.test|-e MODE=selector|ec.test|"
  "C5b ServerCertificateSelector (code), SNI rsa.test|-e MODE=selector|rsa.test|"
  "C6a Endpoint Sni config section, SNI ec.test|-e Kestrel__Endpoints__Https__Sni__ec.test__Certificate__Path=/certs/server-ec.pfx -e Kestrel__Endpoints__Https__Sni__ec.test__Certificate__Password=changeit -e Kestrel__Endpoints__Https__Sni__rsa.test__Certificate__Path=/certs/server-rsa.pfx -e Kestrel__Endpoints__Https__Sni__rsa.test__Certificate__Password=changeit|ec.test|"
  "C6b Endpoint Sni config section, SNI rsa.test|-e Kestrel__Endpoints__Https__Sni__ec.test__Certificate__Path=/certs/server-ec.pfx -e Kestrel__Endpoints__Https__Sni__ec.test__Certificate__Password=changeit -e Kestrel__Endpoints__Https__Sni__rsa.test__Certificate__Path=/certs/server-rsa.pfx -e Kestrel__Endpoints__Https__Sni__rsa.test__Certificate__Password=changeit|rsa.test|"
  "C7 X509Store CurrentUser/My (config Subject+Store+Location)|-e MODE=store -e STORE_IMPORT_PFX=/certs/server-ec.pfx -e STORE_IMPORT_PASSWORD=changeit -e Kestrel__Certificates__Default__Subject=pq-server-ec -e Kestrel__Certificates__Default__Store=My -e Kestrel__Certificates__Default__Location=CurrentUser -e Kestrel__Certificates__Default__AllowInvalid=true|ec.test|"
  "E4 RequireCertificate, client sends cert|-e MTLS=1 -e CA_FILE=/certs/ca.crt $PFX_EC|ec.test|-cert /certs/client.crt -key /certs/client.key"
  "E5 RequireCertificate, no client cert (expect no 'ok')|-e MTLS=1 -e CA_FILE=/certs/ca.crt $PFX_EC|ec.test|"
  "E6 RequireCertificate, cert from another CA (expect no 'ok')|-e MTLS=1 -e CA_FILE=/certs/ca.crt $PFX_EC|ec.test|-cert /certs/other-ca.crt -key /certs/other-ca.key"
  "F3 SslProtocols=Tls12 (expect PQ FAIL)|-e TLS12=1 $PFX_EC|ec.test|"
  "F4 CipherSuitesPolicy TLS1.3 AES-GCM only|-e CIPHERS13=1 $PFX_EC|ec.test|"
)
for k in "${!NAMES[@]}"; do
  echo; echo "--- ${NAMES[$k]}"
  for m in "${MODES[@]}"; do
    IFS='|' read -r label envs sni extra <<<"$m"
    docker run -d --label $LBL --name dotnet2-kestrel --network $NET --network-alias kestrel ${ENVS[$k]} $K $envs \
      -v "$W/kserver/out":/app:ro -v "$W/certs":/certs:ro -w /app --entrypoint dotnet "${DIGS[$k]}" /app/kserver.dll >/dev/null
    for n in $(seq 1 40); do docker logs dotnet2-kestrel 2>&1 | grep -qE "Now listening|Unhandled|fail:" && break; sleep 0.5; done
    if ! docker logs dotnet2-kestrel 2>&1 | grep -q "Now listening"; then
      echo "  $label: SERVER DID NOT START: $(docker logs dotnet2-kestrel 2>&1 | grep -m2 -E 'Exception|fail' | tr '\n' ' ' | cut -c1-300)"
    else
      echo "  $label"
      echo "    PQ client   :$(probe $sni X25519MLKEM768 "-tls1_3 $extra")"
      echo "    X25519 only :$(probe $sni X25519 "$extra")"
    fi
    docker rm -f dotnet2-kestrel >/dev/null 2>&1
  done
done
fi

echo; echo "=== cleanup (own label only) ==="
n=$(docker ps -aq --filter label=$LBL | wc -l | tr -d ' '); docker rm -f $(docker ps -aq --filter label=$LBL) >/dev/null 2>&1
docker network rm $NET >/dev/null; rm -f "$W/certs/ready"; echo "removed containers=$n network=$NET"
