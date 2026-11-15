#!/bin/bash
# Shared artifacts: test PKI, runner image, pq-egress extension, Lambda layer sources.
source "$(dirname "$0")/../env.sh"; source "$E2E_DIR/build/lib.sh"
bash "$E2E_DIR/certs/gen.sh" >/dev/null
docker build -q "${LBL[@]}" -t "$RUNNER" "$E2E_DIR/runner" >/dev/null && echo "runner image"

# pq-egress extension (static linux/arm64)
docker run --rm "${LBL[@]}" -v "$E2E_DIR/lambda/extension/pq-egress":/src -v "$ART":/out -w /src \
  -e CGO_ENABLED=0 -e GOOS=linux -e GOARCH=arm64 "$GO_IMG" go build -trimpath -ldflags=-s -o /out/pq-egress .
echo "pq-egress built"

# layer: pq-egress (extension only)
L="$ART/layer-src/pq-egress"; rm -rf "$L"; mkdir -p "$L/extensions"
cp "$ART/pq-egress" "$L/extensions/pq-egress"; chmod 755 "$L/extensions/pq-egress"

# layer: pq-tls (wrapper kit v2 + config files from the document's configs/)
L="$ART/layer-src/pq-tls/pq-tls"; rm -rf "$ART/layer-src/pq-tls"; mkdir -p "$L"
cp "$REPO_ROOT/kit/java-v2/pq-tls-layer/wrapper" "$REPO_ROOT/kit/java-v2/pq-tls-layer/pq-tls.security" "$L/"
cp "$REPO_ROOT/configs/python/pq-tls/openssl-pq.cnf" "$L/openssl-pq.cnf"
cp "$REPO_ROOT/configs/nodejs/pq-tls/openssl-pq-node.cnf" "$L/openssl-pq-node.cnf"
cp -r "$REPO_ROOT/configs/python/pq-tls/pyshim" "$L/pyshim"
chmod 755 "$L/wrapper"
echo "layer sources: pq-tls, pq-egress (language builds add their parts, then build/layers.sh zips them)"
