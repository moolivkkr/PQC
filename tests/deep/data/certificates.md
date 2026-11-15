# Certificates and signatures (ML-DSA)

## What decides PQ here
Three parties decide whether a handshake uses an ML-DSA certificate. The CA must sign with ML-DSA. The server must hold an ML-DSA certificate and a TLS library that can sign with it (OpenSSL 3.5+). The client must offer ML-DSA in its `signature_algorithms` extension and be able to verify the chain. If the client does not offer ML-DSA, a server holding a second ECDSA certificate falls back to it. That dual-certificate setup is the safe way to start.

## Status matrix

### AWS services
| Service | ML-DSA | Evidence |
|---|---|---|
| AWS Private CA | CA and end-entity certificates: `KeyAlgorithm` and `SigningAlgorithm` `ML_DSA_44`, `ML_DSA_65`, `ML_DSA_87` (same value in both). All commercial, GovCloud and China regions since Nov 2025. | Documented ([algorithms](https://docs.aws.amazon.com/privateca/latest/userguide/PcaWelcome.html#supported-algorithms), [API](https://docs.aws.amazon.com/privateca/latest/APIReference/API_CertificateAuthorityConfiguration.html)) |
| AWS KMS | Signing keys `ML_DSA_44/65/87`, algorithm `ML_DSA_SHAKE_256`; `RAW` messages up to 4 KB, `EXTERNAL_MU` for larger | Documented ([KMS ML-DSA](https://docs.aws.amazon.com/kms/latest/developerguide/mldsa.html)) |
| IAM Roles Anywhere | ML-DSA trust anchors and end-entity certificates (March 2026) | Documented |
| ACM (public certificates); ALB, NLB, CloudFront, API Gateway listeners | RSA and ECDSA only; cannot serve ML-DSA | Claimed (third-party report) |
| ACM private certificates (from Private CA) | ACM supports "some but not all" Private CA algorithms; ML-DSA through ACM not confirmed | Documented (the caveat); ML-DSA Unverified |
| AWS CloudHSM | AWS PQC migration page lists ML-DSA as preview; CloudHSM OpenSSL provider notes say ML-DSA needs OpenSSL 3.5. GA not confirmed. | Unverified |
| Public web PKI and browsers | No public CA issues ML-DSA; browsers don't accept it; Chrome pursues Merkle Tree Certificates | Claimed |

### Clients and runtimes (tested 2026-11-14 against nginx serving ML-DSA + ECDSA)
| Client | TLS: offers ML-DSA, gets | Offline ML-DSA chain verify | Evidence |
|---|---|---|---|
| OpenSSL 3.5.7 `s_client`, curl (Debian 13) | Yes, ML-DSA-44 leaf (`Peer signature type: mldsa44`) | `openssl verify`: OK | Tested |
| OpenSSL 3.5 with `-sigalgs ecdsa_secp256r1_sha256` | No, ECDSA leaf | – | Tested |
| OpenSSL 3.0 (Debian 12) | No, ECDSA leaf | No | Tested |
| Python 3.13 (Debian 13, OpenSSL 3.5.7) | Yes, ML-DSA-44 leaf, verified | (via OpenSSL) | Tested |
| Node 24.22.3 (bundled OpenSSL 3.5.9) | Yes, ML-DSA-44 leaf, `authorized=true` | (via OpenSSL) | Tested |
| .NET 10.0.15 (Alpine 3.24) | Yes, ML-DSA-44 leaf, chain built with custom root | `X509Chain.Build`: true; `MLDsa.IsSupported=True` | Tested |
| Go 1.25.14 | No, ECDSA leaf | No: key parses as unknown algorithm, "signed by unknown authority" | Tested |
| Go 1.27.4 | No, ECDSA leaf (crypto/tls does not offer ML-DSA) | Yes: `x509.Verify` OK | Tested |
| Java 25.0.5 (Temurin, stock JSSE) | No, EC leaf | Yes: PKIX `CertPathValidator` OK | Tested |
| Bouncy Castle JSSE | Not tested | – | Unverified |

Size cost (Tested, DER): ML-DSA-87 root 7,510 bytes, ML-DSA-65 intermediate 6,876, ML-DSA-44 leaf 4,953; ECDSA P-256 root 424, leaf 464. A leaf plus intermediate grows from about 0.9 KB to 11.8 KB. An ML-DSA-44 signature is 2,420 bytes and its public key 1,312 bytes (FIPS 204), against 64 bytes for an ECDSA P-256 signature.

## ML-KEM and ML-DSA compared
| | ML-KEM (key exchange) | ML-DSA (signatures, certificates) |
|---|---|---|
| Threat | Traffic recorded today, decrypted later | Forged certificates once a quantum computer exists |
| Urgency | Now | Later |
| What changes | TLS libraries and config at both ends | The CA, every certificate, every verifier |
| Where it works | Most of this document | Private PKI only |

## Client side (app level)
A client needs two things: the private root in its trust store, and (to get the ML-DSA certificate) a TLS stack that offers ML-DSA. Clients that only meet the first still work against a dual-certificate server; they receive ECDSA.

| Runtime | Trust the private root | Notes |
|---|---|---|
| OpenSSL tools, curl, libpq, Valkey | `--cacert` / `sslrootcert=`; or system store: Debian/Alpine `/usr/local/share/ca-certificates/*.crt` + `update-ca-certificates`; AL2023 `/etc/pki/ca-trust/source/anchors/` + `update-ca-trust` | OpenSSL 3.5 offers `mldsa44/65/87` by default (seen in ClientHello trace, Tested) |
| Python | `ssl.create_default_context(cafile=...)`; `SSL_CERT_FILE`; requests: `REQUESTS_CA_BUNDLE` (certifi has no private roots) | Needs Python linked to OpenSSL 3.5 (see Python tab) |
| Node.js | `tls.connect({ ca })`; `NODE_EXTRA_CA_CERTS=/path/root.pem` | Node 24 bundles OpenSSL 3.5 (Tested) |
| Go | `x509.NewCertPool()` + `AppendCertsFromPEM`; `SSL_CERT_FILE` | Go 1.27 verifies ML-DSA chains; crypto/tls never selects ML-DSA, so the server must also hold ECDSA |
| Java | PKCS12 truststore (`javax.net.ssl.trustStore`) | Stock JDK 25 validates ML-DSA chains but JSSE negotiates ECDSA |
| .NET | `X509ChainPolicy.CustomTrustStore` + `TrustMode = CustomRootTrust`, or the OS store | Linux needs OpenSSL 3.5; macOS has no ML-DSA in .NET 10 (Claimed). Pass server-sent intermediates into `ExtraStore` when you rebuild the chain in a callback (Tested) |

Excerpt (.NET 10 validation callback, Tested):
```csharp
c.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
c.ChainPolicy.CustomTrustStore.AddRange(roots);
foreach (var el in ch!.ChainPolicy.ExtraStore) c.ChainPolicy.ExtraStore.Add(el);
bool ok = c.Build(cert!);
```

## Server side

### nginx: ML-DSA and ECDSA side by side (Tested, nginx 1.29 on OpenSSL 3.5.5)
```nginx
ssl_certificate     /etc/nginx/pki/mldsa-fullchain.crt;
ssl_certificate_key /etc/nginx/pki/mldsa-leaf.key;
ssl_certificate     /etc/nginx/pki/ec-fullchain.crt;
ssl_certificate_key /etc/nginx/pki/ec-leaf.key;
ssl_ecdh_curve      X25519MLKEM768:X25519:prime256v1;
```
OpenSSL picks the certificate by the client's `signature_algorithms`: OpenSSL 3.5, Python, Node and .NET clients got ML-DSA; Go, Java and OpenSSL 3.0 clients got ECDSA, all with `X25519MLKEM768` or `X25519` key exchange. Full server configs for other web servers live in the Web servers and proxies tab.

### Apache httpd, HAProxy, Envoy
Apache accepts several `SSLCertificateFile`/`SSLCertificateKeyFile` pairs and HAProxy loads multi-type bundles, but neither was tested with ML-DSA here (Unverified). Envoy uses BoringSSL; ML-DSA serving not confirmed (Unverified). AWS load balancers cannot serve ML-DSA (see matrix).

### AWS Private CA
CLI flow (Documented values; not run here, no AWS credentials):
```bash
aws acm-pca create-certificate-authority --certificate-authority-type ROOT \
  --certificate-authority-configuration '{"KeyAlgorithm":"ML_DSA_65","SigningAlgorithm":"ML_DSA_65","Subject":{"CommonName":"Example ML-DSA Root"}}'
aws acm-pca get-certificate-authority-csr --certificate-authority-arn $CA --output text > ca.csr
aws acm-pca issue-certificate --certificate-authority-arn $CA --csr fileb://ca.csr \
  --signing-algorithm ML_DSA_65 --template-arn arn:aws:acm-pca:::template/RootCACertificate/V1 \
  --validity Value=10,Type=YEARS
# fetch with get-certificate, then import-certificate-authority-certificate
openssl genpkey -algorithm ML-DSA-44 -out leaf.key
openssl req -new -key leaf.key -subj "/CN=svc.internal" -addext "subjectAltName=DNS:svc.internal" -out leaf.csr
aws acm-pca issue-certificate --certificate-authority-arn $CA --csr fileb://leaf.csr \
  --signing-algorithm ML_DSA_65 --template-arn arn:aws:acm-pca:::template/EndEntityCertificate/V1 \
  --validity Value=90,Type=DAYS
```
Private CA copies the SAN and public key from the CSR without validating them, so build the CSR carefully (Documented). A subordinate CA must use a key algorithm its parent supports (Documented). Terraform and CloudFormation are in Full configuration files; whether your provider version accepts `ML_DSA_*` values is not confirmed (Unverified).

### AWS KMS (ML-DSA signing, not TLS)
```bash
aws kms create-key --key-spec ML_DSA_65 --key-usage SIGN_VERIFY
aws kms sign --key-id $K --message fileb://msg.bin --message-type RAW \
  --signing-algorithm ML_DSA_SHAKE_256 --query Signature --output text | base64 -d > sig.bin
aws kms verify --key-id $K --message fileb://msg.bin --message-type RAW \
  --signing-algorithm ML_DSA_SHAKE_256 --signature fileb://sig.bin
```
Documented. Use it for code and artifact signing, or as a KMS-backed CA key; it does not put ML-DSA into TLS by itself.

### Composite and hybrid certificates
- Composite ML-DSA for X.509 (ML-DSA + RSA/ECDSA in one key and signature) was published as RFC 10073, Proposed Standard, November 2026 (Documented, [datatracker](https://datatracker.ietf.org/doc/draft-ietf-lamps-pq-composite-sigs/)).
- .NET 10 ships a `CompositeMLDsa` API that moved to draft-08 at GA (Documented, [Microsoft Learn](https://learn.microsoft.com/dotnet/core/compatibility/cryptography/10.0/composite-mldsa-draft-08)); check it matches the RFC before use.
- OpenSSL 3.5 composite support: not confirmed (Unverified). AWS Private CA does not list composite algorithms.
- ML-DSA TLS code points (`mldsa44` 0x0904, `mldsa65` 0x0905, `mldsa87` 0x0906) come from draft-ietf-tls-mldsa, still a draft; OpenSSL 3.5 already sends them (Tested).
- Until composites have broad support, dual certificates (ML-DSA + ECDSA) give the same fallback without new formats.

## The CLM product's role
The CLM codebase already has ML-DSA plumbing: certificate policy (`clm/internal/certpolicy/quantumsafe.go`), HSM signing (`clm/internal/hsm/craton_mldsa.go`), the Nitro enclave signer (`nitro-enclave/internal/pqc/signer.go`), and composite and hybrid certificate tests. These were found by file name; the code paths weren't reviewed.

Split of responsibilities:
- **ML-KEM:** discovery plus runtime and config fixes (the rest of this document).
- **ML-DSA:** a CLM re-issuance campaign. Start with internal mutual TLS, service-to-service and code signing; public endpoints wait for the web PKI. CLM should issue the ML-DSA and ECDSA pair together so servers can run dual certificates.

## Packaging per compute type
Each compute type needs the private root in the client's trust store and, on servers, both key pairs.

| Compute | Client trust | Server certificates | Evidence |
|---|---|---|---|
| Lambda zip | Ship `pki/roots.pem` in the package; env `SSL_CERT_FILE=/var/task/pki/roots.pem` (Python, Go), `NODE_EXTRA_CA_CERTS=/var/task/pki/roots.pem` (Node) | n/a | Unverified on Lambda |
| Lambda image | `COPY roots.pem` + same env vars | n/a | Unverified |
| ECS/Fargate, EKS | Base image Debian 13/Alpine 3.24; `COPY` root into `/usr/local/share/ca-certificates/` + `update-ca-certificates` | nginx (Debian 13) with both pairs from Secrets Manager or a mounted secret | Tested (nginx, clients); `update-ca-certificates` with ML-DSA root Unverified |
| EC2 (AL2023) | `/etc/pki/ca-trust/source/anchors/` + `update-ca-trust` | nginx on OpenSSL 3.5 with both pairs | Unverified |

## Verify
```bash
# Which certificate does the server pick? (OpenSSL 3.5 client)
openssl s_client -connect web:443 -CAfile roots.pem -sigalgs mldsa44:mldsa65:mldsa87 </dev/null | grep -E 'Peer signature type|a:PKEY'
openssl s_client -connect web:443 -CAfile roots.pem -sigalgs ecdsa_secp256r1_sha256 </dev/null | grep -E 'Peer signature type|a:PKEY'
# Inventory: signature algorithm of a certificate on disk
openssl x509 -in cert.pem -noout -text | grep -E 'Signature Algorithm|Public Key Algorithm'
```
Expect `Peer signature type: mldsa44` for the first and `ecdsa_secp256r1_sha256` for the second (Tested). Old clients (OpenSSL 3.0, Go, Java) must still complete the handshake (Tested).

## Steps
1. Finish ML-KEM rollout first; it protects against the urgent threat.
2. Inventory certificate signature algorithms in CLM, starting with long-lived roots and intermediates.
3. Build an ML-DSA hierarchy beside the existing one (Private CA or CLM), and distribute the new root to every client trust store.
4. Pilot dual certificates (ML-DSA + ECDSA) on one internal mutual TLS path. Expect OpenSSL 3.5, Python, Node and .NET clients to take ML-DSA, and Go and Java to stay on ECDSA.
5. Expand per path, keeping the ECDSA certificate until every verifier on the path negotiates ML-DSA.
6. Public certificates when CA/Browser Forum rules and browsers allow.

## Pitfalls and rollback
- Never serve only an ML-DSA certificate to a mixed fleet: Go, Java and OpenSSL 3.0 clients cannot negotiate it.
- Chains grow about 13 times (0.9 KB to 11.8 KB). Watch MTU-sensitive paths, middleboxes, IoT devices and client-certificate size limits.
- Each issued certificate has one algorithm. Re-issue rather than re-sign.
- Rollback: remove the ML-DSA `ssl_certificate` pair and reload; ECDSA keeps serving. Keep the ML-DSA root in trust stores; it is harmless when unused.

## Full configuration files

### mkchain.sh (OpenSSL 3.5: ML-DSA and ECDSA chains)
```bash
#!/bin/sh
# mkchain.sh - build an ML-DSA chain (root ML-DSA-87 -> intermediate ML-DSA-65 -> leaf ML-DSA-44)
# and a parallel ECDSA P-256 chain, with OpenSSL 3.5. Tested in postgres:18 (Debian 13, OpenSSL 3.5.7).
set -e
cd /work
openssl version

openssl genpkey -algorithm ML-DSA-87 -out mldsa-root.key
openssl req -x509 -new -key mldsa-root.key -subj "/CN=Example ML-DSA Root CA" -days 3650 \
  -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -out mldsa-root.crt

openssl genpkey -algorithm ML-DSA-65 -out mldsa-int.key
openssl req -new -key mldsa-int.key -subj "/CN=Example ML-DSA Issuing CA" -out mldsa-int.csr
openssl x509 -req -in mldsa-int.csr -CA mldsa-root.crt -CAkey mldsa-root.key -CAcreateserial -days 1825 \
  -extfile ca.ext -extensions v3_int -out mldsa-int.crt

openssl genpkey -algorithm ML-DSA-44 -out mldsa-leaf.key
openssl req -new -key mldsa-leaf.key -subj "/CN=web" -out mldsa-leaf.csr
openssl x509 -req -in mldsa-leaf.csr -CA mldsa-int.crt -CAkey mldsa-int.key -CAcreateserial -days 90 \
  -extfile ca.ext -extensions v3_leaf -out mldsa-leaf.crt
cat mldsa-leaf.crt mldsa-int.crt > mldsa-fullchain.crt

openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out ec-root.key
openssl req -x509 -new -key ec-root.key -subj "/CN=Example ECDSA Root CA" -days 3650 \
  -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" -out ec-root.crt
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out ec-leaf.key
openssl req -new -key ec-leaf.key -subj "/CN=web" -out ec-leaf.csr
openssl x509 -req -in ec-leaf.csr -CA ec-root.crt -CAkey ec-root.key -CAcreateserial -days 90 \
  -extfile ca.ext -extensions v3_leaf -out ec-leaf.crt
cat ec-leaf.crt > ec-fullchain.crt

cat mldsa-root.crt ec-root.crt > roots-both.crt
openssl verify -CAfile mldsa-root.crt -untrusted mldsa-int.crt mldsa-leaf.crt
```

### ca.ext
```ini
# ca.ext - extensions for the intermediate and leaf certificates
[ v3_int ]
basicConstraints       = critical, CA:TRUE, pathlen:0
keyUsage               = critical, keyCertSign, cRLSign
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always

[ v3_leaf ]
basicConstraints       = critical, CA:FALSE
keyUsage               = critical, digitalSignature
extendedKeyUsage       = serverAuth, clientAuth
subjectAltName         = DNS:web, DNS:localhost
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always
```

### nginx dual-certificate server (default.conf)
```nginx
# /etc/nginx/conf.d/default.conf - ML-DSA to clients that offer ML-DSA signature algorithms,
# ECDSA to everyone else. Needs nginx linked to OpenSSL 3.5+. Tested: nginx 1.29 (Debian 13, OpenSSL 3.5.5).
server {
    listen 443 ssl;
    server_name web;

    ssl_certificate     /etc/nginx/pki/mldsa-fullchain.crt;
    ssl_certificate_key /etc/nginx/pki/mldsa-leaf.key;
    ssl_certificate     /etc/nginx/pki/ec-fullchain.crt;
    ssl_certificate_key /etc/nginx/pki/ec-leaf.key;

    ssl_protocols   TLSv1.3 TLSv1.2;
    ssl_ecdh_curve  X25519MLKEM768:X25519:prime256v1;

    location / {
        return 200 "ok $ssl_protocol $ssl_curve\n";
    }
}
```

### Apache httpd vhost (Unverified with ML-DSA)
```apache
# /etc/apache2/sites-available/web-ssl.conf - same dual-certificate idea; not tested with ML-DSA
<VirtualHost *:443>
    ServerName web
    SSLEngine on
    SSLProtocol -all +TLSv1.3 +TLSv1.2
    SSLOpenSSLConfCmd Groups X25519MLKEM768:X25519:prime256v1
    SSLCertificateFile    /etc/apache2/pki/mldsa-fullchain.crt
    SSLCertificateKeyFile /etc/apache2/pki/mldsa-leaf.key
    SSLCertificateFile    /etc/apache2/pki/ec-fullchain.crt
    SSLCertificateKeyFile /etc/apache2/pki/ec-leaf.key
</VirtualHost>
```

### private-ca-mldsa.tf (Terraform; ML_DSA acceptance by provider Unverified)
```hcl
# private-ca-mldsa.tf - ML-DSA-65 root CA in AWS Private CA, self-signed and activated
resource "aws_acmpca_certificate_authority" "mldsa_root" {
  type = "ROOT"

  certificate_authority_configuration {
    key_algorithm     = "ML_DSA_65"
    signing_algorithm = "ML_DSA_65"
    subject {
      common_name  = "Example ML-DSA Root"
      organization = "Example"
    }
  }

  permanent_deletion_time_in_days = 7
}

resource "aws_acmpca_certificate" "mldsa_root" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.mldsa_root.arn
  certificate_signing_request = aws_acmpca_certificate_authority.mldsa_root.certificate_signing_request
  signing_algorithm           = "ML_DSA_65"
  template_arn                = "arn:aws:acm-pca:::template/RootCACertificate/V1"

  validity {
    type  = "YEARS"
    value = 10
  }
}

resource "aws_acmpca_certificate_authority_certificate" "mldsa_root" {
  certificate_authority_arn = aws_acmpca_certificate_authority.mldsa_root.arn
  certificate               = aws_acmpca_certificate.mldsa_root.certificate
  certificate_chain         = aws_acmpca_certificate.mldsa_root.certificate_chain
}

# End-entity certificate from a CSR made with: openssl genpkey -algorithm ML-DSA-44
resource "aws_acmpca_certificate" "svc" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.mldsa_root.arn
  certificate_signing_request = file("${path.module}/leaf.csr")
  signing_algorithm           = "ML_DSA_65"
  template_arn                = "arn:aws:acm-pca:::template/EndEntityCertificate/V1"

  validity {
    type  = "DAYS"
    value = 90
  }

  depends_on = [aws_acmpca_certificate_authority_certificate.mldsa_root]
}

resource "aws_kms_key" "mldsa_signing" {
  description              = "ML-DSA-65 signing key"
  customer_master_key_spec = "ML_DSA_65"
  key_usage                = "SIGN_VERIFY"
  deletion_window_in_days  = 7
}
```

### private-ca-mldsa.yaml (CloudFormation; ML_DSA acceptance by the resource schema Unverified)
```yaml
# private-ca-mldsa.yaml - ML-DSA-65 root CA, its certificate, activation, and a KMS ML-DSA key
AWSTemplateFormatVersion: "2010-09-09"
Resources:
  MlDsaRootCA:
    Type: AWS::ACMPCA::CertificateAuthority
    Properties:
      Type: ROOT
      KeyAlgorithm: ML_DSA_65
      SigningAlgorithm: ML_DSA_65
      Subject:
        CommonName: Example ML-DSA Root
        Organization: Example
  MlDsaRootCert:
    Type: AWS::ACMPCA::Certificate
    Properties:
      CertificateAuthorityArn: !Ref MlDsaRootCA
      CertificateSigningRequest: !GetAtt MlDsaRootCA.CertificateSigningRequest
      SigningAlgorithm: ML_DSA_65
      TemplateArn: arn:aws:acm-pca:::template/RootCACertificate/V1
      Validity:
        Type: YEARS
        Value: 10
  MlDsaRootActivation:
    Type: AWS::ACMPCA::CertificateAuthorityActivation
    Properties:
      CertificateAuthorityArn: !Ref MlDsaRootCA
      Certificate: !GetAtt MlDsaRootCert.Certificate
      Status: ACTIVE
  MlDsaSigningKey:
    Type: AWS::KMS::Key
    Properties:
      Description: ML-DSA-65 signing key
      KeySpec: ML_DSA_65
      KeyUsage: SIGN_VERIFY
      KeyPolicy:
        Version: "2012-10-17"
        Statement:
          - Sid: AccountAdmin
            Effect: Allow
            Principal: { AWS: !Sub "arn:aws:iam::${AWS::AccountId}:root" }
            Action: "kms:*"
            Resource: "*"
Outputs:
  CaArn:
    Value: !Ref MlDsaRootCA
```

### Dockerfile (client trust store, Debian 13)
```dockerfile
# Dockerfile - add the private ML-DSA and ECDSA roots to the system trust store
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates openssl \
    && rm -rf /var/lib/apt/lists/*
COPY pki/mldsa-root.crt /usr/local/share/ca-certificates/example-mldsa-root.crt
COPY pki/ec-root.crt    /usr/local/share/ca-certificates/example-ecdsa-root.crt
RUN update-ca-certificates
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/example-mldsa-root.crt
```

### Lambda environment (SAM excerpt)
```yaml
# template.yaml (excerpt) - private roots shipped in the function package under pki/
  Function:
    Type: AWS::Serverless::Function
    Properties:
      Environment:
        Variables:
          SSL_CERT_FILE: /var/task/pki/roots.pem          # Python, Go
          NODE_EXTRA_CA_CERTS: /var/task/pki/roots.pem    # Node.js
```

### Test kit (this tab's evidence)
`certs/mkchain.sh`, `certs/ca.ext`, `certs/nginx-dualcert.conf`, clients `certs/goclient/main.go`, `certs/pyclient.py`, `certs/VerifyChain.java`, `certs/nodeclient.js`, `certs/dotnet/Program.cs`; runners `run-certs.sh`, `run-certs2.sh`, `run-dotnet.sh`; outputs `certs*-results.txt`, `dotnet-results.txt` in the deep/data work directory.
