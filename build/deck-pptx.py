#!/usr/bin/env python3
"""Build PQC-Summary.pptx from rendered slide images plus speaker notes.

Usage (inside the container that build/deck.sh starts):
  deck-pptx.py <png-dir> <notes.json> <out.pptx>
Each slide is one full-bleed 1920x1080 image; the notes come from each slide's <aside>.
"""
import json
import sys
from pathlib import Path

from pptx import Presentation
from pptx.util import Emu

png_dir, notes_path, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
meta = json.loads(notes_path.read_text())
images = sorted(png_dir.glob("slide-*.png"))
if len(images) != len(meta["slides"]):
    sys.exit(f"{len(images)} images but {len(meta['slides'])} slides in the notes")

prs = Presentation()
prs.slide_width, prs.slide_height = Emu(12192000), Emu(6858000)  # 13.333 x 7.5 in, 16:9
prs.core_properties.title = meta["title"]
prs.core_properties.author = "Kishore Mooli"
blank = prs.slide_layouts[6]
for img, s in zip(images, meta["slides"]):
    slide = prs.slides.add_slide(blank)
    slide.shapes.add_picture(str(img), 0, 0, prs.slide_width, prs.slide_height)
    slide.notes_slide.notes_text_frame.text = s["notes"]
prs.save(out)
print(f"{len(images)} slides -> {out}")
