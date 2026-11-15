## Full configuration files

Every file the sections above reference, complete. Paths are relative to the repository or package root unless they start with `/`.

`pq-tls/openssl-pq.cnf` (Lambda python3.12+, Lambda images, AL2023 containers and hosts; Tested)

```ini
# Keeps the AL2023 defaults and only changes the key-exchange group list, PQ hybrid first.
# Ship it in the package or image and point OPENSSL_CONF at it.
openssl_conf = openssl_init

.include /etc/pki/tls/openssl.d

[openssl_init]
ssl_conf = ssl_module
providers = provider_sect

[provider_sect]
default = default_sect

[default_sect]
activate = 1

[ssl_module]
system_default = pq_system_default

[pq_system_default]
.include = /etc/crypto-policies/back-ends/opensslcnf.config
Groups = *X25519MLKEM768:*X25519:secp256r1:X448:secp521r1:secp384r1:ffdhe2048:ffdhe3072:ffdhe4096:ffdhe6144:ffdhe8192
```

`pq-tls/pyshim/sitecustomize.py` (Lambda python3.9 to 3.11 bridge only; Tested on Lambda base images 3.9 and 3.11)

```python
# pq-tls shim for Lambda Python 3.9-3.11 (system OpenSSL 1.1.1, no ML-KEM).
# Routes urllib3 (requests) and botocore (boto3) through pyOpenSSL, whose bundled
# OpenSSL (from the cryptography wheel) offers X25519MLKEM768 by default.
# Python's own ssl module, http.client and aiohttp are NOT covered.
#
# sitecustomize runs before the Lambda bootstrap has put /var/runtime and the layer's
# site-packages on sys.path, so patching is deferred until each module is first imported.
# Whichever copy the function resolves (its own bundled one or the runtime's) is patched.
import os
import sys

if os.environ.get("PQ_TLS_DISABLE") != "1":
    import importlib.abc
    import importlib.util

    def _log(msg):
        print("pq-tls: python legacy shim: " + msg, file=sys.stderr)

    def _patch_urllib3(module):
        # Append the function package and the layer's site-packages (at the end, so
        # precedence is unchanged) so pyOpenSSL is found in the package or a layer.
        for site in (os.environ.get("LAMBDA_TASK_ROOT", "/var/task"),
                     "/opt/python/lib/python%d.%d/site-packages" % sys.version_info[:2]):
            if site not in sys.path:
                sys.path.append(site)
        import urllib3.contrib.pyopenssl as p
        p.inject_into_urllib3()
        from cryptography.hazmat.backends.openssl.backend import backend
        _log("urllib3 -> pyOpenSSL (%s)" % backend.openssl_version_text())

    def _patch_botocore(module):
        # botocore deliberately keeps the stdlib SSLContext even when urllib3 is patched.
        import urllib3.contrib.pyopenssl as p
        module.SSLContext = p.PyOpenSSLContext
        _log("botocore -> pyOpenSSL")

    _PATCHES = {"urllib3": _patch_urllib3, "botocore.httpsession": _patch_botocore}

    class _Hook(importlib.abc.MetaPathFinder):
        def find_spec(self, name, path, target=None):
            patch = _PATCHES.pop(name, None)
            if patch is None:
                return None
            sys.meta_path.remove(self)
            try:
                spec = importlib.util.find_spec(name)
            finally:
                if _PATCHES and self not in sys.meta_path:
                    sys.meta_path.insert(0, self)
            if spec is None or spec.loader is None:
                return spec
            exec_module = spec.loader.exec_module

            def exec_and_patch(module):
                exec_module(module)
                try:
                    patch(module)
                except Exception as e:  # never break the function
                    _log("not active for %s: %s: %s" % (name, type(e).__name__, e))

            spec.loader.exec_module = exec_and_patch
            return spec

    sys.meta_path.insert(0, _Hook())
```

`template.yaml` (AWS SAM, Lambda zip, python3.13)

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Transform: AWS::Serverless-2016-10-31
Resources:
  OrdersFn:
    Type: AWS::Serverless::Function
    Properties:
      Runtime: python3.13
      Architectures: [arm64]
      Handler: app.handler
      CodeUri: build/            # contains app.py, your deps and pq-tls/openssl-pq.cnf
      Timeout: 30
      Environment:
        Variables:
          OPENSSL_CONF: /var/task/pq-tls/openssl-pq.cnf
```

`cfn/lambda.yaml` (CloudFormation, Lambda zip)

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Parameters:
  CodeBucket: {Type: String}
  CodeKey: {Type: String}
  RoleArn: {Type: String}
Resources:
  OrdersFn:
    Type: AWS::Lambda::Function
    Properties:
      Runtime: python3.13
      Architectures: [arm64]
      Handler: app.handler
      Role: !Ref RoleArn
      Code: {S3Bucket: !Ref CodeBucket, S3Key: !Ref CodeKey}
      Environment:
        Variables:
          OPENSSL_CONF: /var/task/pq-tls/openssl-pq.cnf
```

