// .NET 10: (1) X509Chain over the ML-DSA chain with a custom root, (2) HttpClient to the dual-cert nginx.
using System.Net.Http;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

Console.WriteLine($".NET {Environment.Version}  MLDsa.IsSupported={MLDsa.IsSupported}");
var root = X509Certificate2.CreateFromPem(File.ReadAllText("/work/mldsa-root.crt"));
var inter = X509Certificate2.CreateFromPem(File.ReadAllText("/work/mldsa-int.crt"));
var leaf = X509Certificate2.CreateFromPem(File.ReadAllText("/work/mldsa-leaf.crt"));
Console.WriteLine($"leaf key OID={leaf.PublicKey.Oid.Value} ({leaf.PublicKey.Oid.FriendlyName}) GetMLDsaPublicKey={(leaf.GetMLDsaPublicKey() != null)}");
using (var chain = new X509Chain())
{
    chain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
    chain.ChainPolicy.CustomTrustStore.Add(root);
    chain.ChainPolicy.ExtraStore.Add(inter);
    chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
    bool ok = chain.Build(leaf);
    Console.WriteLine($"offline ML-DSA chain build: {ok} {string.Join(",", chain.ChainStatus.Select(s => s.Status))}");
}
var roots = new X509Certificate2Collection();
roots.ImportFromPemFile("/work/roots-both.crt");
var handler = new HttpClientHandler
{
    ServerCertificateCustomValidationCallback = (msg, cert, ch, errors) =>
    {
        using var c = new X509Chain();
        c.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
        c.ChainPolicy.CustomTrustStore.AddRange(roots);
        c.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
        foreach (var el in ch!.ChainPolicy.ExtraStore) c.ChainPolicy.ExtraStore.Add(el); // intermediates sent by the server
        bool ok = c.Build(cert!);
        Console.WriteLine($"tls leaf key OID={cert!.PublicKey.Oid.Value} chainOk={ok} nameErrors={errors & System.Net.Security.SslPolicyErrors.RemoteCertificateNameMismatch}");
        return ok;
    }
};
using var http = new HttpClient(handler);
try { Console.WriteLine("GET: " + (await http.GetStringAsync("https://web/")).Trim()); }
catch (Exception e) { Console.WriteLine("GET FAIL " + e.GetBaseException().Message); }
