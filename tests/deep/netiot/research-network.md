# PQ (hybrid ML-KEM) support in network devices — verified research (2026-11-14)

Labels: **Documented** = vendor doc page opened; **Claimed** = blog/marketing/forum/roadmap; **Not found** = searched, nothing; "not confirmed" = could not verify. Lines marked "inference" are mine, not vendor statements.
Code points: X25519MLKEM768 = 0x11EC, SecP256r1MLKEM768 = 0x11EB, SecP384r1MLKEM1024 = 0x11ED (RFC 10024 / draft-ietf-tls-ecdhe-mlkem). IKEv2 ML-KEM transform IDs (Transform Type 4/ADDKE): 35 = ML-KEM-512, 36 = ML-KEM-768, 37 = ML-KEM-1024 (as shown in FortiOS CLI).

---

## 1. Palo Alto PAN-OS

| Aspect | Finding | Label |
|---|---|---|
| TLS decryption PQ exists | Yes — "Post-quantum Cryptography (PQC) Support for TLSv1.3 Decryption", introduced **PAN-OS 12.1.2**; applies to SSL Forward Proxy, SSL Inbound Inspection, Decryption Mirror, Network Packet Broker. NGFW acts as "cipher translation proxy" (PQ on one leg, classical on other). TLSv1.3 only. | Documented |
| GUI path | Objects > Decryption Profile > (profile) > SSL Protocol Settings: enable TLSv1.3; "Select **Post-quantum Cryptography (PQC)**, and then select PQC algorithm types": "**PQC-Standard**—Enables the NIST-standardized algorithm, ML-KEM"; "**PQC-Experimental**—Enables nonstandardized algorithms, HQC, Bike, and Frodo-KEM". | Documented |
| Leg selection | "For **Preferred Session Settings**, select the proxy sessions that prioritize PQC": "**Post-Quantum SSL preferred for Client-side session**—The firewall (acting as a server) negotiates PQC algorithms..." / "**Post-Quantum SSL preferred for Server-side session**—The firewall (acting as a client) places PQC algorithms first". | Documented |
| Block non-PQ? | Not found. Doc: if client/server doesn't support PQC, NGFW negotiates a mutually supported classical algorithm. Separate "PQC detection and control (allow/block without decrypting)" listed for 10.2+ in feature table (no config detail opened). | Not found (block in decryption profile) |
| Hybrid curves | Search-result summary of release notes says hybrid with x25519/x448/p256/p384/p521 — not confirmed on an opened page. Community blog (X25519MLKEM768 example) returned HTTP 403. | not confirmed |
| Decryption log fields | Decryption log has single (non-directional) fields: "Key Exchange Algorithm" (`tls_keyxchg`), "Elliptic Curve" (`ec_curve`), "Encryption Algorithm" (`tls_enc`), "TLS Version" (`tls_version`); handshake stage `hs_stage_c2f` / `hs_stage_f2s`. No PQC-specific field on the page; whether ec_curve shows X25519MLKEM768 not confirmed. | Documented (fields) / not confirmed (PQ value) |
| IKEv2 PQ | Yes — RFC 9242 + RFC 9370 hybrid, **PAN-OS 11.2 or later**. ML-KEM 512/768/1024 listed among PQ KEMs (support-features page); config page itself says only "PQC KEM". | Documented |
| IKEv2 config | Network > Network Profiles > IKE Crypto > Advanced Options: "**Post-Quantum IKEv2 Additional Key Exchange** rounds" (Round 1-7, max seven per RFC 9370; DH Group field = default round). Network > Network Profiles > IPSec Crypto > Advanced Options: "**Post-Quantum IPSec Additional Key Exchange** rounds" ("only one PQC KEM is permitted per round"). IKE Gateway: IKEv2 only/preferred mode; General tab "IKEv2 Fragmentation" (enable); Advanced Options > **PQ KEM** > "**Enable Post-Quantum Key Exchange**" (disabled by default); optional "**Block IKEv2 if vulnerable cipher is used**". IKEv1 fallback disables PQ. | Documented |
| IKE logging | Not documented (no show/log field on the config page). | not confirmed |
| VM-Series on AWS | Feature table lists VM-Series under "Quantum-Ready NGFW" without version detail; no separate VM-Series/Marketplace statement. Same PAN-OS features assumed but not confirmed. | not confirmed |
| URLs | https://docs.paloaltonetworks.com/ngfw/release-notes/12-1/features-introduced-in-pan-os/decryption-features ; https://docs.paloaltonetworks.com/content/techdocs/en_US/network-security/decryption/administration/enabling-decryption/create-decryption-profile/create-decryption-profile-pan-os.html ; https://origin-docs.paloaltonetworks.com/network-security/quantum-security/administration/configure-quantum-resistant-ikev2-vpns/configure-post-quantum-ikev2-vpns-with-rfc-9242-and-rfc-9370-hybrid-keys ; https://docs.paloaltonetworks.com/content/techdocs/en_US/network-security/quantum-security/administration/quantum-security-concepts/support-for-quantum-features.html ; https://docs.paloaltonetworks.com/ngfw/administration/monitoring/use-syslog-for-monitoring/syslog-field-descriptions/decryption-log-fields | |

