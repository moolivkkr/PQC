"""Compute executors (Lambda, ECS Fargate, ECS EC2, EC2), grading and detection checks.

Every resource this suite creates is named pqc-* and/or tagged project=pqc-e2e; cleanup() touches nothing else.
"""
import base64
import fnmatch
import json
import os
import re
import time
import urllib.request

import boto3
from botocore.config import Config

TARGETS = ["hybrid", "pqonly", "mtls", "eccert", "tls12"]
OBS_ADMIN = os.environ.get("PQC_OBSERVER_ADMIN", "http://10.250.0.20:8080")
CFG = Config(retries={"max_attempts": 8, "mode": "standard"}, read_timeout=300, connect_timeout=10)
TAGS = [{"Key": "project", "Value": "pqc-e2e"}]
ECS_LOG_GROUP = "/pqc/ecs"


def _c(name):
    return boto3.client(name, config=CFG)


def _obs(path):
    with urllib.request.urlopen(OBS_ADMIN + path, timeout=10) as r:
        return json.loads(r.read() or b"null")


def _ts(s):
    # observer RFC3339Nano UTC -> epoch seconds
    m = re.match(r"(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(\.\d+)?Z", s)
    import calendar
    t = calendar.timegm(tuple(int(x) for x in m.groups()[:6]) + (0, 0, 0))
    return t + float(m.group(7) or 0)


def _short(case_id, n=64):
    name = "pqc-" + re.sub(r"[^A-Za-z0-9-]", "-", case_id)
    return name if len(name) <= n else name[: n - 9] + "-" + format(abs(hash(case_id)) % 16 ** 8, "08x")


class Env:
    def __init__(self, root, run_id):
        self.root, self.run_id = root, run_id
        self.art = os.path.join(root, ".work", "artifacts")
        self.lam, self.iam, self.ecs, self.ec2, self.logs, self.ecr = (
            _c("lambda"), _c("iam"), _c("ecs"), _c("ec2"), _c("logs"), _c("ecr"))
        self.layers, self.amis, self.meta = {}, {}, {"run_id": run_id}

    def prepare(self, cases):
        try:
            info = json.load(urllib.request.urlopen(os.environ["AWS_ENDPOINT_URL"] + "/_localstack/info"))
            self.meta["localstack"] = "%s %s" % (info.get("edition"), info.get("version"))
        except Exception as e:
            self.meta["localstack"] = "unknown (%s)" % e
        try:
            self.role = self.iam.create_role(RoleName="pqc-e2e-lambda", AssumeRolePolicyDocument=json.dumps({
                "Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"},
                                                        "Action": "sts:AssumeRole"}]}), Tags=TAGS)["Role"]["Arn"]
        except self.iam.exceptions.EntityAlreadyExistsException:
            self.role = self.iam.get_role(RoleName="pqc-e2e-lambda")["Role"]["Arn"]
        # Lambda layers: publish each referenced layer zip once per run
        wanted = sorted({l for c in cases if c["compute"] == "lambda" for l in c["lambda"].get("layers", [])})
        for name in wanted:
            zp = os.path.join(self.art, "layers", name + ".zip")
            v = self.lam.publish_layer_version(LayerName="pqc-" + name, Content={"ZipFile": open(zp, "rb").read()},
                                               CompatibleArchitectures=["arm64", "x86_64"])
            self.layers[name] = v["LayerVersionArn"]
        self.meta["layers"] = self.layers
        if any(c["compute"].startswith("ecs") for c in cases):
            for cl in ("pqc-fargate", "pqc-ec2"):
                self.ecs.create_cluster(clusterName=cl, tags=[{"key": "project", "value": "pqc-e2e"}])
            try:
                self.logs.create_log_group(logGroupName=ECS_LOG_GROUP)
            except self.logs.exceptions.ResourceAlreadyExistsException:
                pass
            self.registry = self.ecr.describe_registry()["registryId"]
            self.subnet = self.ec2.describe_subnets()["Subnets"][0]["SubnetId"]
        if any(c["compute"] == "ec2" for c in cases):
            for img in self.ec2.describe_images(Owners=["self", "amazon"])["Images"]:
                if img.get("Name", "").startswith("pqc-"):
                    self.amis[img["Name"]] = img["ImageId"]
            self.meta["amis"] = self.amis

    def ecr_uri(self, ref):
        """'pqc-python:al2023-py312' -> LocalStack ECR URI (build/*.sh pushed it)."""
        repo, tag = ref.split(":", 1)
        r = self.ecr.describe_repositories(repositoryNames=[repo])["repositories"][0]
        return "%s:%s" % (r["repositoryUri"], tag)


