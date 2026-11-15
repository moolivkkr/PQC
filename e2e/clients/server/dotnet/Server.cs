// Load balancer target probe - .NET: SslStream.AuthenticateAsServerAsync with default options (what Kestrel calls).
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

static string Env(string k, string d) { var v = Environment.GetEnvironmentVariable(k); return string.IsNullOrEmpty(v) ? d : v; }

var caseId = Env("PQC_CASE_ID", "adhoc"); var obs = Env("PQC_OBSERVER", "pq-observer");
var port = int.Parse(Env("PQC_SERVER_PORT", "9443"));
var dir = AppContext.BaseDirectory;
var pem = X509Certificate2.CreateFromPemFile(Path.Combine(dir, "server-rsa.crt"), Path.Combine(dir, "server-rsa.key"));
#pragma warning disable SYSLIB0057
var cert = new X509Certificate2(pem.Export(X509ContentType.Pkcs12));
#pragma warning restore SYSLIB0057
var listener = new TcpListener(IPAddress.Any, port);
listener.Start();
_ = Task.Run(async () => {
    while (true) {
        var c = await listener.AcceptTcpClientAsync();
        _ = Task.Run(async () => {
            try {
                using (c) using (var ssl = new SslStream(c.GetStream())) {
                    await ssl.AuthenticateAsServerAsync(cert);
                    var buf = new byte[4096]; await ssl.ReadAsync(buf);
                    var body = "{\"ok\":true,\"server\":\"dotnet\"}";
                    var resp = $"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {body.Length}\r\nConnection: close\r\n\r\n{body}";
                    await ssl.WriteAsync(Encoding.ASCII.GetBytes(resp));
                }
            } catch (Exception e) { Console.Error.WriteLine("server: " + e.Message); }
        });
    }
});
var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
var results = new JsonObject();
var rt = Environment.Version.ToString(); var compute = Env("PQC_COMPUTE", "unknown"); var mode = Env("PQC_MODE", "baseline");
foreach (var t in Env("PQC_TARGETS", "alb-pq,alb-classic").Split(',', StringSplitOptions.RemoveEmptyEntries)) {
    JsonObject res;
    try { res = JsonNode.Parse(await http.GetStringAsync($"http://{obs}:8080/dialback?id={caseId}&port={port}&policy={t}"))!.AsObject(); }
    catch (Exception e) { res = new JsonObject { ["ok"] = false, ["error"] = e.GetType().Name + ": " + e.Message }; }
    var ok = res["ok"]?.GetValue<bool>() ?? false; var pq = res["pq"]?.GetValue<bool>() ?? false;
    res["pq_status"] = !ok ? "failed" : pq ? "pq" : "classical";
    var line = new JsonObject { ["event"] = "tls_handshake", ["role"] = "server", ["case_id"] = caseId, ["lang"] = "dotnet",
        ["runtime"] = rt, ["compute"] = compute, ["mode"] = mode, ["target"] = t };
    foreach (var kv in res) line[kv.Key] = kv.Value?.DeepClone();
    Console.WriteLine(line.ToJsonString());
    results[t] = res;
}
var outObj = new JsonObject { ["case_id"] = caseId, ["lang"] = "dotnet", ["role"] = "server", ["runtime"] = rt,
    ["tls_lib"] = "SslStream/OpenSSL", ["compute"] = compute, ["mode"] = mode, ["results"] = results };
Console.WriteLine("PQC_RESULT " + outObj.ToJsonString());
listener.Stop();
return 0;
