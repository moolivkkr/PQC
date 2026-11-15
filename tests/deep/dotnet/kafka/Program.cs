// Confluent.Kafka (librdkafka) TLS handshake probe. The "broker" is an openssl s_server, so only the TLS
// handshake result matters: librdkafka logs "SSL handshake failed" or moves on to the Kafka protocol.
using Confluent.Kafka;

string port = args.Length > 0 ? args[0] : "8443";
var cfg = new AdminClientConfig
{
    BootstrapServers = $"pqsrv:{port}",
    SecurityProtocol = SecurityProtocol.Ssl,
    EnableSslCertificateVerification = false, // test only
    Debug = "security,broker",
    SocketTimeoutMs = 4000,
};
var curves = Environment.GetEnvironmentVariable("KAFKA_CURVES");
if (!string.IsNullOrEmpty(curves)) cfg.Set("ssl.curves.list", curves);

Console.WriteLine($"librdkafka {Library.VersionString} curves={curves ?? "(default)"} port={port}");
using var admin = new AdminClientBuilder(cfg)
    .SetLogHandler((_, m) =>
    {
        var t = m.Message;
        if (t.Contains("SSL") || t.Contains("ssl") || t.Contains("handshake") || t.Contains("OpenSSL"))
            Console.WriteLine("LOG " + t);
    })
    .Build();
try { admin.GetMetadata(TimeSpan.FromSeconds(6)); } catch (Exception e) { Console.WriteLine("metadata: " + e.Message); }
