#!/bin/bash
# Node.js artifacts: Lambda zips, Lambda container images, ECS images, EC2 AMI files.
# Fix files come from the document's configs/nodejs/ so the published files are what gets tested.
# No layer parts: the pq-tls layer (build/common.sh) already carries the wrapper and /opt/pq-tls/openssl-pq-node.cnf.
source "$(dirname "$0")/../env.sh"; source "$E2E_DIR/build/lib.sh"
SRC="$E2E_DIR/clients/node"; CFG="$REPO_ROOT/configs/nodejs"; B="$WORK/build/node"; OUT="$ART/lambda/node"
rm -rf "$B" "$OUT"; mkdir -p "$B/certs" "$OUT"
NODE_LIB=public.ecr.aws/docker/library/node

# Test certs + a legacy PFX (RC2-40 / 3DES, as old Windows/Java tools export: tab case C / Pitfalls)
cp "$WORK/certs/"{ca.crt,client.crt,client.key,client.p12,ca-both.crt,client-mldsa.crt,client-mldsa.key} "$B/certs/"
docker run --rm "${LBL[@]}" -v "$WORK/certs":/c:ro -v "$B/certs":/o public.ecr.aws/docker/library/debian:trixie-slim sh -euc \
  'apt-get -qq update >/dev/null && apt-get -qq install -y openssl >/dev/null 2>&1
   openssl pkcs12 -export -legacy -in /c/client.crt -inkey /c/client.key -certfile /c/ca.crt -name pqc-client \
     -out /o/client-legacy.p12 -passout pass:changeit
   openssl pkcs12 -in /o/client-legacy.p12 -info -noout -legacy -passin pass:changeit 2>&1 | grep -q RC2 && chmod 644 /o/client-legacy.p12'

pkg() { # pkg <name> [extra shell steps...]: probe + certs (+ extras) -> lambda/node/<name>.zip
  local d="$B/pkg-$1"; rm -rf "$d"; mkdir -p "$d"
  cp "$SRC/index.js" "$d/"; cp -r "$B/certs" "$d/certs"
  shift; for x in "$@"; do eval "$x"; done
  zipdir "$d" "$OUT/$(basename "$d" | sed 's/^pkg-//').zip"
}
pkg probe
# Tab "Lambda zip (nodejs22.x, nodejs24.x)": pq-tls/openssl-pq-node.cnf in the package, OPENSSL_CONF or NODE_OPTIONS
pkg probe-bundled 'mkdir -p "$d/pq-tls"; cp "$CFG/pq-tls/openssl-pq-node.cnf" "$d/pq-tls/"'
# Existing configuration the function already has:
#  conf/app-openssl.cnf   the function's own classical OPENSSL_CONF (nodejs_conf section): wrapper must leave it alone
#  preload/*.js           app code run through NODE_OPTIONS=--require (the probe itself sets no groups):
#                         ecdh-pq.js = tab "In code" method, ecdh-classical.js = case F tls.DEFAULT_ECDH_CURVE pitfall
pkg probe-extra 'mkdir -p "$d/pq-tls" "$d/conf" "$d/preload"; cp "$CFG/pq-tls/openssl-pq-node.cnf" "$d/pq-tls/"
  printf "%s\n" "nodejs_conf = app_init" "[app_init]" "ssl_conf = ssl_sect" "[ssl_sect]" "system_default = app_tls" "[app_tls]" "Groups = X25519:secp256r1" > "$d/conf/app-openssl.cnf"
  echo "require(\"node:tls\").DEFAULT_ECDH_CURVE = \"X25519MLKEM768:X25519:P-256:P-384\";" > "$d/preload/ecdh-pq.js"
  echo "require(\"node:tls\").DEFAULT_ECDH_CURVE = \"X25519:P-256\";" > "$d/preload/ecdh-classical.js"
  printf "%s\n" "#!/bin/bash" "echo \"pq-tls: chained app wrapper ran (OPENSSL_CONF=\$OPENSSL_CONF)\"" "exec \"\$@\"" > "$d/app-wrapper"; chmod 755 "$d/app-wrapper"'
echo "lambda zips: $(ls "$OUT" | tr '\n' ' ')"

# Lambda container images (PackageType Image) on AWS's base image; fixed = the two lines from configs/nodejs/Dockerfile.lambda
LC="$B/lambda-image"; mkdir -p "$LC/pq-tls"; cp "$SRC/index.js" "$LC/"; cp -r "$B/certs" "$LC/certs"
cp "$CFG/pq-tls/openssl-pq-node.cnf" "$LC/pq-tls/"
for v in 22 24; do
  cat > "$LC/Dockerfile.base" <<EOF
