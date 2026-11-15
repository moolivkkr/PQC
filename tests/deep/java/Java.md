# Java runbook

## What decides PQ here

(see doc tab; text as published 2026-11-14)

## Status matrix

All "Tested" rows ran on 2026-11-14 in containers (arm64) against an OpenSSL 3.5.7 PQ-only server (`-tls1_3 -groups X25519MLKEM768`, or nginx `ssl_ecdh_curve X25519MLKEM768`) and a classical-only server (`X25519`). PQ = the PQ-only server connected; every row below also connected to the classical server (fallback works). Images: `eclipse-temurin:17-jre` (17.0.21), `:21-jre` (21.0.13), `:25-jre` (25.0.5), `amazoncorretto:25` (25.0.5), pinned by digest in `out/*.txt`.

### By JDK and compute type (JSSE clients and servers)

| JDK | Lambda zip | Lambda image | Fargate / ECS / EKS | EC2 | Evidence |
| --- | --- | --- | --- | --- | --- |
| 25.0.5+ (Corretto, Temurin) | PQ: runtime `java25` | PQ: `lambda/java:25` | PQ: `amazoncorretto:25`, `eclipse-temurin:25` | PQ: Corretto 25 package | Tested (client and server); Documented ([25.0.5 notes](https://builds.shipilev.net/backports-monitor/release-notes-25.0.5.txt)) |
| 21 (21.0.13) | Not PQ; agent → PQ | Not PQ; agent → PQ | Not PQ; agent or static `java.security` → PQ | Same as containers | Tested |
| 17 (17.0.21) | Not PQ; agent → PQ | Not PQ; agent → PQ | Not PQ; agent or static → PQ | Same | Tested |
| 11 | Not PQ; agent → PQ | Not PQ; agent → PQ | Agent → PQ | Same | Tested on Lambda `java11` (kit); containers Unverified |
| 8 | Agent + `jdk.tls.client.protocols=TLSv1.3,TLSv1.2` → PQ | Same | Same | Same | Tested on Lambda `java8.al2023` (kit) |

### By library (client side)

| Client | JDK 17 / 21 | JDK 17 / 21 + agent | JDK 25.0.5 | Evidence |
| --- | --- | --- | --- | --- |
| JDK `HttpClient`, `HttpsURLConnection` | No | PQ | PQ | Tested |
| Apache HttpClient 5.6.5 and 4.5.14 | No | PQ | PQ | Tested |
| OkHttp 4.12.0 | No | PQ | PQ | Tested |
| Netty 4.2.20, JDK provider | No | PQ | PQ | Tested |
| Netty 4.2.20 + tcnative-boringssl-static 2.0.85 | **PQ** | PQ | PQ | Tested |
| AWS SDK 2.59.1 `ApacheHttpClient` | No | PQ | PQ | Tested (nginx logged the group) |
| AWS SDK 2.59.1 `NettyNioAsyncHttpClient` (tcnative on the class path) | **PQ** | PQ | PQ | Tested; it picked OpenSSL/BoringSSL. Without tcnative it uses JSSE (same as Apache row; not run) |
| AWS SDK 2.59.1 `AwsCrtHttpClient` (aws-crt 0.50.0) | **PQ** | PQ | PQ | Tested; Documented from 2.35.11 |
| AWS SDK 2.35.10 `AwsCrtHttpClient` (aws-crt 0.38.9) | No | n/a | n/a | Tested (fails PQ-only, works classical) |
| PostgreSQL JDBC 42.7.14 → PostgreSQL 18 `ssl_groups=X25519MLKEM768` | No (21) | PQ (21) | PQ | Tested |
| Static BCJSSE via `java.security`, no agent | n/a | PQ (17, 21), with or without `jdk.tls.namedGroups` | n/a | Tested |

### By server (server side)

| Server | JDK 21 default | JDK 21 + BCJSSE | JDK 25.0.5 default | Evidence |
| --- | --- | --- | --- | --- |
| Tomcat 11.0.29 embedded (JSSE) | No (classical only) | PQ with an RSA certificate; **all handshakes fail with an EC P-256 certificate** | PQ (preferred: default client gets X25519MLKEM768) | Tested |
| Tomcat 11.0.29, `SSLHostConfig groups="X25519MLKEM768,x25519"` | No (group unknown to SunJSSE 21, ignored) | n/a | PQ | Tested |
| Tomcat 11.0.29, `groups="x25519,secp256r1"` | n/a | n/a | Not PQ (pin removes it) | Tested |
| Jetty 12.1.15 | No | Fails with EC certificate (same as Tomcat) | PQ | Tested |
| JDK `HttpsServer` | n/a | Fails with EC certificate | PQ | Tested |
| Netty 4.2.20 + tcnative-boringssl-static 2.0.85 | **PQ** (default and with `GROUPS`) | n/a | PQ | Tested |
| Netty 4.2.20, JDK provider | No | n/a | PQ | Tested on 25 |
| Undertow, Spring Boot (Tomcat/Jetty/Undertow), Quarkus, Micronaut | Follow the JSSE row | | | Not run; same JSSE engine |

## Server side

For a Java service behind an ALB, NLB TLS listener, API Gateway or CloudFront, the client-facing handshake happens on the AWS front door, not in the JVM: set the PQ security policy there (see the Load balancers and Edge and API front doors tabs). The JVM's server TLS matters for end-to-end TLS (ALB to target re-encryption, NLB TCP pass-through, service mesh off, internal services).

Order of preference for a JVM that terminates TLS:

1. **JDK 25.0.5+.** Tomcat, Jetty, Undertow, the JDK `HttpsServer` and Netty (JDK provider) all negotiate X25519MLKEM768 with no setting (Tested for Tomcat, Jetty, `HttpsServer`, Netty). Clients that don't offer it still connect.
2. **Netty with `netty-tcnative-boringssl-static`** on any JDK (gRPC-Java, Reactor Netty, Vert.x/Quarkus with native SSL): PQ by default (Tested on JDK 21).
3. **JDK 17/21 + BCJSSE** (agent or static): works as a server only with an RSA certificate in our tests. With an EC P-256 certificate BC 1.87 logged `did not select any credentials` and refused every client, PQ or classical (Tested on 17 and 21, Tomcat, Jetty and `HttpsServer`, with SunX509 and PKIX key managers and three PKCS#12 encodings). I'm not sure of the root cause. Treat BCJSSE on the server side as "test with your own certificate first", and roll out with a canary.

### Spring Boot (embedded Tomcat, Jetty or Undertow)

Boot has no named-group property in 4.1.2; it exposes protocols and ciphers on SSL bundles. On JDK 25.0.5+ do nothing. Keep TLS 1.3 enabled:

```yaml
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

To restrict or reorder groups, set `-Djdk.tls.namedGroups=X25519MLKEM768,x25519,secp256r1,secp384r1` in `JAVA_TOOL_OPTIONS` (embedded Tomcat's `groups` defaults to this property; Jetty and Undertow use the JDK default). A `TomcatConnectorCustomizer` that calls `setGroups` is in the full files (Unverified).

### Standalone Tomcat (`server.xml`)

Tomcat 11.0.12 added a `groups` attribute on `SSLHostConfig` (also backported to 10.1 and 9.0); default = `jdk.tls.namedGroups` ([Tomcat 11 HTTP connector docs](https://tomcat.apache.org/tomcat-11.0-doc/config/http.html)). It only selects among groups the TLS engine knows:

```xml
<SSLHostConfig protocols="TLSv1.3+TLSv1.2"
               groups="X25519MLKEM768,x25519,secp256r1,secp384r1">
```

- JSSE implementation on JDK 25.0.5+: works (Tested via the embedded API). On JDK 21 the name is ignored and the server stays classical (Tested).
- OpenSSL implementation (Tomcat Native or the FFM OpenSSL connector): the attribute is not marked JSSE-only in the docs, so it should reach OpenSSL's group list; with OpenSSL 3.5 underneath that would give PQ. Not tested.
- A list without `X25519MLKEM768` turns PQ off on JDK 25 (Tested).

### Jetty, Undertow, the JDK `HttpsServer`

No group setting in their TLS configuration objects; they follow the JDK and `jdk.tls.namedGroups`. Jetty 12.1.15 on JDK 25.0.5: PQ (Tested).

### Netty server (and gRPC-Java, Reactor Netty, Vert.x)

```java
SslContext ctx = SslContextBuilder.forServer(kmf)
        .sslProvider(SslProvider.OPENSSL)   // tcnative-boringssl-static on the class path
        .protocols("TLSv1.3", "TLSv1.2")
        .build();                           // optional: .option(OpenSslContextOption.GROUPS, new String[]{"X25519MLKEM768","X25519","P-256"})
```

Netty logs `Using configured namedGroups -D 'jdk.tls.namedGroup': [...]` when `jdk.tls.namedGroups` is set, and then uses that list for BoringSSL too: a classical pin turns PQ off even with tcnative (Tested).

### Quarkus and Micronaut

Both run on Netty/Vert.x (Quarkus) or Netty (Micronaut). With the JDK SSL engine they follow the JDK row; with native SSL (tcnative/BoringSSL) they follow the Netty tcnative row. Neither was run here; check the engine in use with the startup log before claiming PQ.

## Client side (app level)

Almost every Java client library delegates TLS to JSSE, so it follows the JDK row of the status matrix with no library setting. Only TLS 1.2 pins and explicit named-group lists stop it.

| Library | TLS engine | What to set for PQ | Evidence |
| --- | --- | --- | --- |
| JDK `java.net.http.HttpClient` | JSSE | Nothing on 25.0.5+; agent on 8 to 21 | Tested 17, 21, 21+agent, 25 |
| `HttpsURLConnection` | JSSE | Same | Tested 17, 21, 21+agent, 25 |
| Apache HttpClient 5.6.5 (`HttpClients.createSystem()`) | JSSE | Same; don't pass `TLS.V_1_2` only to `ClientTlsStrategyBuilder` | Tested |
| Apache HttpClient 4.5.14 | JSSE | Same; don't build `SSLConnectionSocketFactory` with `new String[]{"TLSv1.2"}` | Tested |
| OkHttp 4.12.0 | JSSE (platform) | Same; `ConnectionSpec.MODERN_TLS` keeps 1.3 | Tested |
| Netty 4.2.20, `SslProvider.JDK` | JSSE | Same | Tested |
| Netty 4.2.20 + `netty-tcnative-boringssl-static` 2.0.85, `SslProvider.OPENSSL` | BoringSSL | Nothing: PQ by default on any JDK | Tested 17, 21, 25 |
| Spring `WebClient` (Reactor Netty) / `RestClient` / `RestTemplate` | Reactor Netty (JDK provider unless tcnative is configured) / JSSE | Same as the engine underneath | Not run; follows engine |
| AWS SDK v2 `ApacheHttpClient`, `UrlConnectionHttpClient` | JSSE | Same as the JDK | Tested (Apache) |
| AWS SDK v2 `NettyNioAsyncHttpClient` | Netty: JDK or OpenSSL provider | Same as the JDK when `SslProvider.JDK`; set `sslProvider(SslProvider.OPENSSL)` + tcnative for PQ on old JDKs | Tested, see note |
| AWS SDK v2 `AwsCrtHttpClient` / `AwsCrtAsyncHttpClient` | s2n-tls (Linux) | SDK 2.35.11+; nothing else | Tested, see note; Documented |
| PostgreSQL JDBC 42.7.14 | JSSE | Same; `sslmode=verify-full` | Tested against PostgreSQL 18 `ssl_groups` |
| MySQL Connector/J | JSSE | Same; keep `tlsVersions` including `TLSv1.3` | Not run; follows JSSE |
| Lettuce (Redis) | Netty, JDK provider by default | Same as JDK, or `SslOptions.builder().openSslProvider()` + tcnative | Not run |
| Jedis (Redis) | JSSE `SSLSocketFactory` | Same as JDK | Not run |
| Kafka Java client | JSSE `SSLEngine` | Same; keep `ssl.enabled.protocols=TLSv1.3,TLSv1.2`; `ssl.provider` empty | Not run |

The rows marked "Not run" use JSSE through documented APIs, so they follow the JDK row; treat them as Unverified until you run the live test below against your own build.

### What to change, by library

JDK HttpClient and HttpsURLConnection: no code. Remove protocol pins:

```java
// Blocks PQ: TLS 1.2 only
SSLContext ctx = SSLContext.getInstance("TLSv1.2");
// PQ-capable: let the provider pick TLS 1.3
SSLContext ctx = SSLContext.getInstance("TLS");
```

Apache HttpClient 5:

```java
var tls = ClientTlsStrategyBuilder.create()
        .setSslContext(SSLContexts.createSystemDefault())
        .setTlsVersions(TLS.V_1_3, TLS.V_1_2)   // keep 1.3
        .build();
```

Netty with BoringSSL (PQ on any JDK; optional explicit list):

```java
SslContext ctx = SslContextBuilder.forClient()
        .sslProvider(SslProvider.OPENSSL)
        .option(OpenSslContextOption.GROUPS, new String[]{"X25519MLKEM768", "X25519", "P-256"})
        .build();
```

AWS SDK for Java v2, CRT client (PQ for AWS API calls on any JDK; Linux only, macOS and Windows use the OS TLS library):

```java
KmsClient kms = KmsClient.builder()
        .httpClient(AwsCrtHttpClient.create())
        .build();
```

On SDK versions before 2.35.11 the builder needed `.postQuantumTlsEnabled(true)` (AWS blog); upgrade rather than rely on the flag.

Notes on the AWS SDK tests: the PQ-only nginx server logged `group=X25519MLKEM768` for each client that succeeded. Results are in the status matrix.

### JVM flags that matter (any library on JSSE)

| Flag | Effect |
| --- | --- |
| `-Djdk.tls.namedGroups=X25519MLKEM768,x25519,secp256r1,secp384r1` | Group order. A list without `X25519MLKEM768` turns PQ off, also on JDK 25 (Tested) and also for Netty tcnative (Netty reads this property) |
| `-Djdk.tls.client.protocols=TLSv1.3,TLSv1.2` | Needed on Java 8 only (8 defaults clients to 1.2) |
| `-javaagent:<dir>/pq-tls-agent.jar` | JDK 8 to 21: BCJSSE first + group list |
| `-Djava.security.properties=<file>` | Static BC registration (containers and EC2, not Lambda) |

## Packaging per compute type

Pick one of three routes per workload: JDK 25.0.5+ (preferred, nothing to package), the pq-tls agent (JDK 8 to 21, any compute), or static registration (JDK 11 to 21, containers and EC2 only). The full files are in the last section.

| Compute | JDK 25.0.5+ | JDK 8 to 21: agent | JDK 11 to 21: static `java.security` |
| --- | --- | --- | --- |
| Lambda zip | Runtime `java25` | `pq-tls/` at the zip root; env `JAVA_TOOL_OPTIONS=-javaagent:/var/task/pq-tls/pq-tls-agent.jar` (Tested) | Doesn't work: the Lambda bootstrap's system class path is only `/var/runtime/lib`, so providers from other paths are ignored (Tested, kit) |
| Lambda layer | Not needed | Kit layer at `/opt/pq-tls` + `AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper` (Tested, kit) | Doesn't work (same reason) |
| Lambda container image | `public.ecr.aws/lambda/java:25` | `COPY pq-tls/ ${LAMBDA_TASK_ROOT}/pq-tls/` + `ENV JAVA_TOOL_OPTIONS` | Not tested |
| Fargate, ECS, EKS | `amazoncorretto:25`, `eclipse-temurin:25` | `COPY pq-tls/ /opt/pq-tls/` + `ENV JAVA_TOOL_OPTIONS` in the image, or the variable in the task definition / pod spec | `-Djava.security.properties=` + BC jars on `-cp` (Tested on Temurin 17 and 21) |
| EC2 | Install Corretto 25 (`dnf install java-25-amazon-corretto-headless` on AL2023) | systemd `Environment=JAVA_TOOL_OPTIONS=...`, or an SSM document that installs the kit and a drop-in | Same file, via the unit's `ExecStart` flags |

Rules that apply everywhere:

- Append to an existing `JAVA_TOOL_OPTIONS`; don't replace it (APM agents such as the Datadog, New Relic and OpenTelemetry Java agents also live there).
- On Java 8 add `-Djdk.tls.client.protocols=TLSv1.3,TLSv1.2`.
- Distroless images have no shell, but the JVM reads `JAVA_TOOL_OPTIONS` itself, so `ENV` works.
- Lambda SnapStart: the agent runs at JVM start, before the snapshot, so provider order is captured in the snapshot. Not tested with SnapStart.

## Verify

1. **Posture (no traffic).** `java -version` shows 25.0.5 or later, or `JAVA_TOOL_OPTIONS` contains `pq-tls-agent.jar`. On a running process: `jcmd <pid> VM.system_properties | grep -E 'jdk.tls.namedGroups|java.version'`. For an image, scan the base tag and `ENV` in CI.
2. **Startup log.** With the agent: `pq-tls agent: BCJSSE first, groups=X25519MLKEM768,...` on stderr, plus the JVM's own `Picked up JAVA_TOOL_OPTIONS: ...` line.
3. **Live client test.** From the workload's network, call a PQ-only server (`openssl s_server -tls1_3 -groups X25519MLKEM768`, or nginx with `ssl_ecdh_curve X25519MLKEM768`) and a classical-only server (`-groups X25519`). Both must succeed; the PQ-only one proves PQ, the classical one proves fallback.
4. **Live server test.** `openssl s_client -connect host:8443 -tls1_3 -groups X25519MLKEM768 -brief` (OpenSSL 3.5+) must print `Negotiated TLS1.3 group: X25519MLKEM768`; `-groups X25519` must still connect.
5. **Handshake trace.** `-Djavax.net.debug=ssl:handshake` (SunJSSE) shows the `key_share` in ServerHello with `X25519MLKEM768`. BCJSSE logs through `java.util.logging` (`org.bouncycastle.jsse` at `FINE`).
6. **Observed on AWS.** CloudTrail `tlsDetails.keyExchange` = `X25519MLKEM768` on KMS, STS, IAM, Secrets Manager, ACM and Payment Cryptography calls from the workload's role.

## Pitfalls and rollback

- **A pinned group list wins.** `jdk.tls.namedGroups` without `X25519MLKEM768` keeps any JDK classical, including 25 (Tested), and the agent leaves an existing value alone (Tested). Grep launch scripts, Helm values and `JAVA_TOOL_OPTIONS` for it.
- **TLS 1.2 pins.** `SSLContext.getInstance("TLSv1.2")`, `jdk.tls.client.protocols=TLSv1.2`, `server.ssl.enabled-protocols=TLSv1.2`, Kafka `ssl.enabled.protocols=TLSv1.2` all block PQ.
- **BCJSSE becomes the provider for the whole process.** Test mutual TLS, custom `KeyManager`/`TrustManager`, PKCS#11 keys, session resumption and FIPS mode before rollout. If the app ships its own Bouncy Castle, the agent's 1.87 jars load first on the system class path; align versions.
- **FIPS.** The agent uses the non-FIPS `bcprov`/`bctls` jars. A FIPS build needs `bc-fips` + `bctls-fips`; whether the current FIPS line offers X25519MLKEM768 in BCJSSE is not confirmed (see [BC FIPS 2.1 release notes](https://support.keyfactor.com/hc/en-us/articles/53287242078619-Bouncy-Castle-Java-FIPS-2-1-X-release-notes)). Don't put the non-FIPS agent into a FIPS-mode JVM.
- **Agent ordering.** If another agent also reorders providers or replaces `SSLContext.getDefault()`, the last one wins. Check the startup log.
- **Netty tcnative and the JDK flag.** Netty applies `jdk.tls.namedGroups` to the native engine too; a classical pin there removes PQ from BoringSSL as well (see the status matrix for the test).
- **Larger ClientHello.** X25519MLKEM768 adds about 1.2 KB. Old middleboxes that drop large ClientHellos break the first flight; a classical retry is not automatic in Java.
- **Rollback.** Remove `-javaagent:` (or the `java.security.properties` flag) from `JAVA_TOOL_OPTIONS`, or on JDK 25 set `-Djdk.tls.namedGroups=x25519,secp256r1,secp384r1`, then restart. On Lambda, delete the env var (or set `PQ_TLS_DISABLE=1` with the kit layer); the next cold start is classical.

## Full configuration files

Every file the sections above excerpt, complete. Paths are suggestions; keep the `pq-tls/` directory name so the agent's manifest finds its jars. The agent and the java.security override are for JDK 8 to 21 only; remove them when the JDK reaches 25.0.5 or later.

### Agent build (pq-tls kit)

`pq-tls-agent/src/PqTlsAgent.java`

```java
import java.security.Provider;
import java.security.Security;

// Loaded with -javaagent:<dir>/pq-tls-agent.jar (usually via JAVA_TOOL_OPTIONS).
// Agent jars and their manifest Class-Path are on the SYSTEM class path, so the Bouncy Castle
// providers are visible to the JDK's provider lookup without touching application code.
// BCJSSE goes first so SSLContext.getInstance("TLS") / SSLContext.getDefault() use it; the BC JCA
// provider is added LAST so every other crypto lookup keeps resolving to the JDK providers.
public class PqTlsAgent {
    public static void premain(String args) {
        Provider bc = new org.bouncycastle.jce.provider.BouncyCastleProvider();
        Security.addProvider(bc);
        Security.insertProviderAt(new org.bouncycastle.jsse.provider.BouncyCastleJsseProvider(bc), 1);
        if (System.getProperty("jdk.tls.namedGroups") == null) {
            System.setProperty("jdk.tls.namedGroups", "X25519MLKEM768,x25519,secp256r1,secp384r1");
        }
        System.err.println("pq-tls agent: BCJSSE first, groups=" + System.getProperty("jdk.tls.namedGroups"));
    }
}
```

`pq-tls-agent/MANIFEST.MF` (the jar's manifest; jars are found next to the agent jar)

```text
Premain-Class: PqTlsAgent
Class-Path: bcprov-jdk18on-1.87.jar bctls-jdk18on-1.87.jar bcutil-jdk18on-1.87.jar
```

`pq-tls-agent/build.sh` (Java 8 bytecode, so one jar serves JDK 8 to 21)

```bash
#!/bin/bash
set -euo pipefail
BC=1.87
mkdir -p out/pq-tls
for a in bcprov bctls bcutil; do
  curl -fsSLo out/pq-tls/$a-jdk18on-$BC.jar \
    https://repo1.maven.org/maven2/org/bouncycastle/$a-jdk18on/$BC/$a-jdk18on-$BC.jar
done
# Verify checksums against Maven Central before use (sha256 published as .sha256 is not available for all; compare .sha1 at minimum).
for a in bcprov bctls bcutil; do
  want=$(curl -fsSL https://repo1.maven.org/maven2/org/bouncycastle/$a-jdk18on/$BC/$a-jdk18on-$BC.jar.sha1)
  got=$(sha1sum out/pq-tls/$a-jdk18on-$BC.jar | cut -d' ' -f1)
  [ "$want" = "$got" ] || { echo "checksum mismatch: $a"; exit 1; }
done
javac --release 8 -cp "out/pq-tls/*" -d out/classes src/PqTlsAgent.java
jar cfm out/pq-tls/pq-tls-agent.jar MANIFEST.MF -C out/classes PqTlsAgent.class
ls -l out/pq-tls
```

### Dependencies (pom.xml / build.gradle.kts)

`pom.xml` (excerpt: only the dependencies that matter for PQ; pick the ones your service uses)

```xml
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
    <version>0.50.0</version>   <!-- the version the SDK release pins (awscrt.version) -->
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
       (not needed for the agent path: the agent jar brings its own copies) -->
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

```kotlin
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

`pq-tls/bc-static.security` (JDK 11, 17, 21; load with `-Djava.security.properties=<path>`)

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
```

Before using it, compare the list with `$JAVA_HOME/conf/security/java.security` in your exact image: a vendor that adds or reorders providers needs the same change here. Pair it with `-Djdk.tls.namedGroups=X25519MLKEM768,x25519,secp256r1,secp384r1`. JDK 8 uses class names (`sun.security.provider.Sun`, ..., `com.sun.net.ssl.internal.ssl.Provider`) in `$JAVA_HOME/jre/lib/security/java.security`; the JDK 8 variant was not tested.

### Spring Boot

`src/main/resources/application.yml`

```yaml
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

Spring Boot has no named-group property (checked against the 4.1.2 SSL reference). Set groups with the JVM flag in the launch environment, or with a connector customizer:

`src/main/java/com/example/PqTomcatGroups.java` (Unverified: Tomcat's `SSLHostConfig.setGroups` was tested, the Spring wiring was not)

```java
package com.example;

import org.springframework.boot.tomcat.TomcatConnectorCustomizer; // Boot 4.x; Boot 3.x: org.springframework.boot.web.embedded.tomcat
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

`conf/server.xml` (connector excerpt; Tomcat 11.0.12+, 10.1 and 9.0 lines with the backport)

```xml
<Connector port="8443" protocol="org.apache.coyote.http11.Http11NioProtocol"
           SSLEnabled="true" maxThreads="200">
  <UpgradeProtocol className="org.apache.coyote.http2.Http2Protocol" />
  <SSLHostConfig protocols="TLSv1.3+TLSv1.2"
                 groups="X25519MLKEM768,x25519,secp256r1,secp384r1">
    <Certificate certificateKeystoreFile="conf/tls/server.p12"
                 certificateKeystorePassword="${keystore.password}"
                 certificateKeystoreType="PKCS12" />
  </SSLHostConfig>
</Connector>
```

`bin/setenv.sh` (JDK 25.0.5+: nothing needed; JDK 17/21: the agent)

```bash
#!/bin/sh
# JDK 17/21 only. Remove after moving Tomcat to JDK 25.0.5+.
CATALINA_OPTS="$CATALINA_OPTS -javaagent:/opt/pq-tls/pq-tls-agent.jar"
export CATALINA_OPTS
```

### Netty and AWS SDK code

`NettyPq.java` (client and server; groups are optional, the tested default already prefers X25519MLKEM768)

```java
import io.netty.handler.ssl.*;

final class NettyPq {
    static final String[] GROUPS = {"X25519MLKEM768", "X25519", "P-256", "P-384"};

    static SslContext client() throws Exception {
        return SslContextBuilder.forClient()
                .sslProvider(SslProvider.OPENSSL)          // netty-tcnative-boringssl-static on the class path
                .protocols("TLSv1.3", "TLSv1.2")
                .option(OpenSslContextOption.GROUPS, GROUPS) // explicit list; omit to keep the library default
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

`AwsClients.java` (AWS SDK for Java v2: CRT client; PQ by default from 2.35.11)

```java
import software.amazon.awssdk.http.crt.AwsCrtHttpClient;
import software.amazon.awssdk.http.crt.AwsCrtAsyncHttpClient;
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

Zip layout (agent path, java8.al2023 / java11 / java17 / java21):

```text
function.zip
├── com/example/Handler.class
├── lib/...                      (your dependencies)
└── pq-tls/
    ├── pq-tls-agent.jar
    ├── bcprov-jdk18on-1.87.jar
    ├── bctls-jdk18on-1.87.jar
    └── bcutil-jdk18on-1.87.jar
```

`template.yaml` (SAM)

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
            - -javaagent:/var/task/pq-tls/pq-tls-agent.jar -Djdk.tls.client.protocols=TLSv1.3,TLSv1.2
            - -javaagent:/var/task/pq-tls/pq-tls-agent.jar
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
          JAVA_TOOL_OPTIONS: -javaagent:/var/task/pq-tls/pq-tls-agent.jar
```

`lambda.tf` (Terraform)

```hcl
resource "aws_lambda_function" "fn" {
  function_name = "orders-java"
  runtime       = "java21" # java25: remove the environment block
  handler       = "com.example.Handler::handleRequest"
  role          = var.role_arn
  filename      = "build/function.zip"
  source_code_hash = filebase64sha256("build/function.zip")
  memory_size   = 1024
  timeout       = 30
  architectures = ["arm64"]
  environment {
    variables = {
      JAVA_TOOL_OPTIONS = "-javaagent:/var/task/pq-tls/pq-tls-agent.jar"
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
ENV JAVA_TOOL_OPTIONS="-javaagent:/var/task/pq-tls/pq-tls-agent.jar"
CMD ["com.example.Handler::handleRequest"]
```

### Containers (Fargate, ECS, EKS)

`Dockerfile` (preferred: JDK 25.0.5+, no PQ-specific lines)

```dockerfile
FROM amazoncorretto:25-al2023-headless
# or: FROM eclipse-temurin:25-jre  /  gcr.io/distroless/java25-debian13 (check the tag exists for your registry mirror)
COPY build/libs/app.jar /app/app.jar
USER 1000
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

`Dockerfile.jdk21-agent` (JDK 17/21 until the upgrade)

```dockerfile
FROM amazoncorretto:21-al2023-headless
COPY pq-tls/ /opt/pq-tls/
COPY build/libs/app.jar /app/app.jar
ENV JAVA_TOOL_OPTIONS="-javaagent:/opt/pq-tls/pq-tls-agent.jar"
USER 1000
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

`Dockerfile.distroless-agent` (distroless has no shell; ENV still works because the JVM reads JAVA_TOOL_OPTIONS itself)

```dockerfile
FROM gcr.io/distroless/java21-debian12:nonroot
COPY pq-tls/ /opt/pq-tls/
COPY build/libs/app.jar /app/app.jar
ENV JAVA_TOOL_OPTIONS="-javaagent:/opt/pq-tls/pq-tls-agent.jar"
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

`Dockerfile.static` (static provider registration instead of the agent)

```dockerfile
FROM eclipse-temurin:21-jre
COPY pq-tls/bcprov-jdk18on-1.87.jar pq-tls/bctls-jdk18on-1.87.jar pq-tls/bcutil-jdk18on-1.87.jar /opt/pq-tls/
COPY pq-tls/bc-static.security /opt/pq-tls/bc-static.security
COPY build/libs/app.jar /app/app.jar
ENV JAVA_TOOL_OPTIONS="-Djava.security.properties=/opt/pq-tls/bc-static.security -Djdk.tls.namedGroups=X25519MLKEM768,x25519,secp256r1,secp384r1"
# -jar ignores -cp, so put the BC jars in the jar manifest Class-Path, or run with -cp and the main class:
ENTRYPOINT ["java", "-cp", "/app/app.jar:/opt/pq-tls/*", "com.example.Main"]
```

`taskdef.json` (ECS / Fargate; only needed on JDK 17/21 if the image does not already set it)

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
        {"name": "JAVA_TOOL_OPTIONS", "value": "-javaagent:/opt/pq-tls/pq-tls-agent.jar"}
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
    environment  = [{ name = "JAVA_TOOL_OPTIONS", value = "-javaagent:/opt/pq-tls/pq-tls-agent.jar" }]
  }])
}
```

`ecs.yaml` (CloudFormation)

```yaml
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
            - {Name: JAVA_TOOL_OPTIONS, Value: -javaagent:/opt/pq-tls/pq-tls-agent.jar}
Parameters:
  ExecutionRoleArn: {Type: String}
  Image: {Type: String}
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
              value: "-javaagent:/opt/pq-tls/pq-tls-agent.jar"
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
Environment="JAVA_TOOL_OPTIONS=-javaagent:/opt/pq-tls/pq-tls-agent.jar"
ExecStart=/usr/lib/jvm/java-21-amazon-corretto/bin/java -jar /opt/orders/app.jar
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

`/etc/systemd/system/orders-java.service.d/pq-tls.conf` (drop-in, when you cannot edit the unit)

```ini
[Service]
Environment="JAVA_TOOL_OPTIONS=-javaagent:/opt/pq-tls/pq-tls-agent.jar"
```

`pq-tls-ssm.yaml` (SSM Command document: install the kit from S3 and add the drop-in)

```yaml
schemaVersion: '2.2'
description: Install the pq-tls Java agent and enable it for one systemd service.
parameters:
  Service: {type: String}
  KitS3Uri: {type: String, description: 's3://bucket/pq-tls-1.87.tgz'}
mainSteps:
  - action: aws:runShellScript
    name: install
    inputs:
      runCommand:
        - set -euo pipefail
        - mkdir -p /opt/pq-tls
        - aws s3 cp '{{ KitS3Uri }}' /tmp/pq-tls.tgz
        - tar -xzf /tmp/pq-tls.tgz -C /opt/pq-tls
        - mkdir -p '/etc/systemd/system/{{ Service }}.service.d'
        - printf '[Service]\nEnvironment="JAVA_TOOL_OPTIONS=-javaagent:/opt/pq-tls/pq-tls-agent.jar"\n' > '/etc/systemd/system/{{ Service }}.service.d/pq-tls.conf'
        - systemctl daemon-reload
        - systemctl restart '{{ Service }}'
        - journalctl -u '{{ Service }}' -n 50 --no-pager | grep -m1 'pq-tls agent'
```
