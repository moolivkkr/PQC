"""Java cases. Expectations are the Java tab's claims (src/06-java.md); a FAIL means the doc or the fix is wrong.

The probe (clients/java/Probe.java) is an app with an existing custom keystore + truststore: its own
SSLContext.getInstance("TLS") from truststore.p12 and client.p12 (KeyManagerFactory.getDefaultAlgorithm()),
HttpsURLConnection, no named groups or protocols in code. PQC_JAVA_TLS=sysprops switches to "no TLS code"
(-Djavax.net.ssl.keyStore/trustStore), PQC_JAVA_KMF names a key manager algorithm, PQC_JAVA_CLIENT_KS picks
the client keystore (client-ec.p12 = EC P-256 client cert from the same test CA).
"""
from lib import CLASSICAL, PQ, TLS12_ONLY, ALL, override, write

DOC = "src/06-java.md"
EGRESS_ENV = {  # pq-egress extension: routes to the observer listeners, test CA, client cert for the mtls route
    "PQC_EGRESS_PORT": "2779", "PQ_EGRESS_PORT": "2779",
    "PQ_EGRESS_ROUTES": "hybrid=pq-observer:8443,pqonly=pq-observer:8444,mtls=pq-observer:8445;mtls,"
                        "eccert=pq-observer:8446,tls12=pq-observer:8447",
    "PQ_EGRESS_CA": "/var/task/certs/ca.crt", "PQ_EGRESS_CERT": "/var/task/certs/client.crt",
    "PQ_EGRESS_KEY": "/var/task/certs/client.key"}
WRAP = {"AWS_LAMBDA_EXEC_WRAPPER": "/opt/pq-tls/wrapper"}
KIT_ZIP = "-Djava.security.properties=/var/task/pq-tls/pq-tls.security -javaagent:/var/task/pq-tls/pq-tls-agent.jar"
J8 = " -Djdk.tls.client.protocols=TLSv1.3,TLSv1.2"
KIT_OPT = "-Djava.security.properties=/opt/pq-tls/pq-tls.security -javaagent:/opt/pq-tls/pq-tls-agent.jar"
KIT_EC2 = "-Djava.security.properties=/opt/pqc/java/pq-tls/pq-tls.security -javaagent:/opt/pqc/java/pq-tls/pq-tls-agent.jar"
EC_KS = {"PQC_JAVA_CLIENT_KS": "client-ec.p12"}
SYSPROPS = ("-Djavax.net.ssl.keyStore=/var/task/certs/%s -Djavax.net.ssl.keyStorePassword=changeit "
            "-Djavax.net.ssl.keyStoreType=PKCS12 -Djavax.net.ssl.trustStore=/var/task/certs/truststore.p12 "
            "-Djavax.net.ssl.trustStorePassword=changeit -Djavax.net.ssl.trustStoreType=PKCS12")
PIN = "-Djdk.tls.namedGroups=x25519,secp256r1,secp384r1"
# mTLS refused because no (usable) client certificate was sent; every other target as in the preset
# (TLS 1.3: the server's refusal reaches the client after its Finished, as a write/read error on the connection)
NO_CLIENT_CERT = {"ok": False, "error_match": "(?i)certificate|handshake|SSL|Connection reset|closed|Error writing to server|failed TLS connection"}
J8_HOST = " -Dorg.bouncycastle.jsse.client.assumeOriginalHostName=true"
# JDK 8 + BCJSSE 1.87 + HttpsURLConnection: the JDK 8 HttpsClient creates the socket without a host name, and
# BCJSSE (1.78+) refuses endpoint identification without one -> every handshake fails (see FINDING_J8).
J8_FAIL = {t: {"ok": False, "error_match": "No hostname specified for HTTPS endpoint ID check"} for t in ALL}
FINDING_J8 = ("Fixed in the doc and kit on 2026-11-14; this case keeps the old instructions as a regression check. "
              "src/06-java.md:30, :44 (and template.yaml at :962) say JDK 8 + kit (agent + "
              "-Djdk.tls.client.protocols=TLSv1.3,TLSv1.2) gives PQ. Observed on Corretto 8u512 (Lambda java8.al2, "
              "lambda/java:8.al2023 image, amazoncorretto:8 on ECS): with HttpsURLConnection every handshake fails, "
              "PQ and classical, with BCJSSE 'certificate_unknown(46) <- No hostname specified for HTTPS endpoint ID "
              "check'. JDK 8's HttpsURLConnection creates the socket without a host name; BCJSSE 1.78+ fails "
              "endpoint identification by default then (bc-java issue #1656). Adding "
              "-Dorg.bouncycastle.jsse.client.assumeOriginalHostName=true to JAVA_TOOL_OPTIONS fixes it (PQ on all "
              "targets, case java-lambda-j8-bundled-hostfix). The tab's JDK 8 test used raw SSLSocket, not "
              "HttpsURLConnection. JDK 11+ is not affected.")
