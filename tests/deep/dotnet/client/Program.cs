// PQ TLS client probe: SslStream and HttpClient (SocketsHttpHandler) against a PQ-only (8443) and a classical-only (8444) server.
using System.Net.Security;
using System.Net.Sockets;

string host = Environment.GetEnvironmentVariable("PQ_HOST") ?? "pqsrv";

string TryStream(int port)
{
    try
    {
        using var c = new TcpClient(host, port);
        using var s = new SslStream(c.GetStream(), false, (a, b, d, e) => true);
        s.AuthenticateAsClient(new SslClientAuthenticationOptions { TargetHost = host });
        return "OK " + s.SslProtocol;
    }
    catch (Exception e) { return "FAIL " + (e.InnerException?.GetType().Name ?? e.GetType().Name); }
}

string TryHttp(int port)
{
    try
    {
        var h = new SocketsHttpHandler();
        h.SslOptions.RemoteCertificateValidationCallback = (a, b, d, e) => true; // test only
        using var http = new HttpClient(h) { Timeout = TimeSpan.FromSeconds(10) };
        var r = http.GetAsync($"https://{host}:{port}/").GetAwaiter().GetResult();
        return "OK HTTP " + (int)r.StatusCode;
    }
    catch (Exception e)
    {
        var inner = e; while (inner.InnerException != null) inner = inner.InnerException;
        return "FAIL " + inner.GetType().Name;
    }
}

Console.WriteLine($"{{\"dotnet\":\"{Environment.Version}\",\"sslstream_pq_only\":\"{TryStream(8443)}\",\"sslstream_classical_only\":\"{TryStream(8444)}\",\"httpclient_pq_only\":\"{TryHttp(8443)}\",\"httpclient_classical_only\":\"{TryHttp(8444)}\"}}");
