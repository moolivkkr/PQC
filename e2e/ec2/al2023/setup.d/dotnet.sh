# .NET: both dnf runtimes present and the probe files in place (no PQ setting here: cases choose baseline/conf/policy)
dotnet --list-runtimes
test -f /opt/pqc/dotnet/net8/probe.dll -a -f /opt/pqc/dotnet/net10/probe.dll -a -f /opt/pqc/dotnet/pq-tls/openssl-pq.cnf
