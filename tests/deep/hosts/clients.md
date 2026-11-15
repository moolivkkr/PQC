## What decides PQ here

Each client's own TLS stack decides what it offers: the OS stack on iOS, macOS and Windows; BoringSSL in Chrome; NSS in Firefox; OpenSSL, GnuTLS or LibreSSL in command-line tools; Go's `crypto/tls` in kubectl, helm and terraform. A client only gets PQ if the server also offers it, so most of these clients start using PQ against your estate only after the front doors (ALB, NLB, CloudFront, API Gateway) run a PQ policy (Load balancers and Edge tabs). Every client below still connects to classical servers.

## Status matrix

Tested = run here on 2026-11-14 against a PQ-only server (`openssl s_server -groups X25519MLKEM768 -tls1_3`, OpenSSL 3.5.7) and a classical-only server (`-groups X25519`). Every Tested client also reached the classical server. Scripts and output: `deep/hosts/run-hosts*.sh`, `run-hosts*.out`.

### Devices and browsers

| Client | PQ by default | Version that matters | Evidence |
| --- | --- | --- | --- |
| iOS / iPadOS apps on URLSession or Network.framework | Yes | iOS/iPadOS 26+ | Documented ([Apple Platform Security](https://support.apple.com/en-gb/guide/security/sec100a75d12/web), [Apple 122756](https://support.apple.com/en-gb/122756)) |
| macOS apps on URLSession / Network.framework, visionOS | Yes | macOS Tahoe 26+, visionOS 26+ | Documented (Apple 122756) |
| macOS `/usr/bin/curl`, `/usr/bin/python3` | **No** | macOS 27.0.1: curl 8.7.1 on LibreSSL 3.3.6; python3 on LibreSSL 2.8.3 | Tested (handshake failure on PQ-only) |
| Android apps in Chrome / WebView | Yes | Current Chrome / WebView | Claimed (Google posts summarised by press) |
| Android apps on platform TLS (HttpsURLConnection, OkHttp on the platform provider) | **Not confirmed** | Android 16/17: no documented platform default found | Searched 2026-11-14; none found |
| Android or JVM apps bundling Conscrypt | Yes from Conscrypt 2.6.1, per a maintainer | Conscrypt 2.6.1 (July 2026) | Claimed ([conscrypt#1500](https://github.com/google/conscrypt/issues/1500)) |
| Windows apps on Schannel (.NET Framework, WinHTTP, PowerShell `Invoke-WebRequest` on 5.1) | No: opt-in | Windows 11 24H2/25H2 KB5089573; Server 2025 KB5099536 | Documented ([Microsoft FAQ](https://techcommunity.microsoft.com/t5/post-quantum-crypto-tech-blog/windows-tls-1-3-and-post-quantum-crypto-faq/ba-p/4556389)) |
| Chrome (desktop, Android) | Yes | 131+; can't be turned off from 138 | Documented by AWS ([sdkref](https://docs.aws.amazon.com/sdkref/latest/guide/pqtls-details.html)); 138 change Claimed |
| Edge | Yes | 131+; enterprise opt-out removed from 147 | Claimed ([Cloudflare PQC support](https://developers.cloudflare.com/ssl/post-quantum-cryptography/pqc-support/)) |
| Firefox | Yes | Desktop 132+; Android 145+ | Documented by AWS (desktop 132); Android Claimed (Cloudflare) |
| Safari | Yes | Safari 26+ (iOS 26, macOS 26) | Documented (Apple 122756) |

### Command-line and developer tools

| Tool | Build tested | TLS library | PQ-only server | Evidence |
| --- | --- | --- | --- | --- |
| curl, Debian 13 | 8.14.1 | OpenSSL 3.5.7 | Pass (`X25519MLKEM768`) | Tested |
| curl, Ubuntu 26.04 | 8.18.0 | OpenSSL 3.5.5 | Pass | Tested |
| curl, Alpine 3.24 / `curlimages/curl` | 8.23.0 | OpenSSL 3.5.9 | Pass | Tested |
| curl, AL2023 (`curl-minimal`) | 8.21.0 | OpenSSL 3.5.8 | Fail at `DEFAULT`; pass at `DEFAULT:PQ` or with `OPENSSL_CONF` | Tested |
| curl, Debian 12 / Ubuntu 24.04 / Alpine 3.21 | 7.88.1 / 8.5.0 / 8.14.1 | OpenSSL 3.0 / 3.0 / 3.3 | Fail | Tested |
| curl, macOS system | 8.7.1 | LibreSSL 3.3.6 | Fail | Tested |
| GNU wget, Debian 13 / Ubuntu 26.04 | 1.25.0 | **GnuTLS 3.8.9 / 3.8.12** (no ML-KEM group) | **Fail** | Tested |
| GNU wget, Alpine 3.24 | 1.25.0 | OpenSSL 3.5.9 | Pass | Tested |
| GNU wget, AL2023 | 1.21.3 | GnuTLS 3.8.10 | Pass at `DEFAULT:PQ` | Tested |
| BusyBox wget, Alpine 3.24 | 1.37.0 | BusyBox `ssl_client` (library not checked) | Pass | Tested |
| git, Debian 13 | 2.47.3 | `libcurl-gnutls` | **Fail** (`GnuTLS, handshake failed`) | Tested |
| git, Alpine 3.24 | 2.54.1 | libcurl + OpenSSL 3.5 | Pass | Tested |
| AWS CLI v2 (`amazon/aws-cli`) | 2.40.3 | Bundled OpenSSL (≥ 3.5.6 from 2.34.54) | Pass | Tested; rule Documented |
| AWS CLI v1 on `python:3.13-slim` | 1.46.3 | OpenSSL 3.5.7 | Pass | Tested |
| AWS CLI v1 on `python:3.12-slim-bookworm` | 1.46.3 | OpenSSL 3.0.22 | Fail | Tested |
| kubectl (`alpine/k8s:1.34.1`) | 1.34.1, go1.24.6 | Go `crypto/tls` | Pass | Tested |
| helm (`alpine/helm`) | 4.3.2, go1.27.4 | Go | Pass | Tested |
| terraform (`hashicorp/terraform:latest`) | go1.26.10, no `tlsmlkem=0` in DefaultGODEBUG | Go | Not run live; PQ expected by the Go rule | Tested (`go version -m` only) |
| OpenSSH client | Debian 13 10.0p2, Ubuntu 26.04 10.2p1, Alpine 3.24 10.3p1, Alpine 3.21 9.9p2, macOS 10.3p1 | | ML-KEM negotiated (macOS: version only) | Tested |
| OpenSSH client | Ubuntu 24.04 9.6p1, Debian 12 9.2p1 | | sntrup761 only | Tested |
| JMeter, Gatling, other JVM tools | JVM | JSSE | Follows the JDK (Java tab: JDK 25.0.5 PQ by default) | Documented via Java tab |
| Python CLIs (requests, httpie), Node CLIs (npm) | | Runtime's TLS | Python and Node.js tabs | |
| Postman (desktop) | | Electron (Chromium + Node) | Not confirmed which stack its request engine uses | Unverified |

For Go tools, run `go version -m <binary>`: Go ≥ 1.24 and no `tlsmlkem=0` in `DefaultGODEBUG` means PQ is offered.

## Client side (app level)

### iOS, iPadOS, macOS apps

- Nothing to change for URLSession and Network.framework on 26+. The ClientHello carries X25519MLKEM768 plus a key share (Apple 122756).
- Apple says some legacy servers fail to read the larger ClientHello. It offers a temporary compatibility mode that "will not be available in a future version". Fix the server instead.
- Apps on their own TLS (BoringSSL, OpenSSL, Flutter's `dart:io`) follow that library. Not checked here.
- Apple doesn't give a public API that returns the negotiated group, as far as I found. Verify on the server side (ALB connection log `keyExchange`).

### Android apps

- Chrome and WebView traffic: PQ.
- For app traffic on the platform TLS provider, I found no documented Android 16 or 17 default. Treat it as classical until Google documents it.
- To control it in the app, bundle Conscrypt and install it as the first provider. OkHttp uses Conscrypt when it is the default provider. A Conscrypt maintainer says 2.6.1 offers X25519MLKEM768 by default (Claimed; not tested here).

```kotlin
// Application.onCreate() (excerpt)
Security.insertProviderAt(Conscrypt.newProvider(), 1)
```

### Windows clients

- Schannel apps: `Enable-TlsEccCurve -Name "X25519_MLKEM768" -Position 0` on Windows 11 24H2/25H2 with KB5089573. GPO overrides PowerShell. Full SSM document in the Hosts and OS tab.
- Browsers on Windows use their own stacks and are PQ already.
- PowerShell 7 runs on .NET; on Windows it uses Schannel, so the same setting applies (.NET tab).

### curl

- PQ by default when linked to OpenSSL ≥ 3.5 and the OS policy allows it. Check with `curl -V` (look for `OpenSSL/3.5`) and `curl -v`, which prints `SSL connection using TLSv1.3 / … / X25519MLKEM768`.
- To force the order or test a PQ-only server, `--curves X25519MLKEM768:X25519` (OpenSSL backend).
- macOS: the system curl can't do PQ; use a curl built on OpenSSL 3.5 (Homebrew, or a container).

### wget and git

- Debian and Ubuntu build wget and git (through `libcurl-gnutls`) on GnuTLS. Their GnuTLS (3.8.9 on Debian 13, 3.8.12 on Ubuntu 26.04) has no ML-KEM group, so these fail on PQ-only servers even where curl works.
- Use curl instead of wget in scripts, or use Alpine 3.24 or AL2023 (`DEFAULT:PQ`) images.
- For git in CI on Debian/Ubuntu images, I found no switch to an OpenSSL backend. Use an Alpine-based git image, or keep the git server's front door accepting classical.

### AWS CLI

- v2 on Linux: ≥ 2.34.54 (Documented); 2.40.3 Tested.
- v1: follows Python's OpenSSL (Tested both ways above).
- macOS: Homebrew install with Homebrew OpenSSL ≥ 3.5 (AWS doc). Windows: depends on the OS; not confirmed.
- Details: AWS service endpoints tab.

### kubectl, helm, terraform and other Go tools

- Released binaries built with Go ≥ 1.24 offer PQ (tested kubectl 1.34.1 and helm 4.3.2 live).
- Plugins and providers are separate binaries: terraform providers, kubectl plugins and credential helpers (`aws eks get-token` is the AWS CLI) each have their own TLS. Check each with `go version -m`.

### OpenSSH client

OpenSSH ≥ 10.0 is PQ by default; 9.9 supports ML-KEM; 9.0–9.8 only sntrup761. Config in the Hosts and OS tab.

## Server side

These clients benefit only if the server offers PQ:

| Front door | What to set | Tab |
| --- | --- | --- |
| ALB / NLB | `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09` | Load balancers |
| CloudFront (viewer) | Nothing: PQ by default | Edge and API front doors |
| API Gateway REST | `SecurityPolicy_TLS13_1_2_PQ_2025_09` | Edge and API front doors |
| nginx / Envoy / HAProxy on your hosts | OpenSSL 3.5 + groups | Web servers and proxies |
| sshd / SFTP | OpenSSH ≥ 9.9, or Transfer Family PQ policy | Hosts and OS; Edge |

Keep classical groups on public front doors: Debian/Ubuntu wget and git, macOS system curl, Android platform TLS, Windows Server 2019/2022 and older JDKs can't do PQ yet.

## Packaging

| Where | What to ship |
| --- | --- |
| CI runners and build images | A toolbox image on Alpine 3.24 (curl, wget, git, OpenSSH 10.3) plus the AWS CLI v2 and Go tools copied from their official images. Dockerfile below |
| Developer laptops (macOS) | Homebrew curl and OpenSSL ≥ 3.5; AWS CLI via Homebrew; OpenSSH 10.x is already in macOS 27 |
| Windows laptops / jump hosts | KB5089573 + Schannel group via Intune or GPO (Hosts and OS tab) |
| Mobile apps | iOS 26+ minimum for guaranteed PQ; Android: bundle Conscrypt ≥ 2.6.1 if PQ is required |

## Verify

1. **Posture:** `curl -V`, `ssh -V`, `aws --version`, `go version -m $(which kubectl)`, `ldd $(git --exec-path)/git-remote-https | grep -E 'gnutls|ssl'`.
2. **Live:** against a PQ-only test endpoint, `curl -sv https://pq-test/ 2>&1 | grep 'SSL connection using'` must show `X25519MLKEM768`; `ssh -v host 2>&1 | grep 'kex: algorithm'` must show `mlkem768x25519-sha256`; a classical endpoint must still work.
3. **Observed:** ALB connection logs and NLB access logs carry `keyExchange` per connection; group them by user agent to see which client families are still classical.

## Pitfalls

- curl and wget on the same Debian host differ (OpenSSL vs GnuTLS). So do curl and git.
- Upgrading macOS doesn't upgrade `/usr/bin/curl`'s LibreSSL.
- A PQ-only listener breaks every classical client in the matrix. Use PQ-only only on internal endpoints whose client list you control.
- Older middleboxes may drop the bigger ClientHello; Apple and AWS both warn about it.

## Full configuration files

**`ci/toolbox/Dockerfile`** (PQ-capable CI toolbox; every tool here passed the PQ-only test)

```dockerfile
# tested: helm 4.3.2 (alpine/helm:latest); pin by digest
FROM alpine/helm:latest AS helm
FROM alpine/k8s:1.34.1 AS k8s

FROM alpine:3.24
RUN apk add --no-cache curl wget git openssh-client openssl ca-certificates bash
COPY --from=k8s  /usr/bin/kubectl /usr/local/bin/kubectl
COPY --from=helm /usr/bin/helm    /usr/local/bin/helm
# AWS CLI v2 is built for glibc; run it from the amazon/aws-cli image as a separate step
# rather than copying it into Alpine.
RUN curl -V | grep -q 'OpenSSL/3\.[5-9]' && ssh -V 2>&1 | grep -q 'OpenSSH_1[0-9]'
```

Pin each FROM by digest in real use (the digests tested are in `run-hosts.out`).

**`~/.curlrc`** (pin the group order; optional, OpenSSL-backed curl only)

```text
curves = X25519MLKEM768:X25519:secp256r1
```

**`~/.ssh/config`** (OpenSSH ≥ 9.9 clients)

```text
Host *
    KexAlgorithms mlkem768x25519-sha256,sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org
```

**`app/src/main/java/com/example/App.kt`** (Android: bundle Conscrypt as the first provider)

```kotlin
package com.example

import android.app.Application
import java.security.Security
import org.conscrypt.Conscrypt

class App : Application() {
    override fun onCreate() {
        super.onCreate()
        // Conscrypt 2.6.1+ is reported to offer X25519MLKEM768 by default (not tested here).
        Security.insertProviderAt(Conscrypt.newProvider(), 1)
    }
}
```

**`app/build.gradle.kts`** (excerpt)

```kotlin
dependencies {
    implementation("org.conscrypt:conscrypt-android:2.6.1")
    implementation("com.squareup.okhttp3:okhttp:5.1.0")
}
```

The OkHttp version is an example; use your current one.

**`windows/Enable-PqTls.ps1`** (Windows 11 client, elevated)

```powershell
# Requires KB5089573 (Windows 11 24H2/25H2) or KB5099536 (Server 2025).
Enable-TlsEccCurve -Name "X25519_MLKEM768" -Position 0
Get-TlsEccCurve | Select-Object -First 5
```

**`ci/check-clients.sh`** (posture gate for a CI image)

```bash
#!/bin/sh
# Fails if a tool in this image can't offer X25519MLKEM768.
set -e
curl -V | head -1 | grep -q 'OpenSSL/3\.[5-9]' || { echo "curl not on OpenSSL >= 3.5"; exit 1; }
if command -v git >/dev/null; then
  ldd "$(git --exec-path)/git-remote-https" 2>/dev/null | grep -q gnutls && { echo "git uses GnuTLS (no ML-KEM)"; exit 1; }
fi
if command -v wget >/dev/null; then
  wget --version | grep -q -- '+ssl/gnutls' && { echo "wget uses GnuTLS (no ML-KEM)"; exit 1; }
fi
ssh -V 2>&1 | grep -Eq 'OpenSSH_(9\.9|1[0-9])' || { echo "OpenSSH < 9.9"; exit 1; }
echo "client posture OK"
```
