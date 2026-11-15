#!/bin/sh
# check-go-pq.sh <go-binary>...  - fail if a Go binary will not offer X25519MLKEM768 by default.
# Needs a Go toolchain (any version >= the binary's) on PATH for `go version -m`.
# Rules (Go crypto/tls): toolchain >= 1.24 AND the module's go directive >= 1.24, otherwise the
# default GODEBUG carries tlsmlkem=0. An explicit tls.Config.CurvePreferences is not visible here:
# catch it with the source grep at the end of this script's README section.
rc=0
for bin in "$@"; do
  info=$(go version -m "$bin" 2>/dev/null) || { echo "SKIP $bin: not a Go binary"; continue; }
  tool=$(printf '%s\n' "$info" | head -1 | sed -E 's/.*: go([0-9]+)\.([0-9]+).*/\1 \2/')
  set -- $tool
  major=$1; minor=$2
  godebug=$(printf '%s\n' "$info" | awk '$1=="build" && $2 ~ /^DefaultGODEBUG=/ {sub(/^DefaultGODEBUG=/,"",$2); print $2}')
  if [ "$major" -lt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -lt 24 ]; }; then
    echo "FAIL $bin: built with go$major.$minor (< 1.24, no ML-KEM in crypto/tls)"; rc=1
  elif printf '%s' "$godebug" | grep -q 'tlsmlkem=0'; then
    echo "FAIL $bin: DefaultGODEBUG=$godebug (go.mod go directive < 1.24). Raise go to >= 1.24 or add //go:debug tlsmlkem=1"; rc=1
  else
    echo "PASS $bin: go$major.$minor DefaultGODEBUG=${godebug:-<none>}"
  fi
done
exit $rc
