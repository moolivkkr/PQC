#!/bin/bash
# Runs run-cases.sh for every runtime in the matrix (sequential; 2-3 containers at a time).
V=/private/tmp/claude-501/-Users-kishoremooli-development-cybersecurity/21fa377a-bc06-46f9-9e49-4588545ba6c2/scratchpad/deep/node/v2
$V/run-cases.sh node22 node@sha256:e13726ca604184d7a91fcacab1fc09eefd642dc28e79ac34e85540dd93b78cfb - > $V/out-node22.txt 2>&1
$V/run-cases.sh node24 node@sha256:9d266751ca3d7fdbe651c878ffd5ad0a42fed49a18c283509267c97f025b7496 - > $V/out-node24.txt 2>&1
$V/run-cases.sh lambda22-pq public.ecr.aws/lambda/nodejs@sha256:d95b861c8139eb5229f9703ff217e3cf0ca040430bfa090fee47fac5096a530f /k/openssl-pq-node.cnf > $V/out-lambda22-pq.txt 2>&1
$V/run-cases.sh lambda24-pq public.ecr.aws/lambda/nodejs@sha256:eb0de3ee81b4638149f0b1bcab2c657603a23a0c221a4b5678be29b48265bd31 /k/openssl-pq-node.cnf > $V/out-lambda24-pq.txt 2>&1
$V/run-cases.sh lambda22-aws public.ecr.aws/lambda/nodejs@sha256:d95b861c8139eb5229f9703ff217e3cf0ca040430bfa090fee47fac5096a530f /var/runtime/openssl_conf/openssl.cnf > $V/out-lambda22-aws.txt 2>&1
$V/run-cases.sh lambda24-aws public.ecr.aws/lambda/nodejs@sha256:eb0de3ee81b4638149f0b1bcab2c657603a23a0c221a4b5678be29b48265bd31 /var/runtime/openssl_conf/openssl.cnf > $V/out-lambda24-aws.txt 2>&1
echo ALL-DONE
