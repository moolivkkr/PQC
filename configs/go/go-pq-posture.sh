#!/bin/sh
# Usage: go-pq-posture.sh <dir-with-go-binaries>   (needs a Go toolchain on PATH)
# Fails if any Go binary is classical by build. Runtime GODEBUG must be checked separately.
rc=0
for f in $(find "$1" -type f -perm -u+x); do
  info=$(go version -m "$f" 2>/dev/null) || continue      # not a Go binary
  ver=$(echo "$info" | head -1 | sed -E 's/.*go1\.([0-9]+).*/\1/')
  dbg=$(echo "$info" | grep -o 'DefaultGODEBUG=[^ ]*')
  exp=$(echo "$info" | grep -o 'GOEXPERIMENT=[^ ]*')
  if [ "$ver" -lt 24 ]; then echo "FAIL $f go1.$ver: no ML-KEM"; rc=1
  elif echo "$dbg" | grep -q 'tlsmlkem=0'; then echo "FAIL $f go1.$ver: tlsmlkem=0 (go.mod go line < 1.24)"; rc=1
  elif echo "$exp" | grep -q boringcrypto; then echo "WARN $f boringcrypto: check for crypto/tls/fipsonly"
  elif echo "$dbg" | grep -q 'fips140=on' && [ "$ver" -lt 25 ]; then echo "FAIL $f go1.$ver FIPS: no PQ before 1.25"; rc=1
  else echo "OK   $f go1.$ver $dbg"; fi
done
exit $rc
