// PQ TLS probe - .NET. Same code on Lambda (managed dotnet8/dotnet10 handler, container image, Native AOT bootstrap),
// ECS and EC2 (console: dotnet probe.dll). No PQ-specific settings: .NET has no key-exchange-group API, so the OS OpenSSL
// plus OPENSSL_CONF / crypto policy (or the pq-egress extension) decide what is measured.
//
// Client stack: HttpClient + SocketsHttpHandler (the path HttpClient, IHttpClientFactory and the AWS SDK use).
// Knobs that reproduce the .NET tab's "existing configuration" cases (all optional; defaults = tab case A/D4/E1):
//   PQC_DOTNET_TRUST      custom   (default) SslOptions.CertificateChainPolicy CustomRootTrust + CustomTrustStore (tab D4)
//                         system   no trust code: OS store / SSL_CERT_FILE / SSL_CERT_DIR / update-ca-trust (tab D1, D2, D5)
//                         callback HttpClientHandler.ServerCertificateCustomValidationCallback building the chain (tab D3)
//   PQC_DOTNET_CLIENTCERT p12 (default, client.p12 password changeit), pem (CreateFromPemFile crt+key, tab E2),
//                         store (client.p12 imported into X509Store CurrentUser/My, then read back from the store, tab E3)
//   PQC_DOTNET_HANDLER    sockets (default) | httpclienthandler (HttpClientHandler.ClientCertificates, tab E1)
//   PQC_DOTNET_PROTOCOLS  unset (default: SslProtocols.None = OS default) | Tls12 | Tls12,Tls13  (tab case F1)
// Every result is also printed as one JSON line {"event":"tls_handshake",...,"pq_status":...} for the log filters.
using System.Diagnostics;
using System.Net.Security;
using System.Runtime.InteropServices;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using Amazon.Lambda.Core;

namespace Probe;

public static class Core
{
    static readonly (string Name, int Port)[] Targets =
        { ("hybrid", 8443), ("pqonly", 8444), ("mtls", 8445), ("eccert", 8446), ("tls12", 8447),
          ("mldsa-dual", 8448), ("mldsa-only", 8449), ("mldsa-mtls", 8450) };
    static readonly string[] PassThrough = { "server_cert", "server_sigalg", "client_cert", "client_sigalg" };

    // ML-DSA targets: SocketsHttpHandler with custom root trust = both roots in ca-both.crt (test CA + ML-DSA test CA),
    // whatever PQC_DOTNET_TRUST says; mldsa-mtls presents client-mldsa.crt/.key (PEM). They measure ML-DSA support only.
    static HttpMessageInvoker MldsaClient(string target, string certs)
    {
        var roots = new X509Certificate2Collection();
        roots.ImportFromPemFile(Path.Combine(certs, "ca-both.crt"));
        var sh = new SocketsHttpHandler { ConnectTimeout = TimeSpan.FromSeconds(5), PooledConnectionLifetime = TimeSpan.Zero };
        sh.SslOptions.CertificateChainPolicy = new X509ChainPolicy
        {
            TrustMode = X509ChainTrustMode.CustomRootTrust, RevocationMode = X509RevocationMode.NoCheck,
        };
        sh.SslOptions.CertificateChainPolicy.CustomTrustStore.AddRange(roots);
        if (target == "mldsa-mtls")
            sh.SslOptions.ClientCertificates = new X509CertificateCollection {
                X509Certificate2.CreateFromPemFile(Path.Combine(certs, "client-mldsa.crt"), Path.Combine(certs, "client-mldsa.key")) };
        return new HttpClient(sh) { Timeout = TimeSpan.FromSeconds(15) };
    }

    static string Env(string k, string d = "") => Environment.GetEnvironmentVariable(k) is { Length: > 0 } v ? v : d;

    static string CertsDir()
    {
        // <probe dir>/certs, then its parent (ECS images: /app/net10/probe.dll + /app/certs), then the shared locations
        var here = AppContext.BaseDirectory.TrimEnd('/');
        foreach (var d in new[] { Env("PQC_CERTS"), Path.Combine(here, "certs"), Path.Combine(Path.GetDirectoryName(here) ?? "/", "certs"),
                                  "/var/task/certs", "/app/certs", "/opt/pqc-certs", "/etc/pqc/certs" })
            if (d.Length > 0 && File.Exists(Path.Combine(d, "ca.crt"))) return d;
        throw new FileNotFoundException("test CA not found (set PQC_CERTS)");
    }

    static X509Certificate2 LoadP12(string path)
    {
#if NET9_0_OR_GREATER
        return X509CertificateLoader.LoadPkcs12FromFile(path, "changeit", X509KeyStorageFlags.PersistKeySet | X509KeyStorageFlags.Exportable);
#else
        return new X509Certificate2(path, "changeit", X509KeyStorageFlags.PersistKeySet | X509KeyStorageFlags.Exportable);
#endif
    }

