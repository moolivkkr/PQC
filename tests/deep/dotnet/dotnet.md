# .NET runbook (tab body as written to the doc, rev 14; section 'What decides PQ here' lives in the doc only)

## Status matrix

Tested 2026-11-14 on arm64: a .NET client (SslStream and HttpClient) against a PQ-only server and a classical-only server, and a Kestrel server probed with OpenSSL 3.5 `s_client`. Every row that says "No" still connected to the classical-only server, so the fix only adds PQ. Scripts and output: `deep/dotnet/run-tests.sh`, `results.txt`, `results2.txt`.

**By compute type**

| Compute | OS TLS library | PQ by default | Fix | Evidence |
| --- | --- | --- | --- | --- |
| Lambda zip, `dotnet8` / `dotnet10` | AL2023, OpenSSL 3.5, crypto policy without ML-KEM | No | Ship `pq-tls/openssl-pq.cnf`, set `OPENSSL_CONF=/var/task/pq-tls/openssl-pq.cnf` | Tested (Lambda images, 2026-11-12) |
| Lambda image `public.ecr.aws/lambda/dotnet:8` / `:10` | Same | No | Same file and `ENV` in the Dockerfile | Tested |
| Lambda Native AOT on `provided.al2023` | Same; the AOT binary still loads the system `libssl.so.3` | No | Same file and env var | Tested (AOT build of .NET 8.0.33 run in `provided:al2023`) |
| Fargate, ECS, EKS (Linux) | Whatever the image ships | Depends on image (next table) | Use an `-alpine` or `-resolute` tag, or AL2023 + config file | Tested |
| EC2 Amazon Linux 2023.12+ | OpenSSL 3.5.8 | No | `update-crypto-policies --set DEFAULT:PQ`, or `OPENSSL_CONF` in the systemd unit | Tested in an AL2023 container; policy route [Documented](https://docs.aws.amazon.com/linux/al2023/ug/crypto-policies-pq.html) |
| EC2 Amazon Linux 2, Ubuntu 22.04/24.04 | OpenSSL 1.0.2 to 3.0 | No | Migrate the OS or containerise on a PQ image | Documented (OpenSSL 3.5 is the first with ML-KEM) |
| EC2 Windows Server 2025, Windows containers `ltsc2025` | Schannel | No (groups disabled by default) | July 2026 update or later, then enable `X25519_MLKEM768` | [Documented](https://learn.microsoft.com/en-us/windows/win32/secauthn/tls-supported-groups-in-windows-11-24h2-and-later); not tested here |
| EC2 Windows Server 2022 and older | Schannel | No | No Microsoft statement of support found; plan to move to 2025 | Not confirmed |

**Container images (`mcr.microsoft.com/dotnet/aspnet`, same OS as `runtime` and `runtime-deps`)**

| Tag | OS, OpenSSL | Client PQ | Kestrel PQ | Action |
| --- | --- | --- | --- | --- |
| `8.0` (default) | Debian 12, 3.0.22 | No | No | Change image |
| `10.0` (default), `10.0-noble` | Ubuntu 24.04, 3.0.13 | No | No | Change image |
| `10.0-noble-chiseled` | Ubuntu 24.04, 3.0 | No | No | Change image |
| `10.0-azurelinux3.0` (and `-distroless`) | Azure Linux 3.0, 3.3.7 | No | No | Change image |
| `8.0-alpine`, `10.0-alpine` | Alpine 3.24, 3.5 | Yes | Yes | None |
| `10.0-resolute` | Ubuntu 26.04, 3.5.5 | Yes | Yes | None (glibc) |
| `10.0-resolute-chiseled` | Ubuntu 26.04, 3.5 | Yes | Yes | None (glibc, distroless) |
| `amazonlinux:2023` + `dnf install aspnetcore-runtime-8.0` | AL2023.12, 3.5.8 | No | No | Config file or `DEFAULT:PQ` |
| Same + `OPENSSL_CONF=openssl-pq.cnf` | | Yes | Yes | |
| Same + `update-crypto-policies --set DEFAULT:PQ` | | Yes | Not run | |

All rows Tested (.NET 8.0.33/8.0.34 and 10.0.15). There is no .NET 8 Ubuntu 26.04 tag and no Debian 13 tag for either version as of 2026-11-14 (checked with `docker manifest inspect`); for .NET 8 on glibc use AL2023 or move to .NET 10.

## Client side (app level)

The client offers X25519MLKEM768 when the OS library does. Nothing in .NET code turns PQ on; a few settings turn it off.

| Client | TLS stack | What to set | Evidence |
| --- | --- | --- | --- |
| `HttpClient` / `SocketsHttpHandler` | SslStream → OS | Leave `SslOptions.EnabledSslProtocols` at `None`, or include `Tls13` | Tested |
| `HttpClientHandler.SslProtocols` | SslStream → OS | Same: `None` or include `Tls13` | Tested (via SocketsHttpHandler, which it wraps) |
| `SslStream` directly | OS | `SslClientAuthenticationOptions.EnabledSslProtocols = None` | Tested |
| gRPC `Grpc.Net.Client` | HttpClient | Nothing; HTTP/2 over TLS 1.3 follows the OS | [Documented](https://learn.microsoft.com/en-us/aspnet/core/grpc/client) |
| gRPC `Grpc.Core` (legacy C-core) | Own bundled BoringSSL | Migrate to `Grpc.Net.Client`; Grpc.Core is out of support | [Documented](https://grpc.io/blog/grpc-csharp-future/) that it is deprecated; its ML-KEM support not confirmed |
| AWS SDK for .NET (v3, v4) | HttpClient | Nothing in code; OS must have OpenSSL 3.5+ with ML-KEM enabled | [Documented](https://docs.aws.amazon.com/sdkref/latest/guide/pqtls-details.html) |
| Npgsql 9 | SslStream ([source](https://github.com/npgsql/npgsql/blob/main/src/Npgsql/Internal/NpgsqlConnector.cs)) | Nothing; `SSL Mode=Require` or stricter | Tested against PostgreSQL 18.7 with `ssl_groups = 'X25519MLKEM768'`: alpine, resolute, AL2023+conf connect; noble fails |
| MySqlConnector | SslStream ([source](https://github.com/mysql-net/MySqlConnector/blob/master/src/MySqlConnector/Core/ServerSession.cs)) | Don't pin `TlsVersion=TLS 1.2` in the connection string | Documented (source code) |
| StackExchange.Redis | SslStream ([source](https://github.com/StackExchange/StackExchange.Redis/blob/main/src/StackExchange.Redis/PhysicalConnection.cs)) | Don't set `SslProtocols=Tls12` | Documented (source code) |
| Confluent.Kafka 2.16 | librdkafka with its own statically linked OpenSSL 3.5.8 | Nothing; optional `ssl.curves.list` | Tested: PQ on Debian 12 and Ubuntu 24.04 images, where the OS OpenSSL is 3.0 |

**Code excerpts** (full files at the end of this tab):

```csharp
// HttpClient: the only TLS knob that matters for PQ is the protocol version.
var handler = new SocketsHttpHandler();
handler.SslOptions.EnabledSslProtocols = SslProtocols.None; // OS default: TLS 1.2 + 1.3
// BAD: handler.SslOptions.EnabledSslProtocols = SslProtocols.Tls12;  -> never PQ
var http = new HttpClient(handler);

// gRPC: same handler
var channel = GrpcChannel.ForAddress("https://orders.internal:8443",
    new GrpcChannelOptions { HttpHandler = handler });
```

```csharp
// Confluent.Kafka: PQ by default with librdkafka >= 2.14.2 (bundled OpenSSL 3.5.x).
// Pin the order explicitly if you want the setting visible in config reviews.
var cfg = new ProducerConfig { BootstrapServers = brokers, SecurityProtocol = SecurityProtocol.Ssl };
cfg.Set("ssl.curves.list", "X25519MLKEM768:X25519:P-256");
```

Confluent.Kafka on Alpine failed to load its native library in the test (`DllNotFoundException`); this is a packaging issue, not TLS, and wasn't investigated. librdkafka's bundled OpenSSL does not read the OS crypto policy, so `OPENSSL_CONF` and `DEFAULT:PQ` don't change it; use `ssl.curves.list`. librdkafka bundled OpenSSL 3.0.x up to 2.14.1 ([changelog](https://github.com/confluentinc/librdkafka/blob/master/CHANGELOG.md)): upgrade below that.

**macOS developer machines:** .NET uses Apple's TLS. AWS says PQ needs .NET 10 with the Network.framework opt-in ([AWS](https://docs.aws.amazon.com/sdkref/latest/guide/pqtls-details.html), [Microsoft](https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-10/libraries#tls-13-for-macos-client)). Not tested here.

## Server side

| Server | TLS stack | PQ setting | Evidence |
| --- | --- | --- | --- |
| Kestrel on Linux | SslStream → OpenSSL | None in Kestrel. Use a PQ image or `OPENSSL_CONF`; keep `SslProtocols` at `None` or include `Tls13` | Tested (table above) |
| Kestrel on Windows | Schannel | Enable `X25519_MLKEM768` in Schannel | Documented; not tested |
| IIS | Schannel (HTTP.sys) | Same Schannel setting; it is machine-wide | Documented (Schannel applies to all its callers); not tested |
| HTTP.sys (`UseHttpSys`) | Schannel, kernel mode | Same | Documented; not tested |
| ASP.NET Core gRPC server | Kestrel or HTTP.sys | Follows the server above; gRPC needs HTTP/2, which needs TLS 1.2+ | Inferred from the Kestrel test; a gRPC call itself was not run |
| Behind an ALB/NLB/API Gateway | The AWS front door | The listener policy decides the client-facing leg; see the Load balancers tab | — |

**Kestrel excerpt** (`appsettings.json`; full `Program.cs` and file at the end):

```json
"Kestrel": {
  "Endpoints": {
    "Https": {
      "Url": "https://0.0.0.0:8443",
      "SslProtocols": [ "Tls12", "Tls13" ],
      "Certificate": { "Path": "/certs/server.pfx", "Password": "..." }
    }
  }
}
```

The same endpoint set to `Tls12` only rejected the PQ client with a `protocol_version` alert (Tested). Code that sets `SslServerAuthenticationOptions.EnabledSslProtocols` in `ConfigureHttpsDefaults` or `UseHttps(o => ...)` has the same effect.

**Windows (IIS, HTTP.sys, Kestrel, HttpClient):**

```powershell
# Windows Server 2025 with KB5099536 (2026-07-14) or later; Windows 11 24H2/25H2 with KB5089573 or later
Enable-TlsEccCurve -Name 'X25519_MLKEM768' -Position 0
Get-TlsEccCurve
```

Group Policy route: Computer Configuration > Administrative Templates > Network > SSL Configuration Settings > **ECC Curve Order**, with `X25519_MLKEM768` first; a GPO overrides the cmdlet, and Microsoft says a new order takes effect on the next reboot ([Microsoft](https://learn.microsoft.com/en-us/windows-server/security/tls/manage-tls), [FAQ](https://techcommunity.microsoft.com/t5/post-quantum-crypto-tech-blog/windows-tls-1-3-and-post-quantum-crypto-faq/ba-p/4556389)). The ML-KEM groups are TLS 1.3 only and are not available in legacy FIPS mode. AWS lists PQ on Windows from .NET 10; whether .NET 8 on a patched Windows picks up the group is not confirmed.

## Packaging per compute type

1. **Lambda zip (dotnet8, dotnet10).** Put `pq-tls/openssl-pq.cnf` in the project with `CopyToPublishDirectory` so it lands at `/var/task/pq-tls/openssl-pq.cnf`. Set `OPENSSL_CONF` to that path in SAM, CloudFormation or Terraform. If the function already sets `OPENSSL_CONF`, don't overwrite it; merge and review.
2. **Lambda container image.** `COPY` the file and `ENV OPENSSL_CONF=...` on top of `public.ecr.aws/lambda/dotnet:10`.
3. **Lambda Native AOT (`provided.al2023`).** Same file and env var. AOT doesn't bundle OpenSSL; it loads the runtime's `libssl.so.3` (Tested). Build on AL2023 so glibc matches.
4. **Fargate, ECS, EKS.** Preferred: switch `FROM` to `aspnet:10.0-alpine`, `10.0-resolute` or `10.0-resolute-chiseled`; no env var needed. On .NET 8 and glibc: AL2023 base + config file + `ENV OPENSSL_CONF`. Pin the image by digest.
5. **EC2 Linux (AL2023).** Whole host: SSM document running `update-crypto-policies --set DEFAULT:PQ`, then restart services. One service: `Environment=OPENSSL_CONF=...` in its systemd unit.
6. **EC2 Windows.** Patch, then run `Enable-PqTls.ps1` through SSM Run Command or set the GPO; reboot.

Full Dockerfiles, csproj, SAM, CloudFormation, Terraform, task definition, pod spec, systemd unit, SSM documents and PowerShell are in **Full configuration files** below.

## Verify

- **Posture (Linux image or host):** `cat /etc/os-release`; `openssl version` where present (chiseled images have no shell: inspect the base tag). OpenSSL below 3.5 = not PQ. On AL2023 also check `echo $OPENSSL_CONF` or `update-crypto-policies --show` (expect `DEFAULT:PQ`).
- **Posture (code):** search for `SslProtocols.Tls12`, `EnabledSslProtocols`, `"SslProtocols"` in `appsettings*.json`, `TlsVersion=` in MySQL strings, and `Grpc.Core` package references.
- **Posture (Windows):** `Get-TlsEccCurve` lists `X25519_MLKEM768` first; `Get-HotFix` shows the July 2026 update or later.
- **Live client test:** run the app's HTTP call against a server started with `openssl s_server -groups X25519MLKEM768 -tls1_3 -www`; it must succeed. Against `-groups X25519` it must also succeed (fallback). The probe used here: `deep/dotnet/client/Program.cs`.
- **Live server test:** `openssl s_client -connect host:8443 -groups X25519MLKEM768 -tls1_3 -brief` prints `Negotiated TLS1.3 group: X25519MLKEM768`; with `-groups X25519` it must still connect. Or `curl --curves X25519MLKEM768 https://host:8443/` with curl on OpenSSL 3.5.
- **Observed signal:** .NET doesn't expose the negotiated group (`ITlsHandshakeFeature` shows protocol and cipher only), so app logs can't prove PQ. Use CloudTrail `tlsDetails.keyExchange` for calls to KMS, STS, IAM, Secrets Manager and ACM (expect `X25519MLKEM768`), the PostgreSQL server side, or the load balancer / front-door logs (see their tabs).

## Pitfalls and rollback

- **Default image tags are not PQ.** `8.0` (Debian 12) and `10.0` (Ubuntu 24.04) both ship OpenSSL 3.0. Azure Linux 3.0 ships 3.3. No env var fixes OpenSSL 3.0; change the image.
- **The AL2023 config file is AL2023-only.** It includes `/etc/crypto-policies/...`; on Debian or Alpine that path doesn't exist. Don't copy it into other images.
- **Overriding `OPENSSL_CONF` replaces the system file.** The kit file re-includes the AL2023 policy so other settings stay; a hand-written file that doesn't can drop FIPS or provider settings.
- **TLS 1.2 pins.** `SslProtocols.Tls12` anywhere (handler, Kestrel, MySQL `TlsVersion`, Redis `SslProtocols`) disables PQ silently.
- **Alpine is musl.** Test native dependencies (Confluent.Kafka failed to load its native library here), ICU/globalization and DNS behaviour before switching.
- **Classical servers keep working.** Every PQ client still connected to the X25519-only server, so the change is low risk for outbound calls.
- **Windows:** the group order is machine-wide and needs a reboot under GPO; a GPO "ECC Curve Order" overrides local cmdlet changes.
- **Rollback:** remove the `OPENSSL_CONF` env var (Lambda/ECS/systemd) or set the policy back with `update-crypto-policies --set DEFAULT`; revert the `FROM` line; on Windows `Disable-TlsEccCurve -Name 'X25519_MLKEM768'` (or remove it from the GPO) and reboot.

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
