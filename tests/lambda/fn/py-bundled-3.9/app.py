import ssl, socket
def _raw(port):
    c = ssl.create_default_context(); c.check_hostname = False; c.verify_mode = ssl.CERT_NONE
    try:
        with socket.create_connection(("pqsrv", port), timeout=5) as r, c.wrap_socket(r) as s: return "OK " + s.version()
    except Exception as e: return "FAIL " + type(e).__name__
def _u3(pm, port):
    import urllib3
    try: pm.request("GET", "https://pqsrv:%d/" % port); return "OK"
    except urllib3.exceptions.SSLError: return "FAIL handshake"
    except Exception as e: return "OK handshake (" + type(e).__name__ + ")"
def _boto(port):
    import boto3, botocore.config, botocore.exceptions as be
    c = boto3.client("sts", endpoint_url="https://pqsrv:%d" % port, verify=False, region_name="us-east-1",
                     aws_access_key_id="x", aws_secret_access_key="x",
                     config=botocore.config.Config(retries={"max_attempts": 0}, connect_timeout=5, read_timeout=5))
    try: c.get_caller_identity(); return "OK"
    except be.SSLError: return "FAIL handshake"
    except Exception as e: return "OK handshake (" + type(e).__name__ + ")"
def handler(event, context):
    import sys, urllib3, urllib3.util.ssl_ as u
    pm = urllib3.PoolManager(cert_reqs="CERT_NONE", retries=False, timeout=5)
    return {"py": sys.version.split()[0], "sys_openssl": ssl.OPENSSL_VERSION.split()[1],
            "urllib3_ctx": u.SSLContext.__module__,
            "urllib3": {"pq": _u3(pm, 8443), "classical": _u3(pm, 8444)},
            "boto3": {"pq": _boto(8443), "classical": _boto(8444)},
            "raw_ssl": {"pq": _raw(8443), "classical": _raw(8444)}}
