// Kestrel HTTPS server. The endpoint, certificate and TLS protocols come from appsettings.json.
// Kestrel has no key-exchange-group setting: the OS TLS library (OpenSSL on Linux, Schannel on Windows) picks the group.
using Microsoft.AspNetCore.Connections.Features;
using Microsoft.AspNetCore.Server.Kestrel.Https;

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.ConfigureKestrel(kestrel =>
{
    kestrel.ConfigureHttpsDefaults(https =>
    {
        // Leave SslProtocols at None (OS default) or include Tls13. Tls12 alone disables PQ key exchange.
        https.SslProtocols = System.Security.Authentication.SslProtocols.None;
    });
});

var app = builder.Build();

app.MapGet("/", (HttpContext ctx) =>
{
    var tls = ctx.Features.Get<ITlsHandshakeFeature>();
    return $"ok protocol={tls?.Protocol} cipher={tls?.NegotiatedCipherSuite}\n";
});

app.Run();
