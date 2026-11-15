import java.io.FileInputStream;
import java.net.URI;
import java.net.URL;
import java.security.KeyStore;
import java.security.Security;
import java.util.Arrays;
import java.util.concurrent.TimeUnit;
import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;

import io.netty.bootstrap.Bootstrap;
import io.netty.bootstrap.ServerBootstrap;
import io.netty.channel.Channel;
import io.netty.channel.ChannelInitializer;
import io.netty.channel.EventLoopGroup;
import io.netty.channel.nio.NioEventLoopGroup;
import io.netty.channel.socket.SocketChannel;
import io.netty.channel.socket.nio.NioServerSocketChannel;
import io.netty.channel.socket.nio.NioSocketChannel;
import io.netty.handler.ssl.OpenSsl;
import io.netty.handler.ssl.SslContext;
import io.netty.handler.ssl.SslContextBuilder;
import io.netty.handler.ssl.SslContextOption;
import io.netty.handler.ssl.SslHandler;
import io.netty.handler.ssl.SslProvider;

/**
 * PQ TLS probe for Java clients and servers.
 *   client <lib> <host> <pqPort> <classicalPort>
 *   server <impl> <port> [groups]
 * Trust and key material come from the standard javax.net.ssl.* system properties
 * (trust) and /w/certs/server.p12 (server key, password "changeit").
 */
public class Probe {
    static final String KS = "/w/certs/server.p12";
    static final char[] PW = "changeit".toCharArray();

    public static void main(String[] a) throws Exception {
        String jdk = System.getProperty("java.vendor") + " " + System.getProperty("java.version");
        String tlsProv = SSLContext.getDefault().getProvider().getName();
        if (a[0].equals("client")) {
            String lib = a[1], host = a[2];
            String[] names = {"PQ-only", "classical-only"};
            int[] ports = {Integer.parseInt(a[3]), Integer.parseInt(a[4])};
            for (int i = 0; i < 2; i++) {
                String tag = String.format("%-22s %-20s %-15s", jdk + "/" + tlsProv, lib, names[i]);
                try {
                    System.out.println(tag + " OK   " + client(lib, host, ports[i]));
                } catch (Throwable e) {
                    Throwable r = e;
                    while (r.getCause() != null && r.getCause() != r) r = r.getCause();
                    String m = String.valueOf(r.getMessage());
                    System.out.println(tag + " FAIL " + r.getClass().getSimpleName() + ": " + m.substring(0, Math.min(140, m.length())).replace('\n', ' '));
                }
            }
            System.exit(0);
        } else {
            String groups = a.length > 3 ? a[3] : null;
            System.out.println("server " + a[1] + " on " + jdk + " provider=" + tlsProv + " groups=" + groups
                    + " jdk.tls.namedGroups=" + System.getProperty("jdk.tls.namedGroups"));
            server(a[1], Integer.parseInt(a[2]), groups);
        }
    }

    static String url(String h, int p) { return "https://" + h + ":" + p + "/"; }

    static String client(String lib, String host, int port) throws Exception {
        String u = url(host, port);
        switch (lib) {
            case "jdk-httpclient": {
                var c = java.net.http.HttpClient.newHttpClient();
                var r = c.send(java.net.http.HttpRequest.newBuilder(URI.create(u)).timeout(java.time.Duration.ofSeconds(5)).build(),
                        java.net.http.HttpResponse.BodyHandlers.discarding());
                return "HTTP " + r.statusCode() + " " + r.sslSession().map(s -> s.getProtocol()).orElse("?");
            }
            case "urlconnection": {
                HttpsURLConnection c = (HttpsURLConnection) new URL(u).openConnection();
                c.setConnectTimeout(5000); c.setReadTimeout(5000);
                int code = c.getResponseCode();
                return "HTTP " + code + " " + c.getCipherSuite();
            }
            case "apache5": {
                try (var c = org.apache.hc.client5.http.impl.classic.HttpClients.createSystem()) {
                    return "HTTP " + c.execute(new org.apache.hc.client5.http.classic.methods.HttpGet(u), r -> r.getCode());
                }
            }
            case "apache4": {
                try (var c = org.apache.http.impl.client.HttpClients.createSystem()) {
                    try (var r = c.execute(new org.apache.http.client.methods.HttpGet(u))) {
                        return "HTTP " + r.getStatusLine().getStatusCode();
                    }
                }
            }
            case "okhttp": {
                var c = new okhttp3.OkHttpClient.Builder().callTimeout(5, TimeUnit.SECONDS).build();
                try (var r = c.newCall(new okhttp3.Request.Builder().url(u).build()).execute()) {
                    return "HTTP " + r.code() + " " + r.handshake().tlsVersion();
                }
            }
            case "netty-jdk": return netty(host, port, SslProvider.JDK, null);
            case "netty-tcnative": return netty(host, port, SslProvider.OPENSSL, null);
            case "netty-tcnative-groups": return netty(host, port, SslProvider.OPENSSL, new String[]{"X25519MLKEM768", "X25519"});
            case "netty-jdk-groups": return netty(host, port, SslProvider.JDK, new String[]{"X25519MLKEM768", "x25519"});
            case "aws-crt": return aws(host, port, software.amazon.awssdk.http.crt.AwsCrtHttpClient.create());
            case "aws-apache": return aws(host, port, software.amazon.awssdk.http.apache.ApacheHttpClient.create());
            case "aws-netty": return awsAsync(host, port);
            case "pgjdbc": {
                var p = new java.util.Properties();
                p.setProperty("user", "postgres"); p.setProperty("password", "pq");
                p.setProperty("sslmode", "verify-full");
                p.setProperty("sslfactory", "org.postgresql.ssl.DefaultJavaSSLFactory");
                try (var c = java.sql.DriverManager.getConnection("jdbc:postgresql://" + host + ":" + port + "/postgres", p);
                     var s = c.createStatement();
                     var r = s.executeQuery("select version, cipher from pg_stat_ssl where pid = pg_backend_pid()")) {
                    r.next();
                    return r.getString(1) + " " + r.getString(2);
                }
            }
            default: throw new IllegalArgumentException(lib);
        }
    }

