These files match the excerpts above. Replace the example account IDs, names and ARNs with your own. The Go sources compile against Go 1.26. Tested parts are marked in the sections above; IaC files follow AWS docs and were not deployed (no AWS access here).

`go.mod` (preferred: raise the `go` line)

```text
module example.com/payments

go 1.26

toolchain go1.27.4

require (
	github.com/aws/aws-lambda-go v1.55.1
	github.com/aws/aws-sdk-go-v2 v1.48.0
	github.com/aws/aws-sdk-go-v2/config v1.33.18
	github.com/aws/aws-sdk-go-v2/service/sts v1.52.0
	google.golang.org/grpc v1.85.0
)
```

Versions are what `go mod tidy` resolved on 2026-11-14 (the sources in this section compile and pass `go vet` with Go 1.26.11). Only the `go` line matters for PQ.

`go.mod` (alternative: keep an old `go` line, turn PQ on)

```text
module example.com/legacy

go 1.23

godebug (
	tlsmlkem=1
	tlssecpmlkem=1
)
```

`tlssecpmlkem` is only known to Go 1.26+ toolchains. On 1.24 or 1.25 builds, list `tlsmlkem=1` only, or the build fails on an unknown setting.

`cmd/client/main.go` (HTTP and AWS SDK client, FIPS-safe)

```go
//go:debug tlsmlkem=1
package main

import (
	"context"
	"crypto/fips140"
	"crypto/tls"
	"log"
	"net/http"
	"time"

	awshttp "github.com/aws/aws-sdk-go-v2/aws/transport/http"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sts"
)

// The //go:debug line is optional: needed only while go.mod says go < 1.24.

func httpClient() *http.Client {
	tr := http.DefaultTransport.(*http.Transport).Clone()
	tr.TLSClientConfig = &tls.Config{MinVersion: tls.VersionTLS12} // no CurvePreferences
	return &http.Client{Transport: tr, Timeout: 30 * time.Second}
}

func awsHTTPClient() *awshttp.BuildableClient {
	return awshttp.NewBuildableClient().WithTransportOptions(func(t *http.Transport) {
		if fips140.Enabled() {
			// aws-sdk-go-v2 v1.48.0 forces P-256/384/521 in FIPS mode; keep the approved hybrids.
			t.TLSClientConfig.CurvePreferences = []tls.CurveID{
				tls.SecP256r1MLKEM768, tls.X25519MLKEM768, tls.CurveP256, tls.CurveP384}
		}
	})
}

func main() {
	ctx := context.Background()
	cfg, err := config.LoadDefaultConfig(ctx, config.WithHTTPClient(awsHTTPClient()))
	if err != nil {
		log.Fatal(err)
	}
	out, err := sts.NewFromConfig(cfg).GetCallerIdentity(ctx, &sts.GetCallerIdentityInput{})
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("caller=%s", *out.Arn)

	resp, err := httpClient().Get("https://api.internal.example.com/health")
	if err != nil {
		log.Fatal(err)
	}
	defer resp.Body.Close()
	log.Printf("status=%d tls_group=%v", resp.StatusCode, resp.TLS.CurveID)
}
```

`cmd/server/main.go` (HTTPS and gRPC server that logs the group)

```go
package main

import (
	"context"
	"crypto/tls"
	"log"
	"net"
	"net/http"
	"os"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/health"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/grpc/peer"
)

func tlsConfig() *tls.Config {
	cert, err := tls.LoadX509KeyPair("/etc/tls/tls.crt", "/etc/tls/tls.key")
	if err != nil {
		log.Fatal(err)
	}
	cfg := &tls.Config{Certificates: []tls.Certificate{cert}, MinVersion: tls.VersionTLS12}
	if os.Getenv("TLS_PQ_ONLY") == "1" { // enforcement mode, after every client is PQ
		cfg.MinVersion = tls.VersionTLS13
		cfg.CurvePreferences = []tls.CurveID{tls.X25519MLKEM768, tls.SecP256r1MLKEM768}
	}
	return cfg
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		log.Printf("path=%s tls_version=%x tls_group=%v", r.URL.Path, r.TLS.Version, r.TLS.CurveID)
		w.Write([]byte("ok\n"))
	})
	go func() {
		srv := &http.Server{Addr: ":8443", Handler: mux, TLSConfig: tlsConfig()}
		log.Fatal(srv.ListenAndServeTLS("", ""))
	}()

	lis, err := net.Listen("tcp", ":9443")
	if err != nil {
		log.Fatal(err)
	}
	gs := grpc.NewServer(grpc.Creds(credentials.NewTLS(tlsConfig())),
		grpc.UnaryInterceptor(func(ctx context.Context, req any, info *grpc.UnaryServerInfo, h grpc.UnaryHandler) (any, error) {
			if p, ok := peer.FromContext(ctx); ok {
				if ti, ok := p.AuthInfo.(credentials.TLSInfo); ok {
					log.Printf("grpc method=%s tls_group=%v", info.FullMethod, ti.State.CurveID)
				}
			}
			return h(ctx, req)
		}))
	healthpb.RegisterHealthServer(gs, health.NewServer())
	log.Fatal(gs.Serve(lis))
}
```

