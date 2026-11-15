#!/bin/sh
# Runs INSIDE a .NET runtime container. Cases D (trust), E (client certs), F (TLS settings) against:
#   pqsrv:8443 PQ-only  | clsrv:8444 classical-only  (server cert signed by the private CA)
#   pqsrv:8445 PQ-only + client cert required | clsrv:8446 classical-only + client cert required
C="dotnet /w/kclient/out/kclient.dll"
PQ=https://pqsrv:8443/; CL=https://clsrv:8444/; PQM=https://pqsrv:8445/; CLM=https://clsrv:8446/
export CA_FILE=/certs/ca.crt CLIENT_PFX=/certs/client.pfx CLIENT_CRT=/certs/client.crt CLIENT_KEY=/certs/client.key
echo "D0 no private CA anywhere (expect FAIL on both)"; $C system $PQ $CL
echo "D1 SSL_CERT_FILE=/certs/ca.crt";                  SSL_CERT_FILE=/certs/ca.crt $C system $PQ $CL
echo "D2 SSL_CERT_DIR=/certs/hashdir (openssl rehash)";  SSL_CERT_DIR=/certs/hashdir $C system $PQ $CL
echo "D3 ServerCertificateCustomValidationCallback";    $C callback $PQ $CL
echo "D4 X509ChainPolicy.CustomTrustStore";             $C chainpolicy $PQ $CL
echo "D5 private CA added to the system store"
if [ -d /etc/pki/ca-trust/source/anchors ]; then cp /certs/ca.crt /etc/pki/ca-trust/source/anchors/pq-ca.crt && update-ca-trust && echo "  (update-ca-trust)"
else
  command -v update-ca-certificates >/dev/null || apk add -q ca-certificates >/dev/null 2>&1
  cp /certs/ca.crt /usr/local/share/ca-certificates/pq-ca.crt && update-ca-certificates >/dev/null 2>&1 && echo "  (update-ca-certificates)"
fi
$C system $PQ $CL
echo "E0 server requires a client cert, client sends none (expect FAIL)"; $C system $PQM $CLM
echo "E1 HttpClientHandler.ClientCertificates (PFX)";       $C mtls-handler $PQM $CLM
echo "E2 SocketsHttpHandler.SslOptions.ClientCertificates (PEM pair)"; $C mtls-sockets $PQM $CLM
echo "E3 client cert from X509Store CurrentUser/My";        $C mtls-store $PQM $CLM
echo "F1 EnabledSslProtocols=Tls12 (expect PQ-only FAIL)";  $C tls12 $PQ $CL
echo "F2 CipherSuitesPolicy = TLS 1.3 AES-GCM only";        $C ciphers13 $PQ $CL
