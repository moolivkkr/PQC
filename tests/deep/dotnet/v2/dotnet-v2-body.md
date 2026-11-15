<!--
.NET tab, v2 restructure (BRIEF-LANG-V2). Written 2026-11-14 by the .NET agent. NOT yet applied to the doc:
the doc refused reads and writes ("forbidden / role") after the account change, so the lead applies this file.

How to apply:
- Keep the H1 block mttvddjsrgd.0 (".NET runbook").
- A line "[MOVED: <ids>]" means: move those existing blocks (docs `move` op, keeps ids and comments) to that spot,
  unchanged. Do not retype them. Ids are full ids from the outline read at rev 14.
- A line "[DELETE: <ids>]" means: delete those blocks; their content is now carried by the new text above them.
- Everything else is new markdown to insert.
- After the moves, the old headings left empty get deleted: listed in the last comment of this file.
-->

## Problem statement

A .NET service on Linux negotiates TLS with whatever OpenSSL the container or host ships. On the default `mcr.microsoft.com/dotnet` tags (Debian 12 for `8.0`, Ubuntu 24.04 for `10.0`) that is OpenSSL 3.0, which has no ML-KEM. On Lambda and Amazon Linux 2023 it is OpenSSL 3.5, but the AL2023 crypto policy leaves ML-KEM out of the group list. Either way the handshake uses classical X25519 or P-256 key exchange. Traffic recorded today can be decrypted later by a quantum computer (harvest now, decrypt later).

Who controls the handshake: the OS TLS library, not .NET. `SslStream` (and everything built on it: `HttpClient`, Kestrel, Npgsql, MySqlConnector, StackExchange.Redis, gRPC) calls OpenSSL on Linux, Schannel on Windows and Apple's TLS on macOS. .NET has no API to set key-exchange groups. It can only block PQ, by pinning TLS 1.2.

The good news for teams with existing certificates, keystores and CA bundles: none of them need to change. Tested on 5 images below: PFX, PEM, encrypted PEM, RSA, EC, SNI, X509Store, private CAs, custom trust code and client certificates all keep working when PQ is turned on.

[MOVED: mttvddjsrgd.4167, mttvddjsrgd.4526]
<!-- The existing "What decides PQ here" paragraph and its 4 bullets go here unchanged. Then delete heading mttvddjsrgd.4146. -->

## Versions and native support

