"""PQ TLS probe - Python. Same code on Lambda (handler), ECS and EC2 (CLI). No PQ-specific settings:
whatever the runtime + platform + fix (layer, extension, config file) gives is what is measured.

Targets (observer listeners): hybrid, pqonly, mtls, eccert, tls12. For each it records the observer's view
of the handshake (TLS version, negotiated group, pq) or the client-side error.

Client stack: urllib3 when importable (requests/boto3 path, which the legacy-Python layer shim patches),
else stdlib http.client. Trust: the test CA only (custom-CA case). mTLS: client.crt/client.key.

Every result is also printed as one JSON line {"event":"tls_handshake",...} - the detection pipeline
(CloudWatch Logs filter) keys on that line.
"""
import json
import os
import platform
import ssl
import sys
import time

TARGETS = {"hybrid": 8443, "pqonly": 8444, "mtls": 8445, "eccert": 8446, "tls12": 8447}
HERE = os.path.dirname(os.path.abspath(__file__))


def _certs_dir():
    for d in (os.environ.get("PQC_CERTS", ""), os.path.join(HERE, "certs"), "/opt/pqc-certs", "/etc/pqc/certs"):
        if d and os.path.exists(os.path.join(d, "ca.crt")):
            return d
    raise RuntimeError("test CA not found (set PQC_CERTS)")


def _via_extension(name):
    """Extension mode: plain HTTP to the local pq-egress extension, which originates the TLS (PQ) upstream."""
    import urllib.request
    port = os.environ["PQC_EGRESS_PORT"]
    url = "http://127.0.0.1:%s/%s/probe?id=%s" % (port, name, os.environ.get("PQC_CASE_ID", "adhoc"))
    with urllib.request.urlopen(url, timeout=10) as r:
        return json.loads(r.read())


def _fetch(host, name, port, case_id, certs):
    path = "/probe?id=%s" % case_id
    cert = (os.path.join(certs, "client.crt"), os.path.join(certs, "client.key")) if name == "mtls" else None
    try:
        import urllib3  # noqa: F401  (requests / boto3 stack)
        kw = {"ca_certs": os.path.join(certs, "ca.crt"), "cert_reqs": "CERT_REQUIRED", "retries": False,
              "timeout": urllib3.Timeout(connect=5, read=10)}
        if cert:
            kw["cert_file"], kw["key_file"] = cert
        pool = urllib3.HTTPSConnectionPool(host, port, **kw)
        r = pool.request("GET", path)
        return json.loads(r.data), "urllib3-" + urllib3.__version__
    except ImportError:
        import http.client
        ctx = ssl.create_default_context(cafile=os.path.join(certs, "ca.crt"))
        if cert:
            ctx.load_cert_chain(*cert)
        c = http.client.HTTPSConnection(host, port, context=ctx, timeout=10)
        c.request("GET", path)
        return json.loads(c.getresponse().read()), "http.client"


def run(case_id=None, targets=None):
    case_id = case_id or os.environ.get("PQC_CASE_ID", "adhoc")
    host = os.environ.get("PQC_OBSERVER", "pq-observer")
    names = targets or [t for t in os.environ.get("PQC_TARGETS", ",".join(TARGETS)).split(",") if t]
    certs = _certs_dir()
    out = {"case_id": case_id, "lang": "python", "runtime": platform.python_version(),
           "openssl": ssl.OPENSSL_VERSION, "compute": os.environ.get("PQC_COMPUTE", "unknown"),
           "mode": os.environ.get("PQC_MODE", "baseline"), "openssl_conf": os.environ.get("OPENSSL_CONF", ""),
           "results": {}}
    for name in names:
        t0 = time.time()
        try:
            if os.environ.get("PQC_EGRESS_PORT"):
                obs, stack = _via_extension(name), "extension:pq-egress"
            else:
                obs, stack = _fetch(host, name, TARGETS[name], case_id, certs)
            res = {"ok": True, "tls_version": obs.get("tls_version"), "group": obs.get("group"),
                   "pq": obs.get("pq", False), "offered_pq": obs.get("offered_pq", False), "stack": stack}
        except Exception as e:  # handshake failure etc. - a result, not a crash
            res = {"ok": False, "error": "%s: %s" % (type(e).__name__, str(e)[:300])}
        res["ms"] = int((time.time() - t0) * 1000)
        out["results"][name] = res
        print(json.dumps(dict(event="tls_handshake", case_id=case_id, lang="python", runtime=out["runtime"],
                              compute=out["compute"], mode=out["mode"], target=name, **res)), flush=True)
    return out


def handler(event, context):  # Lambda
    event = event or {}
    return run(event.get("case_id"), event.get("targets"))


if __name__ == "__main__":
    r = run(sys.argv[1] if len(sys.argv) > 1 else None)
    print("PQC_RESULT " + json.dumps(r), flush=True)
