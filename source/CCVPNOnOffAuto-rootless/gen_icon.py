#!/usr/bin/env python3
# Render monochrome "VPN" glyph PNGs for the Control Center customizer entry.
# White glyph on transparent, matching the tile's on-state look.
import os
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.dirname(os.path.abspath(__file__))

def find_font():
    cands = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    ]
    for c in cands:
        if os.path.exists(c):
            return c
    return None

font_path = find_font()

def render(px, text, fs):
    img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = ImageFont.load_default()
    if font_path:
        try:
            f = ImageFont.truetype(font_path, fs)
        except Exception:
            f = ImageFont.load_default()
    try:
        bbox = d.textbbox((0, 0), text, font=f)
        w = bbox[2] - bbox[0]; h = bbox[3] - bbox[1]
        offx = bbox[0]; offy = bbox[1]
    except Exception:
        w = h = fs; offx = offy = 0
    x = (px - w) / 2 - offx
    y = (px - h) / 2 - offy
    d.text((x, y), text, font=f, fill=(255, 255, 255, 255))
    return img

for suffix, px, fs in [("", 40, 16), ("@2x", 80, 32), ("@3x", 120, 48)]:
    im = render(px, "VPN", fs)
    p = os.path.join(OUT, "SettingsIcon%s.png" % suffix)
    im.save(p)
    print("wrote", p, im.size)
print("ICON_DONE")
