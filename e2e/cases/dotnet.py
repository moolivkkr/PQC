""".NET cases. Expectations are the .NET tab's claims (src/07-dotnet.md) and the enforcement tab's Lambda claims
(src/21-enforcement.md); a FAIL means the doc or the fix is wrong. Where a run showed otherwise, `finding` says so."""
from lib import CLASSICAL, PQ, TLS12_ONLY, ALL, write

DOC = "src/07-dotnet.md"
ENF = "src/21-enforcement.md"
EGRESS_ENV = {  # pq-egress extension: routes to the observer listeners, test CA, client cert for the mtls route
    "PQC_EGRESS_PORT": "2779", "PQ_EGRESS_PORT": "2779",
    "PQ_EGRESS_ROUTES": "hybrid=pq-observer:8443,pqonly=pq-observer:8444,mtls=pq-observer:8445;mtls,"
                        "eccert=pq-observer:8446,tls12=pq-observer:8447",
    "PQ_EGRESS_CA": "/var/task/certs/ca.crt", "PQ_EGRESS_CERT": "/var/task/certs/client.crt",
    "PQ_EGRESS_KEY": "/var/task/certs/client.key"}
WRAP = {"AWS_LAMBDA_EXEC_WRAPPER": "/opt/pq-tls/wrapper"}
BUNDLED = {"OPENSSL_CONF": "/var/task/pq-tls/openssl-pq.cnf"}
HANDLER = "probe::Probe.Function::Handler"
# Trust nothing but the OS store: every target must fail certificate validation (tab D0 control)
UNTRUSTED = {t: {"ok": False, "error_match": "UntrustedRoot|RemoteCertificateChainErrors|PartialChain"} for t in ALL}
cases = []


def lam(id, rt, mode, title, expect, zip, layers=(), env=None, doc=DOC + " By compute type: Lambda zip (line 41)",
        handler=HANDLER, finding=None):
    c = {"id": id, "compute": "lambda", "mode": mode, "title": title, "doc": doc, "expect": expect,
         "lambda": {"runtime": rt, "handler": handler, "zip": "dotnet/" + zip, "layers": list(layers), "env": env or {}}}
    if finding:
        c["finding"] = finding
    cases.append(c)


WRAPPER_FINDING = (
    "%s lines 73 and 90 (Guard rule / PQ-L2) accept AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper as covering dotnet8/dotnet10 "
    "Lambdas, but kit/java-v2/pq-tls-layer/wrapper has no dotnet branch: on AWS_Lambda_dotnet* it logs "
    "'pq-tls: AWS_Lambda_dotnetN: no change' and the function stays classical (PQ-only server refused). A function that "
    "passes the guard with only the wrapper is not PQ. Fix: add a *dotnet* case to the wrapper that sets "
    "OPENSSL_CONF=/opt/pq-tls/openssl-pq.cnf when unset (as for python3.12+), or drop the wrapper alternative for dotnet "
    "from the guard. OPENSSL_CONF=/opt/pq-tls/openssl-pq.cnf with the layer attached does work (case *-layer-conf)." % ENF)

STORE_FINDING = (
    "%s row E3 (line 286) and the 'X509Store on Linux' note (line 202) say a CurrentUser/My client certificate keeps working "
    "and only needs persisting or re-importing at start. On the Lambda dotnet8/dotnet10 runtime (LocalStack, AWS base image) "
    "re-importing at start fails: the store lives under $HOME/.dotnet/corefx, HOME set as a function environment variable was "
    "not visible to the process (probe reported it empty), so .NET used the passwd home /home/sbx_user1051, which is read-only "
    "-> CryptographicException 'could not be added to the store' -> UnauthorizedAccessException. The mTLS call fails before any "
    "handshake; other targets are PQ. Setting HOME in code (Environment.SetEnvironmentVariable) did NOT help either. What works: "
    "an exec wrapper in the package that exports HOME=/tmp (AWS_LAMBDA_EXEC_WRAPPER=/var/task/home-wrapper, case "
    "*-store-clientcert), or loading the PFX/PEM directly (E1/E2). The tab should say this for Lambda." % DOC)

