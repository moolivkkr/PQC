"""Load balancer target probe - Python (ssl module + http.server; the stack uvicorn/gunicorn/hypercorn use)."""
import http.server
import json
import os
import platform
import ssl
import sys
import threading
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))


class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps({"ok": True, "server": "python"}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


def main():
    case_id = os.environ.get("PQC_CASE_ID", "adhoc")
    port = int(os.environ.get("PQC_SERVER_PORT", "9443"))
    obs = os.environ.get("PQC_OBSERVER", "pq-observer")
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(os.path.join(HERE, "server-rsa.crt"), os.path.join(HERE, "server-rsa.key"))
    srv = http.server.ThreadingHTTPServer(("0.0.0.0", port), H)
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    out = {"case_id": case_id, "lang": "python", "role": "server", "runtime": platform.python_version(),
           "openssl": ssl.OPENSSL_VERSION, "compute": os.environ.get("PQC_COMPUTE", "unknown"),
           "mode": os.environ.get("PQC_MODE", "baseline"), "results": {}}
    for t in [x for x in os.environ.get("PQC_TARGETS", "alb-pq,alb-classic").split(",") if x]:
        try:
            url = "http://%s:8080/dialback?id=%s&port=%d&policy=%s" % (obs, case_id, port, t)
            res = json.loads(urllib.request.urlopen(url, timeout=30).read())
        except Exception as e:
            res = {"ok": False, "error": "%s: %s" % (type(e).__name__, e)}
        res["pq_status"] = "failed" if not res.get("ok") else ("pq" if res.get("pq") else "classical")
        out["results"][t] = res
        print(json.dumps(dict(event="tls_handshake", role="server", case_id=case_id, lang="python",
                              runtime=out["runtime"], compute=out["compute"], mode=out["mode"], target=t, **res)), flush=True)
    print("PQC_RESULT " + json.dumps(out), flush=True)
    srv.shutdown()


if __name__ == "__main__":
    sys.exit(main())
