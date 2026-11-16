#!/usr/bin/env bash
# Builds HTML and DOCX copies of the review artifacts kept in this folder.
# Sources: PQC-TLS-rollout-plan.md (exported from the Claude Doc) and PQC-e2e-findings.html (the published page).
set -euo pipefail
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
PANDOC=pandoc/core@sha256:5b8a29d9b70d5d8ca766e5d1dcfc41916b23ab79276a80527be70516110f4c1e
cd "$(dirname "$0")"
CSS='body{font-family:-apple-system,"Segoe UI",Helvetica,Arial,sans-serif;max-width:1100px;margin:2rem auto;padding:0 16px;line-height:1.5;color:#1a1a1a;background:#fff}table{border-collapse:collapse;width:100%;margin:1rem 0;font-size:.92rem}th,td{border:1px solid #d0d0d0;padding:6px 8px;vertical-align:top;text-align:left}th{background:#f2f2f2}code{font-family:Menlo,Consolas,monospace;font-size:.85em;background:#f2f2f2;padding:0 3px;word-break:break-word}h1{font-size:1.8rem}h2{margin-top:2rem;border-bottom:1px solid #ddd;padding-bottom:4px}'
printf '<style>%s</style>\n' "$CSS" > .rollout-style.html
run() { docker run --rm -v "$PWD":/d -w /d "$PANDOC" "$@"; }
run PQC-TLS-rollout-plan.md -f gfm -t html5 -s --metadata title="PQC TLS rollout plan" \
  -V title= --include-in-header=.rollout-style.html -o PQC-TLS-rollout-plan.html
run PQC-TLS-rollout-plan.md -f gfm -t docx --metadata title="PQC TLS rollout plan" -o PQC-TLS-rollout-plan.docx
run PQC-e2e-findings.html -f html -t docx --metadata title="PQC guide: end-to-end findings" -o PQC-e2e-findings.docx
rm -f .rollout-style.html
ls -la
