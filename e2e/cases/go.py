"""Go cases. Expectations are the Go tab's claims (src/03-go.md, line numbers below); a FAIL means the doc or the fix is wrong.

One probe source (clients/go), one static binary per toolchain / go line / FIPS mode (build/go.sh), run unchanged as the
Lambda bootstrap (provided.al2023, provided.al2, container image), in ECS images on several bases, and on the EC2 AMIs.
Besides the five observer targets, the hybrid target also checks the exact list of groups the client OFFERED (the
observer's record of that ClientHello, returned to the probe), so SecP hybrids, Kyber draft and FIPS lists are graded.
"""
import os

from lib import CLASSICAL, PQ, TLS12_ONLY, ALL, override, write

DOC = "src/03-go.md"
EGRESS_ENV = {  # pq-egress extension (same routes as cases/python.py); certs are in the zip at /var/task/certs
    "PQC_EGRESS_PORT": "2779", "PQ_EGRESS_PORT": "2779",
    "PQ_EGRESS_ROUTES": "hybrid=pq-observer:8443,pqonly=pq-observer:8444,mtls=pq-observer:8445;mtls,"
                        "eccert=pq-observer:8446,tls12=pq-observer:8447",
    "PQ_EGRESS_CA": "/var/task/certs/ca.crt", "PQ_EGRESS_CERT": "/var/task/certs/client.crt",
    "PQ_EGRESS_KEY": "/var/task/certs/client.key"}
WRAP = {"AWS_LAMBDA_EXEC_WRAPPER": "/opt/pq-tls/wrapper"}

# Offered groups, in the order Go sends them (crypto/tls defaults.go of each toolchain)
P_CURVES = ["CurveP256", "CurveP384", "CurveP521"]
OFF_123 = ["X25519Kyber768Draft00", "X25519"] + P_CURVES                     # Go 1.23: Kyber draft 0x6399, not ML-KEM
OFF_124 = ["X25519MLKEM768", "X25519"] + P_CURVES                            # 1.24, 1.25; 1.26 with tlssecpmlkem=0
OFF_126 = ["X25519MLKEM768", "SecP256r1MLKEM768", "SecP384r1MLKEM1024", "X25519"] + P_CURVES  # 1.26+, go line >= 1.26
OFF_CLASSIC = ["X25519"] + P_CURVES                                          # tlsmlkem=0 (go line < 1.24)
OFF_FIPS124 = P_CURVES                                                       # Go 1.24 FIPS mode
OFF_FIPS125 = ["X25519MLKEM768"] + P_CURVES
OFF_FIPS126 = ["X25519MLKEM768", "SecP256r1MLKEM768", "SecP384r1MLKEM1024"] + P_CURVES


def pq(offered):
    return override(PQ, hybrid=dict(PQ["hybrid"], offered_groups=offered))


def classical(offered, pqonly_err="handshake failure", group="X25519"):
    return override(CLASSICAL, hybrid=dict(CLASSICAL["hybrid"], group=group, offered_groups=offered),
                    pqonly={"ok": False, "error_match": pqonly_err})


def p256(offered):
    """FIPS mode without PQ: P-256 negotiated everywhere, including the TLS 1.2 server."""
    e = classical(offered, group="CurveP256")
    for t in ("mtls", "eccert"):
        e[t] = dict(e[t], group="CurveP256")
    e["tls12"] = dict(e["tls12"], group="CurveP256")
    return e


def all_fail(pattern):
    return {t: {"ok": False, "error_match": pattern} for t in ALL}


cases = []


def lam(id, rt, mode, title, expect, zip, layers=(), env=None, doc=DOC, finding=None):
    c = {"id": id, "compute": "lambda", "mode": mode, "title": title, "doc": doc, "expect": expect,
         "lambda": {"runtime": rt, "handler": "bootstrap", "zip": "go/%s.zip" % zip, "layers": list(layers), "env": env or {}}}
    if finding:
        c["finding"] = finding
    cases.append(c)


BASE = {"1.23": OFF_123, "1.24": OFF_124, "1.25": OFF_124, "1.26": OFF_126, "1.27": OFF_126}
L = {"1.23": "21", "1.24": "20", "1.25": "19", "1.26": "18", "1.27": "17"}
RTS = {"provided.al2023": "al2023", "provided.al2": "al2"}

