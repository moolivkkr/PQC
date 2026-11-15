"""Node.js cases. Expectations are the Node.js tab's claims (src/05-nodejs.md); a FAIL means the doc or the fix is wrong.
Where a run showed the tab to be wrong, the expectation records what happens and `finding` names the doc line."""
from lib import CLASSICAL, PQ, TLS12_ONLY, ALL, override, write

DOC = "src/05-nodejs.md"
EGRESS_ENV = {  # pq-egress extension: routes to the observer listeners, test CA, client cert for the mtls route
    "PQC_EGRESS_PORT": "2779", "PQ_EGRESS_PORT": "2779",
    "PQ_EGRESS_ROUTES": "hybrid=pq-observer:8443,pqonly=pq-observer:8444,mtls=pq-observer:8445;mtls,"
                        "eccert=pq-observer:8446,tls12=pq-observer:8447",
    "PQ_EGRESS_CA": "/var/task/certs/ca.crt", "PQ_EGRESS_CERT": "/var/task/certs/client.crt",
    "PQ_EGRESS_KEY": "/var/task/certs/client.key"}
WRAP = {"AWS_LAMBDA_EXEC_WRAPPER": "/opt/pq-tls/wrapper"}
BUNDLED = {"OPENSSL_CONF": "/var/task/pq-tls/openssl-pq-node.cnf"}
NEC = {"NODE_EXTRA_CA_CERTS": "/var/task/certs/ca.crt", "PQC_NODE_TRUST": "env"}
VERIFY_FAIL = {"ok": False, "error_match": "UNABLE_TO_VERIFY_LEAF_SIGNATURE|SELF_SIGNED_CERT_IN_CHAIN|UNABLE_TO_GET_ISSUER"}
LEGACY_PFX_FAIL = {"ok": False, "error_match": "Unsupported PKCS12 PFX data"}
NO_MTLS = ["hybrid", "pqonly", "eccert", "tls12"]
cases = []

D_LAMBDA = DOC + " Lambda zip (nodejs22.x, nodejs24.x) (l.350-383)"


def lam(id, rt, mode, title, expect, zip="probe.zip", layers=(), env=None, doc=D_LAMBDA, targets=None, finding=None):
    c = {"id": id, "compute": "lambda", "mode": mode, "title": title, "doc": doc, "expect": expect,
         "lambda": {"runtime": rt, "handler": "index.handler", "zip": "node/" + zip, "layers": list(layers),
                    "env": env or {}}}
    if targets:
        c["targets"] = targets
    if finding:
        c["finding"] = finding
    cases.append(c)


OLD = ["nodejs18.x", "nodejs20.x"]      # Lambda: OpenSSL < 3.5, no ML-KEM in the library at all
CUR = ["nodejs22.x", "nodejs24.x"]      # Lambda: bundled OpenSSL 3.5.9, bootstrap OPENSSL_CONF omits ML-KEM
for rt in OLD + CUR:
    v = rt.replace("nodejs", "n").replace(".x", "")
    fixable = rt in CUR
    want = PQ if fixable else CLASSICAL
    why = "" if fixable else " (no fix on 18/20: library has no ML-KEM; tab l.38, l.383)"
    lam("node-lambda-%s-baseline" % v, rt, "baseline",
        "%s zip, no change: bootstrap's classical file / old OpenSSL -> classical, PQ-only server fails" % rt, CLASSICAL,
        doc=DOC + " version table l.21-25, Lambda zip l.352",
        finding=None if fixable else (
            "Outcome as documented (classical, no fix), but the library differs: on Lambda %s process.versions.openssl is "
            "%s, not the 'Bundled OpenSSL 3.0.x' of src/05-nodejs.md l.25 (that is node:20-slim's 3.0.19). Neither has "
            "ML-KEM, and the bundled openssl-pq-node.cnf / --openssl-config / layer leave it classical without breaking "
            "startup (cases node-lambda-%s-bundled-*)." % (rt, {"nodejs18.x": "3.1.8", "nodejs20.x": "3.2.6"}[rt], v)))
    lam("node-lambda-%s-bundled-conf" % v, rt, "bundled",
        "%s + pq-tls/openssl-pq-node.cnf in package + OPENSSL_CONF%s" % (rt, why), want,
        zip="probe-bundled.zip", env=BUNDLED, doc=DOC + " Lambda zip l.356" if fixable else DOC + " l.383")
    lam("node-lambda-%s-bundled-flag" % v, rt, "bundled",
        "%s + NODE_OPTIONS=--openssl-config=/var/task/pq-tls/openssl-pq-node.cnf%s" % (rt, why), want,
        zip="probe-bundled.zip", env={"NODE_OPTIONS": "--openssl-config=/var/task/pq-tls/openssl-pq-node.cnf"},
        doc=DOC + " Lambda zip l.357" if fixable else DOC + " l.383")
    lam("node-lambda-%s-layer" % v, rt, "layer",
        "%s + pq-tls layer + AWS_LAMBDA_EXEC_WRAPPER%s" % (rt, " (wrapper: no change on 18/20)" if not fixable else ""),
        want, layers=["pq-tls"], env=WRAP, doc=DOC + " l.383")
    lam("node-lambda-%s-extension" % v, rt, "extension",
        "%s + pq-egress extension layer: extension originates PQ TLS (works on 18/20 too)" % rt, PQ,
        layers=["pq-egress"], env=EGRESS_ENV, doc="e2e/lambda/extension/pq-egress (extension option)")
    lam("node-lambda-%s-combined" % v, rt, "extension",
        "%s + ONE combined layer (wrapper + extension), extension mode" % rt, PQ,
        layers=["pq-tls-combined"], env=dict(EGRESS_ENV, **WRAP), doc="e2e/lambda/extension/pq-egress + " + DOC + " l.383")

