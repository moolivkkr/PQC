#!/bin/bash
# Go artifacts: one probe source (clients/go) built per toolchain, go line and build mode; the same static binaries go
# into Lambda zips (bootstrap), ECS images (several bases), Lambda container images and the EC2 AMIs.
# Build modes and their Go-tab claims are listed next to each binary below; cases/go.py references them by name.
source "$(dirname "$0")/../env.sh"; source "$E2E_DIR/build/lib.sh"
SRC="$E2E_DIR/clients/go"; CFG="$REPO_ROOT/configs/go"; B="$WORK/build/go"; OUT="$ART/lambda/go"
MOD="$WORK/build/go-modcache"; GC="$WORK/build/go-buildcache"
rm -rf "$B" "$OUT"; mkdir -p "$B/bin" "$OUT" "$MOD" "$GC"

# One container per toolchain builds every variant of that toolchain.
#   b <name> <go-line> [key=value...]   keys: tags=, env=VAR=val (repeatable), godebug=k=v, modfile=extras, boring=1
cat > "$B/variants.sh" <<'EOF'
set -eu
b() {
  name=$1 line=$2; shift 2
  tags=lambda.norpc; modfile=""; ld="-s -w -X main.goLine=$line"; envs="CGO_ENABLED=0"
  rm -rf /tmp/b; cp -r /src /tmp/b; cd /tmp/b
  for kv in "$@"; do
    case $kv in
      tags=*) tags="$tags,${kv#tags=}" ;;
      env=*) envs="$envs ${kv#env=}" ;;
      godebug=*) go mod edit -godebug="${kv#godebug=}" ;;
      modfile=extras) modfile=-modfile=go.extras.mod; tags="$tags,extras" ;;
      boring=1) envs="$envs CGO_ENABLED=1 GOEXPERIMENT=boringcrypto"; tags="$tags,netgo,osusergo"
                ld="$ld -linkmode external -extldflags -static" ;;
    esac
  done
  go mod edit $modfile -go=$line
  if env $envs go build $modfile -trimpath -tags "$tags" -ldflags "$ld" -o /out/$name . 2>/tmp/err; then
    echo "built $name"
  else
    echo "BUILD-FAILED $name: $(tr '\n' ' ' </tmp/err | cut -c1-300)"; echo "$name $(tr '\n' ' ' </tmp/err)" >> /out/BUILD-FAILED
  fi
}
EOF
gobuild() { # gobuild <toolchain> <<< "b ... lines"
  docker run --rm -i "${LBL[@]}" -v "$SRC":/src:ro -v "$B/bin":/out -v "$B/variants.sh":/variants.sh:ro \
    -v "$MOD":/go/pkg/mod -v "$GC":/root/.cache/go-build -e GOTOOLCHAIN=local -e GOOS=linux -e GOARCH=arm64 \
    -e GOFLAGS=-mod=mod golang:$1 sh -c '. /variants.sh; . /dev/stdin'
}
# Baselines: toolchain = go line (Go tab "Versions and native support")
gobuild 1.23 <<'EOF'
b probe-1.23 1.23
EOF
gobuild 1.24 <<'EOF'
b probe-1.24 1.24
b probe-1.24-go1.23 1.23
b probe-1.24-go1.23-godebug 1.23 godebug=tlsmlkem=1
b probe-1.24-go1.23-godebug-secp 1.23 godebug=tlsmlkem=1 godebug=tlssecpmlkem=1
b probe-1.24-fips 1.24 env=GOFIPS140=latest
EOF
gobuild 1.25 <<'EOF'
b probe-1.25 1.25
b probe-1.25-go1.23 1.23
b probe-1.25-boring-fipsonly 1.25 boring=1 tags=fipsonly
EOF
gobuild 1.26 <<'EOF'
b probe-1.26 1.26
b probe-1.26-go1.25 1.25
b probe-1.26-go1.23 1.23
b probe-1.26-go1.23-godebug 1.23 godebug=tlsmlkem=1 godebug=tlssecpmlkem=1
b probe-1.26-fips-v1.26.0 1.26 env=GOFIPS140=v1.26.0
b probe-1.26-fips-v1.0.0 1.26 env=GOFIPS140=v1.0.0
b probe-1.26-boring 1.26 boring=1
b probe-1.26-boring-fipsonly 1.26 boring=1 tags=fipsonly
b probe-1.26-extras 1.26 modfile=extras
EOF
gobuild 1.27 <<'EOF'
b probe-1.27 1.27
b probe-1.27-go1.23 1.23
b probe-1.27-go1.23-directive 1.23 tags=godebugdirective
b probe-1.27-fips 1.27 env=GOFIPS140=latest
b probe-1.27-boring-fipsonly 1.27 boring=1 tags=fipsonly
b probe-1.27-extras 1.27 modfile=extras
EOF
[ -f "$B/bin/BUILD-FAILED" ] && { echo "build failures:"; cat "$B/bin/BUILD-FAILED"; mv "$B/bin/BUILD-FAILED" "$B/build-failed.txt"; }
chmod 755 "$B"/bin/probe-*