    @SuppressWarnings("unchecked")
    static SslContextBuilder groups(SslContextBuilder b, String[] groups) throws Exception {
        if (groups == null) return b;
        // OpenSslContextOption.GROUPS exists only in newer Netty; look it up so the probe still compiles without it.
        Object opt = Class.forName("io.netty.handler.ssl.OpenSslContextOption").getField("GROUPS").get(null);
        return b.option((SslContextOption<Object>) opt, groups);
    }

    static String netty(String host, int port, SslProvider prov, String[] groups) throws Exception {
        SslContextBuilder b = SslContextBuilder.forClient().sslProvider(prov).protocols("TLSv1.3");
        if (groups != null && prov == SslProvider.JDK) {
            // JDK provider: groups come from jdk.tls.namedGroups (JDK 20+ SSLParameters#setNamedGroups is not exposed by Netty).
            System.setProperty("jdk.tls.namedGroups", String.join(",", groups));
        } else {
            b = groups(b, groups);
        }
        SslContext ctx = b.build();
        EventLoopGroup g = new NioEventLoopGroup(1);
        try {
            final SslHandler[] h = new SslHandler[1];
            Channel ch = new Bootstrap().group(g).channel(NioSocketChannel.class)
                    .handler(new ChannelInitializer<SocketChannel>() {
                        protected void initChannel(SocketChannel c) {
                            h[0] = ctx.newHandler(c.alloc(), host, port);
                            c.pipeline().addLast(h[0]);
                        }
                    }).connect(host, port).sync().channel();
            h[0].handshakeFuture().sync();
            String v = prov == SslProvider.OPENSSL ? " " + OpenSsl.versionString() : "";
            String p = h[0].engine().getSession().getProtocol();
            ch.close().sync();
            return p + v;
        } finally {
            g.shutdownGracefully(0, 1, TimeUnit.SECONDS);
        }
    }

    static String aws(String host, int port, software.amazon.awssdk.http.SdkHttpClient http) {
        try (var sts = software.amazon.awssdk.services.sts.StsClient.builder()
                .httpClient(http)
                .endpointOverride(URI.create(url(host, port)))
                .region(software.amazon.awssdk.regions.Region.US_EAST_1)
                .credentialsProvider(software.amazon.awssdk.auth.credentials.StaticCredentialsProvider.create(
                        software.amazon.awssdk.auth.credentials.AwsBasicCredentials.create("AKIDEXAMPLE", "secret")))
                .overrideConfiguration(o -> o.retryStrategy(software.amazon.awssdk.core.retry.RetryMode.STANDARD).apiCallTimeout(java.time.Duration.ofSeconds(10)))
                .build()) {
            sts.getCallerIdentity();
            return "unexpected success";
        } catch (software.amazon.awssdk.core.exception.SdkServiceException e) {
            // The probe server answers with an HTML page, so a service/parse error means TLS + HTTP worked.
            return "TLS ok, HTTP " + e.statusCode() + " (non-AWS body, expected)";
        } catch (software.amazon.awssdk.core.exception.SdkClientException e) {
            String m = String.valueOf(e.getMessage());
            if (m.contains("Unable to unmarshall") || m.contains("parse") || m.contains("Unmarshall")) return "TLS ok (unmarshall error, expected)";
            throw e;
        }
    }

