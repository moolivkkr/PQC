# Brief v2: restructure the language tabs (read BRIEF.md first, then this)

Read `/private/tmp/claude-501/-Users-kishoremooli-development-cybersecurity/21fa377a-bc06-46f9-9e49-4588545ba6c2/scratchpad/deep/BRIEF.md` in full. Its rules still apply: tab ids, evidence labels, testing rules, docker rules, the doc-writing rules and the hand-back format. This file changes two things: the page structure and the list of cases each tab must cover.

## User's request (2026-11-14)
"Update the language-based documentation for all cases: simple cases, existing certs with custom keystores, and anything else missing, across all languages. For each language:
- problem statement
- language versions, what each version supports natively, and the proposed solution
- detailed solutioning and steps for automation
- steps to test."

Readers are application teams. Most of them already run services with their own certificates, keystores, CA bundles and TLS settings. Each team must be able to find its own situation and see exactly what to change, or that nothing needs to change.

## New page structure (replaces the 8-section template for language tabs)
Keep the H1 title block. Then use these sections, in this order:

1. `## Problem statement`
   - A short paragraph: what goes wrong today and why, in this language.
   - Say who controls the handshake: the runtime, the TLS library or the OS.
   - Say what the risk is: harvest-now-decrypt-later on classical key exchange.
2. `## Versions and native support`
   - One table with a row per runtime version line, including EOL lines still in use. Columns:
     - Version
     - TLS stack
     - PQ client by default? (per compute type where it differs: Lambda, container image, EC2 or AL2023)
     - PQ server by default?
     - API to set groups
     - FIPS-mode behaviour
     - Proposed solution for that version
     - Evidence label
   - Follow it with a short "decision guide": a few bullets saying if X then do Y.
