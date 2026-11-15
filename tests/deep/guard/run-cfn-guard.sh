#!/bin/bash
# Runs inside the pqc-guard-cfnbuild container (rust:1-slim-bookworm + cargo install cfn-guard 3.2.1).
set -u
CG=/usr/local/cargo/bin/cfn-guard
cd /w
$CG --version
for s in cfn-good cfn-bad sam-bad; do
  echo "=== template $s"
  $CG validate --rules rules/cfn/pq-tls.guard --data samples/$s.yaml --show-summary all 2>&1 \
    | grep -E 'Status =|^pq-tls.guard/' ; echo "exit=${PIPESTATUS[0]}"
done
echo "=== Config custom policy rule: one configuration item per evaluation"
mkdir -p /tmp/ci
# split JSON array into one file per CI with a tiny awk (no python in the image)
grep -o '{"resourceType".*}}}*' samples/config-ci-lambda.json | while IFS= read -r line; do
  line="${line%,}"; name=$(echo "$line" | sed -E 's/.*"resourceName":"([^"]+)".*/\1/')
  echo "$line" > /tmp/ci/$name.json
  res=$($CG validate --rules rules/config/lambda-pq-tls.guard --data /tmp/ci/$name.json --show-summary fail 2>&1 | grep -E 'Status =|FAIL' | tr '\n' ' ')
  echo "$name: $res"
done
