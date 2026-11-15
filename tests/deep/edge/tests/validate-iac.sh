#!/bin/bash
# Validate the edge group's IaC in containers: terraform validate (aws provider ~> 6.0),
# cfn-lint (latest from PyPI, inside the container), JSON/YAML parse for SCP and k8s files.
set -u
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
D=/private/tmp/claude-501/-Users-kishoremooli-development-cybersecurity/21fa377a-bc06-46f9-9e49-4588545ba6c2/scratchpad/deep/edge
TF=$(docker image inspect --format '{{index .RepoDigests 0}}' hashicorp/terraform:1.13)
PY=$(docker image inspect --format '{{index .RepoDigests 0}}' python:3.13-slim)
echo "terraform image: $TF"; echo "python image: $PY"
for m in lb edge waf; do
  echo "=== terraform $m"
  rm -rf /private/tmp/claude-501/-Users-kishoremooli-development-cybersecurity/21fa377a-bc06-46f9-9e49-4588545ba6c2/scratchpad/deep/edge/tfwork/$m
  mkdir -p $D/tfwork/$m && cp $D/iac/$m/main.tf $D/tfwork/$m/
  docker run --rm --label run=pqc-deep-edge -v $D/tfwork/$m:/tf -w /tf $TF init -backend=false -input=false -no-color >/dev/null 2>&1 || echo "init failed"
  docker run --rm --label run=pqc-deep-edge -v $D/tfwork/$m:/tf -w /tf $TF version -no-color | head -3
  docker run --rm --label run=pqc-deep-edge -v $D/tfwork/$m:/tf -w /tf $TF validate -no-color
  docker run --rm --label run=pqc-deep-edge -v $D/tfwork/$m:/tf -w /tf $TF fmt -check -diff -no-color && echo "fmt ok"
done
echo "=== cfn-lint + json/yaml"
docker run --rm --label run=pqc-deep-edge -v $D/iac:/iac:ro $PY bash -c '
pip install -q cfn-lint pyyaml 2>&1 | tail -1
cfn-lint --version
for t in /iac/lb/lb.yaml /iac/edge/edge.yaml /iac/waf/waf.yaml; do echo "--- $t"; cfn-lint "$t" && echo "cfn-lint clean"; done
python -I -c "import json;json.load(open(\"/iac/lb/scp-elb-pq.json\"));print(\"scp json ok\")"
python -I -c "import yaml;d=list(yaml.safe_load_all(open(\"/iac/lb/k8s-lbc.yaml\")));print(\"k8s yaml ok\",[x[\"kind\"] for x in d])"
'
