// Kestrel test server for the .NET PQ runbook, cases C (certificates), E (mTLS) and F (TLS settings).
// The certificate comes from configuration (env vars Kestrel__...), except in the modes below:
//   MODE=selector  ServerCertificateSelector: ec.test -> EC cert, rsa.test -> RSA cert (PFX files)
//   MODE=store     imports STORE_IMPORT_PFX into X509Store CurrentUser/My first; the endpoint then uses
//                  Kestrel config "Certificate": { "Subject", "Store": "My", "Location": "CurrentUser" }
//   MTLS=1         ClientCertificateMode.RequireCertificate, client chain checked against CA_FILE (CustomTrustStore)
//   TLS12=1        SslProtocols = Tls12 only (pitfall)
//   CIPHERS13=1    CipherSuitesPolicy limited to TLS 1.3 AES-GCM suites
using System.Net.Security;
using System.Security.Authentication;
using System.Security.Cryptography.X509Certificates;
using Microsoft.AspNetCore.Connections.Features;
using Microsoft.AspNetCore.Server.Kestrel.Https;

string mode = Environment.GetEnvironmentVariable("MODE") ?? "config";
string? caFile = Environment.GetEnvironmentVariable("CA_FILE");

if (mode == "store")
{
    // One-time import, as a deployment step would do it. PersistKeySet keeps the key in the store on Linux.
    using var store = new X509Store(StoreName.My, StoreLocation.CurrentUser);
    store.Open(OpenFlags.ReadWrite);
    var pfx = new X509Certificate2(Environment.GetEnvironmentVariable("STORE_IMPORT_PFX")!,
        Environment.GetEnvironmentVariable("STORE_IMPORT_PASSWORD"), X509KeyStorageFlags.PersistKeySet | X509KeyStorageFlags.Exportable);
    store.Add(pfx);
    Console.WriteLine($"imported {pfx.Subject} into CurrentUser/My ({store.Certificates.Count} certs)");
}

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.ConfigureKestrel(kestrel =>
{
    kestrel.ConfigureHttpsDefaults(https =>
    {
        https.SslProtocols = Environment.GetEnvironmentVariable("TLS12") == "1" ? SslProtocols.Tls12 : SslProtocols.None;

        if (mode == "selector")
        {
            var ec = new X509Certificate2("/certs/server-ec.pfx", "changeit");
            var rsa = new X509Certificate2("/certs/server-rsa.pfx", "changeit");
            https.ServerCertificateSelector = (ctx, name) => name == "rsa.test" ? rsa : ec;
        }

        if (Environment.GetEnvironmentVariable("CIPHERS13") == "1")
        {
            https.OnAuthenticate = (ctx, opts) => opts.CipherSuitesPolicy = new CipherSuitesPolicy(new[] {
                TlsCipherSuite.TLS_AES_256_GCM_SHA384, TlsCipherSuite.TLS_AES_128_GCM_SHA256 });
        }

        if (Environment.GetEnvironmentVariable("MTLS") == "1")
        {
            var ca = X509Certificate2.CreateFromPem(File.ReadAllText(caFile!)); // cert only; CreateFromPemFile would want a key
            https.ClientCertificateMode = ClientCertificateMode.RequireCertificate;
            https.ClientCertificateValidation = (cert, chain, errors) =>
            {
                using var c = new X509Chain();
                c.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
                c.ChainPolicy.CustomTrustStore.Add(ca);
                c.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
                return c.Build(cert);
            };
        }
    });
});

var app = builder.Build();
app.MapGet("/", (HttpContext ctx) =>
{
    var tls = ctx.Features.Get<ITlsHandshakeFeature>();
    var cc = ctx.Connection.ClientCertificate;
    return $"ok protocol={tls?.Protocol} cipher={tls?.NegotiatedCipherSuite} host={ctx.Request.Host.Host} clientcert={cc?.Subject ?? "none"}\n";
});
app.Run();
