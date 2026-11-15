#!/bin/bash
# java-pq-check.sh <repo dir>: fail the build on Java settings that block hybrid PQ TLS
# (X25519MLKEM768) or break the pq-tls kit. Exit 1 on any FAIL; WARN lines need a human look.
# Scans source, build files, Dockerfiles, Helm/K8s/ECS/Lambda IaC, launch scripts, properties and YAML.
set -uo pipefail
ROOT=${1:-.}
INC=(--include='*.java' --include='*.kt' --include='*.scala' --include='*.groovy' --include='*.xml'
     --include='*.properties' --include='*.yml' --include='*.yaml' --include='*.json' --include='*.tf'
     --include='*.sh' --include='*.conf' --include='*.service' --include='Dockerfile*' --include='*.env'
     --include='*.security' --include='*.gradle' --include='*.kts')
fails=0
hit() { # level message pattern
  local out; out=$(grep -rnIE "${INC[@]}" --exclude-dir=.git --exclude-dir=target --exclude-dir=build \
                   --exclude-dir=node_modules "$3" "$ROOT" 2>/dev/null | grep -v 'java-pq-check' | head -20)
  [ -z "$out" ] && return
  echo "$1: $2"; echo "$out" | sed 's/^/    /'
  [ "$1" = FAIL ] && fails=$((fails+1)); }

# 1. Group pins without the hybrid group (also turns PQ off on JDK 25 and for Netty tcnative).
out=$(grep -rnIE "${INC[@]}" --exclude-dir=.git 'jdk\.tls\.namedGroups|setGroups\(|groups="|OpenSslContextOption\.GROUPS' "$ROOT" 2>/dev/null \
      | grep -v 'java-pq-check' | grep -vi 'X25519MLKEM768' | head -20)
[ -n "$out" ] && { echo "FAIL: named-group list without X25519MLKEM768"; echo "$out" | sed 's/^/    /'; fails=$((fails+1)); }
# 2. TLS 1.2-only pins (ML-KEM exists only in TLS 1.3).
hit FAIL 'TLS 1.2-only protocol pin' 'SSLContext\.getInstance\("TLSv1\.2"\)|TLS\.V_1_2\)|protocols?="TLSv1\.2"|enabled-protocols: *\[?TLSv1\.2\]?$|ssl\.enabled\.protocols=TLSv1\.2$|jdk\.tls\.(client|server)\.protocols=TLSv1\.2([^,]|$)|tlsVersions=TLSv1\.2([^,]|$)'
# 3. Hard-coded SunX509 key manager: EC certificates (server and mTLS client) fail under the BC agent.
hit FAIL 'hard-coded SunX509 key manager (use KeyManagerFactory.getDefaultAlgorithm() or "PKIX")' \
  'KeyManagerFactory\.getInstance\("SunX509"|keyManagerAlgorithm *= *"?SunX509|ssl\.KeyManagerFactory\.algorithm *= *SunX509|key-manager-algorithm: *SunX509'
# 4. A security-properties file given with '==' replaces java.security completely (drops the kit's line).
hit FAIL 'java.security.properties with == replaces the whole java.security file' 'java\.security\.properties=='
# 5. JDK below 25 in images and runtimes: needs the kit (agent + pq-tls.security) until upgraded.
hit WARN 'JDK below 25 (needs the pq-tls kit or an upgrade to 25.0.5+)' \
  '(FROM|image:|"image").*(corretto|temurin|openjdk|jdk|jre|java)[:-]?(8|11|17|21)([^0-9]|$)|Runtime: *java(8|11|17|21)|runtime *= *"java(8|11|17|21)'
# 6. Kit present without the key-manager fix (v1 packaging).
out=$(grep -rnIE "${INC[@]}" --exclude-dir=.git 'pq-tls-agent\.jar' "$ROOT" 2>/dev/null | grep -v 'java-pq-check' | grep -v 'pq-tls\.security' | head -20)
[ -n "$out" ] && echo "WARN: pq-tls agent without pq-tls.security on the same line (fine only with agent v2)" && echo "$out" | sed 's/^/    /'
# 7. Things that bypass JSSE and need their own check.
hit WARN 'own TLS stack: check separately (tcnative/BoringSSL, CRT, conscrypt, wolfSSL)' 'netty-tcnative|SslProvider\.OPENSSL|aws-crt|conscrypt|wolfssl'
hit WARN 'FIPS provider in use: the non-FIPS BC agent must not be added' 'bc-fips|bctls-fips|BouncyCastleFipsProvider|com\.safelogic|fips\.provider'
echo "java-pq-check: $fails failing check(s)"
[ $fails -eq 0 ]
