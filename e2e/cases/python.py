"""Python cases. Expectations are the Python tab's claims (src/04-python.md); a FAIL means the doc or the fix is wrong."""
from lib import CLASSICAL, PQ, TLS12_ONLY, ALL, write

DOC = "src/04-python.md"
EGRESS_ENV = {  # pq-egress extension: routes to the observer listeners, test CA, client cert for the mtls route
    "PQC_EGRESS_PORT": "2779", "PQ_EGRESS_PORT": "2779",
    "PQ_EGRESS_ROUTES": "hybrid=pq-observer:8443,pqonly=pq-observer:8444,mtls=pq-observer:8445;mtls,"
                        "eccert=pq-observer:8446,tls12=pq-observer:8447",
    "PQ_EGRESS_CA": "/var/task/certs/ca.crt", "PQ_EGRESS_CERT": "/var/task/certs/client.crt",
    "PQ_EGRESS_KEY": "/var/task/certs/client.key"}
WRAP = {"AWS_LAMBDA_EXEC_WRAPPER": "/opt/pq-tls/wrapper"}
cases = []


def lam(id, rt, mode, title, expect, zip="probe.zip", layers=(), env=None, doc=DOC + " Step 2: Lambda zip"):
    cases.append({"id": id, "compute": "lambda", "mode": mode, "title": title, "doc": doc, "expect": expect,
                  "lambda": {"runtime": rt, "handler": "probe.handler", "zip": "python/" + zip, "layers": list(layers),
                             "env": env or {}}})


LEGACY = ["python3.9", "python3.10", "python3.11"]          # Lambda: Amazon Linux 2, OpenSSL 1.1.1
CURRENT = ["python3.12", "python3.13", "python3.14"]        # Lambda: AL2023, OpenSSL 3.5, crypto policy omits ML-KEM
for rt in LEGACY + CURRENT:
    v = rt.replace("python", "py").replace(".", "")
    lam("py-lambda-%s-baseline" % v, rt, "baseline", "%s zip, no change: classical, fails PQ-only server" % rt, CLASSICAL)
    if rt in CURRENT:
        lam("py-lambda-%s-bundled-conf" % v, rt, "bundled", "%s + pq-tls/openssl-pq.cnf in package + OPENSSL_CONF" % rt, PQ,
            zip="probe-bundled.zip", env={"OPENSSL_CONF": "/var/task/pq-tls/openssl-pq.cnf"})
        lam("py-lambda-%s-layer" % v, rt, "layer", "%s + pq-tls layer + AWS_LAMBDA_EXEC_WRAPPER" % rt, PQ,
            layers=["pq-tls"], env=WRAP)
    else:
        lam("py-lambda-%s-bundled-shim" % v, rt, "bundled", "%s + pyshim + pyOpenSSL/cryptography in package (urllib3)" % rt, PQ,
            zip="probe-shim-%s.zip" % v, env={"PYTHONPATH": "/var/task/pq-tls/pyshim"})
        lam("py-lambda-%s-layer" % v, rt, "layer", "%s + pq-tls layer: wrapper turns on the urllib3 shim" % rt, PQ,
            layers=["pq-tls"], env=WRAP)
    lam("py-lambda-%s-extension" % v, rt, "extension", "%s + pq-egress extension layer: extension originates PQ TLS" % rt, PQ,
        layers=["pq-egress"], env=EGRESS_ENV, doc="e2e/lambda/extension/pq-egress (extension option)")

# Limits and existing-configuration cases
lam("py-lambda-py311-layer-stdlib", "python3.11", "layer",
    "python3.11 + layer, stdlib http.client: shim does NOT cover it (documented limit)", CLASSICAL,
    layers=["pq-tls"], env=dict(WRAP, PQC_PY_STACK="stdlib"), doc=DOC + " pyshim header: stdlib ssl not covered")
lam("py-lambda-py311-combined-ext-stdlib", "python3.11", "extension",
    "python3.11 stdlib client via ONE combined layer (wrapper + extension): extension covers what the shim cannot", PQ,
    layers=["pq-tls-combined"], env=dict(EGRESS_ENV, PQC_PY_STACK="stdlib", **WRAP))
