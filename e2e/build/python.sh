#!/bin/bash
# Python artifacts: Lambda zips, Lambda container images, ECS images, EC2 AMI files, layer parts.
# Fix files come from the document's configs/python/ so the published files are what gets tested.
source "$(dirname "$0")/../env.sh"; source "$E2E_DIR/build/lib.sh"
SRC="$E2E_DIR/clients/python"; CFG="$REPO_ROOT/configs/python"; B="$WORK/build/python"; OUT="$ART/lambda/python"
rm -rf "$B"; mkdir -p "$B" "$OUT"
CRYPTO_PINS="cryptography==50.0.2 pyOpenSSL==26.4.0 idna==3.20"   # tab-tested versions + idna (urllib3.contrib.pyopenssl imports it)

# pyOpenSSL + cryptography for Lambda arm64, installed natively INSIDE each runtime image so pip picks the wheel
# that loads on that Python and glibc. (A cross-install with --python-version 3.11 gave an abi3 wheel that fails on
# 3.9/3.10 with "undefined symbol PyType_GetName"; --platform manylinux2014 hid 50.x for 3.9.)
for v in 3.9 3.10 3.11; do
  docker run --rm "${LBL[@]}" -v "$B":/b --entrypoint sh public.ecr.aws/lambda/python:$v -c \
    "pip install -q --disable-pip-version-check --target /b/pywheels-$v $CRYPTO_PINS && rm -rf /b/pywheels-$v/bin" 2>&1 | grep -v -i 'notice\|warning' || true
  ls "$B/pywheels-$v" | grep -q '^cryptography$' || { echo "no cryptography for $v"; exit 1; }
done
# Regression set for the idna pitfall: exactly the Python tab's bridge command (pyopenssl + cryptography only)
docker run --rm "${LBL[@]}" -v "$B":/b --entrypoint sh public.ecr.aws/lambda/python:3.11 -c \
  "pip install -q --disable-pip-version-check --target /b/pywheels-noidna-3.11 cryptography==50.0.2 pyOpenSSL==26.4.0 && rm -rf /b/pywheels-noidna-3.11/bin" 2>&1 | grep -v -i 'notice\|warning' || true
pkg() { # pkg <name> [extra shell steps...]: probe + certs (+ extras) -> lambda/python/<name>.zip
  local d="$B/pkg-$1"; rm -rf "$d"; mkdir -p "$d/certs"
  cp "$SRC/probe.py" "$d/"; cp "$WORK/certs/"{ca.crt,client.crt,client.key} "$d/certs/"
  shift; for x in "$@"; do eval "$x"; done
  zipdir "$d" "$OUT/$(basename "$d" | sed 's/^pkg-//').zip"
}
pkg probe
# Case: python3.12+ bundled config file (Python tab, "Lambda zip, python3.12 to 3.14")
pkg probe-bundled 'mkdir -p "$d/pq-tls"; cp "$CFG/pq-tls/openssl-pq.cnf" "$d/pq-tls/"'
# Case: python3.9-3.11 bridge (Python tab, "Bridge"): shim + pyOpenSSL/cryptography in the package, per version
for v in 3.9 3.10 3.11; do
  pkg "probe-shim-py${v/./}" 'mkdir -p "$d/pq-tls"; cp -r "$CFG/pq-tls/pyshim" "$d/pq-tls/"; cp -r "$B/pywheels-'$v'/." "$d/"'
done
# Case: function already sets its own OPENSSL_CONF (classical file): wrapper must leave it alone
pkg probe-ownconf 'mkdir -p "$d/conf"; printf "%s\n" "openssl_conf = app_init" "[app_init]" "ssl_conf = ssl_sect" "[ssl_sect]" "system_default = app_tls" "[app_tls]" "Groups = X25519:secp256r1" > "$d/conf/app-openssl.cnf"'
# Case: function already uses another exec wrapper (Datadog/OTel style): PQ_TLS_NEXT_WRAPPER chains to it
pkg probe-chain 'printf "%s\n" "#!/bin/bash" "echo \"pq-tls: chained app wrapper ran (OPENSSL_CONF=\$OPENSSL_CONF)\"" "exec \"\$@\"" > "$d/app-wrapper"; chmod 755 "$d/app-wrapper"'
pkg probe-shim-noidna-py311 'mkdir -p "$d/pq-tls"; cp -r "$CFG/pq-tls/pyshim" "$d/pq-tls/"; cp -r "$B/pywheels-noidna-3.11/." "$d/"'
echo "lambda zips: $(ls "$OUT" | tr '\n' ' ')"

