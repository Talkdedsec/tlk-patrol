#!/usr/bin/env python3
"""Side by side crop of two images: side_by_side.py <ref> <shot> <out> <x> <y> <w> <h>"""
import sys
from PIL import Image

ref, shot, out = sys.argv[1:4]
x, y, w, h = [int(v) for v in sys.argv[4:8]]
a = Image.open(ref).convert("RGB").crop((x, y, x + w, y + h))
b = Image.open(shot).convert("RGB").crop((x, y, x + w, y + h))
im = Image.new("RGB", (w * 2 + 6, h), (255, 0, 255))
im.paste(a, (0, 0))
im.paste(b, (w + 6, 0))
im.save(out)
