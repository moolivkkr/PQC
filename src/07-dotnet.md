# .NET

## Problem statement

A .NET service on Linux negotiates TLS with whatever OpenSSL the container or host ships. On the default `mcr.microsoft.com/dotnet` tags (Debian 12 for `8.0`, Ubuntu 24.04 for `10.0`) that is OpenSSL 3.0, which has no ML-KEM. On Lambda and Amazon Linux 2023 it is OpenSSL 3.5, but the AL2023 crypto policy leaves ML-KEM out of the group list. Either way the handshake uses classical X25519 or P-256 key exchange. Traffic recorded today can be decrypted later by a quantum computer (harvest now, decrypt later).

Who controls the handshake: the OS TLS library, not .NET. `SslStream` (and everything built on it: `HttpClient`, Kestrel, Npgsql, MySqlConnector, StackExchange.Redis, gRPC) calls OpenSSL on Linux, Schannel on Windows and Apple's TLS on macOS. .NET has no API to set key-exchange groups. It can only block PQ, by pinning TLS 1.2.

The good news for teams with existing certificates, keystores and CA bundles: none of them need to change. Tested on 5 images below: PFX, PEM, encrypted PEM, RSA, EC, SNI, X509Store, private CAs, custom trust code and client certificates all keep working when PQ is turned on.

**What decides PQ here**

.NET has no TLS library of its own. `SslStream` does every handshake (HttpClient, gRPC, Kestrel, Npgsql, MySqlConnector, StackExchange.Redis, the AWS SDK). On Linux it calls the OS OpenSSL (`libssl.so.3`); on Windows it calls Schannel. So the OS image or host decides, not the .NET version. The one exception is Confluent.Kafka: librdkafka ships its own OpenSSL.

