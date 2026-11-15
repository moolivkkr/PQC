#!/bin/sh
# ci/pq-tls-lint.sh - fail the build on Python TLS settings that block hybrid PQ key exchange.
# Usage: sh ci/pq-tls-lint.sh [dir]   (default .)   Exit 1 = blocking setting found, 0 = clean.
# Allow a reviewed line by adding the comment "pq-tls: allow" on that line.
DIR=${1:-.}
PAT='set_ecdh_curve\(|maximum_version *= *ssl\.TLSVersion\.TLSv1(_[012])?\b|ssl_maximum_version *= *ssl\.TLSVersion\.TLSv1|OP_NO_TLSv1_3|PROTOCOL_TLSv1(_[12])?\b|ssl_version *= *ssl\.PROTOCOL_TLSv1|set_groups\(["'"'"'][^"'"'"']*["'"'"']\)|ssl\.curves\.list|OPENSSL_CONF *= */dev/null'
HITS=$(grep -rnE --include='*.py' --include='*.cfg' --include='*.ini' --include='*.toml' --include='*.yaml' --include='*.yml' \
        --include='*.json' --include='Dockerfile*' --include='*.env' "$PAT" "$DIR" 2>/dev/null | grep -v 'pq-tls: allow')
# set_groups / ssl.curves.list are only a problem when the list has no ML-KEM group
HITS=$(printf '%s\n' "$HITS" | grep -vE '(set_groups|ssl\.curves\.list).*MLKEM' | grep -v '^$')
if [ -n "$HITS" ]; then
  echo "pq-tls-lint: settings that can block X25519MLKEM768 (see the Python tab, case F):"
  printf '%s\n' "$HITS"
  exit 1
fi
echo "pq-tls-lint: clean"
