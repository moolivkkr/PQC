#!/bin/sh
# Test PKI for the Python v2 cases (C, D, E). Runs inside an OpenSSL 3.5 container; writes /w2/certs.
#   ca.pem            private root CA (EC P-256)
#   rsa.pem/rsa.key   server cert, RSA 2048 key (PKCS#8, unencrypted)
#   ec.pem/ec.key     server cert, EC P-256 key
#   rsa-enc.key, ec-enc.key   same keys, encrypted (AES-256, passphrase "changeit")
#   b.pem/b.key       second EC server cert for SNI name b.pqsrv
#   client.pem/client.key/client-enc.key   client cert (EC P-256, clientAuth)
#   server.p12        EC server cert + key + CA in PKCS#12, password "changeit"
#   client.p12        client cert + key in PKCS#12, password "changeit"
#   certifi-plus-ca.pem is built later from the certifi bundle in the client container
set -e
C=/w2/certs; mkdir -p $C; cd $C
[ -f ca.pem ] && { echo "certs exist"; exit 0; }
SAN="subjectAltName=DNS:pqsrv,DNS:pyc,DNS:localhost"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 -subj /CN=pq-lang2-ca \
  -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign -keyout ca.key -out ca.pem 2>/dev/null
leaf() {  # name keyspec cn san eku
  openssl req -newkey $2 -nodes -subj /CN=$3 -keyout $1.key -out $1.csr 2>/dev/null
  printf '%s\nbasicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=%s\n' "$4" "$5" > $1.ext
  openssl x509 -req -in $1.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 30 -extfile $1.ext -out $1.pem 2>/dev/null
}
leaf rsa rsa:2048 pqsrv "$SAN" serverAuth
leaf ec "ec -pkeyopt ec_paramgen_curve:P-256" pqsrv "$SAN" serverAuth
leaf b "ec -pkeyopt ec_paramgen_curve:P-256" b.pqsrv "subjectAltName=DNS:b.pqsrv" serverAuth
leaf client "ec -pkeyopt ec_paramgen_curve:P-256" pq-client "subjectAltName=DNS:pq-client" clientAuth
for k in rsa ec client; do openssl pkey -in $k.key -aes256 -passout pass:changeit -out $k-enc.key; done
openssl pkcs12 -export -in ec.pem -inkey ec.key -certfile ca.pem -name pqsrv -passout pass:changeit -out server.p12
openssl pkcs12 -export -in client.pem -inkey client.key -name pq-client -passout pass:changeit -out client.p12
cat rsa.pem ca.pem > rsa-chain.pem
rm -f *.csr *.ext
chmod 644 *
head -1 rsa-enc.key; ls