FINDING_J8_PROTO = ("Fixed in the doc and kit on 2026-11-14; this case keeps the old instructions as a regression check. "
                    "src/06-java.md:30 ('SunJSSE, TLS 1.2 client default'), :376 ('8 defaults clients to TLS 1.2') and :445 "
                    "state it for JDK 8 generally. Observed: only the Lambda Java 8 runtime sets "
                    "jdk.tls.client.protocols=TLSv1.2,TLSv1.1,TLSv1 (java8.al2 zip and the lambda/java:8.al2023 image, also "
                    "under the image's own RIE without LocalStack); a plain Corretto 8u512 (amazoncorretto:8, and /var/lang/bin/java "
                    "in the Lambda image started directly) offers TLS 1.3 by default (classical P-256 here). BCJSSE honours the "
                    "same property, so on Lambda the flag is required with the kit; in containers and EC2 with 8u512 it is not "
                    "(java-fargate-corretto8-agent-noproto is PQ without it). The flag in JAVA_TOOL_OPTIONS overrides Lambda's value.")
cases = []


def j8finding(c):
    c["expect"] = J8_FAIL
    c["finding"] = FINDING_J8
    c["title"] += " -> HttpsURLConnection fails on JDK 8 (host name)"


def lam(id, rt, mode, title, expect, zip="probe.zip", layers=(), env=None, doc=DOC + " Packaging table: Lambda zip"):
    cases.append({"id": id, "compute": "lambda", "mode": mode, "title": title, "doc": doc, "expect": expect,
                  "lambda": {"runtime": rt, "handler": "Probe::handleRequest", "zip": "java/" + zip,
                             "layers": list(layers), "env": env or {}, "memory": 1024}})


def image(id, tag, mode, title, expect, doc=DOC + " Packaging table: Lambda container image", env=None):
    cases.append({"id": id, "compute": "lambda", "mode": mode, "title": title, "doc": doc, "expect": expect,
                  "lambda": {"image": "pqc-java-lambda:" + tag, "runtime": "image", "env": env or {}, "memory": 1024}})


