## Full configuration files

Every file the sections above refer to, complete. Files marked "tested" were run here on 2026-11-14 (scripts and output under the work dir `deep/dotnet/`). IaC files are written to the documented resource schemas but were not deployed (no AWS credentials here).

**`pq-tls/openssl-pq.cnf`** (Amazon Linux 2023 family only: Lambda dotnet8/dotnet10, provided.al2023, AL2023 containers and EC2; tested). It includes AL2023's crypto-policy file, so don't use it on Debian, Ubuntu or Alpine.

```ini
# Keeps the AL2023 defaults and only changes the key-exchange group list, PQ hybrid first.
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

**`Program.cs`** (Kestrel server; tested on all images in the status matrix)

```csharp
// Kestrel HTTPS server. Endpoint, certificate and TLS protocols come from appsettings.json.
// Kestrel has no key-exchange-group setting: OpenSSL (Linux) or Schannel (Windows) picks the group.
using Microsoft.AspNetCore.Connections.Features;

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.ConfigureKestrel(kestrel =>
{
    kestrel.ConfigureHttpsDefaults(https =>
    {
        // None = OS default (TLS 1.2 + 1.3). Never Tls12 alone: that disables PQ key exchange.
        https.SslProtocols = System.Security.Authentication.SslProtocols.None;
    });
});

var app = builder.Build();

app.MapGet("/", (HttpContext ctx) =>
{
    var tls = ctx.Features.Get<ITlsHandshakeFeature>();
    // .NET does not expose the negotiated group; log protocol and cipher only.
    return $"ok protocol={tls?.Protocol} cipher={tls?.NegotiatedCipherSuite}\n";
});

app.Run();
```

**`appsettings.json`** (tested)

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore.Server.Kestrel.Https": "Debug"
    }
  },
  "AllowedHosts": "*",
  "Kestrel": {
    "EndpointDefaults": {
      "Protocols": "Http1AndHttp2"
    },
    "Endpoints": {
      "Https": {
        "Url": "https://0.0.0.0:8443",
        "SslProtocols": [ "Tls12", "Tls13" ],
        "Certificate": {
          "Path": "/certs/server.pfx",
          "Password": "changeit"
        }
      }
    }
  }
}
```

In production read the certificate password from Secrets Manager or a mounted secret, not the file.

**`App.csproj`** (Kestrel service; tested)

```xml
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <InvariantGlobalization>true</InvariantGlobalization>
  </PropertyGroup>
</Project>
```

The tested build targeted `net8.0` with `<RollForward>Major</RollForward>` so one binary ran on .NET 8 and 10.

**`Function.csproj`** (Lambda zip, dotnet8 or dotnet10 managed runtime: puts the config file at `/var/task/pq-tls/openssl-pq.cnf`)

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <GenerateRuntimeConfigurationFiles>true</GenerateRuntimeConfigurationFiles>
    <AWSProjectType>Lambda</AWSProjectType>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Amazon.Lambda.Core" Version="2.*" />
    <PackageReference Include="Amazon.Lambda.Serialization.SystemTextJson" Version="2.*" />
  </ItemGroup>
  <ItemGroup>
    <!-- Lands in the zip root as pq-tls/openssl-pq.cnf, i.e. /var/task/pq-tls/openssl-pq.cnf -->
    <None Include="pq-tls/openssl-pq.cnf" CopyToOutputDirectory="PreserveNewest" CopyToPublishDirectory="PreserveNewest" />
  </ItemGroup>
</Project>
```

**`FunctionAot.csproj`** (Native AOT on `provided.al2023`; the AOT binary was tested in the `provided.al2023` image)

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <AssemblyName>bootstrap</AssemblyName>
    <PublishAot>true</PublishAot>
    <InvariantGlobalization>true</InvariantGlobalization>
    <StripSymbols>true</StripSymbols>
    <AWSProjectType>Lambda</AWSProjectType>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Amazon.Lambda.RuntimeSupport" Version="1.*" />
    <PackageReference Include="Amazon.Lambda.Serialization.SystemTextJson" Version="2.*" />
  </ItemGroup>
  <ItemGroup>
    <None Include="pq-tls/openssl-pq.cnf" CopyToOutputDirectory="PreserveNewest" CopyToPublishDirectory="PreserveNewest" />
  </ItemGroup>
</Project>
```