for v in ("8", "10"):
    rt, z = "dotnet" + v, "probe-net%s" % v
    p = "dotnet-lambda-%s-" % rt
    lam(p + "baseline", rt, "baseline", "%s zip, no change: AL2023 crypto policy omits ML-KEM -> classical" % rt, CLASSICAL, z + ".zip")
    lam(p + "bundled-conf", rt, "bundled", "%s + pq-tls/openssl-pq.cnf in package + OPENSSL_CONF=/var/task/... (tab fix)" % rt,
        PQ, z + "-bundled.zip", env=BUNDLED)
    lam(p + "layer-wrapper", rt, "layer", "%s + pq-tls layer + AWS_LAMBDA_EXEC_WRAPPER: wrapper's dotnet branch sets OPENSSL_CONF (enforcement tab PQ-L2)" % rt,
        PQ, z + ".zip", layers=["pq-tls"], env=WRAP, doc=ENF + " lines 73, 90 (Guard rule, PQ-L2)")
    lam(p + "layer-conf", rt, "layer", "%s + pq-tls layer + OPENSSL_CONF=/opt/pq-tls/openssl-pq.cnf (no wrapper)" % rt,
        PQ, z + ".zip", layers=["pq-tls"], env={"OPENSSL_CONF": "/opt/pq-tls/openssl-pq.cnf"},
        doc=ENF + " lines 73, 90 (OPENSSL_CONF=/opt/pq-tls/openssl-pq*.cnf)")
    lam(p + "extension", rt, "extension", "%s + pq-egress extension layer: extension originates PQ TLS" % rt, PQ,
        z + ".zip", layers=["pq-egress"], env=EGRESS_ENV, doc="e2e/lambda/extension/pq-egress (extension option)")
    lam(p + "combined", rt, "extension", "%s + ONE combined layer (wrapper + extension), app talks to the extension" % rt, PQ,
        z + ".zip", layers=["pq-tls-combined"], env=dict(EGRESS_ENV, **WRAP), doc="e2e/lambda/extension/pq-egress (extension option)")
    lam(p + "combined-conf", rt, "layer", "%s + combined layer, direct TLS with OPENSSL_CONF=/opt/pq-tls/openssl-pq.cnf" % rt,
        PQ, z + ".zip", layers=["pq-tls-combined"], env={"OPENSSL_CONF": "/opt/pq-tls/openssl-pq.cnf"},
        doc=ENF + " lines 73, 90")
    # Existing certificate / trust / client-cert setups (tab cases D, E) with the fix on: must stay working, PQ
    lam(p + "store-clientcert", rt, "bundled", "%s fixed + X509Store CurrentUser/My, exec wrapper in package exports HOME=/tmp (tab E3)" % rt,
        PQ, z + "-bundled.zip", env=dict(BUNDLED, PQC_DOTNET_CLIENTCERT="store", AWS_LAMBDA_EXEC_WRAPPER="/var/task/home-wrapper"),
        doc=DOC + " case E, row E3 (line 286)")
    lam(p + "store-clientcert-nohome", rt, "bundled", "%s fixed + X509Store, HOME=/tmp as a function variable: LocalStack drops HOME (AWS's own image under RIE honours it; AWS does not reserve HOME), so this records the emulator, not AWS" % rt,
        dict(PQ, mtls={"ok": False, "error_match": "could not be added to the store.*Access to the path '/home/sbx_user"}),
        z + "-bundled.zip", env=dict(BUNDLED, PQC_DOTNET_CLIENTCERT="store", HOME="/tmp"),
        doc=DOC + " case E, row E3 (line 286); X509Store on Linux note (line 202)")
    lam(p + "ssl-cert-file", rt, "bundled", "%s fixed + no trust code, SSL_CERT_FILE=ca.crt (tab D1)" % rt, PQ,
        z + "-bundled.zip", env=dict(BUNDLED, PQC_DOTNET_TRUST="system", SSL_CERT_FILE="/var/task/certs/ca.crt"),
        doc=DOC + " case D, row D1 (line 221)")

d10, z10 = "dotnet-lambda-dotnet10-", "probe-net10-bundled.zip"
lam(d10 + "callback-trust", "dotnet10", "bundled", "dotnet10 fixed + HttpClientHandler validation callback (tab D3)", PQ, z10,
    env=dict(BUNDLED, PQC_DOTNET_TRUST="callback"), doc=DOC + " case D, row D3 (line 223)")
lam(d10 + "ssl-cert-dir", "dotnet10", "bundled", "dotnet10 fixed + no trust code, SSL_CERT_DIR=hashed dir (tab D2)", PQ, z10,
    env=dict(BUNDLED, PQC_DOTNET_TRUST="system", SSL_CERT_DIR="/var/task/certs/hashdir"), doc=DOC + " case D, row D2 (line 222)")
lam(d10 + "no-ca", "dotnet10", "bundled", "dotnet10 fixed, private CA nowhere (tab D0 control): every target UntrustedRoot",
    UNTRUSTED, z10, env=dict(BUNDLED, PQC_DOTNET_TRUST="system"), doc=DOC + " case D, row D0 (line 220)")
