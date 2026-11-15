"""Python PQ TLS client cases D (custom CA trust), E (mutual TLS), F (settings that block PQ), I (pinning).

Usage:  python3 cases.py <tag> <phase>        phase = pre (CA not in the OS store) | os (CA in the OS store)
        python3 cases.py <tag> one <test>     run one test (used internally, each test in its own process)
Servers (srv2.sh, host pqsrv): 8443 PQ-only, 8444 classical-only, 8451/8452 the same with a client cert required,
8453 PQ-only mTLS for gRPC. A test that succeeds against 8443/8451 proves the client offered X25519MLKEM768,
because those servers accept nothing else. Each test runs in a fresh process with its own environment.
"""
import os, socket, ssl, subprocess, sys

TAG = sys.argv[1]
H = "pqsrv"
CD = "/w2/certs"
CA, CCRT, CKEY, CKEY_ENC = CD + "/ca.pem", CD + "/client.pem", CD + "/client.key", CD + "/client-enc.key"
PORTS = {"tls": (("PQ-only", 8443), ("classical-only", 8444)), "mtls": (("PQ-only mTLS", 8451), ("classical mTLS", 8452))}


def short(e):
    return ("%s: %s" % (type(e).__name__, e)).replace("\n", " ")[:160]


def sock_info(s):
    g = s.group() if hasattr(s, "group") else "n/a"
    return "%s group=%s" % (s.version(), g)


def raw(port, ctx):
    with socket.create_connection((H, port), timeout=5) as r, ctx.wrap_socket(r, server_hostname=H) as s:
        return sock_info(s)


def url(port):
    return "https://%s:%d/" % (H, port)


# ---------------- tests: name -> (kind, fn(port)) ----------------
def t_ssl_cafile(p):
    return raw(p, ssl.create_default_context(cafile=CA))


def t_ssl_default(p):  # SSL_CERT_FILE env (pre) or OS store (os phase)
    return raw(p, ssl.create_default_context())


def t_requests_default(p):  # REQUESTS_CA_BUNDLE env, or certifi bundle (with/without our CA appended)
    import requests
    return "HTTP %d" % requests.get(url(p), timeout=5).status_code


def t_requests_verify(p):
    import requests
    return "HTTP %d" % requests.get(url(p), verify=CA, timeout=5).status_code


def t_truststore_requests(p):
    import truststore
    truststore.inject_into_ssl()
    import requests
    return "HTTP %d" % requests.get(url(p), timeout=5).status_code


def t_truststore_ctx(p):
    import truststore
    return raw(p, truststore.SSLContext(ssl.PROTOCOL_TLS_CLIENT))


def t_httpx_ctx(p):
    import httpx
    return "HTTP %d" % httpx.get(url(p), verify=ssl.create_default_context(cafile=CA), timeout=5).status_code


def t_httpx_env(p):  # SSL_CERT_FILE / default
    import httpx
    return "HTTP %d" % httpx.get(url(p), timeout=5).status_code


def t_aiohttp_ctx(p):
    import asyncio, aiohttp

    async def go():
        async with aiohttp.ClientSession() as s:
            async with s.get(url(p), ssl=ssl.create_default_context(cafile=CA)) as r:
                return "HTTP %d" % r.status
    return asyncio.run(go())


def boto_sts(p, **kw):
    import boto3, botocore.config, botocore.exceptions
    cfg = botocore.config.Config(retries={"max_attempts": 1}, connect_timeout=5, read_timeout=5, **kw)
    c = boto3.client("sts", endpoint_url=url(p), region_name="us-east-1", config=cfg,
                     aws_access_key_id="AKIDEXAMPLE", aws_secret_access_key="x")
    try:
        c.get_caller_identity()
        return "unexpected success"
    except botocore.exceptions.SSLError as e:
        raise
    except botocore.exceptions.EndpointConnectionError as e:
        raise
    except Exception as e:  # s_server answers with an HTML page: TLS worked, the API parse fails
        return "TLS OK, then %s (expected: test server is not STS)" % type(e).__name__


def t_boto3_env(p):  # AWS_CA_BUNDLE env
    return boto_sts(p)


def t_boto3_client_cert(p):  # AWS_CA_BUNDLE env + Config(client_cert=...)
    return boto_sts(p, client_cert=(CCRT, CKEY))


# ---- E: mutual TLS
def t_requests_mtls(p):
    import requests
    return "HTTP %d" % requests.get(url(p), verify=CA, cert=(CCRT, CKEY), timeout=5).status_code


def t_requests_no_cert(p):
    import requests
    return "HTTP %d" % requests.get(url(p), verify=CA, timeout=5).status_code


