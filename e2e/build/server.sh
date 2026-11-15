#!/bin/bash
# Load balancer target probes (server role): the client images from build/<lang>.sh plus clients/server/*.
# Run after build/<lang>.sh (the FROM images must be in LocalStack ECR; after a restart run build/repush.sh first).
source "$(dirname "$0")/../env.sh"; source "$E2E_DIR/build/lib.sh"
SRC="$E2E_DIR/clients/server"; B="$WORK/build/server"; rm -rf "$B"; mkdir -p "$B"
REG=000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:${PQC_LS_PORT}
C="$WORK/certs"

# shared payload: server cert + key (+ PKCS#12 for Java)
P="$B/payload"; mkdir -p "$P"; cp "$C/server-rsa.crt" "$C/server-rsa.key" "$P/"
openssl pkcs12 -export -in "$C/server-rsa.crt" -inkey "$C/server-rsa.key" -certfile "$C/ca.crt" -name server \
  -passout pass:changeit -out "$P/server.p12" 2>/dev/null
chmod 644 "$P"/*

# Python, Node: scripts
cp "$SRC/server.py" "$SRC/server.js" "$P/"
# Java: compile once for Java 8+
mkdir -p "$B/java"; cp "$SRC/java/Server.java" "$B/java/"
docker run --rm "${LBL[@]}" -v "$B/java":/w -w /w public.ecr.aws/amazoncorretto/amazoncorretto@sha256:597dbb85c5809a306df0675f491832ec18480cf03754c95a3985cbe645272b85 \
  javac -nowarn --release 8 -d /w/out Server.java 2>&1 | grep -v "^warning\|^Note\|warning$" || true
cp "$B/java/out/"*.class "$P/"
# Go: same source, three builds (toolchain x go line), as the Go tab's matrix
G="$B/go"; mkdir -p "$G/bin"
for spec in "1.26:1.26:server-1.26" "1.26:1.23:server-1.26-go1.23" "1.23:1.23:server-1.23"; do
  IFS=: read -r tc line name <<<"$spec"
  rm -rf "$G/src"; cp -r "$SRC/go" "$G/src"; printf 'module pqc-e2e/server\n\ngo %s\n' "$line" > "$G/src/go.mod"
  docker run --rm "${LBL[@]}" -v "$G/src":/w -v "$G/bin":/out -w /w -e GOTOOLCHAIN=local -e CGO_ENABLED=0 golang:$tc \
    go build -trimpath -o "/out/$name" . 
done
cp "$G/bin/"* "$P/"
# .NET: framework-dependent builds for net8.0 and net10.0
D="$B/dotnet"; mkdir -p "$D/src" "$D/out"; cp "$SRC/dotnet/"* "$D/src/"
docker run --rm "${LBL[@]}" -v "$D/src":/src:ro -v "$D/out":/out mcr.microsoft.com/dotnet/sdk:10.0-alpine sh -c '
  cp -r /src /b && cd /b && for f in net8.0 net10.0; do dotnet publish -c Release -f $f -o /out/$f --nologo -v q >/dev/null || exit 1; done'
mkdir -p "$P/net8" "$P/net10"; cp -r "$D/out/net8.0/." "$P/net8/"; cp -r "$D/out/net10.0/." "$P/net10/"
for f in server-rsa.crt server-rsa.key; do cp "$P/$f" "$P/net8/"; cp "$P/$f" "$P/net10/"; done

# images: <client image> + /srv-pqc
for img in pqc-python:al2023 pqc-python:al2023-policy pqc-python:lib-3.13-slim-trixie pqc-python:lib-3.12-slim-bookworm \
           pqc-node:lib-24-slim pqc-node:lib-20-slim pqc-node:al2023 pqc-node:al2023-policy \
           pqc-go:distroless \
           pqc-java:corretto8 pqc-java:corretto17 pqc-java:corretto21 pqc-java:corretto25 \
           pqc-dotnet:mcr-runtime-8.0 pqc-dotnet:mcr-runtime-10.0-alpine pqc-dotnet:al2023 pqc-dotnet:al2023-policy pqc-dotnet:mcr-aspnet-10.0-resolute; do
  printf 'FROM %s/%s\nCOPY --chmod=755 payload/ /srv-pqc/\n' "$REG" "$img" > "$B/Dockerfile"
  ecr_build pqc-server "$(echo "$img" | sed 's/^pqc-//; s/:/-/')" "$B" "$B/Dockerfile"
done
