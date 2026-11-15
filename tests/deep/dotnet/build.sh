#!/bin/bash
# Build the .NET probes (client, Kestrel server, Confluent.Kafka, Native AOT) and a test certificate.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"; LBL=run=pqc-deep-dotnet
SDK=mcr.microsoft.com/dotnet/sdk:8.0; TRIXIE=debian:trixie-slim; AL=amazonlinux:2023
for i in $SDK $TRIXIE $AL; do docker pull -q $i >/dev/null; done
d() { docker image inspect --format '{{index .RepoDigests 0}}' "$1"; }
echo "sdk=$(d $SDK) trixie=$(d $TRIXIE) al2023=$(d $AL)"

docker run --rm --label $LBL -v "$W/certs":/c -w /c "$(d $TRIXIE)" sh -c '
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 -subj /CN=pqsrv \
    -addext "subjectAltName=DNS:pqsrv,DNS:kestrel" -keyout server.key -out server.crt 2>/dev/null &&
  openssl pkcs12 -export -in server.crt -inkey server.key -out server.pfx -passout pass:changeit && chmod 644 * && echo certs-ok'

for p in client kestrel kafka; do
  docker run --rm --label $LBL -v "$W/$p":/src -w /src "$(d $SDK)" sh -c "dotnet publish -c Release -o /src/out -v q --nologo >/src/build.log 2>&1 && echo $p-built || (tail -20 /src/build.log; echo $p-FAILED)"
done

# Native AOT: build on Amazon Linux 2023 so the binary matches the provided.al2023 glibc.
docker run --rm --label $LBL -v "$W":/w -w /w/aot "$(d $AL)" sh -c '
  dnf install -y -q dotnet-sdk-8.0 clang zlib-devel >/dev/null 2>&1 || { echo dnf-failed; exit 1; }
  dotnet publish -c Release -r linux-arm64 -o /w/aot/out -v q --nologo >/w/aot/build.log 2>&1 && echo aot-built || (tail -30 /w/aot/build.log; echo aot-FAILED)
  ls -la /w/aot/out | head; ldd /w/aot/out/bootstrap'
