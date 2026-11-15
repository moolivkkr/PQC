## Full configuration files

Every file referenced above. The two `.cnf` files, `tls-pq.js`, `pq-check.js` and `server.js` were run in the tests; the IaC files are written to the documented resource schemas and were not deployed (no AWS account in the test lab).

`pq-tls/openssl-pq-node.cnf` (Lambda nodejs22/24: AWS's file with the hybrid group added first; Tested)

```ini
# Replaces the Lambda Node.js runtime's /var/runtime/openssl_conf/openssl.cnf (same structure),
# with the hybrid post-quantum group first. Node reads the nodejs_conf section.
nodejs_conf = openssl_init

[openssl_init]
ssl_conf = ssl_sect

[ssl_sect]
system_default = system_default_sect

[system_default_sect]
Groups = *X25519MLKEM768:*X25519:secp256r1:X448:secp521r1:secp384r1:ffdhe2048:ffdhe3072:ffdhe4096:ffdhe6144:ffdhe8192
```

`/etc/app/openssl-pq-node-system.cnf` (distro Node on system OpenSSL 3.5+, when you can't change the host policy; Tested on AL2023 nodejs22)

```ini
# Node reads nodejs_conf by default and openssl_conf with --openssl-shared-config; both point here.
openssl_conf = pq_init
nodejs_conf = pq_init

[pq_init]
ssl_conf = pq_ssl

[pq_ssl]
system_default = pq_system_default

[pq_system_default]
Groups = *X25519MLKEM768:*X25519:secp256r1:X448:secp521r1:secp384r1:ffdhe2048:ffdhe3072:ffdhe4096:ffdhe6144:ffdhe8192
```

`check-lambda-node-conf.sh` (pipeline check: fail when AWS changes its file in a way ours doesn't mirror)

```bash
#!/bin/bash
# Usage: check-lambda-node-conf.sh 24   -> compares AWS's file in the current base image with ours, ignoring Groups.
set -euo pipefail
img="public.ecr.aws/lambda/nodejs:${1:?node major}"
norm() { grep -vE '^\s*(#|$)' | grep -v '^Groups' ; }
diff <(docker run --rm --entrypoint cat "$img" /var/runtime/openssl_conf/openssl.cnf | norm) \
     <(norm < pq-tls/openssl-pq-node.cnf) && echo "OK: only Groups differs"
docker run --rm --entrypoint grep "$img" -n 'OPENSSL_CONF' /var/runtime/bootstrap
```

`src/tls-pq.js` (shared TLS options with feature detection; Tested on Node 20, 22, 24)

```js
'use strict';
const tls = require('node:tls');
const https = require('node:https');

const PQ_GROUPS = 'X25519MLKEM768:X25519:P-256:P-384';

function pqCapable() {
  try { tls.createSecureContext({ ecdhCurve: 'X25519MLKEM768' }); return true; } catch { return false; }
}

// Spread into tls.connect / https.Agent / undici connect / pg ssl / ioredis tls / kafkajs ssl.
function tlsOptions(extra = {}) {
  const o = { minVersion: 'TLSv1.2', ...extra };
  if (o.ecdhCurve && pqCapable() && !o.ecdhCurve.includes('MLKEM')) {
    o.ecdhCurve = `X25519MLKEM768:${o.ecdhCurve}`; // pinned list: hybrid first, theirs as fallback
  }
  return o;
}

function httpsAgent(extra = {}) {
  return new https.Agent({ keepAlive: true, ...tlsOptions(extra) });
}

function report() {
  return { node: process.version, openssl: process.versions.openssl, pqCapable: pqCapable(),
    OPENSSL_CONF: process.env.OPENSSL_CONF || null, NODE_OPTIONS: process.env.NODE_OPTIONS || null,
    DEFAULT_ECDH_CURVE: tls.DEFAULT_ECDH_CURVE };
}

module.exports = { PQ_GROUPS, pqCapable, tlsOptions, httpsAgent, report };
```

`pq-check.js` (posture + live check; exit 1 if any target is not PQ; Tested)

```js
#!/usr/bin/env node
'use strict';
const tls = require('node:tls');
let pq = false;
try { tls.createSecureContext({ ecdhCurve: 'X25519MLKEM768' }); pq = true; } catch {}
console.log(JSON.stringify({ posture: { node: process.version, openssl: process.versions.openssl, pqCapable: pq,
  OPENSSL_CONF: process.env.OPENSSL_CONF || null, NODE_OPTIONS: process.env.NODE_OPTIONS || null,
  DEFAULT_ECDH_CURVE: tls.DEFAULT_ECDH_CURVE } }));
let bad = !pq;
const one = (t) => new Promise((done) => {
  const [host, port = '443'] = t.split(':');
  const s = tls.connect({ host, port: Number(port), servername: host }, () => {
    const k = s.getEphemeralKeyInfo() || {};
    // Node 24+: {type:'TLSGroup',name:'X25519MLKEM768'}; Node 22: {} for ML-KEM; classical: {type:'ECDH',name:'X25519'}
    const group = k.name || (s.getProtocol() === 'TLSv1.3' && !k.type ? 'non-EC group (ML-KEM hybrid on Node 22)' : 'unknown');
    const ok = /MLKEM|non-EC/.test(group);
    if (!ok) bad = true;
    console.log(JSON.stringify({ target: t, protocol: s.getProtocol(), group, pq: ok }));
    s.end(); done();
  });
  s.setTimeout(8000, () => s.destroy(new Error('timeout')));
  s.on('error', (e) => { bad = true; console.log(JSON.stringify({ target: t, error: e.code || e.message })); done(); });
});
(async () => { for (const t of process.argv.slice(2)) await one(t); process.exit(bad ? 1 : 0); })();
```

`server.js` (Express on HTTPS; Tested on node:24-slim: PQ client X25519MLKEM768, classical client X25519, TLS 1.2 client OK)

```js
'use strict';
const fs = require('node:fs');
const https = require('node:https');
const express = require('express');

const app = express();
app.get('/healthz', (req, res) => res.send('ok'));
app.get('/', (req, res) => res.send(`tls ${req.socket.getProtocol()}`));

const opts = {
  key: fs.readFileSync(process.env.TLS_KEY || '/etc/app/tls/server.key'),
  cert: fs.readFileSync(process.env.TLS_CERT || '/etc/app/tls/server.pem'),
  minVersion: process.env.TLS_MIN_VERSION || 'TLSv1.2', // 'TLSv1.3' to refuse TLS 1.2 clients
};
// Optional explicit list. Must start with X25519MLKEM768, or PQ clients are silently downgraded.
if (process.env.TLS_ECDH_CURVE) opts.ecdhCurve = process.env.TLS_ECDH_CURVE;

https.createServer(opts, app).listen(Number(process.env.PORT || 8443), () =>
  console.log(JSON.stringify({ msg: 'listening', node: process.version, openssl: process.versions.openssl,
    ecdhCurve: opts.ecdhCurve || 'default', minVersion: opts.minVersion })));
```

`template.yaml` (SAM, Lambda zip)

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Globals:
  Function:
    Runtime: nodejs24.x
    Architectures: [arm64]
    Environment:
      Variables:
        OPENSSL_CONF: /var/task/pq-tls/openssl-pq-node.cnf
Resources:
  OrdersFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: build/   # contains index.mjs, node_modules/, pq-tls/openssl-pq-node.cnf
      Handler: index.handler
      Timeout: 10
```

`lambda-cfn.yaml` (plain CloudFormation, Lambda zip)

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Parameters:
  CodeBucket: { Type: String }
  CodeKey: { Type: String }
  RoleArn: { Type: String }
Resources:
  OrdersFunction:
    Type: AWS::Lambda::Function
    Properties:
      Runtime: nodejs24.x
      Architectures: [arm64]
      Handler: index.handler
      Role: !Ref RoleArn
      Code: { S3Bucket: !Ref CodeBucket, S3Key: !Ref CodeKey }
      Environment:
        Variables:
          OPENSSL_CONF: /var/task/pq-tls/openssl-pq-node.cnf
```

`lambda.tf` (Terraform, Lambda zip)

```hcl
resource "aws_lambda_function" "orders" {
  function_name    = "orders"
  runtime          = "nodejs24.x"
  architectures    = ["arm64"]
  handler          = "index.handler"
  role             = aws_iam_role.orders.arn
  filename         = "build/function.zip" # includes pq-tls/openssl-pq-node.cnf
  source_code_hash = filebase64sha256("build/function.zip")

  environment {
    variables = {
      OPENSSL_CONF = "/var/task/pq-tls/openssl-pq-node.cnf"
      # Alternative (Tested): NODE_OPTIONS = "--openssl-config=/var/task/pq-tls/openssl-pq-node.cnf"
    }
  }
}
```

`Dockerfile.lambda` (Lambda container image)

```dockerfile
FROM public.ecr.aws/lambda/nodejs:24@sha256:eb0de3ee81b4638149f0b1bcab2c657603a23a0c221a4b5678be29b48265bd31
COPY package.json package-lock.json ${LAMBDA_TASK_ROOT}/
RUN npm ci --omit=dev
COPY index.mjs ${LAMBDA_TASK_ROOT}/
COPY pq-tls/openssl-pq-node.cnf ${LAMBDA_TASK_ROOT}/pq-tls/openssl-pq-node.cnf
# The bootstrap only sets its own (classical) file when OPENSSL_CONF is unset.
ENV OPENSSL_CONF=/var/task/pq-tls/openssl-pq-node.cnf
CMD ["index.handler"]
```

`Dockerfile` (Fargate / ECS / EKS, official image: nothing PQ-specific)

```dockerfile
FROM node:24-slim@sha256:dc26ae92c9fb15cf6b1d63e20f0944b2efe0f115b20e00be48fb23fceb061c54
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY . .
ENV NODE_ENV=production
# Build-time guard: fail the build if this Node can't do ML-KEM.
RUN node pq-check.js
USER node
EXPOSE 8443
CMD ["node", "server.js"]
```

`Dockerfile.al2023` (AL2023 base with the distro Node package; Tested)

```dockerfile
FROM public.ecr.aws/amazonlinux/amazonlinux:2023
RUN dnf -y install nodejs22 crypto-policies-scripts shadow-utils \
 && update-crypto-policies --set DEFAULT:PQ \
 && dnf clean all && useradd -r app
WORKDIR /app
COPY --chown=app package.json package-lock.json ./
RUN npm ci --omit=dev
COPY --chown=app . .
RUN node pq-check.js
USER app
CMD ["node", "server.js"]
```

`taskdef.json` (ECS / Fargate; no TLS setting needed)

```json
{
  "family": "orders",
  "requiresCompatibilities": ["FARGATE"],
  "networkMode": "awsvpc",
  "cpu": "512",
  "memory": "1024",
  "runtimePlatform": { "cpuArchitecture": "ARM64", "operatingSystemFamily": "LINUX" },
  "executionRoleArn": "arn:aws:iam::111122223333:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "orders",
      "image": "111122223333.dkr.ecr.eu-west-1.amazonaws.com/orders@sha256:<digest>",
      "essential": true,
      "portMappings": [{ "containerPort": 8443, "protocol": "tcp" }],
      "environment": [
        { "name": "NODE_ENV", "value": "production" },
        { "name": "TLS_MIN_VERSION", "value": "TLSv1.2" }
      ],
      "healthCheck": { "command": ["CMD", "node", "-e", "require('https').get({host:'localhost',port:8443,path:'/healthz',rejectUnauthorized:false},r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"], "interval": 30, "timeout": 5, "retries": 3 }
    }
  ]
}
```

`ecs.tf` (Terraform; distro-Node images only need the commented line)

```hcl
resource "aws_ecs_task_definition" "orders" {
  family                   = "orders"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_exec.arn
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
  container_definitions = jsonencode([{
    name         = "orders"
    image        = "${aws_ecr_repository.orders.repository_url}@${var.image_digest}"
    essential    = true
    portMappings = [{ containerPort = 8443, protocol = "tcp" }]
    environment = [
      { name = "NODE_ENV", value = "production" },
      # { name = "OPENSSL_CONF", value = "/etc/app/openssl-pq-node-system.cnf" }, # distro Node without DEFAULT:PQ
    ]
  }])
}
```

`ecs-cfn.yaml` (CloudFormation)

```yaml
Resources:
  OrdersTask:
    Type: AWS::ECS::TaskDefinition
    Properties:
      Family: orders
      RequiresCompatibilities: [FARGATE]
      NetworkMode: awsvpc
      Cpu: '512'
      Memory: '1024'
      ExecutionRoleArn: !Ref ExecRoleArn
      RuntimePlatform: { CpuArchitecture: ARM64, OperatingSystemFamily: LINUX }
      ContainerDefinitions:
        - Name: orders
          Image: !Sub '${AWS::AccountId}.dkr.ecr.${AWS::Region}.amazonaws.com/orders@${ImageDigest}'
          Essential: true
          PortMappings: [{ ContainerPort: 8443, Protocol: tcp }]
          Environment:
            - { Name: NODE_ENV, Value: production }
Parameters:
  ExecRoleArn: { Type: String }
  ImageDigest: { Type: String }
```

`deployment.yaml` (EKS)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: orders }
spec:
  replicas: 2
  selector: { matchLabels: { app: orders } }
  template:
    metadata: { labels: { app: orders } }
    spec:
      containers:
        - name: orders
          image: 111122223333.dkr.ecr.eu-west-1.amazonaws.com/orders@sha256:<digest>
          ports: [{ containerPort: 8443 }]
          env:
            - { name: NODE_ENV, value: production }
            # Distro Node without DEFAULT:PQ only:
            # - { name: OPENSSL_CONF, value: /etc/app/openssl-pq-node-system.cnf }
          volumeMounts: [{ name: tls, mountPath: /etc/app/tls, readOnly: true }]
          readinessProbe: { httpGet: { path: /healthz, port: 8443, scheme: HTTPS } }
      volumes:
        - name: tls
          secret: { secretName: orders-tls }
```

`/etc/systemd/system/orders.service` (EC2)

```ini
[Unit]
Description=orders API (Node.js)
After=network-online.target
Wants=network-online.target

[Service]
User=app
WorkingDirectory=/srv/orders
# Official binaries 22.20+/24.9+: nothing else needed.
ExecStart=/opt/node-v24/bin/node /srv/orders/server.js
Environment=NODE_ENV=production
Environment=TLS_KEY=/etc/app/tls/server.key
Environment=TLS_CERT=/etc/app/tls/server.pem
# AL2023 dnf nodejs22 without the DEFAULT:PQ host policy:
# Environment=OPENSSL_CONF=/etc/app/openssl-pq-node-system.cnf
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

`pq-node-posture.json` (SSM Command document: reports every running Node process)

```json
{
  "schemaVersion": "2.2",
  "description": "Report Node.js version, OpenSSL version and TLS-relevant environment for every running node process.",
  "mainSteps": [
    {
      "action": "aws:runShellScript",
      "name": "nodePqPosture",
      "inputs": {
        "runCommand": [
          "command -v update-crypto-policies >/dev/null && echo \"crypto-policy: $(update-crypto-policies --show)\"",
          "for pid in $(pgrep -x node); do exe=$(readlink /proc/$pid/exe); v=$($exe -p 'process.version+\" openssl=\"+process.versions.openssl' 2>/dev/null); env=$(tr '\\0' '\\n' < /proc/$pid/environ | grep -E '^(OPENSSL_CONF|NODE_OPTIONS)=' | tr '\\n' ' '); echo \"pid=$pid exe=$exe $v $env\"; done"
        ]
      }
    }
  ]
}
```
