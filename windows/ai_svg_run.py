import os
import sys
import warnings

warnings.filterwarnings("ignore")

import pymupdf

# Usage: ai_svg_run.py <clean pdf made from the .ai file> <output folder>
# Writes one SVG per artboard (page): p001.svg, p002.svg, ...
src, out_dir = sys.argv[1], sys.argv[2]
doc = pymupdf.open(src)
try:
    for i, page in enumerate(doc, start=1):
        svg = page.get_svg_image(text_as_path=True)
        with open(os.path.join(out_dir, "p%03d.svg" % i), "w", encoding="utf-8") as f:
            f.write(svg)
finally:
    doc.close()
