#!/usr/bin/env python3
"""PQ TLS posture inventory for one account and region.

Reads Lambda functions, ECS task definitions, ELBv2 listeners, Classic load balancers and API Gateway
REST custom domains, classifies each against the guide's matrices, and writes one JSON line per
component (load the file into S3 and query it with Athena next to the observed signals; see
athena-views.sql). Read-only: it only calls List*/Describe*/Get*.

  python3 pq_inventory.py --out inventory.jsonl [--account-label prod-eu]

Status values: pq (PQ today), pq-fixed (our fix is applied), bridge (partial fix), fixable (one
change makes it PQ), upgrade (only a runtime or version upgrade helps), blocked (AWS offers no PQ
option), scan (metadata is not enough: scan the image or binary), n/a.
Tested against LocalStack Pro (e2e stack), not against a real AWS account.
"""
import argparse, datetime, json, re, sys

import boto3

# Lambda runtimes AWS blocks updates for on 2027-08-31 (AWS runtimes page, read 2026-11-16).
BLOCK_UPDATE = {r: "2027-08-31" for r in ("nodejs18.x", "nodejs20.x", "python3.9", "python3.10", "python3.11",
                                          "java8.al2", "java11", "java17", "provided.al2", "dotnet8")}
PQ_CONF = re.compile(r"pq", re.I)  # our files: openssl-pq.cnf, openssl-pq-node.cnf, /opt/pq-tls/...
WRAPPER = "/opt/pq-tls/wrapper"


def lang_of(runtime):
    for p, l in (("python", "python"), ("nodejs", "node"), ("java", "java"), ("dotnet", "dotnet"),
                 ("provided", "go-or-rust"), ("ruby", "ruby")):
        if runtime.startswith(p):
            return l
    return "unknown"


def lambda_status(fn):
    rt = fn.get("Runtime") or ""
    env = (fn.get("Environment") or {}).get("Variables") or {}
    layers = " ".join(l["Arn"] for l in fn.get("Layers") or [])
    wrapped = env.get("AWS_LAMBDA_EXEC_WRAPPER") == WRAPPER
    egress = "pq-egress" in layers
    conf = PQ_CONF.search(env.get("OPENSSL_CONF", "")) or "openssl-config" in env.get("NODE_OPTIONS", "")
    if fn.get("PackageType") == "Image":
        return "scan", "Container image: scan the image (OpenSSL, JDK, Node, Go build info)", "image"
    if rt.startswith("python3."):
        minor = int(rt.split(".")[1])
        if minor >= 12:
            return ("pq-fixed", "OPENSSL_CONF set to the PQ file", "config") if conf or wrapped else \
                   ("fixable", "Ship openssl-pq.cnf, set OPENSSL_CONF (or the pq-tls layer)", "config")
        if wrapped or "pyshim" in env.get("PYTHONPATH", ""):
            return "bridge", "Shim covers requests and boto3 only; upgrade to python3.12+", "shim"
        return "upgrade", "Upgrade to python3.12+ (interim: shim, layer or pq-egress)", "none"
    if rt.startswith("nodejs"):
        major = int(re.sub(r"\D", "", rt.split(".")[0]) or 0)
        if major <= 20:
            return ("bridge", "pq-egress extension for chosen calls; upgrade to nodejs22.x+", "extension") if egress \
                else ("upgrade", "Upgrade to nodejs22.x or 24.x: bundled OpenSSL has no ML-KEM", "none")
        return ("pq-fixed", "OPENSSL_CONF overrides the bootstrap group list", "config") if conf or wrapped else \
               ("fixable", "Ship openssl-pq-node.cnf, set OPENSSL_CONF (or the pq-tls layer)", "config")
    if rt.startswith("java"):
        if int(re.match(r"java(\d+)", rt).group(1)) >= 25:
            return "pq", "JDK 25.0.5+ negotiates PQ by default", "none"
        jto = env.get("JAVA_TOOL_OPTIONS", "")
        if "pq-tls-agent" in jto or wrapped:
            return "pq-fixed", "Bouncy Castle JSSE agent (kit v2)", "agent"
        return "fixable", "Add the kit v2 agent via JAVA_TOOL_OPTIONS (or the pq-tls layer), or move to java25", "agent"
    if rt.startswith("dotnet"):
        return ("pq-fixed", "OPENSSL_CONF set to the PQ file", "config") if conf or wrapped else \
               ("fixable", "Ship openssl-pq.cnf, set OPENSSL_CONF (or the pq-tls layer)", "config")
    if rt.startswith("provided"):
        if "tlsmlkem=1" in env.get("GODEBUG", ""):
            return "pq-fixed", "GODEBUG=tlsmlkem=1 (needs a Go 1.24+ build)", "godebug"
        return "scan", "Custom runtime: read the binary's build info (go version -m) or crate versions", "none"
    return "scan", "Unknown runtime", "none"


def pager(client, op, key, **kw):
    if client.can_paginate(op):
        for page in client.get_paginator(op).paginate(**kw):
            yield from page.get(key, [])
    else:
        yield from getattr(client, op)(**kw).get(key, [])