`cmd/lambda/main.go` (Lambda handler)

```go
package main

import (
	"context"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sts"
)

func handler(ctx context.Context) (string, error) {
	cfg, err := config.LoadDefaultConfig(ctx) // default HTTP client: PQ outside FIPS mode
	if err != nil {
		return "", err
	}
	out, err := sts.NewFromConfig(cfg).GetCallerIdentity(ctx, &sts.GetCallerIdentityInput{})
	if err != nil {
		return "", err
	}
	return *out.Arn, nil
}

func main() { lambda.Start(handler) }
```

`Makefile` (Lambda zip)

```makefile
GO ?= go
build-lambda:
	GOOS=linux GOARCH=arm64 CGO_ENABLED=0 $(GO) build -trimpath -tags lambda.norpc -o dist/bootstrap ./cmd/lambda
	$(GO) version -m dist/bootstrap | grep -E 'go1\.|DefaultGODEBUG' || true
	cd dist && zip -q function.zip bootstrap
```

`Dockerfile` (ECS, Fargate, EKS: distroless)

```dockerfile
# Pin both images by digest in your registry mirror.
FROM golang:1.26 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -o /out/server ./cmd/server \
 && go version -m /out/server | grep -q 'tlsmlkem=0' && { echo 'classical build: raise go line'; exit 1; } || true

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/server /server
# Optional while go.mod is < 1.26:
# ENV GODEBUG=tlsmlkem=1,tlssecpmlkem=1
USER nonroot:nonroot
EXPOSE 8443 9443
ENTRYPOINT ["/server"]
```

`Dockerfile.lambda` (Lambda container image)

```dockerfile
FROM golang:1.26 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -tags lambda.norpc -o /out/main ./cmd/lambda

FROM public.ecr.aws/lambda/provided:al2023
COPY --from=build /out/main ./main
ENTRYPOINT ["./main"]
```

`Dockerfile.fips` (FIPS 140-3 build)

```dockerfile
FROM golang:1.26 AS build
WORKDIR /src
COPY . .
# Native Go FIPS module; do NOT also set GOEXPERIMENT=boringcrypto (panics at start).
RUN CGO_ENABLED=0 GOFIPS140=v1.26.0 go build -trimpath -o /out/server ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/server /server
ENTRYPOINT ["/server"]
```

`template.yaml` (SAM, Lambda zip)

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Resources:
  PaymentsFunction:
    Type: AWS::Serverless::Function
    Metadata:
      BuildMethod: go1.x
    Properties:
      CodeUri: cmd/lambda/
      Handler: bootstrap
      Runtime: provided.al2023
      Architectures: [arm64]
      Timeout: 10
      Environment:
        Variables:
          # Only while go.mod is below 1.26. Remove after raising the go line.
          GODEBUG: tlsmlkem=1,tlssecpmlkem=1
```

`lambda-cfn.yaml` (plain CloudFormation, zip in S3)

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Parameters:
  CodeBucket: {Type: String}
  CodeKey: {Type: String, Default: payments/function.zip}
  RoleArn: {Type: String}
Resources:
  PaymentsFunction:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: payments
      PackageType: Zip
      Runtime: provided.al2023
      Handler: bootstrap
      Architectures: [arm64]
      Role: !Ref RoleArn
      Code: {S3Bucket: !Ref CodeBucket, S3Key: !Ref CodeKey}
      Environment:
        Variables:
          GODEBUG: tlsmlkem=1,tlssecpmlkem=1
```

`lambda.tf` (Terraform, zip and image)

```hcl
resource "aws_lambda_function" "payments" {
  function_name    = "payments"
  role             = var.lambda_role_arn
  runtime          = "provided.al2023"
  handler          = "bootstrap"
  architectures    = ["arm64"]
  filename         = "${path.module}/dist/function.zip"
  source_code_hash = filebase64sha256("${path.module}/dist/function.zip")

  environment {
    variables = {
      GODEBUG = "tlsmlkem=1,tlssecpmlkem=1" # only while go.mod < 1.26
    }
  }
}

resource "aws_lambda_function" "payments_image" {
  function_name = "payments-image"
  role          = var.lambda_role_arn
  package_type  = "Image"
  image_uri     = "111122223333.dkr.ecr.us-east-1.amazonaws.com/payments@sha256:<digest>"
  architectures = ["arm64"]
}
```

`taskdef.json` (ECS / Fargate)