# Posture: the tab's go-pq-posture.sh and `go version -m` over every binary (recorded for the report, not graded)
docker run --rm "${LBL[@]}" -v "$B/bin":/bin-go:ro -v "$CFG/go-pq-posture.sh":/posture.sh:ro golang:1.27 \
  sh -c 'sh /posture.sh /bin-go; echo "--- go version -m (DefaultGODEBUG / GOFIPS140 / GOEXPERIMENT)"; for f in /bin-go/probe-*; do printf "%s: " ${f##*/}; go version -m $f | grep -E "^\s+build\s+(DefaultGODEBUG|GOFIPS140|GOEXPERIMENT)=" | tr -s "\t " " " | tr "\n" ";"; echo; done' \
  > "$B/posture.txt" 2>&1 || true
echo "posture: $B/posture.txt"; head -40 "$B/posture.txt"

# Lambda zips: bootstrap at the zip root + test certs (custom-CA case) -> lambda/go/<binary>.zip
for f in "$B"/bin/probe-*; do
  n=$(basename "$f"); d="$B/zip-$n"; rm -rf "$d"; mkdir -p "$d/certs"
  cp "$f" "$d/bootstrap"; cp "$WORK/certs/"{ca.crt,client.crt,client.key,client.p12} "$d/certs/"
  zipdir "$d" "$OUT/$n.zip"; rm -rf "$d"
done
echo "lambda zips: $(ls "$OUT" | wc -l | tr -d ' ')"

# ECS images: the SAME binaries on different bases (the tab: OS, crypto policy and base image play no part)
EC="$B/ecs"; mkdir -p "$EC/bin/certs"; cp "$B"/bin/probe-* "$EC/bin/"; cp "$WORK/certs/"{ca.crt,client.crt,client.key,client.p12} "$EC/bin/certs/"
printf 'FROM %s\nCOPY bin/ /app/bin/\n' "$AL2023" > "$EC/Dockerfile.al2023"
printf 'FROM %s\nRUN dnf -y -q install crypto-policies-scripts && update-crypto-policies --set DEFAULT:PQ && dnf clean all\nCOPY bin/ /app/bin/\n' "$AL2023" > "$EC/Dockerfile.al2023-policy"
printf 'FROM %s\nCOPY bin/ /app/bin/\n' "$AL2" > "$EC/Dockerfile.al2"
printf 'FROM scratch\nCOPY bin/ /app/bin/\n' > "$EC/Dockerfile.scratch"
printf 'FROM gcr.io/distroless/static-debian12:nonroot\nCOPY bin/ /app/bin/\nUSER nonroot:nonroot\n' > "$EC/Dockerfile.distroless"
printf 'FROM golang:1.27\nCOPY bin/ /app/bin/\n' > "$EC/Dockerfile.golang"
for base in al2023 al2023-policy al2 scratch distroless golang; do ecr_build pqc-go "$base" "$EC" "$EC/Dockerfile.$base"; done

