"""Write src/24-appendix-tests.md from the latest e2e results and the test folders.

Usage: python3 -I build/gen-appendix-tests.py <pqc repo dir>
Links use REPO/<path>; build/combine.py turns them into repository links.
"""
import collections, json, os, sys

R = sys.argv[1]
res = json.load(open(os.path.join(R, "e2e/results/latest/results.json")))
rows, run = res["results"], (res.get("run_id") or "")
if not run:
    run = rows[0]["full_id"].split("-")[0]
COMP = [("lambda", "Lambda"), ("ecs-fargate", "ECS Fargate"), ("ecs-ec2", "ECS on EC2"), ("ec2", "EC2")]
MODES = {
    "baseline": "no change: the runtime's default (expected classical where the paper says so)",
    "config": "OpenSSL config file and `OPENSSL_CONF`",
    "crypto-policy": "`update-crypto-policies --set DEFAULT:PQ` (image or host)",
    "bundled": "kit files bundled in the Lambda package",
    "layer": "the `pq-tls` layer and `AWS_LAMBDA_EXEC_WRAPPER`",
    "extension": "the `pq-egress` Lambda extension",
    "agent": "kit v1 or v2 Java agent (Bouncy Castle JSSE)",
    "static": "static `java.security` Bouncy Castle entry",
    "godebug": "`GODEBUG=tlsmlkem=1` or a `//go:debug` directive",
    "go-line": "`go` line in `go.mod` below and above 1.24",
    "fips": "FIPS modes (Go FIPS 140-3, boringcrypto, Java and .NET FIPS settings)",
    "image-baseline": "Lambda container image, unchanged",
    "image-fixed": "Lambda container image with the fix in the Dockerfile",
    "image": "container image variants",
    "image-layer": "Lambda container image with the layer contents",
    "settings": "explicit TLS settings that block PQ (case F)",
    "trust": "custom CA trust (case D)",
    "mtls": "mutual TLS (case E)",
    "pinning": "certificate or key pinning (case I)",
    "library": "libraries with their own TLS stack (case H)",
    "code": "a code-level group setting",
    "distro-toolchain": "distro-packaged toolchain or runtime",
}
LANG = {
    "go": ("Go", "ch-03-go", "e2e/clients/go/probe.go", "e2e/clients/server/go/main.go", "tests/deep/go/",
           ["tests/lambda/goprobe/", "tests/lambda/run-dotnet-go.sh"], "configs/go/"),
    "python": ("Python", "ch-04-python", "e2e/clients/python/probe.py", "e2e/clients/server/server.py",
               "tests/deep/python/", ["tests/lambda/client.py", "tests/lambda/run-matrix.sh",
                                      "tests/lambda/run-py-legacy.sh", "tests/lambda/al2023-python-test.sh"],
               "configs/python/"),
    "node": ("Node.js", "ch-05-nodejs", "e2e/clients/node/index.js", "e2e/clients/server/server.js",
             "tests/deep/node/", ["tests/lambda/client.js", "tests/lambda/run-matrix.sh"], "configs/nodejs/"),
    "java": ("Java", "ch-06-java", "e2e/clients/java/Probe.java", "e2e/clients/server/java/Server.java",
             "tests/deep/java/", ["tests/lambda/Client.java", "tests/lambda/agent/", "tests/lambda/run-java-al2023.sh",
                                  "kit/java-v2/"], "configs/java/"),
    "dotnet": (".NET", "ch-07-dotnet", "e2e/clients/dotnet/Probe.cs", "e2e/clients/server/dotnet/Server.cs",
               "tests/deep/dotnet/", ["tests/lambda/dotnet/", "tests/lambda/run-dotnet-go.sh"], "configs/dotnet/"),
}


def link(p):
    ok = os.path.exists(os.path.join(R, p.rstrip("/")))
    if not ok:
        sys.exit("missing path " + p)
    return f"[{p}](REPO/{p})"


def pq(x, t):
    return bool(((x["targets"].get(t) or {}).get("client") or {}).get("pq"))


def tls12(x):
    c = (x["targets"].get("alb-classic") or {}).get("client") or {}
    return c.get("ok") and c.get("tls_version") == "TLSv1.2" and not c.get("pq")


def mldsa(x):
    g = lambda t: (x["targets"].get(t) or {}).get("client") or {}
    d, o, m = g("mldsa-dual"), g("mldsa-only"), g("mldsa-mtls")
    if not d:
        return None
    if d.get("ok") and d.get("server_cert") == "mldsa":
        return "full" if m.get("ok") else "server"
    return "ecdsa" if d.get("ok") else "fail"