# --- Lambda zip: toolchain matrix on both OS-only runtimes (tab line 13, 53: same binary, same result)
for rt, r in RTS.items():
    for v, off in BASE.items():
        tag = v.replace(".", "")
        exp = classical(off) if v == "1.23" else pq(off)
        lam("go-lambda-%s-go%s-baseline" % (r, tag), rt, "baseline",
            "%s bootstrap built with Go %s, go %s: %s" % (rt, v, v, "no ML-KEM (Kyber draft offered)" if v == "1.23" else "PQ by default"),
            exp, "probe-" + v, doc="%s:%s, :53" % (DOC, L[v]))
    # Go 1.23 can't negotiate ML-KEM itself: the pq-egress extension originates the TLS
    lam("go-lambda-%s-go123-extension" % r, rt, "extension",
        "%s Go 1.23 bootstrap + pq-egress extension layer: extension originates PQ TLS" % rt, pq(OFF_126),
        "probe-1.23", layers=["pq-egress"], env=EGRESS_ENV, doc="e2e/lambda/extension/pq-egress (extension option)")
    lam("go-lambda-%s-go123-pqtls-layer" % r, rt, "layer",
        "%s Go 1.23 + pq-tls layer + AWS_LAMBDA_EXEC_WRAPPER: wrapper has no Go branch, Go ignores OPENSSL_CONF -> no effect" % rt,
        classical(OFF_123), "probe-1.23", layers=["pq-tls"], env=WRAP,
        doc="kit/java-v2/pq-tls-layer/wrapper (no provided.* branch); %s:7 (OpenSSL plays no part)" % DOC)
lam("go-lambda-al2023-go127-pqtls-layer", "provided.al2023", "layer",
    "provided.al2023 Go 1.27 + pq-tls layer: no effect, still PQ", pq(OFF_126), "probe-1.27", layers=["pq-tls"], env=WRAP,
    doc="kit/java-v2/pq-tls-layer/wrapper; %s:7" % DOC)
lam("go-lambda-al2023-go123-combined", "provided.al2023", "extension",
    "Go 1.23 + ONE combined layer (wrapper + extension), extension env: PQ via the extension", pq(OFF_126),
    "probe-1.23", layers=["pq-tls-combined"], env=dict(EGRESS_ENV, **WRAP))
lam("go-lambda-al2023-go123-combined-wrapper", "provided.al2023", "layer",
    "Go 1.23 + combined layer, wrapper path only (no extension env): no effect", classical(OFF_123),
    "probe-1.23", layers=["pq-tls-combined"], env=WRAP)

# --- go line (DefaultGODEBUG) and GODEBUG levers (tab lines 36-47, 59-67, 559, 583)
A = "provided.al2023"
lam("go-lambda-al2023-go127-mod123", A, "go-line", "Go 1.27 toolchain, go 1.23 line: tlsmlkem=0 -> classical (most common miss)",
    classical(OFF_CLASSIC), "probe-1.27-go1.23", doc=DOC + ":39, :559")
lam("go-lambda-al2023-go126-mod123", A, "go-line", "Go 1.26, go 1.23 line: classical", classical(OFF_CLASSIC),
    "probe-1.26-go1.23", doc=DOC + ":42")
lam("go-lambda-al2-go125-mod123", "provided.al2", "go-line", "Go 1.25, go 1.23 line: classical", classical(OFF_CLASSIC),
    "probe-1.25-go1.23", doc=DOC + ":44")
lam("go-lambda-al2023-go124-mod123", A, "go-line", "Go 1.24, go 1.23 line: classical", classical(OFF_CLASSIC),
    "probe-1.24-go1.23", doc=DOC + ":46, :20")
lam("go-lambda-al2023-go126-mod125", A, "go-line", "Go 1.26, go 1.25 line: X25519MLKEM768 but no SecP hybrids (tlssecpmlkem=0)",
    pq(OFF_124), "probe-1.26-go1.25", doc=DOC + ":41, :565")
lam("go-lambda-al2023-go124-mod123-godebug-env", A, "godebug", "Go 1.24 go 1.23 + GODEBUG=tlsmlkem=1 in function env: PQ, no rebuild",
    pq(OFF_124), "probe-1.24-go1.23", env={"GODEBUG": "tlsmlkem=1"}, doc=DOC + ":20, :65, :347")
lam("go-lambda-al2023-go126-mod123-godebug-env", A, "godebug",
    "Go 1.26 go 1.23 + GODEBUG=tlsmlkem=1,tlssecpmlkem=1 (template.yaml / lambda.tf value): PQ incl. SecP hybrids",
    pq(OFF_126), "probe-1.26-go1.23", env={"GODEBUG": "tlsmlkem=1,tlssecpmlkem=1"}, doc=DOC + ":481, :857")
