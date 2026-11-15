#!/bin/sh
# Host driver: runs run-v2.sh in debian:trixie-slim by digest, one labelled container.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W=/private/tmp/claude-501/-Users-kishoremooli-development-cybersecurity/21fa377a-bc06-46f9-9e49-4588545ba6c2/scratchpad/deep/go/v2
img=$(docker image inspect --format '{{index .RepoDigests 0}}' debian:trixie-slim); echo "image $img"
docker run --rm --label run=pqc-lang2-go --name go2-test -v $W:/src:ro -v $W/bin:/b:ro "$img" sh /src/run-v2.sh
