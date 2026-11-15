#!/bin/bash
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"; D=$(cd "$(dirname "$0")" && pwd); cd "$D"
L="--label run=pqc-deep-data"; NET=pqnet-data; T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
SDK=$(grep "^dotnet-sdk:10.0-alpine " digests.txt | awk "{print \$2}"); NGX=$(grep '^nginx:1.29 ' digests.txt | awk '{print $2}')
docker rm -f web >/dev/null 2>&1
docker run -d $L --name web --network $NET -v $D/certs:/etc/nginx/pki:ro -v $D/certs/nginx-dualcert.conf:/etc/nginx/conf.d/default.conf:ro $NGX >/dev/null; sleep 2
T 400 docker run --rm $L --network $NET -v $D/certs:/work $SDK sh -c 'openssl version 2>/dev/null || apk add -q openssl >/dev/null; grep PRETTY /etc/os-release; mkdir /p && cd /p && dotnet new console -o . >/dev/null 2>&1 && cp /work/dotnet/Program.cs . && sed -i "s#<Nullable>enable</Nullable>#<Nullable>enable</Nullable><NoWarn>SYSLIB5006</NoWarn>#" p.csproj && dotnet run 2>&1 | tail -8'
docker rm -f web >/dev/null