Build AOT on Amazon Linux 2023 (or the `public.ecr.aws/sam/build-dotnet10` image) so the binary links against the same glibc as `provided.al2023`.

**`Dockerfile`** (Fargate/ECS/EKS, Alpine: PQ with no config; tested with `aspnet:8.0-alpine` and `aspnet:10.0-alpine`)

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build
WORKDIR /src
COPY . .
RUN dotnet publish -c Release -o /app

FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine
# Pin by digest in production: FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine@sha256:...
WORKDIR /app
COPY --from=build /app .
USER $APP_UID
EXPOSE 8443
ENTRYPOINT ["dotnet", "App.dll"]
```

**`Dockerfile.resolute`** (glibc alternative: Ubuntu 26.04 image, PQ with no config; tested with `aspnet:10.0-resolute` and `10.0-resolute-chiseled`)

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0-resolute AS build
WORKDIR /src
COPY . .
RUN dotnet publish -c Release -o /app

FROM mcr.microsoft.com/dotnet/aspnet:10.0-resolute-chiseled
WORKDIR /app
COPY --from=build /app .
EXPOSE 8443
ENTRYPOINT ["dotnet", "App.dll"]
```

**`Dockerfile.al2023`** (glibc, Amazon Linux 2023 with the config file; tested)

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY . .
RUN dotnet publish -c Release -o /app

FROM public.ecr.aws/amazonlinux/amazonlinux:2023
RUN dnf install -y aspnetcore-runtime-8.0 && dnf clean all
COPY pq-tls/openssl-pq.cnf /etc/pq-tls/openssl-pq.cnf
ENV OPENSSL_CONF=/etc/pq-tls/openssl-pq.cnf
# Alternative to the two lines above (whole image, all OpenSSL users):
# RUN dnf install -y crypto-policies-scripts && update-crypto-policies --set DEFAULT:PQ
WORKDIR /app
COPY --from=build /app .
EXPOSE 8443
ENTRYPOINT ["dotnet", "App.dll"]
```

**`Dockerfile.lambda`** (Lambda container image; tested with `public.ecr.aws/lambda/dotnet:8` and `:10`)

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY . .
RUN dotnet publish -c Release -o /out

FROM public.ecr.aws/lambda/dotnet:10
COPY --from=build /out ${LAMBDA_TASK_ROOT}
COPY pq-tls/openssl-pq.cnf /var/task/pq-tls/openssl-pq.cnf
ENV OPENSSL_CONF=/var/task/pq-tls/openssl-pq.cnf
CMD ["Function::Function.Handler::FunctionHandler"]
```

**`template.yaml`** (SAM: zip, managed runtime and Native AOT)

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Transform: AWS::Serverless-2016-10-31
Globals:
  Function:
    Timeout: 30
    MemorySize: 512
    Architectures: [arm64]
    Environment:
      Variables:
        OPENSSL_CONF: /var/task/pq-tls/openssl-pq.cnf
Resources:
  ManagedFn:
    Type: AWS::Serverless::Function
    Properties:
      Runtime: dotnet10
      Handler: Function::Function.Handler::FunctionHandler
      CodeUri: ./src/Function/
  AotFn:
    Type: AWS::Serverless::Function
    Properties:
      Runtime: provided.al2023
      Handler: bootstrap
      CodeUri: ./src/FunctionAot/
    Metadata:
      BuildMethod: dotnet7
```

**`lambda.cfn.yaml`** (plain CloudFormation)

```yaml
Resources:
  DotnetFn:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: orders-api
      Runtime: dotnet10
      Handler: Function::Function.Handler::FunctionHandler
      Architectures: [arm64]
      Role: !GetAtt FnRole.Arn
      Code:
        S3Bucket: !Ref ArtifactBucket
        S3Key: orders-api.zip
      Environment:
        Variables:
          OPENSSL_CONF: /var/task/pq-tls/openssl-pq.cnf
