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
