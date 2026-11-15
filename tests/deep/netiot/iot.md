# IoT devices

<!-- SECTION what -->
## What decides PQ here

The device's TLS library decides the client side, and the broker decides the server side. On microcontrollers that library is the one compiled into the firmware: Mbed TLS (the FreeRTOS, ESP-IDF and Zephyr default) has no ML-KEM, while wolfSSL has it. On Linux-class devices it is the system OpenSSL, or s2n-tls + AWS-LC bundled inside the AWS CRT that the AWS IoT Device SDKs v2 use. On the server side, **AWS IoT Core offers no PQ security policy**, so device-to-IoT Core connections stay classical whatever the device offers. PQ is achievable today only on hops you control: a self-run broker (Mosquitto, EMQX, HiveMQ), a gateway's uplink to your own endpoints, or a PQ tunnel.

All tests ran on 2026-11-14 in local containers, with no AWS access. The scripts and outputs are under `scratchpad/deep/netiot/` (`mosq/`, `wolf/`).

<!-- SECTION matrix -->
## Status matrix by device class

| Device class | TLS stack (component) | PQ (X25519MLKEM768) | Default on? | Evidence |
|---|---|---|---|---|
| MCU, FreeRTOS + coreMQTT | Mbed TLS 3.6 / 4.x (default transport) | **No** (no ML-KEM through Mbed TLS 4.2.0 / TF-PSA-Crypto 1.2.0) | — | Documented ([ChangeLog](https://raw.githubusercontent.com/Mbed-TLS/mbedtls/development/ChangeLog)) |
| MCU, FreeRTOS + coreMQTT | wolfSSL 5.9.1+ (`transport_wolfSSL.c`) | **Yes** | ML-KEM built by default from 5.9.1; set the key share to be sure | Documented ([ChangeLog](https://raw.githubusercontent.com/wolfSSL/wolfssl/master/ChangeLog.md)); API **Tested** on wolfSSL 5.9.4 (Alpine) |
| MCU, ESP32 (ESP-IDF esp-tls) | Mbed TLS (default) | **No** | — | Documented ([esp-tls](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-reference/protocols/esp_tls.html)) |
| MCU, ESP32 | wolfSSL managed component (registry 5.8.2) | Possible with ML-KEM enabled in `user_settings.h`; the X25519MLKEM768 constant in 5.8.2 not confirmed | No | Documented (registry); not tested on hardware |
| MCU, Zephyr 4.4 | Mbed TLS 4.1 + TF-PSA-Crypto 1.1 | **No** | — | Claimed ([BayLibre](https://baylibre.com/blog/zephyr-v4-4-0/)) |
| MCU, Zephyr | wolfSSL (vendor port) | Claimed | — | Claimed ([wolfSSL](https://www.wolfssl.com/?p=48351)) |
| MCU, AWS IoT Device SDK for Embedded C | follows its transport (Mbed TLS, OpenSSL, wolfSSL) | as the transport | — | Documented (source) |
| Linux device / gateway | OpenSSL 3.5 (Debian 13, Alpine 3.24, AL2023 with policy) | **Yes** | Yes on Debian 13 / Alpine 3.24 | **Tested** (Mosquitto client) |
| Linux device / gateway | OpenSSL 3.0 / 1.1.1 (Debian 12, Ubuntu 24.04, Yocto older than 2025) | No | — | see {{tab:99613846-4046}} |
| Linux, AWS IoT Device SDK v2 (Python, JS, Java, C++) | aws-c-io → s2n-tls + AWS-LC | **Yes** | Yes on Linux (awscrt 0.36.1 `DEFAULT` negotiated PQ) | **Tested** (Python, awscrt 0.36.1) and Documented (aws-c-io source) |
| macOS / Windows hosts with Device SDK v2 | Apple Network framework / SChannel | follows the OS | — | not confirmed; see {{tab:89d3721c-f2a1}} |
| Linux, PKCS#11 / TPM private key with the CRT | s2n with legacy ELB policy | **No** (TLS 1.3 not supported with PKCS#11 in aws-c-io) | — | Documented (aws-c-io source) |
| Greengrass v2 nucleus (Java) | AWS CRT Java (MQTT), JDK (HTTPS) | Likely on Linux (CRT); JDK per {{tab:cd465386-557e}} | — | not confirmed (inferred) |
| Greengrass nucleus lite (C) | system OpenSSL | as OpenSSL (3.5 → yes) | — | Documented (build deps); PQ inferred |
| Android / industrial Android gateways | Conscrypt / BoringSSL | not confirmed | — | see {{tab:89d3721c-f2a1}} |
| OPC UA (UA-SecureConversation) | own security policies | **No** PQ policy (Part 2, 1.05.06) | — | Documented (absence) |
| LoRaWAN | AES-128 session keys, no public-key exchange | not affected by ML-KEM; the network/join-server backhaul is ordinary TLS | — | Documented (spec) |
| Cellular (LTE/5G) | 3GPP | No ML-KEM in NAS/AS yet; study TR 33.703 (Rel-20) | — | Documented ([3GPP](https://www.3gpp.org/technologies/pqc-sa3)) |
| **Server: AWS IoT Core** | AWS | **No** PQ policy (`IoTSecurityPolicy_*` list only; same list for custom domains) | — | Documented ([transport security](https://docs.aws.amazon.com/iot/latest/developerguide/transport-security.html)) |
| Server: Mosquitto 2.0.21 on OpenSSL 3.5.7 | OpenSSL | **Yes** | Yes | **Tested** |
| Server: EMQX | Erlang/OTP ssl | Yes when OTP ssl ≥ 11.5 (preferred from 11.7); EMQX config key not found | ssl 11.7+ | Documented ([OTP ssl notes](https://www.erlang.org/doc/apps/ssl/notes.html)) / Not found (EMQX) |
| Server: HiveMQ | JDK JSSE | follows the JVM (see {{tab:cd465386-557e}}) | per JDK | Not found (HiveMQ docs) |

<!-- SECTION client -->
## Client side (devices)

### Microcontrollers: wolfSSL (the only MCU path to ML-KEM today)

- **Build:** wolfSSL 5.9.1+ builds ML-KEM by default. On older 5.8.x builds, or in `user_settings.h` builds, define `WOLFSSL_HAVE_MLKEM`, `WOLFSSL_SHA3`, `WOLFSSL_SHAKE128`, `WOLFSSL_SHAKE256`, `HAVE_CURVE25519`, `WOLFSSL_TLS13` and `HAVE_SUPPORTED_CURVES`. Drop the sizes you don't need with `WOLFSSL_NO_ML_KEM_512` / `WOLFSSL_NO_ML_KEM_1024`. With configure: `--enable-mlkem` (Claimed in wolfSSL posts). Documented (`examples/configs/user_settings_pq.h`).
- **Code:** after `wolfSSL_new()`, call `wolfSSL_UseKeyShare(ssl, WOLFSSL_X25519MLKEM768)`. This sends the hybrid share in the first ClientHello and avoids a HelloRetryRequest. Set the order with `wolfSSL_CTX_set_groups(ctx, groups, n)` and keep `WOLFSSL_ECC_X25519` / `WOLFSSL_ECC_SECP256R1` after it for fallback. Constants (`wolfssl/ssl.h`): `WOLFSSL_X25519MLKEM768 = 4588`, `WOLFSSL_SECP256R1MLKEM768 = 4587`, `WOLFSSL_SECP384R1MLKEM1024 = 4589`. There is no `WOLFSSL_X25519_ML_KEM_768`.
- **FreeRTOS coreMQTT:** `transport_wolfSSL.c` sets no groups, so the device gets the build's defaults. Add the two calls above in `TLS_FreeRTOS_Connect` after `wolfSSL_new` (patch excerpt under Full configuration files).
- **Memory:** wolfSSL reports ML-KEM-768 at about 32 KB stack and 12 KB heap with the default code, or about 2 KB stack and 27 KB heap with `--enable-smallstack`. These figures were measured on a Raspberry Pi 5, not an MCU. Claimed ([wolfSSL blog](https://www.wolfssl.com/optimizing-post-quantum-algorithm-memory-usage-on-embedded-systems/)). Size the TLS task stack and the receive buffer for a ClientHello of about 1.3 KB and a ServerHello of about 1.2 KB.
- **Test (Tested, wolfSSL 5.9.4, Alpine 3.24 package, `WOLFSSL_HAVE_MLKEM` defined):** `pqclient.c` reached a PQ-only OpenSSL 3.5 server with `group=X25519MLKEM768` and a classical-only server with `group=X25519`. The classical-only variant was refused by the PQ-only server, as expected (3/3).

### Microcontrollers: Mbed TLS, ESP-IDF, Zephyr

No ML-KEM in Mbed TLS or TF-PSA-Crypto as of Mbed TLS 4.2.0 (July 2026). The Trusted Firmware roadmap does ML-DSA first and "then look into ML-KEM". Claimed. ESP-IDF `esp_tls_cfg_t.groups_list` takes only Mbed TLS groups. For PQ on ESP32, switch to the wolfSSL component through `CONFIG_ESP_TLS_CUSTOM_STACK` / `esp_tls_register_stack()`, or use the wolfSSL ESP-IDF examples. Nothing to change for devices that connect only to AWS IoT Core: IoT Core is classical.

### Linux-class devices and gateways: OpenSSL 3.5 and Mosquitto clients

On Debian 13 or Alpine 3.24, `mosquitto_pub` and `mosquitto_sub` offer X25519MLKEM768 first with no options. Mosquitto has no groups option. To restrict or enforce the groups, set `OPENSSL_CONF` for the process. Tested: `mosquitto_pub` reached a PQ-only broker with default settings, and failed with `Error: Protocol error` when `OPENSSL_CONF` limited it to X25519/P-256. For AL2023, Yocto and Buildroot images, follow {{tab:99613846-4046}}.

### AWS IoT Device SDK v2 (Python, JavaScript, Java, C++) via the AWS CRT

On Linux, the CRT uses aws-c-io → s2n-tls + AWS-LC, bundled in the wheel, npm or jar. Current aws-c-io maps the default to a PQ s2n policy (`AWS-CRT-SDK-TLSv1.0-2025-PQ`), and `PQ_DEFAULT` to `AWS-CRT-SDK-TLSv1.2-2025-PQ`. Documented ([aws-c-io source](https://github.com/awslabs/aws-c-io/blob/main/source/s2n/s2n_tls_channel_handler.c)).

| Test (python:3.13-slim-trixie, awsiotsdk 1.31.0, awscrt 0.36.1) | Result |
|---|---|
| `cipher_pref = PQ_DEFAULT` → PQ-only Mosquitto (mTLS) | connected, published |
| `cipher_pref = DEFAULT` → PQ-only Mosquitto | connected (default is already PQ on Linux) |
| `cipher_pref = TLSv1_2_2025_07` (non-PQ) → PQ-only Mosquitto | `AWS_IO_TLS_ERROR_NEGOTIATION_FAILURE` (expected) |
| `PQ_DEFAULT` → normal Mosquitto (classical-capable) | connected |

To make PQ explicit (Python): `opts.cipher_pref = awscrt.io.TlsCipherPref.PQ_DEFAULT` before `ClientTlsContext(opts)`. In C++ the same enum value is `AWS_IO_TLS_CIPHER_PREF_PQ_DEFAULT` on `Aws::Crt::Io::TlsContextOptions` (setter name not verified). Not tested in JS, Java or C++; same aws-c-io underneath. Older awscrt versions have only `PQ_TLSv1_0_2021_05`, which is Kyber round 3 and deprecated. Upgrade instead of selecting it. Against IoT Core the hybrid offer falls back to classical. **PKCS#11/TPM keys:** aws-c-io uses legacy TLS 1.2 ELB policies for custom key operations and refuses TLS 1.3, so those devices get no PQ.

### Greengrass v2, Android, OPC UA, LoRaWAN, cellular

- **Greengrass nucleus (Java):** MQTT to IoT Core goes through aws-crt-java (0.45.0 in the current pom), so PQ is offered on Linux. This is inferred and not confirmed, and IoT Core is classical anyway. Component HTTPS calls follow the JDK ({{tab:cd465386-557e}}). **Nucleus lite** links the system OpenSSL; use an OpenSSL 3.5 base image (Debian 13, Alpine 3.24, or Yocto with OpenSSL 3.5).
- **Android gateways:** whether Conscrypt has X25519MLKEM768 on by default per Android version is not confirmed; see {{tab:89d3721c-f2a1}}.
- **OPC UA:** no PQ SecurityPolicy exists (OPC 10000-2, 1.05.06). To protect OPC UA over untrusted links, carry it in a PQ tunnel: strongSwan 6.0.2+ IPsec or a PQ TLS proxy ({{tab:c2c97bfd-040d}}).
- **LoRaWAN:** AES-128 session keys with no public-key handshake, so ML-KEM doesn't apply on the radio link. The LNS-to-cloud backhaul is ordinary TLS; handle it like any Linux gateway. No LoRa Alliance PQ statement found.
- **Cellular:** 3GPP's PQ transition study is TR 33.703 (Release 20), with no ML-KEM in 5G NAS/AS yet. Protect the IP payload with TLS/IPsec on top.

<!-- SECTION server -->
## Server side (brokers and endpoints)

| Endpoint | PQ setting | Evidence |
|---|---|---|
| AWS IoT Core (default and custom domains) | None. Policies: `IoTSecurityPolicy_TLS13_1_3_2022_10`, `…_TLS13_1_2_2022_10` (default), `…_TLS12_1_2_2022_10`, `…_TLS12_1_0_2016_01`, `…_TLS12_1_0_2015_01`; custom policies unsupported. Not on AWS's PQ readiness page | Documented |
| Mosquitto 2.0/2.1 | No groups option. OpenSSL 3.5 default gives hybrid first with classical fallback; enforce with `OPENSSL_CONF` (`Groups = X25519MLKEM768`, `MinProtocol = TLSv1.3`) in the service environment | **Tested** (Mosquitto 2.0.21, OpenSSL 3.5.7) |
| EMQX 5.x/6.x | Erlang `ssl` option `{supported_groups, [x25519mlkem768, x25519, secp256r1]}` (ssl 11.5+, the OTP-28.4 timeframe). EMQX exposes no documented key for it, so PQ follows the bundled OTP default (preferred from ssl 11.7). Check the release's OTP version | Documented (OTP) / Not found (EMQX key) |
| HiveMQ | Runs on the JVM; PQ follows the JDK (see {{tab:cd465386-557e}} for which Corretto/Temurin builds default to X25519MLKEM768, or the BC JSSE agent). HiveMQ has no documented named-group setting; `-Djdk.tls.namedGroups=X25519MLKEM768,x25519,secp256r1` in `JAVA_OPTS` is the standard JSSE knob | Not found (HiveMQ) |
| Broker behind an NLB | TCP passthrough keeps the broker's TLS (PQ as above). A TLS listener terminates at the NLB, so use a PQ policy there ({{tab:bb21387b-4f66}}) | Documented (ELB) |

Mosquitto results (broker on OpenSSL 3.5.7, `require_certificate true`):

| Test | Result |
|---|---|
| `openssl s_client -groups X25519MLKEM768` → broker | `Negotiated TLS1.3 group: X25519MLKEM768` |
| classical client (`-groups X25519`) → broker | connects, `Peer Temp Key: X25519, 253 bits` |
| `mosquitto_pub` (defaults) → PQ-only broker (`OPENSSL_CONF`) | published |
| `mosquitto_pub` with classical-only `OPENSSL_CONF` → PQ-only broker | refused; broker log `no suitable key share` |

<!-- SECTION packaging -->
## Packaging per compute type

| Where | What to ship |
|---|---|
| MCU firmware | wolfSSL 5.9.1+ with the `user_settings.h` below, plus the `wolfSSL_UseKeyShare` call in the transport; OTA through IoT Jobs. Track the TLS library version as a thing attribute in fleet indexing |
| Linux device / gateway image | Debian 13 or Alpine 3.24 base (OpenSSL 3.5); AWS IoT Device SDK v2 with a current awscrt; `Dockerfile.gateway` below |
| Greengrass | Nucleus lite on an OpenSSL 3.5 OS image; Java nucleus on a JDK with PQ ({{tab:cd465386-557e}}) |
| Self-run broker on EC2 | Debian 13 AMI, `mosquitto` package, systemd drop-in `pq.conf` only if you enforce PQ |
| Self-run broker on ECS/EKS | `Dockerfile.mosquitto` (Debian 13), NLB TCP passthrough on 8883 |

<!-- SECTION verify -->
## Verify

1. **Inventory:** per device model record the TLS library and version, and whether OTA is possible. Store them as thing attributes (`tlsLib=wolfssl-5.9.4`) and query fleet indexing for anything below wolfSSL 5.9.1, OpenSSL 3.5 or the current awscrt.
2. **Broker (PQ-only must succeed):** `openssl s_client -connect broker:8883 -groups X25519MLKEM768 -tls1_3 -cert dev.pem -key dev.key -CAfile ca.pem -brief </dev/null` prints `Negotiated TLS1.3 group: X25519MLKEM768`.
3. **Broker fallback:** the same with `-groups X25519` must still connect (unless you enforce PQ).
4. **Device (client) test:** point a test device at `openssl s_server -accept 8883 -groups X25519MLKEM768 -tls1_3 -cert srv.pem -key srv.key -CAfile ca.pem -Verify 1`. It must complete the handshake. Against `-groups X25519` it must fall back.
5. **Observed signal:** the broker log (`no suitable key share` = a classical client refused in PQ-only mode), a Zeek `ssl.log` `curve` on a mirrored gateway uplink ({{tab:c2c97bfd-040d}}), or `wolfSSL_get_curve_name()` and `s2n_connection_get_kem_group_name()` logged on the device.

<!-- SECTION pitfalls -->
## Pitfalls and rollback

- **IoT Core is classical:** don't block device rollout on PQ to IoT Core. Ship PQ-capable stacks now and enforce on your own brokers and gateways first. Watch the [IoT Core security policies](https://docs.aws.amazon.com/iot/latest/developerguide/transport-security.html) page for a PQ policy.
- **Buffers and stacks:** a hybrid ClientHello is about 1.3 KB and the ServerHello about 1.2 KB. MCU TLS receive buffers of 1–2 KB, `MQTT_NETWORK_BUFFER_SIZE` and task stacks need headroom. Test on real hardware for heap fragmentation and handshake time.
- **HelloRetryRequest:** if the device sends only an X25519 share but lists the hybrid group, a PQ-only server forces an extra round trip. Send the hybrid key share first (`wolfSSL_UseKeyShare`).
- **PKCS#11/secure-element keys:** the CRT path gives no TLS 1.3 and no PQ there. wolfSSL with a crypto callback for the secure element is the alternative.
- **Stale crypto names:** `PQ_TLSv1_0_2021_05` (awscrt) and `WOLFSSL_P521_KYBER_LEVEL5` / Kyber IDs are pre-standard. Servers no longer accept them, so replace them.
- **ESP-IDF registry lag:** the managed wolfSSL component is 5.8.2, older than default-on ML-KEM. Pin a newer wolfSSL or enable ML-KEM in `user_settings.h`, and test.
- **Rollback:** brokers: remove the `OPENSSL_CONF` drop-in (back to hybrid-preferred with classical fallback). Devices: keep X25519/P-256 after the hybrid group in the groups list so that no change is needed to fall back; OTA a config flag that skips `wolfSSL_UseKeyShare` if a model misbehaves.

<!-- SECTION files -->
## Full configuration files

**`user_settings.h`** (wolfSSL, MCU; based on wolfSSL's `examples/configs/user_settings_pq.h`; not built on an MCU here)

```c
FILE:wolf/user_settings.h
```

**`pqclient.c`** (Tested, wolfSSL 5.9.4)

```c
FILE:wolf/pqclient.c
```

**`transport_wolfSSL.c` patch** (FreeRTOS coreMQTT; excerpt to add after `wolfSSL_new`)

```c
FILE:wolf/transport_wolfSSL-pq.patch.c
```

**`/etc/mosquitto/mosquitto.conf`** (complete broker config) (Tested, Mosquitto 2.0.21)

```text
FILE:mosq/mosquitto.conf
```

**`/etc/mosquitto/openssl-pq-only.cnf`** (Tested; enforce PQ for the broker or a client)

```ini
FILE:mosq/openssl-pq-only.cnf
```

**`/etc/systemd/system/mosquitto.service.d/pq.conf`** (EC2 broker; enforce PQ)

```ini
FILE:mosq/mosquitto-pq.dropin.conf
```

**`Dockerfile.mosquitto`** (ECS/EKS broker; not deployed)

```dockerfile
FILE:mosq/Dockerfile.mosquitto
```

**`crt_mqtt_pq.py`** (Tested, awscrt 0.36.1 / awsiotsdk 1.31.0)

```python
FILE:mosq/crt_mqtt_pq.py
```

**`Dockerfile.gateway`** (Linux gateway with Device SDK v2 and Mosquitto clients on OpenSSL 3.5; not deployed)

```dockerfile
FILE:mosq/Dockerfile.gateway
```