## 2. Fortinet FortiOS

| Aspect | Finding | Label |
|---|---|---|
| IPsec IKEv2 ML-KEM | Yes. Admin guide "Post-Quantum Cryptography for IPsec key exchange" (7.6.5 doc; community post references same article under 7.6.1). First version: 7.6.1 per community/third-party — not confirmed in release notes. | Documented (7.6.5) / Claimed (7.6.1) |
| CLI (verbatim from 7.6.5 guide) | `config vpn ipsec phase1-interface` ... `set addke1 35 36 37` / `set addke2 1083` / `set childless-ike enable`; `config vpn ipsec phase2-interface` ... `set addke1 1090`. addke1..addke7, up to 3 options each. CLI help: `35 ML-KEM-512. 36 ML-KEM-768. 37 ML-KEM-1024.` Only ML-KEM groups are "standardized by NIST and are FIPS 203 compliant" (others: BIKE, HQC, FrodoKEM etc. experimental). PQC groups unavailable in FIPS-CC mode. | Documented |
| IKE verification/log | `diagnose vpn ike gateway list` shows `PQC-KEM (IKE): yes` and `PQC-KEM (all IPsec): yes`; IKE debug shows `KEM decapsulate okay`, `ADDKE negotiated`. | Documented |
| Interop | Cloudflare changelog: FortiOS 7.6.6+ compatible with Cloudflare ML-KEM IPsec (ML-KEM-768/1024 + DH 20). | Documented (Cloudflare) |
| SSL deep inspection PQ | FortiOS **8.0.0** "Hybrid PQC support in SSL deep inspection": X25519MLKEM768 (0x11EC), SecP256r1MLKEM768 (0x11EB), SecP384r1MLKEM1024 (0x11ED), pure MLKEM512/768/1024. Proxy mode (HTTPS, DoT, POP3S, IMAPS, SMTPS; not yet SIP-TLS, FortiGuard urlfilter conn); flow mode via updated IPS engine. **No ssl-ssh-profile knob** documented — automatic with deep-inspection profile (`set ssl-ssh-profile "Clone of deep-inspection"` in policy). Legs not explicitly separated. 7.4.6/7.6.1 IPS engine fixed Chrome ML-KEM breakage in flow-mode deep inspection (KB). | Documented (8.0) |
| TLS log/diag | `diagnose ips ssl status` → "TLS 1.3 (EC)DHE Named Groups:" counters e.g. `x25519mlkem768:  1`. No traffic-log field documented. | Documented |
| Agentless VPN (ex-SSL VPN) | `config vpn ssl settings` `tls-groups` list includes ML-KEM512/768/1024, P-384-MLKEM1024 (search summary of community KB; not opened). | not confirmed |
| URLs | https://docs.fortinet.com/document/fortigate/7.6.5/administration-guide/229631 ; https://docs.fortinet.com/document/fortigate/8.0.0/administration-guide/771310 ; https://developers.cloudflare.com/changelog/post/2026-04-30-ipsec-post-quantum-third-party/ | |

