# Conftest policy for Dockerfiles (conftest parses Dockerfile natively).
# Usage: conftest test --policy rules/opa/dockerfile --namespace dockerfile.pq_tls Dockerfile
package dockerfile.pq_tls

import rego.v1

# ENV is parsed as triplets: [key, value, "="] per pair.
# Base images whose system OpenSSL is < 3.5 or whose runtime has no PQ (warn: upgrade the base).
classical_bases := [
	"debian:bookworm", "debian:12", "ubuntu:22.04", "ubuntu:24.04", "ubuntu:jammy", "ubuntu:noble",
	"node:18", "node:20",
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
	msg := sprintf("PQ-D1: base image %s has no PQ by default (OpenSSL < 3.5 or runtime too old). Use debian:trixie, alpine:3.22+, node:22.20+/24.5+, golang:1.26+, JDK 25.", [img])
}

# Official python images default to Debian trixie (OpenSSL 3.5, PQ) for every tag, 3.9 to 3.15;
# only the explicit -bookworm (OpenSSL 3.0) and -bullseye (1.1.1) variants are classical.
warn contains msg if {
	some img in from_images
	regex.match(`^python:[^@]*-(bookworm|bullseye)([-@]|$)`, img)
	msg := sprintf("PQ-D1: base image %s is Debian bookworm/bullseye (OpenSSL < 3.5, no PQ). Use the default tag or -trixie.", [img])
}

# Official Node bundles OpenSSL 3.5 from 22.20.0 and 24.5.0; a tag pinned below that is classical.
# Floating tags (node:22, node:24) resolve to current releases and pass.
warn contains msg if {
	some img in from_images
	regex.match(`^node:(22\.([0-9]|1[0-9])|24\.[0-4])([.@-]|$)`, img)
	msg := sprintf("PQ-D1: base image %s pins Node below 22.20 / 24.5 (bundled OpenSSL 3.0, no PQ). Use 22.20+ or 24.9+.", [img])
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
