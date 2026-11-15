#!/bin/sh
# CI guardrail: fail the build on .NET settings that block hybrid post-quantum key exchange.
# usage: sh check-dotnet-pq.sh [repo-root]   (exit 1 = blocking finding; warnings never fail)
ROOT="${1:-.}"; FAIL=0
hit() { # level pattern description [exclude-pattern]
  out=$(grep -rnE --include='*.cs' --include='*.json' --include='*.config' --include='*.xml' \
        --include='*.csproj' --include='*.props' --include='Dockerfile*' --include='*.yaml' --include='*.yml' --include='*.tf' \
        --exclude-dir=bin --exclude-dir=obj --exclude-dir=node_modules --exclude-dir=.git "$2" "$ROOT" 2>/dev/null | grep -vE "${4:-^$}" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//')
  [ -z "$out" ] && return
  echo "$1: $3"; echo "$out" | sed 's/^/    /' | head -20
  [ "$1" = BLOCK ] && FAIL=1
}
# 1. TLS 1.2 pinned without 1.3 (code, appsettings, connection strings)
hit BLOCK 'SslProtocols\.(Tls12|Tls11|Tls)([^0-9]|$)' "SslProtocols pinned to TLS 1.2 or lower (PQ needs TLS 1.3): use SslProtocols.None" 'Tls13' 
hit BLOCK '"SslProtocols"[[:space:]]*:[[:space:]]*\[' "appsettings SslProtocols without Tls13: add Tls13 or remove the key" 'Tls13' 
hit BLOCK '(TlsVersion|Tls Version)[[:space:]]*=[[:space:]]*"?(TLS ?1\.2|Tls12)"?[;"]' "MySqlConnector TlsVersion pinned to 1.2"
hit BLOCK 'ServicePointManager\.SecurityProtocol[[:space:]]*=' "ServicePointManager.SecurityProtocol set without Tls13" 'Tls13|SystemDefault' 
# 2. Base images that ship OpenSSL < 3.5 (no ML-KEM)
hit BLOCK 'FROM[[:space:]]+mcr\.microsoft\.com/dotnet/(aspnet|runtime|runtime-deps|sdk):[0-9.]+([[:space:]]|$|@)|FROM[[:space:]]+mcr\.microsoft\.com/dotnet/[a-z-]+:[0-9.]+-(noble|jammy|bookworm-slim|azurelinux3\.0)' "base image with OpenSSL < 3.5: use -alpine, -resolute or AL2023 + OPENSSL_CONF"
# 3. Settings that need review (warn only)
hit WARN 'CipherSuitesPolicy' "CipherSuitesPolicy set: keep TLS 1.3 suites in it; NotSupportedException on Windows"
hit WARN 'ssl\.curves\.list|ssl\.groups' "librdkafka group list set: X25519MLKEM768 must be in it"
hit WARN 'Grpc\.Core"' "Grpc.Core (C-core, own TLS stack): migrate to Grpc.Net.Client"
hit WARN 'OPENSSL_CONF' "OPENSSL_CONF set: on AL2023 it must point at a file that keeps X25519MLKEM768 in Groups"
hit WARN 'RemoteCertificateValidationCallback[[:space:]]*=[[:space:]]*\([^)]*\)[[:space:]]*=>[[:space:]]*true|ServerCertificateCustomValidationCallback[[:space:]]*=[[:space:]]*HttpClientHandler\.DangerousAcceptAnyServerCertificateValidator' "certificate validation disabled (not a PQ blocker, but fix it)"
[ $FAIL = 1 ] && echo "PQ check: FAILED" || echo "PQ check: passed"
exit $FAIL
