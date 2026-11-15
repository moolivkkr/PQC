#!/bin/bash
# Zip every layer source tree. pq-tls-combined = pq-tls + pq-egress in ONE layer (one of the 5 layer slots).
source "$(dirname "$0")/../env.sh"; source "$E2E_DIR/build/lib.sh"
C="$ART/layer-src/pq-tls-combined"; rm -rf "$C"; mkdir -p "$C"
cp -a "$ART/layer-src/pq-tls/." "$C/"; cp -a "$ART/layer-src/pq-egress/." "$C/"
for d in "$ART"/layer-src/*/; do n=$(basename "$d"); zipdir "$d" "$ART/layers/$n.zip"; echo "layer $n: $(du -h "$ART/layers/$n.zip" | cut -f1)"; done
