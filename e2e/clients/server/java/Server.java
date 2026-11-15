// Load balancer target probe - Java (com.sun.net.httpserver.HttpsServer with the JVM's default JSSE provider and
// default KeyManagerFactory algorithm, as Tomcat/Jetty/Spring Boot use them). Compiled with --release 8.
import com.sun.net.httpserver.HttpsConfigurator;
import com.sun.net.httpserver.HttpsServer;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.InetSocketAddress;
import java.net.URL;
import java.security.KeyStore;
import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;

public class Server {
    static String env(String k, String d) { String v = System.getenv(k); return v == null || v.isEmpty() ? d : v; }

    static String q(String s) { return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\""; }

    public static void main(String[] a) throws Exception {
        String caseId = env("PQC_CASE_ID", "adhoc"), obs = env("PQC_OBSERVER", "pq-observer");
        int port = Integer.parseInt(env("PQC_SERVER_PORT", "9443"));
        File dir = new File(Server.class.getProtectionDomain().getCodeSource().getLocation().toURI());
        KeyStore ks = KeyStore.getInstance("PKCS12");
        try (InputStream in = new FileInputStream(new File(dir, "server.p12"))) { ks.load(in, "changeit".toCharArray()); }
        KeyManagerFactory kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        kmf.init(ks, "changeit".toCharArray());
        SSLContext ctx = SSLContext.getInstance("TLS");
        ctx.init(kmf.getKeyManagers(), null, null);
        HttpsServer srv = HttpsServer.create(new InetSocketAddress(port), 0);
        srv.setHttpsConfigurator(new HttpsConfigurator(ctx));
        srv.createContext("/", ex -> {
            byte[] b = "{\"ok\":true,\"server\":\"java\"}".getBytes("UTF-8");
            ex.getResponseHeaders().add("Content-Type", "application/json");
            ex.sendResponseHeaders(200, b.length);
            try (OutputStream o = ex.getResponseBody()) { o.write(b); }
        });
        srv.start();
        String rt = System.getProperty("java.version"), provider = ctx.getProvider().getName();
        String compute = env("PQC_COMPUTE", "unknown"), mode = env("PQC_MODE", "baseline");
        StringBuilder results = new StringBuilder();
        for (String t : env("PQC_TARGETS", "alb-pq,alb-classic").split(",")) {
            if (t.isEmpty()) continue;
            String raw;
            try {
                HttpURLConnection c = (HttpURLConnection) new URL("http://" + obs + ":8080/dialback?id=" + caseId
                        + "&port=" + port + "&policy=" + t).openConnection();
                c.setConnectTimeout(10000); c.setReadTimeout(30000);
                ByteArrayOutputStream bo = new ByteArrayOutputStream();
                try (InputStream in = c.getInputStream()) { byte[] buf = new byte[4096]; int n; while ((n = in.read(buf)) > 0) bo.write(buf, 0, n); }
                raw = bo.toString("UTF-8").trim();
            } catch (Exception e) {
                raw = "{\"ok\":false,\"error\":" + q(e.toString()) + "}";
            }
            String st = !raw.contains("\"ok\":true") ? "failed" : raw.contains("\"pq\":true") ? "pq" : "classical";
            raw = raw.substring(0, raw.lastIndexOf('}')) + ",\"pq_status\":" + q(st) + "}";
            if (results.length() > 0) results.append(',');
            results.append(q(t)).append(':').append(raw);
            System.out.println("{\"event\":\"tls_handshake\",\"role\":\"server\",\"case_id\":" + q(caseId) + ",\"lang\":\"java\",\"runtime\":"
                    + q(rt) + ",\"compute\":" + q(compute) + ",\"mode\":" + q(mode) + ",\"target\":" + q(t) + "," + raw.substring(1));
        }
        System.out.println("PQC_RESULT {\"case_id\":" + q(caseId) + ",\"lang\":\"java\",\"role\":\"server\",\"runtime\":" + q(rt)
                + ",\"tls_lib\":" + q(provider) + ",\"compute\":" + q(compute) + ",\"mode\":" + q(mode) + ",\"results\":{" + results + "}}");
        srv.stop(0);
        System.exit(0);
    }
}
