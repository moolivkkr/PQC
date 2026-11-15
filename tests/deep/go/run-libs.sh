#!/bin/sh
# Runs inside debian:trixie-slim on pqnet-go with /b = bin dir.
echo "== gRPC client (default creds) -> Go gRPC server PQ-only :9447 and default :9446"
/b/srv grpcclient gosrv:9447
/b/srv grpcclient gosrv:9446
echo "== libraries, Go 1.26.11, go.mod go 1.26"
/b/libs
echo "== libraries with GODEBUG=fips140=on"
GODEBUG=fips140=on /b/libs 2>&1 | grep aws-sdk; sleep 1
echo "== error texts and MLKEM1024"
for v in 1.25 1.26 1.27; do /b/extra-$v; GODEBUG=fips140=only /b/extra-$v; MODE=mlkem1024 /b/extra-$v; done
echo "== Go+BoringCrypto with crypto/tls/fipsonly"
for v in 1.25 1.26 1.27; do /b/extra-fipsonly-boring-$v; done
