## What decides PQ here

The host OS decides PQ only for programs that use the system TLS library: OpenSSL, GnuTLS or NSS on Linux, Schannel on Windows, Apple's stack on macOS. On Red Hat-family systems (AL2023, RHEL) the system-wide crypto policy writes the group list for all three Linux libraries and for OpenSSH. Programs that bring their own TLS (Go, Java, the official Node.js binaries, rustls, AWS CLI v2) follow the language tabs whatever the host is.

## Status matrix

Tested = run here on 2026-11-14 in containers against a PQ-only `openssl s_server` (`-groups X25519MLKEM768 -tls1_3`) and a classical-only one (`-groups X25519`), plus sshd with `KexAlgorithms` restricted to one algorithm. Scripts and output: `deep/hosts/run-hosts*.sh`, `run-hosts*.out`.

| OS | System TLS (OpenSSL / GnuTLS) | PQ TLS by default | OpenSSH | PQ SSH by default | Evidence |
| --- | --- | --- | --- | --- | --- |
| Amazon Linux 2023.12 (image 2023.12.20261102) | OpenSSL 3.5.8, GnuTLS 3.8.10 | **No**; yes after `DEFAULT:PQ` (OpenSSL, GnuTLS, OpenSSH all switch) | 9.9p1 | No; `mlkem768x25519-sha256` first after `DEFAULT:PQ` | Tested; [AWS doc](https://docs.aws.amazon.com/linux/al2023/ug/crypto-policies-pq.html) |
| Amazon Linux 2027 (preview) | OpenSSL 3.5 | Yes; opt out with `DEFAULT:NO-PQ` | PQ by default | Yes | Documented; preview, not for production |
| Amazon Linux 2 | OpenSSL 1.0.2 / 1.1.1 | No, no fix | 7.x (no ML-KEM) | No | Tested (Lambda AL2 images). End of support was **2026-06-30** ([AL2 FAQ](https://aws.amazon.com/amazon-linux-2/faqs/)) |
| Bottlerocket (ECS/EKS nodes) | Not confirmed | Not applicable to workloads | Admin container only | n/a | See Bottlerocket below |
| RHEL 10.1+ | OpenSSL 3.5, GnuTLS, NSS | **Yes** (DEFAULT changed) | PQ by default | Yes | Documented ([Red Hat](https://www.redhat.com/en/blog/whats-new-post-quantum-cryptography-rhel-101)) |
| RHEL 10.0 | OpenSSL 3.5 | No; tech preview `DEFAULT:TEST-PQ` | | | Documented |
| RHEL 9.7 | OpenSSL 3.5 | No; `DEFAULT:PQ` (OpenSSL, NSS) | | | Documented ([Red Hat PQC](https://access.redhat.com/security/pqc/rhel)) |
| Ubuntu 26.04.1 LTS | OpenSSL 3.5.5; GnuTLS 3.8.12 **without** ML-KEM | Yes for OpenSSL programs; **no** for GnuTLS programs (wget, git) | 10.2p1 | Yes (`mlkem768x25519-sha256`) | Tested |
| Ubuntu 24.04.5 LTS | OpenSSL 3.0.13 | No | 9.6p1 | `sntrup761x25519-sha512@openssh.com` only | Tested |
| Debian 13 (trixie) | OpenSSL 3.5.7; GnuTLS 3.8.9 **without** ML-KEM | Yes for OpenSSL; no for GnuTLS | 10.0p2 | Yes | Tested |
| Debian 12 (bookworm) | OpenSSL 3.0.22 | No | 9.2p1 | sntrup761 only | Tested |
| Alpine 3.24 | OpenSSL 3.5.9 | Yes | 10.3p1 | Yes | Tested |
| Alpine 3.21 | OpenSSL 3.3.7 | No | 9.9p2 | Yes | Tested |
| Windows Server 2025 | Schannel | No: opt-in after KB5099536 (2026-07-14) | OpenSSH for Windows: not checked | Not confirmed | Documented ([Microsoft FAQ](https://techcommunity.microsoft.com/t5/post-quantum-crypto-tech-blog/windows-tls-1-3-and-post-quantum-crypto-faq/ba-p/4556389)) |
| Windows 11 24H2/25H2 (build agents, jump hosts) | Schannel | No: opt-in after KB5089573 | | | Documented (same FAQ) |
| Windows Server 2022, 2019 | Schannel | **No PQ update announced** | | | Microsoft's FAQ names only Server 2025 and Windows 11 |
| macOS 27.0.1 build agent | `/usr/bin/curl` LibreSSL 3.3.6; URLSession | curl: **No**; URLSession: yes (macOS 26+) | 10.3p1 | Yes (OpenSSH ≥ 10.0 default) | Tested (curl, `ssh -V`); URLSession Documented ([Apple](https://support.apple.com/en-gb/122756)) |

### By compute type

| Compute | Who owns the host OS | What you change |
| --- | --- | --- |
| EC2 (AL2023, RHEL, Ubuntu, Windows) | You | Crypto policy / Schannel group via SSM; OpenSSH config |
| ECS/EKS on EC2, AL2023 ECS- or EKS-optimized AMI | You | Same as EC2. Containers still use their own image's TLS |
| ECS/EKS on Bottlerocket | You pick the version; no shell or policy tooling | Nothing on the host; fix the container images |
| Fargate | AWS | Nothing on the host; fix the container images |
| Lambda | AWS | Language tabs (`OPENSSL_CONF`) |

### Bottlerocket

Bottlerocket has no package manager and no crypto-policies tool, and I couldn't confirm which OpenSSL version its core kit ships (searched release notes 2026-11-14). That matters little in practice:

- Workload TLS comes from the container image, not the host.
- Host agents (containerd, kubelet, ecs-agent, the SSM agent in the control container) are Go programs; current Go builds offer X25519MLKEM768 by default. Not confirmed per Bottlerocket version.
- The admin and control containers can't be retuned in a supported way. Treat any TLS they make as unknown; Documented status needs a Bottlerocket statement.

Not testable here (needs a Bottlerocket VM).

## Client side (app level on the host)

| Program on the host | TLS library | How to get PQ | Evidence |
| --- | --- | --- | --- |
| curl, Python `ssl`, Ruby, PHP, .NET (Linux), wget on AL2023 | OpenSSL | AL2023: `DEFAULT:PQ`, or per service `OPENSSL_CONF`; Debian 13 / Ubuntu 26.04 / Alpine 3.24: nothing | Tested |
| wget and git on Debian/Ubuntu | GnuTLS (wget links GnuTLS; git uses `libcurl-gnutls`) | **No fix on Debian 13 or Ubuntu 26.04**: their GnuTLS has no ML-KEM group. Use curl, or Alpine/AL2023 builds | Tested: handshake failure on PQ-only |
| GnuTLS programs on AL2023 | GnuTLS 3.8.10 | `DEFAULT:PQ` (negotiated `HYBRID-X25519-MLKEM768`) | Tested |
| NSS programs (Firefox ESR, some LDAP tools) | NSS 3.112 on AL2023 | `DEFAULT:PQ` | Documented (AWS doc) |
| OpenSSH client | OpenSSH | ≥ 9.9 for ML-KEM; AL2023 needs `DEFAULT:PQ` | Tested |
| Windows apps on Schannel (.NET Framework, PowerShell, IIS client calls) | Schannel | `Enable-TlsEccCurve -Name X25519_MLKEM768 -Position 0` | Documented |
| macOS command-line curl | LibreSSL 3.3.6 | Use a curl linked to OpenSSL 3.5 (Homebrew or a container) | Tested (fails on PQ-only) |

### Per-service override with systemd

On AL2023, to change one service and not the whole host, point that unit at the PQ config. Tested equivalent: with the policy at `DEFAULT`, curl run with `OPENSSL_CONF=/tmp/openssl-pq.cnf` negotiated X25519MLKEM768 and still reached the classical server.

```ini
# /etc/systemd/system/myapp.service.d/pq-tls.conf (excerpt)
[Service]
Environment=OPENSSL_CONF=/etc/pki/tls/openssl-pq.cnf
```

Then `systemctl daemon-reload && systemctl restart myapp`. Only OpenSSL-linked programs read this variable.

### OpenSSH client

OpenSSH ≥ 10.0 puts `mlkem768x25519-sha256` first by default ([OpenSSH PQ](https://www.openssh.com/pq.html)); nothing to set. For 9.9 hosts, or to pin the order:

```text
# ~/.ssh/config or /etc/ssh/ssh_config.d/40-pq-kex.conf (excerpt)
Host *
    KexAlgorithms mlkem768x25519-sha256,sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org
```

OpenSSH before 9.9 rejects the unknown name and exits; use `sntrup761x25519-sha512@openssh.com` first on 9.0–9.8 (Ubuntu 24.04, Debian 12). sntrup761 is not a NIST algorithm; use it as an interim step only.

## Server side

### Amazon Linux 2023: crypto policy

1. Patch to AL2023.12 or later.
2. `dnf -y install crypto-policies-scripts && dnf -y update crypto-policies crypto-policies-scripts`.
3. `update-crypto-policies --set DEFAULT:PQ` (`FIPS:PQ` on FIPS hosts).
4. Restart services, or reboot. Already-running processes keep the old list.

**Tested** on AL2023.12.20261102. With `DEFAULT`, OpenSSL's Groups line is `*X25519:secp256r1:…` and both curl and `s_client` fail on the PQ-only server. With `DEFAULT:PQ` it becomes `*?X25519MLKEM768:?x25519_mlkem768:?SecP256r1MLKEM768:…/*X25519:…`, curl reports `X25519MLKEM768`, the classical server still works, `sshd -T` and the client list `mlkem768x25519-sha256` first, and GnuTLS offers `GROUP-X25519-MLKEM768` first.

`DEFAULT:PQ` also enables ML-DSA signatures and P-256/P-384 ML-KEM hybrids. If you want the smallest change, use a custom subpolicy that adds only the X25519 hybrid group:

```text
# /etc/crypto-policies/policies/modules/PQ-HYBRID.pmod
group = +X25519-MLKEM768
```

Tested: with this module OpenSSL's Groups line became `*?X25519MLKEM768:?x25519_mlkem768/*X25519:…` and curl negotiated X25519MLKEM768. Apply with `update-crypto-policies --set DEFAULT:PQ-HYBRID`.

### OpenSSH server

| Host | What to do | Evidence |
| --- | --- | --- |
| AL2023 | `DEFAULT:PQ` (crypto policy writes `opensshserver.config`) | Tested (`sshd -T`) |
| Debian 13, Ubuntu 26.04, Alpine 3.24, RHEL 10.1 | Nothing: OpenSSH 10.x default prefers ML-KEM | Documented; client side Tested |
| Ubuntu 24.04, Debian 12 | Upgrade the OS; sntrup761 meanwhile | Tested |

To restrict a server to PQ only (a bastion, or an SFTP endpoint for PQ clients):

```text
# /etc/ssh/sshd_config.d/40-pq-kex.conf (excerpt; not on AL2023, where the policy owns this)
KexAlgorithms mlkem768x25519-sha256,sntrup761x25519-sha512@openssh.com
```

Tested on Debian 13 sshd with `-o KexAlgorithms=mlkem768x25519-sha256`: OpenSSH 9.9+ clients connected with ML-KEM; Ubuntu 24.04, Debian 12 and AL2023-at-`DEFAULT` clients failed with `no matching key exchange method found`.

### Session Manager and EC2 Instance Connect

- **Session Manager** does not use sshd; the SSM agent opens a TLS WebSocket to `ssmmessages`. The agent is Go 1.26 (offers PQ) but that endpoint isn't on AWS's PQ list. Assume classical (AWS service endpoints tab).
- **EC2 Instance Connect** pushes a key through a PQ-capable API, then you SSH to the instance's sshd: the sshd rules above apply.

### Web servers and other daemons on the host

nginx, Apache httpd, HAProxy and Postfix linked to the system OpenSSL follow the crypto policy unless their config sets groups. Server config is in the Web servers and proxies tab.

### Windows Server 2025 (Schannel)

1. Install KB5099536 (2026-07-14) or later.
2. `Enable-TlsEccCurve -Name "X25519_MLKEM768" -Position 0` (elevated). Position 0 is required for it to be negotiated, per Microsoft.
3. TLS 1.3 must be on. Group Policy overrides the PowerShell setting, so pick one ("don't mix-n-match", Microsoft).
4. Restart services that hold TLS contexts. Whether a reboot is needed isn't stated; not confirmed.

Windows Server 2022 and 2019 have no announced PQ Schannel. For PQ on those hosts, terminate TLS in front (ALB/NLB with a PQ policy) or move to 2025.

## Packaging and rollout per compute type

| Compute | Mechanism | Files (last section) |
| --- | --- | --- |
| EC2 Linux fleet | SSM State Manager association with a Command document, targeted by tag in waves | `PQ-SetCryptoPolicy.json`, `pq-policy.tf`, `pq-policy.yaml` |
| New AMIs | EC2 Image Builder component or user data running the same script | `user-data-pq.sh` |
| Single services | systemd drop-in with `OPENSSL_CONF` | `pq-tls.conf`, `openssl-pq.cnf` |
| EC2 Windows | SSM Run Command / association with `PQ-WindowsSchannel.json` | |
| ECS/EKS nodes (AL2023 AMI) | Same association, targeted by node-group tag | |
| Bottlerocket, Fargate | Nothing on the host | Fix images (language tabs) |

## Verify

1. **Posture (SSM Run Command or Inventory):** `update-crypto-policies --show` = `DEFAULT:PQ`; `grep Groups /etc/crypto-policies/back-ends/opensslcnf.config` starts with `*?X25519MLKEM768`; `sshd -T | grep ^kexalgorithms` starts with `mlkem768x25519-sha256`; `rpm -q openssl-libs openssh-server` (≥ 3.5, ≥ 9.9). Windows: `Get-TlsEccCurve` lists `X25519_MLKEM768` first.
2. **Live:** from the host, `openssl s_client -connect pq-test:443 -brief` (no `-groups`, so the policy is what's tested) must print `Negotiated TLS1.3 group: X25519MLKEM768`; a classical server must still connect. `ssh -v` must print `kex: algorithm: mlkem768x25519-sha256`.
3. **Observed:** CloudTrail `tlsDetails.keyExchange` for the host's AWS calls (if made by a system-OpenSSL client); Zeek on VPC Traffic Mirroring for other host traffic; ALB connection logs for calls to your ALBs.

## Pitfalls and rollback

- `DEFAULT:PQ` changes every OpenSSL, GnuTLS, NSS and OpenSSH program at once, including dnf, the SSM agent's helpers, and monitoring agents. Roll out in waves by tag.
- **Rollback:** `update-crypto-policies --set DEFAULT` then restart. Tested: the PQ-only server failed again right after rollback.
- **Debian/Ubuntu GnuTLS programs stay classical** even on Debian 13 and Ubuntu 26.04 (Tested). Don't assume `wget` or `git` follow `curl`.
- **OpenSSH config:** putting `mlkem768x25519-sha256` in `ssh_config` on OpenSSH < 9.9 breaks every ssh call. Gate by version.
- **Middleboxes:** the larger ClientHello can be dropped by old inspection devices. Test each fleet's egress path before the wave.
- **AL2 hosts** can't be fixed. They're past end of support; migrate to AL2023.

## Full configuration files

**`ssm/PQ-SetCryptoPolicy.json`** (SSM Command document, AL2023 and RHEL 9.7+)

```json
{
  "schemaVersion": "2.2",
  "description": "Set the system-wide crypto policy (PQ rollout or rollback) and report the result.",
  "parameters": {
    "Policy": {
      "type": "String",
      "default": "DEFAULT:PQ",
      "allowedValues": ["DEFAULT:PQ", "FIPS:PQ", "DEFAULT:PQ-HYBRID", "DEFAULT", "FIPS"]
    },
    "RestartUnits": {
      "type": "String",
      "default": "sshd",
      "description": "Space-separated systemd units to restart after the change"
    }
  },
  "mainSteps": [
    {
      "action": "aws:runShellScript",
      "name": "setCryptoPolicy",
      "precondition": { "StringEquals": ["platformType", "Linux"] },
      "inputs": {
        "timeoutSeconds": "600",
        "runCommand": [
          "set -eu",
          "command -v dnf >/dev/null || { echo 'not a dnf-based host'; exit 0; }",
          "dnf -y -q install crypto-policies-scripts",
          "dnf -y -q update crypto-policies crypto-policies-scripts",
          "if [ '{{ Policy }}' = 'DEFAULT:PQ-HYBRID' ]; then printf 'group = +X25519-MLKEM768\\n' > /etc/crypto-policies/policies/modules/PQ-HYBRID.pmod; fi",
          "current=$(update-crypto-policies --show)",
          "if [ \"$current\" != '{{ Policy }}' ]; then update-crypto-policies --set '{{ Policy }}'; for u in {{ RestartUnits }}; do systemctl try-restart \"$u\" || true; done; fi",
          "echo \"policy=$(update-crypto-policies --show)\"",
          "grep -m1 -i '^Groups' /etc/crypto-policies/back-ends/opensslcnf.config || true",
          "sshd -T 2>/dev/null | grep -i '^kexalgorithms' | cut -c1-120 || true",
          "rpm -q openssl-libs openssh-server || true"
        ]
      }
    }
  ]
}
```

**`ssm/pq-policy.tf`** (Terraform: document plus a wave association and a rollback association)

```hcl
resource "aws_ssm_document" "pq_policy" {
  name            = "PQ-SetCryptoPolicy"
  document_type   = "Command"
  document_format = "JSON"
  content         = file("${path.module}/PQ-SetCryptoPolicy.json")
}

resource "aws_ssm_association" "pq_wave" {
  name             = aws_ssm_document.pq_policy.name
  association_name = "pq-crypto-policy-wave1"
  schedule_expression = "rate(1 day)"
  max_concurrency  = "10%"
  max_errors       = "5%"
  parameters = {
    Policy       = "DEFAULT:PQ"
    RestartUnits = "sshd"
  }
  targets {
    key    = "tag:PQRollout"
    values = ["wave1"]
  }
}

resource "aws_ssm_association" "pq_rollback" {
  name             = aws_ssm_document.pq_policy.name
  association_name = "pq-crypto-policy-rollback"
  max_concurrency  = "25%"
  max_errors       = "10%"
  parameters = {
    Policy       = "DEFAULT"
    RestartUnits = "sshd"
  }
  targets {
    key    = "tag:PQRollout"
    values = ["rollback"]
  }
}
```

**`ssm/pq-policy.yaml`** (CloudFormation equivalent)

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Resources:
  PqPolicyDoc:
    Type: AWS::SSM::Document
    Properties:
      Name: PQ-SetCryptoPolicy
      DocumentType: Command
      DocumentFormat: YAML
      Content:
        schemaVersion: "2.2"
        description: Set the system-wide crypto policy and report the result.
        parameters:
          Policy:
            type: String
            default: DEFAULT:PQ
            allowedValues: [DEFAULT:PQ, FIPS:PQ, DEFAULT:PQ-HYBRID, DEFAULT, FIPS]
          RestartUnits:
            type: String
            default: sshd
        mainSteps:
          - action: aws:runShellScript
            name: setCryptoPolicy
            precondition: { StringEquals: [platformType, Linux] }
            inputs:
              timeoutSeconds: "600"
              runCommand:
                - set -eu
                - dnf -y -q install crypto-policies-scripts
                - dnf -y -q update crypto-policies crypto-policies-scripts
                - "if [ '{{ Policy }}' = 'DEFAULT:PQ-HYBRID' ]; then printf 'group = +X25519-MLKEM768\\n' > /etc/crypto-policies/policies/modules/PQ-HYBRID.pmod; fi"
                - "current=$(update-crypto-policies --show); if [ \"$current\" != '{{ Policy }}' ]; then update-crypto-policies --set '{{ Policy }}'; for u in {{ RestartUnits }}; do systemctl try-restart \"$u\" || true; done; fi"
                - echo "policy=$(update-crypto-policies --show)"
                - grep -m1 -i '^Groups' /etc/crypto-policies/back-ends/opensslcnf.config || true
  PqWave1:
    Type: AWS::SSM::Association
    Properties:
      Name: !Ref PqPolicyDoc
      AssociationName: pq-crypto-policy-wave1
      ScheduleExpression: rate(1 day)
      MaxConcurrency: "10%"
      MaxErrors: "5%"
      Parameters:
        Policy: [DEFAULT:PQ]
        RestartUnits: [sshd]
      Targets:
        - Key: tag:PQRollout
          Values: [wave1]
  PqRollback:
    Type: AWS::SSM::Association
    Properties:
      Name: !Ref PqPolicyDoc
      AssociationName: pq-crypto-policy-rollback
      MaxConcurrency: "25%"
      MaxErrors: "10%"
      Parameters:
        Policy: [DEFAULT]
        RestartUnits: [sshd]
      Targets:
        - Key: tag:PQRollout
          Values: [rollback]
```

Rollback = retag the instances `PQRollout=rollback`; the rollback association sets `DEFAULT` and restarts the units.

**`/etc/crypto-policies/policies/modules/PQ-HYBRID.pmod`**

```text
# Custom subpolicy: add the X25519+ML-KEM-768 hybrid group first for TLS and SSH,
# leave every other algorithm as the base policy has it.
# Apply: update-crypto-policies --set DEFAULT:PQ-HYBRID
group = +X25519-MLKEM768
```

**`user-data-pq.sh`** (EC2 user data or Image Builder step for AL2023 AMIs)

```bash
#!/bin/bash
set -euo pipefail
dnf -y -q install crypto-policies-scripts
dnf -y -q update crypto-policies crypto-policies-scripts openssl openssh-server
update-crypto-policies --set DEFAULT:PQ
update-crypto-policies --show
```

**`/etc/pki/tls/openssl-pq.cnf`** (per-service override; same file as the Lambda kit)

```ini
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

**`/etc/systemd/system/myapp.service.d/pq-tls.conf`**

```ini
[Service]
Environment=OPENSSL_CONF=/etc/pki/tls/openssl-pq.cnf
```

**`/etc/ssh/sshd_config.d/40-pq-kex.conf`** (Debian/Ubuntu/Alpine servers that must refuse classical SSH; leave out on AL2023/RHEL)

```text
KexAlgorithms mlkem768x25519-sha256,sntrup761x25519-sha512@openssh.com
```

**`/etc/ssh/ssh_config.d/40-pq-kex.conf`** (clients with OpenSSH ≥ 9.9)

```text
Host *
    KexAlgorithms mlkem768x25519-sha256,sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org
```

**`ssm/PQ-WindowsSchannel.json`** (SSM Command document, Windows Server 2025 / Windows 11)

```json
{
  "schemaVersion": "2.2",
  "description": "Enable or disable the X25519_MLKEM768 TLS group in Schannel and report the curve order.",
  "parameters": {
    "Action": { "type": "String", "default": "Enable", "allowedValues": ["Enable", "Disable", "Report"] }
  },
  "mainSteps": [
    {
      "action": "aws:runPowerShellScript",
      "name": "schannelPq",
      "precondition": { "StringEquals": ["platformType", "Windows"] },
      "inputs": {
        "timeoutSeconds": "300",
        "runCommand": [
          "$ErrorActionPreference = 'Stop'",
          "$build = [System.Environment]::OSVersion.Version; Write-Output \"OS build: $build\"",
          "if ('{{ Action }}' -eq 'Enable')  { Enable-TlsEccCurve -Name 'X25519_MLKEM768' -Position 0 }",
          "if ('{{ Action }}' -eq 'Disable') { Disable-TlsEccCurve -Name 'X25519_MLKEM768' }",
          "Get-TlsEccCurve | Select-Object -First 5"
        ]
      }
    }
  ]
}
```

Run it on hosts that are not under a Group Policy that sets the curve order; GPO wins over this setting.
