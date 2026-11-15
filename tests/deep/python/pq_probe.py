"""pq_probe.py - report whether this Python process negotiates hybrid PQ TLS.

Usage:  python3 pq_probe.py [host[:port] ...]     default: kms.us-east-1.amazonaws.com:443
Exit code 0 = every target negotiated X25519MLKEM768 (3.15+) or connected (older: see note).
Run it with the same image, env (OPENSSL_CONF, PYTHONPATH) and user as the service.
"""
import os
import socket
import ssl
import sys

targets = sys.argv[1:] or ["kms.us-east-1.amazonaws.com:443"]
print("python   ", sys.version.split()[0])
print("openssl  ", ssl.OPENSSL_VERSION)
print("OPENSSL_CONF", os.environ.get("OPENSSL_CONF", "(unset)"))
major, minor = ssl.OPENSSL_VERSION_INFO[:2]
if (major, minor) < (3, 5):
    print("RESULT    classical: OpenSSL < 3.5 has no ML-KEM; no setting can add it")
    sys.exit(2)
rc = 0
for t in targets:
    host, _, port = t.partition(":")
    ctx = ssl.create_default_context()
    try:
        with socket.create_connection((host, int(port or 443)), timeout=5) as raw:
            with ctx.wrap_socket(raw, server_hostname=host) as s:
                if hasattr(s, "group"):  # Python 3.15+
                    g = s.group()
                    print("RESULT    %s %s group=%s" % (t, s.version(), g))
                    rc |= 0 if g and "MLKEM" in g.upper() else 1
                else:
                    # < 3.15 cannot report the group; only a PQ-only server proves the offer.
                    print("RESULT    %s %s connected (group not visible before Python 3.15;"
                          " point this at a PQ-only test server to prove the offer)" % (t, s.version()))
    except Exception as e:
        print("RESULT    %s FAIL %s: %s" % (t, type(e).__name__, e))
        rc |= 1
sys.exit(rc)
