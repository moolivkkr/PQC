"""Python TLS client probe: each library against a PQ-only and a classical-only server.

Usage: python3 pyclients.py <label>
Servers (srv.sh / pgsrv.sh): pqsrv 8443/8444 http, 8445/8446 grpc, 8447/8448 kafka, 8449/8450 redis;
pgsrv 5432 (PQ-only) / 5433 (classical-only). CA at /w/certs/ca.pem; all clients verify the certificate.
For non-HTTP protocols against s_server the handshake result is read from the error class and confirmed
in the server log (srv/*.log "Negotiated TLS1.3 group").
"""
import asyncio, glob, importlib, os, socket, ssl, sys, traceback

LABEL = sys.argv[1] if len(sys.argv) > 1 else "py"
CA = "/w/certs/ca.pem"
H = "pqsrv"
PAIRS = {"http": (8443, 8444), "grpc": (8445, 8446), "kafka": (8447, 8448), "redis": (8449, 8450), "pg": (5432, 5433)}


def out(lib, which, res):
    print("%s | %-28s | %-14s | %s" % (LABEL, lib, which, res), flush=True)


def ctx():
    return ssl.create_default_context(cafile=CA)


def short(e):
    s = "%s: %s" % (type(e).__name__, e)
    return s.replace("\n", " ")[:150]


def both(lib, family, fn):
    pq, cl = PAIRS[family]
    for name, port in (("PQ-only", pq), ("classical-only", cl)):
        try:
            out(lib, name, "OK " + str(fn(port)))
        except Exception as e:
            out(lib, name, "FAIL " + short(e))


def have(mod):
    try:
        return importlib.import_module(mod)
    except Exception as e:
        out(mod, "-", "not importable: " + short(e))
        return None


# ---- posture
v = sys.version.split()[0]
out("python", "-", "%s %s" % (v, ssl.OPENSSL_VERSION))
c = ssl.create_default_context()
out("ssl ctx", "-", "min=%s options=%s has_set_groups=%s" % (c.minimum_version.name, int(c.options), hasattr(c, "set_groups")))
if hasattr(c, "get_groups"):
    try:
        out("ssl get_groups", "-", ",".join(c.get_groups())[:200])
    except Exception as e:
        out("ssl get_groups", "-", short(e))


# ---- stdlib ssl
def raw_ssl(port, mutate=None):
    cx = ctx()
    if mutate:
        mutate(cx)
    with socket.create_connection((H, port), timeout=5) as r:
        with cx.wrap_socket(r, server_hostname=H) as s:
            g = s.group() if hasattr(s, "group") else "n/a(<3.15)"
            return "%s group=%s" % (s.version(), g)


both("ssl (stdlib)", "http", raw_ssl)
if hasattr(c, "set_groups"):
    both("ssl set_groups(X25519MLKEM768)", "http", lambda p: raw_ssl(p, lambda cx: cx.set_groups("X25519MLKEM768")))
    both("ssl set_groups(MLKEM:X25519)", "http", lambda p: raw_ssl(p, lambda cx: cx.set_groups("X25519MLKEM768:X25519")))
both("ssl set_ecdh_curve(X25519MLKEM768)", "http", lambda p: raw_ssl(p, lambda cx: cx.set_ecdh_curve("X25519MLKEM768")))


def http_client(port):
    import http.client
    h = http.client.HTTPSConnection(H, port, context=ctx(), timeout=5)
    h.request("GET", "/")
    v = h.sock.version()
    return "HTTP %s %s" % (h.getresponse().status, v)


both("http.client", "http", http_client)


def urllib_req(port):
    import urllib.request
    r = urllib.request.urlopen("https://%s:%d/" % (H, port), context=ctx(), timeout=5)
    return "HTTP %s" % r.status


both("urllib.request", "http", urllib_req)

if have("requests"):
    import requests
    out("requests", "-", "version " + requests.__version__)
    both("requests", "http", lambda p: "HTTP %s" % requests.get("https://%s:%d/" % (H, p), verify=CA, timeout=5).status_code)

if have("urllib3"):
    import urllib3
    out("urllib3", "-", "version " + urllib3.__version__)
    both("urllib3", "http", lambda p: "HTTP %s" % urllib3.PoolManager(ca_certs=CA, timeout=5).request("GET", "https://%s:%d/" % (H, p)).status)

if have("botocore"):
    import botocore
    from botocore.httpsession import URLLib3Session
    from botocore.awsrequest import AWSRequest
    out("botocore", "-", "version " + botocore.__version__)

    def boto(port):
        s = URLLib3Session(verify=CA, timeout=5)
        r = s.send(AWSRequest(method="GET", url="https://%s:%d/" % (H, port)).prepare())
        return "HTTP %s" % r.status_code

    both("botocore URLLib3Session", "http", boto)

