# Java

## Problem statement

Java services on JDK 8 to 21 negotiate classical key exchange only (X25519 or P-256), so traffic recorded today can be decrypted later by a quantum computer. That covers outbound calls to AWS APIs, databases and partners, and any TLS the JVM terminates itself.

**What decides PQ is the JVM's TLS provider (JSSE), not the OS.** Apache HttpClient, OkHttp, the JDK `HttpClient`, `HttpsURLConnection`, JDBC drivers, Kafka, Tomcat, Jetty and Spring Boot all hand TLS to JSSE, so the base image's OpenSSL and crypto policy make no difference to them.

| JDK | PQ by default? | Fix |
| --- | --- | --- |
| 25.0.5 and later, 27 | Yes, client and server, X25519MLKEM768 first (Tested on Corretto and Temurin 25.0.5). SecP256r1MLKEM768 and SecP384r1MLKEM1024 are also supported (Documented, [Oracle 25.0.5 release notes](https://www.oracle.com/java/technologies/javase/25-0-5-relnotes.html), JDK-8314323) | Nothing |
| 25.0.0 to 25.0.4 | No (Documented) | Patch to 25.0.5+ |
| 8, 11, 17, 21 | No: SunJSSE has no ML-KEM group | Kit v2: Bouncy Castle JSSE (BCJSSE) 1.87 as the TLS provider, loaded by `pq-tls-agent.jar`; or move to 25.0.5+ |

Why other pages say "JDK 27": [JEP 527](https://openjdk.org/jeps/527) (hybrid ML-KEM key exchange in TLS 1.3) shipped in JDK 27 (released 2026-09-15), and the AWS SDK guide names only JDK 27 ([AWS SDKs and Tools guide](https://docs.aws.amazon.com/sdkref/latest/guide/pqtls-details.html)). The October 2026 update 25.0.5 carries the same feature as a backport (Documented). Oracle plans PQ TLS for 21 and 17, then 11 and 8 ([Oracle Java blog, 2026-08](https://blogs.oracle.com/java/post-quantum-cryptography-in-long-term-support-jdk-releases)); secondary reports put 21 and 17 in H1 2027 and 11 and 8 in H2 2027. Claimed, not shipped; we could not open Oracle's own table, so the dates are not sure. Remove the kit when your vendor ships it.

Three stacks bypass JSSE, so the JDK version does not matter for them:

- **Netty with `netty-tcnative-boringssl-static`** (`SslProvider.OPENSSL`; gRPC-Java, Reactor Netty or Vert.x with native SSL): BoringSSL decides. PQ by default (Tested 2.0.85 on JDK 17 and 21).
- **AWS SDK for Java v2 CRT client** (`AwsCrtHttpClient`): s2n-tls on Linux decides. PQ by default from SDK 2.35.11 (Documented, [AWS SDKs and Tools guide](https://docs.aws.amazon.com/sdkref/latest/guide/pqtls-details.html); Tested 2.59.1 PQ, 2.35.10 classical). On macOS and Windows it uses the OS TLS library.
- **Tomcat with the OpenSSL implementation** (Tomcat Native or the FFM connector): the linked OpenSSL decides (Tomcat 11.0.29 on OpenSSL 3.5.5 Tested PQ in the Web servers and proxies chapter).

**Certificates and stores do not change.** JKS and PKCS#12 keystores, `cacerts`, `javax.net.ssl.trustStore` and mutual TLS keep working. Under BCJSSE one security property matters: `ssl.KeyManagerFactory.algorithm=PKIX`, which kit v2 sets. Without it BCJSSE cannot use EC certificates, as a server or as an mTLS client (Tested).

## Quick start by compute type

Kit v2 = the `pq-tls/` directory (`pq-tls-agent.jar` v2, `pq-tls.security`, three Bouncy Castle 1.87 jars) plus `JAVA_TOOL_OPTIONS` with both flags. Source: [kit/java-v2](REPO/kit/java-v2). Below, `KIT` stands for `-Djava.security.properties=<dir>/pq-tls/pq-tls.security -javaagent:<dir>/pq-tls/pq-tls-agent.jar`, where `<dir>` is `/var/task` on Lambda and `/opt` elsewhere. **Append** `KIT` to an existing `JAVA_TOOL_OPTIONS`; don't replace it (APM agents live there).

**Java 8 adds two flags.** `-Dorg.bouncycastle.jsse.client.assumeOriginalHostName=true` everywhere: without it every `HttpsURLConnection` handshake fails under BCJSSE. `-Djdk.tls.client.protocols=TLSv1.3,TLSv1.2` on Lambda only: the Lambda Java 8 runtime limits clients to TLS 1.2. The `pq-tls` layer adds both (Tested).

### Clients

| Compute | Check | One change | Verify | Roll back |
| --- | --- | --- | --- | --- |
| Lambda `java8.al2`, `java11`, `java17`, `java21` (zip) | `Runtime` in the function configuration | `pq-tls/` at the zip root and `JAVA_TOOL_OPTIONS=KIT` (Java 8: plus both Java 8 flags). Or the `pq-tls` layer with `AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper` | Log line `pq-tls agent v2: BCJSSE first, groups=X25519MLKEM768,... ssl.KeyManagerFactory.algorithm=PKIX`; CloudTrail `tlsDetails.keyExchange` on the role's KMS or STS calls | Delete the variable, or set `PQ_TLS_DISABLE=1` with the layer; the next cold start is classical |
| Lambda `java25` | `Runtime` = `java25` | Nothing (25.0.5 Tested) | CloudTrail `keyExchange` | n/a |
| Lambda container image (`public.ecr.aws/lambda/java:8.al2023` to `:21`) | Base image tag and digest | `COPY pq-tls/ ${LAMBDA_TASK_ROOT}/pq-tls/` and `ENV JAVA_TOOL_OPTIONS=KIT`; or base `lambda/java:25` and no change | As for zip | Revert the image; a function variable overrides image `ENV` without a rebuild |
| ECS on Fargate | `docker run --rm --entrypoint java <image> -version` | Base image `amazoncorretto:25` or `eclipse-temurin:25` (25.0.5+). Or `COPY pq-tls/ /opt/pq-tls/` and `ENV JAVA_TOOL_OPTIONS=KIT`, or the same variable in the task definition | Startup log line; CloudTrail; your server or egress proxy logs the group | Revert the image tag, or remove the task definition variable |
| ECS on EC2, EKS | As for Fargate | As for Fargate; EKS sets the variable in `spec.containers[].env` | As for Fargate, plus Zeek on mirrored node ENIs | As for Fargate |
| EC2 | `java -version` for the service's own `java` (via SSM) | `dnf install java-25-amazon-corretto-headless` and point the unit at it. Or kit v2 in `/opt/pq-tls/` and a systemd drop-in `Environment="JAVA_TOOL_OPTIONS=KIT"` | `journalctl -u <service> \| grep 'pq-tls agent v2'`; CloudTrail; Zeek | Remove the drop-in, `systemctl daemon-reload`, restart |

Notes, all Tested in e2e unless marked:

- **Lambda zip, static `java.security` registration does not work** (the bootstrap class path is `/var/runtime/lib` only); use the agent.
- **Lambda container image with JDK 8:** the bundled kit needs both Java 8 flags. Tested only with the layer's files in `/opt` plus the wrapper; the bundled form with both flags is Unverified.
- **Containers, JDK 17 and 21, without an agent:** `bc-static.security` plus the BC jars on `-cp` also gives PQ (Tested, Fargate and ECS on EC2).
- **EC2 with several Corretto packages:** on AL2023, `java` on `PATH` resolved to 25 once 25 was installed (`alternatives` picks the highest). Check which binary the unit starts.
- **JDK 8 on ECS on EC2 and on EC2** with the full fix were not run; Fargate JDK 8 was.

### Servers (the JVM terminates TLS)

If an ALB, NLB TLS listener, API Gateway or CloudFront terminates TLS in front of the JVM, set the PQ policy there; the JVM's own TLS matters for the target leg (ALB re-encryption), NLB TCP pass-through and internal services. See the Load balancers chapter.

| Server situation | One change | Verify | Evidence |
| --- | --- | --- | --- |
| JDK 25.0.5+, any certificate | Nothing. One keystore with several certificates for SNI: also add `pq-tls.security` (PKIX), or the wrong certificate is served | `openssl s_client -connect <host>:8443 -tls1_3 -groups X25519MLKEM768 -brief` prints `Negotiated TLS1.3 group: X25519MLKEM768`; `-groups X25519` still connects | Tested |
| JDK 8 to 21, RSA certificate | Kit v2 (Java 8: plus the host-name flag) | As above | Tested (8, 17, 21 in e2e) |
| JDK 8 to 21, **EC certificate** | Kit v2, which sets `ssl.KeyManagerFactory.algorithm=PKIX`. Remove any hard-coded `SunX509` (code or Tomcat `keyManagerAlgorithm`) or every handshake fails | As above, plus `-servername` for each SNI name | Tested 17, 21; JDK 8 and 11 Unverified |
| Any JDK, Netty with tcnative | Nothing | As above | Tested 21 |

## Versions and native support

| Version | TLS stack | PQ client by default? | PQ server by default? | API to set groups | FIPS mode | Proposed solution | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| JDK 25.0.5+ (Corretto, Temurin) | SunJSSE | Yes on every compute type | Yes (Tomcat, Jetty, `HttpsServer`, Netty JDK provider) | `-Djdk.tls.namedGroups`, `SSLParameters.setNamedGroups` (JDK 20+), Tomcat `SSLHostConfig groups` | Not tested | Upgrade. Optional `pq-tls.security` (PKIX) for multi-certificate SNI stores (case C) | Tested (client, server, keystores, mTLS); Documented |
| JDK 21 (21.0.13) | SunJSSE | No | No | `jdk.tls.namedGroups` (no ML-KEM names) | Not tested | Kit v2, or upgrade to 25 | Tested |
| JDK 17 (17.0.21) | SunJSSE | No | No | Same | Not tested | Kit v2, or upgrade | Tested |
| JDK 11 (11.0.33) | SunJSSE | No | No | Same | Not tested | Kit v2 | Tested client (Lambda zip, layer, image; Fargate; EC2 AL2 and AL2023). Server not tested |
| JDK 8 (8u512) | SunJSSE; TLS 1.2 client default on the Lambda Java 8 runtime only (plain Corretto 8u512 offers TLS 1.3) | No | No | Same | Not tested | Kit v2 + host-name flag; on Lambda also the protocols flag | Tested client (Lambda zip, layer, image with layer files; Fargate) and server (Fargate, RSA certificate) |
| Any JDK + Netty tcnative-boringssl-static 2.0.85 | BoringSSL | Yes | Yes | `OpenSslContextOption.GROUPS`; also reads `jdk.tls.namedGroups` | n/a | Nothing | Tested |
| Any JDK + AWS SDK v2 CRT client (2.35.11+) | s2n-tls (Linux) | Yes, AWS API calls only | n/a | n/a | Not tested | Nothing; before 2.35.11, upgrade | Tested 2.59.1; Documented |

### By JDK and compute type

PQ = connected to a PQ-only server; every PQ cell also connected to a classical-only server, so fallback works. Evidence is the LocalStack e2e run r1117041043 (2026-11-16) unless marked; see Test evidence below.

| JDK | Lambda zip | Lambda image | Fargate | ECS on EC2 / EKS | EC2 |
| --- | --- | --- | --- | --- | --- |
| 25.0.5 | PQ, runtime `java25` | PQ, `lambda/java:25` | PQ, `amazoncorretto:25`; AL2023 `dnf` Corretto 25 | PQ, `amazoncorretto:25` | PQ, AL2023 Corretto 25 package |
| 21.0.13 | Classical; kit or layer gives PQ; static registration does not | Classical; kit gives PQ | Classical; kit or static gives PQ (Corretto, Temurin, AL2023 `dnf`) | Classical; kit gives PQ | Classical; kit gives PQ (AL2023) |
| 17.0.21 | Classical; kit or layer gives PQ | Classical; kit gives PQ | Classical; kit or static gives PQ | Static gives PQ; kit not run | Classical; kit gives PQ (AL2, AL2023) |
| 11.0.33 | Classical; kit or layer gives PQ | Classical; kit gives PQ | Classical; kit gives PQ | Not run | Classical; kit gives PQ (AL2, AL2023) |
| 8u512 | TLS 1.2 classical; kit + both Java 8 flags, or the layer, gives PQ | TLS 1.2 classical; layer files + wrapper give PQ | TLS 1.3 classical; kit + host-name flag gives PQ (protocols flag not needed) | Kit without the host-name flag fails every handshake; full fix not run | Not run |

The `pq-egress` Lambda extension also gave PQ on `java8.al2` to `java25` (it originates the TLS itself).

### Decision guide

- JDK 25.0.5 or later: change nothing; look for pins (case F).
- JDK 8 to 21: roll out kit v2 and plan the upgrade to 25.
- Already shipped kit v1 (agent only)? Add the `pq-tls.security` flag or swap in the v2 jar before any JVM with an EC certificate, server or mTLS client, gets it.
- Netty tcnative or the CRT client: those connections are already PQ; everything else in the JVM still needs the kit.
- FIPS JVM: don't add the kit (case G).

## Cases: what to change

Deep tests (marked "Tested" in this section unless an e2e case is named): 2026-11-14, containers on arm64, `eclipse-temurin:17-jre` 17.0.21, `:21-jre` 21.0.13, `:25-jre` 25.0.5, BC 1.87, peers OpenSSL 3.5.7 on `debian:trixie-slim`. "PQ" means OpenSSL printed `Negotiated TLS1.3 group: X25519MLKEM768`; every PQ row also connected with a classical-only peer unless it says PQ-only. Outputs: `tests/deep/java/out/` and `tests/deep/java/v2/out/`.

### A. Simple client (default HTTP client, AWS SDK, JDBC driver, no TLS code)

**Who:** no `SSLContext`, `KeyManager` or `TrustManager` code (`grep -rE 'SSLContext|KeyManagerFactory|TrustManagerFactory|namedGroups' src/` finds nothing). **Today:** classical on 8 to 21, PQ on 25.0.5+. **Change:** nothing in code; JDK 25.0.5+ or kit v2. **Side effects:** the ClientHello grows by about 1.2 KB; BCJSSE becomes the TLS provider for the whole JVM.

| Client | TLS engine | JDK 17 / 21 | 17 / 21 + kit | 25.0.5 | What to keep | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| JDK `HttpClient`, `HttpsURLConnection` | JSSE | No | PQ | PQ | n/a | Tested |
| Apache HttpClient 5.6.5, 4.5.14 | JSSE | No | PQ | PQ | TLS 1.3 in `setTlsVersions`; no `new String[]{"TLSv1.2"}` | Tested |
| OkHttp 4.12.0 | JSSE | No | PQ | PQ | `ConnectionSpec.MODERN_TLS` | Tested |
| Netty 4.2.20, `SslProvider.JDK` | JSSE | No | PQ | PQ | n/a | Tested |
| Netty 4.2.20 + tcnative-boringssl-static 2.0.85 | BoringSSL | **PQ** | PQ | PQ | No classical `jdk.tls.namedGroups` pin (Netty reads it) | Tested |
| AWS SDK 2.59.1 `ApacheHttpClient` | JSSE | No | PQ | PQ | n/a | Tested |
| AWS SDK 2.59.1 `NettyNioAsyncHttpClient` with tcnative | BoringSSL | **PQ** | PQ | PQ | Without tcnative it uses JSSE (not run) | Tested |
| AWS SDK 2.59.1 `AwsCrtHttpClient` (aws-crt 0.50.0) | s2n-tls | **PQ** | PQ | PQ | SDK 2.35.11+ | Tested; Documented |
| AWS SDK 2.35.10 `AwsCrtHttpClient` (aws-crt 0.38.9) | s2n-tls | No | n/a | n/a | Upgrade | Tested |
| PostgreSQL JDBC 42.7.14 to PostgreSQL 18 (`ssl_groups=X25519MLKEM768`) | JSSE | No (21) | PQ (21) | PQ | `sslmode=verify-full` | Tested |
| Static BCJSSE via `java.security`, no agent | BCJSSE | n/a | PQ (17, 21) | n/a | BC jars on the class path | Tested; e2e Fargate and ECS on EC2 |
| Spring `WebClient`, `RestClient`, `RestTemplate`; MySQL Connector/J; Lettuce; Jedis; Kafka client | JSSE (Lettuce: Netty JDK provider by default) | Follow the JDK rows | | | TLS 1.3 allowed (`tlsVersions`, `ssl.enabled.protocols`); Kafka: leave `ssl.provider` empty | Unverified (not run) |

Unverified rows use standard JSSE APIs, so they should follow the JDK rows; run the live test in "How to test" for your build before you rely on them. Server settings for databases, Redis and Kafka brokers are in the Databases and data services chapter.

### B. Simple server (framework default TLS)

**Who:** Spring Boot `server.ssl.*` or an SSL bundle, Tomcat `server.xml`, Jetty, `HttpsServer`, Quarkus or Micronaut terminating TLS in the JVM. **Today:** classical on 8 to 21, PQ on 25.0.5+. **Change:** JDK 25.0.5+, or kit v2 (kit v1 breaks EC certificates, case C). **Side effects:** clients that don't offer ML-KEM still connect (Tested).

| Server | JDK 21 default | JDK 17 / 21 + kit v2 | JDK 25.0.5 default | Evidence |
| --- | --- | --- | --- | --- |
| Tomcat 11.0.29 embedded (JSSE) | Classical | PQ with RSA or EC certificate; EC fails without PKIX | PQ, preferred | Tested |
| Tomcat 11.0.29 `groups="X25519MLKEM768,x25519"` | Classical (name unknown to SunJSSE 21, ignored) | n/a | PQ | Tested |
| Tomcat 11.0.29 `groups="x25519,secp256r1"` | n/a | n/a | Classical (the pin removes it) | Tested |
| Jetty 12.1.15 | Classical | PQ; EC fails without PKIX | PQ | Tested |
| JDK `HttpsServer` | Classical | PQ; EC fails without PKIX | PQ | Tested; e2e target leg (RSA) on 8, 17, 21, 25 |
| Spring Boot 3.5.16 SSL bundle, EC PKCS#12 | Not run | PQ on 21; fails with the agent's PKIX step switched off | Not run | Tested (21 only) |
| Netty 4.2.20 + tcnative-boringssl-static 2.0.85 | **PQ** | n/a | PQ | Tested |
| Netty 4.2.20, JDK provider | Classical | n/a | PQ | Tested on 25 |
| Undertow; Quarkus; Micronaut | Follow the JSSE rows (JDK engine) or the tcnative row (native SSL) | | | Unverified; confirm the engine from the startup log |

**Order of preference for a JVM that terminates TLS:** (1) JDK 25.0.5+; (2) Netty with tcnative on any JDK; (3) JDK 8 to 21 with kit v2; (4) otherwise a PQ-capable proxy in front (nginx or Envoy on OpenSSL 3.5, Web servers and proxies chapter) or an ALB with a PQ policy.

**Group settings by framework:**

- **Spring Boot** has no named-group property (checked against the [4.1.2 SSL reference](https://docs.spring.io/spring-boot/reference/features/ssl.html)); keep `enabled-protocols: [TLSv1.3, TLSv1.2]` in the bundle. To reorder groups, set `-Djdk.tls.namedGroups=X25519MLKEM768,x25519,secp256r1,secp384r1`; embedded Tomcat's `groups` defaults to it. The `TomcatConnectorCustomizer` in the full files is Unverified.
- **Standalone Tomcat:** `SSLHostConfig groups` arrived in 11.0.12 ([Tomcat 11 HTTP connector](https://tomcat.apache.org/tomcat-11.0-doc/config/http.html); Documented) and, per a mirrored changelog, 10.1.48; the 9.0 line is not sure. It defaults to `jdk.tls.namedGroups` and picks only among groups the engine knows. With the OpenSSL implementation it should pass to OpenSSL (not tested). On JDK 17 and 21, `bin/setenv.sh` adds kit v2 through `CATALINA_OPTS`.
- **Jetty, Undertow, `HttpsServer`:** no group setting; they follow the JDK and `jdk.tls.namedGroups`.
- **Netty server** (gRPC-Java, Reactor Netty, Vert.x): `SslContextBuilder.forServer(kmf).sslProvider(SslProvider.OPENSSL)` with tcnative on the class path. When `jdk.tls.namedGroups` is set, Netty uses that list for BoringSSL too, so a classical pin turns PQ off even with tcnative (Tested). Full code: `NettyPq.java`.

**Behind an ALB or NLB TLS listener (e2e):** with the load balancer modelled as the client on the target leg, an `HttpsServer` target with an RSA PKCS#12 keystore stayed classical on Corretto 8 and 21, negotiated X25519MLKEM768 with kit v2 on Corretto 8, 17 and 21 (Fargate; 21 also on ECS on EC2) and with no change on Corretto 25.0.5. With the ALB's classic backend policy every target negotiated classical TLS 1.2.

### C. Existing server certificates in a custom keystore or cert files

**Who:** the JVM loads its own certificate and key. Find it:

```bash
grep -rnE 'javax\.net\.ssl\.keyStore|KeyManagerFactory|KeyStore\.getInstance|certificateKeystore|server\.ssl\.(key-store|bundle)|spring\.ssl\.bundle|keyManagerAlgorithm|setKeyStorePath' \
  src/ conf/ *.yml *.yaml *.properties Dockerfile* helm/ 2>/dev/null
keytool -list -v -keystore server.p12 -storetype PKCS12 | grep -E 'Alias name|Entry type|Signature algorithm|Subject Public Key Algorithm'
```

**What changes in the store: nothing.** Keep the RSA or EC key, PKCS#12 or JKS, aliases, passwords and the system properties that point at the store.

**What to change (JDK 8 to 21 only):** `ssl.KeyManagerFactory.algorithm=PKIX`, shipped in `pq-tls.security` and also set by agent v2 when the value is still the JDK default `SunX509`. The agent fallback covers apps whose own `-Djava.security.properties` replaces the kit's flag (Tested). Code that names `SunX509` must change:

```java
// Fails with an EC certificate under BCJSSE (JDK 8-21 + kit):
KeyManagerFactory kmf = KeyManagerFactory.getInstance("SunX509");
// Works everywhere, and picks up the kit's PKIX default:
KeyManagerFactory kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
// Tomcat server.xml: drop keyManagerAlgorithm="SunX509", or set keyManagerAlgorithm="PKIX"
```

Why: BCJSSE asks the key manager for key type `EC/secp256r1`, and SunJSSE's `SunX509` key manager returns no alias for it. RSA keys never needed the fix (BC asks for `RSA`, which SunX509 answers).

**Tested proof** (`tests/deep/java/v2/out/t17-v2kit.txt`, `t21-v2kit.txt`, `t17-v1nofix.txt`, `t21-v1nofix.txt`, `t25-none.txt`, `t25-file.txt`, `tomcat-sb.txt`):

| Keystore situation | JDK 17/21 + kit v1 | JDK 17/21 + kit v2 | JDK 25.0.5, no kit |
| --- | --- | --- | --- |
| EC P-256 only, PKCS#12 | **Fails** (handshake_failure, also for classical clients) | PQ; classical client connects | PQ |
| RSA only, PKCS#12 | PQ | PQ | PQ |
| RSA + EC in one PKCS#12 | PQ, always serves RSA | PQ, serves EC; a client offering only RSA signature algorithms gets RSA | PQ, serves EC |
| Two EC certificates, SNI per host name | **Fails** | PQ, right certificate per SNI name | PQ, but **SNI ignored** (served `alt-host`'s certificate for `ks-java`); with `pq-tls.security`: right certificate per name |
| EC in a legacy JKS | **Fails** | PQ | PQ |
| Store from `-Djavax.net.ssl.keyStore*` | **Fails** | PQ | PQ |
| App passes its own `-Djava.security.properties` | **Fails** | PQ (agent v2 fallback) | PQ |
| Code hard-codes `KeyManagerFactory.getInstance("SunX509")` | **Fails** | **Still fails**: change the code | PQ |
| Tomcat 11.0.29 default `keyManagerAlgorithm` (EC) | Fails | PQ | PQ |
| Tomcat `keyManagerAlgorithm="SunX509"` (EC) | Fails | **Still fails** | Not run |
| Tomcat `keyManagerAlgorithm="PKIX"`, kit fix switched off | n/a | PQ (explicit PKIX is enough) | Not run |
| Spring Boot 3.5.16 `spring.ssl.bundle.jks`, EC PKCS#12 (JDK 21) | Fails | PQ; classical client connects | Not run |

- **Spring Boot SSL bundles** call `KeyManagerFactory.getDefaultAlgorithm()` (`SslManagerBundle`, `DefaultSslManagerBundle`, checked with `javap`), so the kit property reaches them; `key.alias` still selects the alias.
- **PEM pairs** (`spring.ssl.bundle.pem`, Tomcat `certificateFile`) become an in-memory keystore with the same key manager, so the same rule applies. Not run separately. Separate JKS key passwords go through the same `KeyManagerFactory.init`; not run separately.
- **BC is stricter on chains:** it applies the client's `signature_algorithms` to the whole chain. A client offering only `rsa_pss_rsae_sha256` was refused an RSA certificate whose CA signed with PKCS#1; adding `rsa_pkcs1_sha256` fixed it (`tests/deep/java/ks/`). Modern clients offer both.
- **Side effects:** an RSA + EC store starts serving EC under kit v2 (check client pins, case I). On JDK 25, PKIX also turns on SNI-based certificate selection.

### D. Custom CA trust (private CA)

**Who:** `grep -rnE 'javax\.net\.ssl\.trustStore|TrustManagerFactory|X509TrustManager|truststore|trust-store|keytool .*-importcert|cacerts' src/ conf/ Dockerfile* helm/ *.yml *.yaml *.properties`

**What to change: nothing, on any JDK.** BCJSSE uses the JDK's trust settings: `javax.net.ssl.trustStore*` when set, else `jssecacerts` or `cacerts`. `ssl.TrustManagerFactory.algorithm` stays `PKIX`; the kit doesn't touch it.

| Trust setup (PQ-only OpenSSL 3.5 server, private-CA certificate) | JDK 17/21 + kit | JDK 25.0.5 | Evidence |
| --- | --- | --- | --- |
| No private CA configured | Fails `certificate_unknown(46)` (correct) | Fails `PKIX path building failed` (correct) | Tested; e2e `java-lambda-j21-sysprops-notrust-bundled` |
| `-Djavax.net.ssl.trustStore=trust.p12` (+ password, type) | PQ | PQ | Tested; e2e Lambda `sysprops` cases |
| App's own `TrustManagerFactory` from a truststore | PQ | PQ | e2e (the probe does this in every case) |
| CA imported into `cacerts` with `keytool -importcert -cacerts` | PQ | Not run | Tested (JDK 21) |

Spring bundle truststores use `TrustManagerFactory.getDefaultAlgorithm()` (javap), so trust is the same. A custom `X509TrustManager` is called by BCJSSE as by SunJSSE (not run; trust-all code is a finding in its own right). Netty tcnative and the CRT client take their own trust inputs; neither was run with a private CA.

### E. Mutual TLS (client certificates)

**Who:** `grep -rnE 'clientAuth|client-auth|certificateVerification|setNeedClientAuth|setWantClientAuth'`, or a client loading its own certificate with `-Djavax.net.ssl.keyStore` or a `KeyManagerFactory`.

**Today with kit v1 (or a hard-coded `SunX509`):** a JVM client with an **EC** client certificate silently sends **no certificate**, and the server answers `certificate_required(116)`. RSA client certificates work. **Change:** kit v2; no change to client or server stores.

| Direction (kit v2 on 17 and 21; JDK 25 without a kit gives the same) | Result | Evidence |
| --- | --- | --- |
| JVM client, EC client certificate, to a PQ mTLS server | PQ; server verified the certificate | Tested; e2e Lambda, Fargate and EC2 `*-ec` cases |
| Same with kit v1 behaviour, or code naming `SunX509` | mTLS refused; RSA certificate with `SunX509` still works | e2e `java-lambda-j21-ks-ec-v1`, `-j17-ks-ec-sunx509`, `-j17-ks-rsa-sunx509` |
| Function passes its own `-Djava.security.properties` (layer) | PQ, EC mTLS works (agent v2 sets PKIX) | e2e `java-lambda-j21-layer-ownsec`, `-j11-layer-ownsec` |
| BCJSSE server, `needClientAuth`, EC or RSA client certificate | PQ; server logged the client CN | Tested |
| Same server, no client certificate, or one from an unknown CA | Refused (correct) | Tested |
| BCJSSE PQ-only server (`jdk.tls.namedGroups=X25519MLKEM768`), X25519-only client | Refused (correct) | Tested |

**Side effect:** a harmless `Broken pipe` after the response when the server closes first (test artefact).

### F. Explicit TLS settings that block PQ

**Who:** run `ci/java-pq-check.sh` (full file below), or:

```bash
grep -rnE 'jdk\.tls\.namedGroups|setNamedGroups|groups="|OpenSslContextOption\.GROUPS|SSLContext\.getInstance\("TLSv1\.2"\)|TLS\.V_1_2|protocols="TLSv1\.2"|enabled-protocols|ssl\.enabled\.protocols|tlsVersions|jdk\.tls\.client\.protocols|KeyManagerFactory\.getInstance\("SunX509"|keyManagerAlgorithm' .
```

| Setting | Effect | Change to |
| --- | --- | --- |
| `jdk.tls.namedGroups` without `X25519MLKEM768` | Classical on every JDK including 25, and for Netty tcnative. The agent leaves an existing value alone (e2e `java-lambda-j25-pin`, `-j21-layer-pin`) | `X25519MLKEM768,x25519,secp256r1,secp384r1` |
| Tomcat `groups="x25519,secp256r1"` | Classical on 25 (Tested) | Add `X25519MLKEM768` first |
| `SSLContext.getInstance("TLSv1.2")`, `TLS.V_1_2` only, `enabled-protocols: [TLSv1.2]`, Kafka `ssl.enabled.protocols=TLSv1.2`, Connector/J `tlsVersions=TLSv1.2` | No TLS 1.3, so no ML-KEM | `"TLS"`, or `TLSv1.3,TLSv1.2` |
| `KeyManagerFactory.getInstance("SunX509")`, Tomcat `keyManagerAlgorithm="SunX509"` | EC certificates fail under BCJSSE (Tested) | `getDefaultAlgorithm()` or `"PKIX"` |
| `-Djava.security.properties==file` (double `=`) | Replaces all of `java.security`; the kit line is lost | Single `=`, or add the line to that file |
| Cipher lists (`ciphers=`, `setEnabledCipherSuites`) | No effect if a TLS 1.3 suite stays | Keep at least one TLS 1.3 suite |

Library fixes, one line each (full code in "Netty and AWS SDK code" below):

| Library | Change |
| --- | --- |
| Any JSSE client | `SSLContext.getInstance("TLS")`, not `"TLSv1.2"` |
| Apache HttpClient 5 custom strategy | `.setTlsVersions(TLS.V_1_3, TLS.V_1_2)` |
| Netty with BoringSSL | `.sslProvider(SslProvider.OPENSSL)`; the `OpenSslContextOption.GROUPS` list is optional |
| AWS SDK v2 | `.httpClient(AwsCrtHttpClient.create())` on 2.35.11+. Before 2.35.11 the builder needed `.postQuantumTlsEnabled(true)` ([AWS Security Blog](https://aws.amazon.com/blogs/security/ml-kem-post-quantum-tls-now-supported-in-aws-kms-acm-and-secrets-manager)); upgrade instead. Covers AWS calls only |

| JVM flag | Effect |
| --- | --- |
| `-Djdk.tls.namedGroups=X25519MLKEM768,x25519,secp256r1,secp384r1` | Group order; a list without `X25519MLKEM768` turns PQ off on 25 and for tcnative (Tested) |
| `-Djdk.tls.client.protocols=TLSv1.3,TLSv1.2` | Required on the Lambda Java 8 runtime (it sets `TLSv1.2,TLSv1.1,TLSv1`, and BCJSSE honours it: e2e `java-lambda-j8-bundled-noproto` stays TLS 1.2); not needed on Corretto 8u512 elsewhere |
| `-Dorg.bouncycastle.jsse.client.assumeOriginalHostName=true` | Java 8 with BCJSSE: JDK 8's `HttpsURLConnection` opens the socket without a host name and BCJSSE (1.78+, after [CVE-2024-34447, bc-java#1656](https://github.com/bcgit/bc-java/issues/1656)) then fails endpoint identification. JDK 11+ not affected |
| `-javaagent:<dir>/pq-tls-agent.jar` | JDK 8 to 21: BCJSSE first + PQ-first group list |
| `-Djava.security.properties=<dir>/pq-tls.security` | Kit v2: the PKIX key manager |
| `-Djava.security.properties=<dir>/bc-static.security` | Static BC registration (containers and EC2, not Lambda); includes the PKIX line |

### G. FIPS mode

**Who:** `bc-fips`/`bctls-fips`, `BouncyCastleFipsProvider` in `java.security`, a vendor FIPS JDK, or Corretto/RHEL with the OS in FIPS mode (`/proc/sys/crypto/fips_enabled` = 1). **Today:** not tested. **Change:** don't add the kit: it puts non-FIPS `bcprov`/`bctls` first. Whether `bctls-fips` offers X25519MLKEM768 is not sure: the [BC FIPS 2.1 release notes](https://support.keyfactor.com/hc/en-us/articles/53287242078619-Bouncy-Castle-Java-FIPS-2-1-X-release-notes) we found cover `bc-fips` and do not mention hybrid TLS groups. Track JDK 25 with your FIPS provider and compliance team. The PKIX key-manager point is Unverified for `bctls-fips`. For AWS API calls use the FIPS endpoints; PQ on them depends on the service (AWS service endpoints chapter).

### H. Libraries with their own TLS stack, and agents

| Library | Stack | Kit effect | What to do | Evidence |
| --- | --- | --- | --- | --- |
| Netty + tcnative-boringssl-static 2.0.85 (gRPC-Java, Reactor Netty, Vert.x/Quarkus native, Lettuce with OpenSSL) | BoringSSL | None | Nothing; don't pin `jdk.tls.namedGroups` without ML-KEM | Tested |
| AWS SDK v2 CRT client | s2n-tls | None | SDK 2.35.11+ | Tested; Documented |
| AWS SDK v2 Apache, UrlConnection, Netty without tcnative; JDBC; Kafka; Jedis | JSSE | Applies | Follow the JDK row; keep TLS 1.3 allowed | Tested (Apache, PostgreSQL); others Unverified |
| APM agents (Datadog, New Relic, OpenTelemetry) | JSSE for exporters | Share `JAVA_TOOL_OPTIONS` | Append the kit, don't replace the variable | Not run |
| Conscrypt, wolfJSSE | Own JSSE provider | The one at position 1 wins | Check `Security.getProviders()` order at startup | Not run |
| Amazon Corretto Crypto Provider (ACCP) | JCA provider, not JSSE | No conflict expected | Check provider order | Unverified |
| Tools the JVM shells out to (`curl`, `git`, `wget`) | Their own libraries | n/a | GnuTLS builds have no ML-KEM; OpenSSL 3.5 builds do (Hosts and OS chapter) | Tested in that chapter |

### I. Certificate pinning, HSM/PKCS#11 and KMS-backed keys

- **Client pins** (OkHttp `CertificatePinner`, custom trust managers) keep working: the kit doesn't change what the peer serves. Exception: a **server** with RSA and EC in one store serves EC under kit v2 (case C), which breaks clients pinning the RSA leaf. Pin the CA or both keys first, or keep one key type per store.
- **PKCS#11/HSM keys** (SunPKCS11, CloudHSM JCE): BCJSSE signs through the `PrivateKey`, so the key must work through JCA `Signature`. Not tested; test on the real HSM, or terminate at an ALB/NLB with an ACM certificate, or move to JDK 25.
- **ACM and KMS keys** can't back a JVM `KeyManager`; terminate at the AWS front door. ACM exportable certificates are ordinary keystores (case C).

### J. Other cases

- **HTTPS proxy** (`https.proxyHost`, SDK `HTTPS_PROXY`): with CONNECT, TLS is end to end, so the JVM and origin decide; a TLS-inspecting proxy decides itself (Network devices and egress chapter). Not run.
- **HTTP/2, gRPC, WebSockets** use the same handshake; gRPC-Java uses Netty (case H).
- **Service mesh sidecar:** if the app speaks plain HTTP to the sidecar, the mesh decides (Service mesh chapter).
- **Lambda SnapStart:** the agent runs before the snapshot, so the provider order should be captured in it. Not tested.
- **Session resumption and 0-RTT** under BCJSSE: not tested.

## Solution and automation

1. **Inventory.** JDK per workload (`java -version` in the image or on EC2, Lambda `Runtime`, ECR image labels). Kit presence: `JAVA_TOOL_OPTIONS` containing `pq-tls-agent.jar` **and** `pq-tls.security`; on a running JVM, `jcmd <pid> VM.system_properties | grep -E 'java.version|jdk.tls.namedGroups|java.security.properties'`. Keystore key types (case C), mTLS (case E), blocking settings (CI check). Traffic: CloudTrail `tlsDetails.keyExchange`.
2. **Change.** JDK 25.0.5+ where you can; elsewhere kit v2 (Quick start). Kit v1 deployments: add the `pq-tls.security` flag or swap the jar. Fix code from case F.
3. **Package per compute type** (full files below):

| Compute | JDK 25.0.5+ | JDK 8 to 21: kit v2 | JDK 17 and 21: static `java.security` |
| --- | --- | --- | --- |
| Lambda zip | Runtime `java25` | `pq-tls/` at the zip root, `JAVA_TOOL_OPTIONS=KIT` (`/var/task`) | Doesn't work (e2e `java-lambda-j21-static`) |
| Lambda layer | Not needed (the wrapper makes no change on 25) | `pq-tls` layer v2 + `AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper`; the wrapper adds `pq-tls.security` unless the function passes its own security file, and the Java 8 flags on `java8*` | Doesn't work |
| Lambda container image | `public.ecr.aws/lambda/java:25` | `COPY pq-tls/ ${LAMBDA_TASK_ROOT}/pq-tls/` + `ENV JAVA_TOOL_OPTIONS=KIT` | Not tested |
| Fargate, ECS on EC2, EKS | `amazoncorretto:25`, `eclipse-temurin:25` | `COPY pq-tls/ /opt/pq-tls/` + `ENV JAVA_TOOL_OPTIONS=KIT`, or the task definition or pod spec | `bc-static.security` + BC jars on `-cp` (e2e, including an EC client certificate) |
| EC2 | `dnf install java-25-amazon-corretto-headless` | systemd drop-in, or the SSM document | Same file via `ExecStart` |

Rules everywhere:

- Append to `JAVA_TOOL_OPTIONS`; distroless images work too (the JVM reads the variable itself).
- `java -jar` ignores `-cp`: for static registration, use the manifest `Class-Path` or `-cp ... MainClass`.
- Pin images by digest and record the JDK patch level; the PQ default arrived in a patch release (25.0.5).
- If the app passes its own `-Djava.security.properties` on the command line, that wins over the kit's flag; agent v2 then sets PKIX itself (Tested), or add the line to the app's file.
- If the app ships its own Bouncy Castle, the agent's 1.87 jars load first on the system class path; align versions.

4. **CI guardrail.** `ci/java-pq-check.sh <repo>` ([kit/java-v2/ci/java-pq-check.sh](REPO/kit/java-v2/ci/java-pq-check.sh)) fails on group pins without ML-KEM, TLS 1.2-only pins, a hard-coded `SunX509` and `java.security.properties==`; it warns on JDK below 25, kit v1 packaging, tcnative/CRT/Conscrypt and FIPS providers. Tested on a fixture: 3 FAIL + 2 WARN on the bad tree (exit 1), 1 WARN on the good one (exit 0), `tests/deep/java/v2/out/ci-check.txt`. Add a registry or admission rule: JDK below 25 without the kit is non-compliant.
5. **Fleet rollout:** see the Rollout checklist.

## How to test

1. **Posture.** `java -version`; startup log `Picked up JAVA_TOOL_OPTIONS: -Djava.security.properties=.../pq-tls.security -javaagent:...` and `pq-tls agent v2: BCJSSE first, groups=X25519MLKEM768,..., ssl.KeyManagerFactory.algorithm=PKIX`. `...=SunX509` means the fix is switched off.
2. **Client, local.** Start a PQ-only and a classical-only OpenSSL 3.5 server (`openssl s_server -tls1_3 -groups X25519MLKEM768` and `-groups X25519`, or nginx `ssl_ecdh_curve X25519MLKEM768` with `$ssl_curve` in the log format). Run your client image against both; both must succeed.
3. **Server.** `openssl s_client -connect <host>:8443 -tls1_3 -groups X25519MLKEM768 -brief` must print `Negotiated TLS1.3 group: X25519MLKEM768`; `-groups X25519` must still connect.
4. **Your keystore (case C).** Start the server with a copy of your real store under kit v2, run step 3 with `-servername <each SNI name>` and check the `Peer certificate` CN. For RSA + EC stores also run `-sigalgs rsa_pss_rsae_sha256:rsa_pkcs1_sha256`.
5. **Your truststore (case D).** Against a PQ-only server with a private-CA certificate: connects with your truststore, fails without it.
6. **mTLS (case E).** Server: `openssl s_client ... -cert client.crt -key client.key -groups X25519MLKEM768` connects and is refused without `-cert`. Client: against `openssl s_server -tls1_3 -groups X25519MLKEM768 -Verify 1 -CAfile ca.crt`, the server log shows `depth=0 CN=<your client cert>`.
7. **In AWS.** CloudTrail `tlsDetails.keyExchange = X25519MLKEM768` on the role's KMS, STS, IAM, Secrets Manager, ACM and Payment Cryptography calls; for servers, the load balancer or peer logs the group.
8. **Rollback.** Remove the flags (or `PQ_TLS_DISABLE=1` with the layer) and restart: step 2 against the PQ-only server must now fail and the classical one still work.

Handshake traces: SunJSSE `-Djavax.net.debug=ssl:handshake` shows the `key_share` group; BCJSSE logs through `java.util.logging` at `FINE` on `org.bouncycastle.jsse`. The harness for cases C to E is `run-v2.sh` (full file below).

## Rollout checklist

| # | Step | Done when |
| --- | --- | --- |
| 1 | Inventory every JVM: JDK patch level, compute type, `JAVA_TOOL_OPTIONS`, existing agents | Each workload has a row in the inventory |
| 2 | Classify: 25.0.5+ (nothing), 8 to 21 (kit v2 or upgrade), FIPS (exception), Netty tcnative / CRT only (already PQ for those calls) | Each row has a target |
| 3 | Find EC keystores, mTLS client certificates, hard-coded `SunX509`, group and TLS 1.2 pins (case C, E, F greps; CI check) | CI check passes, or findings fixed |
| 4 | Check RSA + EC stores for client pinning (case I); test PKCS#11/HSM keys on the real HSM | Owners confirmed |
| 5 | Java 8: both flags on Lambda, the host-name flag elsewhere | Present in IaC |
| 6 | Ship kit v2 (never v1) through the shared build template; append to `JAVA_TOOL_OPTIONS` | Startup log shows `algorithm=PKIX` |
| 7 | Canary one task, pod, alias (10% weighted) or instance per service | No new `handshake_failure`, `certificate_required` or `certificate_unknown` errors; ALB `TargetTLSNegotiationErrorCount` flat |
| 8 | Run "How to test" steps 2 to 6 against the canary | All pass |
| 9 | Widen dev → qa → prod | Dashboards show the workload's AWS calls as `X25519MLKEM768` |
| 10 | Plan the move to JDK 25.0.5+ and remove the kit after it | Kit removed; CI check has no JDK warning |
| 11 | Lambda Java on Amazon Linux 2 (`java8.al2`, `java11`, `java17`): move before AWS blocks updates on 2027-08-31 | Runtime upgraded |

## Pitfalls and rollback

| Pitfall | Effect | Avoid it |
| --- | --- | --- |
| Kit v1 (agent only) | Every EC server certificate fails; EC client certificates silently not sent (Tested; e2e `java-lambda-j21-ks-ec-v1`) | Kit v2 only |
| Hard-coded `SunX509` (code or Tomcat) | Beats the kit; EC fails (Tested; e2e `-j17-ks-ec-sunx509`) | `getDefaultAlgorithm()` or `PKIX`; CI check |
| A pinned `jdk.tls.namedGroups` | Classical on any JDK, 25 included; the agent leaves it alone (e2e) | Add `X25519MLKEM768` first; grep launch scripts, Helm values, `JAVA_TOOL_OPTIONS` |
| TLS 1.2 pins | No ML-KEM | Allow TLS 1.3 (case F) |
| Java 8 without the host-name flag | Every `HttpsURLConnection` handshake fails, PQ and classical (e2e) | Add `assumeOriginalHostName=true` |
| Java 8 on Lambda without the protocols flag | Stays classical TLS 1.2 (e2e) | Add `jdk.tls.client.protocols=TLSv1.3,TLSv1.2`, or use the layer |
| JDK 25 multi-certificate store | SunX509 ignores SNI and serves the wrong certificate (Tested) | `pq-tls.security` (PKIX) on 25 too |
| Served certificate type changes | RSA + EC stores serve EC under kit v2 | Check client pins |
| BC chain strictness | RSA-PSS-only clients refused a PKCS#1-signed chain | Modern clients offer both |
| BCJSSE is the provider for the whole process | Untested areas: PKCS#11 keys, session resumption, FIPS | Test before rollout |
| Another agent reorders providers or replaces `SSLContext.getDefault()` | Undoes the kit | Check the startup log and provider order |
| FIPS JVM | Non-FIPS provider put first | Don't add the kit |
| PQ-only server too early | Classical clients fail (expected) | Enforce only when logs show no classical clients |
| Larger ClientHello (about 1.2 KB more) | Middleboxes that mishandle a split ClientHello break the first flight; Java doesn't retry classical | Test through the real network path |

**Rollback.** Remove both `-Djava.security.properties=.../pq-tls.security` and `-javaagent:` from `JAVA_TOOL_OPTIONS` and restart (removing only the agent leaves the harmless PKIX property). Lambda: delete the variable, or `PQ_TLS_DISABLE=1` with the layer (e2e `java-lambda-j21-layer-disabled`: classical); the next cold start is classical. JDK 25: `-Djdk.tls.namedGroups=x25519,secp256r1,secp384r1` (e2e `java-lambda-j25-pin`). CRT client: swap back to `ApacheHttpClient`.

## Test evidence

The LocalStack e2e suite, run r1117041043 (2026-11-16, LocalStack Pro on arm64, not real AWS), ran **96 Java client cases and 7 load balancer target cases; all 103 passed**. Pass means the observed behaviour matched the case's expectation, which for a baseline case is "classical". Cases: [e2e/cases/java.py](REPO/e2e/cases/java.py). Client: [e2e/clients/java/Probe.java](REPO/e2e/clients/java/Probe.java), an app with its own `SSLContext`, truststore and client keystore over `HttpsURLConnection`, compiled for Java 8, with no PQ settings in code. Server: [e2e/clients/server/java/Server.java](REPO/e2e/clients/server/java/Server.java) (`HttpsServer`, RSA PKCS#12, default key manager). Build and pinned images: [e2e/build/java.sh](REPO/e2e/build/java.sh). Results: [e2e/results/latest/summary.md](REPO/e2e/results/latest/summary.md).

Each client case connects to eight listeners: hybrid, PQ-only, mTLS, EC server certificate, TLS 1.2-only and three ML-DSA listeners.

| Compute | Cases | What it proved |
| --- | --- | --- |
| Lambda zip, `java8.al2` to `java25` | 46 | Baselines: classical on 8 to 21 (TLS 1.2 on 8), PQ on 25. Kit v2 in the zip and the `pq-tls` layer: PQ on 8 to 21, including EC client certificates via own `SSLContext` and via `-Djavax.net.ssl.*`. Java 8: PQ only with both flags. Negative and regression: kit v1 behaviour and hard-coded `SunX509` drop EC mTLS; group pins stay classical; `PQ_TLS_DISABLE=1` rolls back; no private CA fails; static registration doesn't work. `pq-egress` extension: PQ on every runtime |
| Lambda container image, `lambda/java:8.al2023` to `:25` | 11 | Baselines classical on 8 to 21, PQ on 25; `Dockerfile.lambda` kit PQ on 11, 17, 21; JDK 8 PQ with the layer files and wrapper |
| ECS on Fargate | 21 | Corretto 8 to 21 and AL2023 `dnf` Corretto classical, 25 PQ; kit v2 via task definition or image `ENV` PQ on 8, 11, 17, 21 (8 needs the host-name flag, not the protocols flag); static registration PQ on Corretto 17 and 21 and Temurin 21, including an EC client certificate |
| ECS on EC2 | 5 | Corretto 21 classical, 21 + kit PQ, 25 PQ, 17 static PQ; JDK 8 without the host-name flag fails |
| EC2 (AL2023 and AL2) | 13 | Corretto 11, 17, 21 classical and PQ with kit v2 (EC client certificate on 21); 25 PQ; the default `java` resolved to 25 |
| Load balancer target leg (server) | 7 | Fargate: Corretto 8 and 21 classical, 8, 17, 21 + kit v2 PQ, 25 PQ; ECS on EC2: 21 + kit PQ. ALB classic backend policy: classical TLS 1.2 on all |

Across all client cases: every working client still connected to the TLS 1.2-only listener (classical fallback); against a dual-certificate server every Java client received **ECDSA**, and the ML-DSA-only listeners refused all of them. No JDK negotiates ML-DSA in TLS yet.

**Not tested in e2e:** real AWS; JDK 8 with the full fix on ECS on EC2 and EC2; JDK 11 servers; servers with EC certificates (the deep tests cover them on 17, 21 and 25); Temurin 25 (deep tests only); FIPS; SnapStart; PKCS#11. Earlier deep tests (libraries, servers, keystores, CRT versions) are in [tests/deep/java](REPO/tests/deep/java), with outputs in `out/` and `v2/out/`.

## Full configuration files

Every file the sections above excerpt, complete. Keep the `pq-tls/` directory name: the agent's manifest finds its jars next to it. The kit is for JDK 8 to 21 only; remove it when the JDK reaches 25.0.5 or later. Files changed in v2 are given in full below. Unchanged files are moved from the old section.

The test scripts and raw output behind every "Tested" label are in `tests/deep/java/` (`run-clients.sh`, `run-servers.sh`, `run-aws.sh`, `run-static-pg.sh`, `out/*.txt`) and, for kit v2, `tests/deep/java/v2/` (`run-v2.sh`, `run-tomcat-sb.sh`, `out/*.txt`).

### Kit v2 (agent, security file, build)

`pq-tls-agent/src/PqTlsAgent.java` (v2)

```java
import java.security.Provider;
import java.security.Security;

// pq-tls agent v2 (JDK 8 to 21). Load with -javaagent:<dir>/pq-tls-agent.jar, usually via JAVA_TOOL_OPTIONS.
// Agent jars and their manifest Class-Path are on the SYSTEM class path, so the Bouncy Castle providers are
// visible to the JDK's provider lookup without touching application code.
//  1. BCJSSE goes first, so SSLContext.getInstance("TLS") and SSLContext.getDefault() use it. The BC JCA
//     provider is added LAST, so every other crypto lookup keeps resolving to the JDK providers.
//  2. jdk.tls.namedGroups gets a PQ-first list, unless the process already set one.
//  3. NEW in v2: ssl.KeyManagerFactory.algorithm=PKIX. BCJSSE asks the key manager for key types such as
//     "EC/secp256r1"; the JDK default factory (SunX509) answers with no alias for them, so EC server and
//     client certificates are never selected and every handshake that needs one fails. PKIX makes
//     KeyManagerFactory.getDefaultAlgorithm() return a factory that BCJSSE serves itself.
//     The kit also ships pq-tls.security with the same line; this is the fallback for processes whose own
//     -Djava.security.properties replaces the kit's file. A value other than SunX509 is left alone.
//     -Dpq.tls.keyManagerAlgorithm=keep disables this step; any other value replaces PKIX.
public class PqTlsAgent {
    public static void premain(String args) {
        Provider bc = new org.bouncycastle.jce.provider.BouncyCastleProvider();
        Security.addProvider(bc);
        Security.insertProviderAt(new org.bouncycastle.jsse.provider.BouncyCastleJsseProvider(bc), 1);
        if (System.getProperty("jdk.tls.namedGroups") == null) {
            System.setProperty("jdk.tls.namedGroups", "X25519MLKEM768,x25519,secp256r1,secp384r1");
        }
        String want = System.getProperty("pq.tls.keyManagerAlgorithm", "PKIX");
        String cur = Security.getProperty("ssl.KeyManagerFactory.algorithm");
        if (!"keep".equalsIgnoreCase(want) && (cur == null || cur.equalsIgnoreCase("SunX509"))) {
            Security.setProperty("ssl.KeyManagerFactory.algorithm", want);
        }
        System.err.println("pq-tls agent v2: BCJSSE first, groups=" + System.getProperty("jdk.tls.namedGroups")
                + ", ssl.KeyManagerFactory.algorithm=" + Security.getProperty("ssl.KeyManagerFactory.algorithm"));
    }
}
```

`pq-tls/pq-tls.security` (new in v2)

```properties
# pq-tls kit: security properties for JDK 8 to 21 with Bouncy Castle JSSE.
# Load with -Djava.security.properties=<dir>/pq-tls.security (single '=': appended to java.security).
# BCJSSE needs a key manager that understands key types such as "EC/secp256r1". The JDK default
# (SunX509) does not, so EC server and client certificates are never selected. PKIX fixes it and
# is also the better choice for SunJSSE.
ssl.KeyManagerFactory.algorithm=PKIX
```

`pq-tls-agent/MANIFEST.MF` (zip, image and EC2 layout: jars next to the agent)

```text
Premain-Class: PqTlsAgent
Class-Path: bcprov-jdk18on-1.87.jar bctls-jdk18on-1.87.jar bcutil-jdk18on-1.87.jar
```

`pq-tls-agent/MANIFEST-layer.MF` (Lambda layer layout: agent in `/opt/pq-tls`, jars in `/opt/java/lib`)

```text
Premain-Class: PqTlsAgent
Class-Path: ../java/lib/bcprov-jdk18on-1.87.jar ../java/lib/bctls-jdk18on-1.87.jar ../java/lib/bcutil-jdk18on-1.87.jar
```

`pq-tls-agent/build.sh` (v2: also builds the layer jar and copies `pq-tls.security`)

```bash
#!/bin/bash
set -euo pipefail
BC=1.87
mkdir -p out/pq-tls out/layer/pq-tls out/layer/java/lib out/classes
for a in bcprov bctls bcutil; do
  curl -fsSLo out/pq-tls/$a-jdk18on-$BC.jar \
    https://repo1.maven.org/maven2/org/bouncycastle/$a-jdk18on/$BC/$a-jdk18on-$BC.jar
  want=$(curl -fsSL https://repo1.maven.org/maven2/org/bouncycastle/$a-jdk18on/$BC/$a-jdk18on-$BC.jar.sha1)
  got=$(sha1sum out/pq-tls/$a-jdk18on-$BC.jar | cut -d' ' -f1)
  [ "$want" = "$got" ] || { echo "checksum mismatch: $a"; exit 1; }
done
javac --release 8 -cp "out/pq-tls/*" -d out/classes src/PqTlsAgent.java
jar cfm out/pq-tls/pq-tls-agent.jar MANIFEST.MF -C out/classes PqTlsAgent.class
cp pq-tls.security out/pq-tls/
# Lambda layer: /opt/pq-tls (agent, wrapper, security file) + /opt/java/lib (BC jars)
jar cfm out/layer/pq-tls/pq-tls-agent.jar MANIFEST-layer.MF -C out/classes PqTlsAgent.class
cp pq-tls.security wrapper out/layer/pq-tls/ && chmod 755 out/layer/pq-tls/wrapper
cp out/pq-tls/b*-jdk18on-$BC.jar out/layer/java/lib/
(cd out/layer && zip -qr ../pq-tls-layer.zip .)
tar -czf out/pq-tls-$BC.tgz -C out/pq-tls .
ls -l out/pq-tls out/layer/pq-tls out/pq-tls-layer.zip out/pq-tls-$BC.tgz
```

`pq-tls-layer/wrapper` (v2; only the Java branch changed from the layer's v1 wrapper, see the Python and Node.js tabs for the other branches)

```bash
#!/bin/bash
# pq-tls Lambda layer: enable hybrid post-quantum TLS (X25519MLKEM768) for outbound connections
# without changing function code.
#   Attach the layer and set AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper.
#   PQ_TLS_DISABLE=1          switch it off without detaching the layer.
#   PQ_TLS_NEXT_WRAPPER=path  chain to a wrapper the function already used (Datadog, OpenTelemetry, ...).
# Runs after the runtime bootstrap has set its environment, so it can override the bootstrap's choices.
AWS_NODE_CONF=/var/runtime/openssl_conf/openssl.cnf
if [ "${PQ_TLS_DISABLE:-0}" != "1" ]; then
  case "${AWS_EXECUTION_ENV:-}" in
    *python3.1[2-9]*)
      # System OpenSSL 3.5 is PQ-capable; the AL2023 crypto policy leaves ML-KEM out of the group list.
      if [ -z "${OPENSSL_CONF:-}" ]; then
        export OPENSSL_CONF=/opt/pq-tls/openssl-pq.cnf
        echo "pq-tls: python: OPENSSL_CONF=$OPENSSL_CONF"
      else
        echo "pq-tls: python: function sets OPENSSL_CONF=$OPENSSL_CONF; left unchanged"
      fi ;;
    *python3.9*|*python3.10*|*python3.11*)
      # System OpenSSL 1.1.1: route urllib3 (requests, boto3) through pyOpenSSL's bundled OpenSSL.
      export PYTHONPATH="/opt/pq-tls/pyshim${PYTHONPATH:+:$PYTHONPATH}"
      echo "pq-tls: python legacy: urllib3 shim via sitecustomize" ;;
    *nodejs2[2-9]*)
      # Node 22.20+/24.9+ bundle OpenSSL 3.5, but the Lambda bootstrap points OPENSSL_CONF at a
      # file that removes ML-KEM from the group list. Override only that AWS default.
      if [ -z "${OPENSSL_CONF:-}" ] || [ "$OPENSSL_CONF" = "$AWS_NODE_CONF" ]; then
        export OPENSSL_CONF=/opt/pq-tls/openssl-pq-node.cnf
        echo "pq-tls: nodejs: OPENSSL_CONF=$OPENSSL_CONF"
      else
        echo "pq-tls: nodejs: function sets OPENSSL_CONF=$OPENSSL_CONF; left unchanged"
      fi ;;
    *java8*|*java11*|*java17*|*java21*)
      # JDK < 25 has no ML-KEM TLS groups; a Java agent puts Bouncy Castle JSSE first.
      # v2: BCJSSE needs the PKIX key manager for EC server and client certificates. Add the kit file
      # unless the function already passes its own security file; agent v2 then sets PKIX itself.
      case " ${JAVA_TOOL_OPTIONS:-} " in
        *java.security.properties=*) ;;
        *) export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Djava.security.properties=/opt/pq-tls/pq-tls.security" ;;
      esac
      export JAVA_TOOL_OPTIONS="$JAVA_TOOL_OPTIONS -javaagent:/opt/pq-tls/pq-tls-agent.jar"
      # The Lambda Java 8 runtime limits clients to TLS 1.2; ML-KEM exists only in TLS 1.3.
      case "$AWS_EXECUTION_ENV:$JAVA_TOOL_OPTIONS" in
        *java8*:*jdk.tls.client.protocols*) ;;
        *java8*:*) export JAVA_TOOL_OPTIONS="$JAVA_TOOL_OPTIONS -Djdk.tls.client.protocols=TLSv1.3,TLSv1.2" ;;
      esac
      # JDK 8's HttpsURLConnection opens the socket without a host name, and BCJSSE then fails
      # endpoint identification ("No hostname specified for HTTPS endpoint ID check", bc-java#1656).
      case "$AWS_EXECUTION_ENV:$JAVA_TOOL_OPTIONS" in
        *java8*:*assumeOriginalHostName*) ;;
        *java8*:*) export JAVA_TOOL_OPTIONS="$JAVA_TOOL_OPTIONS -Dorg.bouncycastle.jsse.client.assumeOriginalHostName=true" ;;
      esac
      echo "pq-tls: java: Bouncy Castle JSSE agent v2, JAVA_TOOL_OPTIONS=$JAVA_TOOL_OPTIONS" ;;
    *dotnet*)
      # dotnet8/dotnet10 use the AL2023 system OpenSSL 3.5; the crypto policy leaves ML-KEM out.
      if [ -z "${OPENSSL_CONF:-}" ]; then
        export OPENSSL_CONF=/opt/pq-tls/openssl-pq.cnf
        echo "pq-tls: dotnet: OPENSSL_CONF=$OPENSSL_CONF"
      else
        echo "pq-tls: dotnet: function sets OPENSSL_CONF=$OPENSSL_CONF; left unchanged"
      fi ;;
    *)
      # java25+: PQ by default. nodejs18/20: no in-process path (OpenSSL without ML-KEM).
      echo "pq-tls: ${AWS_EXECUTION_ENV:-unknown}: no change" ;;
  esac
fi
if [ -n "${PQ_TLS_NEXT_WRAPPER:-}" ]; then
  exec "$PQ_TLS_NEXT_WRAPPER" "$@"
fi
exec "$@"
```

### Dependencies

`pom.xml` (excerpt: only the dependencies that matter for PQ; pick the options your service uses)

``` xml
<dependencyManagement>
  <dependencies>
    <dependency>
      <groupId>software.amazon.awssdk</groupId>
      <artifactId>bom</artifactId>
      <version>2.59.1</version>   <!-- CRT client PQ by default from 2.35.11 -->
      <type>pom</type>
      <scope>import</scope>
    </dependency>
  </dependencies>
</dependencyManagement>
<dependencies>
  <!-- Option A: AWS SDK v2 CRT HTTP client (PQ for AWS API calls on any JDK, Linux) -->
  <dependency>
    <groupId>software.amazon.awssdk</groupId>
    <artifactId>aws-crt-client</artifactId>
  </dependency>
  <dependency>
    <groupId>software.amazon.awssdk.crt</groupId>
    <artifactId>aws-crt</artifactId>
    <version>0.50.0</version>   <!-- the awscrt.version the SDK release pins -->
  </dependency>

  <!-- Option B: Netty with BoringSSL (PQ by default in the tested versions) -->
  <dependency>
    <groupId>io.netty</groupId>
    <artifactId>netty-tcnative-boringssl-static</artifactId>
    <version>2.0.85.Final</version>
  </dependency>
  <dependency>
    <groupId>io.netty</groupId>
    <artifactId>netty-tcnative-boringssl-static</artifactId>
    <version>2.0.85.Final</version>
    <classifier>linux-x86_64</classifier>
  </dependency>
  <dependency>
    <groupId>io.netty</groupId>
    <artifactId>netty-tcnative-boringssl-static</artifactId>
    <version>2.0.85.Final</version>
    <classifier>linux-aarch_64</classifier>
  </dependency>

  <!-- Option C: Bouncy Castle on the class path for static provider registration
       (not needed for the agent path: the agent directory brings its own copies) -->
  <dependency>
    <groupId>org.bouncycastle</groupId>
    <artifactId>bctls-jdk18on</artifactId>
    <version>1.87</version>
  </dependency>
  <dependency>
    <groupId>org.bouncycastle</groupId>
    <artifactId>bcprov-jdk18on</artifactId>
    <version>1.87</version>
  </dependency>
  <dependency>
    <groupId>org.bouncycastle</groupId>
    <artifactId>bcutil-jdk18on</artifactId>
    <version>1.87</version>
  </dependency>
</dependencies>
```

`build.gradle.kts` (same choices)

``` kotlin
dependencies {
    implementation(platform("software.amazon.awssdk:bom:2.59.1"))
    // Option A: CRT HTTP client
    implementation("software.amazon.awssdk:aws-crt-client")
    implementation("software.amazon.awssdk.crt:aws-crt:0.50.0")
    // Option B: Netty + BoringSSL
    implementation("io.netty:netty-tcnative-boringssl-static:2.0.85.Final")
    runtimeOnly("io.netty:netty-tcnative-boringssl-static:2.0.85.Final:linux-x86_64")
    runtimeOnly("io.netty:netty-tcnative-boringssl-static:2.0.85.Final:linux-aarch_64")
    // Option C: Bouncy Castle for static provider registration
    implementation("org.bouncycastle:bctls-jdk18on:1.87")
    implementation("org.bouncycastle:bcprov-jdk18on:1.87")
    implementation("org.bouncycastle:bcutil-jdk18on:1.87")
}
```

### java.security override (static registration, containers and EC2; not Lambda)

`pq-tls/bc-static.security` (v2: adds the key manager line; load with `-Djava.security.properties=<path>`)

```properties
# Appended to $JAVA_HOME/conf/security/java.security. Bouncy Castle JSSE goes before SunJSSE;
# the BC JCA provider goes last so other crypto keeps resolving to the JDK providers.
# The three BC jars must be on the application class path.
security.provider.1=SUN
security.provider.2=SunRsaSign
security.provider.3=SunEC
security.provider.4=org.bouncycastle.jsse.provider.BouncyCastleJsseProvider BC
security.provider.5=SunJSSE
security.provider.6=SunJCE
security.provider.7=SunJGSS
security.provider.8=SunSASL
security.provider.9=XMLDSig
security.provider.10=SunPCSC
security.provider.11=JdkLDAP
security.provider.12=JdkSASL
security.provider.13=SunPKCS11
security.provider.14=org.bouncycastle.jce.provider.BouncyCastleProvider
# EC certificates (server and mTLS client) under BCJSSE need the PKIX key manager.
ssl.KeyManagerFactory.algorithm=PKIX
```

Compare the list with `$JAVA_HOME/conf/security/java.security` in your exact image first: a vendor that adds or reorders providers needs the same change here. Pair it with `-Djdk.tls.namedGroups=X25519MLKEM768,x25519,secp256r1,secp384r1`. JDK 8 uses class names (`sun.security.provider.Sun`, ..., `com.sun.net.ssl.internal.ssl.Provider`) in `$JAVA_HOME/jre/lib/security/java.security`; a JDK 8 variant was not tested.

### Spring Boot

`src/main/resources/application.yml`

``` yaml
server:
  port: 8443
  http2:
    enabled: true
  ssl:
    bundle: web
spring:
  ssl:
    bundle:
      jks:
        web:
          keystore:
            location: file:/etc/app/tls/server.p12
            password: ${KEYSTORE_PASSWORD}
            type: PKCS12
          options:
            enabled-protocols: [TLSv1.3, TLSv1.2]   # keep TLS 1.3 on; ML-KEM exists only in TLS 1.3
```

SSL bundles call `KeyManagerFactory.getDefaultAlgorithm()` and `TrustManagerFactory.getDefaultAlgorithm()` (Spring Boot 3.5.16, checked with javap). An EC PKCS#12 bundle negotiated X25519MLKEM768 on JDK 21 + kit v2 (Tested, `v2/out/tomcat-sb.txt`).

Spring Boot has no named-group property (checked against the [4.1.2 SSL reference](https://docs.spring.io/spring-boot/reference/features/ssl.html)). Set groups with `-Djdk.tls.namedGroups` in the launch environment (Tomcat's `groups` defaults to it), or with a connector customizer:

`src/main/java/com/example/PqTomcatGroups.java` (Unverified: Tomcat's `SSLHostConfig.setGroups` was tested; this Spring wiring and the Boot 4 package name were not)

``` java
package com.example;

import org.springframework.boot.tomcat.TomcatConnectorCustomizer; // Boot 3.x: org.springframework.boot.web.embedded.tomcat.TomcatConnectorCustomizer
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
class PqTomcatGroups {
    @Bean
    TomcatConnectorCustomizer pqGroups() {
        return connector -> {
            for (var h : connector.findSslHostConfigs()) {
                h.setGroups("X25519MLKEM768,x25519,secp256r1,secp384r1");
            }
        };
    }
}
```

### Standalone Tomcat

`conf/server.xml` (connector; `groups` needs Tomcat 11.0.12+ or the matching 10.1/9.0 releases)

``` xml
<Connector port="8443" protocol="org.apache.coyote.http11.Http11NioProtocol"
           SSLEnabled="true" maxThreads="200">
  <UpgradeProtocol className="org.apache.coyote.http2.Http2Protocol" />
  <SSLHostConfig protocols="TLSv1.3+TLSv1.2"
                 groups="X25519MLKEM768,x25519,secp256r1,secp384r1">
    <!-- don't set keyManagerAlgorithm="SunX509": EC certs fail under BCJSSE; omit it or use PKIX -->
    <Certificate certificateKeystoreFile="conf/tls/server.p12"
                 certificateKeystorePassword="${keystore.password}"
                 certificateKeystoreType="PKCS12" />
  </SSLHostConfig>
</Connector>
```

`bin/setenv.sh` (v2)

```bash
#!/bin/sh
# JDK 17/21 only. Remove after moving Tomcat to JDK 25.0.5+.
CATALINA_OPTS="$CATALINA_OPTS -Djava.security.properties=/opt/pq-tls/pq-tls.security -javaagent:/opt/pq-tls/pq-tls-agent.jar"
export CATALINA_OPTS
```

### Netty and AWS SDK code

`NettyPq.java` (client and server; the explicit list is optional, the tested default already prefers X25519MLKEM768)

``` java
import io.netty.handler.ssl.*;

final class NettyPq {
    static final String[] GROUPS = {"X25519MLKEM768", "X25519", "P-256", "P-384"};

    static SslContext client() throws Exception {
        return SslContextBuilder.forClient()
                .sslProvider(SslProvider.OPENSSL)            // netty-tcnative-boringssl-static on the class path
                .protocols("TLSv1.3", "TLSv1.2")
                .option(OpenSslContextOption.GROUPS, GROUPS) // omit to keep the library default
                .build();
    }

    static SslContext server(javax.net.ssl.KeyManagerFactory kmf) throws Exception {
        return SslContextBuilder.forServer(kmf)
                .sslProvider(SslProvider.OPENSSL)
                .protocols("TLSv1.3", "TLSv1.2")
                .option(OpenSslContextOption.GROUPS, GROUPS)
                .build();
    }
}
```

`AwsClients.java` (AWS SDK for Java v2 CRT client; PQ by default from 2.35.11)

``` java
import software.amazon.awssdk.http.crt.AwsCrtAsyncHttpClient;
import software.amazon.awssdk.http.crt.AwsCrtHttpClient;
import software.amazon.awssdk.services.kms.KmsClient;
import software.amazon.awssdk.services.secretsmanager.SecretsManagerAsyncClient;

final class AwsClients {
    static final KmsClient KMS = KmsClient.builder()
            .httpClient(AwsCrtHttpClient.create())
            .build();
    static final SecretsManagerAsyncClient SM = SecretsManagerAsyncClient.builder()
            .httpClient(AwsCrtAsyncHttpClient.create())
            .build();
}
```

### Lambda

Zip layout (kit v2; java8.al2, java8.al2023, java11, java11.al2023, java17, java17.al2023, java21):

```text
function.zip
├── com/example/Handler.class
├── lib/...                      (your dependencies)
└── pq-tls/
    ├── pq-tls-agent.jar         (v2)
    ├── pq-tls.security
    ├── bcprov-jdk18on-1.87.jar
    ├── bctls-jdk18on-1.87.jar
    └── bcutil-jdk18on-1.87.jar
```

Layer layout (kit v2):

```text
pq-tls-layer.zip
├── pq-tls/
│   ├── wrapper                  (v2)
│   ├── pq-tls-agent.jar         (v2, MANIFEST-layer.MF)
│   ├── pq-tls.security
│   └── openssl-pq.cnf, openssl-pq-node.cnf, pyshim/   (other languages, unchanged)
└── java/lib/
    ├── bcprov-jdk18on-1.87.jar
    ├── bctls-jdk18on-1.87.jar
    └── bcutil-jdk18on-1.87.jar
```

`template.yaml` (SAM, zip)

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Parameters:
  Java8:
    Type: String
    AllowedValues: ['true', 'false']
    Default: 'false'
Conditions:
  IsJava8: !Equals [!Ref Java8, 'true']
Resources:
  Fn:
    Type: AWS::Serverless::Function
    Properties:
      Runtime: java21              # java25: delete the Environment block, nothing else needed
      Handler: com.example.Handler::handleRequest
      CodeUri: build/function.zip
      MemorySize: 1024
      Timeout: 30
      Architectures: [arm64]
      Environment:
        Variables:
          JAVA_TOOL_OPTIONS: !If
            - IsJava8
            - -Djava.security.properties=/var/task/pq-tls/pq-tls.security -javaagent:/var/task/pq-tls/pq-tls-agent.jar -Djdk.tls.client.protocols=TLSv1.3,TLSv1.2 -Dorg.bouncycastle.jsse.client.assumeOriginalHostName=true
            - -Djava.security.properties=/var/task/pq-tls/pq-tls.security -javaagent:/var/task/pq-tls/pq-tls-agent.jar
```

`template-layer.yaml` (SAM, layer v2)

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Resources:
  PqTlsLayer:
    Type: AWS::Serverless::LayerVersion
    Properties:
      LayerName: pq-tls
      ContentUri: build/pq-tls-layer.zip
      CompatibleRuntimes: [java8.al2, java8.al2023, java11, java11.al2023, java17, java17.al2023, java21, python3.12, python3.13, nodejs22.x]
      CompatibleArchitectures: [arm64, x86_64]
  Fn:
    Type: AWS::Serverless::Function
    Properties:
      Runtime: java21
      Handler: com.example.Handler::handleRequest
      CodeUri: build/function.zip
      MemorySize: 1024
      Timeout: 30
      Architectures: [arm64]
      Layers: [!Ref PqTlsLayer]
      Environment:
        Variables:
          AWS_LAMBDA_EXEC_WRAPPER: /opt/pq-tls/wrapper   # adds pq-tls.security + agent v2 to JAVA_TOOL_OPTIONS
```

`lambda.yaml` (plain CloudFormation)

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Parameters:
  CodeBucket: {Type: String}
  CodeKey: {Type: String}
  RoleArn: {Type: String}
Resources:
  Fn:
    Type: AWS::Lambda::Function
    Properties:
      Runtime: java21
      Handler: com.example.Handler::handleRequest
      Role: !Ref RoleArn
      Code: {S3Bucket: !Ref CodeBucket, S3Key: !Ref CodeKey}
      MemorySize: 1024
      Timeout: 30
      Architectures: [arm64]
      Environment:
        Variables:
          JAVA_TOOL_OPTIONS: -Djava.security.properties=/var/task/pq-tls/pq-tls.security -javaagent:/var/task/pq-tls/pq-tls-agent.jar
```

`lambda.tf` (Terraform; zip, and the layer variant)

```hcl
resource "aws_lambda_function" "fn" {
  function_name    = "orders-java"
  runtime          = "java21" # java25: remove the environment block
  handler          = "com.example.Handler::handleRequest"
  role             = var.role_arn
  filename         = "build/function.zip"
  source_code_hash = filebase64sha256("build/function.zip")
  memory_size      = 1024
  timeout          = 30
  architectures    = ["arm64"]
  environment {
    variables = {
      JAVA_TOOL_OPTIONS = "-Djava.security.properties=/var/task/pq-tls/pq-tls.security -javaagent:/var/task/pq-tls/pq-tls-agent.jar"
    }
  }
}

# Layer variant: no kit in the zip.
resource "aws_lambda_layer_version" "pq_tls" {
  layer_name               = "pq-tls"
  filename                 = "build/pq-tls-layer.zip"
  source_code_hash         = filebase64sha256("build/pq-tls-layer.zip")
  compatible_runtimes      = ["java8.al2", "java8.al2023", "java11", "java11.al2023", "java17", "java17.al2023", "java21"]
  compatible_architectures = ["arm64", "x86_64"]
}

resource "aws_lambda_function" "fn_layer" {
  function_name = "orders-java-layer"
  runtime       = "java21"
  handler       = "com.example.Handler::handleRequest"
  role          = var.role_arn
  filename      = "build/function.zip"
  layers        = [aws_lambda_layer_version.pq_tls.arn]
  architectures = ["arm64"]
  environment {
    variables = {
      AWS_LAMBDA_EXEC_WRAPPER = "/opt/pq-tls/wrapper"
    }
  }
}
```

`Dockerfile.lambda` (Lambda container image, java21 base; for java25 drop the COPY and ENV lines)

```dockerfile
FROM public.ecr.aws/lambda/java:21
COPY build/classes/ ${LAMBDA_TASK_ROOT}/
COPY build/dependency/ ${LAMBDA_TASK_ROOT}/lib/
COPY pq-tls/ ${LAMBDA_TASK_ROOT}/pq-tls/
ENV JAVA_TOOL_OPTIONS="-Djava.security.properties=/var/task/pq-tls/pq-tls.security -javaagent:/var/task/pq-tls/pq-tls-agent.jar"
CMD ["com.example.Handler::handleRequest"]
```

### Containers (Fargate, ECS, EKS)

`Dockerfile` (preferred: JDK 25.0.5+, no PQ-specific lines)

``` dockerfile
FROM amazoncorretto:25-al2023-headless
# or: FROM eclipse-temurin:25-jre
COPY build/libs/app.jar /app/app.jar
USER 1000
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

`Dockerfile.jdk21-agent` (kit v2, JDK 17/21 until the upgrade)

```dockerfile
FROM amazoncorretto:21-al2023-headless
COPY pq-tls/ /opt/pq-tls/
COPY build/libs/app.jar /app/app.jar
ENV JAVA_TOOL_OPTIONS="-Djava.security.properties=/opt/pq-tls/pq-tls.security -javaagent:/opt/pq-tls/pq-tls-agent.jar"
USER 1000
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

`Dockerfile.distroless-agent` (distroless has no shell; the JVM reads JAVA_TOOL_OPTIONS itself)

```dockerfile
FROM gcr.io/distroless/java21-debian12:nonroot
COPY pq-tls/ /opt/pq-tls/
COPY build/libs/app.jar /app/app.jar
ENV JAVA_TOOL_OPTIONS="-Djava.security.properties=/opt/pq-tls/pq-tls.security -javaagent:/opt/pq-tls/pq-tls-agent.jar"
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

`Dockerfile.static` (static provider registration instead of the agent; `bc-static.security` v2 holds the PKIX line)

```dockerfile
FROM eclipse-temurin:21-jre
COPY pq-tls/bcprov-jdk18on-1.87.jar pq-tls/bctls-jdk18on-1.87.jar pq-tls/bcutil-jdk18on-1.87.jar /opt/pq-tls/
COPY pq-tls/bc-static.security /opt/pq-tls/bc-static.security
COPY build/libs/app.jar /app/app.jar
ENV JAVA_TOOL_OPTIONS="-Djava.security.properties=/opt/pq-tls/bc-static.security -Djdk.tls.namedGroups=X25519MLKEM768,x25519,secp256r1,secp384r1"
# -jar ignores -cp, so put the BC jars in the jar manifest Class-Path, or run with -cp and the main class:
ENTRYPOINT ["java", "-cp", "/app/app.jar:/opt/pq-tls/*", "com.example.Main"]
```

`taskdef.json` (ECS / Fargate; only needed if the image does not already set it)

```json
{
  "family": "orders-java",
  "requiresCompatibilities": ["FARGATE"],
  "networkMode": "awsvpc",
  "cpu": "1024",
  "memory": "2048",
  "runtimePlatform": {"cpuArchitecture": "ARM64", "operatingSystemFamily": "LINUX"},
  "executionRoleArn": "arn:aws:iam::111122223333:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "app",
      "image": "111122223333.dkr.ecr.eu-west-1.amazonaws.com/orders-java@sha256:<digest>",
      "essential": true,
      "portMappings": [{"containerPort": 8443, "protocol": "tcp"}],
      "environment": [
        {"name": "JAVA_TOOL_OPTIONS", "value": "-Djava.security.properties=/opt/pq-tls/pq-tls.security -javaagent:/opt/pq-tls/pq-tls-agent.jar"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {"awslogs-group": "/ecs/orders-java", "awslogs-region": "eu-west-1", "awslogs-stream-prefix": "app"}
      }
    }
  ]
}
```

`ecs.tf` (Terraform)

```hcl
locals {
  pq_tls_opts = "-Djava.security.properties=/opt/pq-tls/pq-tls.security -javaagent:/opt/pq-tls/pq-tls-agent.jar"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "orders-java"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = var.execution_role_arn
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
  container_definitions = jsonencode([{
    name         = "app"
    image        = var.image # pin by digest
    essential    = true
    portMappings = [{ containerPort = 8443, protocol = "tcp" }]
    environment  = [{ name = "JAVA_TOOL_OPTIONS", value = local.pq_tls_opts }]
  }])
}
```

`ecs.yaml` (CloudFormation)

```yaml
Parameters:
  ExecutionRoleArn: {Type: String}
  Image: {Type: String}
Resources:
  TaskDef:
    Type: AWS::ECS::TaskDefinition
    Properties:
      Family: orders-java
      RequiresCompatibilities: [FARGATE]
      NetworkMode: awsvpc
      Cpu: '1024'
      Memory: '2048'
      ExecutionRoleArn: !Ref ExecutionRoleArn
      RuntimePlatform: {CpuArchitecture: ARM64, OperatingSystemFamily: LINUX}
      ContainerDefinitions:
        - Name: app
          Image: !Ref Image
          Essential: true
          PortMappings: [{ContainerPort: 8443, Protocol: tcp}]
          Environment:
            - Name: JAVA_TOOL_OPTIONS
              Value: -Djava.security.properties=/opt/pq-tls/pq-tls.security -javaagent:/opt/pq-tls/pq-tls-agent.jar
```

`deployment.yaml` (EKS)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders-java
spec:
  replicas: 2
  selector:
    matchLabels: {app: orders-java}
  template:
    metadata:
      labels: {app: orders-java}
    spec:
      containers:
        - name: app
          image: 111122223333.dkr.ecr.eu-west-1.amazonaws.com/orders-java@sha256:<digest>
          ports: [{containerPort: 8443}]
          env:
            - name: JAVA_TOOL_OPTIONS
              value: "-Djava.security.properties=/opt/pq-tls/pq-tls.security -javaagent:/opt/pq-tls/pq-tls-agent.jar"
          readinessProbe:
            tcpSocket: {port: 8443}
```

### EC2

`/etc/systemd/system/orders-java.service`

```ini
[Unit]
Description=orders-java
After=network-online.target
Wants=network-online.target

[Service]
User=orders
# JDK 25.0.5+: delete the Environment line.
Environment="JAVA_TOOL_OPTIONS=-Djava.security.properties=/opt/pq-tls/pq-tls.security -javaagent:/opt/pq-tls/pq-tls-agent.jar"
ExecStart=/usr/lib/jvm/java-21-amazon-corretto/bin/java -jar /opt/orders/app.jar
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

`/etc/systemd/system/orders-java.service.d/pq-tls.conf` (drop-in, when you cannot edit the unit)

```ini
[Service]
Environment="JAVA_TOOL_OPTIONS=-Djava.security.properties=/opt/pq-tls/pq-tls.security -javaagent:/opt/pq-tls/pq-tls-agent.jar"
```

`pq-tls-ssm.yaml` (SSM Command document: install kit v2 from S3 and add the drop-in)

```yaml
schemaVersion: '2.2'
description: Install the pq-tls Java kit v2 (agent + pq-tls.security) and enable it for one systemd service.
parameters:
  Service: {type: String}
  KitS3Uri: {type: String, description: 's3://bucket/pq-tls-1.87.tgz (kit v2)'}
mainSteps:
  - action: aws:runShellScript
    name: install
    inputs:
      runCommand:
        - set -euo pipefail
        - mkdir -p /opt/pq-tls
        - aws s3 cp '{{ KitS3Uri }}' /tmp/pq-tls.tgz
        - tar -xzf /tmp/pq-tls.tgz -C /opt/pq-tls
        - test -f /opt/pq-tls/pq-tls.security
        - mkdir -p '/etc/systemd/system/{{ Service }}.service.d'
        - printf '[Service]\nEnvironment="JAVA_TOOL_OPTIONS=-Djava.security.properties=/opt/pq-tls/pq-tls.security -javaagent:/opt/pq-tls/pq-tls-agent.jar"\n' > '/etc/systemd/system/{{ Service }}.service.d/pq-tls.conf'
        - systemctl daemon-reload
        - systemctl restart '{{ Service }}'
        - sleep 5; journalctl -u '{{ Service }}' -n 100 --no-pager | grep -m1 'ssl.KeyManagerFactory.algorithm=PKIX'
```

The IaC and SSM files above were written for this tab and not deployed (no AWS account in the test lab); the JVM flags they set are the Tested part.

### CI check

`ci/java-pq-check.sh`

```bash
#!/bin/bash
# java-pq-check.sh <repo dir>: fail the build on Java settings that block hybrid PQ TLS
# (X25519MLKEM768) or break the pq-tls kit. Exit 1 on any FAIL; WARN lines need a human look.
# Scans source, build files, Dockerfiles, Helm/K8s/ECS/Lambda IaC, launch scripts, properties and YAML.
set -uo pipefail
ROOT=${1:-.}
INC=(--include='*.java' --include='*.kt' --include='*.scala' --include='*.groovy' --include='*.xml'
     --include='*.properties' --include='*.yml' --include='*.yaml' --include='*.json' --include='*.tf'
     --include='*.sh' --include='*.conf' --include='*.service' --include='Dockerfile*' --include='*.env'
     --include='*.security' --include='*.gradle' --include='*.kts')
fails=0
hit() { # level message pattern
  local out; out=$(grep -rnIE "${INC[@]}" --exclude-dir=.git --exclude-dir=target --exclude-dir=build \
                   --exclude-dir=node_modules "$3" "$ROOT" 2>/dev/null | grep -v 'java-pq-check' | head -20)
  [ -z "$out" ] && return
  echo "$1: $2"; echo "$out" | sed 's/^/    /'
  [ "$1" = FAIL ] && fails=$((fails+1)); }

# 1. Group pins without the hybrid group (also turns PQ off on JDK 25 and for Netty tcnative).
out=$(grep -rnIE "${INC[@]}" --exclude-dir=.git 'jdk\.tls\.namedGroups|setGroups\(|groups="|OpenSslContextOption\.GROUPS' "$ROOT" 2>/dev/null \
      | grep -v 'java-pq-check' | grep -vi 'X25519MLKEM768' | head -20)
[ -n "$out" ] && { echo "FAIL: named-group list without X25519MLKEM768"; echo "$out" | sed 's/^/    /'; fails=$((fails+1)); }
# 2. TLS 1.2-only pins (ML-KEM exists only in TLS 1.3).
hit FAIL 'TLS 1.2-only protocol pin' 'SSLContext\.getInstance\("TLSv1\.2"\)|TLS\.V_1_2\)|protocols?="TLSv1\.2"|enabled-protocols: *\[?TLSv1\.2\]?$|ssl\.enabled\.protocols=TLSv1\.2$|jdk\.tls\.(client|server)\.protocols=TLSv1\.2([^,]|$)|tlsVersions=TLSv1\.2([^,]|$)'
# 3. Hard-coded SunX509 key manager: EC certificates (server and mTLS client) fail under the BC agent.
hit FAIL 'hard-coded SunX509 key manager (use KeyManagerFactory.getDefaultAlgorithm() or "PKIX")' \
  'KeyManagerFactory\.getInstance\("SunX509"|keyManagerAlgorithm *= *"?SunX509|ssl\.KeyManagerFactory\.algorithm *= *SunX509|key-manager-algorithm: *SunX509'
# 4. A security-properties file given with '==' replaces java.security completely (drops the kit's line).
hit FAIL 'java.security.properties with == replaces the whole java.security file' 'java\.security\.properties=='
# 5. JDK below 25 in images and runtimes: needs the kit (agent + pq-tls.security) until upgraded.
hit WARN 'JDK below 25 (needs the pq-tls kit or an upgrade to 25.0.5+)' \
  '(FROM|image:|"image").*(corretto|temurin|openjdk|jdk|jre|java)[:-]?(8|11|17|21)([^0-9]|$)|Runtime: *java(8|11|17|21)|runtime *= *"java(8|11|17|21)'
# 6. Kit present without the key-manager fix (v1 packaging).
out=$(grep -rnIE "${INC[@]}" --exclude-dir=.git 'pq-tls-agent\.jar' "$ROOT" 2>/dev/null | grep -v 'java-pq-check' | grep -v 'pq-tls\.security' | head -20)
[ -n "$out" ] && echo "WARN: pq-tls agent without pq-tls.security on the same line (fine only with agent v2)" && echo "$out" | sed 's/^/    /'
# 7. Things that bypass JSSE and need their own check.
hit WARN 'own TLS stack: check separately (tcnative/BoringSSL, CRT, conscrypt, wolfSSL)' 'netty-tcnative|SslProvider\.OPENSSL|aws-crt|conscrypt|wolfssl'
hit WARN 'FIPS provider in use: the non-FIPS BC agent must not be added' 'bc-fips|bctls-fips|BouncyCastleFipsProvider|com\.safelogic|fips\.provider'
echo "java-pq-check: $fails failing check(s)"
[ $fails -eq 0 ]
```

### Test harness (cases C, D, E)

`V2Test.java` (server with a keystore and optional client auth, client, embedded Tomcat)

```java
import javax.net.ssl.*;
import java.io.*;
import java.security.KeyStore;
import java.security.Security;
import java.security.cert.Certificate;
import java.security.cert.X509Certificate;

// server <keystore|default> <type> <kmfAlg: default|SunX509|PKIX> <port>   (-DneedClientAuth=true for mTLS)
// client <host> <port>                                                    (client cert via javax.net.ssl.keyStore)
// tomcat <p12> <port> <keyManagerAlgorithm|default>                       (embedded Tomcat, SSLHostConfig)
public class V2Test {
    static final char[] PW = "changeit".toCharArray();

    static String cn(Certificate[] c) {
        return c == null || c.length == 0 ? "none" : ((X509Certificate) c[0]).getSubjectX500Principal().getName();
    }

    public static void main(String[] a) throws Exception {
        System.out.println("jdk=" + System.getProperty("java.version") + " kmfDefault=" + KeyManagerFactory.getDefaultAlgorithm()
                + " secprop=" + Security.getProperty("ssl.KeyManagerFactory.algorithm"));
        switch (a[0]) {
            case "server": server(a); break;
            case "client": client(a[1], Integer.parseInt(a[2])); break;
            case "tomcat": tomcat(a[1], Integer.parseInt(a[2]), a[3]); break;
            default: throw new IllegalArgumentException(a[0]);
        }
    }

    static void server(String[] a) throws Exception {
        SSLContext ctx;
        if (a[1].equals("default")) {
            ctx = SSLContext.getDefault();
        } else {
            KeyStore ks = KeyStore.getInstance(a[2]);
            try (var in = new FileInputStream(a[1])) { ks.load(in, PW); }
            KeyManagerFactory f = KeyManagerFactory.getInstance(a[3].equals("default") ? KeyManagerFactory.getDefaultAlgorithm() : a[3]);
            f.init(ks, PW);
            System.out.println("server: kmf=" + f.getAlgorithm() + "/" + f.getProvider().getName());
            ctx = SSLContext.getInstance("TLS");
            ctx.init(f.getKeyManagers(), null, null);   // null trust managers = default (javax.net.ssl.trustStore or cacerts)
        }
        System.out.println("server: SSLContext provider=" + ctx.getProvider().getName());
        SSLServerSocket ss = (SSLServerSocket) ctx.getServerSocketFactory().createServerSocket(Integer.parseInt(a[4]));
        if (Boolean.getBoolean("needClientAuth")) ss.setNeedClientAuth(true);
        while (true) {
            try (SSLSocket s = (SSLSocket) ss.accept()) {
                s.startHandshake();
                Certificate[] peer = null;
                try { peer = s.getSession().getPeerCertificates(); } catch (SSLPeerUnverifiedException e) { }
                System.out.println("server: OK " + s.getSession().getProtocol() + " client-cert=" + cn(peer)
                        + " server-cert=" + cn(s.getSession().getLocalCertificates()));
                s.getOutputStream().write("HTTP/1.0 200 OK\r\n\r\nok\n".getBytes());
                s.getOutputStream().flush();
            } catch (Exception e) {
                System.out.println("server: handshake failed: " + e);
            }
        }
    }

    static void client(String host, int port) {
        SSLContext ctx = null;
        try {
            ctx = SSLContext.getDefault();
            try (SSLSocket s = (SSLSocket) ctx.getSocketFactory().createSocket(host, port)) {
                s.startHandshake();
                s.getOutputStream().write("GET / HTTP/1.0\r\n\r\n".getBytes());
                s.getOutputStream().flush();
                String line = new BufferedReader(new InputStreamReader(s.getInputStream())).readLine();
                System.out.println("client OK provider=" + ctx.getProvider().getName() + " " + s.getSession().getProtocol()
                        + " server-cert=" + cn(s.getSession().getPeerCertificates())
                        + " sent-client-cert=" + cn(s.getSession().getLocalCertificates()) + " first-line=" + line);
            }
        } catch (Exception e) {
            System.out.println("client FAIL provider=" + (ctx == null ? "?" : ctx.getProvider().getName()) + ": " + e);
        }
    }

    static void tomcat(String p12, int port, String kma) throws Exception {
        var t = new org.apache.catalina.startup.Tomcat();
        t.setBaseDir("/tmp/tc" + port);
        var c = new org.apache.catalina.connector.Connector("org.apache.coyote.http11.Http11NioProtocol");
        c.setPort(port);
        c.setSecure(true);
        c.setScheme("https");
        c.setProperty("SSLEnabled", "true");
        var h = new org.apache.tomcat.util.net.SSLHostConfig();
        h.setProtocols("TLSv1.3+TLSv1.2");
        if (!kma.equals("default")) h.setKeyManagerAlgorithm(kma);   // server.xml: <SSLHostConfig keyManagerAlgorithm="...">
        System.out.println("tomcat: SSLHostConfig keyManagerAlgorithm=" + h.getKeyManagerAlgorithm());
        var cert = new org.apache.tomcat.util.net.SSLHostConfigCertificate(h, org.apache.tomcat.util.net.SSLHostConfigCertificate.Type.UNDEFINED);
        cert.setCertificateKeystoreFile(p12);
        cert.setCertificateKeystorePassword("changeit");
        cert.setCertificateKeystoreType("PKCS12");
        h.addCertificate(cert);
        c.addSslHostConfig(h);
        t.getService().addConnector(c);
        t.getConnector();
        var ctx = t.addContext("", null);
        org.apache.catalina.startup.Tomcat.addServlet(ctx, "ok", new jakarta.servlet.http.HttpServlet() {
            protected void doGet(jakarta.servlet.http.HttpServletRequest q, jakarta.servlet.http.HttpServletResponse r) throws IOException {
                r.getWriter().println("ok");
            }
        });
        ctx.addServletMappingDecoded("/", "ok");
        t.start();
        t.getServer().await();
    }
}
```

`run-v2.sh` (one JDK image and one kit mode per run; needs Docker, `debian:trixie-slim` for OpenSSL 3.5 and the keystores from `build-v2.sh`)

```bash
#!/bin/bash
# Java custom keystores (case C), private CA trust (case D) and mutual TLS (case E) with and without
# the key-manager fix. One JDK image and one mode per run.
#   run-v2.sh <image tag> <mode>
#   image: eclipse-temurin:17-jre | eclipse-temurin:21-jre | eclipse-temurin:25-jre
#   mode:  v1nofix (kit agent v1, no fix) | v1file (v1 + -Djava.security.properties=pq-tls.security)
#          v2agent (v2 agent alone, no file) | v2kit (v2 agent + pq-tls.security, as packaged) | none (no agent)
# Agent and fix go in JAVA_TOOL_OPTIONS, as in the packaging; app options go on the command line.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
V="$(cd "$(dirname "$0")" && pwd)"; AG1="$V/../../../lambda-pq/fn/java-bundled/pq-tls"
IMG=$1; MODE=$2; TAG=$(echo "$IMG" | tr ':/' '__')
L=run=pqc-lang2-java; N=pqnet-java2
JDK=$(docker image inspect --format '{{index .RepoDigests 0}}' "$IMG")
DEB=$(docker image inspect --format '{{index .RepoDigests 0}}' debian:trixie-slim)
case $MODE in
  v1nofix) JTO="-javaagent:/agent1/pq-tls-agent.jar" ;;
  v1file)  JTO="-Djava.security.properties=/kit/pq-tls/pq-tls.security -javaagent:/agent1/pq-tls-agent.jar" ;;
  v2agent) JTO="-javaagent:/kit/pq-tls/pq-tls-agent.jar" ;;
  v2kit)   JTO="-Djava.security.properties=/kit/pq-tls/pq-tls.security -javaagent:/kit/pq-tls/pq-tls-agent.jar" ;;
  none)    JTO="" ;;
  file)    JTO="-Djava.security.properties=/kit/pq-tls/pq-tls.security" ;;
esac
echo "== $IMG ($JDK) mode=$MODE JAVA_TOOL_OPTIONS='$JTO'"
docker network create --label $L $N >/dev/null 2>&1
docker rm -f java2-ossl java2-jvm >/dev/null 2>&1
docker run -d --label $L --name java2-ossl --network $N -v "$V":/v "$DEB" sleep 900 >/dev/null
docker run -d --label $L --name java2-jvm --network $N --network-alias ks-java --network-alias alt-host \
  -v "$V":/v -v "$V/kit":/kit:ro -v "$AG1":/agent1:ro -v "$V/../lib-new":/deps:ro "$JDK" sleep 900 >/dev/null
docker exec java2-ossl sh -c 'apt-get -qq update >/dev/null 2>&1; apt-get -qq install -y openssl >/dev/null 2>&1'
printf 'jdk.tls.ephemeralDHKeySize=2048\n' > "$V/app.security"   # stands in for an app that ships its own security file

TS="-Djavax.net.ssl.trustStore=/v/c/trust.p12 -Djavax.net.ssl.trustStorePassword=changeit -Djavax.net.ssl.trustStoreType=PKCS12"
KS() { echo "-Djavax.net.ssl.keyStore=/v/c/$1 -Djavax.net.ssl.keyStorePassword=changeit -Djavax.net.ssl.keyStoreType=PKCS12"; }
LOG="$V/out/srv-$TAG-$MODE"; rm -f "$LOG"-*.log
start() { # port "app opts" args...
  p=$1; o=$2; shift 2
  docker exec -d -e JAVA_TOOL_OPTIONS="$JTO" java2-jvm sh -c "java $o -cp "/v/cls:/deps/*" V2Test server $* $p > /v/out/srv-$TAG-$MODE-$p.log 2>&1"; }
start 9001 "" /v/c/ec-main.p12 PKCS12 default
start 9002 "" /v/c/mixed.p12 PKCS12 default
start 9003 "" /v/c/mixed2.p12 PKCS12 default
start 9004 "" /v/c/multi.p12 PKCS12 default
start 9005 "" /v/c/ec.jks JKS default
start 9006 "" /v/c/ec-main.p12 PKCS12 SunX509
start 9007 "$(KS ec-main.p12)" default x x
start 9009 "" /v/c/rsa-main.p12 PKCS12 default
start 9010 "-DneedClientAuth=true $TS" /v/c/ec-main.p12 PKCS12 default
start 9011 "-DneedClientAuth=true $TS -Djdk.tls.namedGroups=X25519MLKEM768" /v/c/ec-main.p12 PKCS12 default
start 9012 "-Djava.security.properties=/v/app.security $(KS ec-main.p12)" default x x
docker exec -d java2-ossl sh -c 'openssl s_server -accept 8443 -tls1_3 -groups X25519MLKEM768 -cert /v/c/ec-ossl.crt -key /v/c/ec-ossl.key -Verify 1 -CAfile /v/c/ca.crt -www > /v/out/ossl-verify.log 2>&1'
docker exec -d java2-ossl sh -c 'openssl s_server -accept 8444 -tls1_3 -groups X25519MLKEM768 -cert /v/c/ec-ossl.crt -key /v/c/ec-ossl.key -www > /v/out/ossl-pqonly.log 2>&1'
sleep 8

probe() { # label port args
  r=$(docker exec java2-ossl sh -c "echo | timeout 8 openssl s_client -connect ks-java:$2 -brief $3 2>&1")
  g=$(echo "$r" | grep -m1 -oE 'group: [A-Za-z0-9]+')
  cn=$(echo "$r" | grep -m1 -oE 'Peer certificate: .*' | grep -oE 'CN ?= ?[a-z-]+')
  al=$(echo "$r" | grep -m1 -oE 'alert [a-z ]+' | head -1)
  printf "  %-58s | %-22s | %-14s | %s\n" "$1" "${g:-no group}" "${cn:-no cert}" "$al"; }
echo "-- C. server keystores (OpenSSL 3.5 s_client -> JVM server)"
probe "9001 EC P-256 only (PKCS#12)"                     9001 ""
probe "9001 EC only, classical-only client -groups X25519" 9001 "-groups X25519"
probe "9009 RSA only (PKCS#12)"                          9009 ""
probe "9002 RSA+EC in one PKCS#12"                       9002 ""
probe "9003 RSA(self-signed)+EC, RSA-only client sigalgs" 9003 "-sigalgs rsa_pss_rsae_sha256:rsa_pkcs1_sha256"
probe "9004 two EC certs, SNI ks-java"                   9004 "-servername ks-java"
probe "9004 two EC certs, SNI alt-host"                  9004 "-servername alt-host"
probe "9005 EC in JKS"                                   9005 ""
probe "9006 code hard-codes KeyManagerFactory SunX509"   9006 ""
probe "9007 -Djavax.net.ssl.keyStore (default context)"  9007 ""
probe "9012 app's own -Djava.security.properties + keyStore" 9012 ""
echo "-- E1. JVM server requires client cert (needClientAuth, trustStore=private CA)"
probe "9010 client EC cert, PQ group"     9010 "-groups X25519MLKEM768 -cert /v/c/client-ec.crt -key /v/c/client-ec.key"
probe "9010 client RSA cert, default"     9010 "-cert /v/c/client-rsa.crt -key /v/c/client-rsa.key"
probe "9010 no client cert (must fail)"   9010 ""
probe "9010 cert from unknown CA (must fail)" 9010 "-cert /v/c/client-rogue.crt -key /v/c/client-rogue.key"
probe "9011 PQ-only JVM server, EC client cert" 9011 "-cert /v/c/client-ec.crt -key /v/c/client-ec.key"
probe "9011 PQ-only JVM server, X25519-only client (must fail)" 9011 "-groups X25519 -cert /v/c/client-ec.crt -key /v/c/client-ec.key"
sleep 1
echo "   server 9010 log: $(grep -oE 'client-cert=[^ ]+|handshake failed: [^:]+: [a-z_()0-9]+' $LOG-9010.log | tr '\n' ' ')"
echo "   server 9011 log: $(grep -oE 'client-cert=[^ ]+|handshake failed: [^:]+: [a-z_()0-9]+' $LOG-9011.log | tr '\n' ' ')"

cli() { # label host port "app opts"
  r=$(docker exec -e JAVA_TOOL_OPTIONS="$JTO" java2-jvm sh -c "java $4 -cp "/v/cls:/deps/*" V2Test client $2 $3 2>/dev/null" | grep -E '^client')
  printf "  %-58s | %s\n" "$1" "$(echo "$r" | cut -c1-190)"; }
echo "-- D. JVM client trust -> PQ-only OpenSSL server, private-CA cert"
cli "no private CA configured (must fail)"            java2-ossl 8444 ""
cli "-Djavax.net.ssl.trustStore=trust.p12"            java2-ossl 8444 "$TS"
echo "-- E2. JVM client presents cert -> OpenSSL 3.5 PQ-only s_server -Verify 1"
cli "keyStore=client-ec.p12"                          java2-ossl 8443 "$TS $(KS client-ec.p12)"
cli "keyStore=client-rsa.p12"                         java2-ossl 8443 "$TS $(KS client-rsa.p12)"
cli "no keyStore (must fail)"                         java2-ossl 8443 "$TS"
echo "   s_server verify log: $(grep -oE 'depth=0 CN ?= ?[a-z-]+|peer did not return a certificate|alert [a-z ]+' $V/out/ossl-verify.log | tr '\n' ';')"
echo "-- E3. JVM client cert -> PQ-only JVM server (9011, jdk.tls.namedGroups=X25519MLKEM768)"
cli "keyStore=client-ec.p12"                          ks-java 9011 "$TS $(KS client-ec.p12)"
echo "-- server startup lines"
for p in 9001 9006 9007 9012; do echo "  $p: $(grep -m1 -E 'kmfDefault' $LOG-$p.log) $(grep -m1 -oE 'kmf=[^ ]+' $LOG-$p.log) $(grep -m1 'pq-tls agent' $LOG-$p.log)"; done
docker rm -f java2-ossl java2-jvm >/dev/null; docker network rm $N >/dev/null
echo "left: $(docker ps -a --filter label=$L --format '{{.Names}}' | wc -l | tr -d ' ')"
```

`build-v2.sh` (builds kit v2 and the test classes, makes the client and rogue certs)

```bash
#!/bin/bash
# Build the v2 kit (agent with the key-manager fix) and the test classes; make client certs for mTLS.
set -euo pipefail
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
V="$(cd "$(dirname "$0")" && pwd)"; J="$V/.."
BCJARS="$J/../../lambda-pq/fn/java-bundled/pq-tls"
L=run=pqc-lang2-java
JDK=$(docker image inspect --format '{{index .RepoDigests 0}}' eclipse-temurin:21)
DEB=$(docker image inspect --format '{{index .RepoDigests 0}}' debian:trixie-slim)
echo "images: $JDK $DEB"
mkdir -p "$V/kit/pq-tls" "$V/kit/pq-tls-layer" "$V/c"
cp "$BCJARS"/b*-jdk18on-1.87.jar "$V/kit/pq-tls/"
cp "$V/kit/pq-tls/pq-tls.security" "$V/kit/pq-tls-layer/"
printf 'Premain-Class: PqTlsAgent\nClass-Path: bcprov-jdk18on-1.87.jar bctls-jdk18on-1.87.jar bcutil-jdk18on-1.87.jar\n' > "$V/kit/MANIFEST.MF"
printf 'Premain-Class: PqTlsAgent\nClass-Path: ../java/lib/bcprov-jdk18on-1.87.jar ../java/lib/bctls-jdk18on-1.87.jar ../java/lib/bcutil-jdk18on-1.87.jar\n' > "$V/kit/MANIFEST-layer.MF"
cp "$J"/ks/c/{ca.crt,ca.key,ec-main.p12,rsa-main.p12,ec-alt.p12,ec-ossl.crt,ec-ossl.key,mixed.p12,multi.p12,ec.jks,trust.p12} "$V/c/"

docker run --rm --label $L --name java2-build -v "$V":/v -v "$J/lib-new":/deps:ro "$JDK" sh -ec '
  cd /v/kit && rm -rf cls && mkdir cls
  javac -nowarn --release 8 -cp "pq-tls/*" -d cls src/PqTlsAgent.java 2>&1 | grep -v "warning" || true
  jar cfm pq-tls/pq-tls-agent.jar MANIFEST.MF -C cls PqTlsAgent.class
  jar cfm pq-tls-layer/pq-tls-agent.jar MANIFEST-layer.MF -C cls PqTlsAgent.class
  cd /v && rm -rf cls && javac --release 17 -cp "/deps/*" -d cls V2Test.java && echo compiled'

docker run --rm --label $L --name java2-certs -v "$V":/v "$DEB" sh -ec '
  apt-get -qq update >/dev/null 2>&1; apt-get -qq install -y openssl >/dev/null 2>&1; openssl version
  cd /v/c
  mk() { # name keyalg eku
    if [ $2 = ec ]; then openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj /CN=$1 -keyout $1.key -out $1.csr 2>/dev/null
    else openssl req -newkey rsa:2048 -nodes -subj /CN=$1 -keyout $1.key -out $1.csr 2>/dev/null; fi
    printf "extendedKeyUsage=%s\n" $3 > $1.ext
    openssl x509 -req -in $1.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 30 -extfile $1.ext -out $1.crt 2>/dev/null
    openssl pkcs12 -export -in $1.crt -inkey $1.key -certfile ca.crt -name $1 -passout pass:changeit -out $1.p12; }
  mk client-ec ec clientAuth; mk client-rsa rsa clientAuth
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 -subj /CN=rogue-ca -keyout rogue-ca.key -out rogue-ca.crt 2>/dev/null
  openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj /CN=client-rogue -keyout client-rogue.key -out client-rogue.csr 2>/dev/null
  printf "extendedKeyUsage=clientAuth\n" > client-rogue.ext
  openssl x509 -req -in client-rogue.csr -CA rogue-ca.crt -CAkey rogue-ca.key -CAcreateserial -days 30 -extfile client-rogue.ext -out client-rogue.crt 2>/dev/null
  chmod -R a+rwX /v/c; ls /v/c | tr "\n" " "'
ls -l "$V/kit/pq-tls" "$V/kit/pq-tls-layer"
```