lam(d10 + "pem-clientcert", "dotnet10", "bundled", "dotnet10 fixed + client cert from PEM pair CreateFromPemFile (tab E2)", PQ,
    z10, env=dict(BUNDLED, PQC_DOTNET_CLIENTCERT="pem"), doc=DOC + " case E, row E2 (line 285)")
lam(d10 + "hch-p12-clientcert", "dotnet10", "bundled", "dotnet10 fixed + HttpClientHandler.ClientCertificates from PFX (tab E1)",
    PQ, z10, env=dict(BUNDLED, PQC_DOTNET_HANDLER="httpclienthandler", PQC_DOTNET_TRUST="callback"),
    doc=DOC + " case E, row E1 (line 284)")
lam(d10 + "tls12-pin", "dotnet10", "bundled", "dotnet10 fixed but SslOptions.EnabledSslProtocols=Tls12 (tab F1): never PQ",
    TLS12_ONLY, z10, env=dict(BUNDLED, PQC_DOTNET_PROTOCOLS="Tls12"), doc=DOC + " case F, row F1 (line 319)")
lam(d10 + "tls12-tls13", "dotnet10", "bundled", "dotnet10 fixed + EnabledSslProtocols=Tls12|Tls13 (tab: allowed form)", PQ,
    z10, env=dict(BUNDLED, PQC_DOTNET_PROTOCOLS="Tls12,Tls13"), doc=DOC + " case F 'What to change' (line 327)")

# Native AOT on provided.al2023 (tab line 43: loads the system libssl.so.3, same fix)
lam("dotnet-lambda-aot-baseline", "provided.al2023", "baseline", "Native AOT .NET 10 on provided.al2023, no change", CLASSICAL,
    "probe-aot.zip", handler="bootstrap", doc=DOC + " By compute type: Lambda Native AOT (line 43)")
lam("dotnet-lambda-aot-bundled-conf", "provided.al2023", "bundled", "Native AOT + openssl-pq.cnf + OPENSSL_CONF", PQ,
    "probe-aot-bundled.zip", handler="bootstrap", env=BUNDLED, doc=DOC + " By compute type: Lambda Native AOT (line 43)")

# Lambda container images (PackageType Image) on public.ecr.aws/lambda/dotnet
for v in ("8", "10"):
    for kind, exp in (("baseline", CLASSICAL), ("fixed", PQ)):
        cases.append({"id": "dotnet-lambda-image-dotnet%s-%s" % (v, kind), "compute": "lambda", "mode": "image-" + kind,
                      "title": "Lambda container image lambda/dotnet:%s %s" % (v, "+ Dockerfile.lambda COPY/ENV OPENSSL_CONF" if kind == "fixed" else ""),
                      "doc": DOC + " By compute type: Lambda image (line 42); configs/dotnet/Dockerfile.lambda", "expect": exp,
                      "lambda": {"image": "pqc-dotnet-lambda:dotnet%s-%s" % (v, kind), "runtime": "image"}})


def ecs(id, compute, image, fw, mode, title, expect, env=None, doc=DOC + " container images table (lines 52-63)", finding=None):
    c = {"id": id, "compute": compute, "mode": mode, "title": title, "doc": doc, "expect": expect,
         "runtime_label": "%s %s" % (image, fw),
         "ecs": {"image": image, "entrypoint": ["dotnet"], "command": ["/app/%s/probe.dll" % fw], "env": env or {}}}
    if finding:
        c["finding"] = finding
    cases.append(c)


CONF = {"OPENSSL_CONF": "/etc/pq-tls/openssl-pq.cnf"}
F = "ecs-fargate"
for img, fw, exp, note in (
        ("runtime:8.0", "net8", CLASSICAL, "Debian 12, OpenSSL 3.0: no ML-KEM, change image"),
        ("runtime:8.0-alpine", "net8", PQ, "Alpine 3.24, OpenSSL 3.5: PQ out of the box"),
        ("runtime:8.0-noble", "net8", CLASSICAL, "Ubuntu 24.04, OpenSSL 3.0: no ML-KEM"),
        ("runtime:10.0", "net10", CLASSICAL, "default 10.0 = Ubuntu 24.04, OpenSSL 3.0.13: change image"),
        ("runtime:10.0-alpine", "net10", PQ, "Alpine 3.24, OpenSSL 3.5: PQ out of the box"),
        ("runtime:10.0-azurelinux3.0", "net10", CLASSICAL, "Azure Linux 3.0, OpenSSL 3.3: no ML-KEM"),
        ("aspnet:10.0-noble-chiseled", "net10", CLASSICAL, "Ubuntu 24.04 chiseled, OpenSSL 3.0"),
        ("aspnet:10.0-resolute", "net10", PQ, "Ubuntu 26.04, OpenSSL 3.5.5: PQ out of the box"),
        ("aspnet:10.0-resolute-chiseled", "net10", PQ, "Ubuntu 26.04 chiseled, OpenSSL 3.5: PQ out of the box")):
    tag = img.replace(":", "-")
    ecs("dotnet-fargate-%s" % tag.replace(".", ""), F, "pqc-dotnet:mcr-" + tag, fw, "baseline",
        "Fargate mcr.microsoft.com/dotnet/%s - %s" % (img, note), exp)