if have("httpx"):
    import httpx
    out("httpx", "-", "version " + httpx.__version__)
    both("httpx", "http", lambda p: "HTTP %s" % httpx.get("https://%s:%d/" % (H, p), verify=ctx(), timeout=5).status_code)

if have("aiohttp"):
    import aiohttp
    out("aiohttp", "-", "version " + aiohttp.__version__)

    def aio(port):
        async def go():
            async with aiohttp.ClientSession() as s:
                async with s.get("https://%s:%d/" % (H, port), ssl=ctx(), timeout=aiohttp.ClientTimeout(total=5)) as r:
                    return "HTTP %s" % r.status
        return asyncio.run(go())

    both("aiohttp", "http", aio)

# ---- pyOpenSSL direct (bundled OpenSSL from the cryptography wheel)
if have("OpenSSL"):
    import OpenSSL
    from OpenSSL import SSL
    from cryptography.hazmat.backends.openssl.backend import backend
    out("pyOpenSSL", "-", "pyOpenSSL %s cryptography-bundled %s" % (OpenSSL.__version__, backend.openssl_version_text()))

    def pyo(port):
        cx = SSL.Context(SSL.TLS_CLIENT_METHOD)
        cx.load_verify_locations(CA)
        cx.set_verify(SSL.VERIFY_PEER, lambda *a: a[-1])
        s = socket.create_connection((H, port), timeout=5)
        s.settimeout(None)  # pyOpenSSL raises WantReadError on sockets with a timeout
        cn = SSL.Connection(cx, s)
        cn.set_tlsext_host_name(H.encode())
        cn.set_connect_state()
        cn.do_handshake()
        g = cn.get_group_name() if hasattr(cn, "get_group_name") else "n/a"
        r = "%s group=%s" % (cn.get_protocol_version_name(), g)
        cn.close()
        return r

    both("pyOpenSSL", "http", pyo)

    def pyo_urllib3(port):
        import urllib3.contrib.pyopenssl as p
        p.inject_into_urllib3()
        try:
            return "HTTP %s" % urllib3.PoolManager(ca_certs=CA, timeout=5).request("GET", "https://%s:%d/" % (H, port)).status
        finally:
            p.extract_from_urllib3()

    if "urllib3" in sys.modules:
        both("urllib3 + inject pyOpenSSL", "http", pyo_urllib3)

# ---- awscrt (s2n-tls on Linux)
if have("awscrt"):
    import awscrt
    from awscrt import io, http as chttp
    try:
        from importlib.metadata import version as _ver
        out("awscrt", "-", "version %s prefs=%s" % (_ver("awscrt"), [m.name for m in io.TlsCipherPref]))
    except Exception as e:
        out("awscrt", "-", short(e))
    elg = io.EventLoopGroup(1)
    bs = io.ClientBootstrap(elg, io.DefaultHostResolver(elg))

    def crt(port, pref=None):
        o = io.TlsContextOptions()
        o.override_default_trust_store_from_path(None, CA)
        if pref:
            o.cipher_pref = getattr(io.TlsCipherPref, pref)
        co = io.ClientTlsContext(o).new_connection_options()
        co.set_server_name(H)
        cn = chttp.HttpClientConnection.new(host_name=H, port=port, bootstrap=bs, tls_connection_options=co).result(10)
        cn.close()
        return "connected"

    both("awscrt default", "http", crt)
    for pref in [m.name for m in io.TlsCipherPref if "PQ" in m.name]:
        both("awscrt " + pref, "http", lambda p, pref=pref: crt(p, pref))

# ---- redis-py (TLS handshake; s_server then answers with non-RESP data)
if have("redis"):
    import redis
    out("redis-py", "-", "version " + redis.__version__)

    def rds(port):
        try:
            redis.Redis(host=H, port=port, ssl=True, ssl_ca_certs=CA, socket_timeout=5, socket_connect_timeout=5).ping()
            return "ping ok"
        except redis.exceptions.ConnectionError as e:
            if "SSL" in str(e) or "handshake" in str(e).lower() or "Error -2" in str(e) or "refused" in str(e):
                raise
            return "TLS ok (then protocol error, expected vs s_server: %s)" % short(e)[:60]
        except redis.exceptions.TimeoutError:
            return "no SSL error; s_server sends no RESP reply (confirm in server log)"
        except redis.exceptions.ResponseError as e:
            return "TLS ok (then protocol error: %s)" % short(e)[:60]

    both("redis-py", "redis", rds)

