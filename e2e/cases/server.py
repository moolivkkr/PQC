"""Load balancer target leg (server role) -> cases/server.json. Run: python3 cases/server.py

The workload is the TLS server (an HTTPS target behind an ALB, or behind an NLB TLS listener); the observer dials back
as the load balancer would (observer/main.go, /dialback). Targets:
  alb-pq       backend policy AWS uses when the listener policy is PQ (ELBSecurityPolicy-TLS13-1-0-PQ-2025-09)
  alb-classic  backend policy for any other listener policy (ELBSecurityPolicy-2016-08: TLS 1.0-1.2)
Question answered: after the listener moves to a PQ policy, is the load balancer -> container hop PQ, and does the
language fix (not the certificate) decide it? Images: build/server.sh (client image + clients/server/*).
"""
from lib import write

TARGETS = ["alb-pq", "alb-classic"]
PQ = {"alb-pq": {"ok": True, "pq": True, "tls_version": "TLSv1.3"},
      "alb-classic": {"ok": True, "pq": False, "tls_version": "TLSv1.2"}}
CLASSICAL = {"alb-pq": {"ok": True, "pq": False, "tls_version": "TLSv1.3"},
             "alb-classic": {"ok": True, "pq": False, "tls_version": "TLSv1.2"}}

cases = []


def case(lang, cid, image, cmd, mode, expect, title, doc, env=None, compute="ecs-fargate", entrypoint=None):
    c = {"id": "srv-%s-%s" % (lang, cid), "lang": lang, "role": "server", "compute": compute, "mode": mode,
         "title": title, "doc": doc, "targets": TARGETS, "expect": expect,
         "ecs": {"image": "pqc-server:" + image, "command": cmd, "env": env or {}}}
    if entrypoint:
        c["ecs"]["entrypoint"] = entrypoint
    cases.append(c)


# Python: ssl module server (uvicorn / gunicorn / hypercorn use the same module)
PYDOC = "src/04-python.md B. Simple server"
case("python", "al2023-py312-baseline", "python-al2023", ["python3.12", "/srv-pqc/server.py"], "baseline", CLASSICAL,
     "AL2023 image, Python 3.12, no fix: target leg stays classical under a PQ listener policy", PYDOC)
case("python", "al2023-py312-conf", "python-al2023", ["python3.12", "/srv-pqc/server.py"], "config", PQ,
     "AL2023 image + OPENSSL_CONF=openssl-pq.cnf in the task definition", PYDOC, {"OPENSSL_CONF": "/etc/pq-tls/openssl-pq.cnf"})
case("python", "al2023-py312-policy", "python-al2023-policy", ["python3.12", "/srv-pqc/server.py"], "crypto-policy", PQ,
     "AL2023 image with DEFAULT:PQ crypto policy", PYDOC)
case("python", "trixie-py313", "python-lib-3.13-slim-trixie", ["python", "/srv-pqc/server.py"], "baseline", PQ,
     "python:3.13-slim-trixie (OpenSSL 3.5): PQ with no change", PYDOC)
case("python", "bookworm-py312", "python-lib-3.12-slim-bookworm", ["python", "/srv-pqc/server.py"], "baseline", CLASSICAL,
     "python:3.12-slim-bookworm (OpenSSL 3.0): classical; fix = change base image", PYDOC)
case("python", "al2023-py312-conf", "python-al2023", ["python3.12", "/srv-pqc/server.py"], "config", PQ,
     "ECS on EC2: AL2023 image + OPENSSL_CONF", PYDOC, {"OPENSSL_CONF": "/etc/pq-tls/openssl-pq.cnf"}, compute="ecs-ec2")

# Node.js: https.createServer
NDOC = "src/05-nodejs.md B. Simple server"
case("node", "lib-24-slim", "node-lib-24-slim", ["node", "/srv-pqc/server.js"], "baseline", PQ,
     "node:24-slim (bundled OpenSSL 3.5): PQ with no change", NDOC)
case("node", "lib-20-slim", "node-lib-20-slim", ["node", "/srv-pqc/server.js"], "baseline", CLASSICAL,
     "node:20-slim (bundled OpenSSL 3.0): classical; fix = upgrade", NDOC)
case("node", "al2023-n22-baseline", "node-al2023", ["node-22", "/srv-pqc/server.js"], "baseline", CLASSICAL,
     "AL2023 dnf nodejs22, no fix: classical", NDOC)
case("node", "al2023-n22-conf", "node-al2023", ["node-22", "/srv-pqc/server.js"], "config", PQ,
     "AL2023 dnf nodejs22 + OPENSSL_CONF=openssl-pq-node-system.cnf", NDOC, {"OPENSSL_CONF": "/etc/app/openssl-pq-node-system.cnf"})
case("node", "al2023-n20-conf", "node-al2023", ["node-20", "/srv-pqc/server.js"], "config", PQ,
     "AL2023 dnf nodejs20 (system OpenSSL 3.5.8) + OPENSSL_CONF: PQ", NDOC, {"OPENSSL_CONF": "/etc/app/openssl-pq-node-system.cnf"})
case("node", "al2023-n22-policy", "node-al2023-policy", ["node-22", "/srv-pqc/server.js"], "crypto-policy", PQ,
     "AL2023 dnf nodejs22 with DEFAULT:PQ crypto policy", NDOC)
case("node", "lib-24-slim", "node-lib-24-slim", ["node", "/srv-pqc/server.js"], "baseline", PQ,
     "ECS on EC2: node:24-slim", NDOC, compute="ecs-ec2")