# ---------------------------------------------------------------- Lambda zip, every runtime x {baseline, layer, bundled, extension, combined}
# java8.al2023 is not accepted by LocalStack 2026.10.6 (its Runtime enum lacks it, though AWS lists it), so Java 8
# zips run on java8.al2 (Corretto 8 on AL2, same JDK 8 code path, AWS_EXECUTION_ENV matches the wrapper's *java8*);
# java8.al2023 itself is covered by the container-image cases below (public.ecr.aws/lambda/java:8.al2023).
RTS = [("java8.al2", "j8"), ("java11", "j11"), ("java17", "j17"), ("java21", "j21"), ("java25", "j25")]
for rt, v in RTS:
    base = {"j8": TLS12_ONLY, "j25": PQ}.get(v, CLASSICAL)
    lam("java-lambda-%s-baseline" % v, rt, "baseline",
        "%s zip, no change: %s" % (rt, {"j8": "JDK 8 client defaults to TLS 1.2", "j25": "JDK 25.0.5 PQ by default"}.get(v, "classical, fails PQ-only server")),
        base, doc=DOC + " By JDK and compute type (Lambda zip column)")
    lam("java-lambda-%s-layer" % v, rt, "layer",
        "%s + pq-tls layer v2 + AWS_LAMBDA_EXEC_WRAPPER%s" % (rt, " (wrapper: no change on 25)" if v == "j25" else
                                                             " (wrapper adds TLSv1.3)" if v == "j8" else ""),
        PQ, layers=["pq-tls"], env=WRAP, doc=DOC + " Packaging table: Lambda layer; wrapper java branch")
    if v != "j25":
        lam("java-lambda-%s-bundled" % v, rt, "bundled", "%s + kit v2 in the zip (pq-tls/) + JAVA_TOOL_OPTIONS%s" % (rt, " (+ TLSv1.3 flag)" if v == "j8" else ""),
            PQ, zip="probe-agent.zip", env={"JAVA_TOOL_OPTIONS": KIT_ZIP + (J8 if v == "j8" else "")},
            doc=DOC + " Lambda: template.yaml (zip, kit v2)")
    if v == "j8":
        cases[-2]["title"] += " (wrapper adds TLSv1.3 flag + assumeOriginalHostName)"
        j8finding(cases[-1])  # bundled with the old JAVA_TOOL_OPTIONS (no host-name flag)
    lam("java-lambda-%s-extension" % v, rt, "extension", "%s + pq-egress extension layer: extension originates PQ TLS" % rt, PQ,
        layers=["pq-egress"], env=EGRESS_ENV, doc="e2e/lambda/extension/pq-egress (extension option)")
    lam("java-lambda-%s-combined" % v, rt, "layer", "%s + ONE combined layer (wrapper + extension), JVM path via wrapper" % rt, PQ,
        layers=["pq-tls-combined"], env=WRAP, doc=DOC + " Packaging table: Lambda layer")
lam("java-lambda-j17-combined-ext", "java17", "extension", "java17 + combined layer, wrapper AND extension env: extension carries the call",
    PQ, layers=["pq-tls-combined"], env=dict(EGRESS_ENV, **WRAP), doc="e2e/lambda/extension/pq-egress (extension option)")

# JDK 8 remedy for HttpsURLConnection under BCJSSE, and the TLS 1.3 flag question
lam("java-lambda-j8-bundled-hostfix", "java8.al2", "bundled",
    "java8 + kit v2 + TLSv1.3 flag + -Dorg.bouncycastle.jsse.client.assumeOriginalHostName=true: PQ", PQ,
    zip="probe-agent.zip", env={"JAVA_TOOL_OPTIONS": KIT_ZIP + J8 + J8_HOST}, doc=DOC + " JDK 8 row (template.yaml as fixed)")
lam("java-lambda-j8-bundled-noproto", "java8.al2", "bundled",
    "java8 + kit v2 WITHOUT -Djdk.tls.client.protocols (host-name fix on): Lambda's TLS 1.2 setting also binds BCJSSE",
    TLS12_ONLY, zip="probe-agent.zip", env={"JAVA_TOOL_OPTIONS": KIT_ZIP + J8_HOST},
    doc=DOC + " JVM flags: jdk.tls.client.protocols (Java 8 only); Rules: 'On Java 8 add -Djdk.tls.client.protocols'")
lam("java-lambda-j8-layer-hostfix", "java8.al2", "layer", "java8 + layer v2 + function adds assumeOriginalHostName to JAVA_TOOL_OPTIONS: PQ",
    PQ, layers=["pq-tls"], env=dict(WRAP, JAVA_TOOL_OPTIONS=J8_HOST.strip()), doc=DOC + " Lambda layer: wrapper does not add the flag twice")

# ---------------------------------------------------------------- existing keystores / truststores (cases C, D, E)
lam("java-lambda-j21-ks-ec-baseline", "java21", "baseline", "java21, own SSLContext with EC client keystore, no kit: classical, mTLS works",
    CLASSICAL, env=EC_KS, doc=DOC + " C/E: keystore situations")
lam("java-lambda-j21-ks-ec-bundled", "java21", "bundled", "java21 + kit v2, own SSLContext, EC client cert, KeyManagerFactory default (PKIX)",
    PQ, zip="probe-agent.zip", env=dict(EC_KS, JAVA_TOOL_OPTIONS=KIT_ZIP), doc=DOC + " E: BCJSSE client with client-ec.p12 connects")
lam("java-lambda-j21-ks-ec-layer", "java21", "layer", "java21 + layer v2, own SSLContext, EC client cert", PQ,
    layers=["pq-tls"], env=dict(EC_KS, **WRAP), doc=DOC + " E + Lambda layer")
