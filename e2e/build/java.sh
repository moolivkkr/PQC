#!/bin/bash
# Java artifacts: probe class (--release 8), pq-tls kit v2 built from source (kit/java-v2) with Bouncy Castle 1.87
# from Maven Central, Lambda zips, Lambda container images, ECS images, EC2 AMI files, Lambda layer parts.
# Fix files come from the document's kit/java-v2 and configs/java/ so the published files are what gets tested.
source "$(dirname "$0")/../env.sh"; source "$E2E_DIR/build/lib.sh"
SRC="$E2E_DIR/clients/java"; KIT="$REPO_ROOT/kit/java-v2"; CFG="$REPO_ROOT/configs/java"
B="$WORK/build/java"; OUT="$ART/lambda/java"; CACHE="$WORK/cache/java"
rm -rf "$B" "$OUT"; mkdir -p "$B" "$OUT" "$CACHE"
BC=1.87
JDK_IMG=public.ecr.aws/amazoncorretto/amazoncorretto@sha256:597dbb85c5809a306df0675f491832ec18480cf03754c95a3985cbe645272b85  # 21.0.13
CORRETTO_8=public.ecr.aws/amazoncorretto/amazoncorretto@sha256:003d58c8ab28d04de22d6584b9e8dc309775600c23fdf6836d49196903cf77d5   # 8u512
CORRETTO_11=public.ecr.aws/amazoncorretto/amazoncorretto@sha256:7072fdb6991f9339d1fc565c94b286db0496ddc33f2521664432d0763eebc0fd  # 11.0.33
CORRETTO_17=public.ecr.aws/amazoncorretto/amazoncorretto@sha256:df791ac44a535fff63608b3d09fca4a0c6718469cf4e15fe9ff35c3013f8773f  # 17.0.21
CORRETTO_21=$JDK_IMG
CORRETTO_25=public.ecr.aws/amazoncorretto/amazoncorretto@sha256:83f85eb5b71b272ae2e49311c082d8f7ca046bdc1a3bee1765f842d362798fd7  # 25.0.5
TEMURIN_21=public.ecr.aws/docker/library/eclipse-temurin@sha256:18bb4a91a3dea3f03ee31d3755af34dfb40f904fc77ab56cdc2f092e32fff9c2  # 21-jre
LJ_8=public.ecr.aws/lambda/java@sha256:0b3a8a10b1623771090353bc59df0e521fa956f8ca583b06015e46b0698d5cbd    # 8.al2023
LJ_11=public.ecr.aws/lambda/java@sha256:ab4e285b685723edfe40144b322600a61c2dbf4e797c7af752ead8d393b90b25
LJ_17=public.ecr.aws/lambda/java@sha256:dc26a78f49ffab1408e552db47d64ec04b34c885343bef84edf477004a932e72
LJ_21=public.ecr.aws/lambda/java@sha256:ae9c3f35d5a6494ac51b3deeb6cfa421133295c279fe0cae7f27c6db693d6d3a
LJ_25=public.ecr.aws/lambda/java@sha256:6222e267a6f5d17b5b6bb8bf31a7504c8a95fd22eee8d1ba0ab09e31155094cb

# 1. Bouncy Castle 1.87 from Maven Central (sha1 checked, cached)
for a in bcprov bctls bcutil; do
  j="$CACHE/$a-jdk18on-$BC.jar"
  if [ ! -s "$j" ]; then
    curl -fsSLo "$j.tmp" "https://repo1.maven.org/maven2/org/bouncycastle/$a-jdk18on/$BC/$a-jdk18on-$BC.jar"
    want=$(curl -fsSL "https://repo1.maven.org/maven2/org/bouncycastle/$a-jdk18on/$BC/$a-jdk18on-$BC.jar.sha1" | cut -c1-40)
    got=$(shasum -a 1 "$j.tmp" | cut -d' ' -f1)
    [ "$want" = "$got" ] || { echo "checksum mismatch: $a ($got != $want)"; exit 1; }
    mv "$j.tmp" "$j"
  fi
done

# 2. Compile probe (--release 8) and the kit v2 agent from kit/java-v2/src; two jars (zip/image/EC2 and layer manifests)
mkdir -p "$B/src" "$B/kit/pq-tls" "$B/layer/pq-tls" "$B/layer/java/lib" "$B/probe"
cp "$SRC/Probe.java" "$KIT/src/PqTlsAgent.java" "$KIT/MANIFEST.MF" "$KIT/MANIFEST-layer.MF" "$B/src/"
cp "$CACHE"/b*-jdk18on-$BC.jar "$B/kit/pq-tls/"
docker run --rm "${LBL[@]}" -v "$B":/b -w /b "$JDK_IMG" sh -ec '
  mkdir -p cls-agent
  javac -nowarn --release 8 -d probe src/Probe.java 2>&1 | grep -v "^warning\|^Note\|^1 warning" || true
  javac -nowarn --release 8 -cp "kit/pq-tls/*" -d cls-agent src/PqTlsAgent.java 2>&1 | grep -v "^warning\|^Note\|^1 warning" || true
  jar cfm kit/pq-tls/pq-tls-agent.jar src/MANIFEST.MF -C cls-agent PqTlsAgent.class
  jar cfm layer/pq-tls/pq-tls-agent.jar src/MANIFEST-layer.MF -C cls-agent PqTlsAgent.class'
