#!/bin/bash
# CI guardrail: fail the build when Node.js code, config or IaC carries a setting that blocks hybrid PQ key exchange.
# Usage: ci/check-node-tls.sh [repo-dir]     (exit 1 on findings; add "pq-tls-ok" on a line to allow it after review)
set -uo pipefail
root="${1:-.}"; rc=0
src=(--include='*.js' --include='*.mjs' --include='*.cjs' --include='*.ts' --include='*.mts' --include='*.cts')
cfg=(--include='*.json' --include='*.yaml' --include='*.yml' --include='*.tf' --include='Dockerfile*' --include='*.env' --include='*.service' --include='*.sh')
skip=(--exclude-dir=.git --exclude-dir=dist --exclude-dir=coverage)
hit() { # label, grep args...
  local label=$1; shift
  local out; out=$(grep -rnE "$@" "$root" 2>/dev/null | grep -v 'pq-tls-ok')
  [ -n "$out" ] && { echo "::error::$label"; echo "$out" | head -50; rc=1; }
}
# 1. Pinned group lists without the hybrid group (client or server, ecdhCurve or the module default)
#    (a list that starts with a classical group; 'auto' and lists starting X25519MLKEM768 pass)
hit "ecdhCurve / DEFAULT_ECDH_CURVE starts with a classical group" "${src[@]}" "${skip[@]}" --exclude-dir=node_modules \
    -e "(ecdhCurve|DEFAULT_ECDH_CURVE|TLS_ECDH_CURVE)[\"']?[[:space:]]*[:=][[:space:]]*['\"\`](X25519[:'\"\`]|x25519|X448|P-|prime|secp|brainpool|ffdhe)"
# 2. TLS 1.2 caps (no TLS 1.3 = no ML-KEM)
hit "TLS 1.2 cap (maxVersion / secureProtocol / DEFAULT_MAX_VERSION / --tls-max-v1.2)" "${src[@]}" "${cfg[@]}" "${skip[@]}" --exclude-dir=node_modules \
    -e "maxVersion[[:space:]]*:[[:space:]]*['\"]TLSv1(\.[012])?['\"]" -e "DEFAULT_MAX_VERSION[[:space:]]*=[[:space:]]*['\"]TLSv1(\.[012])?['\"]" \
    -e "secureProtocol[[:space:]]*:[[:space:]]*['\"]TLSv1(_[12])?_(client_|server_)?method['\"]" -e "tls-max-v1\.[0-2]"
# 3. Lambda: OPENSSL_CONF pointing at AWS's classical file, or Node runtimes with no fix
hit "Lambda nodejs18.x/20.x runtime (OpenSSL 3.0: no PQ)" "${cfg[@]}" "${skip[@]}" --exclude-dir=node_modules -e "nodejs(18|20)\.x"
hit "OPENSSL_CONF set to the Lambda runtime's classical file" "${cfg[@]}" "${skip[@]}" -e "OPENSSL_CONF.{0,20}/var/runtime/openssl_conf"
# 4. Base images below the PQ floor (22.20 / 24.5; 20 and older never)
hit "node base image below 22.20 / 24.5" --include='Dockerfile*' "${skip[@]}" \
    -e "FROM[[:space:]]+(docker\.io/)?(library/)?node:(1[0-9]|20|21|23)([.-]|$|@|[[:space:]])" \
    -e "FROM[[:space:]]+(docker\.io/)?(library/)?node:22\.(1?[0-9])([.-]|@|[[:space:]]|$)" \
    -e "FROM[[:space:]]+(docker\.io/)?(library/)?node:24\.[0-4]([.-]|@|[[:space:]]|$)" \
    -e "FROM[[:space:]]+public\.ecr\.aws/lambda/nodejs:(18|20)"
# 5. Dependencies that set these options too (report only; review, don't fail)
dep=$(grep -rlE "ecdhCurve[[:space:]]*:|DEFAULT_ECDH_CURVE[[:space:]]*=|maxVersion[[:space:]]*:[[:space:]]*['\"]TLSv1\.2" "$root/node_modules" \
      --include='*.js' --include='*.cjs' --include='*.mjs' 2>/dev/null | grep -vE '/(test|tests|docs?)/|@types/' | head -20)
[ -n "$dep" ] && { echo "::warning::node_modules files that set ecdhCurve/maxVersion (review):"; echo "$dep"; }
[ $rc = 0 ] && echo "check-node-tls: no PQ-blocking settings found"
exit $rc
