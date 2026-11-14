# Java

## Problem statement

Java services on JDK 8 to 21 negotiate classical key exchange only (X25519 or P-256). Traffic recorded today can be decrypted later by a quantum computer: harvest-now, decrypt-later. This affects outbound calls to AWS APIs, databases and partners, and any TLS the JVM terminates itself.

The JDK's TLS provider (JSSE) controls the handshake for almost every Java library. Apache HttpClient, OkHttp, the JDK HttpClient, JDBC drivers, Kafka, Tomcat, Jetty and Spring Boot all follow it. The OS and its OpenSSL don't matter, except for libraries that ship their own TLS stack: Netty tcnative (BoringSSL) and the AWS CRT client (s2n-tls). JDK 25.0.5 and later offer X25519MLKEM768 by default. Older JDKs have no ML-KEM group at all, so on them a provider has to change: the pq-tls kit puts Bouncy Castle JSSE (BCJSSE) in front of JSSE.

Most teams already have their own certificates, keystores and truststores. This tab shows, case by case, that **you don't change the stores themselves**. On JDK 8 to 21 with the kit, one setting matters for certificates: `ssl.KeyManagerFactory.algorithm=PKIX`. Kit v2 ships it. Without it, BCJSSE can't use EC certificates (server, or client certificates for mTLS).
**JDK 25.0.5 and later (released 2026-10-20) offer and prefer X25519MLKEM768 by default**, as client and as server ([Oracle 25.0.5 release note, JDK-8314323](https://www.oracle.com/java/technologies/javase/25-0-5-relnotes.html)).

Why other pages say "JDK 27": [JEP 527](https://openjdk.org/jeps/527) (hybrid ML-KEM key exchange in TLS 1.3) targets JDK 27, and Oracle backported it to JDK 25.0.5 ([Oracle JDK 25.0.5 release notes](https://www.oracle.com/java/technologies/javase/25-0-5-relnotes.html): X25519MLKEM768, SecP256r1MLKEM768 and SecP384r1MLKEM1024, with X25519MLKEM768 most preferred by default). So 25.0.5+ and 27 both qualify; 25.0.0 to 25.0.4 do not (Documented; 25.0.5 Tested on Corretto and Temurin).

Three exceptions bypass JSSE and bring their own TLS library, so the JDK version does not matter for them:

- **Netty with `netty-tcnative-boringssl-static`** (`SslProvider.OPENSSL`): BoringSSL decides. Tested PQ by default on JDK 17 and 21.
- **AWS SDK for Java v2 CRT HTTP client** (`AwsCrtHttpClient`): s2n-tls on Linux decides. PQ by default from SDK 2.35.11 ([AWS SDKs and Tools guide](https://docs.aws.amazon.com/sdkref/latest/guide/pqtls-details.html)).
- **Tomcat with the OpenSSL implementation** (Tomcat Native or the FFM OpenSSL connector): the linked OpenSSL decides (not tested here; see the Web servers and proxies tab for OpenSSL 3.5 group rules).

Oracle has said it will bring PQC to its LTS releases 21, 17, 11 and 8 ([Oracle Java blog, 2026-08](https://blogs.oracle.com/java/post-quantum-cryptography-in-long-term-support-jdk-releases)); secondary reports put 21/17 in H1 2027 and 11/8 in H2 2027 (Claimed, not shipped). Remove the kit when your vendor ships it.

## Versions and native support

| Version | TLS stack | PQ client by default? | PQ server by default? | API to set groups | FIPS-mode behaviour | Proposed solution | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| JDK 25.0.5+ (Corretto, Temurin) | SunJSSE | Yes on every compute type (Lambda `java25`, `lambda/java:25`, `amazoncorretto:25`, `eclipse-temurin:25`, Corretto 25 on AL2023) | Yes (Tomcat, Jetty, `HttpsServer`, Netty JDK provider) | `-Djdk.tls.namedGroups`, `SSLParameters.setNamedGroups` (JDK 20+), Tomcat `SSLHostConfig groups` | Depends on the FIPS provider in use; not tested | Upgrade. No other change. Optional: `ssl.KeyManagerFactory.algorithm=PKIX` if one keystore holds several certificates for SNI (see case C) | Tested (client, server, keystores, mTLS); Documented ([25.0.5 notes](https://builds.shipilev.net/backports-monitor/release-notes-25.0.5.txt)) |
| JDK 21 (21.0.13) | SunJSSE | No (Lambda, container, EC2) | No | `jdk.tls.namedGroups` (no ML-KEM names) | Not tested | pq-tls kit v2 (agent + `pq-tls.security`), or upgrade to 25 | Tested |
| JDK 17 (17.0.21) | SunJSSE | No | No | Same | Not tested | Kit v2, or upgrade | Tested |
| JDK 11 | SunJSSE | No | No | Same | Not tested | Kit v2 | Tested on Lambda `java11` (kit v1, client); server and mTLS not tested |
| JDK 8 | SunJSSE, TLS 1.2 client default | No | No | Same | Not tested | Kit v2 + `-Djdk.tls.client.protocols=TLSv1.3,TLSv1.2` | Tested on Lambda `java8.al2023` (kit v1, client); server and mTLS not tested |
| Any JDK + Netty tcnative-boringssl-static 2.0.85 | BoringSSL | Yes | Yes | `OpenSslContextOption.GROUPS`; also reads `jdk.tls.namedGroups` | n/a | Nothing (keep it) | Tested |
| Any JDK + AWS SDK v2 CRT client (2.35.11+) | s2n-tls | Yes, AWS API calls only | n/a | n/a | Not tested | Nothing; CRT before 2.35.11: upgrade | Tested (2.59.1); Documented |

### By JDK and compute type

All "Tested" rows ran on 2026-11-14 in containers (arm64) against an OpenSSL 3.5.7 PQ-only server (`-tls1_3 -groups X25519MLKEM768`, or nginx `ssl_ecdh_curve X25519MLKEM768`) and a classical-only server (`X25519`). PQ = the PQ-only server connected; every row also connected to the classical server, so fallback works. Images: `eclipse-temurin:17-jre` (17.0.21), `:21-jre` (21.0.13), `:25-jre` (25.0.5), `amazoncorretto:25` (25.0.5), pinned by digest in the test output. Kit = agent v2 + pq-tls.security; v1 rows were tested with the v1 agent.

| JDK | Lambda zip | Lambda image | Fargate / ECS / EKS | EC2 | Evidence |
|----|----|----|----|----|----|
| 25.0.5+ (Corretto, Temurin) | PQ: runtime `java25` | PQ: `lambda/java:25` | PQ: `amazoncorretto:25`, `eclipse-temurin:25` | PQ: Corretto 25 package | Tested (client and server); Documented ([25.0.5 release notes](https://builds.shipilev.net/backports-monitor/release-notes-25.0.5.txt)) |
| 21 (21.0.13) | Not PQ; agent gives PQ | Not PQ; agent gives PQ | Not PQ; agent or static `java.security` gives PQ | Same as containers | Tested |
| 17 (17.0.21) | Not PQ; agent gives PQ | Not PQ; agent gives PQ | Not PQ; agent or static gives PQ | Same as containers | Tested |
| 11 | Not PQ; agent gives PQ | Not PQ; agent gives PQ | Agent gives PQ | Same as containers | Tested on Lambda `java11` (kit); containers Unverified |
| 8 | Agent + `jdk.tls.client.protocols=TLSv1.3,TLSv1.2` gives PQ | Same | Same | Same | Tested on Lambda `java8.al2023` (kit) |

### Decision guide

- On JDK 25.0.5 or later, change nothing. Look for pins (case F).
- On JDK 8 to 21, roll out kit v2 and plan the upgrade to 25. Kit v2 = `pq-tls-agent.jar` v2 + `pq-tls.security` in `JAVA_TOOL_OPTIONS`.
- Already shipped kit v1 (agent only)? Add `-Djava.security.properties=<dir>/pq-tls.security`, or swap in the v2 agent jar. This is required if any JVM uses an EC certificate, as a server or as an mTLS client.
- If you use Netty tcnative or the CRT client, those connections are already PQ. Everything else in the same JVM still needs the kit.
- On a FIPS JVM, don't add the kit (case G).

## Cases: what to change

All Tested rows in this section: 2026-11-14, containers (arm64), `eclipse-temurin:17-jre` 17.0.21, `:21-jre` 21.0.13, `:25-jre` 25.0.5 (digests in the output files), BC 1.87. The test peers are OpenSSL 3.5.7 on `debian:trixie-slim`. "PQ" means OpenSSL printed `Negotiated TLS1.3 group: X25519MLKEM768`. Every PQ row also connected with a classical-only peer (`-groups X25519`), unless the row says it is PQ-only. Kit v2 = `JAVA_TOOL_OPTIONS=-Djava.security.properties=/opt/pq-tls/pq-tls.security -javaagent:/opt/pq-tls/pq-tls-agent.jar`.

### A. Simple client (default HTTP client, AWS SDK, JDBC driver, no TLS code)

**Who this is:** no `SSLContext`, `KeyManager` or `TrustManager` code; `grep -rE 'SSLContext|KeyManagerFactory|TrustManagerFactory|namedGroups' src/` finds nothing.

**What happens today:** classical on 8 to 21, PQ on 25.0.5+ (Tested; see the library table).

**What to change:** nothing in code. JDK 25.0.5+, or kit v2 on 8 to 21.

**Side effects:** the ClientHello grows by about 1.2 KB. BCJSSE becomes the TLS provider for the whole JVM.

#### By library (client side)

| Client | JDK 17 / 21 | JDK 17 / 21 + agent | JDK 25.0.5 | Evidence |
|----|----|----|----|----|
| JDK `HttpClient`, `HttpsURLConnection` | No | PQ | PQ | Tested |
| Apache HttpClient 5.6.5 and 4.5.14 | No | PQ | PQ | Tested |
| OkHttp 4.12.0 | No | PQ | PQ | Tested (also Corretto 25) |
| Netty 4.2.20, JDK provider | No | PQ | PQ | Tested |
| Netty 4.2.20 + `netty-tcnative-boringssl-static` 2.0.85 | **PQ** | PQ | PQ | Tested |
| AWS SDK 2.59.1 `ApacheHttpClient` | No | PQ | PQ | Tested (server logged the group) |
| AWS SDK 2.59.1 `NettyNioAsyncHttpClient`, tcnative on the class path | **PQ** | PQ | PQ | Tested; it picked BoringSSL. Without tcnative it uses JSSE like the Apache row (not run) |
| AWS SDK 2.59.1 `AwsCrtHttpClient` (aws-crt 0.50.0) | **PQ** | PQ | PQ | Tested; Documented from 2.35.11 |
| AWS SDK 2.35.10 `AwsCrtHttpClient` (aws-crt 0.38.9) | No | n/a | n/a | Tested |
| PostgreSQL JDBC 42.7.14 to PostgreSQL 18 with `ssl_groups=X25519MLKEM768` | No (21) | PQ (21) | PQ | Tested |
| Static BCJSSE via `java.security`, no agent | n/a | PQ (17, 21), with or without `jdk.tls.namedGroups` | n/a | Tested |

#### Client libraries

Almost every Java client library hands TLS to JSSE, so it follows the JDK row of the status matrix with no library setting. Only TLS 1.2 pins and explicit group lists stop it. Three clients bring their own TLS library and are PQ on any JDK: Netty with tcnative-boringssl, the AWS SDK's Netty client when tcnative is on the class path, and the AWS SDK's CRT client.

| Library | TLS engine | What to set for PQ | Evidence |
|----|----|----|----|
| JDK `java.net.http.HttpClient` | JSSE | Nothing on 25.0.5+; agent on 8 to 21 | Tested |
| `HttpsURLConnection` | JSSE | Same | Tested |
| Apache HttpClient 5 (`HttpClients.createSystem()`) | JSSE | Same; keep `TLS.V_1_3` in `ClientTlsStrategyBuilder.setTlsVersions` | Tested 5.6.5 |
| Apache HttpClient 4 | JSSE | Same; don't build `SSLConnectionSocketFactory` with `new String[]{"TLSv1.2"}` | Tested 4.5.14 |
| OkHttp | JSSE (platform) | Same; `ConnectionSpec.MODERN_TLS` keeps 1.3 | Tested 4.12.0 |
| Netty, `SslProvider.JDK` | JSSE | Same | Tested 4.2.20 |
| Netty + `netty-tcnative-boringssl-static`, `SslProvider.OPENSSL` | BoringSSL | Nothing, on any JDK | Tested 4.2.20 / 2.0.85 |
| Spring `WebClient` (Reactor Netty), `RestClient`, `RestTemplate` | Reactor Netty (JDK provider unless tcnative is configured) or JSSE | Same as the engine underneath | Not run |
| AWS SDK v2 `ApacheHttpClient`, `UrlConnectionHttpClient` | JSSE | Same as the JDK | Tested (Apache) |
| AWS SDK v2 `NettyNioAsyncHttpClient` | Netty: BoringSSL if tcnative is present, else JSSE | Add tcnative, or `.sslProvider(SslProvider.OPENSSL)` explicitly | Tested 2.59.1 with tcnative |
| AWS SDK v2 `AwsCrtHttpClient`, `AwsCrtAsyncHttpClient` | s2n-tls on Linux; OS library on macOS/Windows | SDK 2.35.11+ (Documented); 2.35.10 was classical (Tested) | Tested 2.59.1 |
| PostgreSQL JDBC | JSSE | Same; `sslmode=verify-full` | Tested 42.7.14 |
| MySQL Connector/J | JSSE | Same; keep `TLSv1.3` in `tlsVersions` | Not run |
| Lettuce (Redis) | Netty, JDK provider by default | Same as JDK, or `SslOptions.builder().openSslProvider()` + tcnative | Not run |
| Jedis (Redis) | JSSE | Same as JDK | Not run |
| Kafka Java client | JSSE `SSLEngine` | Same; keep `ssl.enabled.protocols=TLSv1.3,TLSv1.2`, leave `ssl.provider` empty | Not run |

Rows marked "Not run" use JSSE through standard APIs, so they should follow the JDK row; treat them as Unverified until the live test in "How to test" passes for your build. Server-side settings for databases, Redis and Kafka brokers are on the Databases and data services tab.

### B. Simple server (framework default TLS)

**Who this is:** Spring Boot `server.ssl.*` or an SSL bundle, Tomcat `server.xml`, Jetty, `HttpsServer`, Quarkus or Micronaut that terminate TLS in the JVM. If an ALB, NLB TLS listener, API Gateway or CloudFront terminates TLS in front of you, set the PQ policy there instead (Load balancers and Edge tabs).

**What happens today:** classical on 8 to 21, PQ on 25.0.5+ (Tested: Tomcat 11.0.29, Jetty 12.1.15, `HttpsServer`, Netty).

**What to change:** JDK 25.0.5+, or kit v2. With kit **v1**, a server with an EC certificate fails every handshake, PQ or classical. Kit v2 fixes this (case C).

**Side effects:** clients that don't offer ML-KEM still connect (Tested).

#### By server (server side)

| Server | JDK 21 default | JDK 17 / 21 + BCJSSE | JDK 25.0.5 default | Evidence |
|----|----|----|----|----|
| Tomcat 11.0.29 embedded (JSSE) | Not PQ | PQ with RSA or EC certificate with kit v2 (`ssl.KeyManagerFactory.algorithm=PKIX`); EC fails without it | PQ, and preferred | Tested |
| Tomcat 11.0.29 with `groups="X25519MLKEM768,x25519"` | Not PQ (name unknown to SunJSSE 21, ignored) | n/a | PQ | Tested |
| Tomcat 11.0.29 with `groups="x25519,secp256r1"` | n/a | n/a | Not PQ (the pin removes it) | Tested |
| Jetty 12.1.15 | Not PQ | PQ with kit v2; fails with EC without the PKIX setting (Tested 17, 21) | PQ | Tested |
| JDK `HttpsServer` | n/a | PQ with kit v2; fails with EC without the PKIX setting (Tested 17, 21) | PQ | Tested |
| Netty 4.2.20 + tcnative-boringssl-static 2.0.85 | **PQ** (default and with `GROUPS`) | n/a | PQ | Tested |
| Netty 4.2.20, JDK provider | Not PQ | n/a | PQ | Tested on 25 |
| Undertow; Spring Boot on Tomcat, Jetty or Undertow; Quarkus; Micronaut | Follow the JSSE rows |  |  | Not run; same JSSE engine |

#### Front door and order of preference

If the Java service sits behind an ALB, an NLB TLS listener, API Gateway or CloudFront, the client-facing handshake happens there, not in the JVM: set the PQ policy on the front door (Load balancers tab, Edge and API front doors tab). The JVM's own server TLS matters for end-to-end TLS (ALB-to-target re-encryption, NLB TCP pass-through, internal services without a mesh).

Order of preference for a JVM that terminates TLS:

1.  **JDK 25.0.5+.** Tomcat, Jetty, the JDK `HttpsServer` and Netty (JDK provider) negotiate X25519MLKEM768 with no setting, and classical clients still connect (Tested). Undertow uses the same engine (not run).

2.  **Netty with `netty-tcnative-boringssl-static`** on any JDK (gRPC-Java, Reactor Netty, Vert.x with native SSL): PQ by default (Tested on JDK 21).

3.  **JDK 17/21 + kit v2.** Works with RSA and EC certificates (Tested on 17 and 21: Tomcat 11.0.29, Jetty 12.1.15, `HttpsServer`, Spring Boot 3.5.16). The earlier EC failure was the key manager: BC asks for key type `EC/secp256r1`, and the JDK default `SunX509` key manager returns no alias for it. `ssl.KeyManagerFactory.algorithm=PKIX` makes BC use its own key manager.

4.  **Otherwise:** put a PQ-capable proxy in front (nginx or Envoy on OpenSSL 3.5, see the Web servers and proxies tab), or terminate on an ALB with a PQ policy.

#### Spring Boot (embedded Tomcat, Jetty or Undertow)

Spring Boot 4.1.2 has no named-group property; SSL bundles expose protocols and ciphers ([Spring Boot SSL reference](https://docs.spring.io/spring-boot/reference/features/ssl.html)). On JDK 25.0.5+ do nothing beyond keeping TLS 1.3 enabled:

``` yaml
spring:
  ssl:
    bundle:
      jks:
        web:
          options:
            enabled-protocols: [TLSv1.3, TLSv1.2]
server:
  ssl:
    bundle: web
```

To restrict or reorder groups, put `-Djdk.tls.namedGroups=X25519MLKEM768,x25519,secp256r1,secp384r1` in `JAVA_TOOL_OPTIONS`; embedded Tomcat's `groups` defaults to it, and Jetty and Undertow read it through the JDK. A `TomcatConnectorCustomizer` that calls `setGroups` is in the full files (Unverified).

#### Standalone Tomcat (`server.xml`)

Tomcat 11.0.12 added a `groups` attribute on `SSLHostConfig` (also in the 10.1 and 9.0 lines); its default is `jdk.tls.namedGroups` ([Tomcat 11 HTTP connector](https://tomcat.apache.org/tomcat-11.0-doc/config/http.html)). It only picks among groups the TLS engine knows.

``` xml
<SSLHostConfig protocols="TLSv1.3+TLSv1.2"
               groups="X25519MLKEM768,x25519,secp256r1,secp384r1">
```

- JSSE implementation on JDK 25.0.5+: PQ (Tested via the embedded API, Tomcat 11.0.29).

- JSSE on JDK 21 without BCJSSE: the name is ignored and the server stays classical (Tested).

- OpenSSL implementation (Tomcat Native or the FFM OpenSSL connector): the docs don't mark `groups` as JSSE-only, so it should pass to OpenSSL; with OpenSSL 3.5 underneath that would give PQ. Not tested.

- A list without `X25519MLKEM768` turns PQ off on JDK 25 (Tested).

- For JDK 17/21, `bin/setenv.sh` adds kit v2 (agent + `pq-tls.security`) through `CATALINA_OPTS` (full files).

#### Jetty, Undertow, JDK `HttpsServer`

No group setting in their TLS objects; they follow the JDK and `jdk.tls.namedGroups`. Jetty 12.1.15 on JDK 25.0.5: PQ (Tested).

#### Netty server (gRPC-Java, Reactor Netty, Vert.x)

``` java
SslContext ctx = SslContextBuilder.forServer(kmf)
        .sslProvider(SslProvider.OPENSSL)   // tcnative-boringssl-static on the class path
        .protocols("TLSv1.3", "TLSv1.2")
        .build();                           // optional .option(OpenSslContextOption.GROUPS, ...)
```

When `jdk.tls.namedGroups` is set, Netty logs `Using configured namedGroups -D 'jdk.tls.namedGroup': [...]` and uses that list for BoringSSL too, so a classical pin turns PQ off even with tcnative (Tested).

#### Quarkus and Micronaut

Quarkus (Vert.x) and Micronaut (Netty) follow the JDK rows with the JDK SSL engine and the Netty tcnative row with native SSL. Neither was run here; confirm the engine from the startup log before claiming PQ.

### C. Existing server certificates in a custom keystore or cert files

**Who this is:** the JVM loads its own certificate and key. Find it with:

```bash
grep -rnE 'javax\.net\.ssl\.keyStore|KeyManagerFactory|KeyStore\.getInstance|certificateKeystore|server\.ssl\.(key-store|bundle)|spring\.ssl\.bundle|keyManagerAlgorithm|setKeyStorePath' \
  src/ conf/ *.yml *.yaml *.properties Dockerfile* helm/ 2>/dev/null
keytool -list -v -keystore server.p12 -storetype PKCS12 | grep -E 'Alias name|Entry type|Signature algorithm|Subject Public Key Algorithm'
```

**What changes in the store: nothing.** You don't re-issue, convert or re-import any certificate or key. Keep the RSA or EC key, PKCS#12 or JKS, the aliases, the passwords and the system properties that point at the store.

**What to change:** one security property, and on JDK 8 to 21 only:

```properties
# pq-tls/pq-tls.security, loaded with -Djava.security.properties=/opt/pq-tls/pq-tls.security
ssl.KeyManagerFactory.algorithm=PKIX
```

Kit v2 ships this file, and every packaging excerpt below already passes it. The v2 agent also sets the property itself when it is still the JDK default `SunX509`. That covers apps whose own `-Djava.security.properties` on the command line replaces the kit's flag (Tested). Code that names a key manager algorithm itself must stop naming `SunX509`:

```java
// Fails with an EC certificate under BCJSSE (JDK 8-21 + agent):
KeyManagerFactory kmf = KeyManagerFactory.getInstance("SunX509");
// Works everywhere, and picks up the kit's PKIX default:
KeyManagerFactory kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
```

```xml
<!-- Tomcat server.xml: drop keyManagerAlgorithm="SunX509", or set PKIX -->
<SSLHostConfig protocols="TLSv1.3+TLSv1.2" keyManagerAlgorithm="PKIX">
```

**Tested proof** (`v2/out/t17-v2kit.txt`, `t21-v2kit.txt`, `t21-v1nofix.txt`, `t17-v1nofix.txt`, `t25-none.txt`, `t25-file.txt`, `tomcat-sb.txt`):

| Keystore situation | JDK 17/21 + kit v1 (no fix) | JDK 17/21 + kit v2 | JDK 25.0.5, no kit |
| --- | --- | --- | --- |
| EC P-256 only, PKCS#12 | **Fails** (handshake_failure, also for classical clients) | PQ; classical client connects | PQ |
| RSA only, PKCS#12 | PQ | PQ | PQ |
| RSA + EC in one PKCS#12 | PQ, but always serves RSA; the EC entry is ignored | PQ, serves EC; a client offering only RSA signature algorithms gets RSA | PQ, serves EC |
| Two EC certs in one store, SNI per hostname | **Fails** | PQ, right cert per SNI name | PQ, but **SNI ignored**: the default `SunX509` key manager served `alt-host`'s cert for `ks-java`. With `pq-tls.security` (PKIX): right cert per name |
| EC in a legacy JKS | **Fails** | PQ | PQ |
| Store given by `-Djavax.net.ssl.keyStore`/`keyStorePassword`/`keyStoreType` | **Fails** | PQ | PQ |
| App passes its own `-Djava.security.properties` on the command line (replaces the kit file) | **Fails** | PQ (agent v2 fallback); with kit v1 + file: **fails** | PQ |
| Code hard-codes `KeyManagerFactory.getInstance("SunX509")` | **Fails** | **Still fails**: change the code | PQ |
| Tomcat 11.0.29 `SSLHostConfig` default `keyManagerAlgorithm` (EC) | Fails (lead test, `java/out/bcserver4.txt`) | PQ | PQ |
| Tomcat `keyManagerAlgorithm="SunX509"` (EC) | Fails | **Still fails**: remove it or set `PKIX` | not run |
| Tomcat `keyManagerAlgorithm="PKIX"`, kit fix switched off | n/a | PQ (explicit PKIX is enough) | not run |
| Spring Boot 3.5.16 `spring.ssl.bundle.jks` with an EC PKCS#12 | Fails (agent with the fix switched off) | PQ; classical client connects | not run |

- Spring Boot SSL bundles: `SslManagerBundle` and `DefaultSslManagerBundle` in `spring-boot-3.5.16.jar` call `KeyManagerFactory.getDefaultAlgorithm()` (checked with `javap`), so the kit property reaches them. No bundle change. A `key.alias` in the bundle still selects the alias.
- RSA vs EC: RSA keys never needed the fix, because BC asks for key type `RSA` and SunX509 answers. EC keys need it. **PEM pairs** (`spring.ssl.bundle.pem`, Tomcat `certificateFile`/`certificateKeyFile`) become an in-memory keystore with the same key manager, so the same rule applies. Not run separately.
- **Encrypted keys and key passwords:** PKCS#12 entries are always encrypted with the store password (tested above). JKS entries with a separate key password (`certificateKeyPassword`, `server.ssl.key-password`) go through the same `KeyManagerFactory.init(ks, keyPassword)`, so the fix doesn't change them. Not run separately.
- BC is stricter than SunJSSE on certificate chains: it applies the client's `signature_algorithms` to the whole chain. A client offering only `rsa_pss_rsae_sha256` was refused an RSA cert whose CA signed with PKCS#1; adding `rsa_pkcs1_sha256` fixed it (lead test, `java/ks/run-ks2.out`, `run-ks3.out`). Modern clients offer both.
- PKCS#11/HSM keystores (`KeyStore.getInstance("PKCS11")`): see case I.

**Side effects:** with RSA and EC in one store, kit v2 starts serving the EC certificate to clients that support it (v1 served RSA). Check certificate pinning on clients (case I). On JDK 25 the property also turns on SNI-based certificate selection, so that SunJSSE stops serving the wrong certificate from a multi-cert store.

### D. Custom CA trust (private CA)

**Who this is:**

```bash
grep -rnE 'javax\.net\.ssl\.trustStore|TrustManagerFactory|X509TrustManager|truststore|trust-store|keytool .*-importcert|cacerts' \
  src/ conf/ Dockerfile* helm/ *.yml *.yaml *.properties 2>/dev/null
```

Typical setups: the private CA is imported into the JDK `cacerts` (`keytool -importcert -cacerts`) in the image, a separate truststore is passed with `-Djavax.net.ssl.trustStore`, a Spring SSL bundle has a `truststore`, or the code builds a `TrustManagerFactory` from a file.

**What changes in the store: nothing.** BCJSSE uses the JDK's trust settings: `javax.net.ssl.trustStore*` when set, else `$JAVA_HOME/lib/security/cacerts` (`jssecacerts` first, if it exists). Don't move the CA anywhere.

**What to change:** nothing, on any JDK. Keep the CA-import step in the Dockerfile, the system properties and the trust code. `ssl.TrustManagerFactory.algorithm` stays `PKIX` (the JDK default); the kit doesn't touch it.

**Tested proof** (BCJSSE client on JDK 17 and 21 with kit v1 and v2; SunJSSE on JDK 25, against a **PQ-only** OpenSSL 3.5 server whose cert is from the private CA):

| Trust setup | JDK 17/21 + kit | JDK 25.0.5 | Evidence |
| --- | --- | --- | --- |
| No private CA configured | Fails `certificate_unknown(46)` (correct) | Fails `PKIX path building failed` (correct) | `v2/out/t*-*.txt` |
| `-Djavax.net.ssl.trustStore=trust.p12` (+ `trustStorePassword`, `trustStoreType=PKCS12`) | Connects, TLS 1.3 PQ | Connects | `v2/out/t21-v2kit.txt`, `t17-v2kit.txt`, `t25-none.txt` |
| CA imported into JDK `cacerts` with `keytool -importcert -cacerts` | Connects, PQ | not run | `java/ks/run-ks.out` (JDK 21) |
| `cacerts` import + kit fix property | Connects, PQ | n/a | `java/ks/run-ks.out` |
| JVM server truststore for client certificates (`needClientAuth` + `javax.net.ssl.trustStore`) | Accepts CA-signed client certs, rejects certs from an unknown CA | Same | case E |

- Code with its own `TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())` and `init(keyStore)`: same path as the trustStore row. Not run as separate code.
- Spring Boot `spring.ssl.bundle.*.truststore`: `DefaultSslManagerBundle` uses `TrustManagerFactory.getDefaultAlgorithm()` (javap), so trust is the same as above. Not run as a client.
- Custom `X509TrustManager` (including trust-all code): BCJSSE calls it like SunJSSE does. Not run. Trust-all code is a finding in its own right.
- Netty tcnative and the CRT client use their own trust inputs. Netty takes the trust manager you pass to `SslContextBuilder.trustManager(...)`. CRT uses the OS store or `TlsContextOptions` with a CA file. Neither was run with a private CA.

**Side effects:** none found.

### E. Mutual TLS (client certificates)

**Who this is:** a server with `needClientAuth`/`wantClientAuth`, Tomcat `certificateVerification="required"`, Spring `server.ssl.client-auth=need`, or a client that loads its own cert with `-Djavax.net.ssl.keyStore` or a `KeyManagerFactory`. Grep: `clientAuth|client-auth|certificateVerification|setNeedClientAuth|setWantClientAuth`.

**What happens today (kit v1, JDK 17/21):** a JVM **client** with an **EC** client certificate silently sends **no certificate**, and the server answers `certificate_required(116)`. RSA client certs work. A JVM **server** with an EC server cert fails before client auth even starts (case C). Tested: `v2/out/t21-v1nofix.txt`, `t17-v1nofix.txt`.

**What to change:** kit v2 (the same PKIX property). No change to client or server stores.

**Tested proof** (kit v2 on JDK 17 and 21; JDK 25.0.5 without a kit gives the same results):

| Direction | Result |
| --- | --- |
| BCJSSE server, `needClientAuth`, trust = private CA; OpenSSL 3.5 client with an EC client cert, `-groups X25519MLKEM768` | PQ; server logged `client-cert=CN=client-ec` |
| Same server, RSA client cert | PQ; `client-cert=CN=client-rsa` |
| Same server, no client cert | Server refused: `certificate_required(116)` (correct) |
| Same server, client cert from an unknown CA | Server refused (correct) |
| BCJSSE server PQ-only (`-Djdk.tls.namedGroups=X25519MLKEM768`), X25519-only client | Refused (correct); with EC client cert and PQ: OK |
| BCJSSE client, `-Djavax.net.ssl.keyStore=client-ec.p12` → OpenSSL 3.5 `s_server -tls1_3 -groups X25519MLKEM768 -Verify 1 -CAfile ca.crt` | Connects; `s_server` verified `CN=client-ec` |
| Same, `client-rsa.p12` | Connects; verified `CN=client-rsa` |
| Same, no keystore | Refused `certificate_required` (correct) |
| BCJSSE client (EC cert) → BCJSSE PQ-only server | Connects, both certs exchanged |

**Side effects:** the client closes with a harmless `Broken pipe` after the response when the server shuts the socket first (test artefact, seen on 17 and 21).

### F. Explicit TLS settings that block PQ

**Who this is:** run the CI check (`ci/java-pq-check.sh`, full file at the end), or:

```bash
grep -rnE 'jdk\.tls\.namedGroups|setNamedGroups|groups="|OpenSslContextOption\.GROUPS|SSLContext\.getInstance\("TLSv1\.2"\)|TLS\.V_1_2|protocols="TLSv1\.2"|enabled-protocols|ssl\.enabled\.protocols|tlsVersions|jdk\.tls\.client\.protocols|KeyManagerFactory\.getInstance\("SunX509"|keyManagerAlgorithm' .
```

| Setting | Effect | Change to |
| --- | --- | --- |
| `jdk.tls.namedGroups` without `X25519MLKEM768` | Classical on every JDK including 25, also for Netty tcnative (Tested). The agent leaves an existing value alone | `X25519MLKEM768,x25519,secp256r1,secp384r1` |
| Tomcat `groups="x25519,secp256r1"` | Classical on 25 (Tested) | Add `X25519MLKEM768` first |
| `SSLContext.getInstance("TLSv1.2")`, `TLS.V_1_2` only, `enabled-protocols: [TLSv1.2]`, Kafka `ssl.enabled.protocols=TLSv1.2`, Connector/J `tlsVersions=TLSv1.2` | No TLS 1.3, so no ML-KEM | `"TLS"`, or list `TLSv1.3,TLSv1.2` |
| `KeyManagerFactory.getInstance("SunX509")`, Tomcat `keyManagerAlgorithm="SunX509"` | EC certs fail under BCJSSE (Tested) | `getDefaultAlgorithm()` or `"PKIX"` |
| `-Djava.security.properties==file` (double `=`) | Replaces all of `java.security`, so the kit line is lost | Single `=`, or add the kit line to that file |
| Cipher lists (`ciphers=`, `setEnabledCipherSuites`) | Don't block ML-KEM if a TLS 1.3 suite stays (`TLS_AES_128_GCM_SHA256` etc.) | Keep at least one TLS 1.3 suite |

#### What to change, by library

Remove TLS 1.2 pins (any JSSE client):

``` java
SSLContext ctx = SSLContext.getInstance("TLSv1.2"); // blocks PQ: TLS 1.2 only
SSLContext ctx = SSLContext.getInstance("TLS");     // PQ-capable: the provider picks TLS 1.3
```

Apache HttpClient 5 with a custom TLS strategy:

``` java
var tls = ClientTlsStrategyBuilder.create()
        .setSslContext(SSLContexts.createSystemDefault())
        .setTlsVersions(TLS.V_1_3, TLS.V_1_2)   // keep 1.3
        .build();
```

Netty with BoringSSL (PQ on any JDK; the explicit list is optional):

``` java
SslContext ctx = SslContextBuilder.forClient()
        .sslProvider(SslProvider.OPENSSL)
        .option(OpenSslContextOption.GROUPS, new String[]{"X25519MLKEM768", "X25519", "P-256"})
        .build();
```

AWS SDK for Java v2 with the CRT client (PQ for AWS API calls on any JDK):

``` java
KmsClient kms = KmsClient.builder()
        .httpClient(AwsCrtHttpClient.create())
        .build();
```

Before 2.35.11 the CRT builder needed `.postQuantumTlsEnabled(true)` ([AWS Security Blog](https://aws.amazon.com/blogs/security/ml-kem-post-quantum-tls-now-supported-in-aws-kms-acm-and-secrets-manager)); upgrade rather than rely on the flag. The CRT route covers AWS calls only; other HTTPS calls in the same JVM still follow the JDK.

#### JVM flags that matter

| Flag | Effect |
|----|----|
| `-Djdk.tls.namedGroups=X25519MLKEM768,x25519,secp256r1,secp384r1` | Group order. A list without `X25519MLKEM768` turns PQ off, on JDK 25 too and for Netty tcnative too (Tested) |
| `-Djdk.tls.client.protocols=TLSv1.3,TLSv1.2` | Java 8 only (8 defaults clients to TLS 1.2) |
| `-javaagent:<dir>/pq-tls-agent.jar` | JDK 8 to 21: BCJSSE first + group list |
| `-Djava.security.properties=<file>` | Static BC registration (containers and EC2, not Lambda) |
| `-Djava.security.properties=<dir>/pq-tls.security` | Kit v2: `ssl.KeyManagerFactory.algorithm=PKIX`, needed for EC certs under BCJSSE (Tested) |


### G. FIPS mode

**Who this is:** `bc-fips`/`bctls-fips` jars, `BouncyCastleFipsProvider` in `java.security`, a vendor FIPS JDK, or Corretto/RHEL with the OS in FIPS mode (`-Dcom.redhat.fips=true`, `/proc/sys/crypto/fips_enabled` = 1).

**What happens today:** not tested here.

**What to change:** don't add the kit. It uses non-FIPS `bcprov`/`bctls` jars and would put a non-validated TLS provider first. Whether the BC FIPS line (`bctls-fips`) offers X25519MLKEM768 isn't confirmed ([BC FIPS 2.1 release notes](https://support.keyfactor.com/hc/en-us/articles/53287242078619-Bouncy-Castle-Java-FIPS-2-1-X-release-notes)). Track JDK 25 with your FIPS provider and your compliance team. The key manager point still holds for any BC JSSE (FIPS or not): use `PKIX`, not `SunX509`. That is Unverified for bctls-fips. For AWS API calls from a FIPS workload, use the AWS FIPS endpoints; PQ on them depends on the service (AWS service endpoints tab).

**Side effects:** n/a.

### H. Libraries with their own TLS stack, and agents

| Library | Stack | What the kit does | What to do | Evidence |
| --- | --- | --- | --- | --- |
| Netty + `netty-tcnative-boringssl-static` 2.0.85 (gRPC-Java, Reactor Netty, Vert.x/Quarkus native, Lettuce with OpenSSL) | BoringSSL | Nothing (BoringSSL is used) | Nothing; PQ by default. Don't pin `jdk.tls.namedGroups` without ML-KEM (Netty reads it) | Tested |
| Netty, `SslProvider.JDK` | JSSE | Kit applies | Follow the JDK row | Tested |
| AWS SDK v2 CRT client | s2n-tls | Nothing | SDK 2.35.11+ | Tested |
| AWS SDK v2 Apache / UrlConnection / Netty (no tcnative) | JSSE | Kit applies | Follow the JDK row | Tested (Apache) |
| JDBC (PostgreSQL 42.7.14, Connector/J), Kafka, Jedis | JSSE | Kit applies | Keep TLS 1.3 allowed | Tested (PostgreSQL); others follow JSSE |
| APM agents (Datadog, New Relic, OpenTelemetry) | JSSE for their exporters | Share `JAVA_TOOL_OPTIONS` | Append the kit, don't replace the variable | Not run |
| Conscrypt, wolfJSSE, Amazon Corretto Crypto Provider (ACCP) | Own provider | If registered at position 1 after the agent, it wins | Check `Security.getProviders()` order at startup. ACCP is a JCA provider, not JSSE, so it doesn't conflict | Not run |
| Tools the JVM shells out to (`curl`, `git`, `wget`) | Their own libraries | n/a | See Hosts and OS: GnuTLS builds have no ML-KEM; OpenSSL 3.5 builds do | Lead test |

Netty server code: see "Netty server (gRPC-Java, Reactor Netty, Vert.x)" under case B.

### I. Certificate or key pinning, and HSM/PKCS#11 or KMS-backed keys

- **Pinning (client side):** the kit doesn't change which certificate the *peer* serves, so client pins (OkHttp `CertificatePinner`, custom trust managers) keep working. One exception: a **server** with RSA and EC in the same store starts serving EC under kit v2 (case C). Clients that pin the RSA leaf or SPKI break. Pin the CA or both keys before you roll out, or keep one key type per store.
- **PKCS#11/HSM keys** (`KeyStore.getInstance("PKCS11")`, SunPKCS11, CloudHSM JCE provider): BCJSSE signs the handshake through the `PrivateKey` object, so the key must be usable through JCA `Signature`. Not tested here (no HSM). Test on the real HSM before rollout. If it fails, terminate TLS at an ALB/NLB with an ACM certificate, or move to JDK 25 (SunJSSE).
- **ACM / KMS-backed keys:** ACM private keys can't be exported to a JVM. KMS asymmetric keys can't back a JSSE `KeyManager` without a custom provider. Terminate at the AWS front door. Neither is affected by the kit.
- **ACM exportable certificates** in a keystore are ordinary keystores: case C.

### J. Other cases

- **HTTPS proxy (`https.proxyHost`, `HTTPS_PROXY` in SDKs):** with CONNECT, TLS is end to end, so PQ depends on the JVM and the origin. A TLS-inspecting proxy terminates TLS: then PQ depends on the proxy (Network devices and egress tab). Not run.
- **HTTP/2, gRPC and WebSockets** run over the same TLS handshake, so the same rows apply. gRPC-Java uses Netty: case H.
- **Service mesh sidecar** (Istio, Linkerd, App Mesh Envoy): if the app speaks plain HTTP to the sidecar, the mesh decides PQ (Service mesh tab). The kit only matters for TLS the JVM originates.
- **Lambda SnapStart:** the agent runs before the snapshot. Not tested.
- **Session resumption and 0-RTT:** not tested under BCJSSE.

## Solution and automation

1. **Inventory and detect.**
   - JDK per workload: `java -version` in the image or on EC2; Lambda `Runtime`; ECR image labels.
   - Kit presence: `JAVA_TOOL_OPTIONS` containing `pq-tls-agent.jar` **and** `pq-tls.security`. Running process: `jcmd <pid> VM.system_properties | grep -E 'java.version|jdk.tls.namedGroups|java.security.properties'`. Startup log: `pq-tls agent v2: ... ssl.KeyManagerFactory.algorithm=PKIX`.
   - Keystores and key types (case C greps, `keytool -list -v`), mTLS (case E greps).
   - Blocking settings: the CI check.
   - Traffic: CloudTrail `tlsDetails.keyExchange` for KMS, STS, IAM, Secrets Manager, ACM and Payment Cryptography calls.
2. **Change.** JDK 25.0.5+ where you can. Elsewhere, kit v2: copy `pq-tls/` (agent v2 jar, three BC jars, `pq-tls.security`) and set `JAVA_TOOL_OPTIONS`. If you already have kit v1, add the `pq-tls.security` flag (or swap the jar). Fix code from case F.
3. **Package per compute type** (full files at the end):

| Compute | JDK 25.0.5+ | JDK 8 to 21: kit v2 | JDK 11 to 21: static `java.security` |
| --- | --- | --- | --- |
| Lambda zip | Runtime `java25` | `pq-tls/` at the zip root; `JAVA_TOOL_OPTIONS=-Djava.security.properties=/var/task/pq-tls/pq-tls.security -javaagent:/var/task/pq-tls/pq-tls-agent.jar` | Doesn't work: the Lambda bootstrap class path is `/var/runtime/lib` only (Tested, kit) |
| Lambda layer | Not needed | Layer v2 (`/opt/pq-tls/{wrapper,pq-tls-agent.jar,pq-tls.security}`, `/opt/java/lib/*.jar`) + `AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper`. The v2 wrapper adds the `pq-tls.security` flag unless the function passes its own `java.security.properties` (Tested in a container with `AWS_EXECUTION_ENV=AWS_Lambda_java21`; not on Lambda) | Doesn't work |
| Lambda container image | `public.ecr.aws/lambda/java:25` | `COPY pq-tls/ ${LAMBDA_TASK_ROOT}/pq-tls/` + `ENV JAVA_TOOL_OPTIONS` (both flags) | Not tested |
| Fargate, ECS, EKS | `amazoncorretto:25`, `eclipse-temurin:25` | `COPY pq-tls/ /opt/pq-tls/` + `ENV JAVA_TOOL_OPTIONS="-Djava.security.properties=/opt/pq-tls/pq-tls.security -javaagent:/opt/pq-tls/pq-tls-agent.jar"`, or the same in the task definition or pod spec | `bc-static.security` (now includes the PKIX line) + BC jars on `-cp` (Tested for clients on 17 and 21; the PKIX line in this file was not run separately) |
| EC2 | Corretto 25 (`dnf install java-25-amazon-corretto-headless`) | systemd drop-in with both flags, or the SSM document | Same file via `ExecStart` |

Rules that apply everywhere:

- Append to an existing `JAVA_TOOL_OPTIONS`; don't replace it. APM agents (Datadog, New Relic, OpenTelemetry Java agent) often live there.

- On Java 8 add `-Djdk.tls.client.protocols=TLSv1.3,TLSv1.2`.

- Distroless images have no shell, but the JVM reads `JAVA_TOOL_OPTIONS` itself, so `ENV` works.

- `java -jar` ignores `-cp`: for static registration, list the BC jars in the app jar's manifest `Class-Path` or start with `-cp ... MainClass`.

- Lambda SnapStart: the agent runs before the snapshot, so the provider order is captured in it. Not tested with SnapStart.

- Pin images by digest and record the JDK patch level; the PQ default arrived in a patch release (25.0.5), not a major version.

- If the app already passes `-Djava.security.properties=<its file>` on the command line, that flag wins over the kit's. Either add `ssl.KeyManagerFactory.algorithm=PKIX` to the app's file, or rely on agent v2, which sets it when it finds the JDK default (Tested).

4. **CI guardrails.** Run `ci/java-pq-check.sh <repo>` in every build. It fails on group pins without ML-KEM, TLS 1.2-only pins, a hard-coded `SunX509` key manager and `java.security.properties==`. It warns on JDK below 25, kit v1 packaging (agent without `pq-tls.security`), tcnative/CRT/Conscrypt and FIPS providers. Tested on a fixture: 3 FAIL + 2 WARN on the bad tree (exit 1), 1 WARN on the good one (exit 0), `v2/out/ci-check.txt`. For images, also check the base tag in the registry policy: JDK below 25 without the kit is non-compliant.
5. **Fleet rollout.**
   - Canary one task, pod, alias or instance per service. Lambda: a weighted alias, 10% on the version with the new `JAVA_TOOL_OPTIONS`.
   - Watch handshake errors (`handshake_failure`, `certificate_required`, `certificate_unknown`) in app logs and ALB `TargetTLSNegotiationErrorCount`.
   - Check the startup line, then run the live tests in "How to test".
   - Widen by environment (dev → qa → prod).
   - Servers with EC certs or mTLS clients: canary with kit v2 only, never v1.
6. **Rollback.** See Pitfalls and rollback.

## How to test

1. **Posture.** `java -version`; the startup log shows `Picked up JAVA_TOOL_OPTIONS: -Djava.security.properties=.../pq-tls.security -javaagent:...` and `pq-tls agent v2: BCJSSE first, groups=X25519MLKEM768,..., ssl.KeyManagerFactory.algorithm=PKIX`. A JVM that prints `ssl.KeyManagerFactory.algorithm=SunX509` has the fix switched off.
2. **Local container test, client.** Start a PQ-only and a classical-only OpenSSL 3.5 server (script below, `openssl s_server -tls1_3 -groups X25519MLKEM768` and `-groups X25519`). Run your client image against both. Both must succeed.
3. **Server test.** `openssl s_client -connect <host>:8443 -tls1_3 -groups X25519MLKEM768 -brief` must print `Negotiated TLS1.3 group: X25519MLKEM768`. `-groups X25519` must still connect.
4. **Case C, your own keystore.** Start the server with your real store (copy, not the prod secret) under kit v2. Run step 3. Then run step 3 with `-servername <each SNI name>` and check the `Peer certificate` CN for each. For RSA+EC stores, also run `-sigalgs rsa_pss_rsae_sha256:rsa_pkcs1_sha256` to see what RSA-only clients get.
5. **Case D, your truststore.** Point the client at a PQ-only server whose cert comes from your private CA. It must connect with your truststore, and fail without it.
6. **Case E, mTLS.** Server side: `openssl s_client ... -cert client.crt -key client.key -groups X25519MLKEM768` must connect, and must be refused without `-cert`. Client side: run your client against `openssl s_server -tls1_3 -groups X25519MLKEM768 -Verify 1 -CAfile ca.crt ...`. The s_server log must show `depth=0 CN=<your client cert>`.
7. **In-cloud signal.** CloudTrail `tlsDetails.keyExchange = X25519MLKEM768` for the workload role's KMS/STS/Secrets Manager calls. Server: the ALB/NLB or the peer logs the negotiated group.
8. **Rollback test.** Remove the two flags (or set `PQ_TLS_DISABLE=1` with the layer) and restart. Step 2 against the PQ-only server must now fail, and the classical one must still work.

The repeatable harness used for this tab is `run-v2.sh` (full file at the end). It builds the keystores, then runs every row of cases C, D and E for one JDK image and one kit mode.

More signals:

- **Handshake trace.** SunJSSE: `-Djavax.net.debug=ssl:handshake` shows the ServerHello `key_share` group. BCJSSE: `java.util.logging` level `FINE` on `org.bouncycastle.jsse`.
- **Observed on AWS.** CloudTrail `tlsDetails.keyExchange` = `X25519MLKEM768` on KMS, STS, IAM, Secrets Manager, ACM and Payment Cryptography calls from the workload's role.
- **nginx as the PQ-only test server.** `ssl_ecdh_curve X25519MLKEM768;` makes nginx PQ-only, and `$ssl_curve` in `log_format` logs the negotiated group.

## Pitfalls and rollback

- **Kit v1 and EC certificates.** v1 (agent only) breaks every EC server certificate and silently drops EC client certificates (Tested on 17 and 21). Upgrade any v1 deployment to v2 before it reaches a service with EC certs or mTLS.
- **Hard-coded `SunX509`.** In code or in Tomcat `keyManagerAlgorithm`, it beats the kit (Tested). The CI check catches it.
- **The app's own security file wins.** A command-line `-Djava.security.properties` replaces the kit's flag from `JAVA_TOOL_OPTIONS`. Agent v2 covers that case (Tested); kit v1 + file doesn't.
- **JDK 25 multi-cert stores.** The default `SunX509` key manager ignores SNI and served the wrong certificate (Tested). Set `ssl.KeyManagerFactory.algorithm=PKIX` on JDK 25 too if one store holds several hostnames.
- **Served certificate type can change.** RSA+EC stores serve EC under kit v2 (case C). Check client pins.
- **BC chain strictness** on `signature_algorithms` (case C).

- **A pinned group list wins.** `jdk.tls.namedGroups` without `X25519MLKEM768` keeps any JDK classical, 25 included, and the agent leaves an existing value alone (Tested both). Grep launch scripts, Helm values and `JAVA_TOOL_OPTIONS` for it.

- **TLS 1.2 pins.** `SSLContext.getInstance("TLSv1.2")`, `jdk.tls.client.protocols=TLSv1.2`, `enabled-protocols: [TLSv1.2]`, Kafka `ssl.enabled.protocols=TLSv1.2` all block PQ.


- **BCJSSE is the provider for the whole process.** Mutual TLS, custom keystores and truststores were tested with kit v2 (cases C to E); still test PKCS#11 keys, session resumption and FIPS mode before rollout. If the app ships its own Bouncy Castle, the agent's 1.87 jars load first on the system class path; align the versions.

- **FIPS.** The agent uses non-FIPS `bcprov`/`bctls`. A FIPS JVM needs `bc-fips` + `bctls-fips`; whether the current FIPS line offers X25519MLKEM768 in BCJSSE is not confirmed ([BC Java FIPS 2.1.x release notes](https://support.keyfactor.com/hc/en-us/articles/53287242078619-Bouncy-Castle-Java-FIPS-2-1-X-release-notes)). Don't add the non-FIPS agent to a FIPS-mode JVM.

- **Agent ordering.** Another agent that reorders providers or replaces `SSLContext.getDefault()` can undo this one. Check the startup log.

- **Classical client against a PQ-only server.** Expected to fail; only enforce PQ-only on servers whose clients are all upgraded.

- **Larger ClientHello.** X25519MLKEM768 adds about 1.2 KB to the ClientHello. Middleboxes that mishandle a ClientHello split across packets break the first flight; Java doesn't retry with a classical share.

- **Rollback.** Remove `-javaagent:` (or the `java.security.properties` flag) from `JAVA_TOOL_OPTIONS` and restart; on JDK 25 set `-Djdk.tls.namedGroups=x25519,secp256r1,secp384r1`. On Lambda, delete the variable (or set `PQ_TLS_DISABLE=1` with the kit layer); the next cold start is classical. For the CRT client, swap back to `ApacheHttpClient` in the builder. Kit v2 rollback = remove both `-Djava.security.properties=.../pq-tls.security` and `-javaagent:`; removing only the agent leaves the harmless PKIX property.

## Full configuration files

Every file the sections above excerpt, complete. Keep the `pq-tls/` directory name: the agent's manifest finds its jars next to it. The kit is for JDK 8 to 21 only; remove it when the JDK reaches 25.0.5 or later. Files changed in v2 are given in full below. Unchanged files are moved from the old section.

The test scripts and raw output behind every "Tested" label are in the work folder `deep/java/` (`run-clients.sh`, `run-servers.sh`, `run-aws.sh`, `run-static-pg.sh`, `out/*.txt`) and, for kit v2, `deep/java/v2/` (`run-v2.sh`, `run-tomcat-sb.sh`, `out/*.txt`).

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
      # Java 8 clients default to TLS 1.2; ML-KEM exists only in TLS 1.3.
      case "$AWS_EXECUTION_ENV:$JAVA_TOOL_OPTIONS" in
        *java8*:*jdk.tls.client.protocols*) ;;
        *java8*:*) export JAVA_TOOL_OPTIONS="$JAVA_TOOL_OPTIONS -Djdk.tls.client.protocols=TLSv1.3,TLSv1.2" ;;
      esac
      echo "pq-tls: java: Bouncy Castle JSSE agent v2, JAVA_TOOL_OPTIONS=$JAVA_TOOL_OPTIONS" ;;
    *)
      # java25+: PQ by default. python3.11, nodejs18/20: no in-process path (OpenSSL < 3.5).
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

Zip layout (kit v2; java8.al2023, java11, java17, java21):

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
            - -Djava.security.properties=/var/task/pq-tls/pq-tls.security -javaagent:/var/task/pq-tls/pq-tls-agent.jar -Djdk.tls.client.protocols=TLSv1.3,TLSv1.2
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
      CompatibleRuntimes: [java8.al2023, java11, java17, java21, python3.12, python3.13, nodejs22.x]
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
  compatible_runtimes      = ["java8.al2023", "java11", "java17", "java21"]
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
