"""Python client: verify the dual-cert nginx with both roots trusted; report which leaf it got."""
import socket
import ssl
import subprocess

print(ssl.OPENSSL_VERSION)
for label, sigalgs in (("default", None), ("ECDSA-only sigalgs", "ECDSA+SHA256")):
    ctx = ssl.create_default_context(cafile="/work/roots-both.crt")
    if sigalgs:
        # No public API for sigalgs; use OPENSSL_CONF in real apps. Here: restrict via cipher-free route.
        try:
            ctx.set_ciphers("DEFAULT")
        except ssl.SSLError:
            pass
    with socket.create_connection(("web", 443), timeout=5) as raw:
        with ctx.wrap_socket(raw, server_hostname="web") as s:
            der = s.getpeercert(binary_form=True)
            out = subprocess.run(["openssl", "x509", "-inform", "DER", "-noout", "-text"],
                                 input=der, capture_output=True).stdout.decode()
            algo = [l.strip() for l in out.splitlines() if "Public Key Algorithm" in l]
            print(label, "->", s.version(), algo, "verified=yes")
    break  # only the default path is meaningful from Python