# The document's own Dockerfiles, applied to the probe source (builder stage compiles; FROM lines as published):
#   configs/go/Dockerfile       golang:1.26 -> distroless/static-debian12:nonroot (ECS / Fargate / EKS)
#   configs/go/Dockerfile.fips  golang:1.26 + GOFIPS140=v1.26.0 -> distroless
#   configs/go/Dockerfile.lambda golang:1.26 -> public.ecr.aws/lambda/provided:al2023, ENTRYPOINT ./main
DC="$B/docfiles"; mkdir -p "$DC/src"; cp "$SRC"/*.go "$SRC"/go.mod "$SRC"/go.sum "$DC/src/"
cp -r "$WORK/certs" "$DC/certs"; rm -f "$DC/certs/"*.key.bak
(cd "$DC/src" && sed -i.bak 's/^go 1\.23$/go 1.26/' go.mod && rm -f go.mod.bak)
docfile() { # docfile <published dockerfile> -> same file with only the source paths adapted (+ test certs)
  perl -pe 's#COPY go.mod go.sum \./#COPY src/go.mod src/go.sum ./#; s#^COPY \. \.#COPY src/ .#;
    s#/out/(server|main)#/out/probe#g; s# \./cmd/[a-z]+# .#; s#^EXPOSE.*\n##;
    s#^(COPY --from=build /out/probe /server)$#$1\nCOPY certs/ca.crt certs/client.crt certs/client.key /certs/#;
    s#^(COPY --from=build /out/probe \./main)$#$1\nCOPY certs/ca.crt certs/client.crt certs/client.key ./certs/#' "$1"
}
docfile "$CFG/Dockerfile" > "$DC/Dockerfile.ecs"
docfile "$CFG/Dockerfile.fips" > "$DC/Dockerfile.fips"
docfile "$CFG/Dockerfile.lambda" > "$DC/Dockerfile.lambda"
sed 's#^FROM golang:1.26 AS build#FROM golang:1.23 AS build#' "$DC/Dockerfile.lambda" > "$DC/Dockerfile.lambda-go123"
for f in ecs fips lambda lambda-go123; do echo "--- $f"; cat "$DC/Dockerfile.$f"; done > "$B/docfiles.txt"
ecr_build pqc-go doc-dockerfile "$DC" "$DC/Dockerfile.ecs"
ecr_build pqc-go doc-dockerfile-fips "$DC" "$DC/Dockerfile.fips"
ecr_build pqc-go-lambda go126 "$DC" "$DC/Dockerfile.lambda"
(cd "$DC/src" && sed -i.bak 's/^go 1\.26$/go 1.23/' go.mod && rm -f go.mod.bak)
ecr_build pqc-go-lambda go123 "$DC" "$DC/Dockerfile.lambda-go123"

# EC2: prebuilt binaries -> /opt/pqc/go/bin (AMI), plus the probe source + vendored modules so setup.d/go.sh can
# build one probe with the distro golang package (dnf/yum golang 1.26.10) offline.
E="$ART/ec2/go"; rm -rf "$E"; mkdir -p "$E/bin" "$E/src"; cp "$B"/bin/probe-* "$E/bin/"
cp "$SRC"/*.go "$SRC"/go.mod "$SRC"/go.sum "$E/src/"; rm -f "$E/src/awssdk.go" "$E/src/p12.go"
docker run --rm "${LBL[@]}" -v "$E/src":/w -w /w -v "$MOD":/go/pkg/mod -e GOTOOLCHAIN=local -e GOFLAGS=-mod=mod golang:1.26 \
  sh -c 'go mod edit -go=1.26 && go mod vendor'
cp "$CFG/go-pq-posture.sh" "$E/"
echo "go artifacts done ($(ls "$B/bin" | wc -l | tr -d ' ') binaries)"
