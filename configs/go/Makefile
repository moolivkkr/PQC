GO ?= go
build-lambda:
    GOOS=linux GOARCH=arm64 CGO_ENABLED=0 $(GO) build -trimpath -tags lambda.norpc -o dist/bootstrap ./cmd/lambda
    $(GO) version -m dist/bootstrap | grep -E 'go1\.|DefaultGODEBUG' || true
    cd dist && zip -q function.zip bootstrap