# Other documented Lambda methods
for v, rt in (("n22", "nodejs22.x"), ("n24", "nodejs24.x")):
    lam("node-lambda-%s-devnull" % v, rt, "bundled", "%s OPENSSL_CONF=/dev/null (AWS's opt-in): OpenSSL built-in defaults" % rt,
        PQ, env={"OPENSSL_CONF": "/dev/null"}, doc=DOC + " Lambda zip l.358")
lam("node-lambda-n24-code-ecdh", "nodejs24.x", "code",
    "nodejs24.x, AWS's file, app code sets tls.DEFAULT_ECDH_CURVE PQ-first (NODE_OPTIONS=--require preload)", PQ,
    zip="probe-extra.zip", env={"NODE_OPTIONS": "--require /var/task/preload/ecdh-pq.js"}, doc=DOC + " Lambda zip l.359, l.306")
lam("node-lambda-n24-combined-wrapper", "nodejs24.x", "layer", "nodejs24.x + ONE combined layer, wrapper path only", PQ,
    layers=["pq-tls-combined"], env=WRAP)

# Existing configuration in the function
lam("node-lambda-n24-layer-ownconf", "nodejs24.x", "layer",
    "function already sets OPENSSL_CONF (its own classical file): wrapper leaves it alone -> stays classical", CLASSICAL,
    zip="probe-extra.zip", layers=["pq-tls"], env=dict(WRAP, OPENSSL_CONF="/var/task/conf/app-openssl.cnf"),
    doc=DOC + " l.383, l.450")
lam("node-lambda-n22-layer-chain", "nodejs22.x", "layer",
    "existing exec wrapper chained with PQ_TLS_NEXT_WRAPPER: both run, PQ on", PQ, zip="probe-extra.zip",
    layers=["pq-tls"], env=dict(WRAP, PQ_TLS_NEXT_WRAPPER="/var/task/app-wrapper"), doc="kit/java-v2/pq-tls-layer/wrapper")
lam("node-lambda-n24-layer-disabled", "nodejs24.x", "layer",
    "rollback switch PQ_TLS_DISABLE=1 with layer still attached: back to classical", CLASSICAL,
    layers=["pq-tls"], env=dict(WRAP, PQ_TLS_DISABLE="1"), doc=DOC + " rollback l.463")
lam("node-lambda-n24-code-ecdh-classical", "nodejs24.x", "code",
    "PITFALL: PQ file set, but app code sets tls.DEFAULT_ECDH_CURVE='X25519:P-256' -> classical, PQ-only fails", CLASSICAL,
    zip="probe-extra.zip", env=dict(BUNDLED, NODE_OPTIONS="--require /var/task/preload/ecdh-classical.js"),
    doc=DOC + " case F l.282, l.306")
