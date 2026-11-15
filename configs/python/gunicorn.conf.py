import os
import ssl

bind = "0.0.0.0:8443"
workers = 2
certfile = "/etc/tls/server.pem"
keyfile = "/etc/tls/server.key"


def ssl_context(conf, default_ssl_context_factory):
    ctx = default_ssl_context_factory()
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    if hasattr(ctx, "set_groups"):  # Python 3.15+
        # PQ hybrid first, classical fallback kept. Set PQ_GROUPS=X25519MLKEM768 to refuse classical clients.
        ctx.set_groups(os.environ.get("PQ_GROUPS", "X25519MLKEM768:X25519:secp256r1"))
    return ctx
