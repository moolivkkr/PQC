#!/bin/bash
# Assemble 06-java.md from the v2 draft (D) and the old tab export (O). Edits inside moved blocks are applied afterwards.
set -euo pipefail
S=/private/tmp/claude-501/-Users-kishoremooli-development-cybersecurity/21fa377a-bc06-46f9-9e49-4588545ba6c2/scratchpad
D=$S/deep/java/v2/Java-v2.md
O=$S/export/md-old/Java.md
M=$S/deep/java/merge
OUT=/Users/kishoremooli/development/pqc/src/06-java.md
d() { sed -n "$1,$2p" "$D"; }
o() { sed -n "$1,$2p" "$O"; }
h4() { sed 's/^### /#### /'; }
{
printf '# Java\n\n'
d 13 19; cat "$M/p1.md"
d 21 32
printf '### By JDK and compute type\n\n'
printf '%s Kit = agent v2 + pq-tls.security; v1 rows were tested with the v1 agent.\n\n' "$(o 21 21)"
o 25 31; echo
printf '### Decision guide\n\n'
d 37 42
d 43 56
printf '#### By library (client side)\n\n'; o 35 47; echo
printf '#### Client libraries\n\n'; o 64 85; echo
d 60 69
printf '#### By server (server side)\n\n'; o 51 60; echo
printf '#### Front door and order of preference\n\n'; o 135 145; echo
o 147 202 | h4; echo
d 74 204
o 87 131 | h4; echo
d 207 230
printf 'Netty server code: see "Netty server (gRPC-Java, Reactor Netty, Vert.x)" under case B.\n\n'
d 233 266
o 216 228; echo
d 269 290
printf 'More signals:\n\n'
o 240 240 | sed 's/^5\.  /- /'
o 242 242 | sed 's/^6\.  /- /'
printf -- '- **nginx as the PQ-only test server.** `ssl_ecdh_curve X25519MLKEM768;` makes nginx PQ-only, and `$ssl_curve` in `log_format` logs the negotiated group.\n\n'
d 293 300
o 245 249; o 251 262; echo
d 303 305
printf '\nThe test scripts and raw output behind every "Tested" label are in the work folder `deep/java/` (`run-clients.sh`, `run-servers.sh`, `run-aws.sh`, `run-static-pg.sh`, `out/*.txt`) and, for kit v2, `deep/java/v2/` (`run-v2.sh`, `run-tomcat-sb.sh`, `out/*.txt`).\n'
d 306 457
printf '### Dependencies\n\n'; o 323 405; echo
d 460 485
o 431 431; echo
d 488 489
o 435 455; echo
printf 'SSL bundles call `KeyManagerFactory.getDefaultAlgorithm()` and `TrustManagerFactory.getDefaultAlgorithm()` (Spring Boot 3.5.16, checked with javap). An EC PKCS#12 bundle negotiated X25519MLKEM768 on JDK 21 + kit v2 (Tested, `v2/out/tomcat-sb.txt`).\n\n'
o 457 479; echo
d 492 493
o 483 496; echo
d 496 506
o 509 551; echo
d 509 679
o 656 664; echo
d 682 876
echo; o 856 856
d 877 1186
} > "$OUT"
wc -l "$OUT"
