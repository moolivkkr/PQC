#!/bin/sh
# go-pq-lint.sh [repo-dir]: source and IaC check for Go settings that block hybrid PQ key exchange.
# Exit 1 on any FAIL. Needs only sh, find and grep (run before the build; go-pq-posture.sh checks the binary).
dir=${1:-.}
out=$(mktemp); trap 'rm -f "$out"' EXIT
fail() { echo "FAIL $*" >>"$out"; }

# 1. go line of every main module and go.work: < 1.24 means DefaultGODEBUG tlsmlkem=0
for m in $(find "$dir" \( -name go.mod -o -name go.work \) -not -path '*/vendor/*' -not -path '*/testdata/*'); do
  v=$(sed -n 's/^go \(1\.[0-9]*\).*/\1/p' "$m" | head -1); minor=${v#1.}
  if [ -n "$minor" ] && [ "$minor" -lt 24 ] && ! grep -qE '(^|[[:space:]])tlsmlkem=1' "$m"; then
    fail "$m: 'go $v' (< 1.24) and no 'godebug tlsmlkem=1'"
  fi
  grep -nE 'tlsmlkem=0|tlssecpmlkem=0' "$m" | while read -r l; do fail "$m:$l"; done
done

# 2. Go source (tests excluded)
src=$(find "$dir" -name '*.go' -not -name '*_test.go' -not -path '*/vendor/*' -not -path '*/testdata/*')
for f in $src; do
  if grep -q 'CurvePreferences' "$f" && ! grep -qE 'MLKEM' "$f"; then
    grep -n 'CurvePreferences' "$f" | while read -r l; do fail "$f:$l  (CurvePreferences with no ML-KEM hybrid in this file)"; done
  fi
  grep -nE 'MaxVersion[[:space:]]*[:=][[:space:]]*tls\.VersionTLS1[0-2]' "$f" | while read -r l; do fail "$f:$l  (TLS 1.2 cap: no PQ)"; done
  grep -nE '^//go:debug.*(tlsmlkem=0|tlssecpmlkem=0|tlskyber)' "$f" | while read -r l; do fail "$f:$l"; done
  grep -nE 'crypto/tls/fipsonly' "$f" | while read -r l; do fail "$f:$l  (boringcrypto fipsonly: NIST curves only, no PQ)"; done
done

# 3. Deployment config: GODEBUG overrides and the retired go1.x Lambda runtime
for f in $(find "$dir" \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' -o -name '*.tf' -o -name 'Dockerfile*' -o -name '*.service' -o -name '*.env' \) -not -path '*/node_modules/*' -not -path '*/vendor/*'); do
  grep -nE 'tlsmlkem=0|tlssecpmlkem=0' "$f" | while read -r l; do fail "$f:$l  (GODEBUG turns PQ off)"; done
  grep -nE '(Runtime:[[:space:]]*go1\.x|runtime[[:space:]]*=[[:space:]]*"go1\.x")' "$f" | while read -r l; do fail "$f:$l  (go1.x runtime retired: use provided.al2023)"; done
done

if [ -s "$out" ]; then cat "$out"; echo "go-pq-lint: $(wc -l <"$out" | tr -d ' ') finding(s)"; exit 1; fi
echo "go-pq-lint: OK ($dir)"