cl = [x for x in rows if x.get("role") == "client"]
srv = [x for x in rows if x.get("role") == "server"]
det = [x for x in rows if x["compute"] in ("cloudwatch-logs", "observer")]
passed = sum(x["verdict"] == "PASS" for x in rows)
out = [f"""# Appendix A. What is tested, per language

Every result below comes from the LocalStack Pro end-to-end suite, run {run} (2026-11-16): {len(rows)} cases, {passed} passed ({len(cl)} client cases, {len(srv)} load balancer target cases and {len(det)} detection checks). Earlier container and Lambda-emulator tests (2026-11-12 to 2026-11-14) are listed per language under "Earlier tests". Nothing here ran on real AWS, on x86_64 or through a real ALB or NLB listener.

**How a case works.** Each case deploys a real Lambda function, ECS task or EC2 instance in LocalStack, with the language runtime and the fix under test. Its probe connects to a TLS observer that records what the client offered and negotiated. The probe sets no TLS options itself, so the result reflects the runtime and the fix. Each case is graded against the expectation written in its case file, which follows this paper. PASS means the observed behaviour matched the expectation, so a baseline case that stays classical as documented passes.

| Observer target | Port | Accepts | Question it answers |
| --- | --- | --- | --- |
| `hybrid` | 8443 | X25519MLKEM768 first, classical groups too | Does the client negotiate PQ when it can? |
| `pqonly` | 8444 | X25519MLKEM768 only | Does the client offer ML-KEM at all? |
| `mtls` | 8445 | Hybrid, client certificate required | Does mutual TLS still work with the fix? |
| `eccert` | 8446 | Hybrid with an ECDSA server certificate | Do EC certificates work (Bouncy Castle `PKIX`)? |
| `tls12` | 8447 | TLS 1.2 only | Does the client still connect to a legacy server? |
| `mldsa-dual`, `mldsa-only`, `mldsa-mtls` | 8448 to 8450 | Dual certificate, ML-DSA only, ML-DSA client certificate | Which certificate does the client get, and can it use ML-DSA? |

Shared test code: observer {link('e2e/observer/')}, ML-DSA fixture {link('e2e/mldsa/server.py')}, certificates {link('e2e/certs/gen.sh')} and {link('e2e/certs/gen-mldsa.sh')}, case framework {link('e2e/cases/lib.py')}, ML-DSA expectations {link('e2e/cases/mldsa_rules.py')}, runner {link('e2e/run.sh')}, Lambda layers {link('e2e/build/layers.sh')}, the `pq-egress` extension {link('e2e/lambda/extension/pq-egress/')}, ECS and EC2 deployment {link('e2e/ecs/')} and {link('e2e/ec2/')}. Every case and result: {link('e2e/results/latest/summary.md')}. How to run: {link('e2e/RUNNING.md')}.
"""]

for lang, (name, chap, probe, server, deep, lam, cfg) in LANG.items():
    xs = [x for x in cl if x["lang"] == lang]
    ss = [x for x in srv if x["lang"] == lang]
    out.append(f"## {name}\n\nDetail: [{name}](#{chap}). {len(xs)} client cases and {len(ss)} load balancer target cases; "
               f"{sum(x['verdict'] == 'PASS' for x in xs + ss)} passed.\n")
    out.append("| Compute | Cases | PQ on `hybrid` | Connected to `pqonly` | Runtimes |\n| --- | --- | --- | --- | --- |")
    for c, cn in COMP:
        cs = [x for x in xs if x["compute"] == c]
        if not cs:
            continue
        rts = sorted({x.get("runtime_label") or x.get("runtime") or "" for x in cs} - {""})
        rt = ", ".join(rts[:8]) + (f" and {len(rts) - 8} more" if len(rts) > 8 else "")
        ok_pqonly = sum(bool(((x["targets"].get("pqonly") or {}).get("client") or {}).get("ok")) for x in cs)
        out.append(f"| {cn} | {len(cs)} | {sum(pq(x, 'hybrid') for x in cs)} | {ok_pqonly} | {rt} |")
    modes = collections.Counter(x["mode"] for x in xs)
    out.append("\n**What the cases vary:** " + "; ".join(
        f"{MODES.get(m, m)} ({n})" for m, n in modes.most_common()) + ".\n")
    md = collections.Counter(mldsa(x) for x in xs)
    md.pop(None, None)
    if md:
        parts = [(md.get("full"), "used ML-DSA on all three targets"), (md.get("server"), "used ML-DSA on the server "
                 "targets but could not load an ML-DSA client key"), (md.get("ecdsa"), "got ECDSA from the dual server "
                 "and failed the ML-DSA-only targets"), (md.get("fail"), "failed every target for reasons unrelated to ML-DSA")]
        out.append("**ML-DSA:** " + "; ".join(f"{n} {t}" for n, t in parts if n) + ".\n")
    if ss:
        out.append(f"**Load balancer target leg:** {len(ss)} servers ({', '.join(sorted({x['compute'] for x in ss}))}); "
                   f"{sum(pq(x, 'alb-pq') for x in ss)} negotiated PQ with the ALB's PQ backend policy (the rest are "
                   f"baselines); {sum(tls12(x) for x in ss)} of {len(ss)} negotiated classical TLS 1.2 with the classic policy.\n")
    out.append("| Test component | Path |\n| --- | --- |")
    out.append(f"| Case definitions (one entry per case, with its expectation) | {link(f'e2e/cases/{lang}.py')} |")
    out.append(f"| Probe deployed in every case | {link(probe)} |")
    out.append(f"| Build and deploy script | {link(f'e2e/build/{lang}.sh')} |")
    out.append(f"| Load balancer target server | {link(server)} |")
    out.append(f"| Earlier tests: existing certificates, keystores, libraries (containers) | {link(deep)} |")
    out.append(f"| Earlier tests: Lambda base images under the Runtime Interface Emulator | {', '.join(link(p) for p in lam)} |")
    out.append(f"| Configuration and test harness files from the chapter | {link(cfg)} |\n")