`terraform/lambda.tf` (Lambda zip)

```hcl
data "archive_file" "orders" {
  type        = "zip"
  source_dir  = "${path.module}/build" # app.py, deps, pq-tls/openssl-pq.cnf
  output_path = "${path.module}/orders.zip"
}

resource "aws_lambda_function" "orders" {
  function_name    = "orders"
  role             = var.role_arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "app.handler"
  filename         = data.archive_file.orders.output_path
  source_code_hash = data.archive_file.orders.output_base64sha256

  environment {
    variables = {
      OPENSSL_CONF = "/var/task/pq-tls/openssl-pq.cnf"
    }
  }
}
```

`terraform/lambda-legacy.tf` (python3.11 bridge until the upgrade; same for CloudFormation: set `PYTHONPATH`)

```hcl
resource "aws_lambda_function" "legacy" {
  function_name    = "legacy"
  role             = var.role_arn
  runtime          = "python3.11"
  handler          = "app.handler"
  filename         = "legacy.zip" # app.py, pyopenssl + cryptography (built for the arch), pq-tls/pyshim/
  source_code_hash = filebase64sha256("legacy.zip")
  environment {
    variables = {
      PYTHONPATH = "/var/task/pq-tls/pyshim"
    }
  }
}
```

`Dockerfile.lambda` (Lambda container image)

```dockerfile
FROM public.ecr.aws/lambda/python:3.13
COPY requirements.txt ${LAMBDA_TASK_ROOT}/
RUN pip install --no-cache-dir -r ${LAMBDA_TASK_ROOT}/requirements.txt -t ${LAMBDA_TASK_ROOT}
COPY app.py ${LAMBDA_TASK_ROOT}/
COPY pq-tls/openssl-pq.cnf ${LAMBDA_TASK_ROOT}/pq-tls/openssl-pq.cnf
ENV OPENSSL_CONF=/var/task/pq-tls/openssl-pq.cnf
CMD ["app.handler"]
```

`Dockerfile` (Fargate / ECS / EKS, Debian 13 trixie: PQ with no extra setting)

```dockerfile
FROM python:3.13-slim-trixie
RUN useradd -r -u 10001 app
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
# Fails the build if this image's OpenSSL cannot do ML-KEM.
RUN python -c "import ssl,sys; sys.exit(0 if ssl.OPENSSL_VERSION_INFO >= (3,5) else 'OpenSSL < 3.5')"
USER app
EXPOSE 8443
CMD ["gunicorn", "-c", "gunicorn.conf.py", "app:wsgi"]
```

`Dockerfile.al2023` (Fargate / ECS / EKS on Amazon Linux 2023)

```dockerfile
FROM public.ecr.aws/amazonlinux/amazonlinux:2023
RUN dnf -y install python3.12 python3.12-pip && dnf clean all
WORKDIR /app
COPY requirements.txt .
RUN python3.12 -m pip install --no-cache-dir -r requirements.txt
COPY . .
# Option A (image-wide): switch the crypto policy.
#   RUN dnf -y install crypto-policies-scripts && update-crypto-policies --set DEFAULT:PQ
# Option B (this process only): ship the config file.
COPY pq-tls/openssl-pq.cnf /etc/pq-tls/openssl-pq.cnf
ENV OPENSSL_CONF=/etc/pq-tls/openssl-pq.cnf
CMD ["python3.12", "-m", "gunicorn", "-c", "gunicorn.conf.py", "app:wsgi"]
```

`ecs/taskdef.json` (Fargate; only the PQ-relevant parts shown are required)

```json
{
  "family": "orders",
  "requiresCompatibilities": ["FARGATE"],
  "networkMode": "awsvpc",
  "cpu": "512",
  "memory": "1024",
  "runtimePlatform": {"cpuArchitecture": "ARM64", "operatingSystemFamily": "LINUX"},
  "executionRoleArn": "arn:aws:iam::111122223333:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "orders",
      "image": "111122223333.dkr.ecr.us-east-1.amazonaws.com/orders@sha256:<digest>",
      "essential": true,
      "portMappings": [{"containerPort": 8443, "protocol": "tcp"}],
      "environment": [
        {"name": "OPENSSL_CONF", "value": "/etc/pq-tls/openssl-pq.cnf"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/orders",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "orders"
        }
      }
    }
  ]
}
```

`k8s/deployment.yaml` (EKS)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders
spec:
  replicas: 2
  selector:
    matchLabels: {app: orders}
  template:
    metadata:
      labels: {app: orders}
    spec:
      containers:
        - name: orders
          image: 111122223333.dkr.ecr.us-east-1.amazonaws.com/orders@sha256:<digest>
          ports:
            - containerPort: 8443
          env:
            - name: OPENSSL_CONF          # AL2023-based image only; trixie/alpine need nothing
              value: /etc/pq-tls/openssl-pq.cnf
          readinessProbe:
            tcpSocket: {port: 8443}
