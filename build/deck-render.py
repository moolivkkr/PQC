#!/usr/bin/env python3
"""Assemble src/deck (Slides artifact source) into one printable HTML page.

Writes build/deck.html (one 1920x1080 page per slide, in deck.json order) and
build/deck-notes.json (speaker notes per slide). build/deck.sh prints the page
to PDF with headless Chrome and turns the PDF into a PPTX.

The artifact viewer provides <x-icon> and <x-connector>; here a small script
draws them as inline SVG so the printed slides match the published deck.
"""
import html
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src" / "deck"
OUT = ROOT / "build"

FONTS = """
@font-face { font-family: 'IBM Plex Sans'; font-weight: 400; src: url(fonts/ibm-plex-sans-latin-400-normal.woff2) format('woff2'); }
@font-face { font-family: 'IBM Plex Sans'; font-weight: 500; src: url(fonts/ibm-plex-sans-latin-500-normal.woff2) format('woff2'); }
@font-face { font-family: 'IBM Plex Sans'; font-weight: 600; src: url(fonts/ibm-plex-sans-latin-600-normal.woff2) format('woff2'); }
@font-face { font-family: 'IBM Plex Sans'; font-weight: 700; src: url(fonts/ibm-plex-sans-latin-700-normal.woff2) format('woff2'); }
@font-face { font-family: 'JetBrains Mono'; font-weight: 400; src: url(fonts/jetbrains-mono-latin-400-normal.woff2) format('woff2'); }
@font-face { font-family: 'JetBrains Mono'; font-weight: 600; src: url(fonts/jetbrains-mono-latin-600-normal.woff2) format('woff2'); }
"""

# Base rules the Slides viewer applies (from the type's reference/viewer.md), so the
# local render matches what people see in the published deck.
BASE = """
* { margin: 0 }
body { font: 32px/1.2 sans-serif }
h1 { font-size: 96px; font-weight: 600 }
h2 { font-size: 64px; font-weight: 600 }
h3 { font-size: 44px; font-weight: 600 }
p, li, h1, h2, h3, td, th { overflow-wrap: break-word; text-wrap: pretty }
table { width: 100%; border-collapse: separate; border-spacing: 0; border: solid #0003; border-width: 2px 0 0 2px }
th, td { padding: .35em .6em; text-align: left; border: solid #0003; border-width: 0 2px 2px 0 }
x-shape, x-icon, x-embed { display: block }
"""

PRINT = """
@page { size: 1920px 1080px; margin: 0; }
html, body { margin: 0; padding: 0; background: #14213D; }
* { animation: none !important; }
section { width: 1920px; height: 1080px; box-sizing: border-box; position: relative; overflow: hidden; break-after: page; }
section > aside { display: none; }
"""