FROM public.ecr.aws/lambda/nodejs:$v
COPY index.js \${LAMBDA_TASK_ROOT}/
COPY certs/ \${LAMBDA_TASK_ROOT}/certs/
CMD ["index.handler"]
EOF
  { sed '$d' "$LC/Dockerfile.base"; grep -E '^(COPY pq-tls|ENV OPENSSL_CONF)' "$CFG/Dockerfile.lambda"; echo 'CMD ["index.handler"]'; } > "$LC/Dockerfile.fixed"
  [ "$(grep -c -E '^(COPY pq-tls|ENV OPENSSL_CONF)' "$LC/Dockerfile.fixed")" = 2 ] || { echo "Dockerfile.lambda lines not found"; exit 1; }
  ecr_build pqc-node-lambda "nodejs$v-baseline" "$LC" "$LC/Dockerfile.base"
  ecr_build pqc-node-lambda "nodejs$v-fixed" "$LC" "$LC/Dockerfile.fixed"
done

# ECS images
EC="$B/ecs"; mkdir -p "$EC/etc-app"; cp "$SRC/index.js" "$EC/"; cp -r "$B/certs" "$EC/certs"
cp "$CFG/etc/app/openssl-pq-node-system.cnf" "$EC/etc-app/"
cat > "$EC/Dockerfile.al2023" <<EOF
# AL2023 (same release as the AMI) + dnf nodejs20/22/24 (node-20, node-22, node-24 on system OpenSSL).
# System config file present, NOT enabled: the task definition's OPENSSL_CONF decides.
FROM $AL2023
RUN dnf -y -q install nodejs20 nodejs22 nodejs24 && dnf clean all
COPY index.js /app/index.js
COPY certs/ /app/certs/
COPY etc-app/openssl-pq-node-system.cnf /etc/app/openssl-pq-node-system.cnf
EOF
# configs/nodejs/Dockerfile.al2023: its RUN line (nodejs22 + crypto-policies-scripts + DEFAULT:PQ), plus nodejs20/24
RUNLINE=$(sed -n '/^RUN dnf/,/useradd/p' "$CFG/Dockerfile.al2023" | sed 's/nodejs22/nodejs20 nodejs22 nodejs24/')
grep -q 'update-crypto-policies --set DEFAULT:PQ' <<<"$RUNLINE" || { echo "Dockerfile.al2023 RUN line not found"; exit 1; }
cat > "$EC/Dockerfile.al2023-policy" <<EOF
FROM $AL2023
$RUNLINE
COPY index.js /app/index.js
COPY certs/ /app/certs/
EOF
ecr_build pqc-node al2023 "$EC" "$EC/Dockerfile.al2023"
ecr_build pqc-node al2023-policy "$EC" "$EC/Dockerfile.al2023-policy"
# Official images (bundled OpenSSL), as the tab's Fargate section and version table describe
for t in 20-slim 20-alpine 22-slim 22-alpine 24-slim 24-alpine 26-slim 22.19-alpine 22.20-alpine 24.4-alpine 24.5-alpine; do
  printf 'FROM %s:%s\nCOPY index.js /app/index.js\nCOPY certs/ /app/certs/\n' "$NODE_LIB" "$t" > "$EC/Dockerfile.lib"
  ecr_build pqc-node "lib-$t" "$EC" "$EC/Dockerfile.lib"
done
# Distro builds on system OpenSSL 3.5 (version table rows Debian 13 apt, Alpine 3.22 apk)
printf 'FROM public.ecr.aws/docker/library/debian:trixie-slim\nRUN apt-get -qq update && apt-get -qq install -y --no-install-recommends nodejs && rm -rf /var/lib/apt/lists/*\nCOPY index.js /app/index.js\nCOPY certs/ /app/certs/\n' > "$EC/Dockerfile.debian"
printf 'FROM public.ecr.aws/docker/library/alpine:3.22\nRUN apk add --no-cache nodejs\nCOPY index.js /app/index.js\nCOPY certs/ /app/certs/\n' > "$EC/Dockerfile.alpine"
ecr_build pqc-node distro-debian13 "$EC" "$EC/Dockerfile.debian"
ecr_build pqc-node distro-alpine322 "$EC" "$EC/Dockerfile.alpine"

# EC2: files for the golden AMI (/opt/pqc/node/...). dnf nodejs20/22/24 come from packages.d/node.txt.
# official-<major>/bin/node = the official linux-arm64 build (copied out of the official image: same binary as the
# nodejs.org tarball, glibc >= 2.28) for the tab's "official tarball on EC2" rows.
E="$ART/ec2/node"; rm -rf "$E"; mkdir -p "$E/etc-app"; cp "$SRC/index.js" "$E/"; cp "$CFG/etc/app/openssl-pq-node-system.cnf" "$E/etc-app/"
for m in 22 24; do
  mkdir -p "$E/official-$m/bin"; cid=$(docker create "$NODE_LIB:$m-slim")
  docker cp "$cid:/usr/local/bin/node" "$E/official-$m/bin/node" >/dev/null; docker rm "$cid" >/dev/null
done
echo "node artifacts done"
