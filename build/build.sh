#!/bin/bash
# Build HTML, PDF and DOCX from src/. Usage: bash build/build.sh
set -euo pipefail
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
R="$(cd "$(dirname "$0")/.." && pwd)"
B="$R/build"; T="$B/tabs"
PANDOC=pandoc/core@sha256:5b8a29d9b70d5d8ca766e5d1dcfc41916b23ab79276a80527be70516110f4c1e
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
NAME="PQC-Detection-and-Remediation"
mkdir -p "$T"; rm -f "$T"/*.html

# 1. markdown tabs -> HTML fragments (one container run for all)
docker run --rm --label run=pqc-final -v "$R":/d -w /d --entrypoint sh "$PANDOC" -c '
  for f in src/*.md; do b=$(basename "$f" .md)
    pandoc "$f" -f gfm -t html5 --no-highlight -o "build/tabs/$b.html"; done'
# 2. infrastructure child tabs exported as HTML
cp "$R"/src/html-infra/*.html "$T/"
# 3. combine
python3 -I "$B/combine.py" "$R"
cp "$B/pqc-combined.html" "$R/$NAME.html"
# 4. PDF
"$CHROME" --headless=new --disable-gpu --no-pdf-header-footer --user-data-dir="$B/chrome-profile" \
  --print-to-pdf="$R/$NAME.pdf" "file://$B/pqc-combined.html" 2>/dev/null
# 5. DOCX (imports into Google Docs: File > Open > Upload)
docker run --rm --label run=pqc-final -v "$R":/d -w /d "$PANDOC" build/pqc-for-docx.html -f html -t docx \
  --toc --toc-depth=2 --metadata title="PQC Detection and Remediation by Language and Compute" -o "$NAME.docx"
ls -la "$R/$NAME".*
