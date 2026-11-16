#!/usr/bin/env bash
# Builds the deck from src/deck (the Slides artifact source: deck.json, deck.css, slides/*.html).
#   1. build/deck-render.py assembles build/deck.html and the speaker notes.
#   2. Headless Chrome prints it to PQC-Summary.pdf (one 1920x1080 page per slide)
#      and reports any slide whose content overflows its margins or footer.
#   3. A python:3.12-slim container rasterises the PDF (pdftoppm) and writes
#      PQC-Summary.pptx with python-pptx: one full-bleed image per slide plus the notes.
set -euo pipefail
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PROFILE="$PWD/build/chrome-profile"

python3 build/deck-render.py

"$CHROME" --headless=new --disable-gpu --user-data-dir="$PROFILE" --virtual-time-budget=8000 \
  --dump-dom "file://$PWD/build/deck.html" 2>/dev/null \
  | python3 -c 'import sys,re,html; m=re.search(r"<pre id=\"layout-check\"[^>]*>(.*?)</pre>",sys.stdin.read(),re.S); r=html.unescape(m.group(1)) if m else "LAYOUT CHECK DID NOT RUN"; print(r); sys.exit(0 if r=="LAYOUT OK" else 1)'

"$CHROME" --headless=new --disable-gpu --no-pdf-header-footer --user-data-dir="$PROFILE" \
  --virtual-time-budget=8000 --print-to-pdf="$PWD/PQC-Summary.pdf" "file://$PWD/build/deck.html" 2>/dev/null

docker run --rm --label project=pqc-e2e -v "$PWD":/r -w /r python:3.12-slim sh -c '
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends poppler-utils >/dev/null 2>&1 &&
  pip install -q --root-user-action=ignore python-pptx==1.0.2 >/dev/null 2>&1 &&
  rm -rf /tmp/png && mkdir /tmp/png && pdfinfo PQC-Summary.pdf | grep -E "Pages|Page size" &&
  pdftoppm -r 72 -scale-to-x 1920 -scale-to-y 1080 -png PQC-Summary.pdf /tmp/png/slide &&
  python build/deck-pptx.py /tmp/png build/deck-notes.json PQC-Summary.pptx'
ls -la PQC-Summary.pptx PQC-Summary.pdf
