# Shared brief: deepen the PQC doc (read fully before starting)

## Goal
The Claude Docs document "PQC Detection and Remediation by Language and Compute"
(doc id `44a97a0f-a862-42b5-a154-764d72d41549`, URL https://claude.ai/artifact/9UmGyhf2tCn9V6s93RGx7S)
needs each tab expanded into a complete, practical runbook. Readers: platform, app and network
engineers in an AWS-only organisation who must (a) detect non-PQ TLS connections and (b) change
code/config/packaging to get hybrid post-quantum key exchange (X25519MLKEM768, TLS 1.3).
The user asked for: more depth on every tab, every hardware/device type, and the configuration
files needed on BOTH server side and client side (app level), per language and per component.

## Tab ownership (file id / body node id). Edit ONLY the tabs you own.
| Tab | file id | body node id |
|---|---|---|
| Main (owner: lead, do not edit) | 2b549c4f-a403 | 7f8f4a86-4d9c |
| Runbook by language (parent; lead) | 5dd6e4e1-9c38 | b5cf0064-6a9b |
| Go | f452a156-1a48 | c02d62b2-67e7 |
| Python | 35b45b8c-c6f8 | 610684f0-aa35 |
| Node.js | d69fae22-fa1f | d02c414f-ccd4 |
| Java | cd465386-557e | 4c9d8c6b-f4f3 |
| .NET | c09219a7-69d4 | 88a41389-c93f |
| Infrastructure and services (parent; lead) | c0e73cdc-fca7 | afc77a21-4a57 |
| Load balancers | bb21387b-4f66 | 143c638f-590a |
| Edge and API front doors | 6d11c1c8-dcc8 | d8fe2c64-7cf3 |
| AWS service endpoints | 5a29f676-6958 | 8868eb3f-63a6 |
| Network devices and egress | c2c97bfd-040d | 5bfb4cc4-ab9a |
| IoT | 27172d37-a5c2 | e86fe07a-cac9 |
| Service mesh | 569dd476-c063 | bda3ce4d-bf11 |
| Databases and data services | d9065243-9ab3 | 4939fb11-df6b |
| Hosts and OS | 99613846-4046 | c3d96e94-4f34 |
| Certificates (ML-DSA) | 38ead846-eb16 | c645e972-553d |
| WAF (new) | 37cfac3b-4ca1 | ea8fb0bb-ef44 |
| Web servers and proxies (new) | f7dff530-a0a0 | 10112461-0b3c |
| Mobile, desktop and CLI clients (new) | 89d3721c-f2a1 | 28091f56-7418 |
| Enforcement and guardrails (new) | 0803191b-9855 | ab9fe1da-cf13 |
| Configuration file index (lead) | f5950343-31dd | c238c638-bd7c |

Link to another tab with a mention chip `ref "file/<file id>"` (see the docs guide), e.g. the
Web servers tab for server-side nginx config instead of repeating it.

## Page template (every tab you own)
1. **What decides PQ here** – one short paragraph: whose TLS library/config controls the handshake.
2. **Status matrix** – versions/products × compute type (Lambda zip, Lambda image, Fargate/ECS/EKS, EC2) or
   × device type, with PQ yes/no and an evidence label.
3. **Client side (app level)** – per library/client: exact setting, short code or config excerpt.
4. **Server side** – per server/framework/product: exact setting, short config excerpt.
5. **Packaging per compute type** (where it applies) – Lambda zip layout + IaC env var; Lambda image
   Dockerfile; Fargate/ECS task definition / EKS pod spec + Dockerfile; EC2 systemd unit or SSM document.
   IaC: give Terraform AND CloudFormation (SAM where Lambda); CDK only where it adds something.
6. **Verify** – posture command, live test (PQ-only server must succeed; classical-only server must still work
   = fallback), observed signal (logs).
7. **Pitfalls and rollback.**
8. **Full configuration files** – last section of the tab: every file referenced above, complete, each
   in a code block preceded by its path/filename. The sections above show only excerpts.
Also include every relevant **device/hardware type** for infrastructure tabs (physical/virtual appliance,
SaaS, managed AWS service, MCU vs Linux-class device, etc.).

## Evidence labels (use exactly these, per row/claim)
- **Tested** – you ran it here (say what image/version). Keep the script + output under your work dir.
- **Documented** – vendor docs say so; add the source link.
- **Claimed** – third-party/blog/forum or vendor marketing, not docs; link it.
- **Unverified** – believed, not checked. Use sparingly; prefer to check.
Never present a config as working unless Tested or Documented. If unsure, say "I'm not sure" in the doc
wording ("not confirmed") rather than guessing. Verify date-sensitive claims with WebSearch (today is
2026-11-14). Research vendor products with WebSearch/WebFetch before stating anything about them.

## Already established (tested 2026-11-12/13; do not contradict without new evidence)
- Lambda python3.12/3.13/3.14 + dotnet8/10: PQ with `openssl-pq.cnf` + `OPENSSL_CONF` (AL2023 crypto policy
  otherwise omits ML-KEM). Lambda nodejs22/24: bootstrap sets `OPENSSL_CONF=/var/runtime/openssl_conf/openssl.cnf`
  (Groups without ML-KEM); override with `openssl-pq-node.cnf`. nodejs18/20: no fix, upgrade.
- python3.9–3.11 Lambda (AL2, OpenSSL 1.1.1): sitecustomize shim routes urllib3+botocore through pyOpenSSL
  (cryptography 50.x bundles OpenSSL with ML-KEM); raw ssl/http.client/aiohttp/httpx not covered.
- Java 8–21: Bouncy Castle 1.87 JSSE agent (`-javaagent`), Java 8 also `-Djdk.tls.client.protocols=TLSv1.3,TLSv1.2`.
  Corretto/Temurin 25.0.5: PQ by default; 21.0.13: not.
- Go: 1.24+ toolchain AND go.mod `go` ≥ 1.24, else `GODEBUG=tlsmlkem=1`; `go version -m` shows `tlsmlkem=0`
  in DefaultGODEBUG when classical. `CurvePreferences` set explicitly → no PQ.
- Containers: Debian 13 trixie (OpenSSL 3.5.x) and Alpine 3.24 (3.5.x) PQ by default; Debian 12, Ubuntu 24.04,
  Azure Linux 3.0 not; AL2023 needs `DEFAULT:PQ` or the conf. node:22/24 official images PQ. .NET alpine PQ.
- The kit files live in `/private/tmp/claude-501/-Users-kishoremooli-development-cybersecurity/21fa377a-bc06-46f9-9e49-4588545ba6c2/scratchpad/lambda-pq/`
  (`layer/pq-tls/openssl-pq.cnf`, `openssl-pq-node.cnf`, `wrapper`, `pyshim/sitecustomize.py`; java agent in
  `fn/java-bundled/pq-tls/`; probes `goprobe/`, `dotnet/`; scripts `run-*.sh`). Reuse them; read, don't modify.
- AWS facts: endpoints enforce PQ transparently when the client offers ML-KEM (KMS, Secrets Manager, STS, IAM,
  ACM, S3, DynamoDB non-FIPS); SQS/SNS/EventBridge/ECR control plane only; SSM, Lambda, ECS, EKS, CloudWatch,
  IoT Core, VPN not listed. CloudTrail `tlsDetails.keyExchange` only for KMS, STS, IAM, Secrets Manager, ACM,
  Payment Cryptography. ELB PQ policies `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`, `-TLS13-1-3-PQ-2025-09`
  (+FIPS); SCP key `elasticloadbalancing:SecurityPolicy`. API GW REST `SecurityPolicy_TLS13_1_2_PQ_2025_09`;
  API GW egress TLS 1.2 only; CloudFront viewer PQ by default, origin leg classical. Linkerd 2.19 PQ default;
  Istio 1.27 `COMPLIANCE_POLICY=pqc`. RDS PG18 `ssl_groups`; RDS MySQL 8.4.11; Aurora MySQL 3.14.0.

## Testing rules (hard rules from the user)
- Docker: `export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"` first.
- Label EVERY container/network you create `--label run=pqc-deep-<yourgroup>`; at the end remove only
  containers/networks with your own label. Never remove anything else, never prune.
- Pull images from registries, then run them by digest (`docker image inspect --format '{{index .RepoDigests 0}}'`).
  Installing packages INSIDE containers (apt, apk, dnf, pip, npm, maven, go mod, nuget) is fine.
  NEVER install anything on the host (no brew, no host pip/npm). No `sudo`.
- No network calls except container registries, package mirrors, vendor documentation and web search.
  No AWS API calls (there are no credentials). Don't publish ports unless needed; if you must, use host
  ports ≥ 18500. Prefer a user-defined docker network between test containers.
- macOS has no `timeout`; use `perl -e 'alarm shift; exec @ARGV' 120 <cmd>`.
- Keep ≤ 3 of your containers running at once (other agents share the machine).
- Test harness: a PQ-only TLS server = `openssl s_server -groups X25519MLKEM768 -tls1_3 ...` and a
  classical-only server = `-groups X25519`, from an OpenSSL 3.5 image (debian:trixie-slim has `openssl` 3.5.x).
  To test a SERVER config: `openssl s_client -groups X25519MLKEM768 -tls1_3` must connect, and a classical
  client must still connect (unless the point is 1.3/PQ-only enforcement). `s_client` prints
  "Negotiated TLS1.3 group: X25519MLKEM768" (or check `-brief`).
- Work dir: `/private/tmp/claude-501/-Users-kishoremooli-development-cybersecurity/21fa377a-bc06-46f9-9e49-4588545ba6c2/scratchpad/deep/<yourgroup>/`
  Put scripts, outputs, and the final markdown of each tab (`<tab>.md`) there BEFORE writing to the doc.
- Write files with the Write tool, not shell heredocs, for anything non-trivial.

## Writing to the doc
- Load `mcp__claude_ai_Claude_Docs__guide` with items `["topic.index","topic.editing"]` first and follow it.
  Tools: `mcp__claude_ai_Claude_Docs__read`, `update`, `batch` (load `read` via ToolSearch if needed).
- Container for every call: `{"kind":"project","id":"44a97a0f-a862-42b5-a154-764d72d41549"}`.
- Rewrite your tab in place: read the tab body (view), keep the H1 title block, plant pending blocks for your
  sections after it, fill ONE section per update call (replace the pending id with `## Heading` + body),
  then delete the old body blocks (ids from your first read, guarded with `ifRev`). If a delete is refused
  because a comment hangs on it, leave that block and report it.
- Writing style: plain English, short sentences, tables for comparisons, code blocks for config. No hype.
  Keep existing correct content; extend it. Don't repeat another tab's material: link to it.
- If the Claude Docs tools are not available to you, stop after writing `<tab>.md` files and say so.

## Hand-back (≤ 2,000 characters)
Tabs updated (yes/no each), tests run with pass/fail counts, anything left Unverified or contradicting the
"already established" list, containers cleaned (count), and any risk the lead must check.
