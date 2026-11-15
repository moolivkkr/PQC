#!/bin/sh
# Runs inside debian:trixie-slim on the test network. Executes every probe binary with config variants.
cd /bin-probes
for f in go1.*; do
  case $f in
    *-fips-*|*-boring) CFG=default ./$f; CFG=default GODEBUG=fips140=only ./$f 2>&1 | tail -c 400 ;;
    *-mod1.23*|*-mod1.25) CFG=default ./$f ;;
    *) for c in default classical-curves pq-curves http; do CFG=$c ./$f; done ;;
  esac
done
# GODEBUG overrides at run time (no rebuild)
for f in go1.24-mod1.23 go1.25-mod1.23 go1.26-mod1.23 go1.27-mod1.23; do CFG=default GODEBUG=tlsmlkem=1 ./$f; CFG=default GODEBUG=tlsmlkem=1,tlssecpmlkem=1 ./$f; done
for f in go1.24-mod1.24 go1.25-mod1.25 go1.26-mod1.26 go1.27-mod1.27; do CFG=default GODEBUG=tlsmlkem=0 ./$f; CFG=pq-curves GODEBUG=tlsmlkem=0 ./$f; CFG=default GODEBUG=fips140=on ./$f; done
