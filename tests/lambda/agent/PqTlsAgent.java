import java.security.Provider;
import java.security.Security;

// Java agent loaded via JAVA_TOOL_OPTIONS=-javaagent:/opt/pq-tls/pq-tls-agent.jar.
// Agent jars (and their manifest Class-Path) are on the SYSTEM class path, so the Bouncy Castle
// providers become visible to the JDK's provider lookup without touching function code.
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
