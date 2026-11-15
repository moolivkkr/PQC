import javax.net.ssl.*;
import java.security.cert.X509Certificate;

public class Client {
    public static void main(String[] a) throws Exception {
        String label = a.length > 0 ? a[0] : "java";
        TrustManager[] all = { new X509TrustManager() {
            public void checkClientTrusted(X509Certificate[] c, String t) {}
            public void checkServerTrusted(X509Certificate[] c, String t) {}
            public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; } } };
        SSLContext ctx = SSLContext.getInstance("TLS");
        ctx.init(null, all, null);
        int[] ports = {8443, 8444};
        String[] names = {"PQ-only", "classical-only"};
        for (int i = 0; i < 2; i++) {
            try (SSLSocket s = (SSLSocket) ctx.getSocketFactory().createSocket("pqsrv", ports[i])) {
                s.setSoTimeout(5000);
                s.startHandshake();
                System.out.println(label + ": " + names[i] + ": OK " + s.getSession().getProtocol());
            } catch (Exception e) {
                System.out.println(label + ": " + names[i] + ": FAIL " + e.getClass().getSimpleName() + ": " + e.getMessage());
            }
        }
    }
}
