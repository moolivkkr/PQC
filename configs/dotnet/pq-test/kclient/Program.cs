// .NET PQ client probe for cases D (custom CA trust), E (client certificates) and F (TLS settings).
// usage: dotnet kclient.dll <case> <url> [<url> ...]   (CA_FILE, CLIENT_PFX, CLIENT_CRT, CLIENT_KEY env vars)
// cases: system | callback | chainpolicy | mtls-handler | mtls-sockets | mtls-store | tls12 | ciphers13
using System.Net.Security;
using System.Security.Authentication;
using System.Security.Cryptography.X509Certificates;

string kase = args[0];
string caFile = Environment.GetEnvironmentVariable("CA_FILE") ?? "/certs/ca.crt";
// Not CreateFromPemFile(caFile): with no key path it looks for a private key in the same file and throws.
X509Certificate2 Ca() => X509Certificate2.CreateFromPem(File.ReadAllText(caFile));

X509ChainPolicy CustomTrust()
{
    var p = new X509ChainPolicy { TrustMode = X509ChainTrustMode.CustomRootTrust, RevocationMode = X509RevocationMode.NoCheck };
    p.CustomTrustStore.Add(Ca());
    return p;
}

// Validation callback the way many teams write it: build the chain against their own CA, keep hostname checks.
bool Callback(object? s, X509Certificate2? cert, X509Chain? chain, SslPolicyErrors errors)
{
    if (cert is null || (errors & SslPolicyErrors.RemoteCertificateNameMismatch) != 0) return false;
    using var c = new X509Chain { ChainPolicy = CustomTrust() };
    return c.Build(cert);
}

HttpMessageHandler Build()
{
    switch (kase)
    {
        case "system": return new SocketsHttpHandler();                        // OS trust store / SSL_CERT_FILE / SSL_CERT_DIR
        case "callback": return new HttpClientHandler { ServerCertificateCustomValidationCallback = Callback };
        case "chainpolicy":
        {
            var h = new SocketsHttpHandler();
            h.SslOptions.CertificateChainPolicy = CustomTrust();             // .NET 7+
            return h;
        }
        case "mtls-handler":
        {
            var h = new HttpClientHandler { ServerCertificateCustomValidationCallback = Callback, ClientCertificateOptions = ClientCertificateOption.Manual };
            h.ClientCertificates.Add(new X509Certificate2(Environment.GetEnvironmentVariable("CLIENT_PFX")!, "changeit"));
            return h;
        }
        case "mtls-sockets":
        {
            var h = new SocketsHttpHandler();
            h.SslOptions.CertificateChainPolicy = CustomTrust();
            h.SslOptions.ClientCertificates = new X509CertificateCollection {
                X509Certificate2.CreateFromPemFile(Environment.GetEnvironmentVariable("CLIENT_CRT")!, Environment.GetEnvironmentVariable("CLIENT_KEY")) };
            return h;
        }
        case "mtls-store":
        {
            using var store = new X509Store(StoreName.My, StoreLocation.CurrentUser);
            store.Open(OpenFlags.ReadWrite);
            store.Add(new X509Certificate2(Environment.GetEnvironmentVariable("CLIENT_PFX")!, "changeit", X509KeyStorageFlags.PersistKeySet));
            var found = store.Certificates.Find(X509FindType.FindBySubjectName, "pq-client", false);
            var h = new SocketsHttpHandler();
            h.SslOptions.CertificateChainPolicy = CustomTrust();
            h.SslOptions.ClientCertificates = new X509CertificateCollection { found[0] };
            return h;
        }
        case "tls12":
        {
            var h = new SocketsHttpHandler();
            h.SslOptions.CertificateChainPolicy = CustomTrust();
            h.SslOptions.EnabledSslProtocols = SslProtocols.Tls12;
            return h;
        }
        case "ciphers13":
        {
            var h = new SocketsHttpHandler();
            h.SslOptions.CertificateChainPolicy = CustomTrust();
            h.SslOptions.CipherSuitesPolicy = new CipherSuitesPolicy(new[] { TlsCipherSuite.TLS_AES_256_GCM_SHA384, TlsCipherSuite.TLS_AES_128_GCM_SHA256 });
            return h;
        }
        default: throw new ArgumentException(kase);
    }
}

foreach (var url in args.Skip(1))
{
    string r;
    try
    {
        using var http = new HttpClient(Build()) { Timeout = TimeSpan.FromSeconds(10) };
        var resp = http.GetAsync(url).GetAwaiter().GetResult();
        var body = resp.Content.ReadAsStringAsync().GetAwaiter().GetResult();
        r = $"OK {(int)resp.StatusCode}" + (body.StartsWith("ok ") ? " " + body.Trim() : "");
    }
    catch (Exception e)
    {
        var i = e; while (i.InnerException != null) i = i.InnerException;
        r = $"FAIL {i.GetType().Name}: {i.Message.Split('\n')[0]}";
    }
    Console.WriteLine($"  [{kase}] {url} -> {r}");
}