    static String awsAsync(String host, int port) throws Exception {
        try (var sts = software.amazon.awssdk.services.sts.StsAsyncClient.builder()
                .httpClient(software.amazon.awssdk.http.nio.netty.NettyNioAsyncHttpClient.create())
                .endpointOverride(URI.create(url(host, port)))
                .region(software.amazon.awssdk.regions.Region.US_EAST_1)
                .credentialsProvider(software.amazon.awssdk.auth.credentials.StaticCredentialsProvider.create(
                        software.amazon.awssdk.auth.credentials.AwsBasicCredentials.create("AKIDEXAMPLE", "secret")))
                .build()) {
            sts.getCallerIdentity().get(15, TimeUnit.SECONDS);
            return "unexpected success";
        } catch (java.util.concurrent.ExecutionException e) {
            if (e.getCause() instanceof software.amazon.awssdk.core.exception.SdkServiceException s)
                return "TLS ok, HTTP " + s.statusCode() + " (non-AWS body, expected)";
            throw e;
        }
    }

    static KeyManagerFactory kmf() throws Exception {
        KeyStore ks = KeyStore.getInstance("PKCS12");
        try (var in = new FileInputStream(KS)) { ks.load(in, PW); }
        KeyManagerFactory k = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        k.init(ks, PW);
        return k;
    }

    static void server(String impl, int port, String groups) throws Exception {
        switch (impl) {
            case "tomcat": {
                var t = new org.apache.catalina.startup.Tomcat();
                t.setBaseDir("/tmp/tc" + port);
                var c = new org.apache.catalina.connector.Connector("org.apache.coyote.http11.Http11NioProtocol");
                c.setPort(port);
                c.setSecure(true); c.setScheme("https");
                c.setProperty("SSLEnabled", "true");
                var h = new org.apache.tomcat.util.net.SSLHostConfig();
                h.setProtocols("TLSv1.3+TLSv1.2");
                if (groups != null) h.setGroups(groups);
                var cert = new org.apache.tomcat.util.net.SSLHostConfigCertificate(h, org.apache.tomcat.util.net.SSLHostConfigCertificate.Type.UNDEFINED);
                cert.setCertificateKeystoreFile(KS);
                cert.setCertificateKeystorePassword("changeit");
                cert.setCertificateKeystoreType("PKCS12");
                h.addCertificate(cert);
                c.addSslHostConfig(h);
                t.getService().addConnector(c);
                t.getConnector();
                var ctx = t.addContext("", null);
                org.apache.catalina.startup.Tomcat.addServlet(ctx, "ok", new jakarta.servlet.http.HttpServlet() {
                    protected void doGet(jakarta.servlet.http.HttpServletRequest q, jakarta.servlet.http.HttpServletResponse r) throws java.io.IOException {
                        r.getWriter().println("ok");
                    }
                });
                ctx.addServletMappingDecoded("/", "ok");
                t.start();
                t.getServer().await();
                break;
            }
            case "jetty": {
                var s = new org.eclipse.jetty.server.Server();
                var f = new org.eclipse.jetty.util.ssl.SslContextFactory.Server();
                f.setKeyStorePath(KS);
                f.setKeyStorePassword("changeit");
                f.setKeyStoreType("PKCS12");
                var https = new org.eclipse.jetty.server.HttpConfiguration();
                https.addCustomizer(new org.eclipse.jetty.server.SecureRequestCustomizer(false));
                var conn = new org.eclipse.jetty.server.ServerConnector(s,
                        new org.eclipse.jetty.server.SslConnectionFactory(f, "http/1.1"),
                        new org.eclipse.jetty.server.HttpConnectionFactory(https));
                conn.setPort(port);
                s.addConnector(conn);
                s.start();
                s.join();
                break;
            }
            case "jdk-httpsserver": {
                var s = com.sun.net.httpserver.HttpsServer.create(new java.net.InetSocketAddress(port), 0);
                SSLContext ctx = SSLContext.getInstance("TLS");
                ctx.init(kmf().getKeyManagers(), null, null);
                s.setHttpsConfigurator(new com.sun.net.httpserver.HttpsConfigurator(ctx));
                s.createContext("/", x -> { x.sendResponseHeaders(200, 0); x.close(); });
                s.start();
                Thread.currentThread().join();
                break;
            }
            case "netty-tcnative":
            case "netty-jdk": {
                SslProvider prov = impl.equals("netty-jdk") ? SslProvider.JDK : SslProvider.OPENSSL;
                SslContextBuilder b = SslContextBuilder.forServer(kmf()).sslProvider(prov).protocols("TLSv1.3", "TLSv1.2");
                if (prov == SslProvider.OPENSSL) {
                    System.out.println("netty openssl=" + OpenSsl.versionString());
                    b = groups(b, groups == null ? null : groups.split(","));
                }
                SslContext ctx = b.build();
                EventLoopGroup g = new NioEventLoopGroup(1);
                new ServerBootstrap().group(g).channel(NioServerSocketChannel.class)
                        .childHandler(new ChannelInitializer<SocketChannel>() {
                            protected void initChannel(SocketChannel c) {
                                c.pipeline().addLast(ctx.newHandler(c.alloc()));
                            }
                        }).bind(port).sync().channel().closeFuture().sync();
                break;
            }
            default: throw new IllegalArgumentException(impl);
        }
    }
}
