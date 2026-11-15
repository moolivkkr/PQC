#!/bin/bash
# After a Docker or LocalStack restart: LocalStack keeps no state, so its ECR is empty. Re-push every image this
# suite already built (tagged with the LocalStack registry) instead of rebuilding everything.
source "$(dirname "$0")/../env.sh"; source "$E2E_DIR/build/lib.sh"
REG=000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:${PQC_LS_PORT}
imgs=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep "^$REG/" | grep -v '<none>' || true)
[ -z "$imgs" ] && { echo "no suite images found; run e2e/run.sh to build"; exit 0; }
for r in $(echo "$imgs" | sed "s#^$REG/##; s#:.*##" | sort -u); do ecr_repo "$r" >/dev/null; done
n=0; out=$(mktemp)
for i in $imgs; do ( docker push -q "$i" >/dev/null 2>&1 && echo ok || echo "FAIL $i" ) >>"$out" & n=$((n+1)); [ $((n % 6)) = 0 ] && wait; done; wait
echo "re-pushed: $(grep -c '^ok' "$out") ok, $(grep -c '^FAIL' "$out") failed"; grep '^FAIL' "$out" || true; rm -f "$out"
