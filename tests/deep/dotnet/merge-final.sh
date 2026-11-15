#!/bin/bash
# Assemble the final .NET tab from the v2 draft (V) and the old tab export (O) by line ranges.
set -e
S=/private/tmp/claude-501/-Users-kishoremooli-development-cybersecurity/21fa377a-bc06-46f9-9e49-4588545ba6c2/scratchpad
V=$S/deep/dotnet/v2/dotnet-v2.md
O="$S/export/md-old/.NET.md"
OUT=/Users/kishoremooli/development/pqc/src/07-dotnet.md
v() { sed -n "$1,$2p" "$V"; }
o() { sed -n "$1,$2p" "$O"; }
oi() { sed -n "$1,$2p" "$O" | sed 's/^\(.\)/    \1/'; }   # indent non-empty lines (nest under a list item)
{
echo "# .NET"; echo
# 1. Problem statement + moved "What decides PQ here" (old 5-13)
v 14 21; echo "**What decides PQ here**"; echo; o 5 14
# 2. Versions table, moved status-matrix blocks (old 17-47), decision guide
v 25 35; echo; o 17 48; v 39 47
# 3. Cases: intro + A, moved client blocks (old 51-76)
v 48 60; o 51 77
# B + moved server table, Kestrel excerpt, Tls12 note (old 91-114); Load balancers ref made plain text
v 64 70; o 91 115 | sed 's#<span atom="ref" ref="file/bb21387b-4f66">Load balancers</span>#the Load balancers tab#'
# C to H intro
v 74 264
# H: moved Kafka excerpt + 2 bullets (old 78-87), then draft bullets
o 78 88; v 268 288
# J: moved Windows paragraph, PowerShell, 3 bullets (old 116-128), nested under the Windows bullet
oi 116 128; echo; v 292 298
# Solution step 2: moved packaging list + pointer (old 132-144), nested under step 2
oi 132 144; echo; v 302 328
# How to test: moved Verify bullets (old 148-158)
echo "**Reference checks**"; echo; o 148 159
# Pitfalls: old 162-176, then draft additions
v 332 333; o 162 176; v 336 345
# Full configuration files: old 180-693, then draft additions (skip the APPENDED comment)
o 180 693; echo; v 350 351; v 354 793
} | grep -v 'Lands in the zip root as pq-tls/openssl-pq.cnf' > "$OUT"
wc -l "$OUT"
