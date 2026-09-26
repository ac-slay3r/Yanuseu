#!/usr/bin/env python3
"""Generate the Yanuseu app icon (dark field, gold forked Y mark)."""
import math
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Sources/Yanuseu/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
SIZE = 1024
SCALE = 4
background = Image.new("RGB", (SIZE, SIZE))
pixels = background.load()
assert pixels is not None
# Restrained charcoal radial gradient; opaque RGB output for iOS App Store icons.
for y in range(SIZE):
    dy = (y - SIZE / 2) / (SIZE * 0.8)
    for x in range(SIZE):
        dx = (x - SIZE / 2) / (SIZE * 0.8)
        glow = max(0.0, 1.0 - math.hypot(dx, dy))
        pixels[x, y] = (int(18 + 9 * glow), int(20 + 8 * glow), int(27 + 7 * glow))
canvas = background.resize((SIZE * SCALE, SIZE * SCALE), Image.Resampling.NEAREST)

draw = ImageDraw.Draw(canvas)
def p(points):
    return [(round(x * SCALE), round(y * SCALE)) for x, y in points]

draw.ellipse((182 * SCALE, 182 * SCALE, 842 * SCALE, 842 * SCALE), outline=(66, 57, 41), width=2 * SCALE)
draw.polygon(p([
    (268, 263), (374, 263), (512, 431), (650, 263), (756, 263),
    (564, 495), (564, 759), (460, 759), (460, 495),
]), fill=(226, 190, 105))
draw.polygon(p([(464, 486), (512, 430), (560, 486), (512, 544)]), fill=(24, 26, 34))
for cx, cy in ((321, 312), (703, 312)):
    r = 11
    draw.ellipse(((cx-r)*SCALE, (cy-r)*SCALE, (cx+r)*SCALE, (cy+r)*SCALE), fill=(246, 220, 156))

canvas = canvas.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
OUT.parent.mkdir(parents=True, exist_ok=True)
canvas.save(OUT, format="PNG", optimize=True)
print(f"Wrote {OUT} ({canvas.mode}, {canvas.size[0]}x{canvas.size[1]})")