out.append(f"""## Infrastructure, detection and enforcement

| Area | What was tested | Evidence | Path |
| --- | --- | --- | --- |
| Load balancers | Workload as an HTTPS target with the ALB PQ and classic backend policies ({len(srv)} cases); IaC validated with `terraform validate` and cfn-lint | e2e; static checks | {link('e2e/cases/server.py')}, {link('tests/deep/edge/')} |
| Edge and API front doors | Policy names and IaC; origin and integration legs from documentation | Static checks; Documented | {link('tests/deep/edge/')} |
| Web servers and proxies, service mesh | nginx, Apache httpd, HAProxy, Envoy 1.40 listener and upstream legs against PQ-only and classical backends; Istio charts rendered | Docker | {link('tests/deep/websrv/')} |
| Network devices, egress and IoT | Envoy and Squid egress, strongSwan, Mosquitto, wolfSSL, Zeek 8.0.10 on a pcap | Docker | {link('tests/deep/netiot/')} |
| Hosts and OS, AWS service endpoints | AL2023 crypto policies, Debian, Ubuntu, Alpine, Fedora, GnuTLS tools, OpenSSH 10, AWS CLI v2 | Docker | {link('tests/deep/hosts/')} |
| Databases and certificates | PostgreSQL, MySQL, MariaDB, Valkey servers and drivers; ML-DSA dual certificates with nginx | Docker | {link('tests/deep/data/')} |
| ML-DSA certificates across all languages | Three ML-DSA targets for every client case | e2e | {link('e2e/mldsa/server.py')}, {link('e2e/cases/mldsa_rules.py')} |
| Detection: CloudWatch Logs | Metric filter finds every classical handshake the clients reported | e2e (`detect-cloudwatch-nonpq`) | {link('e2e/runner/')} |
| Detection: server handshake log | Observer log holds every classical and TLS 1.2 handshake | e2e (`detect-server-handshake-log`) | {link('e2e/observer/')} |
| Detection: Zeek 7.2.2 | `ssl.log` `curve` and `pq` per session; three notices | e2e stack, passed 2026-11-16 | {link('e2e/zeek/check.sh')} |
| Posture inventory | 25 components classified correctly | LocalStack, passed 25/25 on 2026-11-16 | {link('e2e/inventory/test_inventory.py')}, {link('configs/inventory/pq_inventory.py')} |
| Enforcement | cfn-guard rules, OPA tests, image checks against good and bad samples | Docker | {link('tests/deep/guard/')} |

## Not tested

- Anything on real AWS: CloudTrail `keyExchange`, ALB and NLB listener legs and logs, Athena queries and dashboards, SCPs, Config rules, Guard hooks.
- x86_64: all tests ran on arm64.
- Ruby, PHP and Rust; JDK 25 builds other than Corretto and Temurin; the `pq-egress` extension for AWS SDK calls.
""")
open(os.path.join(R, "src/24-appendix-tests.md"), "w").write("\n".join(out))
print("wrote src/24-appendix-tests.md", len(cl), len(srv), len(det))
