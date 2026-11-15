# Go: prebuilt probes are in /opt/pqc/go/bin (one per toolchain / go line / FIPS mode, built by build/go.sh).
# One more probe is compiled here with the distro toolchain (yum golang), offline from vendored modules.
cd /opt/pqc/go/src
GOTOOLCHAIN=local GOFLAGS=-mod=vendor GOPROXY=off CGO_ENABLED=0 GOCACHE=/tmp/gocache \
  go build -trimpath -tags lambda.norpc -ldflags "-X main.goLine=1.26" -o /opt/pqc/go/bin/probe-distro .
rm -rf /tmp/gocache
go version -m /opt/pqc/go/bin/probe-distro | head -1