```

`gunicorn.conf.py` (gunicorn terminates TLS; Tested on 3.12, 3.13 and 3.15; set_groups applies on 3.15 only)

```python
import os
import ssl

bind = "0.0.0.0:8443"
workers = 2
certfile = "/etc/tls/server.pem"
keyfile = "/etc/tls/server.key"


def ssl_context(conf, default_ssl_context_factory):
    ctx = default_ssl_context_factory()
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    if hasattr(ctx, "set_groups"):  # Python 3.15+
        # PQ hybrid first, classical fallback kept. Set PQ_GROUPS=X25519MLKEM768 to refuse classical clients.
        ctx.set_groups(os.environ.get("PQ_GROUPS", "X25519MLKEM768:X25519:secp256r1"))
    return ctx
```

`serve_uvicorn.py` (uvicorn terminates TLS with an explicit group list; Tested on 3.15: PQ-first and PQ-only)

```python
import os
import ssl

import uvicorn

config = uvicorn.Config(
    "app:asgi",
    host="0.0.0.0",
    port=int(os.environ.get("PORT", "8443")),
    ssl_certfile=os.environ.get("TLS_CERT", "/etc/tls/server.pem"),
    ssl_keyfile=os.environ.get("TLS_KEY", "/etc/tls/server.key"),
)
config.load()  # builds config.ssl; Server.run() skips load() when already loaded
config.ssl.minimum_version = ssl.TLSVersion.TLSv1_2
if hasattr(config.ssl, "set_groups"):
    config.ssl.set_groups(os.environ.get("PQ_GROUPS", "X25519MLKEM768:X25519:secp256r1"))
uvicorn.Server(config).run()
```

`/etc/systemd/system/orders.service` (EC2, AL2023; scope the config to one service)

```ini
[Unit]
Description=orders API (gunicorn)
After=network-online.target
Wants=network-online.target

[Service]
User=orders
WorkingDirectory=/opt/orders
Environment=OPENSSL_CONF=/etc/pq-tls/openssl-pq.cnf
ExecStart=/opt/orders/venv/bin/gunicorn -c /opt/orders/gunicorn.conf.py app:wsgi
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

`ssm/pq-crypto-policy.yaml` (SSM Command document for AL2023 hosts; run from a State Manager association)

```yaml
schemaVersion: "2.2"
description: Set the AL2023 crypto policy to DEFAULT:PQ and restart listed services.
parameters:
  Services:
    type: String
    default: "orders"
    description: Space-separated systemd units to restart after the change.
mainSteps:
  - action: aws:runShellScript
    name: setPqPolicy
    precondition:
      StringEquals: [platformType, Linux]
    inputs:
      runCommand:
        - set -euo pipefail
        - . /etc/os-release
        - '[ "$ID" = amzn ] && [ "$VERSION_ID" = 2023 ] || { echo "not AL2023, skipping"; exit 0; }'
        - dnf -y install crypto-policies-scripts
        - '[ "$(update-crypto-policies --show)" = DEFAULT:PQ ] || update-crypto-policies --set DEFAULT:PQ'
        - for s in {{ Services }}; do systemctl restart "$s"; done
        - update-crypto-policies --show
```

`pq_probe.py` (posture and live check; run inside the same image, env and user as the service)

```python
"""pq_probe.py - report whether this Python process negotiates hybrid PQ TLS.

Usage:  python3 pq_probe.py [host[:port] ...]     default: kms.us-east-1.amazonaws.com:443
Exit code 0 = every target negotiated X25519MLKEM768 (3.15+) or connected (older: see note).
"""
import os
import socket
import ssl
import sys

targets = sys.argv[1:] or ["kms.us-east-1.amazonaws.com:443"]
print("python   ", sys.version.split()[0])
print("openssl  ", ssl.OPENSSL_VERSION)
print("OPENSSL_CONF", os.environ.get("OPENSSL_CONF", "(unset)"))
major, minor = ssl.OPENSSL_VERSION_INFO[:2]
if (major, minor) < (3, 5):
    print("RESULT    classical: OpenSSL < 3.5 has no ML-KEM; no setting can add it")
    sys.exit(2)
rc = 0
for t in targets:
    host, _, port = t.partition(":")
    ctx = ssl.create_default_context()
    try:
        with socket.create_connection((host, int(port or 443)), timeout=5) as raw:
            with ctx.wrap_socket(raw, server_hostname=host) as s:
                if hasattr(s, "group"):  # Python 3.15+
                    g = s.group()
                    print("RESULT    %s %s group=%s" % (t, s.version(), g))
                    rc |= 0 if g and "MLKEM" in g.upper() else 1
                else:
                    print("RESULT    %s %s connected (group not visible before Python 3.15;"
                          " point this at a PQ-only test server to prove the offer)" % (t, s.version()))
    except Exception as e:
        print("RESULT    %s FAIL %s: %s" % (t, type(e).__name__, e))
        rc |= 1
sys.exit(rc)
```
