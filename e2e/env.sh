# Source this file: sets up a LocalStack *separate* from any other project's instance.
#   Container pqc-e2e-localstack, host port 127.0.0.1:4600, network pqc-e2e (10.250.0.0/24).
# The auth token is read from the shell environment, or from the export line in ~/.zshrc.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
# (The ~/.zshrc line is parsed with a regex, not eval'd: a stray quote there would break eval.)
if [ -z "${LOCALSTACK_AUTH_TOKEN:-}" ]; then
  LOCALSTACK_AUTH_TOKEN="$(grep -E '^export LOCALSTACK_AUTH_TOKEN=' ~/.zshrc 2>/dev/null | grep -oE 'ls-[A-Za-z0-9_-]+' | head -1)"
fi
if [ -z "${LOCALSTACK_AUTH_TOKEN:-}" ] && [ -f ~/.localstack/auth.json ]; then
  LOCALSTACK_AUTH_TOKEN="$(python3 -c 'import json,os;print(json.load(open(os.path.expanduser("~/.localstack/auth.json"))).get("LOCALSTACK_AUTH_TOKEN",""))')"
fi
export LOCALSTACK_AUTH_TOKEN
export E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export COMPOSE_PROJECT_NAME=pqc-e2e
export PQC_LS_PORT=4600
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
export AWS_ENDPOINT_URL="http://localhost:${PQC_LS_PORT}"
