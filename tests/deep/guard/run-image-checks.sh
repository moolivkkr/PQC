#!/bin/bash
# Runs the image-level checks against real images. Host needs only docker.
set -u
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
G=$(cd "$(dirname "$0")" && pwd)
L="--label run=pqc-deep-guard"
dig() { docker image inspect --format '{{index .RepoDigests 0}}' "$1"; }
SYFT=$(dig anchore/syft:latest); CONFTEST=$(dig openpolicyagent/conftest:latest)
echo "syft: $SYFT"; echo "conftest: $CONFTEST"
mkdir -p "$G/out/sbom"
echo "=== 1. OpenSSL version via Syft SBOM + conftest"
for img in debian:trixie-slim debian:bookworm-slim python:3.11-slim-bookworm alpine:3.22 amazonlinux:2023; do
  d=$(dig $img); f="$G/out/sbom/$(echo $img | tr ':/' '__').json"
  docker run --rm $L -v /var/run/docker.sock:/var/run/docker.sock "$SYFT" "docker:$d" -o syft-json -q > "$f" 2>/dev/null \
    || docker run --rm $L "$SYFT" "registry:$d" -o syft-json -q > "$f"
  # make the report name readable
  echo "--- $img ($d)"
  docker run --rm $L -v "$G:/g" -w /g "$CONFTEST" test --no-color --policy rules/opa/image --namespace image.openssl "out/sbom/$(basename $f)" | grep -v '^$'
done
echo "=== 2. Go binaries: go version -m (DefaultGODEBUG tlsmlkem)"
GO=$(dig golang:1.25-trixie)
docker run --rm $L -v "$G/rules/image:/chk:ro" "$GO" sh -c '
  set -e
  for v in 1.23 1.24; do
    mkdir -p /src/m$v && cd /src/m$v
    printf "module example.com/m\n\ngo $v\n" > go.mod
    printf "package main\nimport (\"crypto/tls\";\"fmt\")\nfunc main(){ fmt.Println(tls.VersionTLS13) }\n" > main.go
    CGO_ENABLED=0 go build -o /out/app-go$v .
  done
  set +e; sh /chk/check-go-pq.sh /out/app-go1.23 /out/app-go1.24; echo "exit=$?"' || true
echo "=== 3. JDK release check"
for img in eclipse-temurin:21-jre-alpine eclipse-temurin:25-jre-alpine; do
  DOCKER_CREATE_ARGS="$L" sh "$G/rules/image/check-jdk-pq.sh" "$(dig $img)" | sed "s#$(dig $img)#$img#"; echo "exit=$?"
done