# Layer part: pyOpenSSL/cryptography where the shim looks: /opt/python/lib/pythonX.Y/site-packages
for v in 3.9 3.10 3.11; do
  mkdir -p "$ART/layer-src/pq-tls/python/lib/python$v/site-packages"; cp -r "$B/pywheels-$v/." "$ART/layer-src/pq-tls/python/lib/python$v/site-packages/"
done

# Lambda container images (PackageType Image) on AWS's base image
LC="$B/lambda-image"; mkdir -p "$LC/certs" "$LC/pq-tls"; cp "$SRC/probe.py" "$LC/"; cp "$WORK/certs/"{ca.crt,client.crt,client.key} "$LC/certs/"
cp "$CFG/pq-tls/openssl-pq.cnf" "$LC/pq-tls/"
for v in 3.12 3.13; do
  cat > "$LC/Dockerfile.base" <<EOF
FROM public.ecr.aws/lambda/python:$v
COPY probe.py \${LAMBDA_TASK_ROOT}/
COPY certs/ \${LAMBDA_TASK_ROOT}/certs/
CMD ["probe.handler"]
EOF
  # the two lines from configs/python/Dockerfile.lambda
  { cat "$LC/Dockerfile.base" | sed '$d'; grep -E '^(COPY pq-tls|ENV OPENSSL_CONF)' "$CFG/Dockerfile.lambda"; echo 'CMD ["probe.handler"]'; } > "$LC/Dockerfile.fixed"
  ecr_build pqc-python-lambda "py${v/./}-baseline" "$LC" "$LC/Dockerfile.base"
  ecr_build pqc-python-lambda "py${v/./}-fixed" "$LC" "$LC/Dockerfile.fixed"
done

# ECS images
EC="$B/ecs"; mkdir -p "$EC/certs" "$EC/pq-tls"; cp "$SRC/probe.py" "$EC/"; cp "$WORK/certs/"{ca.crt,client.crt,client.key} "$EC/certs/"
cp "$CFG/pq-tls/openssl-pq.cnf" "$EC/pq-tls/"
cat > "$EC/Dockerfile.al2023" <<EOF
# AL2023 (same release as the AMI) + Python 3.11-3.14 from dnf. Config file present, NOT enabled:
# the task definition's OPENSSL_CONF (configs/python/ecs/taskdef.json) decides.
FROM $AL2023
RUN dnf -y -q install python3.11 python3.12 python3.13 python3.14 && dnf clean all
COPY probe.py /app/probe.py
COPY certs/ /app/certs/
COPY pq-tls/openssl-pq.cnf /etc/pq-tls/openssl-pq.cnf
EOF
cat > "$EC/Dockerfile.al2023-policy" <<EOF
# Option A of configs/python/Dockerfile.al2023: image-wide crypto policy
FROM $AL2023
RUN dnf -y -q install python3.12 crypto-policies-scripts && update-crypto-policies --set DEFAULT:PQ && dnf clean all
COPY probe.py /app/probe.py
COPY certs/ /app/certs/
EOF
ecr_build pqc-python al2023 "$EC" "$EC/Dockerfile.al2023"
ecr_build pqc-python al2023-policy "$EC" "$EC/Dockerfile.al2023-policy"
for base in 3.12-slim-trixie 3.13-slim-trixie 3.12-slim-bookworm 3.12-alpine; do
  printf 'FROM public.ecr.aws/docker/library/python:%s\nCOPY probe.py /app/probe.py\nCOPY certs/ /app/certs/\n' "$base" > "$EC/Dockerfile.lib"
  ecr_build pqc-python "lib-$base" "$EC" "$EC/Dockerfile.lib"
done

# EC2: files for the golden AMI (/opt/pqc/python/...)
E="$ART/ec2/python"; rm -rf "$E"; mkdir -p "$E/pq-tls"; cp "$SRC/probe.py" "$E/"; cp "$CFG/pq-tls/openssl-pq.cnf" "$E/pq-tls/"
echo "python artifacts done"