# ---- confluent-kafka (librdkafka bundled OpenSSL)
if have("confluent_kafka"):
    import logging, confluent_kafka
    try:
        from confluent_kafka.admin import AdminClient
    except ImportError as e:
        out("confluent-kafka", "-", "AdminClient missing in this build: " + short(e))
        AdminClient = None
    so = glob.glob(os.path.join(os.path.dirname(confluent_kafka.__file__), "..", "confluent_kafka.libs", "*")) + \
        glob.glob(os.path.join(os.path.dirname(confluent_kafka.__file__), "*.so*"))
    sslv = set()
    for f in so:
        try:
            data = open(f, "rb").read()
            import re
            sslv.update(m.decode() for m in re.findall(rb"OpenSSL 3\.\d+\.\d+[a-z]? +\d+ \w+ \d{4}", data))
        except Exception:
            pass
    out("confluent-kafka", "-", "client %s librdkafka %s bundled %s" % (getattr(confluent_kafka, "version", lambda: ["?"])()[0], getattr(confluent_kafka, "libversion", lambda: ["?"])()[0], sorted(sslv)))

    def kafka(port, extra=None):
        msgs = []

        class Hd(logging.Handler):
            def emit(self, rec):
                msgs.append(rec.getMessage())
        lg = logging.getLogger("k%d%s" % (port, extra))
        lg.handlers = [Hd()]
        lg.setLevel(logging.DEBUG)
        conf = {"bootstrap.servers": "%s:%d" % (H, port), "security.protocol": "SSL", "ssl.ca.location": CA,
                "debug": "security,broker", "socket.timeout.ms": 4000, "logger": lg}
        if extra:
            conf.update(extra)
        a = AdminClient(conf)
        try:
            a.list_topics(timeout=4)
        except Exception:
            pass
        a.poll(0.5)
        ssl_lines = [m for m in msgs if "SSL" in m or "handshake" in m.lower()]
        txt = " ".join(ssl_lines)
        if "handshake fail" in txt.lower() or "alert" in txt.lower():
            raise RuntimeError("SSL handshake failed: " + txt[:120])
        return "no handshake error logged (confirm in server log): " + txt[:120]

    if AdminClient:
        both("confluent-kafka default", "kafka", kafka)
    if AdminClient:
        both("confluent-kafka ssl.curves.list", "kafka", lambda p: kafka(p, {"ssl.curves.list": "X25519MLKEM768:X25519"}))

# ---- grpcio (bundled BoringSSL; OPENSSL_CONF does not apply)
if have("grpc"):
    import grpc
    out("grpcio", "-", "version " + grpc.__version__)

    def grpc_c(port):
        ch = grpc.secure_channel("%s:%d" % (H, port), grpc.ssl_channel_credentials(open(CA, "rb").read()))
        try:
            grpc.channel_ready_future(ch).result(timeout=4)
            return "READY"
        except grpc.FutureTimeoutError:
            return "not READY (check server log: s_server speaks no HTTP/2)"
        finally:
            ch.close()

    both("grpcio client", "grpc", grpc_c)

# ---- PostgreSQL drivers against real PG18 with ssl_groups
DSN = "host=pgsrv port=%d user=postgres dbname=postgres sslmode=verify-full sslrootcert=" + CA + " connect_timeout=5"
if have("psycopg"):
    import psycopg
    libs = sorted(os.path.basename(f) for f in glob.glob(os.path.join(os.path.dirname(psycopg.__file__), "..", "psycopg_binary.libs", "*")))
    out("psycopg3", "-", "psycopg %s impl=%s libpq=%s libs=%s" % (psycopg.__version__, psycopg.pq.__impl__, psycopg.pq.version(), libs))

    def pg3(port):
        with psycopg.connect(DSN % port) as cn:
            return cn.execute("select version, cipher from pg_stat_ssl where pid = pg_backend_pid()").fetchone()

    both("psycopg3", "pg", pg3)
if have("psycopg2"):
    import psycopg2
    libs = sorted(os.path.basename(f) for f in glob.glob(os.path.join(os.path.dirname(psycopg2.__file__), "..", "psycopg2_binary.libs", "*")))
    out("psycopg2", "-", "psycopg2 %s libpq=%s libs=%s" % (psycopg2.__version__, psycopg2.extensions.libpq_version(), libs))

    def pg2(port):
        cn = psycopg2.connect(DSN % port)
        cur = cn.cursor()
        cur.execute("select version, cipher from pg_stat_ssl where pid = pg_backend_pid()")
        r = cur.fetchone()
        cn.close()
        return r

    both("psycopg2", "pg", pg2)

# ---- PyMySQL: which TLS stack does it use?
if have("pymysql"):
    import inspect, pymysql.connections as pc
    src = inspect.getsource(pc)
    out("PyMySQL", "-", "%s uses ssl.create_default_context=%s" % (pc.__name__, "create_default_context" in src))
print("%s | DONE" % LABEL)
