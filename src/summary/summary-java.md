# Java

**What decides PQ.** The JSSE provider inside the JVM, not OpenSSL, so the OS and image do not matter. JDK 25.0.5+ negotiates X25519MLKEM768 by default (JEP 527, backported to 25.0.5). JDK 8 to 21 have no ML-KEM; the fix is Bouncy Castle JSSE as the TLS provider, loaded by our kit v2 agent, or a move to JDK 25.

| Compute | PQ today? | What to change |
| --- | --- | --- |
| Lambda java8.al2, java11, java17, java21 | No | Kit v2 agent: `JAVA_TOOL_OPTIONS=-javaagent:/var/task/pq-tls/pq-tls-agent.jar` (or the `pq-tls` layer, which adds the Java 8 flags) |
| Lambda java25 | Yes | Nothing |
| Fargate, ECS on EC2, EKS | JDK 25.0.5+ images: yes; 8 to 21: no | Move to Corretto or Temurin 25.0.5+, or the agent, or a static `java.security` Bouncy Castle entry (17, 21) |
| EC2 | Same as containers | Same; `JAVA_TOOL_OPTIONS` in the service unit |

**What to change, in order**

1. Prefer JDK 25.0.5+ where the application can move. Oracle plans backports to 21 and 17, then 11 and 8; secondary reports say H1 and H2 2027 (Claimed, not shipped).
2. Otherwise, the kit v2 agent. Java 8 also needs `-Djdk.tls.client.protocols=TLSv1.3,TLSv1.2` on Lambda and `-Dorg.bouncycastle.jsse.client.assumeOriginalHostName=true` everywhere.
3. **Servers with an EC certificate** need `ssl.KeyManagerFactory.algorithm=PKIX` under Bouncy Castle, or every handshake fails. Kit v2 sets it; code that hard-codes `SunX509` (or Tomcat `keyManagerAlgorithm="SunX509"`) still fails, and the CI check flags it.
4. Without Bouncy Castle: Netty `tcnative-boringssl` 2.0.85, or the AWS SDK v2 CRT client (PQ by default from 2.35.11 per AWS; 2.59.1 Tested PQ, 2.35.10 classical).

**Certificates and keystores:** no change to JKS or PKCS#12 stores, `cacerts` or `javax.net.ssl.trustStore`; mutual TLS works with kit v2 (kit v1 silently sent no EC client certificate). **Risk:** Bouncy Castle becomes the TLS provider for the whole process: test FIPS, custom keystore and mutual TLS services first. **ML-DSA:** no JDK negotiates ML-DSA in TLS yet; Java gets ECDSA from a dual-certificate server.

**Rollback:** remove the `-javaagent` option. **Detect:** CloudTrail for AWS calls; server logs for inbound.

**Tested:** 96 client cases (Lambda 57, Fargate 21, ECS on EC2 5, EC2 13) and 7 load balancer target cases, all passing; Tomcat 11, Jetty 12 and the JDK HttpsServer with EC certificates on JDK 17 and 21 under kit v2, and EC keystores on JDK 25 with no change (container tests). Not yet run: real AWS, JDK 8 on EC2, FIPS.