3. `## Cases: what to change`
   Use one `###` per case, in this order. Each case says:
   - **Who this is**: how a team recognises itself, with a grep or command where possible.
   - **What happens today**: with an evidence label.
   - **What to change**: exact code or config excerpt, or "nothing".
   - **Side effects**.

   Cover ALL of these, using this language's terms:
   - A. **Simple client**: default HTTP client, AWS SDK, DB driver, no custom TLS code.
   - B. **Simple server**: framework default TLS (for example Kestrel, Tomcat, uvicorn, Node https, net/http).
   - C. **Existing server certificates in a custom keystore or cert files**:
     - the app loads its own cert and key (JKS/PKCS#12, PEM pair, PFX, Windows/.NET X509Store, Go tls.LoadX509KeyPair, Node key/cert/pfx, Python load_cert_chain)
     - RSA vs EC keys
     - several certificates in one store (RSA+EC, SNI per hostname)
     - encrypted keys
     - a keystore given through system properties or env vars
     State and TEST whether anything in the store must change. The expected answer is usually "no", but prove it.
   - D. **Custom CA trust**: private CA added to a custom truststore or bundle, the system store, or env vars. Examples: `cacerts`, `javax.net.ssl.trustStore`, `REQUESTS_CA_BUNDLE`, `SSL_CERT_FILE`, certifi, `NODE_EXTRA_CA_CERTS`, Go `x509.SystemCertPool` and `AppendCertsFromPEM`, .NET `X509Chain` and custom validation callbacks. TEST that the PQ solution keeps this trust working.
   - E. **Mutual TLS (client certificates)**: the client presents a cert from its own store or files, and the server requires and verifies it. TEST it with the PQ solution in place.
   - F. **Explicit TLS settings in code or config that block PQ**: pinned curves or groups, cipher lists, max TLS 1.2, a custom SSLContext or `tls.Config`, `SecureProtocol`, and similar. Show how to find them and what to change them to.
   - G. **FIPS mode**.
   - H. **Libraries and agents with their own TLS stack**: gRPC, Netty tcnative, CRT, librdkafka, DB drivers, APM agents, and so on. Mention only those that matter for this language.
   - I. **Certificate or public-key pinning, and HSM/PKCS#11 or KMS-backed keys**: what the solution does to them.
   - J. Any other case you find missing for this language. Examples: proxies (HTTPS_PROXY), HTTP/2 or gRPC servers, WebSockets, outbound calls through a service mesh sidecar.
4. `## Solution and automation`
   Step-by-step rollout:
   - inventory/detect
   - change: code, config, packaging per compute type (Lambda zip, Lambda image, ECS/Fargate/EKS, EC2) with IaC excerpts
   - CI guardrails: grep/lint/policy checks that fail builds on PQ-blocking settings
   - fleet rollout with canary and rollback
   Reuse the existing tab content here; move it, don't retype it.
5. `## How to test`
   - Numbered steps a team can run: posture check, local container test with a PQ-only server and a classical-only server, test for each case above (C, D, E especially), the in-cloud signal, and the rollback test.
   - Put the test scripts in full (the harness from BRIEF.md: `openssl s_server -groups X25519MLKEM768 -tls1_3`).
6. `## Pitfalls and rollback`: keep it, add new findings.
7. `## Full configuration files`: keep it LAST. Add every new file you introduce: keystore test scripts, CI check scripts, and so on.

## Rewriting rules for this pass
- The tab already holds a lot of correct, tested content. Reorganise it into the new sections. Prefer the docs `move` op (it keeps block ids and comments) over deleting and retyping.
- Delete only content that becomes a duplicate.
- Keep every evidence label and source link.
- Plant pending blocks for the new sections first, fill one section per update call, then move or delete the old ones. Load `mcp__claude_ai_Claude_Docs__guide` with items `["topic.index","topic.editing"]` before editing.
- Write `<tab>-v2.md` in your work dir before writing to the doc.
- Container label for this pass: `run=pqc-lang2-<lang>`. Work dir: `scratchpad/deep/<lang>/v2/`. Name containers `<lang>2-*` to avoid collisions; other language agents run at the same time.
- Every claim about cases C, D and E must be **Tested** in this pass or carried over as Tested from earlier evidence (cite the file). Where you can't test something (Windows, HSM, AWS), label it honestly.

## New facts from the lead (tested 2026-11-14; scripts in `scratchpad/deep/java/` and `java/ks/`)
- **Java + Bouncy Castle JSSE agent (JDK 17/21) server with an EC certificate failed because of the key manager, not the certificate.**
  - The cause: BC asks the key manager for key type `EC/secp256r1`. The JDK default `KeyManagerFactory` algorithm is `SunX509`, and SunJSSE's `SunX509KeyManagerImpl` returns no alias for that type. RSA works because its type is `RSA`.
  - The fix: the security property `ssl.KeyManagerFactory.algorithm=PKIX`, as a one-line file passed with `-Djava.security.properties=<file>`, or added to `java.security`. BC's own key manager (`ProvX509KeyManagerSimple`) is then used.
  - Results: Tomcat 11.0.29, Jetty 12.1.15 and HttpsServer on JDK 17 and 21 negotiate X25519MLKEM768 with the EC certificate, and an X25519-only client still connects. Out: `java/out/bcserver4.txt` and `bcserver4-group.txt`; BC debug log in `bcserver3-full.log`.
- **Java custom keystores with the fix**:

  | Scenario | Result |
  |---|---|
  | RSA+EC in one PKCS#12 | Default clients get EC; RSA-only clients get RSA. Without the fix, RSA is always served and EC is ignored, which breaks if RSA is removed |
  | Two EC certs (SNI) | Picked by SNI |
  | EC in JKS | Works |
  | `-Djavax.net.ssl.keyStore` | Works with the fix, fails without it |
  | Code that hard-codes `KeyManagerFactory.getInstance("SunX509")` | Still fails; change the code to `getDefaultAlgorithm()` or `"PKIX"` |
  | Client trust: private CA in `cacerts` (`keytool -importcert -cacerts`) or `-Djavax.net.ssl.trustStore` | Works with the BCJSSE client against a PQ-only server; no CA fails as expected |
  | BC strictness | BC applies the client's signature_algorithms to the cert chain. A client offering only `rsa_pss_rsae_sha256` was refused for a PKCS#1-signed RSA cert; adding `rsa_pkcs1_sha256` fixed it. SunJSSE is lenient |

  Not tested: Spring Boot SSL bundles, Netty JDK provider, Tomcat `keyManagerAlgorithm`, PKCS#11/HSM, the keystore matrix on JDK 17.

  Scripts: `java/ks/KsTest.java`, `run-ks.sh`, `run-ks2.sh`, `run-ks3.sh`; outputs `run-ks*.out`; `java/run-bcserver3.sh`, `run-bcserver4.sh`.
- GnuTLS (Debian 13, Debian 14 forky with GnuTLS 3.8.13, Ubuntu 26.04) has no ML-KEM groups; Fedora's GnuTLS 3.8.13 lists 5. OpenSSH 10 on all of them defaults to `mlkem768x25519-sha256`. Alpine git, whose libcurl uses OpenSSL, works against a PQ-only server. This matters if your language shells out to curl/git/wget or links GnuTLS.

## Hand-back (≤ 2,000 characters)
- Tab restructured: yes or no.
- Sections present.
- Cases C to J: one line each, with Tested, Documented or Unverified.
- Tests run, with pass and fail counts.
- Anything contradicting earlier tab content.
- Containers cleaned (count).
- Risks for the lead.