def row(kind, arn, compute, lang, runtime, status, action, fix, **extra):
    return {"resource_type": kind, "arn": arn, "compute": compute, "language": lang, "runtime": runtime,
            "status": status, "action": action, "fix": fix, "signal": "posture", **extra}


def lambdas(s):
    c = s.client("lambda")
    for fn in pager(c, "list_functions", "Functions"):
        st, action, fix = lambda_status(fn)
        rt = fn.get("Runtime") or "image"
        yield row("lambda", fn["FunctionArn"], "lambda-" + ("image" if fn.get("PackageType") == "Image" else "zip"),
                  lang_of(rt), rt, st, action, fix, block_update=BLOCK_UPDATE.get(rt), role=fn.get("Role"),
                  name=fn["FunctionName"])


def ecs(s):
    c = s.client("ecs")
    for arn in pager(c, "list_task_definitions", "taskDefinitionArns", status="ACTIVE"):
        td = c.describe_task_definition(taskDefinition=arn)["taskDefinition"]
        compute = "ecs-fargate" if "FARGATE" in (td.get("requiresCompatibilities") or []) else "ecs-ec2"
        for cd in td.get("containerDefinitions", []):
            env = {e["name"]: e["value"] for e in cd.get("environment", [])}
            img = cd.get("image", "")
            if PQ_CONF.search(env.get("OPENSSL_CONF", "")) or "pq-tls-agent" in env.get("JAVA_TOOL_OPTIONS", "") \
                    or "tlsmlkem=1" in env.get("GODEBUG", ""):
                st, action = "pq-fixed", "PQ setting in the task definition; confirm the image supports it"
            elif re.search(r"trixie|alpine3\.(2[2-9])|resolute|corretto25|temurin.?25", img):
                st, action = "pq", "Base image is PQ by default (heuristic from the tag; confirm with an image scan)"
            else:
                st, action = "scan", "Scan the image: OS OpenSSL, JDK, Node, Go build info"
            yield row("ecs-container", f"{arn}#{cd['name']}", compute, "unknown", img, st, action, "image",
                      role=td.get("taskRoleArn"), name=f"{td['family']}/{cd['name']}")


def elbv2(s):
    c = s.client("elbv2")
    for lb in pager(c, "describe_load_balancers", "LoadBalancers"):
        for li in pager(c, "describe_listeners", "Listeners", LoadBalancerArn=lb["LoadBalancerArn"]):
            if li.get("Protocol") not in ("HTTPS", "TLS"):
                continue
            pol = li.get("SslPolicy") or ""
            pq = "-PQ-" in pol
            yield row("elbv2-listener", li["ListenerArn"], lb.get("Type", "elb"), "n/a", pol,
                      "pq" if pq else "fixable", "PQ listener policy in place" if pq else
                      "Set ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09 (then the 1-3 PQ policy)", "policy")


def classic(s):
    try:
        for lb in pager(s.client("elb"), "describe_load_balancers", "LoadBalancerDescriptions"):
            yield row("classic-elb", lb["LoadBalancerName"], "elb-classic", "n/a", "classic", "blocked",
                      "Classic Load Balancer has no PQ policy: migrate to ALB or NLB", "migrate")
    except Exception as e:  # service not enabled in this region or emulator
        print("classic elb skipped:", e, file=sys.stderr)


def apigw(s):
    try:
        for d in pager(s.client("apigateway"), "get_domain_names", "items"):
            pol = d.get("securityPolicy") or "TLS_1_2"
            pq = "PQ" in pol
            yield row("apigw-rest-domain", d["domainName"], "api-gateway", "n/a", pol, "pq" if pq else "fixable",
                      "PQ policy in place" if pq else "Set SecurityPolicy_TLS13_1_2_PQ_2025_09", "policy")
        for a in pager(s.client("apigatewayv2"), "get_apis", "Items"):
            yield row("apigw-" + a.get("ProtocolType", "http").lower(), a["ApiId"], "api-gateway", "n/a",
                      a.get("ProtocolType"), "blocked", "No PQ policy for HTTP/WebSocket APIs: front with CloudFront "
                      "or a PQ ALB, or record an exception", "front")
    except Exception as e:
        print("api gateway skipped:", e, file=sys.stderr)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="-")
    ap.add_argument("--account-label", default="")
    a = ap.parse_args()
    s = boto3.session.Session()
    account = s.client("sts").get_caller_identity()["Account"]
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    out = sys.stdout if a.out == "-" else open(a.out, "w")
    counts = {}
    for gen in (lambdas, ecs, elbv2, classic, apigw):
        for r in gen(s):
            r.update(account=account, account_label=a.account_label, region=s.region_name, scanned_at=now)
            out.write(json.dumps(r) + "\n")
            counts[r["status"]] = counts.get(r["status"], 0) + 1
    print(json.dumps(counts, sort_keys=True), file=sys.stderr)


if __name__ == "__main__":
    main()
