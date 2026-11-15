#!/bin/sh
# Assemble the final standalone Go markdown from the v2 draft (D) and the old tab (O).
set -eu
B=/private/tmp/claude-501/-Users-kishoremooli-development-cybersecurity/21fa377a-bc06-46f9-9e49-4588545ba6c2/scratchpad
D=$B/deep/go/v2/go-v2.md
O=$B/export/md-old/Go.md
V=$B/deep/go/v2
OUT=/Users/kishoremooli/development/pqc/src/03-go.md
d() { sed -n "$1,$2p" "$D"; }
# Old-tab cross references are doc-internal spans; keep the page name as plain text.
o() { sed -n "$1,$2p" "$O" | sed -E 's#<span atom="ref" ref="[^"]*">([^<]*)</span>#\1#g'; }
code() { printf '\n`%s` (%s)\n\n```%s\n' "$1" "$2" "$3"; cat "$4"; printf '```\n'; }

{
printf '# Go\n\n'
d 4 31
printf '\n### Detail: toolchain and go line\n\n'
o 11 26
printf '\n'
o 30 36
printf '\n'
o 147 159
printf '\n'
d 34 45
printf '\n'
o 40 67
printf '\n'
d 48 54
printf '\n'
o 105 111
# Default-server paragraph: the draft (case B) now has the server side tested.
o 112 112 | sed 's/server side not separately tested/server side Tested, see "What happens today" above/'
o 113 118
printf '\n'
d 58 268
printf '\n'
o 120 125
printf '\n'
d 272 280
printf '\n'
o 161 171
printf '\n'
d 284 301
printf '\n'
o 69 101
printf '\n'
d 305 322
printf '\n'
o 134 143
printf '\n'
d 326 331
printf '\n### Packaging per compute type\n\n'
o 177 195
printf '\n'
d 335 347
printf '\n### Details for the steps\n\n'
o 199 239 | sed -E 's/^\*\*[1-4]\. /**/'
o 240 240 | sed -e 's/(see Server side)/(see below)/' -e 's/^\*\*4\. /**/'
printf '\n'
o 127 132
printf '\n## Pitfalls and rollback\n\n'
o 244 254
printf '\n'
d 353 357 | sed 's/^- /\n- /' | sed '1{/^$/d;}'
printf '\n'
o 256 264
printf '\n'
o 266 720
printf '\n### Test harness and CI files added in this pass\n\nThese files produced the case C to I results above (outputs `run-v2.out`, `run-v2b.out`, `run-v2c.out`). They run in containers with the certificates under `/certs`.\n'
code go-pq-lint.sh "CI check: source, go.mod and IaC settings that block PQ" sh "$V/go-pq-lint.sh"
code gen-certs.sh "test PKI: private CA, RSA and EC server certs, SNI certs, client certs, encrypted keys, PKCS#12" sh "$V/gen-certs.sh"
code pq-servers.sh "the four OpenSSL 3.5 test servers" sh "$V/pq-servers.sh"
code cases/main.go "cases C, D, E, F, standard library only; build with a go.mod of \`module cases\` and the \`go\` line under test" go "$V/cases/main.go"
code cases/casei.go "case I: pinning and an opaque crypto.Signer key" go "$V/cases/casei.go"
code cases/curve_new.go "group name on Go 1.25+" go "$V/cases/curve_new.go"
code cases/curve_old.go "fallback for Go 1.23 and 1.24" go "$V/cases/curve_old.go"
code deps/go.mod "versions resolved for the library tests" text "$V/bin/deps-go.mod"
code deps/main.go "cases C (PKCS#12, encrypted PKCS#8) and H (AWS SDK, gRPC, pgx)" go "$V/deps/main.go"
} > "$OUT"
wc -l "$OUT"
