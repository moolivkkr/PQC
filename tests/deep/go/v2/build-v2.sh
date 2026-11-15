#!/bin/sh
# Runs inside golang:<v> (by digest). $1 = name suffix, $2 = go line for go.mod, $3 = "deps" to also build deps.
# Mounts: /src = v2 dir, /out = v2/bin, /go/pkg/mod = module cache.
set -u
name=$1; line=$2
export CGO_ENABLED=0 GOTOOLCHAIN=local
d=/tmp/cases; rm -rf $d; mkdir -p $d; cp /src/cases/*.go $d/
printf 'module cases\n\ngo %s\n' "$line" > $d/go.mod
if (cd $d && go vet . >/tmp/vet 2>&1; go build -o /out/cases-$name . 2>/tmp/err); then
  printf 'built cases-%s: ' "$name"; go version /out/cases-$name
  go version -m /out/cases-$name | grep -E 'DefaultGODEBUG' || echo '        (no DefaultGODEBUG line)'
else echo "BUILD-FAIL cases-$name: $(head -c 400 /tmp/err)"; fi
if [ "${3:-}" = deps ]; then
  d=/tmp/deps; rm -rf $d; mkdir -p $d; cp /src/deps/main.go $d/
  cd $d
  go mod init deps >/dev/null 2>&1
  go get google.golang.org/grpc@latest github.com/jackc/pgx/v5@latest github.com/aws/aws-sdk-go-v2@latest \
    github.com/aws/aws-sdk-go-v2/config@latest github.com/aws/aws-sdk-go-v2/credentials@latest \
    github.com/aws/aws-sdk-go-v2/service/sts@latest software.sslmate.com/src/go-pkcs12@latest \
    golang.org/x/crypto@latest github.com/youmark/pkcs8@latest >/tmp/get 2>&1 || { echo GET-FAIL; tail -5 /tmp/get; }
  go mod tidy >/tmp/tidy 2>&1 || { echo TIDY-FAIL; tail -5 /tmp/tidy; }
  if go build -o /out/deps-$name . 2>/tmp/err; then
    echo "built deps-$name"; cp go.mod /out/deps-go.mod
    grep -E '^go |grpc |pgx|aws-sdk-go-v2 |config |go-pkcs12|x/crypto|youmark' go.mod
    go version -m /out/deps-$name | grep -E 'DefaultGODEBUG' || echo '        (no DefaultGODEBUG line)'
  else echo "BUILD-FAIL deps-$name: $(head -c 800 /tmp/err)"; fi
fi
