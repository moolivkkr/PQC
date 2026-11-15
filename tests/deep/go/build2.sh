#!/bin/sh
# inside golang:1.26 / 1.25 / 1.27; $1 = minor
set -u; v=$1; export GOTOOLCHAIN=local GOFLAGS=-mod=mod
for d in extra extra-fipsonly; do rm -rf /tmp/$d; cp -r /src/$d /tmp/$d; printf 'module x\n\ngo 1.%s\n' $v > /tmp/$d/go.mod; done
(cd /tmp/extra && CGO_ENABLED=0 go build -o /out/extra-1.$v . && echo built extra-1.$v)
(cd /tmp/extra-fipsonly && CGO_ENABLED=1 GOEXPERIMENT=boringcrypto go build -o /out/extra-fipsonly-boring-1.$v . && echo built fipsonly-boring-1.$v)
if [ $v = 26 ]; then
 for d in srv libs; do rm -rf /tmp/$d; cp -r /src/$d /tmp/$d; printf 'module %s\n\ngo 1.26\n' $d > /tmp/$d/go.mod; (cd /tmp/$d && go mod tidy >/tmp/tidy.$d 2>&1 && CGO_ENABLED=0 go build -o /out/$d . && echo built $d || tail -5 /tmp/tidy.$d); cp /tmp/$d/go.mod /tmp/$d/go.sum /src/$d/ 2>/dev/null; done
 cd /tmp/libs; for m in github.com/redis/go-redis/v9 github.com/segmentio/kafka-go github.com/IBM/sarama github.com/jackc/pgx/v5 github.com/aws/aws-sdk-go-v2 google.golang.org/grpc; do dir=$(go list -m -f '{{.Dir}} {{.Version}}' $m 2>/dev/null || (cd /tmp/srv && go list -m -f '{{.Dir}} {{.Version}}' $m)); set -- $dir; echo "SRC $m $2 CurvePreferences-hits: $(grep -rl --include=*.go CurvePreferences $1 2>/dev/null | grep -v _test.go | sed "s#$1/##" | tr '\n' ' ')"; done
fi