## 3. Check Point

| Aspect | Finding | Label |
|---|---|---|
| IKEv2 VPN | R82 release notes: "Added support for ML-KEM (Kyber768) as required by the FIPS 203 standard". R82.10 RN: "Added support for standard ML-KEM as required by the FIPS 203 standard" (algorithm list in sk184080 — not opened). Hybrid IKEv2 (classical DH + ML-KEM, RFC 9370 style "multiple key exchanges"). Gateways R82+. | Documented |
| Config | SmartConsole: Objects menu > Object Explorer (Ctrl+E) > VPN Communities > (community) > **Encryption** > check "**Quantum Safe Key Exchange**" (applies default profile). Changing profile = Management API only: `add multiple-key-exchanges`; `set vpn-community-star` / `set vpn-community-meshed` with `ike-phase-1` / `ike-phase-2` → `multiple-key-exchanges`, `use-multiple-key-exchanges`, `use-standard-proposal` (false = PQC-only; can't set both false); then `verify-policy`, `install-policy`. Mixed Kyber env: Expert mode `fw ctl set -f int use_mlkem_over_kyber 1`. Not supported with Traditional Mode VPN. Default = DH15 + ML-KEM-768 per CP blog (Claimed). | Documented / default Claimed |
| VPN logging | Not documented on page. | not confirmed |
| HTTPS inspection PQ | R82.10 RN: adds hybrid group "X25519MLKEM768" for HTTPS Inspection. Blog: inspection off → PQ passes end-to-end; inspection on → inspected if X25519MLKEM768 or client accepts downgrade, "otherwise, the connection is dropped". Config path / legs / log field: not found. | Documented (RN) / config Not found |
| URLs | https://sc1.checkpoint.com/documents/R82/WebAdminGuides/EN/CP_R82_RN/Content/Topics-RN/Whats-New.htm ; https://sc1.checkpoint.com/documents/R82.10/WebAdminGuides/EN/CP_R82.10_RN/Content/Topics-RN/Whats-New.htm ; https://sc1.checkpoint.com/documents/R82.10/WebAdminGuides/EN/CP_R82.10_SitetoSiteVPN_AdminGuide/Content/Topics-VPNSG/Quantum-Safe-Key-Exchange.htm ; https://blog.checkpoint.com/innovation/quantum-safe-cyber-security-current-capabilities-and-the-road-ahead/ | |

## 4. Cisco Secure Firewall (FTD/FMC) and ASA

Source: Cisco blog "Preparing for post-quantum cryptography: the Secure Firewall roadmap" (2026-04-13) — **Claimed/roadmap**:
- ASA: RFC 8784 PPK since **9.18**; RFC 9242 + RFC 9370 (additional key exchanges) since **9.19**.
- FTD: RFC 9242/9370 "coming to FTD in 10.5"; **ML-KEM** targeted **FTD 10.5 / ASA 9.25**, GA "late 2026"; **TLS decryption with PQC** targeted FTD 10.5; PQC metadata logging FTD 11.0.
- ML-KEM in FTD 10.0/7.x: Not found. Exact ASA CLI for additional KE: not confirmed (not opened).
- URL: https://blogs.cisco.com/security/preparing-for-post-quantum-cryptography-the-secure-firewall-roadmap

## 5. Juniper SRX / vSRX

- IKEv2 PQ: **only RFC 8784 PPK** documented ("Quantum Safe IPsec VPN": static key-manager profile used as PPK profile under IKE gateway; junos-ike + Junos Key Manager; Feature Explorer intro releases 22.4R1…25.2R1 by platform; SRX1500+ and vSRX). Doc gives no set-commands (appendix blank). Verify: `show security ike security-associations detail`, `show security ipsec security-associations detail`, `show security key-manager profiles detail`. **ML-KEM / RFC 9370: Not found.** — Documented (PPK) / Not found (ML-KEM)
- SSL proxy PQ (X25519MLKEM768): Not found.
- URLs: https://networkingdocs.hpe.com/documentation/us/en/software/junos/vpn-ipsec/topics/topic-map/quantum-safe-ipsec-vpn.html ; https://apps.juniper.net/feature-explorer/feature/7502

## 6. F5 BIG-IP

| Aspect | Finding | Label |
|---|---|---|
| Versions | X25519KYBER768: 17.5.0+; **X25519MLKEM768: 17.5.1+**; P256rMLKEM768 & P384rMLKEM1024: **21.1+**. TLS 1.3 only. 21.1 doc: PQC key exchange "on Client and Server-side SSL profiles". | Documented |
| tmsh (verbatim) | `create ltm cipher rule TMSH_PQC cipher DEFAULT dh-groups X25519MLKEM768:DEFAULT signature-algorithms DEFAULT` → `create ltm cipher group TMSH_PQC allow add { TMSH_PQC }` → `create ltm profile client-ssl TMSH_PQC cipher-group TMSH_PQC options { dont-insert-empty-fragments } ciphers none`. Server side: GUI "Configure through Server-SSL profile" selects cipher group; doc's tmsh server-ssl section repeats client-ssl command (doc error) — analogous `modify ltm profile server-ssl <p> cipher-group TMSH_PQC ciphers none` is my inference, not documented. | Documented / server tmsh not confirmed |
| Logging | No iRule/log method documented for negotiated group. | not confirmed |
| URLs | https://techdocs.f5.com/en-us/bigip-17-5-1/big-ip-system-ssl-administration/integrating-pqc-on-the-client-side.html ; https://techdocs.f5.com/en-us/bigip-21-1-0/big-ip-system-ssl-administration/integrating-pqc-on-the-client-side.html | |

## 7. NetScaler (Citrix ADC) 14.1

- "NetScaler supports hybrid Post-Quantum Cryptography (PQC) on the **front end**" (client leg only; back end not addressed). Group X25519_MLKEM768. Enhanced SSL profile only. — Documented
- CLI: `bind ssl profile <name> -eccCurveName X25519_MLKEM768` (append) or `bind ssl profile <name> -eccCurveName ALL` (rebind all, X25519_MLKEM768 first). GUI: Traffic Management > SSL > SSL Profiles > edit > Advanced Settings > ECC Curve > All or X25519_MLKEM768 > Bind.
- Minimum 14.1 build: not confirmed. Logging: not documented.
- URL: https://docs.netscaler.com/us/en/citrix-adc/current-release/ssl/hybrid-pqc.html

## 8. A10 Thunder ACOS

- A10 blog: ACOS **7.0.3** adds hybrid KEM in SSL/TLS data plane on OpenSSL 3.5: X25519+ML-KEM-768, secp256r1+ML-KEM-768, secp384r1+ML-KEM-1024; client-side and server-side SSL listed. — Claimed (blog)
- CLI/template syntax, logging: Not found.
- URL: https://www.a10networks.com/blog/post-quantum-cryptography-comes-to-a10-ssl-tls-data-plane/

## 9. HAProxy

- Config (HAProxy Technologies blog, verbatim): `ssl-default-bind-curves X25519MLKEM768:SecP256r1MLKEM768:X25519:P-384:P-256`, `ssl-default-server-curves X25519MLKEM768:SecP256r1MLKEM768:X25519:P-384:P-256`, `ssl-default-bind-options ssl-min-ver TLSv1.3 no-tls-tickets`, `ssl-default-server-options ssl-min-ver TLSv1.3`. Blog: "HAProxy Enterprise 3.2+ and HAProxy Community 3.3+ support hybrid post-quantum cryptography natively" (AWS-LC builds); "HAProxy Enterprise or HAProxy Community Performance Packages are required"; confirm AWS-LC in `haproxy -vv`. Manual keywords: global `ssl-default-bind-curves`, `ssl-default-server-curves`; bind/server `curves <curves>` (colon-delimited; "When "curves" is set, "ecdhe" parameter is ignored"). A distro HAProxy linked to OpenSSL 3.5 should also accept the name (OpenSSL 3.5 ships the group) — inference, not confirmed by HAProxy docs. — Documented (manual) / Claimed (vendor blog)
- Logging: sample fetches **`ssl_fc_curve`** (front/client leg) and **`ssl_bc_curve`** (back/server leg), "Returns the name of the curve used in the key agreement"; present since **HAProxy 2.9** (absent in 2.8.0 manual); "Compatibility: OpenSSL >= 3.0.0, AWS-LC >= 3.0.0 (API >= 30)"; name format library-dependent. Log e.g. `log-format "... %[ssl_fc_curve]"`. That it prints "X25519MLKEM768" for hybrid: not confirmed. — Documented (fetch)
- URLs: https://docs.haproxy.org/ (configuration.txt, master/3.5-dev and tags v2.9.0–v3.3.0 via github.com/haproxy/haproxy doc/configuration.txt) ; https://www.haproxy.com/blog/how-to-enable-post-quantum-cryptography-and-tls-termination-with-haproxy

## 10. SSE / cloud proxies

| Product | Finding | Label | URL |
|---|---|---|---|
| Zscaler ZIA | Blog 2026-02-17: ZIA inline inspection "now supports hybrid PQC key exchange" (ML-KEM, draft-ietf-tls-ecdhe-mlkem). Client leg: if client offers TLS 1.3 + hybrid group, ZIA uses it, "independent of server capabilities". Server leg: ZIA ClientHello "includes all standard hybrid PQC key exchange methods". No config change needed. Logging: "selected key exchange group is always logged" — field name not given. Help-center doc not found. | Claimed (vendor blog) | https://www.zscaler.com/blogs/product-insights/leading-security-service-edge-now-quantum-ready |
| Netskope NG-SWG | **Beta from Release 137**: X25519MLKEM768 only; front-end (client→proxy) and back-end (proxy→server) "flags are independently controlled"; "Contact Netskope Support to enable it for your tenant"; falls back to X25519/P-256, sessions not dropped. Log fields not mentioned. | Documented | https://docs.netskope.com/en/post-quantum-cryptography-support |
| Cloudflare One | Product table: Gateway egress (to origin) key agreement X25519MLKEM768; Cloudflare One Client (WARP, MASQUE/TLS 1.3) X25519MLKEM768; Cloudflare Tunnel (cloudflared) X25519MLKEM768; Access (visitor→edge) X25519MLKEM768; Cloudflare IPsec "ML-KEM-768/1024 + DH Group 20 (P-384) in IKEv2" (downgrade protection in progress). Gateway client-side decryption leg not separately stated. Changelog 2026-04-30: IPsec PQ GA with third-party devices (RFC 9370 + draft-ietf-ipsecme-ikev2-mlkem, IKE_INTERMEDIATE), validated Cisco 8000 IOS XR 26.1.1 and FortiOS 7.6.6+. | Documented | https://developers.cloudflare.com/ssl/post-quantum-cryptography/pqc-cloudflare-products/ ; https://developers.cloudflare.com/changelog/post/2026-04-30-ipsec-post-quantum-third-party/ |
| Prisma Access | No Prisma Access-specific PQ decryption doc found. SCM "Quantum-Safe Security" insights mention cipher translation by NGFWs on PAN-OS 12.1+ and Prisma Access telemetry; Prisma SD-WAN has RFC 9370 ML-KEM IPsec (search result, not opened). | Not found | — |

## 11. Squid (ssl-bump)

- `http_port` / `https_port` TLS options: only `tls-dh=[curve:]file` — "File containing DH parameters for temporary/ephemeral DH key exchanges, optionally prefixed by a curve for ephemeral ECDH key exchanges ... Supported curves for ECDH can be listed using the "openssl ecparam -list_curves" command"; `options=SINGLE_ECDH_USE` ("The adopted curve should be specified using the tls-dh option"). **No TLS groups/curves list option** on http_port or `tls_outgoing_options` (v7 docs). A single ECDH curve name ≠ hybrid group; X25519MLKEM768 via tls-dh: not confirmed. Server leg uses OpenSSL library default groups (OpenSSL 3.5 default includes X25519MLKEM768) — inference, not confirmed by Squid docs. Logging of negotiated group: Not found. — Documented (absence) 
- URLs: https://www.squid-cache.org/Doc/config/http_port/ ; https://www.squid-cache.org/Doc/config/tls_outgoing_options/

## 12. Envoy

- `ecdh_curves` in `TlsParameters` (`tls_params`): arch doc: BoringSSL backend supports X25519MLKEM768; "X25519MLKEM768 is included in the default ECDH curves for both downstream and upstream TLS connections" (incl. FIPS builds); disable with runtime `envoy.reloadable_features.pqc_default_ecdh_curves: false`. Explicit: `tls_params: { ecdh_curves: [X25519MLKEM768, X25519, P-256] }`. — Documented
- Default-on version: changelog **1.40.0** (2026-10-13): "Added ``X25519MLKEM768`` ... to the default ECDH curves for both upstream and downstream TLS connections (including FIPS builds)". Explicit opt-in on earlier BoringSSL builds: HashiCorp Consul doc cites Envoy 1.37.6/1.38.4/1.39.1 (search summary, not opened) — not confirmed.
- Logging: access-log substitutions **`%DOWNSTREAM_TLS_GROUP%`** and **`%UPSTREAM_TLS_GROUP%`** added in **1.39.0**: "The TLS group may be used to discern if a TLS connection used a post quantum safe key exchange (e.g. X25519MLKEM768)." — Documented (changelog)
- URLs: https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/security/ssl ; https://github.com/envoyproxy/envoy/blob/main/changelogs/1.40.0.yaml ; https://github.com/envoyproxy/envoy/blob/main/changelogs/1.39.0.yaml

## 13. AWS

| Item | Finding | Label | URL |
|---|---|---|---|
| Network Firewall TLS inspection | Considerations page: TLS 1.1/1.2/1.3; lists client cipher suites only (no key-exchange groups, no PQ mention); "Network Firewall uses TLS 1.3 to initiate the forward connection to the server"; no ECH/ESNI, no QUIC, no StartTLS. **AWS PQ-readiness page**: NFW "Hybrid PQ key exchange launched in FIPS & non-FIPS endpoints, in commercial and US GovCloud regions" / "NFW can handle PQ-TLS handshakes, but you may need to adjust rules that aggressively drop connections." Which leg(s) and group names: not stated. TLS log field for group: not found. | Documented (both pages; partially conflicting detail) | https://docs.aws.amazon.com/network-firewall/latest/developerguide/tls-inspection-considerations.html ; https://aws.amazon.com/security/post-quantum-cryptography/aws-pq-readiness-confidentiality/ |
| Site-to-Site VPN | No PQ/ML-KEM. Phase 1 DH groups 2, 14–24; Phase 2 2, 5, 14–24 (classical only). Doc history latest entry 2025-11-15 (Concentrators); no PQ entry. No What's New 2025–2026 PQ VPN announcement found. | Not found (PQ) | https://docs.aws.amazon.com/vpn/latest/s2svpn/WhatsNew.html ; https://docs.aws.amazon.com/vpn/latest/s2svpn/CGRequirements.html |
| Client VPN | OpenVPN-based TLS; no PQ / tls-groups statement in docs. | Not found | https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/what-is.html |
| ALB/NLB | What's New 2025-11-21: PQ-TLS security policies (hybrid ML-KEM), opt-in per listener. Policy names not on that page. | Documented | https://aws.amazon.com/about-aws/whats-new/2025/11/network-load-balancers-post-quantum-key-exchange-tls |
| Gateway Load Balancer | "operates at the third layer of the OSI model, the network layer. It listens for all IP packets across all ports"; GWLB ↔ appliances use "GENEVE protocol on port 6081". No TLS termination → PQ depends entirely on the appliance. | Documented | https://docs.aws.amazon.com/elasticloadbalancing/latest/gateway/introduction.html |

## 14. strongSwan 6.0

- 6.0.0 (2024-12-03): ML-KEM keywords `mlkem512`, `mlkem768`, `mlkem1024`; "additional key exchange methods are configured with a `keX_` prefix", e.g. `x25519-ke1_mlkem768`; optional round `keX_none`. Backends: new **`ml` plugin**, `botan` (Botan 3.6.0+), `wolfssl` (wolfSSL 5.7.4+), `openssl` with AWS-LC 1.37.0+. Uses RFC 9370 IKE_INTERMEDIATE; IKE_SA_INIT can't be fragmented. — Documented
- swanctl.conf verbatim (strongSwan test rw-mlkem, moon): `proposals = aes256-aes128-sha384-sha256-ecp384-x25519-ke1_mlkem768-ke1_mlkem1024-ke1_mlkem512-ke1_none` ; `esp_proposals = aes256gcm128-aes128gcm128-ecp384-x25519-ke1_mlkem768-ke1_mlkem1024-ke1_mlkem512-ke1_none`; strongswan.conf `charon-systemd { load = nonce pem pkcs1 ml openssl ... }`.
- Log lines (moon.daemon.log): `[CFG] selected proposal: IKE:AES_CBC_256/HMAC_SHA2_384_192/PRF_HMAC_SHA2_384/ECP_384/KE1_ML_KEM_768`; `[ENC] parsed IKE_INTERMEDIATE request 1 [ KE ]`. `swanctl --list-sas`: `AES_CBC-128/HMAC_SHA2_256_128/PRF_HMAC_SHA2_256/CURVE_25519/KE1_ML_KEM_512`.
- URLs: https://strongswan.org/blog/2024/12/03/strongswan-6.0.0-released.html ; https://strongswan.org/testing/testresults/ikev2/rw-mlkem/

## 15. OpenVPN / WireGuard / libreswan

- **OpenVPN 2.6** manual: `--tls-groups list` "A list of allowable groups/curves in order of preference" (OpenSSL 1.1+ default "X25519:secp256r1:X448:secp521r1:secp384r1"). — Documented. With OpenSSL 3.5: OpenVPN Access Server tutorial: `tls-groups X25519MLKEM768` (PQ-only), `tls-groups "X25519MLKEM768:X25519"`, `tls-groups SecP256r1MLKEM768`; requires OpenSSL 3.5+ on both ends; OpenVPN Connect v3 not yet supported. Log: `key agreement: X25519MLKEM768` (`grep "key agreement" /var/log/openvpnas.log`). — Documented (Access Server); community 2.6 + OpenSSL 3.5 behaviour identical by inference, not separately confirmed. URLs: https://openvpn.net/community-docs/community-articles/openvpn-2-6-manual.html ; https://openvpn.net/as-docs/v3/tutorials/tutorial--post-quantum-cryptography.html
- **WireGuard**: no PQ key exchange. Rosenpass: "WireGuard handles pre-quantum security"; Rosenpass (Classic McEliece + Kyber) feeds the WireGuard pre-shared key. — Documented. https://rosenpass.eu/
- **libreswan 5.4** (2026-08-13) CHANGES: "implement IKE_ADDITIONAL_KE for RFC 9370"; "support ML_KEM_768 in IKE_SA_INIT and IKE_INTERMEDIATE exchanges ... requires NSS >= 3.118.1"; IKE_FOLLOWUP_KE. Only ML_KEM_768 listed. Syntax (main-branch test `ikev2-intermediate-04-addke-ml-kem-768`): `intermediate=yes` + `ike=aes128-sha2-dh31;addke1=ml_kem_768`; pure KEM: `ike=aes;ke=ml_kem_768`. Log: `processed IKE_SA_INIT response ... {cipher=AES_CBC_128 integ=HMAC_SHA2_256_128 prf=HMAC_SHA2_256 ke=DH31 addke1=ML_KEM_768}, initiating IKE_INTERMEDIATE`. ipsec.conf(5) web man page has no ML-KEM text yet. — Documented (project CHANGES + test suite). URL: https://github.com/libreswan/libreswan/blob/main/CHANGES ; https://github.com/libreswan/libreswan/tree/main/testing/pluto/ikev2-intermediate-04-addke-ml-kem-768

## 16. Zeek / Suricata

- **Zeek** `ssl.log` field **`curve`** ("Elliptic curve the server chose when using ECDH/ECDHE"); for TLS 1.3 set from the server key_share (`event ssl_extension_key_share` → `c$ssl$curve = ec_curves[curves[0]]`). `SSL::ec_curves` maps `[4588] = "X25519MLKEM768"` (0x11EC), `[4587] = "SecP256r1MLKEM768"`, `[4589] = "SecP384r1MLKEM1024"`, `[25497] = "X25519Kyber768Draft00"`. First in **Zeek 7.1.0** (7.0.0 had only X25519Kyber768Draft00). — Documented (source: scripts/base/protocols/ssl/consts.zeek, main.zeek at tags v7.0.0/v7.1.0/master)
- JA4 plugin: `zkg install zeek/foxio/ja4` (Zeek 7.0+), adds JA4/JA4S to ssl.log; group not confirmed in JA4 — use `curve`. https://github.com/FoxIO-LLC/ja4/tree/main/zeek
- **Suricata** (7.0.10 and 9.0-dev docs): **no** `tls.*` rule keyword for key-exchange group/curve (keywords cover cert_subject/issuer/serial/fingerprint, sni, subjectaltname, certs, ja3/ja4…). EVE TLS custom fields `client_handshake` (`version`, `ciphers`, `exts`, `sig_algs`) and `server_handshake` (`version`, chosen cipher, `exts`) — extension IDs only, no group value (present in 8.0.0 docs). → Negotiated group not loggable. — Documented (absence). https://docs.suricata.io/en/latest/rules/tls-keywords.html ; https://docs.suricata.io/en/latest/output/eve/eve-json-format.html

---
### Summary matrix (TLS inspection PQ / IKEv2 ML-KEM)
| Vendor | TLS inspect PQ | IKEv2 ML-KEM |
|---|---|---|
| PAN-OS | Yes 12.1.2, both legs selectable | Yes 11.2+ (RFC 9370 rounds) |
| FortiOS | Yes 8.0 (auto, both modes) | Yes 7.6.x (`addke1 36`) |
| Check Point | Yes R82.10 (X25519MLKEM768; drop otherwise) | Yes R82 (Kyber768) / R82.10 (std ML-KEM) |
| Cisco FTD/ASA | No (roadmap FTD 10.5) | ASA RFC 9370 since 9.19; ML-KEM roadmap FTD 10.5/ASA 9.25 |
| Juniper SRX | Not found | PPK (RFC 8784) only |
| F5 | Yes 17.5.1 (X25519MLKEM768), 21.1 more groups | n/a |
| NetScaler 14.1 | Front end only | n/a |
| A10 ACOS 7.0.3 | Claimed both sides | n/a |
| AWS NFW | PQ-readiness says launched; details not documented | AWS S2S VPN: No |