lam("go-lambda-al2023-go126-mod123-godebug-gomod", A, "godebug",
    "Go 1.26 go 1.23 + go.mod godebug (tlsmlkem=1, tlssecpmlkem=1) block (configs/go/go.variant2.mod)", pq(OFF_126),
    "probe-1.26-go1.23-godebug", doc=DOC + ":63, :617-626")
lam("go-lambda-al2-go124-mod123-godebug-gomod", "provided.al2", "godebug",
    "Go 1.24 go 1.23 + go.mod 'godebug tlsmlkem=1' (tlssecpmlkem unknown to 1.24: build fails, see build log)", pq(OFF_124),
    "probe-1.24-go1.23-godebug", doc=DOC + ":63, :628")
lam("go-lambda-al2023-go127-mod123-directive", A, "godebug",
    "Go 1.27 go 1.23 + //go:debug tlsmlkem=1 above package main: X25519MLKEM768 only (tlssecpmlkem stays 0)",
    pq(OFF_124), "probe-1.27-go1.23-directive", doc=DOC + ":63")
lam("go-lambda-al2023-go127-tlsmlkem0", A, "godebug", "Go 1.27 + GODEBUG=tlsmlkem=0 at run time: PQ off", classical(OFF_CLASSIC),
    "probe-1.27", env={"GODEBUG": "tlsmlkem=0"}, doc=DOC + ":65, :346")
lam("go-lambda-al2-go124-tlsmlkem0", "provided.al2", "godebug", "Go 1.24 + GODEBUG=tlsmlkem=0: PQ off", classical(OFF_CLASSIC),
    "probe-1.24", env={"GODEBUG": "tlsmlkem=0"}, doc=DOC + ":65, :346")
lam("go-lambda-al2023-go126-tlssecpmlkem0", A, "godebug", "Go 1.26 + GODEBUG=tlssecpmlkem=0: X25519MLKEM768 only",
    pq(OFF_124), "probe-1.26", env={"GODEBUG": "tlssecpmlkem=0"}, doc=DOC + ":521")
lam("go-lambda-al2023-go126-rollback", A, "godebug", "Rollback: GODEBUG=tlsmlkem=0,tlssecpmlkem=0 on a PQ build -> classical",
    classical(OFF_CLASSIC), "probe-1.26", env={"GODEBUG": "tlsmlkem=0,tlssecpmlkem=0"}, doc=DOC + ":467, :583")

# --- F. Explicit TLS settings (tab lines 339-348, 49, 67)
lam("go-lambda-al2023-go126-curves-classical", A, "settings", "CurvePreferences {X25519, P256}: classical, PQ-only server fails",
    override(classical(["X25519", "CurveP256"]), tls12=dict(CLASSICAL["tls12"], group="X25519")), "probe-1.26",
    env={"PQC_GO_CURVES": "classical"}, doc=DOC + ":341")
lam("go-lambda-al2023-go126-curves-hybrid", A, "settings", "CurvePreferences {X25519MLKEM768, X25519, P256}: PQ",
    pq(["X25519MLKEM768", "X25519", "CurveP256"]), "probe-1.26", env={"PQC_GO_CURVES": "hybrid"}, doc=DOC + ":342")
lam("go-lambda-al2023-go126-curves-hybrid-tlsmlkem0", A, "settings",
    "Go 1.26: explicit hybrid list + GODEBUG=tlsmlkem=0 -> hybrid dropped from the explicit list",
    classical(["X25519", "CurveP256"]), "probe-1.26", env={"PQC_GO_CURVES": "hybrid", "GODEBUG": "tlsmlkem=0"},
    doc=DOC + ":67, :342, :569")
lam("go-lambda-al2023-go127-curves-hybrid-tlsmlkem0", A, "settings",
    "Go 1.27: explicit hybrid list beats GODEBUG=tlsmlkem=0", pq(["X25519MLKEM768", "X25519", "CurveP256"]),
    "probe-1.27", env={"PQC_GO_CURVES": "hybrid", "GODEBUG": "tlsmlkem=0"}, doc=DOC + ":17, :67")
lam("go-lambda-al2023-go126-max12", A, "settings", "MaxVersion TLS 1.2: never PQ, PQ-only server: protocol version",
    override(TLS12_ONLY, pqonly={"ok": False, "error_match": "protocol version"}), "probe-1.26",
    env={"PQC_GO_VERSION": "max12"}, doc=DOC + ":343")
