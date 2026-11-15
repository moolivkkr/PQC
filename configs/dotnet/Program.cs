// Kestrel HTTPS server. Endpoint, certificate and TLS protocols come from appsettings.json.
// Kestrel has no key-exchange-group setting: OpenSSL (Linux) or Schannel (Windows) picks the group.
using Microsoft.AspNetCore.Connections.Features;

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.ConfigureKestrel(kestrel =>
{
    kestrel.ConfigureHttpsDefaults(https =>
    {
        // None = OS default (TLS 1.2 + 1.3). Never Tls12 alone: that disables PQ key exchange.
        https.SslProtocols = System.Security.Authentication.SslProtocols.None;
    });
});

var app = builder.Build();

app.MapGet("/", (HttpContext ctx) =>
{
    var tls = ctx.Features.Get<ITlsHandshakeFeature>();
    // .NET does not expose the negotiated group; log protocol and cipher only.
    return $"ok protocol={tls?.Protocol} cipher={tls?.NegotiatedCipherSuite}\n";
});

app.Run();