lam("node-lambda-n24-tls-max-12", "nodejs24.x", "code",
    "PITFALL: PQ file set + NODE_OPTIONS=--tls-max-v1.2 -> no TLS 1.3, no ML-KEM, PQ-only server: protocol version alert",
    override(TLS12_ONLY, pqonly={"ok": False, "error_match": "protocol version|alert"}),
    zip="probe-bundled.zip", env=dict(BUNDLED, NODE_OPTIONS="--tls-max-v1.2"), doc=DOC + " case F l.288, l.448")

# Case D: trust via NODE_EXTRA_CA_CERTS (probe passes no `ca` option)
for v, rt in (("n22", "nodejs22.x"), ("n24", "nodejs24.x")):
    lam("node-lambda-%s-nec-bundled" % v, rt, "bundled",
        "%s PQ file + NODE_EXTRA_CA_CERTS (no ca: in code): PQ, verified, mTLS works" % rt, PQ,
        zip="probe-bundled.zip", env=dict(BUNDLED, **NEC), doc=DOC + " case D l.206, l.220")
lam("node-lambda-n24-nec-aws", "nodejs24.x", "baseline", "nodejs24.x AWS default config + NODE_EXTRA_CA_CERTS: classical",
    CLASSICAL, env=NEC, doc=DOC + " case D l.221")
lam("node-lambda-n24-nec-none", "nodejs24.x", "bundled",
    "NEGATIVE: PQ file, no ca: and no NODE_EXTRA_CA_CERTS -> every target fails verification",
    {t: VERIFY_FAIL for t in ALL}, zip="probe-bundled.zip", env=dict(BUNDLED, PQC_NODE_TRUST="env"), doc=DOC + " case D l.222")
lam("node-lambda-n22-nec-layer", "nodejs22.x", "layer", "nodejs22.x pq-tls layer + NODE_EXTRA_CA_CERTS: PQ, verified", PQ,
    layers=["pq-tls"], env=dict(WRAP, **NEC), doc=DOC + " case D l.199, l.383")
lam("node-lambda-n24-fetch-nec", "nodejs24.x", "bundled",
    "nodejs24.x global fetch (bundled undici) + PQ file + NODE_EXTRA_CA_CERTS: fetch inherits Node's defaults", PQ,
    zip="probe-bundled.zip", env=dict(BUNDLED, PQC_NODE_STACK="fetch", **NEC), targets=NO_MTLS, doc=DOC + " case A l.63, case D l.206")

# Case C/E: PFX client certificates
lam("node-lambda-n24-pfx", "nodejs24.x", "bundled", "nodejs24.x PQ file, mTLS with pfx: client.p12 (AES-256/PBKDF2)", PQ,
    zip="probe-bundled.zip", env=dict(BUNDLED, PQC_NODE_CLIENT_CERT="pfx"), doc=DOC + " case E l.250")
for v, rt, extra in (("n24", "nodejs24.x", BUNDLED), ("n22", "nodejs22.x", BUNDLED), ("n20", "nodejs20.x", {})):
    base = PQ if extra else CLASSICAL
    lam("node-lambda-%s-pfx-legacy" % v, rt, "bundled" if extra else "baseline",
        "%s legacy RC2-40/3DES PFX for mTLS: Unsupported PKCS12 PFX data (not PQ-related); other targets unaffected" % rt,
        override(base, mtls=LEGACY_PFX_FAIL), zip="probe.zip" if not extra else "probe-bundled.zip",
        env=dict(extra, PQC_NODE_CLIENT_CERT="pfx-legacy"), doc=DOC + " case C l.161, l.178, l.456")
lam("node-lambda-n24-pfx-legacy-provider", "nodejs24.x", "bundled",
    "nodejs24.x legacy PFX + --openssl-legacy-provider: Lambda image cannot load the legacy provider -> mTLS still fails",
    override(PQ, mtls=LEGACY_PFX_FAIL), zip="probe-bundled.zip",
    env=dict(BUNDLED, PQC_NODE_CLIENT_CERT="pfx-legacy", NODE_OPTIONS="--openssl-legacy-provider"), doc=DOC + " case C l.178, l.456")

