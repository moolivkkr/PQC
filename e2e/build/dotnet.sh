#!/bin/bash
# .NET artifacts: Lambda zips (dotnet8, dotnet10, Native AOT on provided.al2023), Lambda container images, ECS images,
# EC2 AMI files. Fix files come from the document's configs/dotnet/ so the published files are what gets tested.
source "$(dirname "$0")/../env.sh"; source "$E2E_DIR/build/lib.sh"
SRC="$E2E_DIR/clients/dotnet"; CFG="$REPO_ROOT/configs/dotnet"; B="$WORK/build/dotnet"; OUT="$ART/lambda/dotnet"
SDK=mcr.microsoft.com/dotnet/sdk:10.0-alpine     # builds portable (framework-dependent) IL for net8.0 and net10.0
MCR=mcr.microsoft.com/dotnet
rm -rf "$B/src" "$B/pub" "$B"/pkg-* "$B/img"; mkdir -p "$B/src" "$B/pub" "$B/nuget" "$OUT"
cp "$SRC"/probe.csproj "$SRC"/Probe.cs "$B/src/"
CERTS=("$WORK/certs/"{ca.crt,client.crt,client.key,client.p12})

# 1. Framework-dependent publish, one per target framework (the Lambda managed runtime and dotnet hosts run these)
docker run --rm "${LBL[@]}" -v "$B/src":/src:ro -v "$B/pub":/out -v "$B/nuget":/root/.nuget/packages $SDK sh -c '
  cp -r /src /b && cd /b && for f in net8.0 net10.0; do
    dotnet publish -nologo -v q -c Release -f $f -p:UseAppHost=false -o /out/$f 2>&1 | grep -v "warning CA1416" || true
    test -f /out/$f/probe.dll || exit 1; rm -f /out/$f/*.pdb; done'
# 2. Native AOT bootstrap (tab: FunctionAot.csproj, "Build AOT on Amazon Linux 2023 so glibc matches")
#    (same container also makes the SSL_CERT_DIR hashed directory for tab case D2 with AL2023's openssl)
docker run --rm "${LBL[@]}" -v "$B/src":/src:ro -v "$B/pub":/out -v "$B/nuget":/root/.nuget/packages -v "$WORK/certs/ca.crt":/ca.crt:ro "$AL2023" sh -c '
  dnf -y -q install dotnet-sdk-10.0 dotnet-sdk-aot-10.0 clang zlib-devel openssl >/dev/null 2>&1 || exit 1
  mkdir -p /out/hashdir && cp /ca.crt /out/hashdir/$(openssl x509 -hash -noout -in /ca.crt).0
  export DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1
  cp -r /src /b && cd /b && dotnet publish -nologo -v q -c Release -f net10.0 -p:TargetFrameworks=net10.0 -r linux-arm64 -p:PublishAot=true -o /out/aot 2>&1 | grep -v "warning CA1416" || true
  test -x /out/aot/bootstrap || exit 1; rm -f /out/aot/*.dbg /out/aot/*.pdb'

pkg() { # pkg <zipname> <pubdir> [extra shell steps...]: probe + certs (+ extras) -> lambda/dotnet/<zipname>.zip
  local d="$B/pkg-$1"; rm -rf "$d"; mkdir -p "$d/certs"; cp -r "$B/pub/$2/." "$d/"; cp "${CERTS[@]}" "$d/certs/"; cp -r "$B/pub/hashdir" "$d/certs/"
  local n=$1; shift 2; for x in "$@"; do eval "$x"; done
  zipdir "$d" "$OUT/$n.zip"
}
BUNDLE='mkdir -p "$d/pq-tls"; cp "$CFG/pq-tls/openssl-pq.cnf" "$d/pq-tls/"'   # tab: Function.csproj CopyToPublishDirectory
for f in net8 net10; do
  pkg "probe-$f" "$f.0"
  pkg "probe-$f-bundled" "$f.0" "$BUNDLE" \
    'printf "%s\n" "#!/bin/bash" "# X509Store CurrentUser lives under \$HOME; Lambda has no writable HOME" "export HOME=/tmp" "exec \"\$@\"" > "$d/home-wrapper"; chmod 755 "$d/home-wrapper"'
done
pkg probe-aot aot
pkg probe-aot-bundled aot "$BUNDLE"
echo "lambda zips: $(ls "$OUT" | tr '\n' ' ')"

# 3. Lambda container images on public.ecr.aws/lambda/dotnet: baseline vs the two fix lines of configs/dotnet/Dockerfile.lambda
LC="$B/img/lambda"; mkdir -p "$LC/certs" "$LC/pq-tls"; cp "${CERTS[@]}" "$LC/certs/"; cp "$CFG/pq-tls/openssl-pq.cnf" "$LC/pq-tls/"
cp -r "$B/pub/net8.0" "$LC/net8"; cp -r "$B/pub/net10.0" "$LC/net10"
for v in 8 10; do
  cat > "$LC/Dockerfile.base" <<EOF
FROM public.ecr.aws/lambda/dotnet:$v
COPY net$v/ \${LAMBDA_TASK_ROOT}/
COPY certs/ \${LAMBDA_TASK_ROOT}/certs/
CMD ["probe::Probe.Function::Handler"]
EOF
  { sed '$d' "$LC/Dockerfile.base"; grep -E '^(COPY pq-tls|ENV OPENSSL_CONF)' "$CFG/Dockerfile.lambda"; echo 'CMD ["probe::Probe.Function::Handler"]'; } > "$LC/Dockerfile.fixed"
  grep -q '^ENV OPENSSL_CONF' "$LC/Dockerfile.fixed" || { echo "Dockerfile.lambda fix lines not found"; exit 1; }
  ecr_build pqc-dotnet-lambda "dotnet$v-baseline" "$LC" "$LC/Dockerfile.base"
  ecr_build pqc-dotnet-lambda "dotnet$v-fixed" "$LC" "$LC/Dockerfile.fixed"
done

# 4. ECS images. Every image carries /app/net8 and /app/net10 (+ certs, + the AL2023 conf file where it applies).
EC="$B/img/ecs"; mkdir -p "$EC/certs" "$EC/pq-tls"; cp "${CERTS[@]}" "$EC/certs/"; cp "$CFG/pq-tls/openssl-pq.cnf" "$EC/pq-tls/"
cp "$WORK/certs/ca.crt" "$EC/corp-ca.crt"
cp -r "$B/pub/net8.0" "$EC/net8"; cp -r "$B/pub/net10.0" "$EC/net10"
APP='COPY net8/ /app/net8/
COPY net10/ /app/net10/
COPY certs/ /app/certs/'
# MCR images the tab's container table compares (runtime and aspnet share the OS; aspnet where no runtime tag is pulled)
for img in runtime:8.0 runtime:8.0-alpine runtime:8.0-noble runtime:10.0 runtime:10.0-alpine runtime:10.0-azurelinux3.0 \
           aspnet:10.0-noble-chiseled aspnet:10.0-resolute aspnet:10.0-resolute-chiseled; do
  printf 'FROM %s/%s\n%s\n' "$MCR" "$img" "$APP" > "$EC/Dockerfile.mcr"
  ecr_build pqc-dotnet "mcr-${img/:/-}" "$EC" "$EC/Dockerfile.mcr"
done
# Tab case D5 (private CA in the system store), the tab's Dockerfile lines per OS family
printf 'FROM %s/aspnet:10.0-resolute\nCOPY corp-ca.crt /usr/local/share/ca-certificates/corp-ca.crt\nRUN update-ca-certificates\n%s\n' "$MCR" "$APP" > "$EC/Dockerfile.resolute-sysca"
ecr_build pqc-dotnet mcr-aspnet-10.0-resolute-sysca "$EC" "$EC/Dockerfile.resolute-sysca"
printf 'FROM %s/runtime:10.0-alpine\nRUN apk add --no-cache ca-certificates\nCOPY corp-ca.crt /usr/local/share/ca-certificates/corp-ca.crt\nRUN update-ca-certificates\n%s\n' "$MCR" "$APP" > "$EC/Dockerfile.alpine-sysca"
ecr_build pqc-dotnet mcr-runtime-10.0-alpine-sysca "$EC" "$EC/Dockerfile.alpine-sysca"
# AL2023 (same release as the AMI) + .NET 8 and 10 from dnf (tab Dockerfile.al2023 uses aspnetcore-runtime-8.0).
# Config file present, NOT enabled: the task definition's OPENSSL_CONF (configs/dotnet/taskdef.json) decides.
cat > "$EC/Dockerfile.al2023" <<EOF
FROM $AL2023
RUN dnf -y -q install aspnetcore-runtime-8.0 aspnetcore-runtime-10.0 && dnf clean all
COPY pq-tls/openssl-pq.cnf /etc/pq-tls/openssl-pq.cnf
$APP
EOF
# The tab's Dockerfile.al2023 as published: COPY + ENV OPENSSL_CONF baked into the image
{ echo "FROM $AL2023"; echo "RUN dnf -y -q install aspnetcore-runtime-8.0 aspnetcore-runtime-10.0 && dnf clean all"
  grep -E '^(COPY pq-tls|ENV OPENSSL_CONF)' "$CFG/Dockerfile.al2023"; echo "$APP"; } > "$EC/Dockerfile.al2023-fixed"
grep -q '^ENV OPENSSL_CONF' "$EC/Dockerfile.al2023-fixed" || { echo "Dockerfile.al2023 fix lines not found"; exit 1; }
# Option B of Dockerfile.al2023 (commented alternative): image-wide crypto policy
cat > "$EC/Dockerfile.al2023-policy" <<EOF
FROM $AL2023
RUN dnf -y -q install aspnetcore-runtime-8.0 aspnetcore-runtime-10.0 crypto-policies-scripts && update-crypto-policies --set DEFAULT:PQ && dnf clean all
$APP
EOF
# D5 on AL2023: CA in the system trust (update-ca-trust) + OPENSSL_CONF: the kit file must keep the CA locations working
cat > "$EC/Dockerfile.al2023-sysca" <<EOF
FROM $AL2023
RUN dnf -y -q install aspnetcore-runtime-10.0 && dnf clean all
COPY corp-ca.crt /etc/pki/ca-trust/source/anchors/corp-ca.crt
RUN update-ca-trust
COPY pq-tls/openssl-pq.cnf /etc/pq-tls/openssl-pq.cnf
$APP
EOF
for t in al2023 al2023-fixed al2023-policy al2023-sysca; do ecr_build pqc-dotnet "$t" "$EC" "$EC/Dockerfile.$t"; done

# 5. EC2: files for the golden AMI (/opt/pqc/dotnet/...); the AMI installs the dnf runtimes (packages.d/dotnet.txt)
E="$ART/ec2/dotnet"; rm -rf "$E"; mkdir -p "$E/pq-tls"
cp -r "$B/pub/net8.0" "$E/net8"; cp -r "$B/pub/net10.0" "$E/net10"; cp "$CFG/pq-tls/openssl-pq.cnf" "$E/pq-tls/"
echo "dotnet artifacts done"
