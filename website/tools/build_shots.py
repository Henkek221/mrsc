#!/usr/bin/env python3
"""Turns the raw iPhone screenshots in website/screenshots/ into small WebP files in website/img/.
- Erases the real status bar (time, battery, "◂ Instagram") so the page can draw a clean 9:41 one on top.
- Writes img/shots.json with the status bar ink colour per image.
Run: python3 website/tools/build_shots.py"""
import json, os
from PIL import Image

here = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(here, "../screenshots")
dst = os.path.join(here, "../img")
os.makedirs(dst, exist_ok=True)

# raw file -> (name, has a status bar)
MAP = {
    "IMG_0804.PNG": ("home-mrsc", True), "IMG_0805.PNG": ("home-green-room", True),
    "IMG_0806.PNG": ("home-crimson", True), "IMG_0807.PNG": ("home-tube", True),
    "IMG_0808.PNG": ("home-cloud", True), "IMG_0809.PNG": ("home-tide", True),
    "IMG_0810.PNG": ("home-pulse", True),
    "IMG_0811.PNG": ("player-mrsc", True), "IMG_0813.PNG": ("player-green-room", True),
    "IMG_0814.PNG": ("player-crimson", True), "IMG_0815.PNG": ("player-tube", True),
    "IMG_0816.PNG": ("player-cloud", True), "IMG_0817.PNG": ("player-tide", True),
    "IMG_0818.PNG": ("player-pulse", True),
    "IMG_0819.PNG": ("home", True), "IMG_0820.PNG": ("lyrics", False),
    "IMG_0821.PNG": ("customize", True), "IMG_0822.PNG": ("edit-theme", True),
    "IMG_0823.PNG": ("audio-lab", True), "IMG_0824.PNG": ("sound", True),
    "IMG_0825.PNG": ("app-icon", True), "IMG_0826.PNG": ("onboarding", True),
}
BAR, SAMPLE, WIDTH = 150, 152, 720  # px in the 1206 x 2622 original

manifest = {}
for raw, (name, bar) in MAP.items():
    p = os.path.join(src, raw)
    if not os.path.exists(p):
        print("missing", raw); continue
    im = Image.open(p).convert("RGB")
    ink = None
    if bar:
        row = im.crop((0, SAMPLE, im.width, SAMPLE + 1))
        for y in range(BAR + 1):
            im.paste(row, (0, y))
        b = row.tobytes(); px = [tuple(b[i:i + 3]) for i in range(0, len(b), 3)]
        lum = sum(0.2126 * r + 0.7152 * g + 0.0722 * b for r, g, b in px) / len(px) / 255
        ink = "#000" if lum > 0.55 else "#fff"
    im = im.resize((WIDTH, round(im.height * WIDTH / im.width)), Image.LANCZOS)
    im.save(os.path.join(dst, name + ".webp"), "WEBP", quality=82, method=6)
    manifest[name] = ink

# Widgets: only the widget stack from the home screen shot.
p = os.path.join(src, "IMG_0827.PNG")
if os.path.exists(p):
    w = Image.open(p).convert("RGB").crop((30, 240, 1176, 1380))
    w = w.resize((760, round(w.height * 760 / w.width)), Image.LANCZOS)
    w.save(os.path.join(dst, "widgets.webp"), "WEBP", quality=84, method=6)

json.dump(manifest, open(os.path.join(dst, "shots.json"), "w"), indent=1)
total = sum(os.path.getsize(os.path.join(dst, f)) for f in os.listdir(dst))
print(f"{len(manifest)} shots, {total / 1e6:.1f} MB")
