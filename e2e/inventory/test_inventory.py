"""Test configs/inventory/pq_inventory.py against the e2e LocalStack (source e2e/env.sh first).

Creates one fixture per classification row (Lambda zip functions, ECS task
definitions, ALB listeners, a Classic LB, an API Gateway REST domain and an HTTP API), runs the
inventory, checks every fixture's status, then deletes the fixtures. Needs boto3.

  source e2e/env.sh && python3 e2e/inventory/test_inventory.py
"""
import io, json, os, subprocess, sys, tempfile, zipfile

import boto3

R = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
P = "pqinv-"
ROLE = "arn:aws:iam::000000000000:role/pqinv"
s = boto3.session.Session()
lam, ecs, elb, elbc, ec2 = (s.client(n) for n in ("lambda", "ecs", "elbv2", "elb", "ec2"))
apigw, apigw2 = s.client("apigateway"), s.client("apigatewayv2")

buf = io.BytesIO()
with zipfile.ZipFile(buf, "w") as z:
    z.writestr("index.py", "def handler(e, c):\n    return 1\n")
ZIP = buf.getvalue()
CONF = {"OPENSSL_CONF": "/var/task/pq-tls/openssl-pq.cnf"}
NODECONF = {"OPENSSL_CONF": "/var/task/pq-tls/openssl-pq-node.cnf"}
WRAP = {"AWS_LAMBDA_EXEC_WRAPPER": "/opt/pq-tls/wrapper"}
EGRESS = "arn:aws:lambda:us-east-1:000000000000:layer:pq-egress:1"

# name: (runtime, env, layers, expected status)
LAMBDAS = {
    "py313-baseline": ("python3.13", {}, [], "fixable"),
    "py313-conf": ("python3.13", CONF, [], "pq-fixed"),
    "py311-baseline": ("python3.11", {}, [], "upgrade"),
    "py311-shim": ("python3.11", {"PYTHONPATH": "/var/task/pq-tls/pyshim"}, [], "bridge"),
    "py39-layer": ("python3.9", WRAP, [], "bridge"),
    "node22-baseline": ("nodejs22.x", {}, [], "fixable"),
    "node22-conf": ("nodejs22.x", NODECONF, [], "pq-fixed"),
    "node24-layer": ("nodejs24.x", WRAP, [], "pq-fixed"),
    "node20-baseline": ("nodejs20.x", {}, [], "upgrade"),
    "node18-egress": ("nodejs18.x", {}, [EGRESS], "bridge"),
    "java21-baseline": ("java21", {}, [], "fixable"),
    "java17-agent": ("java17", {"JAVA_TOOL_OPTIONS": "-javaagent:/var/task/pq-tls/pq-tls-agent.jar"}, [], "pq-fixed"),
    "java25": ("java25", {}, [], "pq"),
    "dotnet8-baseline": ("dotnet8", {}, [], "fixable"),
    "dotnet10-conf": ("dotnet10", CONF, [], "pq-fixed"),
    "go-al2023": ("provided.al2023", {}, [], "scan"),
    "go-godebug": ("provided.al2", {"GODEBUG": "tlsmlkem=1"}, [], "pq-fixed"),
}
TASKS = {  # family: (image, env, expected)
    "py-trixie": ("python:3.13-slim-trixie", {}, "pq"),
    "py-bookworm": ("python:3.12-slim-bookworm", {}, "scan"),
    "al2023-conf": ("public.ecr.aws/amazonlinux/amazonlinux:2023", CONF, "pq-fixed"),
}


