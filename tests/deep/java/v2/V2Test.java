import javax.net.ssl.*;
import java.io.*;
import java.security.KeyStore;
import java.security.Security;
import java.security.cert.Certificate;
import java.security.cert.X509Certificate;

// server <keystore|default> <type> <kmfAlg: default|SunX509|PKIX> <port>   (-DneedClientAuth=true for mTLS)
// client <host> <port>                                                    (client cert via javax.net.ssl.keyStore)
// tomcat <p12> <port> <keyManagerAlgorithm|default>                       (embedded Tomcat, SSLHostConfig)
public class V2Test {
    static final char[] PW = "changeit".toCharArray();

    static String cn(Certificate[] c) {
        return c == null || c.length == 0 ? "none" : ((X509Certificate) c[0]).getSubjectX500Principal().getName();
    }

    public static void main(String[] a) throws Exception {
        System.out.println("jdk=" + System.getProperty("java.version") + " kmfDefault=" + KeyManagerFactory.getDefaultAlgorithm()
                + " secprop=" + Security.getProperty("ssl.KeyManagerFactory.algorithm"));
        switch (a[0]) {
            case "server": server(a); break;
            case "client": client(a[1], Integer.parseInt(a[2])); break;
            case "tomcat": tomcat(a[1], Integer.parseInt(a[2]), a[3]); break;
            default: throw new IllegalArgumentException(a[0]);
        }
    }

    static void server(String[] a) throws Exception {
        SSLContext ctx;
        if (a[1].equals("default")) {
            ctx = SSLContext.getDefault();
        } else {
            KeyStore ks = KeyStore.getInstance(a[2]);
            try (var in = new FileInputStream(a[1])) { ks.load(in, PW); }
            KeyManagerFactory f = KeyManagerFactory.getInstance(a[3].equals("default") ? KeyManagerFactory.getDefaultAlgorithm() : a[3]);
            f.init(ks, PW);
            System.out.println("server: kmf=" + f.getAlgorithm() + "/" + f.getProvider().getName());
            ctx = SSLContext.getInstance("TLS");
            ctx.init(f.getKeyManagers(), null, null);   // null trust managers = default (javax.net.ssl.trustStore or cacerts)
        }
        System.out.println("server: SSLContext provider=" + ctx.getProvider().getName());
        SSLServerSocket ss = (SSLServerSocket) ctx.getServerSocketFactory().createServerSocket(Integer.parseInt(a[4]));
        if (Boolean.getBoolean("needClientAuth")) ss.setNeedClientAuth(true);
        while (true) {
            try (SSLSocket s = (SSLSocket) ss.accept()) {
                s.startHandshake();
                Certificate[] peer = null;
                try { peer = s.getSession().getPeerCertificates(); } catch (SSLPeerUnverifiedException e) { }
                System.out.println("server: OK " + s.getSession().getProtocol() + " client-cert=" + cn(peer)
                        + " server-cert=" + cn(s.getSession().getLocalCertificates()));
                s.getOutputStream().write("HTTP/1.0 200 OK\r\n\r\nok\n".getBytes());
                s.getOutputStream().flush();
            } catch (Exception e) {
                System.out.println("server: handshake failed: " + e);
            }
        }
    }

    static void client(String host, int port) {
        SSLContext ctx = null;
        try {
            ctx = SSLContext.getDefault();
            try (SSLSocket s = (SSLSocket) ctx.getSocketFactory().createSocket(host, port)) {
                s.startHandshake();
                s.getOutputStream().write("GET / HTTP/1.0\r\n\r\n".getBytes());
                s.getOutputStream().flush();
                String line = new BufferedReader(new InputStreamReader(s.getInputStream())).readLine();
                System.out.println("client OK provider=" + ctx.getProvider().getName() + " " + s.getSession().getProtocol()
                        + " server-cert=" + cn(s.getSession().getPeerCertificates())
                        + " sent-client-cert=" + cn(s.getSession().getLocalCertificates()) + " first-line=" + line);
            }
        } catch (Exception e) {
            System.out.println("client FAIL provider=" + (ctx == null ? "?" : ctx.getProvider().getName()) + ": " + e);
        }
    }

    static void tomcat(String p12, int port, String kma) throws Exception {
        var t = new org.apache.catalina.startup.Tomcat();
        t.setBaseDir("/tmp/tc" + port);
        var c = new org.apache.catalina.connector.Connector("org.apache.coyote.http11.Http11NioProtocol");
        c.setPort(port);
        c.setSecure(true);
        c.setScheme("https");
        c.setProperty("SSLEnabled", "true");
        var h = new org.apache.tomcat.util.net.SSLHostConfig();
        h.setProtocols("TLSv1.3+TLSv1.2");
        if (!kma.equals("default")) h.setKeyManagerAlgorithm(kma);   // server.xml: <SSLHostConfig keyManagerAlgorithm="...">
        System.out.println("tomcat: SSLHostConfig keyManagerAlgorithm=" + h.getKeyManagerAlgorithm());
        var cert = new org.apache.tomcat.util.net.SSLHostConfigCertificate(h, org.apache.tomcat.util.net.SSLHostConfigCertificate.Type.UNDEFINED);
        cert.setCertificateKeystoreFile(p12);
        cert.setCertificateKeystorePassword("changeit");
        cert.setCertificateKeystoreType("PKCS12");
        h.addCertificate(cert);
        c.addSslHostConfig(h);
        t.getService().addConnector(c);
        t.getConnector();
        var ctx = t.addContext("", null);
        org.apache.catalina.startup.Tomcat.addServlet(ctx, "ok", new jakarta.servlet.http.HttpServlet() {
            protected void doGet(jakarta.servlet.http.HttpServletRequest q, jakarta.servlet.http.HttpServletResponse r) throws IOException {
                r.getWriter().println("ok");
            }
        });
        ctx.addServletMappingDecoded("/", "ok");
        t.start();
        t.getServer().await();
    }
}