```

**`lambda.tf`** (Terraform)

```hcl
resource "aws_lambda_function" "dotnet" {
  function_name = "orders-api"
  runtime       = "dotnet10"            # or "provided.al2023" with handler "bootstrap" for Native AOT
  handler       = "Function::Function.Handler::FunctionHandler"
  architectures = ["arm64"]
  role          = aws_iam_role.fn.arn
  filename      = "build/orders-api.zip" # zip contains pq-tls/openssl-pq.cnf at its root
  source_code_hash = filebase64sha256("build/orders-api.zip")

  environment {
    variables = {
      OPENSSL_CONF = "/var/task/pq-tls/openssl-pq.cnf"
    }
  }
}
```

**`taskdef.json`** (ECS/Fargate; the env var is only needed for the AL2023 image, harmless to omit for Alpine or resolute)

```json
{
  "family": "orders-api",
  "requiresCompatibilities": ["FARGATE"],
  "networkMode": "awsvpc",
  "cpu": "512",
  "memory": "1024",
  "runtimePlatform": { "cpuArchitecture": "ARM64", "operatingSystemFamily": "LINUX" },
  "executionRoleArn": "arn:aws:iam::111122223333:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "api",
      "image": "111122223333.dkr.ecr.eu-west-1.amazonaws.com/orders-api@sha256:REPLACE",
      "essential": true,
      "portMappings": [{ "containerPort": 8443, "protocol": "tcp" }],
      "environment": [
        { "name": "OPENSSL_CONF", "value": "/etc/pq-tls/openssl-pq.cnf" },
        { "name": "ASPNETCORE_ENVIRONMENT", "value": "Production" }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/orders-api",
          "awslogs-region": "eu-west-1",
          "awslogs-stream-prefix": "api"
        }
      }
    }
  ]
}
```

**`ecs.tf`** (Terraform for the same task definition)

```hcl
resource "aws_ecs_task_definition" "api" {
  family                   = "orders-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.exec.arn
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
  container_definitions = jsonencode([{
    name         = "api"
    image        = "${aws_ecr_repository.api.repository_url}@${var.image_digest}"
    essential    = true
    portMappings = [{ containerPort = 8443, protocol = "tcp" }]
    environment  = [{ name = "OPENSSL_CONF", value = "/etc/pq-tls/openssl-pq.cnf" }]
  }])
}
```

**`ecs.cfn.yaml`** (CloudFormation for the same task definition)

```yaml
Resources:
  ApiTaskDef:
    Type: AWS::ECS::TaskDefinition
    Properties:
      Family: orders-api
      RequiresCompatibilities: [FARGATE]
      NetworkMode: awsvpc
      Cpu: "512"
      Memory: "1024"
      ExecutionRoleArn: !GetAtt ExecRole.Arn
      RuntimePlatform:
        CpuArchitecture: ARM64
        OperatingSystemFamily: LINUX
      ContainerDefinitions:
        - Name: api
          Image: !Sub "${AWS::AccountId}.dkr.ecr.${AWS::Region}.amazonaws.com/orders-api@${ImageDigest}"
          Essential: true
          PortMappings:
            - ContainerPort: 8443
          Environment:
            - Name: OPENSSL_CONF
              Value: /etc/pq-tls/openssl-pq.cnf
```

**`deployment.yaml`** (EKS)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders-api
spec:
  replicas: 2
  selector:
    matchLabels: { app: orders-api }
  template:
    metadata:
      labels: { app: orders-api }
    spec:
      containers:
        - name: api
          image: 111122223333.dkr.ecr.eu-west-1.amazonaws.com/orders-api@sha256:REPLACE
          ports:
            - containerPort: 8443
          env:
            - name: OPENSSL_CONF          # AL2023 image only
              value: /etc/pq-tls/openssl-pq.cnf
          volumeMounts:
            - name: tls
              mountPath: /certs
              readOnly: true
      volumes:
        - name: tls
          secret:
            secretName: orders-api-tls   # holds server.pfx
```

