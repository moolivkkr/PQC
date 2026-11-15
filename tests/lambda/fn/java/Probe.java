import javax.net.ssl.*;
import java.security.cert.X509Certificate;
import java.util.LinkedHashMap;
import java.util.Map;

// Plain POJO handler (Probe::handleRequest): unchanged application code, no PQ-specific settings.
public class Probe {
    public Map<String, String> handleRequest(Map<String, Object> event) throws Exception {
        Map<String, String> out = new LinkedHashMap<>();
        out.put("runtime", System.getProperty("java.version"));
        TrustManager[] all = { new X509TrustManager() {
            public void checkClientTrusted(X509Certificate[] c, String t) {}
            public void checkServerTrusted(X509Certificate[] c, String t) {}
            public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; } } };
        SSLContext ctx = SSLContext.getInstance("TLS");
        ctx.init(null, all, null);
        out.put("jsse_provider", ctx.getProvider().getName());
        int[] ports = {8443, 8444};
        String[] names = {"pq_only", "classical_only"};
        for (int i = 0; i < 2; i++) {
            try (SSLSocket s = (SSLSocket) ctx.getSocketFactory().createSocket("pqsrv", ports[i])) {
                s.setSoTimeout(5000);
                s.startHandshake();
                out.put(names[i], "OK " + s.getSession().getProtocol());
            } catch (Exception e) {
                out.put(names[i], "FAIL " + e.getClass().getSimpleName());
            }
        }
        return out;
    }
}