# Go: net/http ListenAndServeTLS, default tls.Config
GDOC = "src/03-go.md B. Simple server"
case("go", "go126", "go-distroless", ["/srv-pqc/server-1.26"], "baseline", PQ,
     "Go 1.26 toolchain, go 1.26 line: PQ by default", GDOC)
case("go", "go126-mod123", "go-distroless", ["/srv-pqc/server-1.26-go1.23"], "baseline", CLASSICAL,
     "Go 1.26 toolchain, go 1.23 line (tlsmlkem=0): classical", GDOC)
case("go", "go126-mod123-godebug", "go-distroless", ["/srv-pqc/server-1.26-go1.23"], "godebug", PQ,
     "Same binary + GODEBUG=tlsmlkem=1,tlssecpmlkem=1 in the task definition", GDOC, {"GODEBUG": "tlsmlkem=1,tlssecpmlkem=1"})
case("go", "go123", "go-distroless", ["/srv-pqc/server-1.23"], "baseline", CLASSICAL,
     "Go 1.23 (Kyber draft only): classical; fix = rebuild with 1.26", GDOC)
case("go", "go126", "go-distroless", ["/srv-pqc/server-1.26"], "baseline", PQ,
     "ECS on EC2: Go 1.26", GDOC, compute="ecs-ec2")

# Java: HttpsServer with the default provider and KeyManagerFactory algorithm
JDOC = "src/06-java.md B. Simple server"
KIT = "-Djava.security.properties=/opt/pq-tls/pq-tls.security -javaagent:/opt/pq-tls/pq-tls-agent.jar"
J = ["java", "-cp", "/srv-pqc", "Server"]
case("java", "corretto21-baseline", "java-corretto21", J, "baseline", CLASSICAL, "Corretto 21, no kit: classical", JDOC)
case("java", "corretto21-agent", "java-corretto21", J, "agent", PQ, "Corretto 21 + kit v2 in JAVA_TOOL_OPTIONS", JDOC,
     {"JAVA_TOOL_OPTIONS": KIT})
case("java", "corretto17-agent", "java-corretto17", J, "agent", PQ, "Corretto 17 + kit v2", JDOC, {"JAVA_TOOL_OPTIONS": KIT})
case("java", "corretto8-baseline", "java-corretto8", J, "baseline", CLASSICAL, "Corretto 8u512, no kit: classical", JDOC)
case("java", "corretto8-agent", "java-corretto8", J, "agent", PQ,
     "Corretto 8 + kit v2 with the Java 8 flags (server side not covered by the tab before this case)", JDOC,
     {"JAVA_TOOL_OPTIONS": KIT + " -Djdk.tls.client.protocols=TLSv1.3,TLSv1.2 -Dorg.bouncycastle.jsse.client.assumeOriginalHostName=true"})
case("java", "corretto25", "java-corretto25", J, "baseline", PQ, "Corretto 25.0.5: PQ by default", JDOC)
case("java", "corretto21-agent", "java-corretto21", J, "agent", PQ, "ECS on EC2: Corretto 21 + kit v2", JDOC,
     {"JAVA_TOOL_OPTIONS": KIT}, compute="ecs-ec2")

# .NET: SslStream server (Kestrel's TLS layer)
DDOC = "src/07-dotnet.md B. Simple server"
N8, N10 = ["/srv-pqc/net8/server.dll"], ["/srv-pqc/net10/server.dll"]
case("dotnet", "runtime-80", "dotnet-mcr-runtime-8.0", N8, "baseline", CLASSICAL,
     "mcr runtime:8.0 (Debian 12, OpenSSL 3.0): classical; fix = change image", DDOC, entrypoint=["dotnet"])
case("dotnet", "runtime-100-alpine", "dotnet-mcr-runtime-10.0-alpine", N10, "baseline", PQ,
     "mcr runtime:10.0-alpine (OpenSSL 3.5): PQ with no change", DDOC, entrypoint=["dotnet"])
case("dotnet", "aspnet-100-resolute", "dotnet-mcr-aspnet-10.0-resolute", N10, "baseline", PQ,
     "mcr aspnet:10.0-resolute (Ubuntu 26.04): PQ with no change", DDOC, entrypoint=["dotnet"])
case("dotnet", "al2023-net8-baseline", "dotnet-al2023", N8, "baseline", CLASSICAL, "AL2023 + .NET 8, no fix: classical",
     DDOC, entrypoint=["dotnet"])
case("dotnet", "al2023-net8-conf", "dotnet-al2023", N8, "config", PQ, "AL2023 + .NET 8 + OPENSSL_CONF", DDOC,
     {"OPENSSL_CONF": "/etc/pq-tls/openssl-pq.cnf"}, entrypoint=["dotnet"])
case("dotnet", "al2023-net8-policy", "dotnet-al2023-policy", N8, "crypto-policy", PQ, "AL2023 + .NET 8 with DEFAULT:PQ",
     DDOC, entrypoint=["dotnet"])
case("dotnet", "runtime-100-alpine", "dotnet-mcr-runtime-10.0-alpine", N10, "baseline", PQ, "ECS on EC2: 10.0-alpine",
     DDOC, entrypoint=["dotnet"], compute="ecs-ec2")

for c in cases:
    if c["compute"] == "ecs-ec2":
        c["id"] = c["id"].replace("srv-%s-" % c["lang"], "srv-%s-ecsec2-" % c["lang"], 1)
    else:
        c["id"] = c["id"].replace("srv-%s-" % c["lang"], "srv-%s-fargate-" % c["lang"], 1)
write("server", cases, default_targets=TARGETS)