lam("java-lambda-j17-ks-ec-sunx509", "java17", "bundled",
    "java17 + kit v2, code hard-codes KeyManagerFactory.getInstance(\"SunX509\"), EC client cert: mTLS still fails",
    override(PQ, mtls=NO_CLIENT_CERT), zip="probe-agent.zip", env=dict(EC_KS, PQC_JAVA_KMF="SunX509", JAVA_TOOL_OPTIONS=KIT_ZIP),
    doc=DOC + " C: 'Code hard-codes KeyManagerFactory.getInstance(\"SunX509\")' -> Still fails")
lam("java-lambda-j17-ks-rsa-sunx509", "java17", "bundled",
    "java17 + kit v2, hard-coded SunX509 with the RSA client cert: works (RSA never needed the fix)", PQ,
    zip="probe-agent.zip", env={"PQC_JAVA_KMF": "SunX509", "JAVA_TOOL_OPTIONS": KIT_ZIP}, doc=DOC + " C: 'RSA vs EC' note")
lam("java-lambda-j17-ks-ec-pkix", "java17", "bundled", "java17 + kit v2, code names \"PKIX\" explicitly, EC client cert", PQ,
    zip="probe-agent.zip", env=dict(EC_KS, PQC_JAVA_KMF="PKIX", JAVA_TOOL_OPTIONS=KIT_ZIP), doc=DOC + " C: use getDefaultAlgorithm() or PKIX")
lam("java-lambda-j21-ks-ec-v1", "java21", "bundled",
    "java21 + agent only, PKIX step switched off (= kit v1 behaviour): EC client cert silently not sent",
    override(PQ, mtls=NO_CLIENT_CERT), zip="probe-agent.zip",
    env=dict(EC_KS, JAVA_TOOL_OPTIONS="-javaagent:/var/task/pq-tls/pq-tls-agent.jar -Dpq.tls.keyManagerAlgorithm=keep"),
    doc=DOC + " E: 'What happens today (kit v1)': EC client cert -> certificate_required")
lam("java-lambda-j21-layer-ownsec", "java21", "layer",
    "java21 + layer, function passes its own -Djava.security.properties (no PKIX line): wrapper leaves it, agent v2 sets PKIX; EC mTLS works",
    PQ, zip="probe-ownsec.zip", layers=["pq-tls"],
    env=dict(EC_KS, JAVA_TOOL_OPTIONS="-Djava.security.properties=/var/task/conf/app.security", **WRAP),
    doc=DOC + " C: 'App passes its own -Djava.security.properties' -> PQ (agent v2 fallback); wrapper v2 comment")
lam("java-lambda-j11-layer-ownsec", "java11", "layer", "java11 + layer, own security file, EC client cert", PQ,
    zip="probe-ownsec.zip", layers=["pq-tls"],
    env=dict(EC_KS, JAVA_TOOL_OPTIONS="-Djava.security.properties=/var/task/conf/app.security", **WRAP),
    doc=DOC + " C: own -Djava.security.properties")
for v, rt, exp, extra, zp, mode in (("j21", "java21", CLASSICAL, "", "probe.zip", "baseline"),
                                    ("j21", "java21", PQ, KIT_ZIP + " ", "probe-agent.zip", "bundled"),
                                    ("j25", "java25", PQ, "", "probe.zip", "baseline")):
    lam("java-lambda-%s-sysprops-ec-%s" % (v, mode), rt, mode,
        "%s%s, no TLS code: stores given by -Djavax.net.ssl.keyStore/trustStore (EC client cert)" % (rt, " + kit v2" if extra else ""),
        exp, zip=zp, env={"PQC_JAVA_TLS": "sysprops", "JAVA_TOOL_OPTIONS": extra + SYSPROPS % "client-ec.p12"},
        doc=DOC + " C: 'Store given by -Djavax.net.ssl.keyStore'; D: trustStore row")
