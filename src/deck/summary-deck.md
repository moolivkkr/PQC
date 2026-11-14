---
title: Post-quantum TLS across languages and infrastructure
subtitle: Detection and remediation summary, 2026-11-14
---

# The problem

## Why act now

- Traffic recorded today can be decrypted once a large quantum computer exists ("harvest now, decrypt later").
- The fix is the hybrid key exchange **X25519MLKEM768** in TLS 1.3. It changes only how the session key is agreed.
- **Certificates, keystores and CA bundles do not change** for PQ key exchange. ML-DSA certificates are a separate, later step.
- Whether a connection is PQ depends on the **client's TLS library** (language runtime and version), not on the compute type.
- Compute type decides how we **see** non-PQ connections and how the fix **ships**.

## How we find non-PQ connections

| Signal | Lambda / Fargate | Containers on EC2, EC2 | Front doors |
|---|---|---|---|
| AWS API calls | CloudTrail `tlsDetails.keyExchange` (KMS, STS, IAM, Secrets Manager, ACM) | Same | n/a |
| Other outbound | Posture only, or an egress sensor | Zeek on VPC Traffic Mirroring | n/a |
| Inbound | Front door logs | Front door logs, mirroring | ALB/NLB logs record key exchange |
| Posture | Runtime, package type, env vars | Image SBOM, OpenSSL/JDK/Go versions | Security policy names |

A TLS 1.2 connection is always non-PQ.

# Status by language

## Languages at a glance

| Language | PQ by default today | Fix |
|---|---|---|
| Go | 1.24+ with `go` line 1.24+ | Build with current Go; drop pinned `CurvePreferences` |
| Python | Debian 13 / Alpine images; not Lambda or AL2023 | `openssl-pq.cnf` + `OPENSSL_CONF`; upgrade 3.9–3.11 on Lambda |
| Node.js | Official 22.20+ / 24.5+ images; not on Lambda | `openssl-pq-node.cnf` on Lambda; upgrade 18 and 20 |
| Java | JDK 25.0.5+ | Bouncy Castle agent (kit v2) on 8–21, or move to 25.0.5+ |
| .NET | Alpine, Ubuntu 26.04 images; not Lambda or AL2023 | PQ base image or `openssl-pq.cnf`; Schannel opt-in on Windows |

## Existing certificates and keystores

| Language | Keystore / key files | Watch out for |
|---|---|---|
| Go | No change | `AWS_CA_BUNDLE` with a plain `http.Client`; `x/crypto/pkcs12` vs OpenSSL 3 files |
| Python | No change | gunicorn + encrypted key; `truststore` disables the Lambda shim |
| Node.js | No change | Legacy RC2/3DES PFX: re-export; empty CA store in Lambda image |
| Java | No change | EC server cert under Bouncy Castle needs `PKIX` key manager; hard-coded `SunX509` |
| .NET | No change | `CreateFromPemFile` on a CA-only file throws |

All cases tested with the PQ fix in place: own server certificate, private CA trust, mutual TLS.

## Java: the EC certificate fix

- **Symptom:** Bouncy Castle JSSE server with an EC (P-256) certificate failed every handshake.
- **Cause:** BC asks the key manager for `EC/secp256r1`; the JDK default `SunX509` key manager returns nothing.
- **Fix:** `ssl.KeyManagerFactory.algorithm=PKIX` (kit v2 sets it; `pq-tls.security` file).
- **Tested:** Tomcat 11, Jetty 12, HttpsServer on JDK 17 and 21; classical clients still connect.
- **Still breaks:** code or Tomcat config that hard-codes `SunX509` (CI check flags it).
- **Side effect:** RSA+EC stores now serve EC to default clients.

# Infrastructure

## Infrastructure at a glance

| Component | PQ path |
|---|---|
| ALB, NLB | `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`, later 1.3-only PQ |
| CloudFront | Viewer side PQ by default; origin leg classical |
| API Gateway REST | PQ policy; HTTP/WebSocket and egress have none |
| AWS endpoints | KMS, STS, Secrets Manager, ACM, IAM PQ now |
| Service mesh | Linkerd 2.19+ default; Istio 1.27+ `COMPLIANCE_POLICY=pqc` |
| Hosts | Debian 13 / Ubuntu 26.04 OpenSSL PQ; AL2023 `DEFAULT:PQ` |
| IoT Core | No PQ policy yet |

## Resolved risks

- **GnuTLS tools** (wget, git on Debian/Ubuntu): no ML-KEM in any Debian or Ubuntu GnuTLS yet; they fail against PQ-only servers. Use OpenSSL-linked tools. SSH is already PQ (OpenSSH 10).
- **Security Hub ELB.17** passes six non-PQ policies. Use the org Config rule `pq-tls-elbv2-listener-policy` with a PQ-only list, plus the SCP.
- **Kyverno 1.20** dropped legacy ClusterPolicy: admission checks are written as ValidatingPolicy (CEL).

# Rollout

## How the fix ships

1. **Classify:** posture inventory puts each workload in a matrix row.
2. **Change request:** a bot bumps the shared build template; it ships the pq-tls kit and sets the variable.
3. **Release:** the normal pipeline; guardrails warn, then fail, on missing PQ settings and non-PQ ELB policies.
4. **Verify:** observed signals (CloudTrail, ELB logs, sensors) confirm PQ; shipping is not proof.

Canary first; rollback is removing the variable or file in the next release.

## Open items

- Node.js 18/20 and Python 3.9–3.11 on Lambda: upgrade before AWS block-update dates.
- Lambda and Fargate outbound to non-AWS services: no AWS log shows the group.
- API Gateway egress, CloudFront origin leg, IoT Core: classical by AWS design; record as exceptions.
- IaC and guardrails not yet applied to an AWS account: validate in a sandbox, start in audit mode.
- Untested: Ruby, PHP, Rust, Windows Schannel, HSM/PKCS#11 keys.
