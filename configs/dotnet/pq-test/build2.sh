#!/bin/bash
# Build the v2 .NET probes and a private-CA certificate set (EC + RSA server certs, client cert; PFX, PEM, encrypted PEM).
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
W="$(cd "$(dirname "$0")" && pwd)"; LBL=run=pqc-lang2-dotnet
dg() { docker pull -q "$1" >/dev/null 2>&1; docker image inspect --format '{{index .RepoDigests 0}}' "$1"; }
SDK=$(dg mcr.microsoft.com/dotnet/sdk:8.0); TRIXIE=$(dg debian:trixie-slim)
echo "sdk=$SDK"; echo "trixie=$TRIXIE"
mkdir -p "$W/certs"
docker run --rm --label $LBL --name dotnet2-certs -v "$W/certs":/c -w /c "$TRIXIE" sh -ec '
  apt-get update -qq >/dev/null && apt-get install -y -qq openssl >/dev/null 2>&1
  SAN="subjectAltName=DNS:pqsrv,DNS:clsrv,DNS:kestrel,DNS:ec.test,DNS:rsa.test,DNS:localhost"
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 -subj "/CN=PQ Test Private CA" \
    -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign -keyout ca.key -out ca.crt 2>/dev/null
  mk() { # name keyspec cn eku
    openssl req -new -newkey $2 -nodes -subj "/CN=$3" -keyout $1.key -out $1.csr 2>/dev/null
    printf "%s\nextendedKeyUsage=%s\nbasicConstraints=CA:FALSE\n" "$SAN" "$4" > $1.ext
    openssl x509 -req -in $1.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 30 -extfile $1.ext -out $1.crt 2>/dev/null
    cat $1.crt ca.crt > $1-chain.crt
    openssl pkcs12 -export -in $1.crt -inkey $1.key -certfile ca.crt -out $1.pfx -passout pass:changeit
    openssl pkcs8 -topk8 -in $1.key -out $1-enc.key -v2 aes-256-cbc -passout pass:changeit
    rm -f $1.csr $1.ext; }
  mk server-ec "ec -pkeyopt ec_paramgen_curve:P-256" "pq-server-ec" serverAuth
  mk server-rsa "rsa:2048" "pq-server-rsa" serverAuth
  mk client "ec -pkeyopt ec_paramgen_curve:P-256" "pq-client" clientAuth
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 -subj "/CN=Other CA" -keyout other-ca.key -out other-ca.crt 2>/dev/null
  chmod 644 *; ls'
for p in kserver kclient; do
  docker run --rm --label $LBL --name dotnet2-build-$p -v "$W/$p":/src -w /src "$SDK" sh -c "dotnet publish -c Release -o /src/out -v q --nologo >/src/build.log 2>&1 && echo $p-built || (tail -20 /src/build.log; echo $p-FAILED)"
done
