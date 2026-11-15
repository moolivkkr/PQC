# Dockerfile - pq-envoy sidecar. Envoy 1.36.13 (BoringSSL) accepts X25519MLKEM768 (Tested 2026-11-14).
# The base image (Ubuntu 22.04) has no curl, which the ECS health check needs.
FROM envoyproxy/envoy@sha256:93e25ef06d87a908a1114e8dff9a2b3a3046fbbfda7e644d448d752332633de6
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
# envoy.yaml = the Web servers tab file: listener 8443 terminates PQ TLS from peers,
# listener 8080 takes the app's plain HTTP and originates PQ TLS (ecdh_curves + TLS 1.3 min AND max) to peers.
COPY envoy.yaml /etc/envoy/envoy.yaml
# Certificates: write them to /certs at task start (e.g. an init container reading Secrets Manager);
# never bake private keys into the image.
