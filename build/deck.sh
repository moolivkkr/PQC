#!/usr/bin/env bash
# Builds the summary deck as PPTX (pandoc, pinned) and PDF (LibreOffice in debian:trixie-slim).
set -euo pipefail
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
cd "$(dirname "$0")/.."
PANDOC=pandoc/core@sha256:5b8a29d9b70d5d8ca766e5d1dcfc41916b23ab79276a80527be70516110f4c1e
docker run --rm -v "$PWD":/d -w /d "$PANDOC" src/deck/summary-deck.md -t pptx --slide-level=2 \
  --reference-doc=build/deck-reference.pptx -o PQC-Summary.pptx
docker run --rm --label project=pqc-e2e -v "$PWD":/r debian:trixie-slim sh -c '
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    libreoffice-impress fonts-dejavu poppler-utils >/dev/null 2>&1 &&
  mkdir -p /tmp/o && cp /r/PQC-Summary.pptx /tmp/o/ && cd /tmp/o &&
  HOME=/tmp soffice --headless --convert-to pdf PQC-Summary.pptx >/dev/null 2>&1 &&
  pdfinfo PQC-Summary.pdf | grep Pages && cp PQC-Summary.pdf /r/'
ls -la PQC-Summary.pptx PQC-Summary.pdf