lam("go-lambda-al2023-go126-min13", A, "settings", "MinVersion TLS 1.3: PQ (TLS 1.2-only server then refused)",
    override(pq(OFF_126), tls12={"ok": False, "error_match": "protocol version"}), "probe-1.26",
    env={"PQC_GO_VERSION": "min13"}, doc=DOC + ":344")
lam("go-lambda-al2023-go126-ciphers12", A, "settings", "CipherSuites (TLS 1.2 list): doesn't touch TLS 1.3, PQ",
    pq(OFF_126), "probe-1.26", env={"PQC_GO_CIPHERS": "tls12"}, doc=DOC + ":345")
lam("go-lambda-al2023-go123-curve4588", A, "settings",
    "Go 1.23 with X25519MLKEM768 listed by number (4588): every handshake fails, even to classical",
    all_fail("CurvePreferences includes unsupported curve"), "probe-1.23", env={"PQC_GO_CURVES": "hybrid"}, doc=DOC + ":348")
lam("go-lambda-al2023-go127-mlkem1024", A, "settings",
    "Go 1.27: pure MLKEM1024 only when listed (offered), hybrid still negotiated",
    pq(["X25519MLKEM768", "MLKEM1024", "X25519"]), "probe-1.27", env={"PQC_GO_CURVES": "mlkem1024"}, doc=DOC + ":49")

# --- D. custom CA trust, E. client certificates, I. pinning (tab lines 237-252, 319-323, 438)
CA = "/var/task/certs/ca.crt"
lam("go-lambda-al2023-go126-trust-ssl-cert-file", A, "trust", "RootCAs nil + SSL_CERT_FILE=<private CA>: PQ",
    pq(OFF_126), "probe-1.26", env={"PQC_GO_TRUST": "env", "SSL_CERT_FILE": CA}, doc=DOC + ":241")
lam("go-lambda-al2-go127-trust-ssl-cert-dir", "provided.al2", "trust", "RootCAs nil + SSL_CERT_DIR=<dir with CA>: PQ",
    pq(OFF_126), "probe-1.27", env={"PQC_GO_TRUST": "env", "SSL_CERT_DIR": "/var/task/certs"}, doc=DOC + ":242")
lam("go-lambda-al2023-go126-trust-none", A, "trust", "RootCAs nil, no SSL_CERT_*: private CA unknown (negative)",
    all_fail("unknown authority"), "probe-1.26", env={"PQC_GO_TRUST": "env"}, doc=DOC + ":243")
lam("go-lambda-al2023-go126-trust-system-plus-ca", A, "trust", "SystemCertPool() + AppendCertsFromPEM(ca): PQ",
    pq(OFF_126), "probe-1.26", env={"PQC_GO_TRUST": "system+ca"}, doc=DOC + ":244")
lam("go-lambda-al2023-go126-trust-empty", A, "trust", "RootCAs = empty pool (negative)", all_fail("unknown authority"),
    "probe-1.26", env={"PQC_GO_TRUST": "empty"}, doc=DOC + ":246")
lam("go-lambda-al2023-go124-trust-ssl-cert-file", A, "trust", "Go 1.24: SSL_CERT_FILE trust, PQ", pq(OFF_124),
    "probe-1.24", env={"PQC_GO_TRUST": "env", "SSL_CERT_FILE": CA}, doc=DOC + ":237")
lam("go-lambda-al2023-go123-trust-ssl-cert-file", A, "trust", "Go 1.23: same trust, classical (trust was never the cause)",
    classical(OFF_123), "probe-1.23", env={"PQC_GO_TRUST": "env", "SSL_CERT_FILE": CA}, doc=DOC + ":311")
lam("go-lambda-al2023-go126-clientcert-callback", A, "mtls", "GetClientCertificate callback: PQ, mTLS OK", pq(OFF_126),
    "probe-1.26", env={"PQC_GO_CLIENTCERT": "callback"}, doc=DOC + ":321")
_certs = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".work", "certs")
lam("go-lambda-al2023-go126-clientcert-env-pem", A, "mtls",
    "Client cert + key PEM injected as env vars (tls.X509KeyPair(os.Getenv)): PQ", pq(OFF_126), "probe-1.26",
    env={"PQC_GO_CLIENTCERT": "env-pem", "PQC_GO_CERT_PEM": open(os.path.join(_certs, "client.crt")).read(),
         "PQC_GO_KEY_PEM": open(os.path.join(_certs, "client.key")).read()}, doc=DOC + ":157, :180")
