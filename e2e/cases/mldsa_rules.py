"""Expected ML-DSA certificate behaviour per client case (targets mldsa-dual, mldsa-only, mldsa-mtls).

The rule is the TLS library and its configuration, as documented in the guide (Use cases, ML-DSA per client stack,
and the Certificates (ML-DSA) tab):
  - OpenSSL 3.5 with default signature algorithms offers ML-DSA: the dual server sends ML-DSA, ML-DSA-only works,
    and an ML-DSA client key signs (MLDSA_FULL).
  - Amazon Linux 2023's DEFAULT crypto policy lists only classical signature algorithms. Our ML-KEM file
    openssl-pq.cnf includes that policy, so it stays classical for signatures; DEFAULT:PQ adds ML-DSA; Node's
    system file (openssl-pq-node-system.cnf) sets its own list without the policy and gets ML-DSA.
  - OpenSSL 1.x, 3.0 to 3.4, Go and Java (JSSE and Bouncy Castle JSSE) never offer ML-DSA: they get the ECDSA
    certificate from the dual server and fail the other two (MLDSA_NONE). The ML-DSA root in their bundle is harmless.
  - TLS 1.2 caps rule ML-DSA out (TLS 1.3 only).
  - .NET 8 negotiates ML-DSA through OpenSSL 3.5 but cannot load an ML-DSA private key (no ML-DSA key type before
    .NET 10), so its ML-DSA client certificate fails (DOTNET8).
  - Python 3.9 to 3.11 with the pq-tls shim or layer: requests goes through pyOpenSSL, whose cryptography wheel
    bundles OpenSSL 3.5, so ML-DSA works there although the runtime's own OpenSSL is 1.1.1.
  - A case that fails every handshake for another reason (FIPS-only Go, boringcrypto panic, Java 8 without the host
    name flag, the shim without idna) fails these too (ALL_FAIL). Trust-negative cases do not: the probes trust
    ca-both.crt on the mldsa-* targets.
"""
import re
from lib import MLDSA_FULL, MLDSA_NONE

ALL_FAIL = {"mldsa-dual": {"ok": False}, "mldsa-only": {"ok": False}, "mldsa-mtls": {"ok": False}}
DOTNET8 = {"mldsa-dual": {"ok": True, "server_cert": "mldsa"}, "mldsa-only": {"ok": True, "server_cert": "mldsa"},
           "mldsa-mtls": {"ok": False, "error_match": "not a known key algorithm"}}

# Cases that fail every handshake for a runtime reason. Trust-negative cases (no CA, wrong pin) are not here: the
# probes always trust ca-both.crt on the mldsa-* targets, so those behave like their stack's default.
ALL_FAIL_IDS = [r"go125-fips140-only$", r"boring-fips140-on$", r"^java-lambda-j8-bundled$", r"^java-lambda-image-j8-fixed$",
                r"corretto8-agent$", r"shim-noidna$"]
NODE_NONE = [r"lambda-n18", r"lambda-n20", r"lib-20-", r"lib-2219-", r"lib-244-", r"tls-max-12",
             r"al2023-n2\d-baseline"]


def expect(lang, c):
    i = c["id"]
    if any(re.search(p, i) for p in ALL_FAIL_IDS):
        return ALL_FAIL
    if lang in ("go", "java"):
        return MLDSA_NONE
    if lang == "node":
        return MLDSA_NONE if any(re.search(p, i) for p in NODE_NONE) else MLDSA_FULL
    if lang == "python":
        if re.search(r"py3(9|10|11)-(bundled-shim|layer)$", i):
            return MLDSA_FULL
        if "policy" in i or "layer-ownconf" in i or "trixie" in i or "alpine" in i:
            return MLDSA_FULL
        return MLDSA_NONE
    if lang == "dotnet":
        if "alpine" in i or "resolute" in i or "policy" in i:
            return DOTNET8 if re.search(r"80-alpine|alpine8|net8", i) else MLDSA_FULL
        return MLDSA_NONE
    return MLDSA_NONE