| Version | TLS stack | PQ client by default | PQ server (Kestrel) by default | API to set groups | FIPS-mode behaviour | Proposed solution | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| .NET 10 LTS (supported to Nov 2028) | SslStream → OpenSSL (Linux), Schannel (Windows) | Lambda `dotnet10`: no. Image `10.0`/`10.0-noble`: no. `10.0-alpine`, `10.0-resolute`: yes. AL2023/EC2: no | Same as client | None. OS config only (`OPENSSL_CONF`, crypto policy, Schannel curve order) | Follows OpenSSL. AL2023 `FIPS:PQ` policy keeps ML-KEM; Windows legacy FIPS mode has no ML-KEM groups | Use `-alpine` or `-resolute` images. On Lambda/AL2023 ship `openssl-pq.cnf` + `OPENSSL_CONF` | Tested (10.0.15); FIPS rows Documented ([AL2023](https://docs.aws.amazon.com/linux/al2023/ug/crypto-policies-pq.html)) |
| .NET 9 STS (out of support since 2026-11-10) | Same | Same pattern as .NET 10 | Same | None | Same | Upgrade to .NET 10 | Unverified (same code path; not run). End of support [Documented](https://devblogs.microsoft.com/dotnet/dotnet-8-9-end-of-support/) |
| .NET 8 LTS (out of support since 2026-11-10) | Same | Lambda `dotnet8`: no. Image `8.0` (Debian 12): no. `8.0-alpine`: yes. AL2023: no | Same as client | None | Same | Upgrade to .NET 10. Until then: `8.0-alpine`, or AL2023 + `OPENSSL_CONF` | Tested (8.0.33, 8.0.34) |
| .NET 6 / 7 (out of support) | Same | Same as the OS OpenSSL | Same | None | Same | Upgrade | Unverified (not run) |
| .NET Framework 4.8 / 4.8.1 (Windows only) | Schannel | Only on Windows Server 2025 / Windows 11 24H2+ with the July 2026 update and `X25519_MLKEM768` enabled | Same (IIS, HTTP.sys) | None in .NET; Schannel curve order (machine-wide) | Legacy FIPS mode: no ML-KEM groups | Patch Windows and enable the group; don't set `ServicePointManager.SecurityProtocol` to `Tls12` | Schannel Documented ([Microsoft](https://learn.microsoft.com/en-us/windows/win32/secauthn/tls-supported-groups-in-windows-11-24h2-and-later)); .NET Framework picking it up not confirmed |
| Native AOT (`provided.al2023`) | Loads the system `libssl.so.3` | No | n/a | None | Same as AL2023 | `openssl-pq.cnf` + `OPENSSL_CONF` | Tested |

[MOVED: mttvddjsrgd.5503, mttvddjsrgd.5850, mttvddjsrgd.5866, mttvddjsrgd.7220, mttvddjsrgd.7313, mttvddjsrgd.8102]
<!-- The existing intro paragraph, "By compute type" table and "Container images" table move here unchanged. Delete heading mttvddjsrgd.5489. -->

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

[MOVED: mttvddjsrgd.8432, mttvddjsrgd.8553, mttvddjsrgd.9912]
<!-- Existing client intro, client library table and the HttpClient/gRPC excerpt move here. Delete heading mttvddjsrgd.8408. -->

### B. Simple server

- **Who this is:** Kestrel (`WebApplication`, `UseKestrel`) with the default HTTPS endpoint, or behind an ALB/NLB that terminates TLS.
- **What happens today:** Kestrel follows the image: PQ on `-alpine`, `-resolute`, AL2023 + `OPENSSL_CONF`; classical on `8.0`, `10.0`, Azure Linux. Tested (v1 and v2). Behind a load balancer the client-facing handshake is the listener policy's (see the Load balancers tab).
- **What to change:** the image or `OPENSSL_CONF`. Keep `SslProtocols` at `None` or include `Tls13`.
- **Side effects:** none; X25519-only clients still connect (Tested).

[MOVED: mttvddjsrgd.11415, mttvddjsrgd.12217, mttvddjsrgd.12290, mttvddjsrgd.12500]
<!-- Existing server table, Kestrel excerpt and the Tls12 note move here. Delete heading mttvddjsrgd.11403. -->

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
- **X509Store on Linux:** CurrentUser/My lives under `~/.dotnet/corefx/cryptography/x509stores/my/`; it must be persisted (volume or image layer) or re-imported at start. LocalMachine/My is not writable on Linux. Root/CA stores on Linux are a read-only view of the OpenSSL trust files ([discussion](https://github.com/dotnet/runtime/issues/32875)). Not a PQ issue.
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

[MOVED: mttvddjsrgd.10387, mttvddjsrgd.10703]
<!-- Existing Confluent.Kafka excerpt and the 2 bullets (Kafka on Alpine, macOS) move here. -->

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

[MOVED: mttvddjsrgd.12748, mttvddjsrgd.12814, mttvddjsrgd.12990]
<!-- Existing Windows heading paragraph, PowerShell excerpt and the 3 bullets (GPO, FIPS, .NET 8 on Windows) move here. -->

- **macOS developer machines:** Apple TLS; PQ needs .NET 10 with the Network.framework opt-in (see the bullet moved under H). Not tested.

## Solution and automation

1. **Inventory.** Per repo: base image tag (`grep -rn "^FROM" Dockerfile*`), target framework (`grep -rn "<TargetFramework" --include=*.csproj`), Lambda runtime (`Runtime: dotnet8` in SAM/CFN, `runtime = "dotnet8"` in Terraform), and the blockers in case F (`check-dotnet-pq.sh`). Per running container: `cat /etc/os-release; openssl version` (chiseled images: inspect the tag).
2. **Change, per compute type.**

[MOVED: mttvddjsrgd.13592, mttvddjsrgd.14726]
<!-- Existing 6-step packaging list and the pointer paragraph move here. Delete heading mttvddjsrgd.13565. -->

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

[MOVED: mttvddjsrgd.14921]
<!-- Existing Verify bullets move here as the reference list under the steps. Delete heading mttvddjsrgd.14914. -->

## Pitfalls and rollback

[MOVED: mttvddjsrgd.16426]
<!-- Existing 8 bullets move here unchanged. Delete heading mttvddjsrgd.16404 (replaced by this one). New bullets below are appended after them. -->

- **Debian 12 and Ubuntu 24.04 images hide the problem in tests that only use classical servers.** Every certificate and trust case passed classically there (Tested). Always test against a PQ-only server.
- **`CreateFromPemFile(caPath)` with one argument throws for a CA-only file.** Use `CreateFromPem(File.ReadAllText(path))` (Tested).
- **TLS 1.2-only Kestrel with an EC certificate** refused clients whose group list lacks P-256 (Tested, F3b). One more reason to allow TLS 1.3.
- **Kestrel `X509Store` certificates on Linux** live in the user's home directory; a read-only root filesystem or a new container loses them unless mounted or re-imported. Not PQ-related.
- **Alpine CA install** may need `apk add ca-certificates` before `update-ca-certificates`.
- **.NET 8 and 9 are out of support since 2026-11-10.** The PQ fix works on .NET 8, but plan the move to .NET 10 ([Microsoft](https://devblogs.microsoft.com/dotnet/dotnet-8-9-end-of-support/)).

## Full configuration files

[MOVED: mttvddjsrgd.17918 ... mttvddjsrgd.32650]
<!-- Every existing block from .17918 (intro paragraph) through .32650 (last Kafka code block) moves here unchanged, in order.
     Delete heading mttvddjsrgd.17893 (replaced by this one). The new files below are appended after them. -->

The files below were added in this pass (2026-11-14). The probes and scripts are test tools, not production code; the CI check and workflow are meant for production pipelines.

<!-- APPENDED FILES FOLLOW -->