    static X509Certificate2 ClientCert(string certs, string mode, List<string> notes)
    {
        switch (mode)
        {
            case "pem":
                return X509Certificate2.CreateFromPemFile(Path.Combine(certs, "client.crt"), Path.Combine(certs, "client.key"));
            case "store":
            {
                // An "existing certificate store": import once (as a deploy step would), then read it back by subject.
                // CurrentUser stores live under $HOME/.dotnet/corefx (on Lambda see cases dotnet-lambda-*-store-clientcert*).
                var p12 = LoadP12(Path.Combine(certs, "client.p12"));
                var cn = p12.GetNameInfo(X509NameType.SimpleName, false);
                using var st = new X509Store(StoreName.My, StoreLocation.CurrentUser);
                st.Open(OpenFlags.ReadWrite);
                if (st.Certificates.Find(X509FindType.FindBySubjectName, cn, false).Count == 0) st.Add(p12);
                var found = st.Certificates.Find(X509FindType.FindBySubjectName, cn, false);
                notes.Add($"X509Store CurrentUser/My: {found.Count} cert(s) CN={cn}, HasPrivateKey={found[0].HasPrivateKey}");
                return found[0];
            }
            default:
                return LoadP12(Path.Combine(certs, "client.p12"));
        }
    }

    static HttpMessageInvoker Client(string target, string certs, List<string> notes)
    {
        var trust = Env("PQC_DOTNET_TRUST", "custom");
        var ca = X509Certificate2.CreateFromPem(File.ReadAllText(Path.Combine(certs, "ca.crt")));   // tab D: not CreateFromPemFile
        X509Certificate2 cc = target == "mtls" ? ClientCert(certs, Env("PQC_DOTNET_CLIENTCERT", "p12"), notes) : null;
        SslProtocols? protos = null;
        var p = Env("PQC_DOTNET_PROTOCOLS");
        if (p.Length > 0)
        {
            protos = SslProtocols.None;
            foreach (var s in p.Split(',', StringSplitOptions.RemoveEmptyEntries)) protos |= Enum.Parse<SslProtocols>(s.Trim());
        }
        if (trust == "callback" || Env("PQC_DOTNET_HANDLER") == "httpclienthandler")
        {
            var h = new HttpClientHandler();
            if (trust == "callback")
                h.ServerCertificateCustomValidationCallback = (msg, cert, chain, errors) =>
                {
                    if (cert is null || (errors & SslPolicyErrors.RemoteCertificateNameMismatch) != 0) return false;
                    using var c = new X509Chain { ChainPolicy = { TrustMode = X509ChainTrustMode.CustomRootTrust, CustomTrustStore = { ca },
                                                                  RevocationMode = X509RevocationMode.NoCheck } };
                    return c.Build(cert);
                };
            else if (trust == "custom")
                throw new NotSupportedException("custom trust is a SocketsHttpHandler setting; use PQC_DOTNET_TRUST=callback|system");
            if (cc != null) { h.ClientCertificateOptions = ClientCertificateOption.Manual; h.ClientCertificates.Add(cc); }
            if (protos != null) h.SslProtocols = protos.Value;
            return new HttpClient(h) { Timeout = TimeSpan.FromSeconds(15) };
        }
        var sh = new SocketsHttpHandler { ConnectTimeout = TimeSpan.FromSeconds(5), PooledConnectionLifetime = TimeSpan.Zero };
        if (trust == "custom")
            sh.SslOptions.CertificateChainPolicy = new X509ChainPolicy
            {
                TrustMode = X509ChainTrustMode.CustomRootTrust, CustomTrustStore = { ca }, RevocationMode = X509RevocationMode.NoCheck,
            };
        if (cc != null) sh.SslOptions.ClientCertificates = new X509CertificateCollection { cc };
        if (protos != null) sh.SslOptions.EnabledSslProtocols = protos.Value;
        return new HttpClient(sh) { Timeout = TimeSpan.FromSeconds(15) };
    }

    static string ErrorChain(Exception e)
    {
        var parts = new List<string>();
        for (var x = e; x != null && parts.Count < 5; x = x.InnerException)
            parts.Add(x.GetType().Name + ": " + x.Message);
        var s = string.Join(" -> ", parts);
        return s.Length > 600 ? s[..600] : s;
    }

