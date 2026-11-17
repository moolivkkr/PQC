#!/usr/bin/env python3
"""Renumber slide footers ("Post-quantum TLS on AWS · NN") in deck.json order; the cover keeps its byline."""
import json, re
from pathlib import Path
SRC = Path(__file__).resolve().parent.parent / "src" / "deck"
order = json.loads((SRC / "deck.json").read_text())["order"]
score = order.index("scorecard") + 1 if "scorecard" in order else None
for n, sid in enumerate(order, 1):
    p = SRC / "slides" / f"{sid}.html"
    t = p.read_text()
    new = re.sub(r"(Post-quantum TLS on AWS · )(\d\d|NN)", lambda m: f"{m.group(1)}{n:02d}", t)
    if score:  # cross-references to the scorecard
        new = re.sub(r"slide \d+\b", f"slide {score}", new)
    if new != t:
        p.write_text(new)
print(f"{len(order)} slides renumbered")