lam("go-lambda-al2023-go126-clientcert-none", A, "mtls", "No client cert (negative): mTLS server refuses, rest PQ",
    override(pq(OFF_126), mtls={"ok": False, "error_match": "certificate required"}), "probe-1.26",
    env={"PQC_GO_CLIENTCERT": "none"}, doc=DOC + ":323, :579")
lam("go-lambda-al2-go123-clientcert-callback", "provided.al2", "mtls", "Go 1.23 GetClientCertificate: mTLS OK, classical",
    classical(OFF_123), "probe-1.23", env={"PQC_GO_CLIENTCERT": "callback"}, doc=DOC + ":319")
lam("go-lambda-al2023-go126-p12-sslmate", A, "mtls",
    "Client cert from OpenSSL 3 default PKCS#12 via sslmate go-pkcs12 DecodeChain: PQ", pq(OFF_126), "probe-1.26-extras",
    env={"PQC_GO_CLIENTCERT": "p12-sslmate"}, doc=DOC + ":154")
lam("go-lambda-al2023-go126-p12-xcrypto", A, "mtls",
    "Same PKCS#12 via frozen x/crypto/pkcs12 Decode: load fails (unknown digest algorithm), mTLS target fails",
    override(pq(OFF_126), mtls={"ok": False, "error_match": r"unknown digest algorithm: 2\.16\.840\.1\.101\.3\.4\.2\.1"}),
    "probe-1.26-extras", env={"PQC_GO_CLIENTCERT": "p12-xcrypto"}, doc=DOC + ":156, :573")
lam("go-lambda-al2023-go126-pin-ca", A, "pinning", "VerifyConnection SPKI pin (CA key): passes over X25519MLKEM768",
    pq(OFF_126), "probe-1.26", env={"PQC_GO_PIN": "ca"}, doc=DOC + ":438")
lam("go-lambda-al2023-go126-pin-wrong", A, "pinning", "Wrong SPKI pin: fails with the app's error (negative)",
    all_fail("SPKI pin mismatch"), "probe-1.26", env={"PQC_GO_PIN": "wrong"}, doc=DOC + ":438")

# --- G. FIPS mode (tab lines 367-377; table 369-375)
F_P256 = ("Fixed in the doc on 2026-11-14; kept as a regression check. "
    "Tab says 'P-256 only' (%s:371, :374); the client offers P-256, P-384 and P-521 (crypto/tls "
          "defaultCurvePreferencesFIPS / allowedCurvePreferencesFIPS) and the server picked P-256. No PQ, no X25519 as claimed."
          % DOC)
F_PLUS = ("Fixed in the doc on 2026-11-14; kept as a regression check. "
    "Tab lists the FIPS groups as hybrids + 'P-256' (%s:17, :371); the client also offers P-384 and P-521. PQ as claimed."
          % DOC)
lam("go-lambda-al2023-go124-fips140-on", A, "fips", "Go 1.24 GODEBUG=fips140=on: no PQ, no X25519", p256(OFF_FIPS124),
    "probe-1.24", env={"GODEBUG": "fips140=on"}, doc=DOC + ":371", finding=F_P256)
lam("go-lambda-al2023-go124-fips140-only", A, "fips", "Go 1.24 GODEBUG=fips140=only: same as on", p256(OFF_FIPS124),
    "probe-1.24", env={"GODEBUG": "fips140=only"}, doc=DOC + ":372", finding=F_P256)
lam("go-lambda-al2-go124-gofips140", "provided.al2", "fips", "Go 1.24 built GOFIPS140=latest: no PQ", p256(OFF_FIPS124),
    "probe-1.24-fips", doc=DOC + ":363, :523", finding=F_P256)
lam("go-lambda-al2023-go125-fips140-on", A, "fips", "Go 1.25 fips140=on: X25519MLKEM768 + NIST curves",
    override(pq(OFF_FIPS125), tls12=dict(PQ["tls12"], group="CurveP256")), "probe-1.25", env={"GODEBUG": "fips140=on"},
    doc=DOC + ":19, :371", finding=F_PLUS)
lam("go-lambda-al2023-go125-fips140-only", A, "fips", "Go 1.25 fips140=only: every handshake fails",
    all_fail("use of X25519 is not allowed in FIPS 140-only mode"), "probe-1.25", env={"GODEBUG": "fips140=only"},
    doc=DOC + ":19, :372")