# Lambda container images (PackageType Image) on public.ecr.aws/lambda/nodejs
for v in ("22", "24"):
    for kind, exp in (("baseline", CLASSICAL), ("fixed", PQ)):
        cases.append({"id": "node-lambda-image-n%s-%s" % (v, kind), "compute": "lambda", "mode": "image-" + kind,
                      "title": "Lambda container image nodejs:%s %s" % (v, "(Dockerfile.lambda COPY + ENV OPENSSL_CONF)" if kind == "fixed" else "(no change)"),
                      "doc": DOC + " Lambda container image l.385-387", "expect": exp,
                      "lambda": {"image": "pqc-node-lambda:nodejs%s-%s" % (v, kind), "runtime": "image"}})


def ecs(id, compute, image, cmd, mode, title, expect, env=None, doc=DOC + " Fargate, ECS, EKS l.389-393", targets=None,
        finding=None):
    c = {"id": id, "compute": compute, "mode": mode, "title": title, "doc": doc, "expect": expect,
         "runtime_label": image + " " + cmd[0], "ecs": {"image": image, "command": cmd, "env": env or {}}}
    if targets:
        c["targets"] = targets
    if finding:
        c["finding"] = finding
    cases.append(c)


SYSCONF = {"OPENSSL_CONF": "/etc/app/openssl-pq-node-system.cnf"}
AL2023_N20_FINDING = (
    "AL2023 dnf nodejs20 (20.20.2) links the system OpenSSL 3.5.8, so it negotiates X25519MLKEM768 once the crypto policy "
    "is DEFAULT:PQ or OPENSSL_CONF points at openssl-pq-node-system.cnf, exactly like nodejs22/24. The tab says the opposite: "
    "src/05-nodejs.md l.25 ('20.x ... No / No / No ... Upgrade; no setting adds PQ'), l.38 ('any Node below 22.20 / 24.5: "
    "upgrade ... There is no setting') and l.5 ('anything on Node 20 or older'). l.452 already notes this for Debian 13's "
    "Node 20; the l.26 AL2023 row should cover nodejs20 too, and the rule should be 'check process.versions.openssl'.")
for nv in ("20", "22", "24"):
    node = "node-" + nv
    cur = nv != "20"
    ecs("node-fargate-al2023-n%s-baseline" % nv, "ecs-fargate", "pqc-node:al2023", [node, "/app/index.js"], "baseline",
        "Fargate AL2023 dnf nodejs%s (system OpenSSL 3.5): DEFAULT crypto policy omits ML-KEM" % nv, CLASSICAL,
        doc=DOC + " version table l.26")
    ecs("node-fargate-al2023-n%s-conf" % nv, "ecs-fargate", "pqc-node:al2023", [node, "/app/index.js"], "config",
        "Fargate AL2023 dnf nodejs%s + task-def OPENSSL_CONF=openssl-pq-node-system.cnf" % nv, PQ,
        env=SYSCONF, doc=DOC + (" l.26, l.393" if cur else " l.25, l.38 (Node 20: no setting adds PQ)"),
        finding=None if cur else AL2023_N20_FINDING)
    ecs("node-fargate-al2023-n%s-policy" % nv, "ecs-fargate", "pqc-node:al2023-policy", [node, "/app/index.js"],
        "crypto-policy", "Fargate AL2023 dnf nodejs%s, image with update-crypto-policies --set DEFAULT:PQ (Dockerfile.al2023)" % nv,
        PQ, doc=DOC + (" l.26, l.393" if cur else " l.25, l.38 (Node 20: no setting adds PQ)"),
        finding=None if cur else AL2023_N20_FINDING)
OFFICIAL = (("20-slim", CLASSICAL, "Node 20, bundled OpenSSL 3.0: no ML-KEM", "l.25"),
            ("20-alpine", CLASSICAL, "Node 20, bundled OpenSSL 3.0: no ML-KEM", "l.25"),
            ("22-slim", PQ, "Node 22.20+, bundled OpenSSL 3.5: PQ out of the box", "l.22, l.391"),
            ("22-alpine", PQ, "Node 22.20+, bundled OpenSSL 3.5: PQ out of the box", "l.22, l.391"),
            ("24-slim", PQ, "Node 24.5+, bundled OpenSSL 3.5: PQ out of the box", "l.21, l.391"),
            ("24-alpine", PQ, "Node 24.5+, bundled OpenSSL 3.5: PQ out of the box", "l.21, l.391"),
            ("26-slim", PQ, "Node 26, bundled OpenSSL 3.5.9", "l.23"),
            ("22.19-alpine", CLASSICAL, "22.19 = bundled OpenSSL 3.0: below the floor", "l.24"),
            ("22.20-alpine", PQ, "22.20 = first 22.x with OpenSSL 3.5", "l.22, l.33"),
            ("24.4-alpine", CLASSICAL, "24.4 = bundled OpenSSL 3.0: below the floor", "l.24"),
            ("24.5-alpine", PQ, "24.5 = first 24.x with OpenSSL 3.5 (don't flag 24.5-24.8 as classical)", "l.21, l.33"))
