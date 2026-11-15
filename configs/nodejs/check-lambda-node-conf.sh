#!/bin/bash
# Usage: check-lambda-node-conf.sh 24  -> compares AWS's file in the current base image with ours, ignoring Groups.
set -euo pipefail
img="public.ecr.aws/lambda/nodejs:${1:?node major}"
norm() { grep -vE '^\s*(#|$)' | grep -v '^Groups' ; }
diff <(docker run --rm --entrypoint cat "$img" /var/runtime/openssl_conf/openssl.cnf | norm) \
     <(norm < pq-tls/openssl-pq-node.cnf) && echo "OK: only Groups differs"
docker run --rm --entrypoint grep "$img" -n 'OPENSSL_CONF' /var/runtime/bootstrap