lam("java-lambda-j21-sysprops-notrust-bundled", "java21", "bundled",
    "java21 + kit v2, no private CA configured: every handshake refused (correct)",
    {t: {"ok": False, "error_match": "(?i)certif|PKIX|trust"} for t in ALL}, zip="probe-agent.zip",
    env={"PQC_JAVA_TLS": "sysprops", "JAVA_TOOL_OPTIONS": KIT_ZIP}, doc=DOC + " D: 'No private CA configured' -> fails")
lam("java-lambda-j25-ks-ec-baseline", "java25", "baseline", "java25, own SSLContext, EC client cert, no kit", PQ, env=EC_KS,
    doc=DOC + " C/E: JDK 25.0.5 no kit column")

# ---------------------------------------------------------------- pins and rollback (case F, Pitfalls)
lam("java-lambda-j25-pin", "java25", "baseline", "java25 with -Djdk.tls.namedGroups pinned without X25519MLKEM768: classical",
    CLASSICAL, env={"JAVA_TOOL_OPTIONS": PIN}, doc=DOC + " F: jdk.tls.namedGroups without X25519MLKEM768")
lam("java-lambda-j21-layer-pin", "java21", "layer", "java21 + layer, app pins jdk.tls.namedGroups: agent leaves it alone -> classical",
    CLASSICAL, layers=["pq-tls"], env=dict(WRAP, JAVA_TOOL_OPTIONS=PIN), doc=DOC + " Pitfalls: 'A pinned group list wins'")
lam("java-lambda-j21-layer-disabled", "java21", "layer", "rollback switch PQ_TLS_DISABLE=1 with layer still attached: classical",
    CLASSICAL, layers=["pq-tls"], env=dict(WRAP, PQ_TLS_DISABLE="1"), doc=DOC + " Pitfalls and rollback")
lam("java-lambda-j21-static", "java21", "static", "java21 zip, static BC registration via bc-static.security: doesn't work on Lambda",
    CLASSICAL, zip="probe-static.zip",
    env={"JAVA_TOOL_OPTIONS": "-Djava.security.properties=/var/task/pq-tls/bc-static.security "
                              "-Djdk.tls.namedGroups=X25519MLKEM768,x25519,secp256r1,secp384r1"},
    doc=DOC + " Packaging table: Lambda zip, static java.security -> 'Doesn't work'")

# ---------------------------------------------------------------- Lambda container images (public.ecr.aws/lambda/java)
for v in ("8", "11", "17", "21"):
    image("java-lambda-image-j%s-baseline" % v, "java%s-baseline" % v, "image-baseline",
          "Lambda image lambda/java:%s, no change" % ("8.al2023" if v == "8" else v), TLS12_ONLY if v == "8" else CLASSICAL)
    image("java-lambda-image-j%s-fixed" % v, "java%s-fixed" % v, "image-fixed",
          "Lambda image lambda/java:%s + Dockerfile.lambda COPY pq-tls/ + ENV JAVA_TOOL_OPTIONS%s" % ("8.al2023" if v == "8" else v,
                                                                                                   " (+ TLSv1.3 flag)" if v == "8" else ""), PQ)
for c in cases:
    if c["id"] == "java-lambda-image-j8-fixed":
        j8finding(c)
image("java-lambda-image-j25-baseline", "java25-baseline", "image-baseline", "Lambda image lambda/java:25 (25.0.5), no change", PQ)
image("java-lambda-image-j8-layer", "java8-layer", "image-layer",
      "lambda/java:8.al2023 + pq-tls layer contents in /opt + AWS_LAMBDA_EXEC_WRAPPER (wrapper adds agent + TLSv1.3)", PQ,
      doc=DOC + " Packaging table: Lambda layer (java8.al2023)")
image("java-lambda-image-j8-layer-hostfix", "java8-layer", "image-layer",
      "lambda/java:8.al2023 + layer in /opt + wrapper, function adds assumeOriginalHostName", PQ,
      doc=DOC + " Packaging table: Lambda layer (java8.al2023): wrapper does not add the flag twice", env={"JAVA_TOOL_OPTIONS": J8_HOST.strip()})


# ---------------------------------------------------------------- ECS (Fargate and EC2 launch type)
def ecs(id, compute, image, cmd, mode, title, expect, env=None, doc=DOC + " Packaging table: Fargate, ECS, EKS"):
    cases.append({"id": id, "compute": compute, "mode": mode, "title": title, "doc": doc, "expect": expect,
                  "runtime_label": image + " " + cmd[0],
                  "ecs": {"image": image, "command": cmd, "env": env or {}}})