[ -f "$B/probe/Probe.class" ] && [ -f "$B/kit/pq-tls/pq-tls-agent.jar" ] || { echo "java compile failed"; exit 1; }
cp "$KIT/pq-tls/pq-tls.security" "$B/kit/pq-tls/"
cp "$CFG/pq-tls/bc-static.security" "$B/kit/pq-tls/"          # static registration variant (containers/EC2)
cp "$CACHE"/b*-jdk18on-$BC.jar "$B/layer/java/lib/"

# 3. Test certs: the shared PKI + an EC P-256 client keystore (client-ec.p12, signed by the same test CA) so the
#    tab's EC-certificate claims (SunX509 vs PKIX key manager under BCJSSE) can be exercised against the mtls listener.
C="$CACHE/certs"; mkdir -p "$C"
if [ ! -s "$C/client-ec.p12" ] || [ "$WORK/certs/ca.crt" -nt "$C/client-ec.p12" ]; then
  docker run --rm "${LBL[@]}" -v "$WORK/certs":/ca:ro -v "$C":/o -w /o --entrypoint sh "$RUNNER" -ec '
    openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout client-ec.key -out client-ec.csr -subj /CN=pqc-client-ec 2>/dev/null
    printf "extendedKeyUsage=clientAuth\n" > ext
    openssl x509 -req -in client-ec.csr -CA /ca/ca.crt -CAkey /ca/ca.key -CAserial /o/ca.srl -CAcreateserial -days 825 -extfile ext -out client-ec.crt 2>/dev/null
    openssl pkcs12 -export -in client-ec.crt -inkey client-ec.key -certfile /ca/ca.crt -name pqc-client-ec -out client-ec.p12 -passout pass:changeit
    rm -f client-ec.csr ext; chmod 644 *'
fi
certs() { mkdir -p "$1"; cp "$WORK/certs/"{ca.crt,client.crt,client.key,client.p12,truststore.p12,truststore-both.p12,client-mldsa.p12} "$C/client-ec.p12" "$1/"; }

# 4. Lambda zips (class at the zip root; certs/ next to it)
pkg() { # pkg <name> [extra shell steps...] -> lambda/java/<name>.zip
  local d="$B/pkg-$1"; rm -rf "$d"; mkdir -p "$d"
  cp "$B/probe/Probe.class" "$d/"; certs "$d/certs"
  shift; for x in "$@"; do eval "$x"; done
  zipdir "$d" "$OUT/$(basename "$d" | sed 's/^pkg-//').zip"
}
pkg probe
# Tab "Lambda zip": pq-tls/ at the zip root (agent v2, pq-tls.security, three BC jars)
pkg probe-agent 'mkdir -p "$d/pq-tls"; cp "$B/kit/pq-tls/"{pq-tls-agent.jar,pq-tls.security,b*-jdk18on-$BC.jar} "$d/pq-tls/"'
# Function with its own security file passed on the command line (no PKIX line): wrapper must leave it, agent v2 sets PKIX
pkg probe-ownsec 'mkdir -p "$d/conf"; printf "%s\n" "# the application'"'"'s own security overrides" "networkaddress.cache.ttl=30" > "$d/conf/app.security"'
# Static java.security registration on Lambda (tab: "Doesn't work"): BC jars in lib/ + bc-static.security
pkg probe-static 'mkdir -p "$d/lib" "$d/pq-tls"; cp "$B/kit/pq-tls/"b*-jdk18on-$BC.jar "$d/lib/"; cp "$B/kit/pq-tls/bc-static.security" "$d/pq-tls/"'
echo "lambda zips: $(ls "$OUT" | tr '\n' ' ')"

# 5. Layer part (tab "Layer layout (kit v2)"): /opt/pq-tls/pq-tls-agent.jar (MANIFEST-layer.MF) + /opt/java/lib/*.jar.
#    wrapper + pq-tls.security are already there (build/common.sh copies them from kit/java-v2/pq-tls-layer).
L="$ART/layer-src/pq-tls"; mkdir -p "$L/pq-tls" "$L/java/lib"
cp "$B/layer/pq-tls/pq-tls-agent.jar" "$L/pq-tls/"; cp "$B/layer/java/lib/"*.jar "$L/java/lib/"
[ -f "$L/pq-tls/wrapper" ] || { echo "layer-src/pq-tls/pq-tls/wrapper missing: run build/common.sh first"; exit 1; }