def make():
    global EGRESS
    EGRESS = lam.publish_layer_version(LayerName="pq-egress", Content={"ZipFile": ZIP})["LayerVersionArn"]
    LAMBDAS["node18-egress"] = LAMBDAS["node18-egress"][:2] + ([EGRESS], "bridge")
    for name, (rt, env, layers, _) in LAMBDAS.items():
        lam.create_function(FunctionName=P + name, Runtime=rt, Role=ROLE, Handler="index.handler",
                            Code={"ZipFile": ZIP}, Environment={"Variables": env}, Layers=layers)
    for fam, (img, env, _) in TASKS.items():
        ecs.register_task_definition(family=P + fam, requiresCompatibilities=["FARGATE"], networkMode="awsvpc",
                                     cpu="256", memory="512", containerDefinitions=[{
                                         "name": "app", "image": img, "essential": True,
                                         "environment": [{"name": k, "value": v} for k, v in env.items()]}])
    vpc = ec2.create_vpc(CidrBlock="10.91.0.0/16")["Vpc"]["VpcId"]
    subs = [ec2.create_subnet(VpcId=vpc, CidrBlock=f"10.91.{i}.0/24", AvailabilityZone=f"us-east-1{z}")["Subnet"]["SubnetId"]
            for i, z in ((1, "a"), (2, "b"))]
    lb = elb.create_load_balancer(Name=P + "alb", Subnets=subs, Type="application")["LoadBalancers"][0]["LoadBalancerArn"]
    tg = elb.create_target_group(Name=P + "tg", Protocol="HTTP", Port=80, VpcId=vpc)["TargetGroups"][0]["TargetGroupArn"]
    d = tempfile.mkdtemp()
    subprocess.run(["openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256", "-nodes",
                    "-subj", "/CN=pqinv.example.com", "-days", "2", "-keyout", d + "/k.pem", "-out", d + "/c.pem"],
                   check=True, capture_output=True)
    cert = s.client("acm").import_certificate(Certificate=open(d + "/c.pem", "rb").read(),
                                              PrivateKey=open(d + "/k.pem", "rb").read())["CertificateArn"]
    for port, pol in ((443, "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"), (8443, "ELBSecurityPolicy-2016-08")):
        elb.create_listener(LoadBalancerArn=lb, Protocol="HTTPS", Port=port, SslPolicy=pol,
                            Certificates=[{"CertificateArn": cert}],
                            DefaultActions=[{"Type": "forward", "TargetGroupArn": tg}])
    elbc.create_load_balancer(LoadBalancerName=P + "clb", Listeners=[{"Protocol": "HTTP", "LoadBalancerPort": 80,
                              "InstanceProtocol": "HTTP", "InstancePort": 80}], AvailabilityZones=["us-east-1a"])
    apigw.create_domain_name(domainName="pqinv.example.com", regionalCertificateArn=cert,
                             endpointConfiguration={"types": ["REGIONAL"]}, securityPolicy="TLS_1_2")
    apigw2.create_api(Name=P + "http", ProtocolType="HTTP")
    return {"vpc": vpc, "subnets": subs, "lb": lb, "tg": tg, "cert": cert}


def clean(st):
    for name in LAMBDAS:
        try: lam.delete_function(FunctionName=P + name)
        except Exception: pass
    for fam in TASKS:
        for arn in ecs.list_task_definitions(familyPrefix=P + fam)["taskDefinitionArns"]:
            ecs.deregister_task_definition(taskDefinition=arn)
    for f, kw in ((elb.delete_load_balancer, {"LoadBalancerArn": st.get("lb")}),
                  (elb.delete_target_group, {"TargetGroupArn": st.get("tg")}),
                  (elbc.delete_load_balancer, {"LoadBalancerName": P + "clb"}),
                  (apigw.delete_domain_name, {"domainName": "pqinv.example.com"})):
        try: f(**kw)
        except Exception: pass
    try:
        for v in lam.list_layer_versions(LayerName="pq-egress")["LayerVersions"]:
            lam.delete_layer_version(LayerName="pq-egress", VersionNumber=v["Version"])
    except Exception: pass
    for a in apigw2.get_apis()["Items"]:
        if a["Name"].startswith(P): apigw2.delete_api(ApiId=a["ApiId"])
    if st.get("cert"):
        try: s.client("acm").delete_certificate(CertificateArn=st["cert"])
        except Exception: pass
    for sn in st.get("subnets", []):
        try: ec2.delete_subnet(SubnetId=sn)
        except Exception: pass
    if st.get("vpc"):
        try: ec2.delete_vpc(VpcId=st["vpc"])
        except Exception: pass


st = {}
try:
    st = make()
    out = subprocess.run([sys.executable, os.path.join(R, "configs/inventory/pq_inventory.py"), "--account-label", "e2e"],
                         capture_output=True, text=True, check=True)
    rows = [json.loads(l) for l in out.stdout.splitlines()]
    got = {}
    for r in rows:
        key = r["arn"]
        got[key] = r["status"]
    want = {}
    for name, (*_, exp) in LAMBDAS.items():
        want[next(k for k in got if k.endswith(":function:" + P + name))] = exp
    for fam, (*_, exp) in TASKS.items():
        want[next(k for k in got if f"task-definition/{P}{fam}:" in k)] = exp
    lst = {r["runtime"]: r["arn"] for r in rows if r["resource_type"] == "elbv2-listener"}
    want[lst["ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"]] = "pq"
    want[lst["ELBSecurityPolicy-2016-08"]] = "fixable"
    want[P + "clb"] = "blocked"
    want["pqinv.example.com"] = "fixable"
    want[next(r["arn"] for r in rows if r["resource_type"] == "apigw-http")] = "blocked"
    bad = {k: (got.get(k), v) for k, v in want.items() if got.get(k) != v}
    for k, v in want.items():
        print(f"{'ok  ' if k not in bad else 'FAIL'} {v:9} {got.get(k)!s:9} {k.split(':')[-1][-60:]}")
    print(out.stderr.strip())
    print(f"INVENTORY CHECK {'PASS' if not bad else 'FAIL'}: {len(want) - len(bad)}/{len(want)}")
    sys.exit(1 if bad else 0)
finally:
    clean(st)