for v in ("1.26", "1.27"):
    tag = v.replace(".", "")
    for m in ("on", "only"):
        lam("go-lambda-al2023-go%s-fips140-%s" % (tag, m), A, "fips", "Go %s fips140=%s: three hybrids + NIST curves" % (v, m),
            override(pq(OFF_FIPS126), tls12=dict(PQ["tls12"], group="CurveP256")), "probe-" + v,
            env={"GODEBUG": "fips140=" + m}, doc=DOC + ":17-18, :371-372", finding=F_PLUS)
lam("go-lambda-al2023-go126-gofips140-v1260", A, "fips", "Go 1.26 GOFIPS140=v1.26.0 build (Dockerfile.fips): PQ",
    override(pq(OFF_FIPS126), tls12=dict(PQ["tls12"], group="CurveP256")), "probe-1.26-fips-v1.26.0",
    doc=DOC + ":365, :489, :831", finding=F_PLUS)
lam("go-lambda-al2-go126-gofips140-v100", "provided.al2", "fips",
    "Go 1.26 GOFIPS140=v1.0.0 (CMVP #5247 module): group policy follows the toolchain, SecP hybrids offered",
    override(pq(OFF_FIPS126), tls12=dict(PQ["tls12"], group="CurveP256")), "probe-1.26-fips-v1.0.0", doc=DOC + ":377",
    finding=F_PLUS)
lam("go-lambda-al2023-go127-gofips140", A, "fips", "Go 1.27 GOFIPS140=latest build: PQ",
    override(pq(OFF_FIPS126), tls12=dict(PQ["tls12"], group="CurveP256")), "probe-1.27-fips", doc=DOC + ":17",
    finding=F_PLUS)
lam("go-lambda-al2023-go126-boring", A, "fips", "Go 1.26 GOEXPERIMENT=boringcrypto, no fipsonly: same as non-FIPS (PQ)",
    pq(OFF_126), "probe-1.26-boring", doc=DOC + ":373")
for v in ("1.25", "1.26", "1.27"):
    lam("go-lambda-al2023-go%s-boring-fipsonly" % v.replace(".", ""), A, "fips",
        "Go %s boringcrypto + crypto/tls/fipsonly: no PQ" % v, p256(OFF_FIPS124), "probe-%s-boring-fipsonly" % v,
        doc=DOC + ":374", finding=F_P256)

# --- H. AWS SDK for Go v2 transport (tab lines 93-94, 387, 405-415)
lam("go-lambda-al2023-go126-awssdk", A, "library", "aws-sdk-go-v2 v1.48.0 BuildableClient (CA + client cert): PQ outside FIPS",
    pq(OFF_126), "probe-1.26-extras", env={"PQC_GO_STACK": "awssdk"}, doc=DOC + ":93, :387")
lam("go-lambda-al2023-go126-awssdk-fips", A, "library",
    "aws-sdk-go-v2 in FIPS mode (fips140=on): SDK forces P-256/P-384/P-521 -> no PQ", p256(P_CURVES), "probe-1.26-extras",
    env={"PQC_GO_STACK": "awssdk", "GODEBUG": "fips140=on"}, doc=DOC + ":94, :405")
lam("go-lambda-al2023-go126-awssdk-fips-fix", A, "library",
    "aws-sdk-go-v2 FIPS + the tab's WithTransportOptions fix (hybrids put back): PQ",
    override(pq(["X25519MLKEM768", "SecP256r1MLKEM768", "CurveP256", "CurveP384"]), tls12=dict(PQ["tls12"], group="CurveP256")),
    "probe-1.26-extras", env={"PQC_GO_STACK": "awssdk-fipsfix", "GODEBUG": "fips140=on"}, doc=DOC + ":405-415, :657-665")
lam("go-lambda-al2023-go127-awssdk-tlsmlkem0", A, "library", "aws-sdk-go-v2 + GODEBUG=tlsmlkem=0: fails to PQ-only",
    classical(OFF_CLASSIC), "probe-1.27-extras", env={"PQC_GO_STACK": "awssdk", "GODEBUG": "tlsmlkem=0"}, doc=DOC + ":387")

# --- Lambda container images (configs/go/Dockerfile.lambda, builder golang:1.26 / golang:1.23)
for tag, exp, t in (("go126", pq(OFF_126), "golang:1.26 builder, go 1.26: PQ"),
                    ("go123", classical(OFF_123), "golang:1.23 builder: classical")):
    cases.append({"id": "go-lambda-image-%s" % tag, "compute": "lambda", "mode": "image",
                  "title": "Lambda container image (configs/go/Dockerfile.lambda -> provided:al2023), " + t,
                  "doc": DOC + ":54, :483, :809-822", "expect": exp,
                  "lambda": {"image": "pqc-go-lambda:" + tag, "runtime": "image"}})