- **No .NET API picks the key-exchange group.** `SslClientAuthenticationOptions`, `SslServerAuthenticationOptions` and `CipherSuitesPolicy` have no groups setting, and the native shim never calls `SSL_CTX_set1_groups` (Documented: [pal_ssl.c, release/10.0](https://github.com/dotnet/runtime/blob/release/10.0/src/native/libs/System.Security.Cryptography.Native/pal_ssl.c)). Groups come from the OpenSSL config or the Schannel curve order.

- **`OPENSSL_CONF` is honoured.** .NET initialises OpenSSL with `OPENSSL_INIT_LOAD_CONFIG` (Documented: [openssl.c](https://github.com/dotnet/runtime/blob/release/8.0/src/native/libs/System.Security.Cryptography.Native/openssl.c); Tested on Lambda and AL2023).

- **Which libssl loads.** .NET tries `libssl.so.3`, then `1.1`. An override env var forces a version: `CLR_OPENSSL_VERSION_OVERRIDE` in .NET 8 and 9, `DOTNET_OPENSSL_VERSION_OVERRIDE` in .NET 10 and later (Documented: [opensslshim.c](https://github.com/dotnet/runtime/blob/release/10.0/src/native/libs/System.Security.Cryptography.Native/opensslshim.c)). It cannot help when the image only has OpenSSL 3.0; the fix there is a different image.

- **Rule of thumb:** OpenSSL 3.5+ with a default group list that includes X25519MLKEM768 = PQ. OpenSSL 3.0 to 3.4 = never PQ. Amazon Linux 2023 has 3.5 but its crypto policy leaves ML-KEM out until you change it.

## Versions and native support

| Version | TLS stack | PQ client by default | PQ server (Kestrel) by default | API to set groups | FIPS-mode behaviour | Proposed solution | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| .NET 10 LTS (supported to Nov 2028) | SslStream → OpenSSL (Linux), Schannel (Windows) | Lambda `dotnet10`: no. Image `10.0`/`10.0-noble`: no. `10.0-alpine`, `10.0-resolute`: yes. AL2023/EC2: no | Same as client | None. OS config only (`OPENSSL_CONF`, crypto policy, Schannel curve order) | Follows OpenSSL. AL2023 `FIPS:PQ` policy keeps ML-KEM; Windows legacy FIPS mode has no ML-KEM groups | Use `-alpine` or `-resolute` images. On Lambda/AL2023 ship `openssl-pq.cnf` + `OPENSSL_CONF` | Tested (10.0.15); FIPS rows Documented ([AL2023](https://docs.aws.amazon.com/linux/al2023/ug/crypto-policies-pq.html)) |
| .NET 9 STS (out of support since 2026-11-10) | Same | Same pattern as .NET 10 | Same | None | Same | Upgrade to .NET 10 | Unverified (same code path; not run). End of support [Documented](https://devblogs.microsoft.com/dotnet/dotnet-8-9-end-of-support/) |
| .NET 8 LTS (out of support since 2026-11-10) | Same | Lambda `dotnet8`: no. Image `8.0` (Debian 12): no. `8.0-alpine`: yes. AL2023: no | Same as client | None | Same | Upgrade to .NET 10. Until then: `8.0-alpine`, or AL2023 + `OPENSSL_CONF` | Tested (8.0.33, 8.0.34) |
| .NET 6 / 7 (out of support) | Same | Same as the OS OpenSSL | Same | None | Same | Upgrade | Unverified (not run) |
| .NET Framework 4.8 / 4.8.1 (Windows only) | Schannel | Only on Windows Server 2025 / Windows 11 24H2+ with the July 2026 update and `X25519_MLKEM768` enabled | Same (IIS, HTTP.sys) | None in .NET; Schannel curve order (machine-wide) | Legacy FIPS mode: no ML-KEM groups | Patch Windows and enable the group; don't set `ServicePointManager.SecurityProtocol` to `Tls12` | Schannel Documented ([Microsoft](https://learn.microsoft.com/en-us/windows/win32/secauthn/tls-supported-groups-in-windows-11-24h2-and-later)); .NET Framework picking it up not confirmed |
| Native AOT (`provided.al2023`) | Loads the system `libssl.so.3` | No | n/a | None | Same as AL2023 | `openssl-pq.cnf` + `OPENSSL_CONF` | Tested |


Tested 2026-11-14 on arm64: a .NET client (SslStream and HttpClient) against a PQ-only server and a classical-only server, and a Kestrel server probed with OpenSSL 3.5 `s_client`. Every row that says "No" still connected to the classical-only server, so the fix only adds PQ. Scripts and output: `deep/dotnet/run-tests.sh`, `results.txt`, `results2.txt`.

**By compute type**

| Compute | OS TLS library | PQ by default | Fix | Evidence |
|----|----|----|----|----|
| Lambda zip, `dotnet8` / `dotnet10` | AL2023, OpenSSL 3.5, crypto policy without ML-KEM | No | Ship `pq-tls/openssl-pq.cnf`, set `OPENSSL_CONF=/var/task/pq-tls/openssl-pq.cnf`. Fleet option: the kit's `pq-tls` layer with `AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper` (its dotnet branch sets `OPENSSL_CONF=/opt/pq-tls/openssl-pq.cnf` unless the function sets one) | Tested (Lambda images, 2026-11-12; e2e `dotnet-lambda-dotnet8/10-bundled-conf`, `-layer-wrapper`, `-layer-conf`) |
| Lambda image `public.ecr.aws/lambda/dotnet:8` / `:10` | Same | No | Same file and `ENV` in the Dockerfile | Tested |
| Lambda Native AOT on `provided.al2023` | Same; the AOT binary still loads the system `libssl.so.3` | No | Same file and env var | Tested (AOT build of .NET 8.0.33 run in `provided:al2023`) |
| Fargate, ECS, EKS (Linux) | Whatever the image ships | Depends on image (next table) | Use an `-alpine` or `-resolute` tag, or AL2023 + config file | Tested |
| EC2 Amazon Linux 2023.12+ | OpenSSL 3.5.8 | No | `update-crypto-policies --set DEFAULT:PQ`, or `OPENSSL_CONF` in the systemd unit | Tested in an AL2023 container; policy route [Documented](https://docs.aws.amazon.com/linux/al2023/ug/crypto-policies-pq.html) |
| EC2 Amazon Linux 2, Ubuntu 22.04/24.04 | OpenSSL 1.0.2 to 3.0 | No | Migrate the OS or containerise on a PQ image | Documented (OpenSSL 3.5 is the first with ML-KEM) |
| EC2 Windows Server 2025, Windows containers `ltsc2025` | Schannel | No (groups disabled by default) | July 2026 update or later, then enable `X25519_MLKEM768` | [Documented](https://learn.microsoft.com/en-us/windows/win32/secauthn/tls-supported-groups-in-windows-11-24h2-and-later); not tested here |
| EC2 Windows Server 2022 and older | Schannel | No | No Microsoft statement of support found; plan to move to 2025 | Not confirmed |

**Container images (`mcr.microsoft.com/dotnet/aspnet`; `runtime` and `runtime-deps` use the same OS)**

| Tag | OS, OpenSSL | Client PQ | Kestrel PQ | Action |
|----|----|----|----|----|
| `8.0` (default) | Debian 12, 3.0.22 | No | No | Change image |
| `10.0` (default), `10.0-noble` | Ubuntu 24.04, 3.0.13 | No | No | Change image |
| `10.0-noble-chiseled` | Ubuntu 24.04, 3.0 | No | No | Change image |
| `10.0-azurelinux3.0` (and `-distroless`) | Azure Linux 3.0, 3.3.7 | No | No | Change image |
| `8.0-alpine`, `10.0-alpine` | Alpine 3.24, 3.5 | Yes | Yes | None |
| `10.0-resolute` | Ubuntu 26.04, 3.5.5 | Yes | Yes | None (glibc) |
| `10.0-resolute-chiseled` | Ubuntu 26.04, 3.5 | Yes | Yes | None (glibc, distroless) |
| `amazonlinux:2023` + `dnf install aspnetcore-runtime-8.0` | AL2023.12, 3.5.8 | No | No | Config file or `DEFAULT:PQ` |
| Same + `OPENSSL_CONF=openssl-pq.cnf` | AL2023.12, 3.5.8 | Yes | Yes |  |
| Same + `update-crypto-policies --set DEFAULT:PQ` | AL2023.12, 3.5.8 | Yes | Yes (e2e target leg, `srv-dotnet-fargate-al2023-net8-policy`) |  |

All rows Tested (.NET 8.0.33/8.0.34 and 10.0.15). The `-distroless` Azure Linux variant wasn't run; it shares the 3.0 base. As of 2026-11-14 there is no .NET 8 Ubuntu 26.04 tag and no Debian 13 tag for either version (checked with `docker manifest inspect`); for .NET 8 on glibc use AL2023 or move to .NET 10.

**Decision guide**

- On a default `8.0` or `10.0` image: change `FROM` to `10.0-alpine` or `10.0-resolute` (or `-resolute-chiseled`). No code change.
- On Lambda `dotnet8`/`dotnet10`, Native AOT, an AL2023 image or EC2 AL2023: ship `openssl-pq.cnf` and set `OPENSSL_CONF`, or on EC2 run `update-crypto-policies --set DEFAULT:PQ` (`FIPS:PQ` on FIPS hosts).
- If your code or `appsettings` sets `SslProtocols` to `Tls12` only, add `Tls13` or remove the setting. That is the only code change PQ ever needs.
- On .NET 8 or 9: plan the move to .NET 10 now (both left support on 2026-11-10). The PQ fix works on .NET 8 meanwhile.
- On Windows: patch to the July 2026 update or later, enable `X25519_MLKEM768`, reboot. Not tested here.
- Certificates, keystores, CA bundles and client certificates: leave them alone (cases C, D, E).

## Cases: what to change

All tests below ran on 2026-11-14 on arm64 with these images (pulled, run by digest): `aspnet:8.0` (Debian 12, OpenSSL 3.0, .NET 8.0.34), `aspnet:8.0-alpine` (Alpine 3.24, 8.0.34), `aspnet:10.0-alpine` (10.0.15), `aspnet:10.0-resolute` (Ubuntu 26.04, OpenSSL 3.5.5, 10.0.15), and `amazonlinux:2023` + `aspnetcore-runtime-8.0` (OpenSSL 3.5.8, 8.0.33) with `OPENSSL_CONF=openssl-pq.cnf`. There is no .NET 10 Debian 12 tag. The PQ-only server is `openssl s_server -groups X25519MLKEM768 -tls1_3` and the classical server `-groups X25519`, from OpenSSL 3.5.7 (debian:trixie-slim). Kestrel was probed with `openssl s_client`, which prints the negotiated group. Scripts and output: `deep/dotnet/v2/run-cases.sh`, `results-v2.txt`.

Result in one line: on the four PQ images every certificate, trust and mTLS case negotiated X25519MLKEM768 and still worked with a classical client. On Debian 12 the same cases all worked classically and none was PQ, so the image, not the certificate setup, decides.

### A. Simple client

- **Who this is:** `HttpClient`, `IHttpClientFactory`, AWS SDK for .NET, Npgsql, MySqlConnector, StackExchange.Redis, gRPC `Grpc.Net.Client`, with no TLS code. Check: `grep -rn "SslProtocols\|SslOptions\|ClientCertificates" --include=*.cs .` returns nothing.
- **What happens today:** classical on default images, Lambda and AL2023; PQ on `-alpine`/`-resolute`. Tested (v1, `deep/dotnet/results.txt`).
- **What to change:** the image or `OPENSSL_CONF` only. No code.
- **Side effects:** none seen; every PQ client still reached the classical-only server (fallback, Tested).

The client offers X25519MLKEM768 when the OS library does. Nothing in .NET code turns PQ on; a few settings turn it off.

| Client | TLS stack | What to set | Evidence |
|----|----|----|----|
| `HttpClient` / `SocketsHttpHandler` | SslStream → OS | Leave `SslOptions.EnabledSslProtocols` at `None`, or include `Tls13` | Tested |
| `HttpClientHandler.SslProtocols` | SslStream → OS | Same: `None` or include `Tls13` | Tested via SocketsHttpHandler, which it wraps |
| `SslStream` directly | OS | `SslClientAuthenticationOptions.EnabledSslProtocols = None` | Tested |
| gRPC `Grpc.Net.Client` | HttpClient | Nothing; HTTP/2 over TLS follows the OS | [Documented](https://learn.microsoft.com/en-us/aspnet/core/grpc/client) |
| gRPC `Grpc.Core` (legacy C-core) | Own bundled BoringSSL | Migrate to `Grpc.Net.Client`; Grpc.Core is out of support | [Documented](https://grpc.io/blog/grpc-csharp-future/) deprecation; its ML-KEM support not confirmed |
| AWS SDK for .NET (v3, v4) | HttpClient | Nothing in code; the OS needs OpenSSL 3.5+ with ML-KEM enabled | [Documented](https://docs.aws.amazon.com/sdkref/latest/guide/pqtls-details.html) |
| Npgsql 9 | SslStream ([source](https://github.com/npgsql/npgsql/blob/main/src/Npgsql/Internal/NpgsqlConnector.cs)) | Nothing; `SSL Mode=Require` or stricter | Tested against PostgreSQL 18.7 with `ssl_groups = 'X25519MLKEM768'`: alpine, resolute and AL2023+conf connect; noble fails |
| MySqlConnector | SslStream ([source](https://github.com/mysql-net/MySqlConnector/blob/master/src/MySqlConnector/Core/ServerSession.cs)) | Don't pin `TlsVersion=TLS 1.2` in the connection string | Documented (source code) |
| StackExchange.Redis | SslStream ([source](https://github.com/StackExchange/StackExchange.Redis/blob/main/src/StackExchange.Redis/PhysicalConnection.cs)) | Don't set `SslProtocols=Tls12` | Documented (source code) |
| Confluent.Kafka 2.16 | librdkafka with its own statically linked OpenSSL 3.5.8 | Nothing; optional `ssl.curves.list` | Tested: PQ on the Debian 12 and Ubuntu 24.04 images, whose OS OpenSSL is 3.0 |

``` csharp
// HttpClient: the only TLS setting that matters for PQ is the protocol version.
var handler = new SocketsHttpHandler();
handler.SslOptions.EnabledSslProtocols = SslProtocols.None; // OS default: TLS 1.2 + 1.3
// BAD: handler.SslOptions.EnabledSslProtocols = SslProtocols.Tls12;  -> never PQ
var http = new HttpClient(handler);

// gRPC: same handler
var channel = GrpcChannel.ForAddress("https://orders.internal:8443",
    new GrpcChannelOptions { HttpHandler = handler });
```

### B. Simple server

- **Who this is:** Kestrel (`WebApplication`, `UseKestrel`) with the default HTTPS endpoint, or behind an ALB/NLB that terminates TLS.
- **What happens today:** Kestrel follows the image: PQ on `-alpine`, `-resolute`, AL2023 + `OPENSSL_CONF`; classical on `8.0`, `10.0`, Azure Linux. Tested (v1 and v2). Behind a load balancer the client-facing handshake is the listener policy's (see the Load balancers tab).
- **What to change:** the image or `OPENSSL_CONF`. Keep `SslProtocols` at `None` or include `Tls13`.
- **Side effects:** none; X25519-only clients still connect (Tested).

| Server | TLS stack | PQ setting | Evidence |
|----|----|----|----|
| Kestrel on Linux | SslStream → OpenSSL | None in Kestrel. Use a PQ image or `OPENSSL_CONF`; keep `SslProtocols` at `None` or include `Tls13` | Tested (status matrix) |
| Kestrel on Windows | Schannel | Enable `X25519_MLKEM768` in Schannel | Documented; not tested |
| IIS | Schannel via HTTP.sys | Same Schannel setting; it is machine-wide | Documented (Schannel setting applies to all its callers); not tested |
| HTTP.sys (`UseHttpSys`) | Schannel, kernel mode | Same | Documented; not tested |
| ASP.NET Core gRPC server | Kestrel or HTTP.sys | Follows the server above; gRPC needs HTTP/2 | Inferred from the Kestrel test; a gRPC call itself was not run |
| Behind ALB, NLB or API Gateway | The AWS front door | The listener policy decides the client-facing leg; see the Load balancers tab | — |

**Kestrel excerpt** (`appsettings.json`; full `Program.cs` and file at the end):

``` json
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

The same endpoint set to `Tls12` only rejected the PQ client with a `protocol_version` alert (Tested). Code that sets `SslProtocols` in `ConfigureHttpsDefaults`, `UseHttps(o => ...)` or `SslServerAuthenticationOptions.EnabledSslProtocols` has the same effect.

**Behind an ALB or NLB TLS listener (e2e, 2026-11-15):** with the load balancer modelled as the client on the target leg, an `SslStream` server (Kestrel's TLS layer) stayed classical on `runtime:8.0` and AL2023 .NET 8, and negotiated X25519MLKEM768 on `10.0-alpine`, `aspnet:10.0-resolute`, and AL2023 with `OPENSSL_CONF` or `DEFAULT:PQ` (cases `srv-dotnet-*`, Load balancers tab).

### C. Existing server certificates: PFX, PEM, encrypted keys, SNI, X509Store

- **Who this is:** Kestrel loads your own certificate. Find it with:
  `grep -rnE "Certificates|Certificate\"|KeyPath|ServerCertificate|X509Store|UseHttps\(" --include=*.cs --include=appsettings*.json .`
  and in env vars or Helm values: `Kestrel__Certificates__Default__Path`, `ASPNETCORE_Kestrel__Certificates__Default__Password`.
- **What happens today:** the certificate does not affect key exchange. The key exchange group comes from OpenSSL; the certificate only signs the handshake. Tested: same cert, PQ on PQ images, classical on Debian 12.
- **What changes in the store or files:** nothing. Keep the same PFX, PEM, password, key type, store and SNI map. ML-KEM is a key exchange; your RSA or ECDSA certificate stays valid (ML-DSA certificates are a separate, later step: see the Certificates tab).
- **What to change:** only the image or `OPENSSL_CONF` (case A/B). No config key, no code.
- **Side effects:** none found. Unlike Java with Bouncy Castle, no key-manager setting is needed: .NET has no key-manager layer between the store and OpenSSL.

**Tested proof (Kestrel server, `openssl s_client` as client).** "PQ" = `-groups X25519MLKEM768 -tls1_3` printed `Negotiated TLS1.3 group: X25519MLKEM768` and got the HTTP 200 body. "Classical" = `-groups X25519` got HTTP 200. Chain verified with `-CAfile ca.crt -verify_return_error` in both.

| # | How the certificate is loaded | Key | Signature seen | 8.0-alpine | 10.0-alpine | 10.0-resolute | AL2023 + conf | 8.0 (Debian 12) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| C1 | `Kestrel:Certificates:Default:Path` + `Password` (PFX, AES-256/PBKDF2 from OpenSSL 3.5) | EC P-256 | ecdsa_secp256r1_sha256 | PQ + classical | PQ + classical | PQ + classical | PQ + classical | Classical only |
| C2 | Same, PFX | RSA 2048 | rsa_pss_rsae_sha256 | PQ + classical | PQ + classical | PQ + classical | PQ + classical | Classical only |
| C3 | PEM pair: `Path` (leaf + CA chain) + `KeyPath` | EC | ecdsa_secp256r1_sha256 | PQ + classical | PQ + classical | PQ + classical | PQ + classical | Classical only |
| C4 | PEM pair with encrypted PKCS#8 key: `Path` + `KeyPath` + `Password` | RSA | rsa_pss_rsae_sha256 | PQ + classical | PQ + classical | PQ + classical | PQ + classical | Classical only |
| C5 | `ServerCertificateSelector` in code: `ec.test` → EC PFX, `rsa.test` → RSA PFX | EC and RSA | right cert per SNI | PQ + classical | PQ + classical | PQ + classical | PQ + classical | Classical only |
| C6 | Endpoint `Sni` config section, one entry per host name | EC and RSA | right cert per SNI | PQ + classical | PQ + classical | PQ + classical | PQ + classical | Classical only |
| C7 | `X509Store` CurrentUser/My: PFX imported with `PersistKeySet`, endpoint uses `Subject` + `Store: My` + `Location: CurrentUser` | EC | ecdsa_secp256r1_sha256 | PQ + classical | PQ + classical | PQ + classical | PQ + classical | Classical only |

All 90 probes (9 setups x 2 clients x 5 images) behaved as shown (Tested, `results-v2.txt`). Config used, as env vars (same keys as `appsettings.json`):

```bash
# C1/C2 PFX
Kestrel__Certificates__Default__Path=/certs/server-ec.pfx
Kestrel__Certificates__Default__Password=<from Secrets Manager>
# C3/C4 PEM pair (Password only when the key is encrypted)
Kestrel__Certificates__Default__Path=/certs/server-rsa-chain.crt
Kestrel__Certificates__Default__KeyPath=/certs/server-rsa-enc.key
Kestrel__Certificates__Default__Password=<key password>
# C6 SNI map in config
Kestrel__Endpoints__Https__Sni__ec.test__Certificate__Path=/certs/server-ec.pfx
Kestrel__Endpoints__Https__Sni__rsa.test__Certificate__Path=/certs/server-rsa.pfx
# C7 X509Store
Kestrel__Certificates__Default__Subject=pq-server-ec
Kestrel__Certificates__Default__Store=My
Kestrel__Certificates__Default__Location=CurrentUser
Kestrel__Certificates__Default__AllowInvalid=true   # needed here because the test CA is not in the system store
```

```csharp
// C5: per-host certificate selection in code (unchanged by PQ)
builder.WebHost.ConfigureKestrel(k => k.ConfigureHttpsDefaults(https =>
{
    https.ServerCertificateSelector = (ctx, name) => name == "rsa.test" ? rsaCert : ecCert;
}));
```

Notes for this case:

- **RSA and EC:** both work with PQ. The key type changes only the signature (RSA-PSS or ECDSA), not the key exchange.
- **Several certificates:** Kestrel serves one certificate per endpoint unless you use `ServerCertificateSelector` or the `Sni` section. Both select by SNI, and both worked with PQ. There is no "RSA+EC in one store, pick by client" behaviour as in Java; if you need both, use SNI or two endpoints.
- **X509Store on Linux:** CurrentUser/My lives under `~/.dotnet/corefx/cryptography/x509stores/my/`; it must be persisted (volume or image layer) or re-imported at start. On Lambda the passwd home (`/home/sbx_user…`) is read-only, so importing there fails with `CryptographicException: The X509 certificate could not be added to the store` (`UnauthorizedAccessException`): set `HOME=/tmp` (function environment variable, or an exec wrapper that exports it) before the first `X509Store` use, or load the PFX/PEM directly (E1, E2). Tested: e2e `dotnet-lambda-dotnet8/10-store-clientcert` (PQ with `HOME=/tmp`); without it the import fails before any handshake. LocalMachine/My is not writable on Linux. Root/CA stores on Linux are a read-only view of the OpenSSL trust files ([discussion](https://github.com/dotnet/runtime/issues/32875)). Not a PQ issue.
- **Windows certificate store (Schannel):** works the same way in principle: the curve order is machine-wide and separate from the certificate. Not tested here (Documented only for Schannel groups).
- **HSM, TPM or KMS keys:** see case I.

### D. Custom CA trust: system store, SSL_CERT_FILE / SSL_CERT_DIR, validation callbacks, CustomTrustStore

- **Who this is:** your service calls internal endpoints signed by a private CA (ACM Private CA, an on-prem CA). Find it with:
  `grep -rnE "ServerCertificateCustomValidationCallback|RemoteCertificateValidationCallback|CertificateChainPolicy|CustomTrustStore|X509Chain" --include=*.cs .`
  and in Dockerfiles: `update-ca-certificates`, `update-ca-trust`, `SSL_CERT_FILE`, `SSL_CERT_DIR`.
- **What happens today:** trust is checked after key exchange and is independent of it. Tested: every trust method below worked with PQ on the PQ images, and failed only on Debian 12, where the PQ-only server refused the handshake before any certificate was seen.
- **What changes in the store or bundle:** nothing. Same CA file, same hashed directory, same callback, same `X509ChainPolicy`.
- **What to change:** only the image or `OPENSSL_CONF`. On AL2023 the kit `openssl-pq.cnf` changes only `Groups`; the CA locations (`/etc/pki/tls/certs`, `/etc/pki/ca-trust`) and `update-ca-trust` keep working (Tested, row D5).
- **Side effects:** if you move from Debian/Ubuntu to Alpine, the CA install command is the same (`update-ca-certificates`) but needs the `ca-certificates` package (`apk add ca-certificates`); the aspnet Alpine image may only have the bundle. On AL2023 use `/etc/pki/ca-trust/source/anchors/` + `update-ca-trust`.

**Tested proof (.NET client, `HttpClient`).** PQ = request to the PQ-only server returned 200. Classical = request to the X25519-only server returned 200.

| # | Trust method | 8.0-alpine | 10.0-alpine | 10.0-resolute | AL2023 + conf | 8.0 (Debian 12) |
| --- | --- | --- | --- | --- | --- | --- |
| D0 | No private CA anywhere (control) | Fails `UntrustedRoot` (expected) | Same | Same | Same | Same on classical; PQ fails earlier at handshake |
| D1 | `SSL_CERT_FILE=/certs/ca.crt` | PQ + classical | PQ + classical | PQ + classical | PQ + classical | Classical only |
| D2 | `SSL_CERT_DIR=/certs/hashdir` (`openssl rehash`) | PQ + classical | PQ + classical | PQ + classical | PQ + classical | Classical only |
| D3 | `HttpClientHandler.ServerCertificateCustomValidationCallback` building the chain against the CA | PQ + classical | PQ + classical | PQ + classical | PQ + classical | Classical only |
| D4 | `SocketsHttpHandler.SslOptions.CertificateChainPolicy` with `CustomRootTrust` + `CustomTrustStore` | PQ + classical | PQ + classical | PQ + classical | PQ + classical | Classical only |
| D5 | CA added to the system store (`update-ca-certificates` or `update-ca-trust`) | PQ + classical | PQ + classical | PQ + classical | PQ + classical | Classical only |

60 requests, all as expected (Tested, `results-v2.txt`).

```csharp
// D4: trust only your private CA for this client (.NET 7+). Unchanged by PQ.
var ca = X509Certificate2.CreateFromPem(File.ReadAllText("/certs/ca.crt"));
var handler = new SocketsHttpHandler();
handler.SslOptions.CertificateChainPolicy = new X509ChainPolicy
{
    TrustMode = X509ChainTrustMode.CustomRootTrust,
    CustomTrustStore = { ca },
};
```

```csharp
// D3: validation callback that keeps host-name checks and builds the chain against your CA. Unchanged by PQ.
var handler = new HttpClientHandler
{
    ServerCertificateCustomValidationCallback = (msg, cert, chain, errors) =>
    {
        if (cert is null || (errors & SslPolicyErrors.RemoteCertificateNameMismatch) != 0) return false;
        using var c = new X509Chain { ChainPolicy = { TrustMode = X509ChainTrustMode.CustomRootTrust, CustomTrustStore = { ca } } };
        return c.Build(cert);
    }
};
```

```dockerfile
# D5: private CA in the system store
# Debian/Ubuntu (resolute):
COPY ca.crt /usr/local/share/ca-certificates/corp-ca.crt
RUN update-ca-certificates
# Alpine:
RUN apk add --no-cache ca-certificates
COPY ca.crt /usr/local/share/ca-certificates/corp-ca.crt
RUN update-ca-certificates
# Amazon Linux 2023:
COPY ca.crt /etc/pki/ca-trust/source/anchors/corp-ca.crt
RUN update-ca-trust
```

Notes for this case:

- **Pitfall found while testing:** `X509Certificate2.CreateFromPemFile("ca.crt")` with no key path throws `CryptographicException: The key contents do not contain a PEM...`, because it looks for a private key in the same file. Load a CA with `X509Certificate2.CreateFromPem(File.ReadAllText(path))` or `X509CertificateLoader` (.NET 9+). This is not PQ-related but appears when teams add custom trust code.
- **Callbacks that return `true`:** they hide trust errors; PQ does not change them, but the CI check below warns on them.
- **Certificate pinning:** see case I.

### E. Mutual TLS (client certificates)

- **Who this is:** `HttpClientHandler.ClientCertificates`, `SocketsHttpHandler.SslOptions.ClientCertificates`, `ClientCertificateContext`, or Kestrel `ClientCertificateMode`. Grep: `grep -rnE "ClientCertificate" --include=*.cs --include=appsettings*.json .`
- **What happens today:** the client certificate is sent and checked after key exchange; PQ does not touch it. Tested.
- **What changes in the store or files:** nothing.
- **What to change:** the image or `OPENSSL_CONF` on both sides.
- **Side effects:** none found. A missing or foreign client certificate is still refused with PQ on.

| # | Test | 8.0-alpine | 10.0-alpine | 10.0-resolute | AL2023 + conf | 8.0 (Debian 12) |
| --- | --- | --- | --- | --- | --- | --- |
| E0 | .NET client, no client cert, server requires one | Refused `certificate required` (expected) | Same | Same | Same | Same (classical) |
| E1 | `HttpClientHandler.ClientCertificates` from a PFX | PQ + classical | PQ + classical | PQ + classical | PQ + classical | Classical only |
| E2 | `SocketsHttpHandler.SslOptions.ClientCertificates` from a PEM pair (`CreateFromPemFile(crt, key)`) | PQ + classical | PQ + classical | PQ + classical | PQ + classical | Classical only |
| E3 | Client cert from `X509Store` CurrentUser/My | PQ + classical | PQ + classical | PQ + classical | PQ + classical | Classical only |
| E4 | Kestrel `ClientCertificateMode.RequireCertificate` + `ClientCertificateValidation` with `CustomTrustStore`; `s_client -cert` | PQ + classical, app sees `CN=pq-client` | Same | Same | Same | Classical only |
| E5 | Same server, client sends no cert | Handshake completes (PQ group shown), request refused, no response | Same | Same | Same | Same (classical) |
| E6 | Same server, cert from another CA | Request refused | Same | Same | Same | Same (classical) |

Servers in E0–E3: `openssl s_server -Verify 1 -CAfile ca.crt -verify_return_error`, PQ-only and classical-only. All 70 results as expected (Tested, `results-v2.txt`).

```csharp
// E4: Kestrel requires and verifies client certificates against your CA. Unchanged by PQ.
builder.WebHost.ConfigureKestrel(k => k.ConfigureHttpsDefaults(https =>
{
    https.ClientCertificateMode = ClientCertificateMode.RequireCertificate;
    https.ClientCertificateValidation = (cert, chain, errors) =>
    {
        using var c = new X509Chain();
        c.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
        c.ChainPolicy.CustomTrustStore.Add(clientCa);
        c.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck; // or Online with a reachable CRL/OCSP
        return c.Build(cert);
    };
}));
```

In TLS 1.3 a refused client certificate shows up after the handshake (the server sends an alert and closes). Logs that count "handshake succeeded" will count E5/E6 as handshakes; count HTTP results instead.

### F. Explicit TLS settings that block PQ

- **Who this is:** code or config that sets protocols or ciphers. Find it with the CI check (`check-dotnet-pq.sh`, full file at the end) or:
  `grep -rnE "SslProtocols|EnabledSslProtocols|CipherSuitesPolicy|TlsVersion=|SecurityProtocol" --include=*.cs --include=*.json --include=*.config .`
- **What happens today:**

| # | Setting | Result | Evidence |
| --- | --- | --- | --- |
| F1 | Client `SslOptions.EnabledSslProtocols = SslProtocols.Tls12` | PQ-only server refuses (`protocol version` alert); classical works | Tested, all 5 images |
| F2 | Client `CipherSuitesPolicy` with TLS 1.3 AES-GCM suites only | PQ still works; groups are separate from cipher suites | Tested, 4 PQ images |
| F3 | Kestrel `SslProtocols = Tls12` | PQ clients refused (`protocol version`) | Tested, all 5 images |
| F3b | Same, with an EC certificate, client offering only X25519 | Refused (`handshake failure`). In TLS 1.2 the client's group list also limits the ECDSA cert curve; with `X25519:P-256` it connects, and an RSA cert works with X25519 only | Tested (`run-f3.sh`, `results-f3.txt`, 10.0-alpine) |
| F4 | Kestrel `CipherSuitesPolicy` (via `OnAuthenticate`) TLS 1.3 AES-GCM only | PQ + classical | Tested, 4 PQ images |
| F5 | `CipherSuitesPolicy` on Windows | Throws `NotSupportedException` | [Documented](https://learn.microsoft.com/en-us/dotnet/core/extensions/sslstream-best-practices) |
| F6 | MySqlConnector `TlsVersion=TLS 1.2`, Redis `SslProtocols=Tls12`, `ServicePointManager.SecurityProtocol = Tls12` | Same effect as F1 | Documented (source code); not run |

- **What to change:** remove the protocol setting (`SslProtocols.None` = OS default, Microsoft's [recommendation](https://learn.microsoft.com/en-us/dotnet/core/extensions/sslstream-best-practices)) or use `Tls12 | Tls13`. In `appsettings.json` use `"SslProtocols": [ "Tls12", "Tls13" ]` or drop the key. A `CipherSuitesPolicy` can stay if it lists TLS 1.3 suites.
- **Side effects:** allowing TLS 1.3 may change which cipher suite is used; check any compliance rule that named TLS 1.2 suites.

### G. FIPS mode

- .NET has no FIPS switch of its own on Linux; it uses whatever OpenSSL provider is active. On AL2023 in FIPS mode use `update-crypto-policies --set FIPS:PQ`, which AWS documents as enabling ML-KEM hybrids under the FIPS policy ([AL2023](https://docs.aws.amazon.com/linux/al2023/ug/crypto-policies-pq.html)). Documented; not run here (no FIPS-enabled host).
- Do not use the kit `openssl-pq.cnf` on a FIPS host: it re-includes the current policy file, but whether the FIPS provider stays active with it was not tested. Use `FIPS:PQ` instead.
- Windows legacy FIPS mode (`FipsAlgorithmPolicy`): Microsoft says the ML-KEM groups are not available. Documented ([FAQ](https://techcommunity.microsoft.com/t5/post-quantum-crypto-tech-blog/windows-tls-1-3-and-post-quantum-crypto-faq/ba-p/4556389)).
- Lambda has no FIPS mode switch for the managed runtime; FIPS endpoints (`*-fips`) are a separate AWS topic (AWS service endpoints tab).

### H. Libraries with their own TLS stack

``` csharp
// Confluent.Kafka: PQ by default with librdkafka >= 2.14.2 (bundled OpenSSL 3.5.x).
// Pin the order explicitly if you want it visible in config reviews.
var cfg = new ProducerConfig { BootstrapServers = brokers, SecurityProtocol = SecurityProtocol.Ssl };
cfg.Set("ssl.curves.list", "X25519MLKEM768:X25519:P-256");
```

- **Confluent.Kafka details.** librdkafka bundled OpenSSL 3.0.x up to 2.14.1 and 3.5.x from 2.14.2 ([changelog](https://github.com/confluentinc/librdkafka/blob/master/CHANGELOG.md)); upgrade below that. Its bundled OpenSSL doesn't use the OS library, so the OS crypto policy and image don't apply (whether it reads `OPENSSL_CONF` is not confirmed); control it with `ssl.curves.list`. Setting it to `X25519` made the PQ-only handshake fail (Tested), which proves the setting is honoured. On Alpine the package failed to load its native library (`DllNotFoundException`); that is packaging, not TLS, and wasn't investigated.

- **macOS developer machines.** .NET uses Apple's TLS there. AWS says PQ needs .NET 10 with the Network.framework opt-in ([AWS](https://docs.aws.amazon.com/sdkref/latest/guide/pqtls-details.html), [Microsoft](https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-10/libraries#tls-13-for-macos-client)). Not tested here.

- **Confluent.Kafka (librdkafka):** bundles OpenSSL 3.5.8 from 2.14.2, so it is PQ even on Debian 12 and Ubuntu 24.04 images, and ignores `OPENSSL_CONF`. Tested (v1).
- **Grpc.Core (legacy, BoringSSL):** out of support; migrate to `Grpc.Net.Client`, which uses `HttpClient`.
- **Microsoft.Data.SqlClient, Oracle.ManagedDataAccess:** believed to use `SslStream` on Linux and so follow the OS. Unverified (not tested, source not checked).
- **APM agents (OpenTelemetry exporters, Datadog, New Relic .NET agents):** export over `HttpClient` or gRPC .NET; they follow the OS. Not tested; Unverified.
- **Shelling out to `curl`, `git`, `wget`:** Alpine and resolute curl use OpenSSL 3.5 (PQ). GnuTLS builds (Debian 13, Ubuntu 26.04 `git`'s libcurl-gnutls) have no ML-KEM (lead's finding). Check `curl -V`.

### I. Pinning, HSM/PKCS#11, TPM and KMS-backed keys

- **Certificate or public-key pinning** (callback comparing `GetPublicKeyString()` or a SPKI hash): unaffected. PQ key exchange does not change the server certificate or its key. Pins break only when the certificate changes, for example a later move to ML-DSA certificates. Reasoning from the TLS 1.3 design, consistent with case C/D tests; no pinning test run.
- **Keys in an HSM or TPM on Linux:** .NET 9+ can open a key through an OpenSSL provider with `SafeEvpPKeyHandle.OpenKeyFromProvider` (for example a PKCS#11 or TPM2 provider) ([API](https://learn.microsoft.com/en-us/dotnet/api/system.security.cryptography.safeevppkeyhandle.openkeyfromprovider)). Key exchange is still done in software by OpenSSL, so PQ applies the same way. Using such a key as a Kestrel certificate key was not tested; not confirmed.
- **Windows CNG / smart-card / HSM keys via the certificate store:** Schannel uses them for signing; group choice is the machine curve order. Documented in principle; not tested.
- **AWS KMS asymmetric keys:** .NET has no built-in way to use a KMS key as a TLS private key. Use ACM certificates on the load balancer, or ACM exportable certificates. The calls to KMS itself are PQ when the client is (AWS service endpoints tab).

### J. Other cases

- **HTTPS proxy (`HTTPS_PROXY`):** `HttpClient` opens a CONNECT tunnel and does TLS end to end with the target, so the target's group applies. A TLS-intercepting proxy terminates TLS; then the proxy's TLS stack decides (Network devices and egress tab). Not tested here.
- **HTTP/2 and gRPC servers:** same Kestrel TLS path as case B. The v1 test endpoint had `Http1AndHttp2` enabled and negotiated PQ; no HTTP/2 or gRPC request was made, so the HTTP/2 path itself is Unverified.
- **WebSockets (`ClientWebSocket`, SignalR):** use `SocketsHttpHandler`; same as case A. Not run.
- **Service mesh sidecar (Istio, Linkerd, App Mesh Envoy):** if the app talks plain HTTP to the sidecar, the sidecar decides (Service mesh tab), and app-level changes don't matter for that leg.
- **Windows hosts (IIS, HTTP.sys, Kestrel, .NET Framework):**

    **Windows (IIS, HTTP.sys, Kestrel and HttpClient all use Schannel):**

    ``` powershell
    # Windows Server 2025 with KB5099536 (2026-07-14) or later; Windows 11 24H2/25H2 with KB5089573 or later
    Enable-TlsEccCurve -Name 'X25519_MLKEM768' -Position 0
    Get-TlsEccCurve
    ```

    - **Group Policy route:** Computer Configuration \> Administrative Templates \> Network \> SSL Configuration Settings \> **ECC Curve Order**, with `X25519_MLKEM768` first. A GPO overrides the cmdlet, and Microsoft says a new order takes effect on the next reboot ([Manage TLS](https://learn.microsoft.com/en-us/windows-server/security/tls/manage-tls), [Windows PQC FAQ](https://techcommunity.microsoft.com/t5/post-quantum-crypto-tech-blog/windows-tls-1-3-and-post-quantum-crypto-faq/ba-p/4556389)).

    - **Limits:** the ML-KEM groups are TLS 1.3 only, disabled by default, and not available in legacy FIPS mode ([supported groups](https://learn.microsoft.com/en-us/windows/win32/secauthn/tls-supported-groups-in-windows-11-24h2-and-later)).

    - **.NET version on Windows:** AWS lists PQ on Windows from .NET 10. Whether .NET 8 on a patched Windows picks up the group is not confirmed.

- **macOS developer machines:** Apple TLS; PQ needs .NET 10 with the Network.framework opt-in (see the bullet moved under H). Not tested.

## Solution and automation

1. **Inventory.** Per repo: base image tag (`grep -rn "^FROM" Dockerfile*`), target framework (`grep -rn "<TargetFramework" --include=*.csproj`), Lambda runtime (`Runtime: dotnet8` in SAM/CFN, `runtime = "dotnet8"` in Terraform), and the blockers in case F (`check-dotnet-pq.sh`). Per running container: `cat /etc/os-release; openssl version` (chiseled images: inspect the tag).
2. **Change, per compute type.**

    1.  **Lambda zip (dotnet8, dotnet10).** Add `pq-tls/openssl-pq.cnf` to the project with `CopyToPublishDirectory` so it lands at `/var/task/pq-tls/openssl-pq.cnf`. Set `OPENSSL_CONF` to that path in SAM, CloudFormation or Terraform. If the function already sets `OPENSSL_CONF`, don't overwrite it; merge and review.

    2.  **Lambda container image.** `COPY` the file and set `ENV OPENSSL_CONF=...` on top of `public.ecr.aws/lambda/dotnet:10` (or `:8`).

    3.  **Lambda Native AOT (`provided.al2023`).** Same file and env var. AOT doesn't bundle OpenSSL; it loads the runtime's `libssl.so.3` (Tested). Build on AL2023 so glibc matches.

    4.  **Fargate, ECS, EKS.** Preferred: switch `FROM` to `aspnet:10.0-alpine`, `10.0-resolute` or `10.0-resolute-chiseled`; no env var needed. For .NET 8 on glibc: AL2023 base + config file + `ENV OPENSSL_CONF`. Pin the image by digest.

    5.  **EC2 Linux (AL2023).** Whole host: an SSM document runs `update-crypto-policies --set DEFAULT:PQ`, then restarts services. One service only: `Environment=OPENSSL_CONF=...` in its systemd unit.

    6.  **EC2 Windows.** Install the July 2026 cumulative update or later, then run `Enable-PqTls.ps1` through SSM Run Command, or set the GPO, and reboot.

    The Dockerfiles, csproj files, SAM, CloudFormation, Terraform, ECS task definition, EKS manifest, systemd unit, SSM documents and PowerShell script are in Full configuration files below.

3. **CI guardrail.** Run `check-dotnet-pq.sh` (full file at the end) in every pipeline. It fails the build on `SslProtocols` pinned to TLS 1.2 or lower without `Tls13`, `appsettings` `SslProtocols` arrays without `Tls13`, MySqlConnector `TlsVersion=TLS 1.2`, `ServicePointManager.SecurityProtocol` without `Tls13`/`SystemDefault`, and base images with OpenSSL below 3.5 (`aspnet:8.0`, `10.0`, `-noble`, `-jammy`, `-bookworm-slim`, `-azurelinux3.0`). It warns on `CipherSuitesPolicy`, `ssl.curves.list`, `Grpc.Core`, `OPENSSL_CONF` and disabled certificate validation. Tested on bad and good fixtures (`deep/dotnet/v2/ci/fixtures`): exit 1 with 4 findings on bad, exit 0 on good.
4. **Fleet rollout.**
    1. Canary one service per compute type (one Lambda, one ECS service, one EC2 host). Deploy the image or env-var change only, no app code.
    2. Watch error rate and TLS failures for 24 h; check CloudTrail `tlsDetails.keyExchange` for KMS/STS/Secrets Manager calls from that role (expect `X25519MLKEM768`).
    3. Roll by wave (10%, 50%, 100%) through the normal deployment pipeline; ECS/EKS rolling updates, Lambda alias weights.
    4. Rollback = remove `OPENSSL_CONF`, revert the `FROM` line, or `update-crypto-policies --set DEFAULT`. No certificate or store to roll back, because none changed.

## How to test

1. **Posture.** In the image or host: `cat /etc/os-release; openssl version` (3.5 or later needed). AL2023: `echo $OPENSSL_CONF` or `update-crypto-policies --show` (`DEFAULT:PQ`). Repo: `sh check-dotnet-pq.sh .` exits 0.
2. **Start the harness.** One container runs four OpenSSL 3.5 servers with your private CA's certificate: PQ-only (8443), classical-only (8444), and the same two requiring a client certificate (8445, 8446). See `run-cases.sh` (the `dotnet2-tools` container).
3. **Client tests (cases A, D, E, F).** Run your app's own HTTP call, or the probe `kclient.dll`, against all four ports. Pass = PQ-only and classical-only both return 200; with mTLS, the cert-required ports return 200 only with your client certificate. Script: `client-cases.sh` (runs D0–D5, E0–E3, F1–F2).
4. **Server tests (cases B, C, E, F).** Start your Kestrel service with its real certificate config, then from an OpenSSL 3.5 container:

```bash
printf 'GET / HTTP/1.1\r\nHost: api.internal\r\nConnection: close\r\n\r\n' | \
  openssl s_client -connect api.internal:8443 -servername api.internal -groups X25519MLKEM768 -tls1_3 \
  -CAfile ca.crt -verify_return_error -brief -ign_eof   # expect: Negotiated TLS1.3 group: X25519MLKEM768 and your response
# fallback: same with -groups X25519 (and no -tls1_3): must also succeed
# mTLS: add -cert client.crt -key client.key; without them the request must be refused
# every SNI name you serve: repeat with each -servername
```

5. **Negative control.** Run the same tests on the old image (or without `OPENSSL_CONF`): PQ-only must fail and classical must pass. This proves the test can tell the difference.
6. **In the cloud.** CloudTrail `tlsDetails.keyExchange` for KMS, STS, IAM, Secrets Manager, ACM calls from the service role; load balancer or front-door logs for inbound legs (their tabs). .NET itself doesn't expose the negotiated group (`ITlsHandshakeFeature` shows protocol and cipher only).
7. **Rollback test.** Remove the env var or revert the image in a canary and rerun step 3: PQ-only fails again, classical still passes.

**Reference checks**

- **Posture (Linux image or host):** `cat /etc/os-release`; `openssl version` where present (chiseled images have no shell: check the base tag). OpenSSL below 3.5 = not PQ. On AL2023 also check `echo $OPENSSL_CONF` or `update-crypto-policies --show` (expect `DEFAULT:PQ`).

- **Posture (code and config):** search for `SslProtocols.Tls12`, `EnabledSslProtocols`, `"SslProtocols"` in `appsettings*.json`, `TlsVersion=` in MySQL connection strings, `SslProtocols=` in Redis strings, and `Grpc.Core` package references.

- **Posture (Windows):** `Get-TlsEccCurve` lists `X25519_MLKEM768` first; `Get-HotFix` shows the July 2026 update or later.

- **Live client test:** run the app's call against a server started with `openssl s_server -groups X25519MLKEM768 -tls1_3 -www`; it must succeed. Against `-groups X25519` it must also succeed (fallback). Probe used here: `deep/dotnet/client/Program.cs`.

- **Live server test:** `openssl s_client -connect host:8443 -groups X25519MLKEM768 -tls1_3 -brief` prints `Negotiated TLS1.3 group: X25519MLKEM768`; with `-groups X25519` it must still connect. Or `curl --curves X25519MLKEM768 https://host:8443/` with curl built on OpenSSL 3.5 (Tested against Kestrel on Alpine).

- **Observed signal:** .NET doesn't expose the negotiated group (`ITlsHandshakeFeature` shows only protocol and cipher), so app logs can't prove PQ. Use CloudTrail `tlsDetails.keyExchange` for calls to KMS, STS, IAM, Secrets Manager and ACM (expect `X25519MLKEM768`), the database server side, or the load balancer and front-door logs (see their tabs).

## Pitfalls and rollback

- **Default image tags are not PQ.** `8.0` (Debian 12) and `10.0` (Ubuntu 24.04) ship OpenSSL 3.0; Azure Linux 3.0 ships 3.3. No env var fixes OpenSSL below 3.5, and `DOTNET_OPENSSL_VERSION_OVERRIDE` can only pick a libssl that is installed. Change the image.

- **The kit config file is AL2023-only.** It includes `/etc/crypto-policies/...`, which doesn't exist on Debian, Ubuntu or Alpine. Don't copy it into other images.

- **`OPENSSL_CONF` replaces the system config.** The kit file re-includes the AL2023 policy so other settings stay; a hand-written file that doesn't can drop provider or FIPS settings.

- **TLS 1.2 pins.** `SslProtocols.Tls12` anywhere (handler, Kestrel, MySQL `TlsVersion`, Redis `SslProtocols`) disables PQ without an error against servers that also accept 1.2.

- **Alpine is musl.** Test native dependencies (Confluent.Kafka failed to load its native library here), ICU/globalization and DNS behaviour before switching. `10.0-resolute` is the glibc alternative.

- **Classical servers keep working.** Every PQ client in the tests still connected to the X25519-only server, so the change is low risk for outbound calls.

- **Windows:** the group order is machine-wide; a GPO "ECC Curve Order" overrides local cmdlet changes, and the policy takes effect on reboot.

- **Rollback:** remove the `OPENSSL_CONF` env var (Lambda, ECS, systemd) or run `update-crypto-policies --set DEFAULT`; revert the `FROM` line; on Windows run `Disable-TlsEccCurve -Name 'X25519_MLKEM768'` (or remove it from the GPO) and reboot.

- **Debian 12 and Ubuntu 24.04 images hide the problem in tests that only use classical servers.** Every certificate and trust case passed classically there (Tested). Always test against a PQ-only server.
- **`CreateFromPemFile(caPath)` with one argument throws for a CA-only file.** Use `CreateFromPem(File.ReadAllText(path))` (Tested).
- **TLS 1.2-only Kestrel with an EC certificate** refused clients whose group list lacks P-256 (Tested, F3b). One more reason to allow TLS 1.3.
- **Kestrel `X509Store` certificates on Linux** live in the user's home directory; a read-only root filesystem or a new container loses them unless mounted or re-imported. Not PQ-related.
- **Alpine CA install** may need `apk add ca-certificates` before `update-ca-certificates`.
- **.NET 8 and 9 are out of support since 2026-11-10.** The PQ fix works on .NET 8, but plan the move to .NET 10 ([Microsoft](https://devblogs.microsoft.com/dotnet/dotnet-8-9-end-of-support/)).

## Full configuration files

Every file the sections above refer to, complete. Files marked tested were run here on 2026-11-14 (scripts and output in `deep/dotnet/`). The IaC files follow the documented resource schemas but were not deployed (no AWS credentials here).

**`pq-tls/openssl-pq.cnf`** (Amazon Linux 2023 family only: Lambda dotnet8/dotnet10, provided.al2023, AL2023 containers and EC2; tested). It includes AL2023's crypto-policy file, so don't use it on Debian, Ubuntu or Alpine.

``` ini
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

**`Program.cs`** (Kestrel server; tested on every image in the status matrix)

``` csharp
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

``` json
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

In production read the certificate password from Secrets Manager or a mounted secret, not from the file.

**`App.csproj`** (Kestrel service; tested)

``` xml
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

**`Function.csproj`** (Lambda zip on the dotnet8 or dotnet10 managed runtime; puts the config file at `/var/task/pq-tls/openssl-pq.cnf`)

``` xml
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
    <None Include="pq-tls/openssl-pq.cnf" CopyToOutputDirectory="PreserveNewest" CopyToPublishDirectory="PreserveNewest" />
  </ItemGroup>
</Project>
```

**`FunctionAot.csproj`** (Native AOT on `provided.al2023`; an AOT binary was tested in the `provided:al2023` image)

``` xml
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

Build AOT on Amazon Linux 2023 so the binary links against the same glibc as `provided.al2023`.

**`Dockerfile`** (Fargate/ECS/EKS on Alpine: PQ with no config; tested with `aspnet:8.0-alpine` and `aspnet:10.0-alpine`)

``` dockerfile
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

**`Dockerfile.resolute`** (glibc alternative: Ubuntu 26.04, PQ with no config; tested with `aspnet:10.0-resolute` and `10.0-resolute-chiseled`)

``` dockerfile
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

**`Dockerfile.al2023`** (glibc on Amazon Linux 2023 with the config file; tested)

``` dockerfile
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

``` dockerfile
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

**`template.yaml`** (SAM: zip on the managed runtime, and Native AOT)

``` yaml
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

``` yaml
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

``` hcl
resource "aws_lambda_function" "dotnet" {
  function_name    = "orders-api"
  runtime          = "dotnet10" # or "provided.al2023" with handler "bootstrap" for Native AOT
  handler          = "Function::Function.Handler::FunctionHandler"
  architectures    = ["arm64"]
  role             = aws_iam_role.fn.arn
  filename         = "build/orders-api.zip" # zip holds pq-tls/openssl-pq.cnf at its root
  source_code_hash = filebase64sha256("build/orders-api.zip")

  environment {
    variables = {
      OPENSSL_CONF = "/var/task/pq-tls/openssl-pq.cnf"
    }
  }
}
```

**`taskdef.json`** (ECS/Fargate; the env var is only needed for the AL2023 image and can be left out for Alpine or resolute)

``` json
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

``` hcl
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

``` yaml
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

``` yaml
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

**`/etc/systemd/system/orders-api.service`** (EC2 Amazon Linux 2023, one service; the same `OPENSSL_CONF` setting was tested in an AL2023 container)

``` ini
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

**`ssm-al2023-pq-policy.yaml`** (SSM Command document, whole host on EC2 AL2023.12+; route [Documented](https://docs.aws.amazon.com/linux/al2023/ug/crypto-policies-pq.html), document not run here)

``` yaml
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

``` powershell
#Requires -RunAsAdministrator
# Puts the hybrid ML-KEM group first in the Schannel supported-groups order.
# Needs Windows Server 2025 with KB5099536 (2026-07-14) or later,
# or Windows 11 24H2/25H2 with KB5089573 or later.
$ErrorActionPreference = 'Stop'
$build = [Environment]::OSVersion.Version
Write-Output "OS build: $build"
if ($build.Build -lt 26100) { throw 'Schannel ML-KEM groups need Windows Server 2025 / Windows 11 24H2 or later.' }

Write-Output 'Before:'; Get-TlsEccCurve
Enable-TlsEccCurve -Name 'X25519_MLKEM768' -Position 0
Write-Output 'After:'; Get-TlsEccCurve

# A Group Policy "ECC Curve Order" setting overrides this; if one is set, edit the GPO instead.
# Reboot so every Schannel user (IIS, HTTP.sys, Kestrel, HttpClient) picks up the new order.
Restart-Computer -Force
```

**`ssm-windows-pq.json`** (SSM Command document wrapping the script; `exit 3010` asks SSM to reboot the instance)

``` json
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

**`appsettings.json` (Kafka section) and producer setup** (Confluent.Kafka; `ssl.curves.list` is optional because librdkafka 2.14.2+ is PQ by default; tested)

``` json
{
  "Kafka": {
    "BootstrapServers": "b-1.msk.example:9094",
    "SecurityProtocol": "Ssl",
    "SslCurvesList": "X25519MLKEM768:X25519:P-256"
  }
}
```

``` csharp
var cfg = new ProducerConfig
{
    BootstrapServers = conf["Kafka:BootstrapServers"],
    SecurityProtocol = SecurityProtocol.Ssl,
};
// librdkafka passes this to SSL_CTX_set1_curves_list.
cfg.Set("ssl.curves.list", conf["Kafka:SslCurvesList"]);
```

The files below were added in this pass (2026-11-14). The probes and scripts are test tools, not production code; the CI check and workflow are meant for production pipelines.

**`tools/check-dotnet-pq.sh`** (CI guardrail; tested on fixtures: bad tree exit 1 with 4 findings, good tree exit 0)

```bash
#!/bin/sh
# CI guardrail: fail the build on .NET settings that block hybrid post-quantum key exchange.
# usage: sh check-dotnet-pq.sh [repo-root]   (exit 1 = blocking finding; warnings never fail)
ROOT="${1:-.}"; FAIL=0
hit() { # level pattern description [exclude-pattern]
  out=$(grep -rnE --include='*.cs' --include='*.json' --include='*.config' --include='*.xml' \
        --include='*.csproj' --include='*.props' --include='Dockerfile*' --include='*.yaml' --include='*.yml' --include='*.tf' \
        --exclude-dir=bin --exclude-dir=obj --exclude-dir=node_modules --exclude-dir=.git "$2" "$ROOT" 2>/dev/null | grep -vE "${4:-^$}" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//')
  [ -z "$out" ] && return
  echo "$1: $3"; echo "$out" | sed 's/^/    /' | head -20
  [ "$1" = BLOCK ] && FAIL=1
}
# 1. TLS 1.2 pinned without 1.3 (code, appsettings, connection strings)
hit BLOCK 'SslProtocols\.(Tls12|Tls11|Tls)([^0-9]|$)' "SslProtocols pinned to TLS 1.2 or lower (PQ needs TLS 1.3): use SslProtocols.None" 'Tls13' 
hit BLOCK '"SslProtocols"[[:space:]]*:[[:space:]]*\[' "appsettings SslProtocols without Tls13: add Tls13 or remove the key" 'Tls13' 
hit BLOCK '(TlsVersion|Tls Version)[[:space:]]*=[[:space:]]*"?(TLS ?1\.2|Tls12)"?[;"]' "MySqlConnector TlsVersion pinned to 1.2"
hit BLOCK 'ServicePointManager\.SecurityProtocol[[:space:]]*=' "ServicePointManager.SecurityProtocol set without Tls13" 'Tls13|SystemDefault' 
# 2. Base images that ship OpenSSL < 3.5 (no ML-KEM)
hit BLOCK 'FROM[[:space:]]+mcr\.microsoft\.com/dotnet/(aspnet|runtime|runtime-deps|sdk):[0-9.]+([[:space:]]|$|@)|FROM[[:space:]]+mcr\.microsoft\.com/dotnet/[a-z-]+:[0-9.]+-(noble|jammy|bookworm-slim|azurelinux3\.0)' "base image with OpenSSL < 3.5: use -alpine, -resolute or AL2023 + OPENSSL_CONF"
# 3. Settings that need review (warn only)
hit WARN 'CipherSuitesPolicy' "CipherSuitesPolicy set: keep TLS 1.3 suites in it; NotSupportedException on Windows"
hit WARN 'ssl\.curves\.list|ssl\.groups' "librdkafka group list set: X25519MLKEM768 must be in it"
hit WARN 'Grpc\.Core"' "Grpc.Core (C-core, own TLS stack): migrate to Grpc.Net.Client"
hit WARN 'OPENSSL_CONF' "OPENSSL_CONF set: on AL2023 it must point at a file that keeps X25519MLKEM768 in Groups"
hit WARN 'RemoteCertificateValidationCallback[[:space:]]*=[[:space:]]*\([^)]*\)[[:space:]]*=>[[:space:]]*true|ServerCertificateCustomValidationCallback[[:space:]]*=[[:space:]]*HttpClientHandler\.DangerousAcceptAnyServerCertificateValidator' "certificate validation disabled (not a PQ blocker, but fix it)"
[ $FAIL = 1 ] && echo "PQ check: FAILED" || echo "PQ check: passed"
exit $FAIL
```

**`.github/workflows/pq-check.yml`** (GitHub Actions wrapper; not run here)

```yaml
# .github/workflows/pq-check.yml — runs the .NET PQ guardrail on every pull request.
# Not run here (no GitHub runner); the script itself was tested on fixtures.
name: pq-tls-check
on: [pull_request]
jobs:
  pq-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Block PQ-disabling TLS settings and old base images
        run: sh tools/check-dotnet-pq.sh .
```

**`pq-test/build2.sh`** (creates the private CA, EC and RSA server certs, client cert (PFX, PEM, encrypted PEM) and builds the probes; tested)

```bash
#!/bin/bash
# Build the v2 .NET probes and a private-CA certificate set (EC + RSA server certs, client cert; PFX, PEM, encrypted PEM).
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"; LBL=run=pqc-lang2-dotnet
dg() { docker pull -q "$1" >/dev/null 2>&1; docker image inspect --format '{{index .RepoDigests 0}}' "$1"; }
SDK=$(dg mcr.microsoft.com/dotnet/sdk:8.0); TRIXIE=$(dg debian:trixie-slim)
echo "sdk=$SDK"; echo "trixie=$TRIXIE"
mkdir -p "$W/certs"
docker run --rm --label $LBL --name dotnet2-certs -v "$W/certs":/c -w /c "$TRIXIE" sh -ec '
  apt-get update -qq >/dev/null && apt-get install -y -qq openssl >/dev/null 2>&1
  SAN="subjectAltName=DNS:pqsrv,DNS:clsrv,DNS:kestrel,DNS:ec.test,DNS:rsa.test,DNS:localhost"
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 -subj "/CN=PQ Test Private CA" \
    -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign -keyout ca.key -out ca.crt 2>/dev/null
  mk() { # name keyspec cn eku
    openssl req -new -newkey $2 -nodes -subj "/CN=$3" -keyout $1.key -out $1.csr 2>/dev/null
    printf "%s\nextendedKeyUsage=%s\nbasicConstraints=CA:FALSE\n" "$SAN" "$4" > $1.ext
    openssl x509 -req -in $1.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 30 -extfile $1.ext -out $1.crt 2>/dev/null
    cat $1.crt ca.crt > $1-chain.crt
    openssl pkcs12 -export -in $1.crt -inkey $1.key -certfile ca.crt -out $1.pfx -passout pass:changeit
    openssl pkcs8 -topk8 -in $1.key -out $1-enc.key -v2 aes-256-cbc -passout pass:changeit
    rm -f $1.csr $1.ext; }
  mk server-ec "ec -pkeyopt ec_paramgen_curve:P-256" "pq-server-ec" serverAuth
  mk server-rsa "rsa:2048" "pq-server-rsa" serverAuth
  mk client "ec -pkeyopt ec_paramgen_curve:P-256" "pq-client" clientAuth
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 -subj "/CN=Other CA" -keyout other-ca.key -out other-ca.crt 2>/dev/null
  chmod 644 *; ls'
for p in kserver kclient; do
  docker run --rm --label $LBL --name dotnet2-build-$p -v "$W/$p":/src -w /src "$SDK" sh -c "dotnet publish -c Release -o /src/out -v q --nologo >/src/build.log 2>&1 && echo $p-built || (tail -20 /src/build.log; echo $p-FAILED)"
done
```

**`pq-test/kserver/Program.cs`** (Kestrel probe for cases C, E, F; tested)

```csharp
// Kestrel test server for the .NET PQ runbook, cases C (certificates), E (mTLS) and F (TLS settings).
// The certificate comes from configuration (env vars Kestrel__...), except in the modes below:
//   MODE=selector  ServerCertificateSelector: ec.test -> EC cert, rsa.test -> RSA cert (PFX files)
//   MODE=store     imports STORE_IMPORT_PFX into X509Store CurrentUser/My first; the endpoint then uses
//                  Kestrel config "Certificate": { "Subject", "Store": "My", "Location": "CurrentUser" }
//   MTLS=1         ClientCertificateMode.RequireCertificate, client chain checked against CA_FILE (CustomTrustStore)
//   TLS12=1        SslProtocols = Tls12 only (pitfall)
//   CIPHERS13=1    CipherSuitesPolicy limited to TLS 1.3 AES-GCM suites
using System.Net.Security;
using System.Security.Authentication;
using System.Security.Cryptography.X509Certificates;
using Microsoft.AspNetCore.Connections.Features;
using Microsoft.AspNetCore.Server.Kestrel.Https;

string mode = Environment.GetEnvironmentVariable("MODE") ?? "config";
string? caFile = Environment.GetEnvironmentVariable("CA_FILE");

if (mode == "store")
{
    // One-time import, as a deployment step would do it. PersistKeySet keeps the key in the store on Linux.
    using var store = new X509Store(StoreName.My, StoreLocation.CurrentUser);
    store.Open(OpenFlags.ReadWrite);
    var pfx = new X509Certificate2(Environment.GetEnvironmentVariable("STORE_IMPORT_PFX")!,
        Environment.GetEnvironmentVariable("STORE_IMPORT_PASSWORD"), X509KeyStorageFlags.PersistKeySet | X509KeyStorageFlags.Exportable);
    store.Add(pfx);
    Console.WriteLine($"imported {pfx.Subject} into CurrentUser/My ({store.Certificates.Count} certs)");
}

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.ConfigureKestrel(kestrel =>
{
    kestrel.ConfigureHttpsDefaults(https =>
    {
        https.SslProtocols = Environment.GetEnvironmentVariable("TLS12") == "1" ? SslProtocols.Tls12 : SslProtocols.None;

        if (mode == "selector")
        {
            var ec = new X509Certificate2("/certs/server-ec.pfx", "changeit");
            var rsa = new X509Certificate2("/certs/server-rsa.pfx", "changeit");
            https.ServerCertificateSelector = (ctx, name) => name == "rsa.test" ? rsa : ec;
        }

        if (Environment.GetEnvironmentVariable("CIPHERS13") == "1")
        {
            https.OnAuthenticate = (ctx, opts) => opts.CipherSuitesPolicy = new CipherSuitesPolicy(new[] {
                TlsCipherSuite.TLS_AES_256_GCM_SHA384, TlsCipherSuite.TLS_AES_128_GCM_SHA256 });
        }

        if (Environment.GetEnvironmentVariable("MTLS") == "1")
        {
            var ca = X509Certificate2.CreateFromPem(File.ReadAllText(caFile!)); // cert only; CreateFromPemFile would want a key
            https.ClientCertificateMode = ClientCertificateMode.RequireCertificate;
            https.ClientCertificateValidation = (cert, chain, errors) =>
            {
                using var c = new X509Chain();
                c.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
                c.ChainPolicy.CustomTrustStore.Add(ca);
                c.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
                return c.Build(cert);
            };
        }
    });
});

var app = builder.Build();
app.MapGet("/", (HttpContext ctx) =>
{
    var tls = ctx.Features.Get<ITlsHandshakeFeature>();
    var cc = ctx.Connection.ClientCertificate;
    return $"ok protocol={tls?.Protocol} cipher={tls?.NegotiatedCipherSuite} host={ctx.Request.Host.Host} clientcert={cc?.Subject ?? "none"}\n";
});
app.Run();
```

**`pq-test/kserver/kserver.csproj`** (tested)

```xml
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <RollForward>Major</RollForward>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <InvariantGlobalization>true</InvariantGlobalization>
    <NoWarn>SYSLIB0057</NoWarn>
  </PropertyGroup>
</Project>
```

**`pq-test/kclient/Program.cs`** (HttpClient probe for cases D, E, F; tested)

```csharp
// .NET PQ client probe for cases D (custom CA trust), E (client certificates) and F (TLS settings).
// usage: dotnet kclient.dll <case> <url> [<url> ...]   (CA_FILE, CLIENT_PFX, CLIENT_CRT, CLIENT_KEY env vars)
// cases: system | callback | chainpolicy | mtls-handler | mtls-sockets | mtls-store | tls12 | ciphers13
using System.Net.Security;
using System.Security.Authentication;
using System.Security.Cryptography.X509Certificates;

string kase = args[0];
string caFile = Environment.GetEnvironmentVariable("CA_FILE") ?? "/certs/ca.crt";
// Not CreateFromPemFile(caFile): with no key path it looks for a private key in the same file and throws.
X509Certificate2 Ca() => X509Certificate2.CreateFromPem(File.ReadAllText(caFile));

X509ChainPolicy CustomTrust()
{
    var p = new X509ChainPolicy { TrustMode = X509ChainTrustMode.CustomRootTrust, RevocationMode = X509RevocationMode.NoCheck };
    p.CustomTrustStore.Add(Ca());
    return p;
}

// Validation callback the way many teams write it: build the chain against their own CA, keep hostname checks.
bool Callback(object? s, X509Certificate2? cert, X509Chain? chain, SslPolicyErrors errors)
{
    if (cert is null || (errors & SslPolicyErrors.RemoteCertificateNameMismatch) != 0) return false;
    using var c = new X509Chain { ChainPolicy = CustomTrust() };
    return c.Build(cert);
}

HttpMessageHandler Build()
{
    switch (kase)
    {
        case "system": return new SocketsHttpHandler();                        // OS trust store / SSL_CERT_FILE / SSL_CERT_DIR
        case "callback": return new HttpClientHandler { ServerCertificateCustomValidationCallback = Callback };
        case "chainpolicy":
        {
            var h = new SocketsHttpHandler();
            h.SslOptions.CertificateChainPolicy = CustomTrust();             // .NET 7+
            return h;
        }
        case "mtls-handler":
        {
            var h = new HttpClientHandler { ServerCertificateCustomValidationCallback = Callback, ClientCertificateOptions = ClientCertificateOption.Manual };
            h.ClientCertificates.Add(new X509Certificate2(Environment.GetEnvironmentVariable("CLIENT_PFX")!, "changeit"));
            return h;
        }
        case "mtls-sockets":
        {
            var h = new SocketsHttpHandler();
            h.SslOptions.CertificateChainPolicy = CustomTrust();
            h.SslOptions.ClientCertificates = new X509CertificateCollection {
                X509Certificate2.CreateFromPemFile(Environment.GetEnvironmentVariable("CLIENT_CRT")!, Environment.GetEnvironmentVariable("CLIENT_KEY")) };
            return h;
        }
        case "mtls-store":
        {
            using var store = new X509Store(StoreName.My, StoreLocation.CurrentUser);
            store.Open(OpenFlags.ReadWrite);
            store.Add(new X509Certificate2(Environment.GetEnvironmentVariable("CLIENT_PFX")!, "changeit", X509KeyStorageFlags.PersistKeySet));
            var found = store.Certificates.Find(X509FindType.FindBySubjectName, "pq-client", false);
            var h = new SocketsHttpHandler();
            h.SslOptions.CertificateChainPolicy = CustomTrust();
            h.SslOptions.ClientCertificates = new X509CertificateCollection { found[0] };
            return h;
        }
        case "tls12":
        {
            var h = new SocketsHttpHandler();
            h.SslOptions.CertificateChainPolicy = CustomTrust();
            h.SslOptions.EnabledSslProtocols = SslProtocols.Tls12;
            return h;
        }
        case "ciphers13":
        {
            var h = new SocketsHttpHandler();
            h.SslOptions.CertificateChainPolicy = CustomTrust();
            h.SslOptions.CipherSuitesPolicy = new CipherSuitesPolicy(new[] { TlsCipherSuite.TLS_AES_256_GCM_SHA384, TlsCipherSuite.TLS_AES_128_GCM_SHA256 });
            return h;
        }
        default: throw new ArgumentException(kase);
    }
}

foreach (var url in args.Skip(1))
{
    string r;
    try
    {
        using var http = new HttpClient(Build()) { Timeout = TimeSpan.FromSeconds(10) };
        var resp = http.GetAsync(url).GetAwaiter().GetResult();
        var body = resp.Content.ReadAsStringAsync().GetAwaiter().GetResult();
        r = $"OK {(int)resp.StatusCode}" + (body.StartsWith("ok ") ? " " + body.Trim() : "");
    }
    catch (Exception e)
    {
        var i = e; while (i.InnerException != null) i = i.InnerException;
        r = $"FAIL {i.GetType().Name}: {i.Message.Split('\n')[0]}";
    }
    Console.WriteLine($"  [{kase}] {url} -> {r}");
}
```

**`pq-test/kclient/kclient.csproj`** (tested)

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <RollForward>Major</RollForward>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <InvariantGlobalization>true</InvariantGlobalization>
    <NoWarn>SYSLIB0057</NoWarn>
  </PropertyGroup>
</Project>
```

**`pq-test/client-cases.sh`** (runs inside each .NET image; tested)

```bash
#!/bin/sh
# Runs INSIDE a .NET runtime container. Cases D (trust), E (client certs), F (TLS settings) against:
#   pqsrv:8443 PQ-only  | clsrv:8444 classical-only  (server cert signed by the private CA)
#   pqsrv:8445 PQ-only + client cert required | clsrv:8446 classical-only + client cert required
C="dotnet /w/kclient/out/kclient.dll"
PQ=https://pqsrv:8443/; CL=https://clsrv:8444/; PQM=https://pqsrv:8445/; CLM=https://clsrv:8446/
export CA_FILE=/certs/ca.crt CLIENT_PFX=/certs/client.pfx CLIENT_CRT=/certs/client.crt CLIENT_KEY=/certs/client.key
echo "D0 no private CA anywhere (expect FAIL on both)"; $C system $PQ $CL
echo "D1 SSL_CERT_FILE=/certs/ca.crt";                  SSL_CERT_FILE=/certs/ca.crt $C system $PQ $CL
echo "D2 SSL_CERT_DIR=/certs/hashdir (openssl rehash)";  SSL_CERT_DIR=/certs/hashdir $C system $PQ $CL
echo "D3 ServerCertificateCustomValidationCallback";    $C callback $PQ $CL
echo "D4 X509ChainPolicy.CustomTrustStore";             $C chainpolicy $PQ $CL
echo "D5 private CA added to the system store"
if [ -d /etc/pki/ca-trust/source/anchors ]; then cp /certs/ca.crt /etc/pki/ca-trust/source/anchors/pq-ca.crt && update-ca-trust && echo "  (update-ca-trust)"
else
  command -v update-ca-certificates >/dev/null || apk add -q ca-certificates >/dev/null 2>&1
  cp /certs/ca.crt /usr/local/share/ca-certificates/pq-ca.crt && update-ca-certificates >/dev/null 2>&1 && echo "  (update-ca-certificates)"
fi
$C system $PQ $CL
echo "E0 server requires a client cert, client sends none (expect FAIL)"; $C system $PQM $CLM
echo "E1 HttpClientHandler.ClientCertificates (PFX)";       $C mtls-handler $PQM $CLM
echo "E2 SocketsHttpHandler.SslOptions.ClientCertificates (PEM pair)"; $C mtls-sockets $PQM $CLM
echo "E3 client cert from X509Store CurrentUser/My";        $C mtls-store $PQM $CLM
echo "F1 EnabledSslProtocols=Tls12 (expect PQ-only FAIL)";  $C tls12 $PQ $CL
echo "F2 CipherSuitesPolicy = TLS 1.3 AES-GCM only";        $C ciphers13 $PQ $CL
```

**`pq-test/run-cases.sh`** (full matrix: harness servers, client cases, Kestrel cases; tested)

```bash
#!/bin/bash
# .NET PQ v2 matrix: cases C (Kestrel certificates), D (trust), E (mTLS), F (TLS settings)
# on aspnet 8.0 (Debian 12), 8.0-alpine, 10.0-alpine, 10.0-resolute (Ubuntu 26.04), AL2023 + OPENSSL_CONF.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"; LBL=run=pqc-lang2-dotnet; NET=pqnet2-dotnet
ONLY="${1:-all}"   # all | client | server
dg() { docker pull -q "$1" >/dev/null 2>&1; docker image inspect --format '{{index .RepoDigests 0}}' "$1"; }
MCR=mcr.microsoft.com/dotnet/aspnet
cp "$W/../../../lambda-pq/layer/pq-tls/openssl-pq.cnf" "$W/openssl-pq.cnf"
cp "$W/../Dockerfile.al2023-test" "$W/Dockerfile.al2023-test"
docker build -q --label $LBL -t pqc-lang2-dotnet-al2023:test -f "$W/Dockerfile.al2023-test" "$W" >/dev/null && echo "al2023 test image built"
declare -a NAMES DIGS ENVS
i=0; for t in 8.0 8.0-alpine 10.0-alpine 10.0-resolute; do NAMES[$i]="aspnet:$t"; DIGS[$i]=$(dg $MCR:$t); ENVS[$i]="-e X=1"; i=$((i+1)); done
NAMES[$i]="AL2023 aspnetcore-8 + OPENSSL_CONF"; DIGS[$i]=pqc-lang2-dotnet-al2023:test; ENVS[$i]="-e OPENSSL_CONF=/etc/pq-tls/openssl-pq.cnf"
for k in "${!NAMES[@]}"; do echo "image ${NAMES[$k]} = ${DIGS[$k]}"; done
TRIXIE=$(dg debian:trixie-slim); echo "tools = $TRIXIE"

docker network create --label $LBL $NET >/dev/null
docker run -d --label $LBL --name dotnet2-tools --network $NET --network-alias pqsrv --network-alias clsrv -v "$W/certs":/certs "$TRIXIE" sh -c '
  apt-get update -qq >/dev/null && apt-get install -y -qq openssl >/dev/null 2>&1
  mkdir -p /certs/hashdir && cp /certs/ca.crt /certs/hashdir/ && openssl rehash /certs/hashdir
  cd /certs; S="-cert server-ec.crt -key server-ec.key -cert_chain ca.crt -www -quiet"
  openssl s_server -accept 8443 -groups X25519MLKEM768 -tls1_3 $S &
  openssl s_server -accept 8444 -groups X25519 $S &
  openssl s_server -accept 8445 -groups X25519MLKEM768 -tls1_3 $S -Verify 1 -CAfile ca.crt -verify_return_error &
  openssl s_server -accept 8446 -groups X25519 $S -Verify 1 -CAfile ca.crt -verify_return_error &
  openssl version > /certs/ready; wait' >/dev/null
for n in $(seq 1 60); do [ -f "$W/certs/ready" ] && break; sleep 2; done
echo "tools openssl: $(cat "$W/certs/ready")"

if [ "$ONLY" != server ]; then
echo; echo "=========== CLIENT CASES D, E, F ==========="
for k in "${!NAMES[@]}"; do
  echo; echo "--- ${NAMES[$k]}"
  docker run --rm --label $LBL --name dotnet2-client --network $NET ${ENVS[$k]} -v "$W":/w:ro -v "$W/certs":/certs:ro \
    --entrypoint sh "${DIGS[$k]}" -c '(. /etc/os-release; echo "  os=$PRETTY_NAME dotnet=$(ls /usr/share/dotnet/shared/Microsoft.NETCore.App 2>/dev/null || ls /usr/lib64/dotnet/shared/Microsoft.NETCore.App 2>/dev/null)"); sh /w/client-cases.sh' 2>&1
done
fi

if [ "$ONLY" != client ]; then
echo; echo "=========== KESTREL SERVER CASES C, E, F (probed with OpenSSL 3.5 s_client) ==========="
probe() { # $1 sni  $2 groups  $3 extra s_client args
  docker exec dotnet2-tools sh -c "printf 'GET / HTTP/1.1\r\nHost: $1\r\nConnection: close\r\n\r\n' | openssl s_client -connect kestrel:8443 -servername $1 -groups $2 -CAfile /certs/ca.crt -verify_return_error -brief -ign_eof $3 2>&1" \
    | grep -E 'Negotiated TLS1.3 group|Signature type|Protocol version|^ok |alert|error' | grep -v '^DONE' | sed 's/^/      /' | tr '\n' ' ' | sed 's/  */ /g'
}
K="-e Kestrel__Endpoints__Https__Url=https://0.0.0.0:8443"
PFX_EC="-e Kestrel__Certificates__Default__Path=/certs/server-ec.pfx -e Kestrel__Certificates__Default__Password=changeit"
declare -a MODES=(
  "C1 PFX, EC key (Certificates:Default Path+Password)|$PFX_EC|ec.test|"
  "C2 PFX, RSA key|-e Kestrel__Certificates__Default__Path=/certs/server-rsa.pfx -e Kestrel__Certificates__Default__Password=changeit|rsa.test|"
  "C3 PEM pair, EC (Path+KeyPath, chain in Path)|-e Kestrel__Certificates__Default__Path=/certs/server-ec-chain.crt -e Kestrel__Certificates__Default__KeyPath=/certs/server-ec.key|ec.test|"
  "C4 PEM pair, RSA, encrypted PKCS#8 key (KeyPath+Password)|-e Kestrel__Certificates__Default__Path=/certs/server-rsa-chain.crt -e Kestrel__Certificates__Default__KeyPath=/certs/server-rsa-enc.key -e Kestrel__Certificates__Default__Password=changeit|rsa.test|"
  "C5a ServerCertificateSelector (code), SNI ec.test|-e MODE=selector|ec.test|"
  "C5b ServerCertificateSelector (code), SNI rsa.test|-e MODE=selector|rsa.test|"
  "C6a Endpoint Sni config section, SNI ec.test|-e Kestrel__Endpoints__Https__Sni__ec.test__Certificate__Path=/certs/server-ec.pfx -e Kestrel__Endpoints__Https__Sni__ec.test__Certificate__Password=changeit -e Kestrel__Endpoints__Https__Sni__rsa.test__Certificate__Path=/certs/server-rsa.pfx -e Kestrel__Endpoints__Https__Sni__rsa.test__Certificate__Password=changeit|ec.test|"
  "C6b Endpoint Sni config section, SNI rsa.test|-e Kestrel__Endpoints__Https__Sni__ec.test__Certificate__Path=/certs/server-ec.pfx -e Kestrel__Endpoints__Https__Sni__ec.test__Certificate__Password=changeit -e Kestrel__Endpoints__Https__Sni__rsa.test__Certificate__Path=/certs/server-rsa.pfx -e Kestrel__Endpoints__Https__Sni__rsa.test__Certificate__Password=changeit|rsa.test|"
  "C7 X509Store CurrentUser/My (config Subject+Store+Location)|-e MODE=store -e STORE_IMPORT_PFX=/certs/server-ec.pfx -e STORE_IMPORT_PASSWORD=changeit -e Kestrel__Certificates__Default__Subject=pq-server-ec -e Kestrel__Certificates__Default__Store=My -e Kestrel__Certificates__Default__Location=CurrentUser -e Kestrel__Certificates__Default__AllowInvalid=true|ec.test|"
  "E4 RequireCertificate, client sends cert|-e MTLS=1 -e CA_FILE=/certs/ca.crt $PFX_EC|ec.test|-cert /certs/client.crt -key /certs/client.key"
  "E5 RequireCertificate, no client cert (expect no 'ok')|-e MTLS=1 -e CA_FILE=/certs/ca.crt $PFX_EC|ec.test|"
  "E6 RequireCertificate, cert from another CA (expect no 'ok')|-e MTLS=1 -e CA_FILE=/certs/ca.crt $PFX_EC|ec.test|-cert /certs/other-ca.crt -key /certs/other-ca.key"
  "F3 SslProtocols=Tls12 (expect PQ FAIL)|-e TLS12=1 $PFX_EC|ec.test|"
  "F4 CipherSuitesPolicy TLS1.3 AES-GCM only|-e CIPHERS13=1 $PFX_EC|ec.test|"
)
for k in "${!NAMES[@]}"; do
  echo; echo "--- ${NAMES[$k]}"
  for m in "${MODES[@]}"; do
    IFS='|' read -r label envs sni extra <<<"$m"
    docker run -d --label $LBL --name dotnet2-kestrel --network $NET --network-alias kestrel ${ENVS[$k]} $K $envs \
      -v "$W/kserver/out":/app:ro -v "$W/certs":/certs:ro -w /app --entrypoint dotnet "${DIGS[$k]}" /app/kserver.dll >/dev/null
    for n in $(seq 1 40); do docker logs dotnet2-kestrel 2>&1 | grep -qE "Now listening|Unhandled|fail:" && break; sleep 0.5; done
    if ! docker logs dotnet2-kestrel 2>&1 | grep -q "Now listening"; then
      echo "  $label: SERVER DID NOT START: $(docker logs dotnet2-kestrel 2>&1 | grep -m2 -E 'Exception|fail' | tr '\n' ' ' | cut -c1-300)"
    else
      echo "  $label"
      echo "    PQ client   :$(probe $sni X25519MLKEM768 "-tls1_3 $extra")"
      echo "    X25519 only :$(probe $sni X25519 "$extra")"
    fi
    docker rm -f dotnet2-kestrel >/dev/null 2>&1
  done
done
fi

echo; echo "=== cleanup (own label only) ==="
n=$(docker ps -aq --filter label=$LBL | wc -l | tr -d ' '); docker rm -f $(docker ps -aq --filter label=$LBL) >/dev/null 2>&1
docker network rm $NET >/dev/null; rm -f "$W/certs/ready"; echo "removed containers=$n network=$NET"
```

**`pq-test/run-f3.sh`** (TLS 1.2 + EC certificate follow-up; tested)

```bash
#!/bin/bash
# F3 follow-up: Kestrel SslProtocols=Tls12 with an EC cert. Why did a classical client offering only X25519 fail?
# Hypothesis: in TLS 1.2 the client's supported_groups list also limits the ECDSA certificate curve (P-256).
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"; LBL=run=pqc-lang2-dotnet; NET=pqnet2-dotnet-f3
A=$(docker image inspect --format '{{index .RepoDigests 0}}' mcr.microsoft.com/dotnet/aspnet:10.0-alpine)
T=$(docker image inspect --format '{{index .RepoDigests 0}}' debian:trixie-slim)
docker network create --label $LBL $NET >/dev/null
docker run -d --label $LBL --name dotnet2-tools-f3 --network $NET -v "$W/certs":/certs:ro "$T" sh -c 'apt-get update -qq >/dev/null; apt-get install -y -qq openssl >/dev/null 2>&1; touch /tmp/ready; sleep 600' >/dev/null
for i in $(seq 1 60); do docker exec dotnet2-tools-f3 test -f /tmp/ready 2>/dev/null && break; sleep 2; done
for cert in ec rsa; do
  docker run -d --label $LBL --name dotnet2-kestrel-f3 --network $NET --network-alias kestrel -e TLS12=1 \
    -e Kestrel__Endpoints__Https__Url=https://0.0.0.0:8443 -e Kestrel__Certificates__Default__Path=/certs/server-$cert.pfx -e Kestrel__Certificates__Default__Password=changeit \
    -v "$W/kserver/out":/app:ro -v "$W/certs":/certs:ro -w /app --entrypoint dotnet "$A" /app/kserver.dll >/dev/null
  for i in $(seq 1 40); do docker logs dotnet2-kestrel-f3 2>&1 | grep -q "Now listening" && break; sleep 0.5; done
  for g in X25519 X25519:P-256 X25519MLKEM768:X25519:P-256; do
    r=$(docker exec dotnet2-tools-f3 sh -c "echo | openssl s_client -connect kestrel:8443 -groups $g -brief 2>&1" | grep -E 'Protocol version|Server Temp Key|Negotiated|alert' | head -2 | tr '\n' ' ')
    echo "Tls12-only Kestrel, $cert cert, client groups $g: $r"
  done
  docker rm -f dotnet2-kestrel-f3 >/dev/null
done
docker rm -f dotnet2-tools-f3 >/dev/null; docker network rm $NET >/dev/null; echo "cleanup done"
```
