import javax.net.ssl.*;
import java.io.*;
import java.security.KeyStore;
import java.security.cert.X509Certificate;

// server <keystore|default> <type> <kmfAlg: default|SunX509|PKIX> <port>
// client <host> <port>
public class KsTest {
    static final char[] PW = "changeit".toCharArray();

    public static void main(String[] a) throws Exception {
        if (a[0].equals("server")) {
            SSLContext ctx;
            if (a[1].equals("default")) {
                ctx = SSLContext.getDefault();
                System.out.println("server: default SSLContext, kmf default alg=" + KeyManagerFactory.getDefaultAlgorithm());
            } else {
                KeyStore ks = KeyStore.getInstance(a[2]);
                try (var in = new FileInputStream(a[1])) { ks.load(in, PW); }
                KeyManagerFactory f = KeyManagerFactory.getInstance(
                        a[3].equals("default") ? KeyManagerFactory.getDefaultAlgorithm() : a[3]);
                f.init(ks, PW);
                System.out.println("server: kmf=" + f.getAlgorithm() + " from " + f.getProvider().getName()
                        + " aliases=" + java.util.Collections.list(ks.aliases()));
                ctx = SSLContext.getInstance("TLS");
                ctx.init(f.getKeyManagers(), null, null);
            }
            System.out.println("server: SSLContext provider=" + ctx.getProvider().getName());
            SSLServerSocket ss = (SSLServerSocket) ctx.getServerSocketFactory().createServerSocket(Integer.parseInt(a[4]));
            while (true) {
                try (SSLSocket s = (SSLSocket) ss.accept()) {
                    s.startHandshake();
                    s.getOutputStream().write("HTTP/1.0 200 OK\r\n\r\nok\n".getBytes());
                    s.getOutputStream().flush();
                } catch (Exception e) {
                    System.out.println("server: handshake failed: " + e);
                }
            }
        } else {
            SSLContext ctx = SSLContext.getDefault();
            try (SSLSocket s = (SSLSocket) ctx.getSocketFactory().createSocket(a[1], Integer.parseInt(a[2]))) {
                s.startHandshake();
                X509Certificate c = (X509Certificate) s.getSession().getPeerCertificates()[0];
                System.out.println("client OK provider=" + ctx.getProvider().getName() + " " + s.getSession().getProtocol()
                        + " peer=" + c.getSubjectX500Principal().getName());
            } catch (Exception e) {
                System.out.println("client FAIL provider=" + ctx.getProvider().getName() + ": " + e);
            }
        }
    }
}
