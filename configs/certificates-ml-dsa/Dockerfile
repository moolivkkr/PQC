# Dockerfile - add the private ML-DSA and ECDSA roots to the system trust store
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates openssl \
    && rm -rf /var/lib/apt/lists/*
COPY pki/mldsa-root.crt /usr/local/share/ca-certificates/example-mldsa-root.crt
COPY pki/ec-root.crt    /usr/local/share/ca-certificates/example-ecdsa-root.crt
RUN update-ca-certificates
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/example-mldsa-root.crt
