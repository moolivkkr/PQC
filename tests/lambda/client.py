import os, socket, ssl, sys
label = sys.argv[1] if len(sys.argv) > 1 else "python"
for port, name in ((8443, "PQ-only"), (8444, "classical-only")):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    try:
        with socket.create_connection(("pqsrv", port), timeout=5) as raw:
            with ctx.wrap_socket(raw, server_hostname="pqsrv") as s:
                print(f"{label}: {name}: OK {s.version()}")
    except Exception as e:
        print(f"{label}: {name}: FAIL {type(e).__name__}: {e}")
