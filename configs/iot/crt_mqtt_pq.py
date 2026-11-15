"""MQTT over mutual TLS with the AWS CRT (aws-iot-device-sdk-python-v2 / awscrt).
On Linux, awscrt uses s2n-tls + AWS-LC; cipher_pref selects the s2n security policy."""
import sys
from awscrt import io, mqtt

host, port, ca, cert, key = sys.argv[1:6]
pref_name = sys.argv[6] if len(sys.argv) > 6 else "PQ_DEFAULT"

opts = io.TlsContextOptions.create_client_with_mtls_from_path(cert, key)
opts.override_default_trust_store_from_path(None, ca)
opts.cipher_pref = getattr(io.TlsCipherPref, pref_name)   # PQ_DEFAULT = hybrid ML-KEM offered
tls_ctx = io.ClientTlsContext(opts)

elg = io.EventLoopGroup(1)
resolver = io.DefaultHostResolver(elg)
bootstrap = io.ClientBootstrap(elg, resolver)
client = mqtt.Client(bootstrap, tls_ctx)
conn = mqtt.Connection(client=client, host_name=host, port=int(port),
                       client_id=f"crt-{pref_name}", clean_session=True, keep_alive_secs=30)
try:
    conn.connect().result(timeout=15)
    pub, _ = conn.publish(topic="pq/test", payload=b"hello", qos=mqtt.QoS.AT_LEAST_ONCE)
    pub.result(timeout=10)
    conn.disconnect().result(timeout=10)
    print(f"CONNECT_OK pref={pref_name}")
except Exception as e:  # noqa: BLE001
    print(f"CONNECT_FAIL pref={pref_name}: {type(e).__name__}: {e}")
    sys.exit(1)
