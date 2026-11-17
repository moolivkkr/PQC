#!/bin/bash
# Build every document from src/ as HTML, PDF and DOCX. Usage: bash build/build.sh [document ...]
# Documents (build/combine.py DOCS): guide, paper, exec, go, python, nodejs, java, dotnet. Default: all.
set -euo pipefail
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
R="$(cd "$(dirname "$0")/.." && pwd)"
B="$R/build"; T="$B/tabs"
PANDOC=pandoc/core@sha256:5b8a29d9b70d5d8ca766e5d1dcfc41916b23ab79276a80527be70516110f4c1e
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
mkdir -p "$T"; rm -f "$T"/*.html

# 1. markdown chapters -> HTML fragments (one container run for all)
docker run --rm --label run=pqc-final -v "$R":/d -w /d --entrypoint sh "$PANDOC" -c '
  for f in src/*.md src/paper/*.md src/summary/*.md src/exec/*.md src/lang/*.md; do b=$(basename "$f" .md)
    pandoc "$f" -f gfm -t html5 --no-highlight -o "build/tabs/$b.html"; done'
# 2. infrastructure chapters exported as HTML
cp "$R"/src/html-infra/*.html "$T/"
# 3. combine into documents; each OUT line: key, output path (no extension), title
mkdir -p "$B/out"
python3 -I "$B/combine.py" "$R" "$@" | tee "$B/out/combine.log"
grep '^OUT ' "$B/out/combine.log" | while read -r _ key out title; do
  mkdir -p "$(dirname "$R/$out")"
  cp "$B/out/$key.html" "$R/$out.html"
  # 4. PDF
  "$CHROME" --headless=new --disable-gpu --no-pdf-header-footer --user-data-dir="$B/chrome-profile" \
    --print-to-pdf="$R/$out.pdf" "file://$B/out/$key.html" 2>/dev/null
  # 5. DOCX (imports into Google Docs: File > Open > Upload)
  docker run --rm --label run=pqc-final -v "$R":/d -w /d "$PANDOC" "build/out/$key-docx.html" -f html -t docx \
    --toc --toc-depth=2 --metadata title="$title" -o "$out.docx" </dev/null
  ls -la "$R/$out".pdf "$R/$out".docx | awk '{print $5, $9}'
done