CP = ["java", "-cp", "/app", "Probe"]
CP_STATIC = ["java", "-cp", "/app:/opt/pq-tls/*", "Probe"]
for v in ("8", "11", "17", "21", "25"):
    img = "pqc-java:corretto" + v
    ecs("java-fargate-corretto%s-baseline" % v, "ecs-fargate", img, CP, "baseline", "Fargate amazoncorretto:%s, no change" % v,
        {"25": PQ}.get(v, CLASSICAL), doc=DOC + " By JDK and compute type (Fargate column)")
    if v == "8":
        cases[-1]["title"] += " (8u512 offers TLS 1.3, classical)"
        cases[-1]["finding"] = FINDING_J8_PROTO
    if v != "25":
        ecs("java-fargate-corretto%s-agent" % v, "ecs-fargate", img, CP, "agent",
            "Fargate amazoncorretto:%s + kit v2 via task-definition JAVA_TOOL_OPTIONS (taskdef.json)%s" % (v, " + TLSv1.3 flag" if v == "8" else ""),
            PQ, env={"JAVA_TOOL_OPTIONS": KIT_OPT + (J8 if v == "8" else "")}, doc=DOC + " taskdef.json")
        if v == "8":
            j8finding(cases[-1])
            ecs("java-fargate-corretto8-agent-hostfix", "ecs-fargate", img, CP, "agent",
                "Fargate amazoncorretto:8 + kit v2 + TLSv1.3 flag + assumeOriginalHostName", PQ,
                env={"JAVA_TOOL_OPTIONS": KIT_OPT + J8 + J8_HOST}, doc=DOC + " taskdef.json (JVM flags as fixed)")
            ecs("java-fargate-corretto8-agent-noproto", "ecs-fargate", img, CP, "agent",
                "Fargate amazoncorretto:8 + kit v2 + assumeOriginalHostName, WITHOUT the TLSv1.3 flag", PQ,
                env={"JAVA_TOOL_OPTIONS": KIT_OPT + J8_HOST}, doc=DOC + " JVM flags: jdk.tls.client.protocols")
            cases[-1]["finding"] = FINDING_J8_PROTO
ecs("java-fargate-corretto21-agent-ec", "ecs-fargate", "pqc-java:corretto21", CP, "agent",
    "Fargate corretto 21 + kit v2, EC client keystore", PQ, env=dict(EC_KS, JAVA_TOOL_OPTIONS=KIT_OPT), doc=DOC + " E")
ecs("java-fargate-corretto21-agent-image", "ecs-fargate", "pqc-java:corretto21-agent-image", CP, "agent",
    "Fargate image built from Dockerfile.jdk21-agent (ENV JAVA_TOOL_OPTIONS, USER 1000)", PQ, doc=DOC + " Dockerfile.jdk21-agent")
for t in ("temurin21", "corretto17", "corretto21"):
    ecs("java-fargate-%s-static" % t, "ecs-fargate", "pqc-java:%s-static" % t, CP_STATIC, "static",
        "Fargate %s + Dockerfile.static (bc-static.security + BC jars on -cp)" % t, PQ, doc=DOC + " Dockerfile.static")
ecs("java-fargate-corretto21-static-ec", "ecs-fargate", "pqc-java:corretto21-static", CP_STATIC, "static",
    "Fargate corretto21 static registration, EC client cert (PKIX line in bc-static.security)", PQ, env=EC_KS,
    doc=DOC + " Packaging table: 'the PKIX line in this file was not run separately'")
for v in ("17", "21", "25"):
    j = "/usr/lib/jvm/jre-%s/bin/java" % v
    ecs("java-fargate-al2023-j%s-baseline" % v, "ecs-fargate", "pqc-java:al2023", [j, "-cp", "/app", "Probe"], "baseline",
        "Fargate AL2023 + dnf java-%s-amazon-corretto-headless" % v, PQ if v == "25" else CLASSICAL)