**`/etc/systemd/system/orders-api.service`** (EC2 Amazon Linux 2023, per-service fix; tested equivalent: `OPENSSL_CONF` in the AL2023 container)

```ini
[Unit]
Description=orders-api (.NET)
After=network-online.target
Wants=network-online.target

[Service]
User=orders
WorkingDirectory=/opt/orders-api
ExecStart=/usr/bin/dotnet /opt/orders-api/App.dll
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=OPENSSL_CONF=/etc/pq-tls/openssl-pq.cnf
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

**`ssm-al2023-pq-policy.yaml`** (SSM Command document, whole-host fix on EC2 AL2023.12+; Documented by [AL2023](https://docs.aws.amazon.com/linux/al2023/ug/crypto-policies-pq.html), not run here)

```yaml
schemaVersion: "2.2"
description: Set the AL2023 crypto policy to DEFAULT:PQ and restart .NET services
parameters:
  Services:
    type: String
    default: orders-api
mainSteps:
  - action: aws:runShellScript
    name: setPqPolicy
    precondition:
      StringEquals: [platformType, Linux]
    inputs:
      runCommand:
        - set -euo pipefail
        - dnf install -y crypto-policies-scripts
        - update-crypto-policies --set DEFAULT:PQ
        - update-crypto-policies --show
        - for s in {{ Services }}; do systemctl restart "$s"; done
```

**`Enable-PqTls.ps1`** (Windows Server 2025 / Windows 11 24H2+, Schannel; Documented by Microsoft, not run here)

```powershell
#Requires -RunAsAdministrator
# Puts the hybrid ML-KEM group first in the Schannel supported-groups order.
# Needs Windows Server 2025 with KB5099536 (2026-07-14) or later, or Windows 11 24H2/25H2 with KB5089573 or later.
$ErrorActionPreference = 'Stop'
$build = [Environment]::OSVersion.Version
Write-Output "OS build: $build"
if ($build.Build -lt 26100) { throw 'Schannel ML-KEM groups need Windows Server 2025 / Windows 11 24H2 or later.' }

Write-Output 'Before:'; Get-TlsEccCurve
Enable-TlsEccCurve -Name 'X25519_MLKEM768' -Position 0
Write-Output 'After:'; Get-TlsEccCurve

# A Group Policy "ECC Curve Order" setting overrides this; if one is set, edit the GPO instead.
# New curve order takes effect after a restart of the services that use Schannel (IIS, Kestrel, HTTP.sys apps);
# Microsoft's docs say the policy route takes effect on the next reboot.
Restart-Computer -Force
```

**`ssm-windows-pq.json`** (SSM Command document wrapping the script)

```json
{
  "schemaVersion": "2.2",
  "description": "Enable X25519_MLKEM768 in Schannel and reboot",
  "mainSteps": [
    {
      "action": "aws:runPowerShellScript",
      "name": "enablePqGroup",
      "precondition": { "StringEquals": ["platformType", "Windows"] },
      "inputs": {
        "runCommand": [
          "Enable-TlsEccCurve -Name 'X25519_MLKEM768' -Position 0",
          "Get-TlsEccCurve",
          "exit 3010"
        ]
      }
    }
  ]
}
```

`exit 3010` asks SSM to reboot the instance and resume.

**`kafka.appsettings.json`** (Confluent.Kafka client; `ssl.curves.list` is optional, librdkafka 2.14.2+ is already PQ by default)

```json
{
  "Kafka": {
    "BootstrapServers": "b-1.msk.example:9094",
    "SecurityProtocol": "Ssl",
    "SslCurvesList": "X25519MLKEM768:X25519:P-256"
  }
}
```

```csharp
var cfg = new ProducerConfig
{
    BootstrapServers = conf["Kafka:BootstrapServers"],
    SecurityProtocol = SecurityProtocol.Ssl,
};
// Pin PQ first explicitly (librdkafka passes this to SSL_CTX_set1_curves_list).
cfg.Set("ssl.curves.list", conf["Kafka:SslCurvesList"]);
```
