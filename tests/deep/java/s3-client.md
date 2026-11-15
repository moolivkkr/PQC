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