lam("py-lambda-py311-shim-noidna", "python3.11", "bundled",
    "PITFALL: bridge built with only 'pyopenssl cryptography' (as the tab says): urllib3 needs idna -> requests FAIL",
    {t: {"ok": False, "error_match": "idna"} for t in ALL}, zip="probe-shim-noidna-py311.zip",
    env={"PYTHONPATH": "/var/task/pq-tls/pyshim", "PQC_PY_STRICT": "1"}, doc=DOC + " Bridge (pip install line)")
cases[-1]["finding"] = ("Fixed in the doc on 2026-11-14; kept as a regression check. "
    "Bridge step installs only pyopenssl + cryptography; urllib3.contrib.pyopenssl also imports idna, "
                        "which the Lambda runtime lacks, so every urllib3/boto3 request raises ImportError. Add idna to "
                        "the pip line (and build per Python version: the 3.11 abi3 cryptography wheel fails on 3.9/3.10).")
lam("py-lambda-py313-combined-wrapper", "python3.13", "layer",
    "python3.13 + ONE combined layer, wrapper path only", PQ, layers=["pq-tls-combined"], env=WRAP)
lam("py-lambda-py312-layer-ownconf", "python3.12", "layer",
    "function already sets OPENSSL_CONF (classical file): wrapper leaves it alone -> stays classical until Groups merged",
    CLASSICAL, zip="probe-ownconf.zip", layers=["pq-tls"],
    env=dict(WRAP, OPENSSL_CONF="/var/task/conf/app-openssl.cnf"), doc=DOC + " 'If the function already sets OPENSSL_CONF'")
lam("py-lambda-py312-layer-chain", "python3.12", "layer",
    "existing exec wrapper chained with PQ_TLS_NEXT_WRAPPER: both run, PQ on", PQ, zip="probe-chain.zip",
    layers=["pq-tls"], env=dict(WRAP, PQ_TLS_NEXT_WRAPPER="/var/task/app-wrapper"))
lam("py-lambda-py312-layer-disabled", "python3.12", "layer",
    "rollback switch PQ_TLS_DISABLE=1 with layer still attached: back to classical", CLASSICAL,
    layers=["pq-tls"], env=dict(WRAP, PQ_TLS_DISABLE="1"))

# Lambda container images (PackageType Image) on public.ecr.aws/lambda/python
for v in ("312", "313"):
    for kind, exp in (("baseline", CLASSICAL), ("fixed", PQ)):
        cases.append({"id": "py-lambda-image-py%s-%s" % (v, kind), "compute": "lambda", "mode": "image-" + kind,
                      "title": "Lambda container image python:%s.%s %s" % (v[0], v[1:], "(Dockerfile.lambda ENV OPENSSL_CONF)" if kind == "fixed" else ""),
                      "doc": DOC + " Lambda container image", "expect": exp,
                      "lambda": {"image": "pqc-python-lambda:py%s-%s" % (v, kind), "runtime": "image"}})


def ecs(id, compute, image, cmd, mode, title, expect, env=None, doc=DOC + " Fargate, ECS and EKS"):
    cases.append({"id": id, "compute": compute, "mode": mode, "title": title, "doc": doc, "expect": expect,
                  "runtime_label": image + " " + cmd[0],
                  "ecs": {"image": image, "command": cmd, "env": env or {}}})


CONF = {"OPENSSL_CONF": "/etc/pq-tls/openssl-pq.cnf"}
for py in ("3.11", "3.12", "3.13", "3.14"):
    tag = py.replace(".", "")
    ecs("py-fargate-al2023-py%s-baseline" % tag, "ecs-fargate", "pqc-python:al2023", ["python" + py, "/app/probe.py"],
        "baseline", "Fargate AL2023 python%s: crypto policy omits ML-KEM" % py, CLASSICAL)
    ecs("py-fargate-al2023-py%s-conf" % tag, "ecs-fargate", "pqc-python:al2023", ["python" + py, "/app/probe.py"],
        "config", "Fargate AL2023 python%s + task-def OPENSSL_CONF (configs/python/ecs/taskdef.json)" % py, PQ, env=CONF)