# --- ECS (Fargate, EC2 launch type): the same binaries in images on different bases
def ecs(id, compute, image, cmd, mode, title, expect, env=None, doc=DOC + ":13, :55", finding=None):
    c = {"id": id, "compute": compute, "mode": mode, "title": title, "doc": doc, "expect": expect,
         "runtime_label": "%s %s" % (image, cmd[-1].split("/")[-1] if cmd else "(ENTRYPOINT)"),
         "ecs": {"image": image, "command": cmd, "env": env or {}}}
    if finding:
        c["finding"] = finding
    cases.append(c)


def binp(name):
    return "/app/bin/" + name


ECS_BASES = {"al2023": "AL2023 2023.12.20261109", "scratch": "scratch (no OS, no CA bundle)",
             "distroless": "distroless/static-debian12:nonroot", "golang": "golang:1.27 (Debian 13, OpenSSL 3.5 PQ by default)"}
for base, desc in ECS_BASES.items():
    for v in ("1.23", "1.24", "1.27"):
        exp = classical(BASE[v]) if v == "1.23" else pq(BASE[v])
        ecs("go-fargate-%s-go%s" % (base, v.replace(".", "")), "ecs-fargate", "pqc-go:" + base, [binp("probe-" + v)],
            "baseline", "Fargate %s, Go %s binary" % (desc, v), exp)
for v in ("1.23", "1.27"):
    exp = classical(BASE[v]) if v == "1.23" else pq(BASE[v])
    ecs("go-fargate-al2023-policy-go%s" % v.replace(".", ""), "ecs-fargate", "pqc-go:al2023-policy", [binp("probe-" + v)],
        "crypto-policy", "Fargate AL2023 with update-crypto-policies DEFAULT:PQ, Go %s: policy changes nothing" % v, exp, doc=DOC + ":7")
    ecs("go-fargate-al2-go%s" % v.replace(".", ""), "ecs-fargate", "pqc-go:al2", [binp("probe-" + v)], "baseline",
        "Fargate Amazon Linux 2 (OpenSSL 1.0.2) base, Go %s: OS TLS library plays no part" % v, exp, doc=DOC + ":7")
ecs("go-fargate-al2023-go126-mod123-taskdef-godebug", "ecs-fargate", "pqc-go:al2023", [binp("probe-1.26-go1.23")], "godebug",
    "Fargate Go 1.26 go 1.23 + task-def GODEBUG=tlsmlkem=1,tlssecpmlkem=1 (configs/go/taskdef.json)", pq(OFF_126),
    env={"GODEBUG": "tlsmlkem=1,tlssecpmlkem=1"}, doc=DOC + ":485, :931")
ecs("go-fargate-scratch-go127-ssl-cert-file", "ecs-fargate", "pqc-go:scratch", [binp("probe-1.27")], "trust",
    "Fargate scratch: SSL_CERT_FILE with the private CA, RootCAs nil: PQ", pq(OFF_126),
    env={"PQC_GO_TRUST": "env", "SSL_CERT_FILE": "/app/bin/certs/ca.crt"}, doc=DOC + ":261, :292")
ecs("go-fargate-scratch-go127-no-bundle", "ecs-fargate", "pqc-go:scratch", [binp("probe-1.27")], "trust",
    "Fargate scratch, RootCAs nil and no bundle: unknown authority (negative)", all_fail("unknown authority"),
    env={"PQC_GO_TRUST": "env"}, doc=DOC + ":292")
ecs("go-fargate-doc-dockerfile", "ecs-fargate", "pqc-go:doc-dockerfile", [], "image",
    "Fargate image from configs/go/Dockerfile (golang:1.26 -> distroless nonroot): PQ", pq(OFF_126), doc=DOC + ":485, :788-807")
ecs("go-fargate-doc-dockerfile-fips", "ecs-fargate", "pqc-go:doc-dockerfile-fips", [], "fips",
    "Fargate image from configs/go/Dockerfile.fips (GOFIPS140=v1.26.0): PQ in FIPS mode",
    override(pq(OFF_FIPS126), tls12=dict(PQ["tls12"], group="CurveP256")), doc=DOC + ":489, :824-836", finding=F_PLUS)
