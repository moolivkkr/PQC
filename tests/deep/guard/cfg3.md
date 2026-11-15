`rules/opa/image/openssl_sbom.rego`

```text
# Conftest policy for a Syft JSON SBOM (syft <image> -o syft-json).
# Fails when the image's system OpenSSL is older than 3.5 (no ML-KEM).
# Usage: conftest test --policy rules/opa/image --namespace image.openssl sbom.json
package image.openssl

import rego.v1

openssl_pkgs := {"openssl", "libssl3", "libssl3t64", "openssl-libs", "libcrypto3", "libssl3-openssl", "openssl3"}

# Packages that carry the system TLS library, with "major.minor" parsed from the version.
ssl_pkgs contains {"name": a.name, "version": a.version, "mm": mm} if {
	some a in input.artifacts
	a.name in openssl_pkgs
	m := regex.find_all_string_submatch_n(`^(?:\d+:)?(\d+)\.(\d+)`, a.version, 1)
	mm := [to_number(m[0][1]), to_number(m[0][2])]
}

too_old(mm) if mm[0] < 3

too_old(mm) if {
	mm[0] == 3
	mm[1] < 5
}

deny contains msg if {
	some p in ssl_pkgs
	too_old(p.mm)
	msg := sprintf("PQ-I1 %s: %s %s is older than OpenSSL 3.5 (no X25519MLKEM768). Rebase on debian:trixie / alpine:3.22+ or add a PQ-capable TLS library.", [input.source.metadata.userInput, p.name, p.version])
}

warn contains msg if {
	count(ssl_pkgs) == 0
	msg := sprintf("PQ-I2 %s: no system OpenSSL package found (distroless/static image?). Check the language runtime's own TLS stack (Go, Java, .NET, Node).", [input.source.metadata.userInput])
}

warn contains msg if {
	some a in input.artifacts
	a.name in {"openssl-libs"}
	contains(a.version, "amzn2023")
	msg := sprintf("PQ-I3 %s: Amazon Linux 2023 OpenSSL needs crypto-policy DEFAULT:PQ or OPENSSL_CONF=openssl-pq.cnf for ML-KEM by default.", [input.source.metadata.userInput])
}
```

`rules/image/check-go-pq.sh`

```bash
#!/bin/sh
# check-go-pq.sh <go-binary>...  - fail if a Go binary will not offer X25519MLKEM768 by default.
# Needs a Go toolchain (any version >= the binary's) on PATH for `go version -m`.
# Rules (Go crypto/tls): toolchain >= 1.24 AND the module's go directive >= 1.24, otherwise the
# default GODEBUG carries tlsmlkem=0. An explicit tls.Config.CurvePreferences is not visible here:
# catch it with the source grep at the end of this script's README section.
rc=0
for bin in "$@"; do
  info=$(go version -m "$bin" 2>/dev/null) || { echo "SKIP $bin: not a Go binary"; continue; }
  tool=$(printf '%s\n' "$info" | head -1 | sed -E 's/.*: go([0-9]+)\.([0-9]+).*/\1 \2/')
  set -- $tool
  major=$1; minor=$2
  godebug=$(printf '%s\n' "$info" | awk '$1=="build" && $2 ~ /^DefaultGODEBUG=/ {sub(/^DefaultGODEBUG=/,"",$2); print $2}')
  if [ "$major" -lt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -lt 24 ]; }; then
    echo "FAIL $bin: built with go$major.$minor (< 1.24, no ML-KEM in crypto/tls)"; rc=1
  elif printf '%s' "$godebug" | grep -q 'tlsmlkem=0'; then
    echo "FAIL $bin: DefaultGODEBUG=$godebug (go.mod go directive < 1.24). Raise go to >= 1.24 or add //go:debug tlsmlkem=1"; rc=1
  else
    echo "PASS $bin: go$major.$minor DefaultGODEBUG=${godebug:-<none>}"
  fi
done
exit $rc
```

`rules/image/check-jdk-pq.sh`

