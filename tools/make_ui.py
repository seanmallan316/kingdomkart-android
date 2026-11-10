#!/usr/bin/env python3
"""Draws the phone touch buttons (normal and pressed) and the app icon."""
import math, sys
from PIL import Image, ImageDraw, ImageFont
OUT = "game/ui/"
FONT = "/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf"
S = 4  # draw big then shrink for smooth edges

def base(size, on, ring):
    im = Image.new("RGBA", (size * S, size * S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    fill = (255, 215, 110, 200) if on else (20, 18, 45, 150)
    d.ellipse([6 * S, 6 * S, (size - 6) * S, (size - 6) * S], fill=fill, outline=ring, width=7 * S)
    return im, d

def finish(im, size, name):
    im.resize((size, size), Image.LANCZOS).save(OUT + name)

def arrow(d, size, left, col):
    c = size * S / 2; r = size * S * 0.26
    pts = [(c + r, c - r), (c - r * 0.9, c), (c + r, c + r)] if left else [(c - r, c - r), (c + r * 0.9, c), (c - r, c + r)]
    d.polygon(pts, fill=col)

def text(d, size, t, col, fs):
    f = ImageFont.truetype(FONT, fs * S); w = d.textlength(t, font=f)
    d.text((size * S / 2 - w / 2, size * S / 2 - fs * S * 0.62), t, font=f, fill=col)

for on in (False, True):
    sfx = "_on" if on else ""
    ink = (40, 20, 60, 255) if on else (255, 245, 220, 255)
    ring = (255, 220, 120, 255)
    for name, left in (("left", True), ("right", False)):
        im, d = base(230, on, ring); arrow(d, 230, left, ink); finish(im, 230, f"btn_{name}{sfx}.png")
    im, d = base(230, on, (120, 200, 255, 255)); text(d, 230, "DRIFT", ink, 46); finish(im, 230, f"btn_drift{sfx}.png")
    im, d = base(190, on, (255, 120, 120, 255)); text(d, 190, "BRAKE", ink, 36); finish(im, 190, f"btn_brake{sfx}.png")
im, d = base(120, False, ring)
d.rectangle([42 * S, 36 * S, 54 * S, 84 * S], fill=(255, 245, 220, 255)); d.rectangle([66 * S, 36 * S, 78 * S, 84 * S], fill=(255, 245, 220, 255))
finish(im, 120, "btn_pause.png")
# app icon: the Jesus character art on a night-blue tile with a gold ring
art = Image.open(sys.argv[1]).convert("RGBA")
icon = Image.new("RGBA", (512, 512), (12, 16, 52, 255)); d = ImageDraw.Draw(icon)
for i in range(256):
    d.ellipse([256 - 250 + i // 2, 256 - 250 + i // 2, 256 + 250 - i // 2, 256 + 250 - i // 2], fill=(12 + i // 6, 16 + i // 6, 52 + i // 4, 255))
art.thumbnail((440, 440)); icon.alpha_composite(art, ((512 - art.width) // 2, 512 - art.height - 10))
d.ellipse([8, 8, 504, 504], outline=(255, 210, 110, 255), width=14)
icon.save("game/icon.png")
print("ui done")