ecs("go-fargate-al2023-go126-boring-fips140-on", "ecs-fargate", "pqc-go:al2023",
    [binp("probe-1.27"), "-wrap", binp("probe-1.26-boring")], "fips",
    "boringcrypto build + GODEBUG=fips140=on: panics at start (probe -wrap records the crash)",
    all_fail("FIPS 140-3 mode is incompatible with GOEXPERIMENT=boringcrypto"), env={"GODEBUG": "fips140=on"}, doc=DOC + ":375, :830")
for base, v in (("al2023", "1.23"), ("al2023", "1.27"), ("scratch", "1.27"), ("distroless", "1.24"), ("golang", "1.26")):
    exp = classical(BASE[v]) if v == "1.23" else pq(BASE[v])
    ecs("go-ecsec2-%s-go%s" % (base, v.replace(".", "")), "ecs-ec2", "pqc-go:" + base, [binp("probe-" + v)], "baseline",
        "ECS EC2 launch type, %s, Go %s binary" % (ECS_BASES[base], v), exp)


# --- EC2 golden AMIs: prebuilt binaries in /opt/pqc/go/bin, plus one built on the AMI with the distro golang package
def ec2(id, ami, run, mode, title, expect, setup=(), env=None, doc=DOC + ":56, :487", finding=None):
    c = {"id": id, "compute": "ec2", "mode": mode, "title": title, "doc": doc, "expect": expect,
         "runtime_label": "%s %s" % (ami, run.split()[0].split("/")[-1]),
         "ec2": {"ami": ami, "run": run, "setup": list(setup), "env": env or {}}}
    if finding:
        c["finding"] = finding
    cases.append(c)


EB = "/opt/pqc/go/bin/"
for v in ("1.23", "1.24", "1.25", "1.26", "1.27"):
    exp = classical(BASE[v]) if v == "1.23" else pq(BASE[v])
    ec2("go-ec2-al2023-go%s" % v.replace(".", ""), "pqc-al2023", EB + "probe-" + v, "baseline",
        "EC2 AL2023, prebuilt Go %s binary, default crypto policy" % v, exp)
for v in ("1.23", "1.27"):
    exp = classical(BASE[v]) if v == "1.23" else pq(BASE[v])
    ec2("go-ec2-al2023-go%s-host-policy" % v.replace(".", ""), "pqc-al2023", EB + "probe-" + v, "crypto-policy",
        "EC2 AL2023 host update-crypto-policies --set DEFAULT:PQ, Go %s: no change (Go ignores the policy)" % v, exp,
        setup=["update-crypto-policies --set DEFAULT:PQ"], doc=DOC + ":7")
ec2("go-ec2-al2023-distro-golang", "pqc-al2023", EB + "probe-distro", "distro-toolchain",
    "EC2 AL2023: probe built on the AMI with dnf golang (1.26.10), go 1.26: PQ incl. SecP hybrids", pq(OFF_126),
    doc=DOC + ":7 (distro toolchain)")
ec2("go-ec2-al2023-go124-mod123-systemd-godebug", "pqc-al2023", EB + "probe-1.24-go1.23", "godebug",
    "EC2 AL2023 Go 1.24 go 1.23 + Environment=GODEBUG=tlsmlkem=1 (systemd unit equivalent): PQ", pq(OFF_124),
    env={"GODEBUG": "tlsmlkem=1"}, doc=DOC + ":487, :1015")
ec2("go-ec2-al2023-go127-fips140-on", "pqc-al2023", EB + "probe-1.27", "fips", "EC2 AL2023 Go 1.27 fips140=on: PQ",
    override(pq(OFF_FIPS126), tls12=dict(PQ["tls12"], group="CurveP256")), env={"GODEBUG": "fips140=on"}, doc=DOC + ":17",
    finding=F_PLUS)
for v in ("1.23", "1.26", "1.27"):
    exp = classical(BASE[v]) if v == "1.23" else pq(BASE[v])
    ec2("go-ec2-al2-go%s" % v.replace(".", ""), "pqc-al2", EB + "probe-" + v, "baseline",
        "EC2 Amazon Linux 2 (OpenSSL 1.0.2, no TLS 1.3 in the OS), prebuilt Go %s binary" % v, exp, doc=DOC + ":7, :56")
ec2("go-ec2-al2-distro-golang", "pqc-al2", EB + "probe-distro", "distro-toolchain",
    "EC2 Amazon Linux 2: probe built on the AMI with yum golang (1.26.10): PQ", pq(OFF_126), doc=DOC + ":7 (distro toolchain)")

write("go", cases)
