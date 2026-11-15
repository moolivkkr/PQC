#!/bin/bash
# Build the golden AMIs and register them with the pqc-e2e LocalStack by tag (localstack-ec2/<name>:<ami-id>).
# Only pqc-* AMI tags are created; shared tags (amazonlinux-2023, ubuntu-*, re-*) are never touched.
source "$(dirname "$0")/../env.sh"; source "$E2E_DIR/build/lib.sh"
ami_id() { case $1 in al2023) echo ami-0a2023111090;; al2) echo ami-0a0000000002;; esac; }
for os in ${PQC_AMIS:-al2023 al2}; do
  docker build -q "${LBL[@]}" -f "$E2E_DIR/ec2/$os/Dockerfile" -t "localstack-ec2/pqc-$os:$(ami_id $os)" "$E2E_DIR" >/dev/null
  echo "AMI pqc-$os = $(ami_id $os) ($(docker run --rm "localstack-ec2/pqc-$os:$(ami_id $os)" cat /etc/pqc/ami-release))"
done