# Simple outline glyphs for the icons the deck uses (48x48, stroke = currentColor).
SCRIPT = r"""
const ICONS = {
  Clock: '<circle cx="24" cy="24" r="19"/><path d="M24 13v11l8 5"/>',
  Warning: '<path d="M24 6 L44 41 H4 Z"/><path d="M24 19v11"/><circle cx="24" cy="35" r="1.5" fill="currentColor"/>',
  Search: '<circle cx="20" cy="20" r="13"/><path d="M30 30 L43 43"/>',
};
for (const el of document.querySelectorAll('x-icon')) {
  const g = ICONS[el.getAttribute('name')] || '<circle cx="24" cy="24" r="19"/>';
  el.outerHTML = `<svg class="${el.className}" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">${g}</svg>`;
}
for (const sec of document.querySelectorAll('section')) {
  const cons = sec.querySelectorAll('x-connector');
  if (!cons.length) continue;
  const ns = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(ns, 'svg');
  svg.setAttribute('width', 1920); svg.setAttribute('height', 1080);
  svg.style.cssText = 'position:absolute;left:0;top:0;pointer-events:none;overflow:visible';
  let n = 0;
  for (const c of cons) {
    const [x1, y1, x2, y2] = ['x1', 'y1', 'x2', 'y2'].map(a => +c.getAttribute(a));
    const color = c.style.color || '#1F5F94';
    const w = parseFloat(c.style.borderWidth) || 3;
    const dashed = c.style.borderStyle === 'dashed';
    let d = `M${x1} ${y1} L${x2} ${y2}`;
    if (c.getAttribute('route') === 'elbow') { const xm = (x1 + x2) / 2; d = `M${x1} ${y1} H${xm} V${y2} H${x2}`; }
    const id = 'ah' + (n++);
    const m = document.createElementNS(ns, 'marker');
    m.setAttribute('id', id); m.setAttribute('viewBox', '0 0 10 10'); m.setAttribute('refX', 9); m.setAttribute('refY', 5);
    m.setAttribute('markerWidth', 5); m.setAttribute('markerHeight', 5); m.setAttribute('orient', 'auto');
    m.innerHTML = `<path d="M0 0 L10 5 L0 10 Z" fill="${color}"/>`;
    svg.appendChild(m);
    const p = document.createElementNS(ns, 'path');
    p.setAttribute('d', d); p.setAttribute('fill', 'none'); p.setAttribute('stroke', color); p.setAttribute('stroke-width', w);
    if (dashed) p.setAttribute('stroke-dasharray', `${w * 4} ${w * 3}`);
    if (c.getAttribute('head') === 'end') p.setAttribute('marker-end', `url(#${id})`);
    svg.appendChild(p);
    c.remove();
  }
  sec.appendChild(svg);
}
// Layout check: content must sit inside the 128px side margins and end above the footer.
document.fonts.ready.then(() => {
  const problems = [];
  for (const sec of document.querySelectorAll('section')) {
    const sr = sec.getBoundingClientRect();
    const foot = sec.querySelector('.foot');
    const limit = foot ? foot.getBoundingClientRect().top - sr.top - 8 : 1080 - 96;
    for (const el of sec.querySelectorAll('*')) {
      if (el.closest('aside') || el.closest('.foot') || el.closest('svg') || el.matches('.spine, .zone')) continue;
      const r = el.getBoundingClientRect();
      if (!r.width || !r.height) continue;
      const bottom = r.bottom - sr.top, right = r.right - sr.left;
      if (bottom > limit + 0.5 || right > 1920 - 128 + 0.5)
        problems.push(`${sec.id}: <${el.tagName.toLowerCase()}${el.className ? '.' + el.className : ''}> bottom ${Math.round(bottom)} (limit ${Math.round(limit)}), right ${Math.round(right)}`);
    }
    if (foot && foot.scrollWidth > foot.clientWidth + 1) problems.push(`${sec.id}: footer text wraps or overflows`);
  }
  const pre = document.createElement('pre');
  pre.id = 'layout-check'; pre.style.display = 'none';
  pre.textContent = problems.length ? problems.join('\n') : 'LAYOUT OK';
  document.body.appendChild(pre);
});
"""


def main() -> int:
    deck = json.loads((SRC / "deck.json").read_text())
    css = (SRC / "deck.css").read_text()
    sections, notes = [], []
    for sid in deck["order"]:
        text = (SRC / "slides" / f"{sid}.html").read_text()
        m = re.search(r"<aside>(.*?)</aside>", text, re.S)
        notes.append({"id": sid, "notes": html.unescape(m.group(1)).strip() if m else ""})
        sections.append(text)
    page = (
        f"<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
        f"<title>{html.escape(deck['title'])}</title>"
        f"<style>{FONTS}{BASE}{css}{PRINT}</style></head><body>\n"
        + "\n".join(sections)
        + f"\n<script>{SCRIPT}</script></body></html>\n"
    )
    (OUT / "deck.html").write_text(page)
    (OUT / "deck-notes.json").write_text(json.dumps({"title": deck["title"], "slides": notes}, indent=1, ensure_ascii=False))
    print(f"{len(sections)} slides -> build/deck.html")
    return 0


if __name__ == "__main__":
    sys.exit(main())
