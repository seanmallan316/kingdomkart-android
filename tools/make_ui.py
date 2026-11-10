#!/usr/bin/env python3
"""Draws the phone touch controls (controller style: stick, GAS, DRIFT, BRAKE, pause) and the app icon."""
import sys
from PIL import Image, ImageDraw, ImageFont
OUT = "game/ui/"
FONT = "/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf"
S = 4  # draw big, then shrink for smooth edges


def circle_button(size, word, letter, ring, on):
    im = Image.new("RGBA", (size * S, size * S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    pad = 8 * S
    body = (ring[0], ring[1], ring[2], 215) if on else (40, 40, 46, 170)
    d.ellipse([pad, pad, size * S - pad, size * S - pad], fill=body, outline=ring + (255,), width=9 * S)
    # soft top shine like a real button
    d.ellipse([pad * 3, pad * 2, size * S - pad * 3, size * S * 0.55], fill=(255, 255, 255, 30 if not on else 50))
    ink = (25, 20, 35, 255) if on else (240, 240, 245, 255)
    f = ImageFont.truetype(FONT, int(size * 0.22) * S); w = d.textlength(word, font=f)
    d.text((size * S / 2 - w / 2, size * S * 0.40 - size * 0.14 * S), word, font=f, fill=ink)
    f2 = ImageFont.truetype(FONT, int(size * 0.13) * S); w2 = d.textlength(letter, font=f2)
    d.text((size * S / 2 - w2 / 2, size * S * 0.64), letter, font=f2, fill=ink[:3] + (170,))
    return im.resize((size, size), Image.LANCZOS)


for on in (False, True):
    sfx = "_on" if on else ""
    circle_button(300, "GAS", "A", (90, 220, 120), on).save(OUT + f"btn_gas{sfx}.png")
    circle_button(250, "DRIFT", "R", (90, 180, 255), on).save(OUT + f"btn_drift{sfx}.png")
    circle_button(190, "BRAKE", "B", (255, 110, 110), on).save(OUT + f"btn_brake{sfx}.png")

# steering stick, like the controller picture: a dark ring and a round thumb knob
base = Image.new("RGBA", (300 * S, 300 * S), (0, 0, 0, 0)); d = ImageDraw.Draw(base)
d.ellipse([4 * S, 4 * S, 296 * S, 296 * S], fill=(20, 20, 24, 150), outline=(90, 90, 100, 200), width=6 * S)
for x, pts in ((40, [(40, 150), (70, 125), (70, 175)]), (260, [(260, 150), (230, 125), (230, 175)])):
    d.polygon([(a * S, b * S) for a, b in pts], fill=(200, 200, 210, 160))
base.resize((300, 300), Image.LANCZOS).save(OUT + "stick_base.png")
knob = Image.new("RGBA", (150 * S, 150 * S), (0, 0, 0, 0)); d = ImageDraw.Draw(knob)
d.ellipse([4 * S, 4 * S, 146 * S, 146 * S], fill=(78, 78, 86, 235), outline=(130, 130, 140, 255), width=5 * S)
d.ellipse([22 * S, 18 * S, 128 * S, 90 * S], fill=(255, 255, 255, 28))
knob.resize((150, 150), Image.LANCZOS).save(OUT + "stick_knob.png")

im = Image.new("RGBA", (120 * S, 120 * S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
d.ellipse([6 * S, 6 * S, 114 * S, 114 * S], fill=(40, 40, 46, 170), outline=(150, 150, 160, 255), width=5 * S)
d.rectangle([42 * S, 36 * S, 54 * S, 84 * S], fill=(240, 240, 245, 255)); d.rectangle([66 * S, 36 * S, 78 * S, 84 * S], fill=(240, 240, 245, 255))
im.resize((120, 120), Image.LANCZOS).save(OUT + "btn_pause.png")

if len(sys.argv) > 1:   # the app icon (only remade when the art is given)
    art = Image.open(sys.argv[1]).convert("RGBA")
    icon = Image.new("RGBA", (512, 512), (12, 16, 52, 255)); d = ImageDraw.Draw(icon)
    for i in range(256):
        d.ellipse([6 + i // 2, 6 + i // 2, 506 - i // 2, 506 - i // 2], fill=(12 + i // 6, 16 + i // 6, 52 + i // 4, 255))
    art.thumbnail((440, 440)); icon.alpha_composite(art, ((512 - art.width) // 2, 512 - art.height - 10))
    d.ellipse([8, 8, 504, 504], outline=(255, 210, 110, 255), width=14)
    icon.save("game/icon.png")
print("ui done")