for tag, exp, note, line in OFFICIAL:
    ecs("node-fargate-lib-%s" % tag.replace(".", ""), "ecs-fargate", "pqc-node:lib-" + tag, ["node", "/app/index.js"],
        "baseline", "Fargate node:%s - %s" % (tag, note), exp, doc=DOC + " version table " + line)
ecs("node-fargate-distro-debian13", "ecs-fargate", "pqc-node:distro-debian13", ["node", "/app/index.js"], "baseline",
    "Fargate debian:trixie-slim apt nodejs (20.19.x on system OpenSSL 3.5): 'Node 20 is never PQ' is wrong", PQ,
    doc=DOC + " version table l.27, pitfall l.452")
ecs("node-fargate-distro-alpine322", "ecs-fargate", "pqc-node:distro-alpine322", ["node", "/app/index.js"], "baseline",
    "Fargate alpine:3.22 apk nodejs (system OpenSSL 3.5)", PQ, doc=DOC + " version table l.28")
# Official image + existing settings
ecs("node-fargate-lib-24-slim-nec", "ecs-fargate", "pqc-node:lib-24-slim", ["node", "/app/index.js"], "baseline",
    "Fargate node:24-slim, trust via NODE_EXTRA_CA_CERTS (no ca: in code)", PQ,
    env={"NODE_EXTRA_CA_CERTS": "/app/certs/ca.crt", "PQC_NODE_TRUST": "env"}, doc=DOC + " case D l.206")
ecs("node-fargate-lib-22-slim-fetch", "ecs-fargate", "pqc-node:lib-22-slim", ["node", "/app/index.js"], "baseline",
    "Fargate node:22-slim global fetch + NODE_EXTRA_CA_CERTS", PQ,
    env={"NODE_EXTRA_CA_CERTS": "/app/certs/ca.crt", "PQC_NODE_TRUST": "env", "PQC_NODE_STACK": "fetch"}, targets=NO_MTLS,
    doc=DOC + " case A l.63")
ecs("node-fargate-lib-24-slim-pfx", "ecs-fargate", "pqc-node:lib-24-slim", ["node", "/app/index.js"], "baseline",
    "Fargate node:24-slim mTLS with pfx client.p12", PQ, env={"PQC_NODE_CLIENT_CERT": "pfx"}, doc=DOC + " case E l.250")
ecs("node-fargate-lib-24-slim-pfx-legacy", "ecs-fargate", "pqc-node:lib-24-slim", ["node", "/app/index.js"], "baseline",
    "Fargate node:24-slim legacy RC2/3DES PFX: Unsupported PKCS12 PFX data", override(PQ, mtls=LEGACY_PFX_FAIL),
    env={"PQC_NODE_CLIENT_CERT": "pfx-legacy"}, doc=DOC + " case C l.161")
ecs("node-fargate-lib-24-slim-pfx-legacy-provider", "ecs-fargate", "pqc-node:lib-24-slim", ["node", "/app/index.js"],
    "baseline", "Fargate node:24-slim legacy PFX + --openssl-legacy-provider: loads on official Node", PQ,
    env={"PQC_NODE_CLIENT_CERT": "pfx-legacy", "NODE_OPTIONS": "--openssl-legacy-provider"}, doc=DOC + " case C l.178")
ecs("node-fargate-lib-24-slim-tls-max-12", "ecs-fargate", "pqc-node:lib-24-slim", ["node", "/app/index.js"], "code",
    "PITFALL: node:24-slim with NODE_OPTIONS=--tls-max-v1.2: no TLS 1.3, no ML-KEM",
    override(TLS12_ONLY, pqonly={"ok": False, "error_match": "protocol version|alert"}),
    env={"NODE_OPTIONS": "--tls-max-v1.2"}, doc=DOC + " case F l.288, l.448")
