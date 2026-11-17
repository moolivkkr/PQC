import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.KeyManager;
import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSocketFactory;
import javax.net.ssl.TrustManagerFactory;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.KeyStore;
import java.security.Security;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * PQ TLS probe - Java. Same class on Lambda (POJO handler Probe::handleRequest), ECS and EC2 (main).
 * Compiled with --release 8, so one class file runs on JDK 8 to 25. No PQ-specific settings in code:
 * no named groups, no protocol list; whatever the JDK, provider order and kit (agent, layer, security
 * file) give is what is measured.
 *
 * Client stack: HttpsURLConnection. TLS setup (PQC_JAVA_TLS):
 *   custom  (default) the app's own SSLContext.getInstance("TLS"), trust = truststore.p12 via
 *           TrustManagerFactory.getDefaultAlgorithm(), keys = client keystore via KeyManagerFactory
 *           (PQC_JAVA_KMF: "default" = KeyManagerFactory.getDefaultAlgorithm(), or a name such as SunX509)
 *   sysprops  no TLS code: the JVM default context, configured with -Djavax.net.ssl.keyStore/trustStore
 * Client keystore file: PQC_JAVA_CLIENT_KS (absolute, or a name in the certs dir), default client.p12.
 *
 * Output: one {"event":"tls_handshake",...} line per target; main() also prints PQC_RESULT <json>.
 */
public class Probe {
    static final String[] NAMES = {"hybrid", "pqonly", "mtls", "eccert", "tls12", "mldsa-dual", "mldsa-only", "mldsa-mtls"};
    static final int[] PORTS = {8443, 8444, 8445, 8446, 8447, 8448, 8449, 8450};
    static final String[] PASS_THROUGH = {"server_cert", "server_sigalg", "client_cert", "client_sigalg"};
    static final char[] PW = "changeit".toCharArray();

    public String handleRequest(Map<String, Object> event) throws Exception {   // Lambda
        String id = null;
        List<String> targets = null;
        if (event != null) {
            if (event.get("case_id") != null) id = String.valueOf(event.get("case_id"));
            Object t = event.get("targets");
            if (t instanceof List) {
                targets = new ArrayList<String>();
                for (Object o : (List<?>) t) targets.add(String.valueOf(o));
            }
        }
        return run(id, targets);
    }

    public static void main(String[] args) throws Exception {
        String r = run(args.length > 0 ? args[0] : null, null);
        System.out.println("PQC_RESULT " + r);
        System.out.flush();
    }

    static String env(String k, String d) {
        String v = System.getenv(k);
        return v == null || v.isEmpty() ? d : v;
    }

    static File certsDir() {
        List<String> c = new ArrayList<String>();
        c.add(env("PQC_CERTS", ""));
        c.add(env("LAMBDA_TASK_ROOT", "/var/task") + "/certs");
        try {
            File here = new File(Probe.class.getProtectionDomain().getCodeSource().getLocation().toURI());
            c.add((here.isDirectory() ? here : here.getParentFile()).getPath() + "/certs");
        } catch (Exception ignored) {
        }
        c.add("/opt/pqc-certs");
        c.add("/etc/pqc/certs");
        for (String d : c) {
            if (!d.isEmpty() && new File(d, "truststore.p12").exists()) return new File(d);
        }
        throw new IllegalStateException("test truststore not found (set PQC_CERTS)");
    }

    static KeyStore load(File f) throws Exception {
        KeyStore ks = KeyStore.getInstance("PKCS12");
        InputStream in = new FileInputStream(f);
        try {
            ks.load(in, PW);
        } finally {
            in.close();
        }
        return ks;
    }

    static String[] tlsSetup(File certs, SSLSocketFactory[] out) throws Exception {
        String mode = env("PQC_JAVA_TLS", "custom");
        if (mode.equals("sysprops")) {
            SSLContext d = SSLContext.getDefault();
            out[0] = d.getSocketFactory();
            return new String[]{d.getProvider().getName() + " " + d.getProvider().getVersion(), "sysprops",
                    "(default context)"};
        }
        String ksName = env("PQC_JAVA_CLIENT_KS", "client.p12");
        File ksFile = ksName.startsWith("/") ? new File(ksName) : new File(certs, ksName);
        TrustManagerFactory tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        tmf.init(load(new File(certs, "truststore.p12")));
        String alg = env("PQC_JAVA_KMF", "default");
        if (alg.equals("default")) alg = KeyManagerFactory.getDefaultAlgorithm();
        KeyManagerFactory kmf = KeyManagerFactory.getInstance(alg);
        kmf.init(load(ksFile), PW);
        SSLContext ctx = SSLContext.getInstance("TLS");
        ctx.init(kmf.getKeyManagers(), tmf.getTrustManagers(), null);
        out[0] = ctx.getSocketFactory();
        return new String[]{ctx.getProvider().getName() + " " + ctx.getProvider().getVersion(), "custom",
                alg + " (" + kmf.getProvider().getName() + ") " + ksFile.getName()};
    }

