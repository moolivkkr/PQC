#!/bin/sh
# Runs inside golang:<v>. Builds probe variants into /out. $1 = toolchain minor (23..27)
set -u
v=$1; out=/out; src=/src
export CGO_ENABLED=0 GOTOOLCHAIN=local GOFLAGS=-mod=mod
b() { # name goline [extra go.mod lines] [go:debug line]
  name=$1; line=$2; extra=${3:-}; dbg=${4:-}
  d=/tmp/$name; rm -rf $d; mkdir -p $d
  printf 'module probe\n\ngo %s\n%s\n' "$line" "$extra" > $d/go.mod
  if [ -n "$dbg" ]; then printf '%s\n' "$dbg" > $d/main.go; cat $src/main.go >> $d/main.go; else cp $src/main.go $d/; fi
  if (cd $d && go build -o $out/$name . 2>/tmp/err); then echo "built $name"; else echo "BUILD-FAIL $name: $(head -c 300 /tmp/err)"; fi
}
b go1.$v-mod1.23 1.23
b go1.$v-mod1.$v 1.$v
if [ $v -ge 24 ]; then
  b go1.$v-mod1.23-godebugdirective 1.23 '' '//go:debug tlsmlkem=1'
  b go1.$v-mod1.23-godebugblock 1.23 'godebug tlsmlkem=1'
  GOFIPS140=latest b go1.$v-mod1.$v-fips-latest 1.$v
  GOFIPS140=v1.0.0 b go1.$v-mod1.$v-fips-v1.0.0 1.$v
fi
if [ $v -ge 26 ]; then
  b go1.$v-mod1.25 1.25
  GOFIPS140=v1.26.0 b go1.$v-mod1.$v-fips-v1.26.0 1.$v
fi
# Go+BoringCrypto (cgo, linux only)
CGO_ENABLED=1 GOEXPERIMENT=boringcrypto b go1.$v-mod1.$v-boring 1.$v
for f in $out/go1.$v-*; do printf '%s: ' "$(basename $f)"; go version -m $f | grep -E 'DefaultGODEBUG|GOFIPS140|GOEXPERIMENT' | tr '\n\t' '  '; echo; done
