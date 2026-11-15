"""p12_to_pem.py - load a PKCS#12 file and write PEM cert chain + key for ssl.load_cert_chain.
Usage: python3 p12_to_pem.py server.p12 /run/tls   (password in env P12_PASSWORD)
Writes /run/tls/server.pem (leaf + chain) and /run/tls/server.key (PKCS#8, mode 0600).
"""
import os, sys
from cryptography.hazmat.primitives.serialization import pkcs12, Encoding, PrivateFormat, NoEncryption

src, out = sys.argv[1], sys.argv[2]
key, cert, chain = pkcs12.load_key_and_certificates(open(src, "rb").read(), os.environ["P12_PASSWORD"].encode())
os.makedirs(out, exist_ok=True)
with open(os.path.join(out, "server.pem"), "wb") as f:
    f.write(cert.public_bytes(Encoding.PEM) + b"".join(c.public_bytes(Encoding.PEM) for c in chain or []))
fd = os.open(os.path.join(out, "server.key"), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "wb") as f:
    f.write(key.private_bytes(Encoding.PEM, PrivateFormat.PKCS8, NoEncryption()))