def t_ssl_mtls(p):
    c = ssl.create_default_context(cafile=CA)
    c.load_cert_chain(CCRT, CKEY)
    return raw(p, c)


def mtls_ctx(enc=False):
    c = ssl.create_default_context(cafile=CA)
    if enc:
        c.load_cert_chain(CCRT, CKEY_ENC, password="changeit")
    else:
        c.load_cert_chain(CCRT, CKEY)
    return c


def t_httpx_mtls(p):
    import httpx
    return "HTTP %d" % httpx.get(url(p), verify=mtls_ctx(), timeout=5).status_code


def t_httpx_mtls_enc(p):
    import httpx
    return "HTTP %d" % httpx.get(url(p), verify=mtls_ctx(enc=True), timeout=5).status_code


def t_aiohttp_mtls(p):
    import asyncio, aiohttp

    async def go():
        async with aiohttp.ClientSession() as s:
            async with s.get(url(p), ssl=mtls_ctx()) as r:
                return "HTTP %d" % r.status
    return asyncio.run(go())


def t_grpc_mtls(p):
    import grpc
    rd = lambda f: open(f, "rb").read()
    creds = grpc.ssl_channel_credentials(rd(CA), rd(CKEY), rd(CCRT))
    ch = grpc.secure_channel("%s:%d" % (H, 8453), creds)
    try:
        grpc.channel_ready_future(ch).result(timeout=4)
        return "channel READY"
    except grpc.FutureTimeoutError:
        return "no READY (expected: s_server speaks no HTTP/2); handshake judged from server log"


# ---- F: settings that block PQ
def f_ctx(mut):
    c = ssl.create_default_context(cafile=CA)
    mut(c)
    return c


def t_f_set_ciphers(p):
    return raw(p, f_ctx(lambda c: c.set_ciphers("ECDHE+AESGCM:!aNULL")))


def t_f_max_tls12(p):
    def m(c):
        c.maximum_version = ssl.TLSVersion.TLSv1_2
    return raw(p, f_ctx(m))


def t_f_min_tls13(p):
    def m(c):
        c.minimum_version = ssl.TLSVersion.TLSv1_3
    return raw(p, f_ctx(m))


def t_f_no_tls13(p):
    def m(c):
        c.options |= ssl.OP_NO_TLSv1_3
    return raw(p, f_ctx(m))


def t_f_protocol_tls12(p):
    import warnings
    warnings.simplefilter("ignore")
    c = ssl.SSLContext(ssl.PROTOCOL_TLSv1_2)
    c.load_verify_locations(CA)
    c.verify_mode = ssl.CERT_REQUIRED
    c.check_hostname = True
    return raw(p, c)


def t_f_ecdh_p256(p):
    return raw(p, f_ctx(lambda c: c.set_ecdh_curve("prime256v1")))


def t_f_ecdh_x25519(p):
    return raw(p, f_ctx(lambda c: c.set_ecdh_curve("X25519")))


def t_f_ecdh_mlkem(p):
    return raw(p, f_ctx(lambda c: c.set_ecdh_curve("X25519MLKEM768")))


def t_f_urllib3_max12(p):
    import urllib3
    pm = urllib3.PoolManager(ca_certs=CA, ssl_maximum_version=ssl.TLSVersion.TLSv1_2)
    return "HTTP %d" % pm.request("GET", url(p), timeout=5).status


# ---- I: pinning
def t_i_pin(p):
    import hashlib
    want = ssl.PEM_cert_to_DER_cert(open(CD + "/ec.pem").read())
    with socket.create_connection((H, p), timeout=5) as r, \
            ssl.create_default_context(cafile=CA).wrap_socket(r, server_hostname=H) as s:
        got = s.getpeercert(binary_form=True)
        ok = hashlib.sha256(got).hexdigest() == hashlib.sha256(want).hexdigest()
        return "%s pin=%s" % (sock_info(s), "match" if ok else "MISMATCH")


