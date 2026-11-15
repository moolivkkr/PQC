import io.netty.handler.ssl.*;

final class NettyPq {
    static final String[] GROUPS = {"X25519MLKEM768", "X25519", "P-256", "P-384"};

    static SslContext client() throws Exception {
        return SslContextBuilder.forClient()
                .sslProvider(SslProvider.OPENSSL)            // netty-tcnative-boringssl-static on the class path
                .protocols("TLSv1.3", "TLSv1.2")
                .option(OpenSslContextOption.GROUPS, GROUPS) // omit to keep the library default
                .build();
    }

    static SslContext server(javax.net.ssl.KeyManagerFactory kmf) throws Exception {
        return SslContextBuilder.forServer(kmf)
                .sslProvider(SslProvider.OPENSSL)
                .protocols("TLSv1.3", "TLSv1.2")
                .option(OpenSslContextOption.GROUPS, GROUPS)
                .build();
    }
}
