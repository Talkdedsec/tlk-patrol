#!/usr/bin/env python3
"""Stacks an image crop above a screenshot crop and prints the mean absolute difference.

Usage: compare_ref.py <image.jpg> <shot.png> <out.png> <x> <y> <w> <h>
"""
import sys
from PIL import Image, ImageChops

ref_path, shot_path, out_path = sys.argv[1:4]
x, y, w, h = [int(v) for v in sys.argv[4:8]]
ref = Image.open(ref_path).convert("RGB").crop((x, y, x + w, y + h))
shot = Image.open(shot_path).convert("RGB").crop((x, y, x + w, y + h))
diff = ImageChops.difference(ref, shot)
mean = sum(sum(p) for p in diff.getdata()) / (3.0 * w * h)
out = Image.new("RGB", (w, h * 2 + 6), (255, 0, 255))
out.paste(ref, (0, 0))
out.paste(shot, (0, h + 6))
out.save(out_path)
print("mean abs diff %.2f" % mean)