```bash
#!/bin/sh
# check-jdk-pq.sh <image>  - read the JDK `release` file from a container image without running it.
# PASS: JAVA_VERSION >= 25. WARN: 8-21 (needs the Bouncy Castle JSSE agent; check JAVA_TOOL_OPTIONS).
# Needs: docker (or podman with the same CLI).
img="$1"
cid=$(docker create ${DOCKER_CREATE_ARGS:-} "$img" /bin/true) || exit 2
trap 'docker rm -f "$cid" >/dev/null 2>&1' EXIT
jhome=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$img" | sed -n 's/^JAVA_HOME=//p' | head -1)
for p in "${jhome:-/nonexistent}/release" /opt/java/openjdk/release /usr/lib/jvm/default-jvm/release /usr/lib/jvm/java/release; do
  if docker cp "$cid:$p" - 2>/dev/null | tar -xO 2>/dev/null > /tmp/jdk-release.$$; then
    [ -s /tmp/jdk-release.$$ ] && break
  fi
done
ver=$(sed -n 's/^JAVA_VERSION="\{0,1\}\([^"]*\)"\{0,1\}/\1/p' /tmp/jdk-release.$$ 2>/dev/null); rm -f /tmp/jdk-release.$$
[ -z "$ver" ] && { echo "SKIP $img: no JDK release file found"; exit 0; }
major=$(echo "$ver" | sed -E 's/^1\.([0-9]+).*/\1/; s/^([0-9]+).*/\1/')
jto=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$img" | sed -n 's/^JAVA_TOOL_OPTIONS=//p')
if [ "$major" -ge 25 ]; then
  echo "PASS $img: JDK $ver (ML-KEM hybrid groups on by default)"
elif echo "$jto" | grep -q 'pq-tls-agent.jar\|bctls'; then
  echo "PASS $img: JDK $ver with Bouncy Castle JSSE agent ($jto)"
else
  echo "WARN $img: JDK $ver has no ML-KEM TLS group. Add -javaagent:/opt/pq-tls/pq-tls-agent.jar or move to JDK 25"; exit 1
fi
```

`rules/opa/dockerfile/pq_dockerfile.rego`

```text
# Conftest policy for Dockerfiles (conftest parses Dockerfile natively).
# Usage: conftest test --policy rules/opa/dockerfile --namespace dockerfile.pq_tls Dockerfile
package dockerfile.pq_tls

import rego.v1

# ENV is parsed as triplets: [key, value, "="] per pair.
# Base images whose system OpenSSL is < 3.5 or whose runtime has no PQ (warn: upgrade the base).
classical_bases := [
	"debian:bookworm", "debian:12", "ubuntu:22.04", "ubuntu:24.04", "ubuntu:jammy", "ubuntu:noble",
	"node:18", "node:20", "python:3.9", "python:3.10", "python:3.11",
	"amazonlinux:2", "public.ecr.aws/lambda/nodejs:20", "public.ecr.aws/lambda/nodejs:18",
	"public.ecr.aws/lambda/python:3.11", "public.ecr.aws/lambda/python:3.10", "public.ecr.aws/lambda/python:3.9",
	"golang:1.22", "golang:1.23", "eclipse-temurin:17", "eclipse-temurin:21", "amazoncorretto:17", "amazoncorretto:21",
]

from_images contains img if {
	some instr in input
	instr.Cmd == "from"
	img := lower(instr.Value[0])
}

env_pairs contains [k, v] if {
	some instr in input
	instr.Cmd == "env"
	some i
	i % 3 == 0
	k := instr.Value[i]
	v := instr.Value[i + 1]
}

run_lines contains line if {
	some instr in input
	instr.Cmd == "run"
	line := concat(" ", instr.Value)
}

warn contains msg if {
	some img in from_images
	some base in classical_bases
	base_match(img, base)
	msg := sprintf("PQ-D1: base image %s has no PQ by default (OpenSSL < 3.5 or runtime too old). Use debian:trixie, alpine:3.22+, node:22+, golang:1.24+, JDK 25.", [img])
}

deny contains msg if {
	some [k, v] in env_pairs
	k == "GODEBUG"
	contains(v, "tlsmlkem=0")
	msg := "PQ-D2: ENV GODEBUG tlsmlkem=0 disables X25519MLKEM768 in Go"
}

deny contains msg if {
	some [k, v] in env_pairs
	k == "OPENSSL_CONF"
	v == "/dev/null"
	msg := "PQ-D3: ENV OPENSSL_CONF=/dev/null drops PQ group configuration"
}

deny contains msg if {
	some [k, v] in env_pairs
	k in {"JAVA_TOOL_OPTIONS", "JAVA_OPTS", "JDK_JAVA_OPTIONS"}
	contains(v, "jdk.tls.namedGroups=")
	not contains(v, "X25519MLKEM768")
	msg := sprintf("PQ-D4: %s sets jdk.tls.namedGroups without X25519MLKEM768", [k])
}

deny contains msg if {
	some line in run_lines
	regex.match(`update-crypto-policies\s+--set\s+(DEFAULT|LEGACY|FUTURE)\s*($|[;&])`, line)
	msg := "PQ-D5: update-crypto-policies sets a policy without the :PQ subpolicy (use DEFAULT:PQ on AL2023/RHEL)"
}

# "node:20" matches node:20, node:20-slim, node:20.18 but not node:200; "amazonlinux:2" does not match amazonlinux:2023.
base_match(img, base) if img == base

base_match(img, base) if startswith(img, concat("", [base, "-"]))

base_match(img, base) if startswith(img, concat("", [base, "."]))

base_match(img, base) if startswith(img, concat("", [base, "@"]))
```

