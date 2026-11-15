using System.Net.Security; using System.Net.Sockets;
string Try(int port) { try { using var c = new TcpClient("pqsrv", port); using var s = new SslStream(c.GetStream(), false, (a,b,d,e) => true);
  s.AuthenticateAsClient("pqsrv"); return "OK " + s.SslProtocol; } catch (Exception e) { return "FAIL " + (e.InnerException?.GetType().Name ?? e.GetType().Name); } }
Console.WriteLine($"{{\"dotnet\":\"{Environment.Version}\",\"pq_only\":\"{Try(8443)}\",\"classical_only\":\"{Try(8444)}\"}}");