```json
{
  "family": "payments-api",
  "requiresCompatibilities": ["FARGATE"],
  "networkMode": "awsvpc",
  "cpu": "512",
  "memory": "1024",
  "runtimePlatform": {"cpuArchitecture": "ARM64", "operatingSystemFamily": "LINUX"},
  "executionRoleArn": "arn:aws:iam::111122223333:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::111122223333:role/payments-task",
  "containerDefinitions": [
    {
      "name": "api",
      "image": "111122223333.dkr.ecr.us-east-1.amazonaws.com/payments-api@sha256:<digest>",
      "essential": true,
      "portMappings": [{"containerPort": 8443, "protocol": "tcp"}, {"containerPort": 9443, "protocol": "tcp"}],
      "environment": [
        {"name": "GODEBUG", "value": "tlsmlkem=1,tlssecpmlkem=1"},
        {"name": "TLS_PQ_ONLY", "value": "0"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {"awslogs-group": "/ecs/payments-api", "awslogs-region": "us-east-1", "awslogs-stream-prefix": "api"}
      }
    }
  ]
}
```

`ecs-task.tf` (Terraform for the same task definition)

```hcl
resource "aws_ecs_task_definition" "payments_api" {
  family                   = "payments-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
  container_definitions = jsonencode([{
    name         = "api"
    image        = var.image # repo@sha256:digest
    essential    = true
    portMappings = [{ containerPort = 8443, protocol = "tcp" }, { containerPort = 9443, protocol = "tcp" }]
    environment  = [{ name = "GODEBUG", value = "tlsmlkem=1,tlssecpmlkem=1" }]
  }])
}
```

`deployment.yaml` (EKS)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payments-api
  namespace: payments
spec:
  replicas: 2
  selector:
    matchLabels: {app: payments-api}
  template:
    metadata:
      labels: {app: payments-api}
    spec:
      securityContext: {runAsNonRoot: true}
      containers:
        - name: api
          image: 111122223333.dkr.ecr.us-east-1.amazonaws.com/payments-api@sha256:<digest>
          ports:
            - {containerPort: 8443, name: https}
            - {containerPort: 9443, name: grpc}
          env:
            - name: GODEBUG          # only while go.mod < 1.26
              value: tlsmlkem=1,tlssecpmlkem=1
            - name: TLS_PQ_ONLY
              value: "0"
          volumeMounts:
            - {name: tls, mountPath: /etc/tls, readOnly: true}
      volumes:
        - name: tls
          secret: {secretName: payments-api-tls}
```

`/etc/systemd/system/payments-api.service` (EC2)

```ini
[Unit]
Description=payments API (Go)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/opt/payments/server
User=payments
# Only while the binary's go.mod is < 1.26:
Environment=GODEBUG=tlsmlkem=1,tlssecpmlkem=1
Environment=TLS_PQ_ONLY=0
Restart=on-failure
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

`go-pq-posture.sh` (CI gate and host or image scan)

```sh
#!/bin/sh
# Usage: go-pq-posture.sh <dir-with-go-binaries>   (needs a Go toolchain on PATH)
# Fails if any Go binary is classical by build. Runtime GODEBUG must be checked separately.
rc=0
for f in $(find "$1" -type f -perm -u+x); do
  info=$(go version -m "$f" 2>/dev/null) || continue      # not a Go binary
  ver=$(echo "$info" | head -1 | sed -E 's/.*go1\.([0-9]+).*/\1/')
  dbg=$(echo "$info" | grep -o 'DefaultGODEBUG=[^ ]*')
  exp=$(echo "$info" | grep -o 'GOEXPERIMENT=[^ ]*')
  if [ "$ver" -lt 24 ]; then echo "FAIL $f go1.$ver: no ML-KEM"; rc=1
  elif echo "$dbg" | grep -q 'tlsmlkem=0'; then echo "FAIL $f go1.$ver: tlsmlkem=0 (go.mod go line < 1.24)"; rc=1
  elif echo "$exp" | grep -q boringcrypto; then echo "WARN $f boringcrypto: check for crypto/tls/fipsonly"
  elif echo "$dbg" | grep -q 'fips140=on' && [ "$ver" -lt 25 ]; then echo "FAIL $f go1.$ver FIPS: no PQ before 1.25"; rc=1
  else echo "OK   $f go1.$ver $dbg"; fi
done
exit $rc
```

To scan an image: `docker create --name x <image>; docker cp x:/server ./scan/; docker rm x; ./go-pq-posture.sh ./scan`. To scan EC2 hosts, run it through SSM Run Command on the binary folder.

Test kit used for this tab (scripts and raw output): `servers.sh`, `probe/main.go`, `build.sh`, `run-clients.sh`, `srv/main.go`, `libs/main.go`, `extra/main.go`, `run-server-tests.sh`, `run-libs.sh`, with outputs `clients.out`, `server-tests.out`, `libs.out`, `awsfix.out`, `compute.out`, `gosrv.log`.