def _env_for(case, full_id):
    # server-role cases (load balancer target leg) use the same variables; PQC_TARGETS = alb-pq,alb-classic
    e = {"PQC_COMPUTE": case["compute"], "PQC_MODE": case.get("mode", "baseline"), "PQC_CASE_ID": full_id,
         "PQC_TARGETS": ",".join(case["targets"]), "PQC_OBSERVER": "pq-observer"}
    e.update(case.get(case["compute"].split("-")[0], {}).get("env", {}))
    return e


def _parse_result(text, full_id=None):
    """Last PQC_RESULT line (for this case id - LocalStack's filter_log_events ignores logStreamNamePrefix)."""
    found = None
    for line in (text or "").splitlines():
        i = line.find("PQC_RESULT ")
        if i >= 0:
            try:
                r = json.loads(line[i + len("PQC_RESULT "):])
            except ValueError:
                continue
            if full_id is None or r.get("case_id") == full_id:
                found = r
    return found


# ---------------------------------------------------------------- executors
def _wait_for_handshake_logs(env, group, full_id, want, timeout=20):
    """Deleting the function right after invoke can drop its last stdout line before LocalStack ships it to
    CloudWatch Logs (seen once: the final target's tls_handshake line never arrived). Wait until every handshake
    line of this invocation is in the log group, so the CloudWatch detection check sees what the client logged."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            evs = env.logs.filter_log_events(logGroupName=group, filterPattern='"%s"' % full_id).get("events", [])
        except Exception:
            evs = []
        if sum('"tls_handshake"' in e["message"] and full_id in e["message"] for e in evs) >= want:
            return True
        time.sleep(1)
    return False


def _run_lambda(env, case, full_id):
    spec = case["lambda"]
    fn = _short(case["id"])
    try:
        env.lam.delete_function(FunctionName=fn)
    except env.lam.exceptions.ResourceNotFoundException:
        pass
    kw = dict(FunctionName=fn, Role=env.role, Timeout=spec.get("timeout", 90), MemorySize=spec.get("memory", 512),
              Architectures=["arm64"], Environment={"Variables": _env_for(case, full_id)}, Tags={"project": "pqc-e2e"})
    if spec.get("image"):
        kw.update(PackageType="Image", Code={"ImageUri": env.ecr_uri(spec["image"])})
    else:
        kw.update(Runtime=spec["runtime"], Handler=spec["handler"],
                  Code={"ZipFile": open(os.path.join(env.art, "lambda", spec["zip"]), "rb").read()},
                  Layers=[env.layers[l] for l in spec.get("layers", [])])
    env.lam.create_function(**kw)
    env.lam.get_waiter("function_active_v2").wait(FunctionName=fn, WaiterConfig={"Delay": 2, "MaxAttempts": 150})
    r = env.lam.invoke(FunctionName=fn, Payload=json.dumps({"case_id": full_id, "targets": case["targets"]}),
                       LogType="Tail")
    payload = r["Payload"].read().decode()
    log = base64.b64decode(r.get("LogResult", "")).decode(errors="replace")
    client = None
    if not r.get("FunctionError"):
        client = json.loads(payload)
        if isinstance(client, str):
            client = json.loads(client)
    notes = [l.strip() for l in log.splitlines() if "pq-tls" in l or "pq-egress" in l][:6]
    if client:
        _wait_for_handshake_logs(env, "/aws/lambda/" + fn, full_id, len(client.get("results") or {}))
    if not spec.get("keep"):
        env.lam.delete_function(FunctionName=fn)
    return client, {"function_error": r.get("FunctionError"), "payload": payload[:2000] if r.get("FunctionError") else None,
                    "log_notes": notes}


def _run_ecs(env, case, full_id):
    spec = case["ecs"]
    fargate = case["compute"] == "ecs-fargate"
    fam = _short(case["id"], 255)
    cdef = {"name": "probe", "image": env.ecr_uri(spec["image"]), "essential": True, "memory": 512,
            "environment": [{"name": k, "value": v} for k, v in _env_for(case, full_id).items()],
            "logConfiguration": {"logDriver": "awslogs", "options": {
                "awslogs-group": ECS_LOG_GROUP, "awslogs-region": "us-east-1", "awslogs-stream-prefix": fam}}}
    if spec.get("command"):
        cdef["command"] = spec["command"]
    if spec.get("entrypoint"):
        cdef["entryPoint"] = spec["entrypoint"]
    td = env.ecs.register_task_definition(
        family=fam, networkMode="awsvpc" if fargate else "bridge",
        requiresCompatibilities=["FARGATE" if fargate else "EC2"], cpu="512", memory="1024",
        containerDefinitions=[cdef])["taskDefinition"]["taskDefinitionArn"]
    kw = dict(cluster="pqc-fargate" if fargate else "pqc-ec2", taskDefinition=td,
              launchType="FARGATE" if fargate else "EC2", tags=[{"key": "project", "value": "pqc-e2e"}])
    if fargate:
        kw["networkConfiguration"] = {"awsvpcConfiguration": {"subnets": [env.subnet], "assignPublicIp": "ENABLED"}}
    started = time.time()
    t = env.ecs.run_task(**kw)
    if t.get("failures"):
        raise RuntimeError("run_task failures: %s" % t["failures"])
    arn = t["tasks"][0]["taskArn"]
    deadline = time.time() + spec.get("timeout", 300)
    d = {}
    while time.time() < deadline:
        d = env.ecs.describe_tasks(cluster=kw["cluster"], tasks=[arn])["tasks"][0]
        if d["lastStatus"] == "STOPPED":
            break
        time.sleep(2)
    text = ""
    # The log group is shared by every ECS case and LocalStack ignores logStreamNamePrefix, so page through all of
    # it (from this task's start) - a single call returns only the first page and can miss this case's lines.
    since = int((started - 5) * 1000)
    for _ in range(20):
        evs, kw2 = [], {"logGroupName": ECS_LOG_GROUP, "logStreamNamePrefix": fam + "/", "startTime": since}
        for _page in range(50):
            resp = env.logs.filter_log_events(**kw2)
            evs += resp.get("events", [])
            if not resp.get("nextToken") or resp.get("nextToken") == kw2.get("nextToken"):
                break
            kw2["nextToken"] = resp["nextToken"]
        evs = [e for e in evs if e.get("logStreamName", "").startswith(fam + "/")] or evs
        text = "\n".join(e["message"] for e in evs if full_id in e["message"] or "pq-tls" in e["message"])
        if _parse_result(text, full_id):
            break
        time.sleep(2)
    env.ecs.deregister_task_definition(taskDefinition=td)
    notes = [l.strip()[:300] for l in text.splitlines() if "pq-tls" in l][:6]
    return _parse_result(text, full_id), {"task_status": d.get("lastStatus"), "stopped_reason": d.get("stoppedReason"),
                                  "exit_codes": [c.get("exitCode") for c in d.get("containers", [])],
                                  "log_tail": text[-1500:] if "PQC_RESULT " not in text else None, "log_notes": notes}


USER_DATA = """#!/bin/bash
export {exports}
{{
{setup}
{run}
}} > /var/log/pqc.log 2>&1
curl -s -m 10 -X POST --data-binary @/var/log/pqc.log "http://pq-observer:8080/results?id=$PQC_CASE_ID"
"""


def _run_ec2(env, case, full_id):
    spec = case["ec2"]
    ami = env.amis.get(spec["ami"])
    if not ami:
        raise RuntimeError("AMI %s not registered (run build/ami.sh); have %s" % (spec["ami"], sorted(env.amis)))
    exports = " ".join("%s=%s" % (k, json.dumps(v)) for k, v in _env_for(case, full_id).items())
    ud = USER_DATA.format(exports=exports, setup="\n".join(spec.get("setup", [])), run=spec["run"])
    r = env.ec2.run_instances(ImageId=ami, InstanceType=spec.get("instance_type", "t3.small"), MinCount=1, MaxCount=1,
                              UserData=ud, TagSpecifications=[{"ResourceType": "instance", "Tags": TAGS + [
                                  {"Key": "Name", "Value": _short(case["id"], 120)}]}])
    iid = r["Instances"][0]["InstanceId"]
    text, deadline = "", time.time() + spec.get("timeout", 300)
    try:
        while time.time() < deadline:
            got = _obs("/results?id=" + full_id) or []
            if got:
                text = got[-1]
                break
            time.sleep(3)
    finally:
        env.ec2.terminate_instances(InstanceIds=[iid])
    notes = [l.strip()[:300] for l in text.splitlines() if "pq-tls" in l][:6]
    return _parse_result(text, full_id), {"instance": iid, "ami": ami, "log_tail": text[-1500:] if "PQC_RESULT " not in text else None,
                                  "log_notes": notes}


EXEC = {"lambda": _run_lambda, "ecs-fargate": _run_ecs, "ecs-ec2": _run_ecs, "ec2": _run_ec2}


# ---------------------------------------------------------------- grading
def _observer_view(full_id, t0, t1):
    """Observer records for this case: its requests, plus ClientHellos from the same client IP that fall strictly
    between this case's first and last request (+1 s). Probes visit targets in a fixed order with hybrid first and
    tls12 last, so a failed handshake (no request) is bracketed by the case's own successful ones; a recycled IP
    from another container cannot fall inside that bracket."""
    evs = _obs("/events") or []
    reqs = [e for e in evs if e.get("case_id") == full_id]
    if not reqs:
        return reqs, []
    ips = {e["remote"].rsplit(":", 1)[0] for e in reqs}
    lo = min(_ts(e["time"]) for e in reqs) - 1
    hi = max(_ts(e["time"]) for e in reqs) + 1
    hellos = [e for e in evs if e["kind"] == "hello" and e["remote"].rsplit(":", 1)[0] in ips and lo <= _ts(e["time"]) <= hi]
    return reqs, hellos


def _grade(case, client, reqs, hellos):
    mism, per = [], {}
    results = (client or {}).get("results", {})
    for t in case["targets"]:
        res = results.get(t)
        exp = case.get("expect", {}).get(t, {})
        hel = [h for h in hellos if h["listener"] == t]
        req = [q for q in reqs if q["listener"] == t]
        # offered groups: from the observer's record of this exact connection when it completed, else bracketed hellos
        src = req[-1] if req else (hel[-1] if hel else None)
        view = {"client": res, "observer_request": req[-1] if req else None,
                "observer_offered_pq": src["offered_pq"] if src else None,
                "observer_offered_groups": src.get("offered_groups") if src else None}
        per[t] = view
        if res is None:
            mism.append("%s: no client result" % t)
            continue
        for k, v in exp.items():
            got = res.get(k)
            if k == "offered_pq" and view["observer_offered_pq"] is not None:
                got = view["observer_offered_pq"]
            if k == "error_match":
                if not re.search(v, res.get("error", "") or ""):
                    mism.append("%s: error %r !~ /%s/" % (t, res.get("error"), v))
                continue
            if got != v:
                mism.append("%s: %s=%r expected %r" % (t, k, got, v))
        # client and observer must agree on what was negotiated
        if res.get("ok") and req and bool(req[-1].get("pq")) != bool(res.get("pq")):
            mism.append("%s: client/observer pq disagree" % t)
    return mism, per


def _fmt(t, res):
    if not res:
        return "%s=?" % t
    if not res.get("ok"):
        return "%s=FAIL" % t
    return "%s=%s/%s" % (t, "PQ" if res.get("pq") else "classical", (res.get("group") or "").replace("MLKEM", "MLKEM"))


def run_case(env, case):
    full_id = "%s-%s" % (env.run_id, case["id"])
    t0 = time.time()
    out = {"id": case["id"], "lang": case["lang"], "compute": case["compute"], "mode": case.get("mode", "baseline"),
           "title": case.get("title", ""), "doc": case.get("doc", ""), "full_id": full_id, "file": case["_file"],
           "runtime_label": case.get("runtime_label") or case.get("lambda", {}).get("runtime")
           or case.get("ecs", {}).get("image") or case.get("ec2", {}).get("ami"),
           "expect": case.get("expect", {}), "finding": case.get("finding"), "role": case.get("role", "client")}
    try:
        client, extra = EXEC[case["compute"]](env, case, full_id)
        out.update(extra=extra, client=client)
        reqs, hellos = _observer_view(full_id, t0, time.time())
        if client is None:
            out.update(verdict="ERROR", summary="no client result: %s" % json.dumps(extra)[:400])
        else:
            mism, per = _grade(case, client, reqs, hellos)
            out.update(targets=per, mismatches=mism, verdict="FAIL" if mism else "PASS",
                       runtime=client.get("runtime"), tls_lib=client.get("openssl") or client.get("tls_lib"),
                       summary=" ".join(_fmt(t, client.get("results", {}).get(t)) for t in case["targets"])
                       + ("  !! " + "; ".join(mism) if mism else ""))
    except Exception as e:
        out.update(verdict="ERROR", summary="%s: %s" % (type(e).__name__, str(e)[:500]))
    out["seconds"] = round(time.time() - t0, 1)
    return out


# ---------------------------------------------------------------- detection
# String-valued field: works on CloudWatch and on LocalStack (whose filter engine has no boolean JSON comparisons).
DETECT_PATTERN = '{ ($.event = "tls_handshake") && ($.pq_status = "classical") }'


def run_detection(env, results):
    """Visibility checks over what this run produced:
    D1 CloudWatch Logs: a JSON filter over Lambda and ECS log groups finds exactly the classical (non-PQ) handshakes the
       clients reported - the query a platform team would alarm on.
    D2 Server side: the observer's ClientHello log flags every client that did not offer a PQ group, and every TLS 1.2
       negotiation, independent of any client logging."""
    out = []
    cw = [r for r in results if r["compute"] in ("lambda", "ecs-fargate", "ecs-ec2") and r.get("client")]
    if cw:
        t0 = time.time()
        expected = {(r["full_id"], t) for r in cw for t, v in (r["client"].get("results") or {}).items()
                    if v.get("ok") and not v.get("pq")}
        groups = [ECS_LOG_GROUP] if any(r["compute"].startswith("ecs") for r in cw) else []
        groups += ["/aws/lambda/" + _short(r["id"]) for r in cw if r["compute"] == "lambda"]
        found = set()
        err = None
        for g in sorted(set(groups)):
            try:
                tok = None
                while True:
                    kw = dict(logGroupName=g, filterPattern=DETECT_PATTERN, startTime=int((time.time() - 6 * 3600) * 1000))
                    if tok:
                        kw["nextToken"] = tok
                    resp = env.logs.filter_log_events(**kw)
                    for e in resp.get("events", []):
                        try:
                            m = json.loads(e["message"][e["message"].index("{"):])
                        except Exception:
                            continue
                        if str(m.get("case_id", "")).startswith(env.run_id + "-"):
                            found.add((m["case_id"], m["target"]))
                    tok = resp.get("nextToken")
                    if not tok:
                        break
            except env.logs.exceptions.ResourceNotFoundException:
                continue
            except Exception as e:  # pragma: no cover
                err = "%s: %s" % (type(e).__name__, e)
        missing, extra = sorted(expected - found), sorted(found - expected)
        ok = not missing and not extra and err is None
        out.append({"id": "detect-cloudwatch-nonpq", "lang": "all", "compute": "cloudwatch-logs", "mode": "detection",
                    "title": "CloudWatch Logs filter finds every classical handshake reported by Lambda/ECS clients",
                    "verdict": "PASS" if ok else "FAIL", "file": "(runner)", "full_id": env.run_id,
                    "summary": "pattern %s: expected %d, found %d%s" % (DETECT_PATTERN, len(expected), len(found),
                                                                       ("; missing %s; extra %s; %s" % (missing[:5], extra[:5], err or "")) if not ok else ""),
                    "seconds": round(time.time() - t0, 1)})
    # D2: observer side
    evs = _obs("/events") or []
    run_reqs = [e for e in evs if str(e.get("case_id", "")).startswith(env.run_id + "-") and e.get("kind") == "request"]
    classical = [e for e in run_reqs if not e.get("pq")]
    tls12 = [e for e in run_reqs if e.get("tls_version") == "TLSv1.2"]
    reported = {(r["full_id"], t) for r in results if r.get("client") and r.get("role") != "server" for t, v in (r["client"].get("results") or {}).items()
                if v.get("ok") and not v.get("pq")}
    seen = {(e["case_id"], e["listener"]) for e in classical}
    missing = sorted(reported - seen)
    out.append({"id": "detect-server-handshake-log", "lang": "all", "compute": "observer", "mode": "detection",
                "title": "Server-side handshake log flags every non-PQ and TLS 1.2 handshake",
                "verdict": "PASS" if not missing else "FAIL", "file": "(runner)", "full_id": env.run_id,
                "summary": "%d handshakes, %d classical, %d TLS1.2; %s" % (
                    len(run_reqs), len(classical), len(tls12),
                    "all client-reported classical handshakes present" if not missing else "missing %s" % missing[:5]),
                "seconds": 0})
    return out


# ---------------------------------------------------------------- cleanup
def cleanup():
    lam, ecs, ec2 = _c("lambda"), _c("ecs"), _c("ec2")
    n = 0
    for page in lam.get_paginator("list_functions").paginate():
        for f in page["Functions"]:
            if f["FunctionName"].startswith("pqc-"):
                lam.delete_function(FunctionName=f["FunctionName"])
                n += 1
    for page in lam.get_paginator("list_layers").paginate():
        for l in page["Layers"]:
            if l["LayerName"].startswith("pqc-"):
                for v in lam.list_layer_versions(LayerName=l["LayerName"])["LayerVersions"]:
                    lam.delete_layer_version(LayerName=l["LayerName"], VersionNumber=v["Version"])
    ids = [i["InstanceId"] for r in ec2.describe_instances(Filters=[{"Name": "tag:project", "Values": ["pqc-e2e"]}])["Reservations"]
           for i in r["Instances"] if i["State"]["Name"] != "terminated"]
    if ids:
        ec2.terminate_instances(InstanceIds=ids)
    for cl in ("pqc-fargate", "pqc-ec2"):
        try:
            for t in ecs.list_tasks(cluster=cl)["taskArns"]:
                ecs.stop_task(cluster=cl, task=t)
        except Exception:
            pass
    print("deleted %d functions, terminated %d instances (pqc-* / project=pqc-e2e only)" % (n, len(ids)))
