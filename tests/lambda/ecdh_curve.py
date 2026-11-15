import socket, ssl, sys

# Code-level option: ask for the hybrid group through the existing set_ecdh_curve API.
label = sys.argv[1]
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
try:
    ctx.set_ecdh_curve("X25519MLKEM768")
    with socket.create_connection(("pqsrv", 8443), timeout=5) as raw:
        with ctx.wrap_socket(raw, server_hostname="pqsrv") as s:
            print(f"{label} set_ecdh_curve: PQ-only OK {s.version()}")
except Exception as e:
    print(f"{label} set_ecdh_curve: FAIL {type(e).__name__}: {e}")
