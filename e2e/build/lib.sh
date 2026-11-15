# Shared helpers for build/*.sh. Source after env.sh.
set -euo pipefail
: "${E2E_DIR:?source e2e/env.sh first}"
REPO_ROOT="$(cd "$E2E_DIR/.." && pwd)"
WORK="$E2E_DIR/.work"; ART="$WORK/artifacts"
mkdir -p "$ART"/{layers,layer-src,lambda,ec2}
GO_IMG=golang@sha256:eb61c3873c97416fff0116553fff65d67a3549f72e11d9758849a689cdd8b523   # 1.27.4
AL2023=public.ecr.aws/amazonlinux/amazonlinux:2023.12.20261109.0                         # = AMI al2023-ami-2023.12.20261109.0
AL2=public.ecr.aws/amazonlinux/amazonlinux:2
RUNNER=pqc-e2e/runner:local
LBL=(--label project=pqc-e2e)

# ecr_repo <name> -> prints repositoryUri (creates the repo in the pqc-e2e LocalStack)
ecr_repo() {
  docker run --rm --network pqc-e2e --entrypoint python3 "$RUNNER" -c '
import boto3,sys; e=boto3.client("ecr"); n=sys.argv[1]
try: print(e.create_repository(repositoryName=n, tags=[{"Key":"project","Value":"pqc-e2e"}])["repository"]["repositoryUri"])
except e.exceptions.RepositoryAlreadyExistsException: print(e.describe_repositories(repositoryNames=[n])["repositories"][0]["repositoryUri"])' "$1"
}
# ecr_build <repo> <tag> <context> [dockerfile] [build-args...]: build for linux/arm64 and push to LocalStack ECR
ecr_build() {
  local repo=$1 tag=$2 ctx=$3 df=${4:-}; shift 4 || shift $#
  local uri; uri=$(ecr_repo "$repo")
  docker build -q "${LBL[@]}" ${df:+-f "$df"} "$@" -t "$uri:$tag" "$ctx" >/dev/null
  docker push -q "$uri:$tag" >/dev/null
  echo "pushed $repo:$tag"
}
# zipdir <dir> <out.zip>
zipdir() { rm -f "$2"; (cd "$1" && zip -qr -X "$2" .); }
