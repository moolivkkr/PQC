import socket, ssl, sys


def handler(event, context):
    out = {"runtime": sys.version.split()[0], "openssl": ssl.OPENSSL_VERSION}
    for port, name in ((8443, "pq_only"), (8444, "classical_only")):
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        try:
            with socket.create_connection(("pqsrv", port), timeout=5) as raw:
                with ctx.wrap_socket(raw, server_hostname="pqsrv") as s:
                    out[name] = "OK " + str(s.version())
        except Exception as e:
            out[name] = "FAIL " + type(e).__name__
    return out
