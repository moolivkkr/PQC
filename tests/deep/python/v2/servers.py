"""Case C (a server that loads its own cert and key) and server-side case F, with the stdlib ssl module.

Each port runs a tiny HTTPS responder built on ssl.SSLContext. The probe (openssl s_client in another container)
connects once offering only X25519MLKEM768 and once offering only X25519, and records the negotiated group
and which certificate was served.
"""
import os, socket, ssl, sys, tempfile, threading

C = "/w2/certs"
PW = "changeit"
log = lambda m: print(m, flush=True)


def base():
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    return ctx


def rsa():
    c = base(); c.load_cert_chain(C + "/rsa.pem", C + "/rsa.key"); return c


def ec():
    c = base(); c.load_cert_chain(C + "/ec.pem", C + "/ec.key"); return c


def rsa_enc():
    c = base(); c.load_cert_chain(C + "/rsa.pem", C + "/rsa-enc.key", password=PW); return c


def ec_enc():
    c = base(); c.load_cert_chain(C + "/ec.pem", C + "/ec-enc.key", password=lambda: os.environ.get("TLS_KEY_PASSWORD", PW)); return c


def rsa_and_ec():  # two key types in one context: OpenSSL keeps one cert per key type and picks by the client's sigalgs
    c = base()
    c.load_cert_chain(C + "/rsa-chain.pem", C + "/rsa.key")
    c.load_cert_chain(C + "/ec.pem", C + "/ec.key")
    return c


def sni():
    default, other = ec(), base()
    other.load_cert_chain(C + "/b.pem", C + "/b.key")

    def cb(sock, name, _ctx):
        if name == "b.pqsrv":
            sock.context = other
    default.sni_callback = cb
    return default


def p12_cryptography():
    from cryptography.hazmat.primitives.serialization import pkcs12, Encoding, PrivateFormat, NoEncryption
    key, cert, extra = pkcs12.load_key_and_certificates(open(C + "/server.p12", "rb").read(), PW.encode())
    d = tempfile.mkdtemp()
    with open(d + "/k.pem", "wb") as f:
        f.write(key.private_bytes(Encoding.PEM, PrivateFormat.PKCS8, NoEncryption()))
    with open(d + "/c.pem", "wb") as f:
        f.write(cert.public_bytes(Encoding.PEM) + b"".join(x.public_bytes(Encoding.PEM) for x in extra or []))
    c = base(); c.load_cert_chain(d + "/c.pem", d + "/k.pem"); return c


def p12_pyopenssl():
    from OpenSSL import crypto
    if not hasattr(crypto, "load_pkcs12"):
        raise RuntimeError("OpenSSL.crypto.load_pkcs12 does not exist in this pyOpenSSL; use cryptography's pkcs12")
    p = crypto.load_pkcs12(open(C + "/server.p12", "rb").read(), PW.encode())
    raise RuntimeError("unexpected: load_pkcs12 present")


def mtls():
    c = ec(); c.verify_mode = ssl.CERT_REQUIRED; c.load_verify_locations(C + "/ca.pem"); return c


def f_ecdh():
    c = ec(); c.set_ecdh_curve("prime256v1"); return c


def f_max12():
    c = ec(); c.maximum_version = ssl.TLSVersion.TLSv1_2; return c


def f_ciphers():
    c = ec(); c.set_ciphers("ECDHE+AESGCM:!aNULL"); return c


SERVERS = {9501: rsa, 9502: ec, 9503: rsa_enc, 9504: ec_enc, 9505: rsa_and_ec, 9506: sni, 9507: p12_cryptography,
           9508: p12_pyopenssl, 9509: mtls, 9510: f_ecdh, 9511: f_max12, 9512: f_ciphers}


def serve(port, ctx):
    ls = socket.create_server(("0.0.0.0", port))
    while True:
        conn, _ = ls.accept()
        try:
            with ctx.wrap_socket(conn, server_side=True) as s:
                s.settimeout(3)
                try:
                    s.recv(1024)
                except Exception:
                    pass
                s.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: close\r\n\r\nok\n")
        except Exception as e:
            log("%d handshake error: %s" % (port, str(e)[:120]))


for port, make in SERVERS.items():
    try:
        ctx = make()
        threading.Thread(target=serve, args=(port, ctx), daemon=True).start()
        log("%d %s: listening" % (port, make.__name__))
    except Exception as e:
        log("%d %s: SETUP FAILED %s: %s" % (port, make.__name__, type(e).__name__, str(e)[:160]))
threading.Event().wait()