ecs("py-fargate-al2023-py312-policy", "ecs-fargate", "pqc-python:al2023-policy", ["python3.12", "/app/probe.py"],
    "crypto-policy", "Fargate AL2023 image with update-crypto-policies --set DEFAULT:PQ", PQ)
for base, exp, note in (("3.12-slim-trixie", PQ, "Debian 13, OpenSSL 3.5: PQ out of the box"),
                        ("3.13-slim-trixie", PQ, "Debian 13, OpenSSL 3.5: PQ out of the box"),
                        ("3.12-alpine", PQ, "Alpine, OpenSSL 3.5: PQ out of the box"),
                        ("3.12-slim-bookworm", CLASSICAL, "Debian 12, OpenSSL 3.0: no ML-KEM, move base image")):
    ecs("py-fargate-lib-%s" % base.replace(".", ""), "ecs-fargate", "pqc-python:lib-" + base, ["python", "/app/probe.py"],
        "baseline", "Fargate python:%s - %s" % (base, note), exp)
# ECS on EC2 launch type: same images, same results expected (the container's userland decides, not the host)
ecs("py-ecsec2-al2023-py312-baseline", "ecs-ec2", "pqc-python:al2023", ["python3.12", "/app/probe.py"], "baseline",
    "ECS EC2 launch type, AL2023 python3.12", CLASSICAL)
ecs("py-ecsec2-al2023-py312-conf", "ecs-ec2", "pqc-python:al2023", ["python3.12", "/app/probe.py"], "config",
    "ECS EC2 launch type, AL2023 python3.12 + OPENSSL_CONF", PQ, env=CONF)
ecs("py-ecsec2-lib-313-slim-trixie", "ecs-ec2", "pqc-python:lib-3.13-slim-trixie", ["python", "/app/probe.py"], "baseline",
    "ECS EC2 launch type, python:3.13-slim-trixie", PQ)


def ec2(id, ami, run, mode, title, expect, setup=(), env=None, doc=DOC + " EC2"):
    cases.append({"id": id, "compute": "ec2", "mode": mode, "title": title, "doc": doc, "expect": expect,
                  "runtime_label": "%s %s" % (ami, run.split()[0]),
                  "ec2": {"ami": ami, "run": run, "setup": list(setup), "env": env or {}}})


P = "/opt/pqc/python/probe.py"
for py in ("3.11", "3.12", "3.13", "3.14"):
    tag = py.replace(".", "")
    ec2("py-ec2-al2023-py%s-baseline" % tag, "pqc-al2023", "python%s %s" % (py, P), "baseline",
        "EC2 AL2023 2023.12.20261109 python%s, default crypto policy" % py, CLASSICAL)
ec2("py-ec2-al2023-py312-service-conf", "pqc-al2023", "python3.12 " + P, "config",
    "EC2 AL2023: one service with OPENSSL_CONF (systemd Environment= equivalent)", PQ,
    env={"OPENSSL_CONF": "/opt/pqc/python/pq-tls/openssl-pq.cnf"})
ec2("py-ec2-al2023-py313-host-policy", "pqc-al2023", "python3.13 " + P, "crypto-policy",
    "EC2 AL2023: host-wide update-crypto-policies --set DEFAULT:PQ (SSM document step)", PQ,
    setup=["update-crypto-policies --set DEFAULT:PQ"])
ec2("py-ec2-al2023-py311-host-policy", "pqc-al2023", "python3.11 " + P, "crypto-policy",
    "EC2 AL2023 python3.11 (system OpenSSL 3.5, unlike Lambda's 3.11) + DEFAULT:PQ", PQ,
    setup=["update-crypto-policies --set DEFAULT:PQ"])
ec2("py-ec2-al2-py3-baseline", "pqc-al2", "python3 " + P, "baseline",
    "EC2 Amazon Linux 2 python3.7, OpenSSL 1.0.2: no TLS 1.3 at all - migrate the host", TLS12_ONLY)

write("python", cases)
