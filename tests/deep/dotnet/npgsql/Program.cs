// Npgsql TLS probe against PostgreSQL 18 started with ssl_groups = 'X25519MLKEM768' (PQ-only key exchange).
using Npgsql;

var cs = Environment.GetEnvironmentVariable("PG_CS") ?? "Host=pg;Username=postgres;Password=pqtest;SSL Mode=Require;Timeout=8";
try
{
    await using var conn = new NpgsqlConnection(cs);
    await conn.OpenAsync();
    await using var cmd = new NpgsqlCommand("select version, cipher from pg_stat_ssl where pid = pg_backend_pid()", conn);
    await using var r = await cmd.ExecuteReaderAsync();
    await r.ReadAsync();
    Console.WriteLine($"npgsql OK {r.GetString(0)} {r.GetString(1)} (dotnet {Environment.Version})");
}
catch (Exception e)
{
    var inner = e; while (inner.InnerException != null) inner = inner.InnerException;
    Console.WriteLine($"npgsql FAIL {inner.GetType().Name}: {inner.Message} (dotnet {Environment.Version})");
}
