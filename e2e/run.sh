#!/bin/bash
# PQC end-to-end suite on an isolated LocalStack (pqc-e2e-localstack, 127.0.0.1:4600, network pqc-e2e).
#   ./run.sh                      build everything and run all cases
#   ./run.sh --lang python        only Python (build + run)
#   ./run.sh --lang server        load balancer target-leg cases (after the five languages are built)
#   ./run.sh --skip-build --compute lambda --id 'py-lambda-py312*'
#   ./run.sh down                 stop this suite's containers (never volumes, never other LocalStacks)
set -euo pipefail
source "$(dirname "$0")/env.sh"; cd "$E2E_DIR"
LANGS="python node java dotnet go server"   # server = load balancer target cases (needs the five language images)
BUILD=1; ARGS=()
if [ "${1:-}" = down ]; then
  docker run --rm --network pqc-e2e -v "$E2E_DIR":/e2e pqc-e2e/runner:local cleanup || true
  docker compose stop; exit 0
fi
while [ $# -gt 0 ]; do
  case $1 in
    --skip-build) BUILD=0 ;;
    --lang) LANGS=${2//,/ }; ARGS+=(--lang "$2"); shift ;;
    *) ARGS+=("$1") ;;
  esac; shift
done
mkdir -p .work/certs && bash certs/gen.sh >/dev/null
docker compose up -d --build --wait >/dev/null && echo "stack up: $(curl -s localhost:$PQC_LS_PORT/_localstack/info | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["edition"],d["version"],"license",d["is_license_activated"])')"
if [ $BUILD = 1 ]; then
  bash build/common.sh
  for l in $LANGS; do [ -f "build/$l.sh" ] && bash "build/$l.sh"; done
  bash build/layers.sh
  bash build/ami.sh
fi
for l in $LANGS; do [ -f "cases/$l.py" ] && (cd cases && python3 "$l.py" >/dev/null); done
rc=0
docker run --rm --network pqc-e2e -v "$E2E_DIR":/e2e -e E2E_ROOT=/e2e -e PQC_JOBS="${PQC_JOBS:-6}" \
  pqc-e2e/runner:local run ${ARGS[@]+"${ARGS[@]}"} || rc=$?
echo; cat results/latest/summary.md | head -5
exit $rc