RES = "pqc-dotnet:mcr-aspnet-10.0-resolute"
ecs("dotnet-fargate-resolute-sysca", F, "pqc-dotnet:mcr-aspnet-10.0-resolute-sysca", "net10", "baseline",
    "Fargate 10.0-resolute, CA via update-ca-certificates, no trust code (tab D5)", PQ, env={"PQC_DOTNET_TRUST": "system"},
    doc=DOC + " case D, row D5 (line 225)")
ecs("dotnet-fargate-alpine-sysca", F, "pqc-dotnet:mcr-runtime-10.0-alpine-sysca", "net10", "baseline",
    "Fargate 10.0-alpine, apk add ca-certificates + update-ca-certificates, no trust code (tab D5)", PQ,
    env={"PQC_DOTNET_TRUST": "system"}, doc=DOC + " case D, row D5 (line 225) and Alpine CA pitfall")
ecs("dotnet-fargate-resolute-ssl-cert-file", F, RES, "net10", "baseline",
    "Fargate 10.0-resolute, SSL_CERT_FILE=/app/certs/ca.crt, no trust code (tab D1)", PQ,
    env={"PQC_DOTNET_TRUST": "system", "SSL_CERT_FILE": "/app/certs/ca.crt"}, doc=DOC + " case D, row D1 (line 221)")
ecs("dotnet-fargate-resolute-store-clientcert", F, RES, "net10", "baseline",
    "Fargate 10.0-resolute, client cert from X509Store CurrentUser/My (tab E3)", PQ,
    env={"PQC_DOTNET_CLIENTCERT": "store", "HOME": "/tmp"}, doc=DOC + " case E, row E3 (line 286)")
ecs("dotnet-fargate-resolute-pem-clientcert", F, RES, "net10", "baseline",
    "Fargate 10.0-resolute, client cert PEM pair (tab E2)", PQ, env={"PQC_DOTNET_CLIENTCERT": "pem"},
    doc=DOC + " case E, row E2 (line 285)")
ecs("dotnet-fargate-resolute-tls12-pin", F, RES, "net10", "baseline",
    "Fargate 10.0-resolute (PQ image) but EnabledSslProtocols=Tls12 (tab F1): never PQ", TLS12_ONLY,
    env={"PQC_DOTNET_PROTOCOLS": "Tls12"}, doc=DOC + " case F, row F1 (line 319)")
ecs("dotnet-fargate-alpine8-callback-trust", F, "pqc-dotnet:mcr-runtime-8.0-alpine", "net8", "baseline",
    "Fargate 8.0-alpine, HttpClientHandler validation callback + PFX client cert (tab D3/E1)", PQ,
    env={"PQC_DOTNET_TRUST": "callback", "PQC_DOTNET_HANDLER": "httpclienthandler"}, doc=DOC + " case D row D3, case E row E1")
ecs("dotnet-fargate-debian8-store-clientcert", F, "pqc-dotnet:mcr-runtime-8.0", "net8", "baseline",
    "Fargate 8.0 (Debian 12), X509Store client cert: works, classical only (tab E3, Debian column)", CLASSICAL,
    env={"PQC_DOTNET_CLIENTCERT": "store", "HOME": "/tmp"}, doc=DOC + " case E, row E3 (line 286)")
# AL2023 + dnf runtime: baseline vs OPENSSL_CONF (task definition) vs crypto policy
for fw in ("net8", "net10"):
    ecs("dotnet-fargate-al2023-%s-baseline" % fw, F, "pqc-dotnet:al2023", fw, "baseline",
        "Fargate AL2023 + dnf aspnetcore-runtime (%s): crypto policy omits ML-KEM" % fw, CLASSICAL)
    ecs("dotnet-fargate-al2023-%s-conf" % fw, F, "pqc-dotnet:al2023", fw, "config",
        "Fargate AL2023 %s + task-def OPENSSL_CONF (configs/dotnet/taskdef.json)" % fw, PQ, env=CONF,
        doc=DOC + " container images table (line 62); configs/dotnet/taskdef.json")
    ecs("dotnet-fargate-al2023-%s-policy" % fw, F, "pqc-dotnet:al2023-policy", fw, "crypto-policy",
        "Fargate AL2023 %s image with update-crypto-policies --set DEFAULT:PQ" % fw, PQ, doc=DOC + " container images table (line 63)")
