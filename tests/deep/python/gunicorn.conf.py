# gunicorn.conf.py - TLS terminated by gunicorn itself (no ALB in front).
# The ssl_context hook (gunicorn 21+) lets you adjust the stdlib SSLContext gunicorn builds.
import ssl

bind = "0.0.0.0:9447"
workers = 2
certfile = "/w/certs/leaf.pem"
keyfile = "/w/certs/leaf.key"


def ssl_context(conf, default_ssl_context_factory):
    ctx = default_ssl_context_factory()
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    if hasattr(ctx, "set_groups"):  # Python 3.15+
        # PQ hybrid first, classical fallback kept. Use "X25519MLKEM768" alone to refuse classical clients.
        ctx.set_groups(__import__("os").environ.get("PQ_GROUPS", "X25519MLKEM768:X25519:secp256r1"))
    return ctx