TESTS = {  # name: (ports, env, extra PYTHONPATH prefix)
    # D
    "D ssl cafile=": ("tls", t_ssl_cafile, {}, ""),
    "D ssl SSL_CERT_FILE": ("tls", t_ssl_default, {"SSL_CERT_FILE": CA}, ""),
    "D requests REQUESTS_CA_BUNDLE": ("tls", t_requests_default, {"REQUESTS_CA_BUNDLE": CA}, ""),
    "D requests verify=": ("tls", t_requests_verify, {}, ""),
    "D requests SSL_CERT_FILE only": ("tls", t_requests_default, {"SSL_CERT_FILE": CA}, ""),
    "D requests certifi+CA appended": ("tls", t_requests_default, {}, "/w2/certifi-plus"),
    "D requests certifi (no CA) neg": ("tls", t_requests_default, {}, ""),
    "D httpx verify=ctx": ("tls", t_httpx_ctx, {}, ""),
    "D httpx SSL_CERT_FILE": ("tls", t_httpx_env, {"SSL_CERT_FILE": CA}, ""),
    "D aiohttp ssl=ctx": ("tls", t_aiohttp_ctx, {}, ""),
    "D boto3 AWS_CA_BUNDLE": ("tls", t_boto3_env, {"AWS_CA_BUNDLE": CA}, ""),
    # E
    "E requests cert=(crt,key)": ("mtls", t_requests_mtls, {}, ""),
    "E requests no cert neg": ("mtls", t_requests_no_cert, {}, ""),
    "E ssl load_cert_chain": ("mtls", t_ssl_mtls, {}, ""),
    "E httpx ctx+cert": ("mtls", t_httpx_mtls, {}, ""),
    "E httpx ctx+encrypted key": ("mtls", t_httpx_mtls_enc, {}, ""),
    "E aiohttp ctx+cert": ("mtls", t_aiohttp_mtls, {}, ""),
    "E boto3 client_cert": ("mtls", t_boto3_client_cert, {"AWS_CA_BUNDLE": CA}, ""),
    "E grpc ssl_channel_credentials": ("grpc", t_grpc_mtls, {}, ""),
    # F
    "F set_ciphers(ECDHE+AESGCM)": ("tls", t_f_set_ciphers, {}, ""),
    "F maximum_version=TLSv1_2": ("tls", t_f_max_tls12, {}, ""),
    "F minimum_version=TLSv1_3": ("tls", t_f_min_tls13, {}, ""),
    "F OP_NO_TLSv1_3": ("tls", t_f_no_tls13, {}, ""),
    "F PROTOCOL_TLSv1_2": ("tls", t_f_protocol_tls12, {}, ""),
    "F set_ecdh_curve(prime256v1)": ("tls", t_f_ecdh_p256, {}, ""),
    "F set_ecdh_curve(X25519)": ("tls", t_f_ecdh_x25519, {}, ""),
    "F set_ecdh_curve(X25519MLKEM768)": ("tls", t_f_ecdh_mlkem, {}, ""),
    "F urllib3 ssl_maximum_version=1.2": ("tls", t_f_urllib3_max12, {}, ""),
    # I
    "I cert pin (sha256 of DER)": ("tls", t_i_pin, {}, ""),
}
OS_TESTS = {  # run after the CA is added to the OS trust store
    "D ssl default ctx, CA in OS store": ("tls", t_ssl_default, {}, ""),
    "D requests default, CA in OS store": ("tls", t_requests_default, {}, ""),
    "D truststore.inject_into_ssl+requests": ("tls", t_truststore_requests, {}, ""),
    "D truststore.SSLContext raw": ("tls", t_truststore_ctx, {}, ""),
    "D httpx default, CA in OS store": ("tls", t_httpx_env, {}, ""),
}


def run_one(name):
    table = dict(TESTS, **OS_TESTS)
    kind, fn, _, _ = table[name]
    ports = (("PQ-only mTLS", 8453),) if kind == "grpc" else PORTS[kind]
    for label, port in ports:
        try:
            res = "OK " + str(fn(port))
        except Exception as e:
            res = "FAIL " + short(e)
        print("%s | %-38s | %-15s | %s" % (TAG, name, label, res), flush=True)


if sys.argv[2] == "one":
    run_one(sys.argv[3])
else:
    table = OS_TESTS if sys.argv[2] == "os" else TESTS
    only = os.environ.get("ONLY")  # optional comma-separated prefixes
    for name, (_, _, env, pp) in table.items():
        if only and not any(name.startswith(o) for o in only.split(",")):
            continue
        e = dict(os.environ, **env)
        if pp:
            e["PYTHONPATH"] = pp + ":" + e.get("PYTHONPATH", "")
        r = subprocess.run([sys.executable, __file__, TAG, "one", name], env=e, capture_output=True, text=True, timeout=60)
        sys.stdout.write(r.stdout)
        shim = sorted({l.split("shim: ")[1] for l in r.stderr.splitlines() if "pq-tls: python legacy shim" in l})
        if shim:
            print("%s | %-38s | shim log: %s" % (TAG, name, "; ".join(shim)))
        if r.returncode:
            print("%s | %-38s | crashed: %s" % (TAG, name, r.stderr.strip().splitlines()[-1:] if r.stderr else ""))