    static JsonElement Get(HttpMessageInvoker client, string url)
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(15));
        using var resp = client.SendAsync(req, cts.Token).GetAwaiter().GetResult();
        var body = resp.Content.ReadAsStringAsync().GetAwaiter().GetResult();
        if (!resp.IsSuccessStatusCode) throw new HttpRequestException($"HTTP {(int)resp.StatusCode}: {body[..Math.Min(200, body.Length)]}");
        using var doc = JsonDocument.Parse(body);
        return doc.RootElement.Clone();
    }

    // OpenSSL that .NET loaded: libcrypto's OpenSSL_version(OPENSSL_VERSION) string, plus .NET's own view (hex)
    static string OpenSslVersion()
    {
        string s = null;
        foreach (var lib in new[] { "libcrypto.so.3", "libcrypto.so.1.1", "libcrypto.so" })
        {
            if (!NativeLibrary.TryLoad(lib, out var h)) continue;
            if (NativeLibrary.TryGetExport(h, "OpenSSL_version", out var f))
                unsafe { s = Marshal.PtrToStringAnsi(((delegate* unmanaged<int, IntPtr>)f)(0)); }
            else if (NativeLibrary.TryGetExport(h, "SSLeay_version", out f))
                unsafe { s = Marshal.PtrToStringAnsi(((delegate* unmanaged<int, IntPtr>)f)(0)); }
            if (s != null) break;
        }
        try { s = (s ?? "OpenSSL ?") + $" (SafeEvpPKeyHandle.OpenSslVersion=0x{SafeEvpPKeyHandle.OpenSslVersion:x})"; }
        catch (Exception e) { s = (s ?? "?") + " (" + e.GetType().Name + ")"; }
        return s;
    }

    public static string Run(string caseId = null, IList<string> targets = null)
    {
        caseId ??= Env("PQC_CASE_ID", "adhoc");
        var host = Env("PQC_OBSERVER", "pq-observer");
        var names = targets?.Count > 0 ? targets.ToList()
            : Env("PQC_TARGETS", string.Join(",", Targets.Select(t => t.Name))).Split(',', StringSplitOptions.RemoveEmptyEntries).ToList();
        var certs = CertsDir();
        var egress = Env("PQC_EGRESS_PORT");
        var runtime = Environment.Version.ToString();
        var compute = Env("PQC_COMPUTE", "unknown");
        var mode = Env("PQC_MODE", "baseline");
        var stack = egress.Length > 0 ? "extension:pq-egress"
            : $"{(Env("PQC_DOTNET_TRUST") == "callback" || Env("PQC_DOTNET_HANDLER") == "httpclienthandler" ? "HttpClientHandler" : "SocketsHttpHandler")}"
              + $" trust={Env("PQC_DOTNET_TRUST", "custom")} clientcert={Env("PQC_DOTNET_CLIENTCERT", "p12")}"
              + (Env("PQC_DOTNET_PROTOCOLS").Length > 0 ? " protocols=" + Env("PQC_DOTNET_PROTOCOLS") : "");
        var results = new List<(string, Dictionary<string, object>)>();
        foreach (var name in names)
        {
            var sw = Stopwatch.StartNew();
            var res = new Dictionary<string, object>();
            var notes = new List<string>();
            try
            {
                JsonElement obs;
                if (egress.Length > 0)
                {
                    using var c = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
                    obs = Get(c, $"http://127.0.0.1:{egress}/{name}/probe?id={caseId}");
                }
                else
                {
                    var port = Targets.First(t => t.Name == name).Port;
                    using var c = name.StartsWith("mldsa") ? MldsaClient(name, certs) : Client(name, certs, notes);
                    obs = Get(c, $"https://{host}:{port}/probe?id={caseId}");
                }
                res["ok"] = true;
                res["tls_version"] = Str(obs, "tls_version");
                res["group"] = Str(obs, "group");
                res["pq"] = Bool(obs, "pq");
                res["offered_pq"] = Bool(obs, "offered_pq");
                foreach (var k in PassThrough) if (obs.TryGetProperty(k, out var pv) && pv.ValueKind == JsonValueKind.String) res[k] = pv.GetString();
                res["stack"] = name.StartsWith("mldsa") && egress.Length == 0 ? "SocketsHttpHandler trust=custom(ca-both)" : stack;
            }
            catch (Exception e)
            {
                res["ok"] = false;
                res["error"] = ErrorChain(e);
            }
            if (notes.Count > 0) res["notes"] = string.Join("; ", notes);
            res["ms"] = (int)sw.ElapsedMilliseconds;
            res["pq_status"] = !(bool)res["ok"] ? "failed" : (bool)res["pq"] ? "pq" : "classical";
            results.Add((name, res));
            Console.WriteLine(Json(w =>
            {
                w.WriteString("event", "tls_handshake"); w.WriteString("case_id", caseId); w.WriteString("lang", "dotnet");
                w.WriteString("runtime", runtime); w.WriteString("compute", compute); w.WriteString("mode", mode); w.WriteString("target", name);
                WriteDict(w, res);
            }));
            Console.Out.Flush();
        }
        var ossl = OpenSslVersion();
        return Json(w =>
        {
            w.WriteString("case_id", caseId); w.WriteString("lang", "dotnet"); w.WriteString("runtime", runtime);
            w.WriteString("framework", RuntimeInformation.FrameworkDescription);
            w.WriteString("os", RuntimeInformation.OSDescription);
            w.WriteString("aot", RuntimeFeature());
            w.WriteString("openssl", ossl); w.WriteString("tls_lib", ossl);
            w.WriteString("compute", compute); w.WriteString("mode", mode); w.WriteString("openssl_conf", Env("OPENSSL_CONF"));
            w.WriteString("exec_env", Env("AWS_EXECUTION_ENV"));
            w.WriteString("home", Env("HOME"));
            w.WriteStartObject("results");
            foreach (var (n, r) in results) { w.WriteStartObject(n); WriteDict(w, r); w.WriteEndObject(); }
            w.WriteEndObject();
        });
    }

    static string RuntimeFeature() =>
        System.Runtime.CompilerServices.RuntimeFeature.IsDynamicCodeSupported ? "no" : "yes (native AOT)";

    static string Str(JsonElement e, string k) => e.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
    static bool Bool(JsonElement e, string k) => e.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.True;

    static void WriteDict(Utf8JsonWriter w, Dictionary<string, object> d)
    {
        foreach (var (k, v) in d)
            switch (v)
            {
                case null: w.WriteNull(k); break;
                case bool b: w.WriteBoolean(k, b); break;
                case int i: w.WriteNumber(k, i); break;
                default: w.WriteString(k, v.ToString()); break;
            }
    }

    static string Json(Action<Utf8JsonWriter> body)
    {
        using var ms = new MemoryStream();
        using (var w = new Utf8JsonWriter(ms))
        {
            w.WriteStartObject(); body(w); w.WriteEndObject();
        }
        return Encoding.UTF8.GetString(ms.ToArray());
    }

    // Lambda event {"case_id":..., "targets":[...]}
    public static string RunEvent(Stream input)
    {
        string caseId = null; List<string> targets = null;
        try
        {
            using var doc = JsonDocument.Parse(input);
            if (doc.RootElement.ValueKind == JsonValueKind.Object)
            {
                caseId = Str(doc.RootElement, "case_id");
                if (doc.RootElement.TryGetProperty("targets", out var t) && t.ValueKind == JsonValueKind.Array)
                    targets = t.EnumerateArray().Select(x => x.GetString()).ToList();
            }
        }
        catch (JsonException) { }
        return Run(caseId, targets);
    }
}

