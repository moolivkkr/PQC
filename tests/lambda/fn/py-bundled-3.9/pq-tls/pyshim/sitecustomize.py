# pq-tls shim for Lambda Python 3.9-3.11 (system OpenSSL 1.1.1, no ML-KEM).
# Routes urllib3 (requests) and botocore (boto3) through pyOpenSSL, whose bundled
# OpenSSL (from the cryptography wheel) offers X25519MLKEM768 by default.
# Python's own ssl module, http.client and aiohttp are NOT covered.
#
# sitecustomize runs before the Lambda bootstrap has put /var/runtime and the layer's
# site-packages on sys.path, so patching is deferred until each module is first imported.
# Whichever copy the function resolves (its own bundled one or the runtime's) is patched.
import os
import sys

if os.environ.get("PQ_TLS_DISABLE") != "1":
    import importlib.abc
    import importlib.util

    def _log(msg):
        print("pq-tls: python legacy shim: " + msg, file=sys.stderr)

    def _patch_urllib3(module):
        # The bootstrap imports urllib3 before it adds the function package and the layer's
        # site-packages to sys.path; append them (at the end, so precedence is unchanged) so
        # pyOpenSSL can be found whether it ships in the package or in a layer.
        for site in (os.environ.get("LAMBDA_TASK_ROOT", "/var/task"),
                     "/opt/python/lib/python%d.%d/site-packages" % sys.version_info[:2]):
            if site not in sys.path:
                sys.path.append(site)
        import urllib3.contrib.pyopenssl as p
        p.inject_into_urllib3()
        from cryptography.hazmat.backends.openssl.backend import backend
        _log("urllib3 -> pyOpenSSL (%s)" % backend.openssl_version_text())

    def _patch_botocore(module):
        # botocore deliberately keeps the stdlib SSLContext even when urllib3 is patched.
        import urllib3.contrib.pyopenssl as p
        module.SSLContext = p.PyOpenSSLContext
        _log("botocore -> pyOpenSSL")

    _PATCHES = {"urllib3": _patch_urllib3, "botocore.httpsession": _patch_botocore}

    class _Hook(importlib.abc.MetaPathFinder):
        def find_spec(self, name, path, target=None):
            patch = _PATCHES.pop(name, None)
            if patch is None:
                return None
            # Resolve with the other finders; stay installed while patches remain.
            sys.meta_path.remove(self)
            try:
                spec = importlib.util.find_spec(name)
            finally:
                if _PATCHES and self not in sys.meta_path:
                    sys.meta_path.insert(0, self)
            if spec is None or spec.loader is None:
                return spec
            exec_module = spec.loader.exec_module

            def exec_and_patch(module):
                exec_module(module)
                try:
                    patch(module)
                except Exception as e:  # never break the function
                    _log("not active for %s: %s: %s" % (name, type(e).__name__, e))

            spec.loader.exec_module = exec_and_patch
            return spec

    sys.meta_path.insert(0, _Hook())
