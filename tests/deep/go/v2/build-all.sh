#!/bin/sh
# Host driver: builds the case binaries in golang images run by digest, one container at a time.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W=/private/tmp/claude-501/-Users-kishoremooli-development-cybersecurity/21fa377a-bc06-46f9-9e49-4588545ba6c2/scratchpad/deep/go/v2
mkdir -p $W/bin $W/gomod
dig() { docker image inspect --format '{{index .RepoDigests 0}}' "$1"; }
run() { # tag name goline [deps]
  img=$(dig golang:$1); echo "== golang:$1 -> $img"
  docker run --rm --label run=pqc-lang2-go --name go2-build-$2 -v $W:/src:ro -v $W/bin:/out -v $W/gomod:/go/pkg/mod \
    "$img" sh /src/build-v2.sh "$2" "$3" "${4:-}"
}
run 1.23 1.23-mod1.23 1.23
run 1.24 1.24-mod1.22 1.22
run 1.24 1.24-mod1.24 1.24
run 1.25 1.25-mod1.25 1.25
run 1.26 1.26-mod1.26 1.26 deps
