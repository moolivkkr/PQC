// Java (stock JDK): (1) PKIX validation of the ML-DSA chain, (2) TLS to the dual-cert nginx.
import java.io.FileInputStream;
import java.security.KeyStore;
import java.security.cert.*;
import java.util.*;
import javax.net.ssl.*;

public class VerifyChain {
    public static void main(String[] a) throws Exception {
        System.out.println("java " + System.getProperty("java.version"));
        CertificateFactory cf = CertificateFactory.getInstance("X.509");
        X509Certificate root = (X509Certificate) cf.generateCertificate(new FileInputStream("/work/mldsa-root.crt"));
        X509Certificate inter = (X509Certificate) cf.generateCertificate(new FileInputStream("/work/mldsa-int.crt"));
        X509Certificate leaf = (X509Certificate) cf.generateCertificate(new FileInputStream("/work/mldsa-leaf.crt"));
        System.out.println("leaf sigAlg=" + leaf.getSigAlgName() + " keyAlg=" + leaf.getPublicKey().getAlgorithm());
        try {
            CertPath path = cf.generateCertPath(List.of(leaf, inter));
            PKIXParameters p = new PKIXParameters(Set.of(new TrustAnchor(root, null)));
            p.setRevocationEnabled(false);
            CertPathValidator.getInstance("PKIX").validate(path, p);
            System.out.println("offline ML-DSA chain PKIX validate: OK");
        } catch (Exception e) {
            System.out.println("offline ML-DSA chain PKIX validate: FAIL " + e);
        }
        KeyStore ts = KeyStore.getInstance("PKCS12");
        ts.load(null, null);
        Collection<? extends Certificate> roots = cf.generateCertificates(new FileInputStream("/work/roots-both.crt"));
        int i = 0;
        for (Certificate c : roots) ts.setCertificateEntry("r" + i++, c);
        TrustManagerFactory tmf = TrustManagerFactory.getInstance("PKIX");
        tmf.init(ts);
        SSLContext ctx = SSLContext.getInstance("TLS");
        ctx.init(null, tmf.getTrustManagers(), null);
        try (SSLSocket s = (SSLSocket) ctx.getSocketFactory().createSocket("web", 443)) {
            SSLParameters sp = s.getSSLParameters();
            sp.setEndpointIdentificationAlgorithm("HTTPS");
            s.setSSLParameters(sp);
            s.startHandshake();
            X509Certificate got = (X509Certificate) s.getSession().getPeerCertificates()[0];
            System.out.println("tls ok: " + s.getSession().getProtocol() + " leafKey=" + got.getPublicKey().getAlgorithm());
        } catch (Exception e) {
            System.out.println("tls FAIL " + e);
        }
    }
}