// Lambda managed runtime (dotnet8 / dotnet10 / container image): handler "probe::Probe.Function::Handler".
// Stream in/out, so no serializer package is needed.
public class Function
{
    public Stream Handler(Stream input, ILambdaContext context) =>
        new MemoryStream(Encoding.UTF8.GetBytes(Core.RunEvent(input)));
}

public static class Program
{
    public static async Task<int> Main(string[] args)
    {
#if PQC_AOT
        if (Environment.GetEnvironmentVariable("AWS_LAMBDA_RUNTIME_API") != null)
        {
            // Native AOT on provided.al2023: this binary is the bootstrap.
            Func<Stream, ILambdaContext, Stream> h = (s, c) => new MemoryStream(Encoding.UTF8.GetBytes(Core.RunEvent(s)));
            using var boot = Amazon.Lambda.RuntimeSupport.LambdaBootstrapBuilder.Create(h).Build();
            await boot.RunAsync();
            return 0;
        }
#endif
        await Task.CompletedTask;
        try
        {
            Console.WriteLine("PQC_RESULT " + Core.Run(args.Length > 0 ? args[0] : null));
            return 0;
        }
        catch (Exception e)
        {
            // Never die with an unhandled exception: on some bases that aborts (exit 133/139) or hangs in createdump
            // instead of exiting, and the runner then waits for the ECS timeout. Print a result the runner can grade.
            var msg = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping.Encode(e.GetType().Name + ": " + e.Message);
            Console.WriteLine("PQC_RESULT {\"case_id\":\"" + Environment.GetEnvironmentVariable("PQC_CASE_ID") +
                              "\",\"lang\":\"dotnet\",\"runtime\":\"" + Environment.Version + "\",\"compute\":\"" + Environment.GetEnvironmentVariable("PQC_COMPUTE") + "\",\"probe_error\":\"" + msg + "\",\"results\":{}}");
            Console.Out.Flush();
            return 2;
        }
    }
}