# ECS on EC2 launch type: same images, same results expected (the container's userland decides, not the host)
ecs("node-ecsec2-al2023-n22-baseline", "ecs-ec2", "pqc-node:al2023", ["node-22", "/app/index.js"], "baseline",
    "ECS EC2 launch type, AL2023 dnf nodejs22", CLASSICAL, doc=DOC + " l.26")
ecs("node-ecsec2-al2023-n22-conf", "ecs-ec2", "pqc-node:al2023", ["node-22", "/app/index.js"], "config",
    "ECS EC2 launch type, AL2023 dnf nodejs22 + OPENSSL_CONF system file", PQ, env=SYSCONF, doc=DOC + " l.393")
ecs("node-ecsec2-al2023-n24-policy", "ecs-ec2", "pqc-node:al2023-policy", ["node-24", "/app/index.js"], "crypto-policy",
    "ECS EC2 launch type, AL2023 dnf nodejs24, image crypto policy DEFAULT:PQ", PQ, doc=DOC + " l.393")
ecs("node-ecsec2-lib-24-slim", "ecs-ec2", "pqc-node:lib-24-slim", ["node", "/app/index.js"], "baseline",
    "ECS EC2 launch type, node:24-slim: PQ, host policy not involved", PQ, doc=DOC + " l.391")
ecs("node-ecsec2-lib-20-slim", "ecs-ec2", "pqc-node:lib-20-slim", ["node", "/app/index.js"], "baseline",
    "ECS EC2 launch type, node:20-slim: classical", CLASSICAL, doc=DOC + " l.25")


def ec2(id, ami, run, mode, title, expect, setup=(), env=None, doc=DOC + " EC2 l.395-397", finding=None):
    c = {"id": id, "compute": "ec2", "mode": mode, "title": title, "doc": doc, "expect": expect,
         "runtime_label": "%s %s" % (ami, run.split()[0]),
         "ec2": {"ami": ami, "run": run, "setup": list(setup), "env": env or {}}}
    if finding:
        c["finding"] = finding
    cases.append(c)


P = "/opt/pqc/node/index.js"
for nv in ("20", "22", "24"):
    cur = nv != "20"
    d20 = " l.25, l.38 (Node 20: no setting adds PQ)"
    ec2("node-ec2-al2023-n%s-baseline" % nv, "pqc-al2023", "node-%s %s" % (nv, P), "baseline",
        "EC2 AL2023 2023.12.20261109 dnf nodejs%s, default crypto policy" % nv, CLASSICAL, doc=DOC + " l.26, l.397")
    ec2("node-ec2-al2023-n%s-service-conf" % nv, "pqc-al2023", "node-%s %s" % (nv, P), "config",
        "EC2 AL2023 dnf nodejs%s: one service with OPENSSL_CONF=openssl-pq-node-system.cnf (systemd Environment=)" % nv,
        PQ, env={"OPENSSL_CONF": "/opt/pqc/node/etc-app/openssl-pq-node-system.cnf"},
        doc=DOC + (" l.397, orders.service l.837" if cur else d20), finding=None if cur else AL2023_N20_FINDING)
    ec2("node-ec2-al2023-n%s-host-policy" % nv, "pqc-al2023", "node-%s %s" % (nv, P), "crypto-policy",
        "EC2 AL2023 dnf nodejs%s: host-wide update-crypto-policies --set DEFAULT:PQ" % nv, PQ,
        setup=["update-crypto-policies --set DEFAULT:PQ"], doc=DOC + (" l.397" if cur else d20),
        finding=None if cur else AL2023_N20_FINDING)
for m in ("22", "24"):
    ec2("node-ec2-al2023-official%s-baseline" % m, "pqc-al2023", "/opt/pqc/node/official-%s/bin/node %s" % (m, P), "baseline",
        "EC2 AL2023, official Node %s linux-arm64 binary (bundled OpenSSL 3.5): PQ by default" % m, PQ, doc=DOC + " l.21-22, l.397")
ec2("node-ec2-al2023-official24-host-default-pq", "pqc-al2023", "/opt/pqc/node/official-24/bin/node " + P, "crypto-policy",
    "EC2 AL2023, official Node 24 binary with host DEFAULT:PQ: crypto policy not involved, still PQ", PQ,
    setup=["update-crypto-policies --set DEFAULT:PQ"], doc=DOC + " l.397")

write("node", cases)