    /** ML-DSA targets: trust = truststore-both.p12 (test CA + ML-DSA test CA); mldsa-mtls also loads client-mldsa.p12.
     *  Always the app's own SSLContext, whatever PQC_JAVA_TLS says: these targets measure ML-DSA support, not trust setup.
     *  Built per target so a JDK that cannot load the ML-DSA key only fails mldsa-mtls. */
    static SSLSocketFactory mldsaFactory(File certs, boolean withKey) throws Exception {
        TrustManagerFactory tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        tmf.init(load(new File(certs, "truststore-both.p12")));
        KeyManager[] km = null;
        if (withKey) {
            KeyManagerFactory kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
            kmf.init(load(new File(certs, "client-mldsa.p12")), PW);
            km = kmf.getKeyManagers();
        }
        SSLContext ctx = SSLContext.getInstance("TLS");
        ctx.init(km, tmf.getTrustManagers(), null);
        return ctx.getSocketFactory();
    }

    static String fetch(String url, SSLSocketFactory sf) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        if (sf != null && c instanceof HttpsURLConnection) ((HttpsURLConnection) c).setSSLSocketFactory(sf);
        c.setConnectTimeout(5000);
        c.setReadTimeout(10000);
        try {
            int code = c.getResponseCode();
            InputStream in = code < 400 ? c.getInputStream() : c.getErrorStream();
            ByteArrayOutputStream b = new ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            for (int n; in != null && (n = in.read(buf)) > 0; ) b.write(buf, 0, n);
            if (code != 200) throw new IllegalStateException("HTTP " + code + ": " + b.toString("UTF-8"));
            return b.toString("UTF-8");
        } finally {
            c.disconnect();
        }
    }

    static String run(String caseId, List<String> targets) {
        if (caseId == null) caseId = env("PQC_CASE_ID", "adhoc");
        String host = env("PQC_OBSERVER", "pq-observer");
        if (targets == null) {
            targets = new ArrayList<String>();
            for (String t : env("PQC_TARGETS", "hybrid,pqonly,mtls,eccert,tls12").split(",")) {
                if (!t.isEmpty()) targets.add(t);
            }
        }
        String egress = env("PQC_EGRESS_PORT", "");
        String compute = env("PQC_COMPUTE", "unknown"), mode = env("PQC_MODE", "baseline");
        String runtime = System.getProperty("java.version");
        String[] info = {"none", "", ""};
        SSLSocketFactory[] sf = {null};
        String setupErr = null;
        if (egress.isEmpty()) {
            try {
                info = tlsSetup(certsDir(), sf);
            } catch (Throwable e) {
                setupErr = err(e);
            }
        } else {
            info = new String[]{"extension:pq-egress", "extension", ""};
        }
        Map<String, String> results = new LinkedHashMap<String, String>();
        for (String name : targets) {
            int port = PORTS[Arrays.asList(NAMES).indexOf(name)];
            long t0 = System.currentTimeMillis();
            StringBuilder r = new StringBuilder("{");
            String status;
            try {
                boolean mldsa = name.startsWith("mldsa") && egress.isEmpty();
                if (setupErr != null && !mldsa) throw new IllegalStateException("TLS setup failed: " + setupErr);
                String url = egress.isEmpty() ? "https://" + host + ":" + port + "/probe?id=" + caseId
                        : "http://127.0.0.1:" + egress + "/" + name + "/probe?id=" + caseId;
                String obs = fetch(url, mldsa ? mldsaFactory(certsDir(), name.equals("mldsa-mtls")) : sf[0]);
                boolean pq = bool(obs, "pq");
                r.append("\"ok\":true,\"tls_version\":").append(raw(obs, "tls_version"))
                        .append(",\"group\":").append(raw(obs, "group"))
                        .append(",\"pq\":").append(pq)
                        .append(",\"offered_pq\":").append(bool(obs, "offered_pq"))
                        .append(",\"client_cert_cn\":").append(raw(obs, "client_cert_cn"));
                for (String k : PASS_THROUGH) if (obs.contains("\"" + k + "\"")) r.append(",\"").append(k).append("\":").append(raw(obs, k));
                r
                        .append(",\"stack\":").append(q("HttpsURLConnection " + info[0]));
                status = pq ? "pq" : "classical";
            } catch (Throwable e) {
                r.append("\"ok\":false,\"error\":").append(q(err(e))).append(",\"stack\":").append(q(stack(e)));
                status = "failed";
            }
            r.append(",\"ms\":").append(System.currentTimeMillis() - t0)
                    .append(",\"pq_status\":").append(q(status)).append("}");
            results.put(name, r.toString());
            String body = r.substring(1, r.length() - 1);
            System.out.println("{\"event\":\"tls_handshake\",\"case_id\":" + q(caseId) + ",\"lang\":\"java\",\"runtime\":"
                    + q(runtime) + ",\"compute\":" + q(compute) + ",\"mode\":" + q(mode) + ",\"target\":" + q(name)
                    + "," + body + "}");
            System.out.flush();
        }
        StringBuilder o = new StringBuilder("{");
        o.append("\"case_id\":").append(q(caseId)).append(",\"lang\":\"java\",\"runtime\":").append(q(runtime))
                .append(",\"java_vendor\":").append(q(System.getProperty("java.vendor") + " " + System.getProperty("java.vm.version")))
                .append(",\"tls_lib\":").append(q(info[0]))
                .append(",\"tls_setup\":").append(q(info[1]))
                .append(",\"key_manager\":").append(q(info[2]))
                .append(",\"kmf_default\":").append(q(Security.getProperty("ssl.KeyManagerFactory.algorithm")))
                .append(",\"named_groups\":").append(q(System.getProperty("jdk.tls.namedGroups")))
                .append(",\"client_protocols\":").append(q(System.getProperty("jdk.tls.client.protocols")))
                .append(",\"java_tool_options\":").append(q(System.getenv("JAVA_TOOL_OPTIONS")))
                .append(",\"exec_env\":").append(q(System.getenv("AWS_EXECUTION_ENV")))
                .append(",\"providers\":").append(q(providers()))
                .append(",\"compute\":").append(q(compute)).append(",\"mode\":").append(q(mode))
                .append(",\"results\":{");
        boolean first = true;
        for (Map.Entry<String, String> e : results.entrySet()) {
            if (!first) o.append(",");
            first = false;
            o.append(q(e.getKey())).append(":").append(e.getValue());
        }
        return o.append("}}").toString();
    }

    static String providers() {
        StringBuilder b = new StringBuilder();
        java.security.Provider[] ps = Security.getProviders();
        for (int i = 0; i < ps.length && i < 6; i++) b.append(i == 0 ? "" : ",").append(ps[i].getName());
        return b.toString();
    }

    static String err(Throwable e) {
        String m = e.getClass().getName() + ": " + e.getMessage();
        for (Throwable c = e.getCause(); c != null && c != c.getCause(); c = c.getCause()) {
            m += " <- " + c.getClass().getSimpleName() + ": " + c.getMessage();
        }
        return m.length() > 400 ? m.substring(0, 400) : m;
    }

    static String stack(Throwable e) {
        StringBuilder b = new StringBuilder();
        StackTraceElement[] st = e.getStackTrace();
        for (int i = 0; i < st.length && i < 4; i++) b.append(i == 0 ? "" : " | ").append(st[i]);
        return b.toString();
    }

    // Tiny JSON helpers for the observer's flat object ({"tls_version":"TLSv1.3","group":"X25519MLKEM768","pq":true,...})
    static String raw(String json, String key) {
        int i = json.indexOf("\"" + key + "\"");
        if (i < 0) return "null";
        int s = json.indexOf(':', i) + 1;
        while (s < json.length() && json.charAt(s) == ' ') s++;
        if (s < json.length() && json.charAt(s) == '"') {
            int e = s + 1;
            while (e < json.length() && json.charAt(e) != '"') e += json.charAt(e) == '\\' ? 2 : 1;
            return json.substring(s, e + 1);
        }
        int e = s;
        while (e < json.length() && ",}] \n".indexOf(json.charAt(e)) < 0) e++;
        return json.substring(s, e);
    }

    static boolean bool(String json, String key) {
        return "true".equals(raw(json, key));
    }

    static String q(String s) {
        if (s == null) return "null";
        StringBuilder b = new StringBuilder("\"");
        for (char c : s.toCharArray()) {
            if (c == '"' || c == '\\') b.append('\\').append(c);
            else if (c < 0x20) b.append(String.format("\\u%04x", (int) c));
            else b.append(c);
        }
        return b.append('"').toString();
    }
}
