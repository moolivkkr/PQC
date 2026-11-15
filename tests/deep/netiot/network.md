# Network devices, VPN and egress

<!-- SECTION what -->
## What decides PQ here

A network device sets PQ only where it terminates TLS or IKE itself. A decrypting firewall, ADC or proxy runs two separate handshakes: the **client leg** (the client to the device, where the device acts as the server) and the **server leg** (the device to the origin, where the device acts as the client). Each leg gets PQ only if that device's TLS stack and profile offer ML-KEM. A device that doesn't decrypt passes the client's handshake through unchanged, so PQ then depends on the two endpoints. It only has to forward the roughly 1.2 KB larger ClientHello without dropping it. For IPsec, both IKEv2 peers must support RFC 9370 additional key exchanges with ML-KEM. Network devices play two roles: **sensors** that show which connections are classical, and **converters** that terminate classical TLS and re-originate PQ TLS for clients you can't upgrade.

All tests ran on 2026-11-14 in local containers, with no AWS access. The scripts and outputs are under `scratchpad/deep/netiot/` (`squid/`, `swan/`, `zeek/`, `envoy/`).

<!-- SECTION matrix -->
## Status matrix by device type

| Device type | Product (form) | Client leg PQ (device as server) | Server leg PQ (device as client) | IKEv2 ML-KEM | Min version | Evidence |
|---|---|---|---|---|---|---|
| NGFW | Palo Alto PAN-OS (PA hardware, VM-Series on EC2/Marketplace) | Yes (decryption profile, PQC) | Yes | Yes (RFC 9370 rounds) | TLS decryption 12.1.2; IKEv2 11.2 | Documented ([decryption](https://docs.paloaltonetworks.com/ngfw/release-notes/12-1/features-introduced-in-pan-os/decryption-features), [IKEv2](https://origin-docs.paloaltonetworks.com/network-security/quantum-security/administration/configure-quantum-resistant-ikev2-vpns/configure-post-quantum-ikev2-vpns-with-rfc-9242-and-rfc-9370-hybrid-keys)); VM-Series parity not confirmed |
| NGFW | Fortinet FortiGate (hardware, FortiGate-VM on EC2) | Yes (automatic in deep inspection) | Yes (legs not separated in the docs) | Yes (`addke1 36`) | SSL deep inspection 8.0.0; IPsec 7.6.x (7.6.5 guide; 7.6.1 claimed) | Documented ([SSL 8.0](https://docs.fortinet.com/document/fortigate/8.0.0/administration-guide/771310), [IPsec 7.6.5](https://docs.fortinet.com/document/fortigate/7.6.5/administration-guide/229631)) |
| NGFW | Check Point Quantum (appliance, CloudGuard on EC2) | Yes (X25519MLKEM768 in HTTPS Inspection) | Not stated | Yes ("Quantum Safe Key Exchange") | IKEv2 R82 (Kyber768), R82.10 (standard ML-KEM); HTTPS Inspection R82.10 | Documented ([R82.10 RN](https://sc1.checkpoint.com/documents/R82.10/WebAdminGuides/EN/CP_R82.10_RN/Content/Topics-RN/Whats-New.htm), [VPN guide](https://sc1.checkpoint.com/documents/R82.10/WebAdminGuides/EN/CP_R82.10_SitetoSiteVPN_AdminGuide/Content/Topics-VPNSG/Quantum-Safe-Key-Exchange.htm)) |
| NGFW | Cisco Secure Firewall FTD (hardware, FTDv on EC2) | No (roadmap FTD 10.5) | No | No (roadmap FTD 10.5) | none today | Claimed ([Cisco roadmap blog](https://blogs.cisco.com/security/preparing-for-post-quantum-cryptography-the-secure-firewall-roadmap)) |
| NGFW | Cisco ASA (hardware, ASAv) | No | No | RFC 9370 framework since 9.19; ML-KEM roadmap 9.25 | none today | Claimed (same blog) |
| NGFW | Juniper SRX / vSRX | Not found | Not found | No (RFC 8784 PPK only) | none | Documented PPK ([Juniper](https://networkingdocs.hpe.com/documentation/us/en/software/junos/vpn-ipsec/topics/topic-map/quantum-safe-ipsec-vpn.html)); ML-KEM not found |
| ADC | F5 BIG-IP (hardware, VE on EC2) | Yes (client-ssl cipher group) | Yes (server-ssl cipher group) | n/a | X25519MLKEM768 17.5.1; more groups 21.1 | Documented ([F5 17.5.1](https://techdocs.f5.com/en-us/bigip-17-5-1/big-ip-system-ssl-administration/integrating-pqc-on-the-client-side.html)) |
| ADC | NetScaler ADC 14.1 (MPX, VPX on EC2) | Yes (front end) | Not documented | n/a | 14.1 (build not confirmed) | Documented ([NetScaler](https://docs.netscaler.com/us/en/citrix-adc/current-release/ssl/hybrid-pqc.html)) |
| ADC | A10 Thunder ACOS (hardware, vThunder) | Yes | Yes | n/a | ACOS 7.0.3 | Claimed ([A10 blog](https://www.a10networks.com/blog/post-quantum-cryptography-comes-to-a10-ssl-tls-data-plane/)) |
| ADC | HAProxy Enterprise 3.2+ / Community 3.3+ (AWS-LC build) | Yes (`curves`) | Yes (`ssl-default-server-curves`) | n/a | 3.2 / 3.3 | Documented (manual) and Claimed (blog). Config on {{tab:f7dff530-a0a0}} |
| Forward proxy | Squid 6.13 ssl-bump (Debian 13, OpenSSL 3.5.7) | Yes (OpenSSL default) | Yes (OpenSSL default) | n/a | Squid built on OpenSSL 3.5 | **Tested** (4/4) |
| Egress proxy | Envoy 1.40.2 egress gateway (BoringSSL) | Yes | Yes (`ecdh_curves`, default from 1.40) | n/a | 1.40.0 default; log field 1.39.0 | **Tested** (2/2) and Documented ([Envoy](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/security/ssl)) |
| SWG (SaaS) | Zscaler ZIA | Yes | Yes (offers all hybrid groups) | n/a | since Feb 2026 | Claimed ([Zscaler blog](https://www.zscaler.com/blogs/product-insights/leading-security-service-edge-now-quantum-ready)) |
| SWG (SaaS) | Netskope NG-SWG | Beta, X25519MLKEM768 | Beta, separate flag | n/a | Release 137, via support ticket | Documented ([Netskope](https://docs.netskope.com/en/post-quantum-cryptography-support)) |
| SASE (SaaS) | Cloudflare One (WARP client, Gateway, Tunnel, IPsec) | Yes (WARP, Access) | Yes (Gateway egress, Tunnel) | Yes (ML-KEM-768/1024 + DH20) | GA | Documented ([Cloudflare](https://developers.cloudflare.com/ssl/post-quantum-cryptography/pqc-cloudflare-products/)) |
| SASE (SaaS) | Palo Alto Prisma Access | Not found | Not found | Not found | — | Not found |
| VPN | strongSwan 6.0.7 (Alpine 3.24, OpenSSL 3.5.9) | n/a | n/a | Yes | 6.0.0 (ml/AWS-LC), 6.0.2 (OpenSSL 3.5) | **Tested** (IKE SA up with `KE1_ML_KEM_768`) |
| VPN | strongSwan 6.0.1 (Debian 13 package) | n/a | n/a | **No**: openssl plugin lists no ML-KEM; the SA failed | — | **Tested** (fail) |
| VPN | libreswan 5.4 (NSS ≥ 3.118.1) | n/a | n/a | Yes (ML_KEM_768 only) | 5.4 | Documented ([CHANGES](https://github.com/libreswan/libreswan/blob/main/CHANGES)) |
| VPN | OpenVPN 2.6 + OpenSSL 3.5 | Yes (`tls-groups`) | Yes | n/a | 2.6 + OpenSSL 3.5 both ends | Documented ([Access Server tutorial](https://openvpn.net/as-docs/v3/tutorials/tutorial--post-quantum-cryptography.html)) |
| VPN | WireGuard | No (Curve25519 only); Rosenpass adds a PQ pre-shared key | — | — | — | Documented ([Rosenpass](https://rosenpass.eu/)) |
| AWS managed | Site-to-Site VPN | — | — | No (classical DH groups 2, 14–24) | — | Documented ([CGW requirements](https://docs.aws.amazon.com/vpn/latest/s2svpn/CGRequirements.html)) |
| AWS managed | Client VPN (OpenVPN based) | No PQ statement | — | — | — | Not found |
| AWS managed | Network Firewall TLS inspection | Readiness page says hybrid PQ launched; groups and legs not documented | Uses TLS 1.3 to the server; PQ not stated | — | — | Documented, but incomplete ([readiness](https://aws.amazon.com/security/post-quantum-cryptography/aws-pq-readiness-confidentiality/), [TLS inspection](https://docs.aws.amazon.com/network-firewall/latest/developerguide/tls-inspection-considerations.html)) |
| AWS managed | Gateway Load Balancer | No TLS (layer 3, GENEVE 6081); PQ is the appliance's | — | — | — | Documented ([GWLB](https://docs.aws.amazon.com/elasticloadbalancing/latest/gateway/introduction.html)) |
| AWS managed | Transit Gateway, VPC peering, PrivateLink, Direct Connect | No TLS termination; passes the endpoint's handshake | — | — | — | Documented (behaviour) |
| AWS managed | VPC Lattice HTTPS listener, Verified Access | Not documented | — | — | — | Not found |
| Sensor | Zeek 8.0.10 (on EC2 with Traffic Mirroring) | Logs negotiated group | — | — | `curve` = X25519MLKEM768 from 7.1.0 | **Tested** |
| Sensor | Suricata 7/8 | Can't log the group | — | — | — | Documented (absence, [EVE format](https://docs.suricata.io/en/latest/output/eve/eve-json-format.html)) |

<!-- SECTION ngfw -->
## Next-generation firewalls (TLS decryption and IPsec)

Hardware and virtual forms run the same OS, so the settings below apply to VM-Series, FortiGate-VM, CloudGuard and the other AWS Marketplace images. Check the image's OS version first: Marketplace AMIs often lag the current release.

### Palo Alto PAN-OS (12.1.2+ decryption, 11.2+ IKEv2)

- **Decryption (both legs):** Objects > Decryption > Decryption Profile > *profile* > SSL Protocol Settings. Set the max version to TLSv1.3, tick **Post-quantum Cryptography (PQC)**, choose **PQC-Standard** (ML-KEM; leave PQC-Experimental off). Under **Preferred Session Settings** tick **Post-Quantum SSL preferred for Client-side session** (firewall as server) and/or **Post-Quantum SSL preferred for Server-side session** (firewall as client). This applies to SSL Forward Proxy, SSL Inbound Inspection and Decryption Mirror. A client or server without PQ gets a classical handshake; the docs show no "block non-PQ" option in the profile. Documented.
- **Cipher translation:** each leg is chosen on its own, so a classical client can reach a PQ server and the reverse. Documented.
- **Logging:** the decryption log has `tls_keyxchg` (Key Exchange Algorithm) and `ec_curve` (Elliptic Curve). Whether `ec_curve` shows `X25519MLKEM768` is not confirmed; check on your firewall before relying on it.
- **IKEv2 (11.2+):** Network > Network Profiles > IKE Crypto > *profile* > Advanced Options > **Post-Quantum IKEv2 Additional Key Exchange** round 1 = ML-KEM-768. In IPSec Crypto > Advanced Options, set **Post-Quantum IPSec Additional Key Exchange** the same way. On the IKE Gateway: IKEv2 only, General > enable **IKEv2 Fragmentation**, Advanced Options > PQ KEM > **Enable Post-Quantum Key Exchange**. Optionally tick **Block IKEv2 if vulnerable cipher is used**. Falling back to IKEv1 disables PQ. Documented.

### Fortinet FortiGate (FortiOS 8.0 SSL inspection, 7.6.x IPsec)

- **SSL deep inspection (8.0.0+):** there's no profile switch. A policy with a deep-inspection `ssl-ssh-profile` negotiates X25519MLKEM768, SecP256r1MLKEM768 and SecP384r1MLKEM1024 in proxy mode, and in flow mode through the updated IPS engine. SIP-TLS isn't covered yet. Check counters with `diagnose ips ssl status` (under "TLS 1.3 (EC)DHE Named Groups", for example `x25519mlkem768: 1`). Documented. Before 7.4.6/7.6.1 the IPS engine broke Chrome's ML-KEM handshakes in flow mode, so upgrade first.
- **IPsec (7.6.x):** see `fortigate-ipsec-pq.conf` under Full configuration files. Verify with `diagnose vpn ike gateway list`, which should show `PQC-KEM (IKE): yes` and `PQC-KEM (all IPsec): yes`. The PQ groups aren't available in FIPS-CC mode. Documented.

### Check Point (R82 / R82.10)

- **IKEv2:** SmartConsole > Object Explorer > VPN Communities > *community* > Encryption > tick **Quantum Safe Key Exchange**, then install policy. To change the profile, use the Management API: `add multiple-key-exchanges`, then `set vpn-community-star … ike-phase-1 { use-multiple-key-exchanges true … }`. Setting `use-standard-proposal false` makes it PQ-only. It doesn't work with Traditional Mode VPN. Documented.
- **HTTPS Inspection (R82.10):** adds X25519MLKEM768. A vendor blog says a client that offers only PQ groups and won't fall back is dropped when inspected. The config path and the log field aren't documented: not confirmed.

### Cisco Secure Firewall (FTD) and ASA, Juniper SRX

- No ML-KEM today. Cisco's roadmap says ML-KEM IKEv2 and PQ TLS decryption are coming in FTD 10.5 / ASA 9.25 ("late 2026"). Claimed. ASA has RFC 9370 additional key exchanges (classical) since 9.19.
- Juniper documents only RFC 8784 post-quantum pre-shared keys (Junos Key Manager) for IPsec. That protects against harvest-now attacks when a strong PPK is distributed out of band, but it isn't ML-KEM. Documented.
- For these platforms today: put a PQ-capable device in the path (a PAN-OS/FortiGate VM, or strongSwan 6.0.2+) or use Cloudflare/SASE IPsec. Exclude decrypted flows you can't make PQ from the "PQ-required" policy, and record them as exceptions.

<!-- SECTION adc -->
## ADCs and load balancers

| Product | Client leg (virtual server) | Server leg (pool) | Logging the group | Evidence |
|---|---|---|---|---|
| F5 BIG-IP 17.5.1+ | cipher rule `dh-groups X25519MLKEM768:DEFAULT` → cipher group → `client-ssl … cipher-group <grp> ciphers none` | the same cipher group on the `server-ssl` profile (GUI documented; the server-ssl tmsh line is our inference) | Not documented | Documented |
| NetScaler 14.1 | `bind ssl profile <p> -eccCurveName X25519_MLKEM768` (Enhanced SSL profile) | Not documented | Not documented | Documented |
| A10 ACOS 7.0.3 | client-SSL template (syntax not published) | server-SSL template | Not found | Claimed |
| HAProxy | `curves X25519MLKEM768:X25519:P-256` on `bind`, or `ssl-default-bind-curves` | `ssl-default-server-curves` / `curves` on `server` | `%[ssl_fc_curve]` / `%[ssl_bc_curve]` (2.9+) | Documented |

HAProxy, nginx and other open-source configs are on {{tab:f7dff530-a0a0}}. The AWS ALB and NLB policies are on {{tab:bb21387b-4f66}}.

<!-- SECTION proxy -->
## Forward proxies and secure web gateways (egress)

### Squid ssl-bump (Tested)

Squid has no TLS groups directive. `http_port` offers only `tls-dh=[curve:]file`, a single ECDH curve, and `tls_outgoing_options` has no curve option. Both legs therefore use the OpenSSL library defaults. Squid 6.13 on Debian 13 (`squid-openssl`, OpenSSL 3.5.7) negotiated X25519MLKEM768 on both legs with no Squid setting. It also bridged a classical client to a PQ-only origin, and a PQ client to a classical-only origin. Restricting the process with `OPENSSL_CONF` (`Groups = X25519:P-256`) made the PQ-only origin fail, which proves the control point. Squid can log the TLS version and cipher per leg (`%ssl::>negotiated_version`, `%ssl::<negotiated_cipher`) but not the group. Use Zeek, or the origin's logs, to see it.

| Test (squid 6.13, OpenSSL 3.5.7, debian:trixie-slim) | Result |
|---|---|
| PQ client → Squid → PQ-only origin (`-groups X25519MLKEM768`) | 200, client leg `Negotiated TLS1.3 group: X25519MLKEM768` |
| Classical client (`--curves X25519`) → Squid → PQ-only origin | 200 (Squid converts) |
| PQ client → Squid → classical-only origin | 200 (server-leg fallback) |
| Squid with `OPENSSL_CONF` Groups=X25519:P-256 → PQ-only origin | fails, as expected |

Debian 12 / Ubuntu 24.04 / AL2 Squid packages use OpenSSL 3.0 or 1.1.1 and give no PQ. Use a Debian 13 or Alpine 3.24 based image (see {{tab:99613846-4046}}).

### Envoy egress gateway (Tested)

Envoy 1.40.2 (BoringSSL) originated TLS 1.3 to a PQ-only origin with `upstream_group=X25519MLKEM768`. Pointed at a classical-only origin, it fell back to `upstream_group=X25519`. The group was logged with `%UPSTREAM_TLS_GROUP%` (and `%DOWNSTREAM_TLS_GROUP%` for the client leg), available since 1.39.0. From 1.40.0, X25519MLKEM768 is in the default curves; setting `ecdh_curves` makes it explicit. Istio egress gateways are on {{tab:569dd476-c063}}.

### SaaS SWG and SASE

| Service | What to configure | Logging | Evidence |
|---|---|---|---|
| Zscaler ZIA | Nothing; hybrid used when the client offers it, upstream ClientHello offers hybrid groups | "selected key exchange group is always logged" (field name not published) | Claimed |
| Netskope NG-SWG | Open a support case to enable PQ for the tenant (front-end and back-end flags separate); falls back to X25519/P-256 | Not mentioned | Documented (beta) |
| Cloudflare One | Gateway egress, WARP client, Tunnel and Access are PQ by default; IPsec needs ML-KEM proposals on your device (FortiOS 7.6.6+, Cisco IOS XR 26.1.1 validated) | Not covered here | Documented |
| Prisma Access | No PQ decryption document found | — | Not found |

<!-- SECTION vpn -->
## VPN

| VPN | How to get PQ | Evidence |
|---|---|---|
| AWS Site-to-Site VPN | Not possible: phase 1 and 2 offer classical DH groups only. Run your own PQ IPsec on EC2 (strongSwan 6.0.2+, PAN-OS 11.2+, FortiGate 7.6.x, Check Point R82.10) over the internet or Direct Connect, or tunnel the traffic in PQ TLS | Documented (absence) |
| AWS Client VPN | No PQ statement; the client and endpoint OpenSSL builds are AWS-managed | Not found |
| strongSwan | `proposals = aes256gcm16-prfsha384-x25519-ke1_mlkem768[-ke1_none]`; needs 6.0.0+ with the `ml` plugin or AWS-LC, or 6.0.2+ with OpenSSL 3.5 | **Tested** (6.0.7) / Documented |
| libreswan 5.4 | `ike=aes128-sha2-dh31;addke1=ml_kem_768` + `intermediate=yes` | Documented |
| OpenVPN 2.6 | `tls-groups X25519MLKEM768:X25519` with OpenSSL 3.5 on both ends; the log shows `key agreement: X25519MLKEM768`. OpenVPN Connect v3 not yet | Documented (Access Server) |
| WireGuard | No ML-KEM. Rosenpass (Classic McEliece + ML-KEM/Kyber) feeds WireGuard a PQ pre-shared key; WireGuard keeps the classical handshake | Documented |
| PAN-OS / FortiGate / Check Point | See the NGFW section | Documented |

**strongSwan test (Tested):** two Alpine 3.24 containers ran strongSwan 6.0.7 with the openssl plugin (OpenSSL 3.5.9), which lists `ML_KEM_512/768/1024[openssl]`. The IKE SA came up as `AES_GCM_16-256/PRF_HMAC_SHA2_384/CURVE_25519/KE1_ML_KEM_768`. The ML-KEM share went in `IKE_INTERMEDIATE` (fragmented `EF(1/2)`), and the transport-mode CHILD SA was installed (needs `--cap-add NET_ADMIN` only). The same config on **Debian 13's strongSwan 6.0.1** failed: its openssl plugin has no ML-KEM. ML-KEM through OpenSSL 3.5 arrived in 6.0.2 ([release note](https://strongswan.org/blog/2025/07/14/strongswan-6.0.2-released.html)).

<!-- SECTION aws -->
## AWS network services

- **AWS Network Firewall:** the PQ readiness page says hybrid PQ key exchange launched on FIPS and non-FIPS endpoints. It adds that "you may need to adjust rules that aggressively drop connections" because of the larger ClientHello. The TLS inspection docs don't say which groups each leg offers, and the TLS log has no group field. Treat PQ through NFW TLS inspection as **not confirmed**. Test it with the PQ-only and classical-only probes under Verify before you rely on it. Without TLS inspection, NFW passes the handshake through, so PQ is end to end. Check stateful rules that match on `tls.sni` or the handshake size against the 1.2 KB larger ClientHello.
- **Gateway Load Balancer:** layer 3, GENEVE on UDP 6081; it never sees TLS. PQ is whatever the appliance behind it does (PAN-OS, FortiGate, Check Point, as above). Allow for GENEVE overhead in the appliance MTU.
- **Transit Gateway, VPC peering, Direct Connect, PrivateLink:** no TLS termination. They don't block PQ; the endpoints decide.
- **Site-to-Site and Client VPN:** classical only (see VPN).
- **ALB, NLB, CloudFront, API Gateway:** see {{tab:bb21387b-4f66}} and {{tab:6d11c1c8-dcc8}}.

<!-- SECTION sensors -->
## Sensors: detect non-PQ connections

| Sensor | What it shows | How | Evidence |
|---|---|---|---|
| Zeek 7.1+ (8.0.10 tested) | negotiated group in `ssl.log` field `curve` (`X25519MLKEM768`, `x25519`, `secp256r1`) | `pq-tls.zeek` adds a `pq` column and raises `PQTLS::Classical_Key_Exchange` notices | **Tested** |
| Suricata 7/8 | version, cipher, extension IDs only; no group | — | Documented (absence) |
| JA4 (`zkg install zeek/foxio/ja4`) | what the client **offers**; finds clients that never offer ML-KEM | JA4 fingerprints in `ssl.log` | Documented (plugin) |
| Envoy / HAProxy / OpenVPN logs | negotiated group per connection | `%DOWNSTREAM_TLS_GROUP%`, `%[ssl_fc_curve]`, `key agreement:` | Documented / Tested (Envoy) |
| FortiOS | group counters | `diagnose ips ssl status` | Documented |
| VPC Flow Logs | no TLS data | — | Documented |

Zeek test: a pcap with three handshakes (OpenSSL 3.5 default, X25519-only, TLS 1.2) produced this `ssl.log` (`zeek-cut server_name version curve pq`):

```text
pq.example       TLSv13  X25519MLKEM768  T
classic.example  TLSv13  x25519          F
tls12.example    TLSv12  x25519          F
```

It also raised two notices: `non-PQ TLS key exchange: group=x25519 version=TLSv13 sni=classic.example` and the same for `tls12.example`.

**Packet capture on AWS:** VPC Traffic Mirroring works only from Nitro EC2 network interfaces. It can't mirror Fargate tasks, Lambda or AWS-managed endpoints. Mirror the ENIs of NAT instances, proxies or app hosts to a Zeek sensor ENI, or to an NLB/GWLB endpoint for a sensor fleet. Mirrored packets arrive VXLAN-encapsulated on UDP 4789, and Zeek decodes VXLAN on 4789 by default. Mirror only TCP 443 and other TLS ports to cut cost. Don't truncate packets: the hybrid ClientHello spans two segments. Terraform and CloudFormation are under Full configuration files ([AWS Traffic Mirroring](https://docs.aws.amazon.com/vpc/latest/mirroring/what-is-traffic-mirroring.html)).

<!-- SECTION packaging -->
## Packaging per compute type

| Component | EC2 (appliance or Linux) | ECS / Fargate / EKS | Notes |
|---|---|---|---|
| Vendor NGFW / ADC | Marketplace AMI behind GWLB (NGFW) or NLB (ADC) | — | Pin the OS version that has PQ (table above) in the launch template |
| Squid egress proxy | Debian 13 AMI + `squid-openssl`, systemd unit with `Environment=OPENSSL_CONF=` only if you restrict groups | `Dockerfile.squid` (Debian 13), task definition below, CA key from Secrets Manager | Client leg needs the bump CA in every client trust store |
| Envoy egress | Envoy binary or container on EC2 | `envoyproxy/envoy:v1.40.x`, pinned by digest, config in a ConfigMap | Istio: see {{tab:569dd476-c063}} |
| strongSwan PQ VPN | Alpine 3.24 container with `--cap-add NET_ADMIN --network host`, or a source build of 6.0.2+ on AL2023 with OpenSSL 3.5 | not suitable (needs xfrm and host networking) | Debian 13's 6.0.1 package does not work |
| Zeek sensor | Nitro EC2 receiving Traffic Mirroring (VXLAN 4789) | — | `zeek/zeek:8.0` image, pinned by digest |

The Squid Dockerfile and task definition below come from the tested `squid.conf`. They weren't deployed to AWS (no access), so treat them as a starting point.

<!-- SECTION verify -->
## Verify

1. **Posture:** for each device record the OS version, whether PQ is enabled per leg, and the IKE proposals. Compare against the matrix.
2. **Live test through the device (client leg):** `openssl s_client -connect <vip>:443 -groups X25519MLKEM768 -tls1_3 -brief </dev/null` from an OpenSSL 3.5 host must print `Negotiated TLS1.3 group: X25519MLKEM768`. Through a forward proxy, add `-proxy <proxy>:3128`. A classical client (`-groups X25519`) must still connect, and prints `Peer Temp Key: X25519`.
3. **Server leg:** point the device at a PQ-only origin (`openssl s_server -groups X25519MLKEM768 -tls1_3 -www`). The request must succeed. Point it at a classical-only origin (`-groups X25519`): it must also succeed (fallback).
4. **IPsec:** `swanctl --list-sas` shows `KE1_ML_KEM_768`. FortiOS `diagnose vpn ike gateway list` shows `PQC-KEM (IKE): yes`. libreswan's log shows `addke1=ML_KEM_768`.
5. **Observed signal:** the Zeek `ssl.log` `pq` column, Envoy `%UPSTREAM_TLS_GROUP%`, HAProxy `%[ssl_fc_curve]`, FortiOS `diagnose ips ssl status`. Alert on any `pq=F` to an endpoint you expect to be PQ.

<!-- SECTION pitfalls -->
## Pitfalls and rollback

- **Middleboxes that drop big ClientHellos:** X25519MLKEM768 adds about 1.2 KB, so the ClientHello spans two TCP segments. Old IPS signatures, NFW rules and some load balancers dropped or reset these (FortiOS flow mode before 7.4.6/7.6.1). Test every inline device before you enable PQ on clients.
- **One leg PQ, the other classical:** a decrypting device that is PQ on one side only gives you no end-to-end PQ. Check both legs.
- **Decryption breaks pinning and mutual TLS:** exclude those flows (and AWS SDK traffic to PQ endpoints such as KMS) from decryption so they stay end-to-end PQ.
- **IKE fragmentation:** ML-KEM-768 IKE messages exceed 1,280 bytes. Enable IKEv2 fragmentation (RFC 7383) on both peers; IKE_SA_INIT itself can't be fragmented, which is why ML-KEM goes in IKE_INTERMEDIATE.
- **Distro packages lag:** Debian 13 has strongSwan 6.0.1 with no ML-KEM (Tested). Debian 12 and Ubuntu 24.04 Squid, HAProxy and OpenVPN use OpenSSL 3.0, which has no ML-KEM.
- **Logging gaps:** Squid, F5, NetScaler, Check Point and PAN-OS (not confirmed) don't give you a documented group field. Add a Zeek sensor, or log at the origin.
- **Rollback:** decryption profiles: untick PQC (PAN-OS) or remove the cipher group (F5). IPsec: keep `ke1_none` (strongSwan) or classical proposals in the same proposal list during migration, so a peer without PQ still connects. Squid/Envoy: set `OPENSSL_CONF` or `ecdh_curves` to classical, or set the Envoy runtime flag `envoy.reloadable_features.pqc_default_ecdh_curves: false`.

<!-- SECTION files -->
## Full configuration files

**`/etc/squid/squid.conf`** (Tested, Squid 6.13 / OpenSSL 3.5.7)

```squid
FILE:squid/squid.conf
```

**`Dockerfile.squid`** (not deployed; based on the tested image)

```dockerfile
FILE:squid/Dockerfile.squid
```

**`squid-entrypoint.sh`**

```bash
FILE:squid/squid-entrypoint.sh
```

**`squid-taskdef.json`** (ECS Fargate; not deployed)

```json
FILE:squid/squid-taskdef.json
```

**`/etc/envoy/envoy-egress.yaml`** (Tested, Envoy 1.40.2)

```yaml
FILE:envoy/envoy-egress.yaml
```

**`/etc/swanctl/conf.d/pq.conf`** (Tested, strongSwan 6.0.7 / OpenSSL 3.5.9; replace LOCAL/REMOTE per peer)

```text
FILE:swan/swanctl.conf
```

**`/etc/strongswan.d/zz-log.conf`** (log the selected proposal)

```text
FILE:swan/zz-log.conf
```

**`fortigate-ipsec-pq.conf`** (FortiOS 7.6.5 CLI, Documented; not tested)

```text
FILE:vendor/fortigate-ipsec-pq.conf
```

**`f5-pq.tmsh`** (BIG-IP 17.5.1+, Documented; server-ssl line is our inference)

```text
FILE:vendor/f5-pq.tmsh
```

**`netscaler-pq.cli`** (NetScaler 14.1, Documented)

```text
FILE:vendor/netscaler-pq.cli
```

**`/etc/openvpn/server/pq.conf` excerpt** (OpenVPN 2.6 + OpenSSL 3.5, Documented)

```text
FILE:vendor/openvpn-pq.conf
```

**`/opt/zeek/share/zeek/site/pq-tls.zeek`** (Tested, Zeek 8.0.10); add `@load ./pq-tls` to `local.zeek`

```zeek
FILE:zeek/pq-tls.zeek
```

**`traffic-mirror.tf`** (Terraform; not deployed)

```hcl
FILE:zeek/traffic-mirror.tf
```

**`traffic-mirror.yaml`** (CloudFormation; not deployed)

```yaml
FILE:zeek/traffic-mirror.yaml
```
