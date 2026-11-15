import os
import ssl

import uvicorn

config = uvicorn.Config(
    "app:asgi",
    host="0.0.0.0",
    port=int(os.environ.get("PORT", "8443")),
    ssl_certfile=os.environ.get("TLS_CERT", "/etc/tls/server.pem"),
    ssl_keyfile=os.environ.get("TLS_KEY", "/etc/tls/server.key"),
)
config.load()  # builds config.ssl; Server.run() skips load() when already loaded
config.ssl.minimum_version = ssl.TLSVersion.TLSv1_2
if hasattr(config.ssl, "set_groups"):
    config.ssl.set_groups(os.environ.get("PQ_GROUPS", "X25519MLKEM768:X25519:secp256r1"))
uvicorn.Server(config).run()