ecs("dotnet-fargate-al2023-fixed-net8", F, "pqc-dotnet:al2023-fixed", "net8", "config",
    "Fargate: configs/dotnet/Dockerfile.al2023 as published (COPY + ENV OPENSSL_CONF baked in)", PQ,
    doc=DOC + " Full configuration files: Dockerfile.al2023")
ecs("dotnet-fargate-al2023-sysca-conf", F, "pqc-dotnet:al2023-sysca", "net10", "config",
    "Fargate AL2023, CA via update-ca-trust, no trust code, + OPENSSL_CONF: kit file keeps CA locations (tab D5)", PQ,
    env=dict(CONF, PQC_DOTNET_TRUST="system"), doc=DOC + " case D 'What to change' (line 213), row D5")
# ECS on EC2 launch type: same images, same results expected (the container's userland decides, not the host)
E = "ecs-ec2"
ecs("dotnet-ecsec2-debian8-baseline", E, "pqc-dotnet:mcr-runtime-8.0", "net8", "baseline", "ECS EC2 launch type, runtime:8.0 (Debian 12)", CLASSICAL)
ecs("dotnet-ecsec2-alpine10-baseline", E, "pqc-dotnet:mcr-runtime-10.0-alpine", "net10", "baseline", "ECS EC2 launch type, runtime:10.0-alpine", PQ)
ecs("dotnet-ecsec2-resolute-baseline", E, RES, "net10", "baseline", "ECS EC2 launch type, aspnet:10.0-resolute", PQ)
ecs("dotnet-ecsec2-al2023-net10-baseline", E, "pqc-dotnet:al2023", "net10", "baseline", "ECS EC2 launch type, AL2023 net10", CLASSICAL)
ecs("dotnet-ecsec2-al2023-net8-conf", E, "pqc-dotnet:al2023", "net8", "config", "ECS EC2 launch type, AL2023 net8 + OPENSSL_CONF", PQ, env=CONF)
ecs("dotnet-ecsec2-al2023-net10-policy", E, "pqc-dotnet:al2023-policy", "net10", "crypto-policy",
    "ECS EC2 launch type, AL2023 net10 + DEFAULT:PQ image", PQ)


def ec2(id, run, mode, title, expect, setup=(), env=None, doc=DOC + " By compute type: EC2 AL2023 (line 45)"):
    cases.append({"id": id, "compute": "ec2", "mode": mode, "title": title, "doc": doc, "expect": expect,
                  "runtime_label": "pqc-al2023 " + run.split()[1],
                  "ec2": {"ami": "pqc-al2023", "run": run, "setup": list(setup), "env": env or {}}})


for fw in ("net8", "net10"):
    run = "dotnet /opt/pqc/dotnet/%s/probe.dll" % fw
    ec2("dotnet-ec2-al2023-%s-baseline" % fw, run, "baseline", "EC2 AL2023 2023.12.20261109 dnf .NET (%s), default policy" % fw, CLASSICAL)
    ec2("dotnet-ec2-al2023-%s-service-conf" % fw, run, "config",
        "EC2 AL2023 %s: one service with OPENSSL_CONF (systemd Environment= equivalent)" % fw, PQ,
        env={"OPENSSL_CONF": "/opt/pqc/dotnet/pq-tls/openssl-pq.cnf"})
    ec2("dotnet-ec2-al2023-%s-host-policy" % fw, run, "crypto-policy",
        "EC2 AL2023 %s: host-wide update-crypto-policies --set DEFAULT:PQ (configs/dotnet/ssm-al2023-pq-policy.yaml)" % fw, PQ,
        setup=["update-crypto-policies --set DEFAULT:PQ", "update-crypto-policies --show"])
ec2("dotnet-ec2-al2023-net10-policy-store-clientcert", "dotnet /opt/pqc/dotnet/net10/probe.dll", "crypto-policy",
    "EC2 AL2023 DEFAULT:PQ + client cert from X509Store CurrentUser/My (tab E3)", PQ,
    setup=["update-crypto-policies --set DEFAULT:PQ"], env={"PQC_DOTNET_CLIENTCERT": "store", "HOME": "/root"},
    doc=DOC + " case E, row E3 (line 286)")

write("dotnet", cases)
