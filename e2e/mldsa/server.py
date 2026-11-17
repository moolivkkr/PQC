"""pq-mldsa: ML-DSA certificate endpoints next to pq-observer (same network namespace: clients reach pq-observer:8448-8450).

Python 3.15 on OpenSSL 3.5: it serves ML-DSA certificates, verifies ML-DSA client certificates, and its ssl module
reports the negotiated group and the signature algorithms each side used (SSLSocket.group(), server_sigalg(),
client_sigalg(), new in 3.15). A test fixture only; the probes under test are unchanged by it.

  :8448 mldsa-dual  ML-DSA-44 and ECDSA P-256 server certificates; OpenSSL picks one from the client's
                    signature_algorithms -> "does this client get ML-DSA, and does every other client still connect?"
  :8449 mldsa-only  ML-DSA-44 server certificate only, TLS 1.3 -> "can this client negotiate and verify ML-DSA?"
  :8450 mldsa-mtls  dual server certificates; client certificate required, trusted root = the ML-DSA test CA only
                    -> "can this client sign with an ML-DSA key?" (user and workload identity)

GET /probe?id=<case> returns the pq-observer view (tls_version, group, pq) plus server_cert (mldsa|ecdsa),
server_sigalg, client_cert, client_sigalg. Every handshake is printed as one JSON line; GET :8081/events returns them.
"""
import json
import socket
import ssl
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer, ThreadingHTTPServer
from socketserver import ThreadingMixIn
from urllib.parse import parse_qs, urlparse

C = "/certs/"
GROUPS = "X25519MLKEM768:SecP256r1MLKEM768:X25519:prime256v1:secp384r1"
EVENTS, LOCK = [], threading.Lock()


def record(ev):
    ev["ts"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    with LOCK:
        EVENTS.append(ev)
        del EVENTS[:-20000]
    print(json.dumps({"event": "mldsa_handshake", **ev}), flush=True)


def kind(sigalg):
    s = (sigalg or "").lower()
    return "mldsa" if "mldsa" in s else "ecdsa" if "ecdsa" in s else "rsa" if "rsa" in s else (s or None)


def context(certs, mtls=False, tls13_only=False):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_3 if tls13_only else ssl.TLSVersion.TLSv1_2
    ctx.set_groups(GROUPS) if hasattr(ctx, "set_groups") else ctx.set_ecdh_curve("X25519MLKEM768")
    for crt, key in certs:  # one certificate per key type; OpenSSL keeps both
        ctx.load_cert_chain(C + crt, C + key)
    if mtls:
        ctx.verify_mode = ssl.CERT_REQUIRED
        ctx.load_verify_locations(C + "ca-mldsa.crt")
    return ctx


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        s = self.connection
        listener = self.server.listener
        peer = s.getpeercert(binary_form=True)
        csig = s.client_sigalg() if peer else None
        v = {"listener": listener, "tls_version": s.version(), "group": s.group(),
             "pq": "MLKEM" in (s.group() or "").upper(), "server_sigalg": s.server_sigalg(),
             "server_cert": kind(s.server_sigalg()), "client_sigalg": csig,
             "client_cert": kind(csig) if peer else None}
        record({"kind": "request", "case_id": parse_qs(urlparse(self.path).query).get("id", [""])[0], **v})
        body = json.dumps(v).encode()
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.send_header("connection", "close")
        self.end_headers()
        self.wfile.write(body)


class TLSServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True

    def __init__(self, port, listener, ctx):
        self.listener, self.ctx = listener, ctx
        super().__init__(("0.0.0.0", port), Handler)

    def get_request(self):
        raw, addr = self.socket.accept()
        raw.settimeout(10)
        try:
            return self.ctx.wrap_socket(raw, server_side=True), addr
        except (ssl.SSLError, OSError) as e:  # a failed handshake is a result: log it, keep serving
            record({"kind": "error", "listener": self.listener, "remote": addr[0], "error": str(e)[:200]})
            raw.close()
            raise


class Events(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        with LOCK:
            body = b"ok" if self.path.startswith("/healthz") else json.dumps(EVENTS).encode()
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)


DUAL = [("server-mldsa.crt", "server-mldsa.key"), ("server-ec.crt", "server-ec.key")]
for port, name, ctx in ((8448, "mldsa-dual", context(DUAL)),
                        (8449, "mldsa-only", context([DUAL[0]], tls13_only=True)),
                        (8450, "mldsa-mtls", context(DUAL, mtls=True))):
    threading.Thread(target=TLSServer(port, name, ctx).serve_forever, daemon=True).start()
    print("%s on :%d" % (name, port), flush=True)
ThreadingHTTPServer(("0.0.0.0", 8081), Events).serve_forever()
