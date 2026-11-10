#!/usr/bin/env python3
"""Draws the phone touch controls (controller style: stick, GAS, DRIFT, BRAKE, pause) and the app icon."""
import sys
from PIL import Image, ImageDraw, ImageFont
OUT = "port/ui/"
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

# ---- ITEM button (X / ZL on a controller)
for on in (False, True):
    circle_button(190, "ITEM", "X", (255, 200, 80), on).save(OUT + ("btn_item_on.png" if on else "btn_item.png"))

# ---- the eight blessings, as bright little pictures for the blessing slot
import math
def icon(name, draw):
    im = Image.new("RGBA", (160 * S, 160 * S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    draw(d, lambda v: v * S)
    im.resize((160, 160), Image.LANCZOS).save(OUT + f"item_{name}.png")

def manna(d, s):
    d.ellipse([s(20), s(80), s(140), s(130)], fill=(225, 175, 60, 255), outline=(150, 100, 30, 255), width=s(4))   # golden dish
    for x, y in ((50, 78), (80, 70), (110, 78), (65, 55), (95, 55), (80, 40)):
        d.ellipse([s(x - 17), s(y - 11), s(x + 17), s(y + 11)], fill=(252, 248, 235, 255), outline=(205, 190, 150, 255), width=s(3))
def loaves(d, s):
    d.ellipse([s(15), s(40), s(95), s(100)], fill=(200, 130, 55, 255), outline=(130, 75, 25, 255), width=s(4))
    for x in (38, 55, 72): d.line([s(x), s(52), s(x + 8), s(88)], fill=(240, 190, 110, 255), width=s(4))
    d.ellipse([s(70), s(92), s(135), s(130)], fill=(120, 170, 220, 255), outline=(50, 90, 140, 255), width=s(4))
    d.polygon([s(70), s(111), s(50), s(95), s(50), s(127)], fill=(120, 170, 220, 255))
    d.ellipse([s(118), s(103), s(126), s(111)], fill=(20, 30, 50, 255))
def samaritan(d, s):
    d.polygon([s(80), s(140), s(18), s(70), s(30), s(32), s(62), s(28), s(80), s(52), s(98), s(28), s(130), s(32), s(142), s(70)],
              fill=(235, 70, 90, 255), outline=(150, 30, 50, 255))
    d.rounded_rectangle([s(30), s(95), s(130), s(125)], s(14), fill=(240, 205, 165, 255), outline=(170, 120, 80, 255), width=s(4))
def shield(d, s):
    d.polygon([s(80), s(150), s(22), s(95), s(28), s(25), s(80), s(10), s(132), s(25), s(138), s(95)], fill=(235, 190, 70, 255), outline=(150, 105, 25, 255))
    d.rectangle([s(72), s(35), s(88), s(120)], fill=(255, 250, 230, 255)); d.rectangle([s(50), s(58), s(110), s(74)], fill=(255, 250, 230, 255))
def parting(d, s):
    for x0, x1 in ((10, 65), (95, 150)):
        d.rounded_rectangle([s(x0), s(15), s(x1), s(145)], s(18), fill=(60, 130, 215, 255), outline=(25, 70, 140, 255), width=s(4))
        for y in (40, 75, 110): d.arc([s(x0 + 6), s(y), s(x1 - 6), s(y + 25)], 200, 340, fill=(220, 240, 255, 255), width=s(5))
    d.polygon([s(68), s(150), s(92), s(150), s(84), s(15), s(76), s(15)], fill=(230, 200, 140, 255))
def jubilee(d, s):
    d.polygon([s(15), s(70), s(110), s(55), s(150), s(20), s(150), s(140), s(110), s(105), s(15), s(90)], fill=(235, 185, 70, 255), outline=(150, 100, 25, 255))
    d.ellipse([s(140), s(18), s(158), s(142)], fill=(200, 140, 40, 255))
    for i, r in enumerate((25, 40)): d.arc([s(150 - r), s(80 - r), s(150 + r), s(80 + r)], -40, 40, fill=(255, 240, 200, 255), width=s(4))
def fire(d, s):
    d.ellipse([s(25), s(85), s(95), s(155)], outline=(255, 210, 90, 255), width=s(9))
    for a in range(0, 360, 45):
        d.line([s(60), s(120), s(60 + 30 * math.cos(math.radians(a))), s(120 + 30 * math.sin(math.radians(a)))], fill=(255, 210, 90, 255), width=s(5))
    d.polygon([s(60), s(5), s(110), s(60), s(150), s(30), s(140), s(100), s(95), s(110), s(40), s(80)], fill=(255, 110, 30, 255))
    d.polygon([s(75), s(40), s(105), s(75), s(125), s(60), s(120), s(95), s(90), s(100), s(65), s(80)], fill=(255, 220, 80, 255))
def water(d, s):
    d.polygon([s(80), s(8), s(128), s(88), s(32), s(88)], fill=(70, 160, 240, 255))
    d.ellipse([s(32), s(55), s(128), s(150)], fill=(70, 160, 240, 255), outline=(30, 90, 170, 255), width=s(4))
    d.ellipse([s(55), s(85), s(78), s(115)], fill=(220, 240, 255, 230))
for n, f in (("manna", manna), ("loaves", loaves), ("samaritan", samaritan), ("shield", shield), ("parting", parting),
             ("jubilee", jubilee), ("fire", fire), ("water", water)):
    icon(n, f)
print("items done")

# ---- BACK (B) for the menus
circle_button(160, "BACK", "B", (200, 200, 220), False).save(OUT + "btn_back.png")
print("back done")