ecs("java-fargate-al2023-j21-agent", "ecs-fargate", "pqc-java:al2023", ["/usr/lib/jvm/jre-21/bin/java", "-cp", "/app", "Probe"],
    "agent", "Fargate AL2023 dnf Corretto 21 + kit v2 (task env)", PQ, env={"JAVA_TOOL_OPTIONS": KIT_OPT})
# ECS on EC2 launch type: same images, same results expected (the container's JDK decides, not the host)
ecs("java-ecsec2-corretto21-baseline", "ecs-ec2", "pqc-java:corretto21", CP, "baseline", "ECS EC2 launch type, corretto 21", CLASSICAL)
ecs("java-ecsec2-corretto21-agent", "ecs-ec2", "pqc-java:corretto21", CP, "agent", "ECS EC2 launch type, corretto 21 + kit v2", PQ,
    env={"JAVA_TOOL_OPTIONS": KIT_OPT})
ecs("java-ecsec2-corretto25-baseline", "ecs-ec2", "pqc-java:corretto25", CP, "baseline", "ECS EC2 launch type, corretto 25", PQ)
ecs("java-ecsec2-corretto17-static", "ecs-ec2", "pqc-java:corretto17-static", CP_STATIC, "static",
    "ECS EC2 launch type, corretto 17 static registration", PQ)
ecs("java-ecsec2-corretto8-agent", "ecs-ec2", "pqc-java:corretto8", CP, "agent", "ECS EC2 launch type, corretto 8 + kit v2 + TLSv1.3 flag", PQ,
    env={"JAVA_TOOL_OPTIONS": KIT_OPT + J8})
j8finding(cases[-1])


# ---------------------------------------------------------------- EC2 (golden AMIs)
def ec2(id, ami, run, mode, title, expect, setup=(), env=None, doc=DOC + " Packaging table: EC2"):
    cases.append({"id": id, "compute": "ec2", "mode": mode, "title": title, "doc": doc, "expect": expect,
                  "runtime_label": "%s %s" % (ami, run.split()[0]),
                  "ec2": {"ami": ami, "run": run, "setup": list(setup), "env": env or {}}})


P = "-cp /opt/pqc/java Probe"
JVM = "/usr/lib/jvm/jre-%s/bin/java"   # alternatives link to the Corretto package (arch-independent)
for v in ("11", "17", "21"):
    ec2("java-ec2-al2023-j%s-baseline" % v, "pqc-al2023", "%s %s" % (JVM % v, P), "baseline",
        "EC2 AL2023 Corretto %s (dnf), no change" % v, CLASSICAL)
    ec2("java-ec2-al2023-j%s-agent" % v, "pqc-al2023", "%s %s" % (JVM % v, P), "agent",
        "EC2 AL2023 Corretto %s + kit v2 (systemd Environment= equivalent)" % v, PQ, env={"JAVA_TOOL_OPTIONS": KIT_EC2})
ec2("java-ec2-al2023-j25-baseline", "pqc-al2023", "%s %s" % (JVM % "25", P), "baseline", "EC2 AL2023 Corretto 25 package", PQ)
ec2("java-ec2-al2023-default-java", "pqc-al2023", "java " + P, "baseline",
    "EC2 AL2023 'java' on PATH with 11/17/21/25 installed (alternatives picks the highest: 25)", PQ)
ec2("java-ec2-al2023-j21-agent-ec", "pqc-al2023", "%s %s" % (JVM % "21", P), "agent", "EC2 AL2023 Corretto 21 + kit v2, EC client keystore",
    PQ, env={"JAVA_TOOL_OPTIONS": KIT_EC2, "PQC_JAVA_CLIENT_KS": "/opt/pqc/java/client-ec.p12"}, doc=DOC + " E")
for v in ("11", "17"):
    ec2("java-ec2-al2-j%s-baseline" % v, "pqc-al2", "%s %s" % (JVM % v, P), "baseline", "EC2 Amazon Linux 2 Corretto %s, no change" % v, CLASSICAL)
    ec2("java-ec2-al2-j%s-agent" % v, "pqc-al2", "%s %s" % (JVM % v, P), "agent", "EC2 Amazon Linux 2 Corretto %s + kit v2" % v, PQ,
        env={"JAVA_TOOL_OPTIONS": KIT_EC2})

write("java", cases)