# 6. Lambda container images (PackageType Image): baseline, and fixed = the COPY/ENV lines of configs/java/Dockerfile.lambda
LC="$B/lambda-image"; mkdir -p "$LC/classes" "$LC/pq-tls"; cp "$B/probe/Probe.class" "$LC/classes/"; certs "$LC/classes/certs"
cp "$B/kit/pq-tls/"{pq-tls-agent.jar,pq-tls.security,b*-jdk18on-$BC.jar} "$LC/pq-tls/"
for v in 8 11 17 21 25; do
  eval "img=\$LJ_$v"
  printf 'FROM %s\nCOPY classes/ ${LAMBDA_TASK_ROOT}/\nCMD ["Probe::handleRequest"]\n' "$img" > "$LC/Dockerfile.base"
  ecr_build pqc-java-lambda "java$v-baseline" "$LC" "$LC/Dockerfile.base"
  [ $v = 25 ] && continue
  { sed '$d' "$LC/Dockerfile.base"; grep -E '^(COPY pq-tls|ENV JAVA_TOOL_OPTIONS)' "$CFG/Dockerfile.lambda" \
      | sed "$( [ $v = 8 ] && echo 's|pq-tls-agent.jar"$|pq-tls-agent.jar -Djdk.tls.client.protocols=TLSv1.3,TLSv1.2"|' )"
    echo 'CMD ["Probe::handleRequest"]'; } > "$LC/Dockerfile.fixed"
  grep -q 'ENV JAVA_TOOL_OPTIONS' "$LC/Dockerfile.fixed" || { echo "Dockerfile.lambda lines not found"; exit 1; }
  ecr_build pqc-java-lambda "java$v-fixed" "$LC" "$LC/Dockerfile.fixed"
done
# java8.al2023 + the pq-tls layer: LocalStack 2026.10.6 rejects Runtime=java8.al2023 for zips, so the layer is
# applied the way AWS documents for images (layer contents copied to /opt) + AWS_LAMBDA_EXEC_WRAPPER.
rm -rf "$LC/opt"; cp -a "$L" "$LC/opt"
printf 'FROM %s\nCOPY classes/ ${LAMBDA_TASK_ROOT}/\nCOPY opt/ /opt/\nENV AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper\nCMD ["Probe::handleRequest"]\n' "$LJ_8" > "$LC/Dockerfile.layer"
ecr_build pqc-java-lambda java8-layer "$LC" "$LC/Dockerfile.layer"

# 7. ECS images: probe in /app, certs in /app/certs, kit v2 in /opt/pq-tls (present, NOT enabled: the task
#    definition's JAVA_TOOL_OPTIONS decides, as in configs/java/taskdef.json)
EC="$B/ecs"; mkdir -p "$EC/app" "$EC/pq-tls"; cp "$B/probe/Probe.class" "$EC/app/"; certs "$EC/app/certs"
cp "$B/kit/pq-tls/"* "$EC/pq-tls/"
for v in 8 11 17 21 25; do
  eval "img=\$CORRETTO_$v"
  printf 'FROM %s\nCOPY app/ /app/\nCOPY pq-tls/ /opt/pq-tls/\n' "$img" > "$EC/Dockerfile.corretto"
  ecr_build pqc-java "corretto$v" "$EC" "$EC/Dockerfile.corretto"
done
# configs/java/Dockerfile.jdk21-agent: kit enabled in the image (ENV + USER 1000)
{ printf 'FROM %s\nCOPY app/ /app/\n' "$CORRETTO_21"; grep -E '^(COPY pq-tls/|ENV JAVA_TOOL_OPTIONS|USER)' "$CFG/Dockerfile.jdk21-agent"; } > "$EC/Dockerfile.agent"
ecr_build pqc-java corretto21-agent-image "$EC" "$EC/Dockerfile.agent"
# configs/java/Dockerfile.static: BC jars + bc-static.security + ENV (namedGroups pin with ML-KEM); run with -cp
for t in temurin21:TEMURIN_21 corretto17:CORRETTO_17 corretto21:CORRETTO_21; do
  eval "img=\$${t#*:}"
  { printf 'FROM %s\nCOPY app/ /app/\n' "$img"; grep -E '^(COPY pq-tls/|ENV JAVA_TOOL_OPTIONS)' "$CFG/Dockerfile.static"; } > "$EC/Dockerfile.static"
  grep -q bc-static.security "$EC/Dockerfile.static" || { echo "Dockerfile.static lines not found"; exit 1; }
  ecr_build pqc-java "${t%%:*}-static" "$EC" "$EC/Dockerfile.static"
done
# AL2023 (same release as the AMI) + Corretto from dnf, kit present not enabled
printf 'FROM %s\nRUN dnf -y -q install java-17-amazon-corretto-headless java-21-amazon-corretto-headless java-25-amazon-corretto-headless && dnf clean all\nCOPY app/ /app/\nCOPY pq-tls/ /opt/pq-tls/\n' "$AL2023" > "$EC/Dockerfile.al2023"
ecr_build pqc-java al2023 "$EC" "$EC/Dockerfile.al2023"

# 8. EC2: files for the golden AMIs (/opt/pqc/java/...): probe, EC client keystore, kit v2 (zip/EC2 manifest layout)
E="$ART/ec2/java"; rm -rf "$E"; mkdir -p "$E/pq-tls"
cp "$B/probe/Probe.class" "$C/client-ec.p12" "$E/"; cp "$B/kit/pq-tls/"* "$E/pq-tls/"
echo "java artifacts done"
