# gunicorn.conf.py for an encrypted private key (gunicorn has no key-password option).
# The ssl_context hook builds the context itself and passes the password from the environment
# (for example injected from Secrets Manager by ECS "secrets" or an EKS CSI driver).
import os
import ssl

bind = os.environ.get("BIND", "0.0.0.0:8443")
workers = 2
certfile = os.environ.get("TLS_CERT", "/etc/tls/server.pem")
keyfile = os.environ.get("TLS_KEY", "/etc/tls/server-enc.key")  # must be set so gunicorn turns TLS on


def ssl_context(conf, default_ssl_context_factory):
    # Do not call default_ssl_context_factory(): it loads the key without a password and fails.
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(conf.certfile, conf.keyfile, password=os.environ["TLS_KEY_PASSWORD"])
    if conf.ca_certs:  # mTLS: --ca-certs plus --cert-reqs 2
        ctx.load_verify_locations(conf.ca_certs)
        ctx.verify_mode = ssl.VerifyMode(conf.cert_reqs)
    return ctx
