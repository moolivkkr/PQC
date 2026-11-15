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
