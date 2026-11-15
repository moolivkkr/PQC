"""Run uvicorn with an explicit TLS group list (Python 3.15+ SSLContext.set_groups).

uvicorn builds its SSLContext in Config.load(); load it first, adjust the context, then run.
Server.startup() skips load() when the config is already loaded.
"""
import os
import ssl

import uvicorn

config = uvicorn.Config(
    "app:asgi",
    host="0.0.0.0",
    port=int(os.environ.get("PORT", "8443")),
    ssl_certfile=os.environ.get("TLS_CERT", "/w/certs/leaf.pem"),
    ssl_keyfile=os.environ.get("TLS_KEY", "/w/certs/leaf.key"),
)
config.load()
config.ssl.minimum_version = ssl.TLSVersion.TLSv1_2
if hasattr(config.ssl, "set_groups"):
    # PQ hybrid first, classical fallback kept; "X25519MLKEM768" alone refuses classical clients.
    config.ssl.set_groups(os.environ.get("PQ_GROUPS", "X25519MLKEM768:X25519:secp256r1"))
uvicorn.Server(config).run()
