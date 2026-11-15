# tested: helm 4.3.2 (alpine/helm:latest); pin by digest
FROM alpine/helm:latest AS helm
FROM alpine/k8s:1.34.1 AS k8s

FROM alpine:3.24
RUN apk add --no-cache curl wget git openssh-client openssl ca-certificates bash
COPY --from=k8s  /usr/bin/kubectl /usr/local/bin/kubectl
COPY --from=helm /usr/bin/helm    /usr/local/bin/helm
# AWS CLI v2 is built for glibc: run it from amazon/aws-cli (>= 2.34.54) as a separate step.
RUN curl -V | grep -q 'OpenSSL/3\.[5-9]' && ssh -V 2>&1 | grep -q 'OpenSSH_1[0-9]'
