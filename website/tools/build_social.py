#!/usr/bin/env python3
"""Builds the share image (img/og-image.jpg, 1200x630) and the PNG app icons from the brushed wordmark.
Run after the logo or the screenshots change: python3 website/tools/build_social.py"""
import json, os, re
from PIL import Image, ImageDraw, ImageFont

here = os.path.dirname(os.path.abspath(__file__))
site = os.path.join(here, "..")
RED = (255, 59, 92)
letters = json.loads(re.search(r"=\s*(\[.*\]);", open(os.path.join(site, "assets/wordmark.js")).read(), re.S).group(1))

def wordmark(size, ss=3):
    """White brushed MR/SC on transparent, size x size px (drawn large, then scaled down for smooth edges)."""
    big = size * ss
    im = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    k = big / 1024
    for path in letters:
        for poly in path.split("Z"):
            nums = [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", poly)]
            pts = [(nums[i] * k, nums[i + 1] * k) for i in range(0, len(nums) - 1, 2)]
            if len(pts) > 2:
                d.polygon(pts, fill=(255, 255, 255, 255))
    return im.resize((size, size), Image.LANCZOS)

def icon(size, radius=0):
    im = Image.new("RGBA", (size, size), RED + (255,))
    im.alpha_composite(wordmark(size))
    if radius:
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius, fill=255)
        im.putalpha(mask)
    return im

icon(180).convert("RGB").save(os.path.join(site, "assets/apple-touch-icon.png"))
icon(512).convert("RGB").save(os.path.join(site, "assets/icon-512.png"))
icon(192).convert("RGB").save(os.path.join(site, "assets/icon-192.png"))
# Browser tab icons: rounded like the SVG favicon, transparent corners.
icon(256, radius=58).save(os.path.join(site, "favicon.ico"), sizes=[(16, 16), (32, 32), (48, 48)])
icon(96, radius=22).save(os.path.join(site, "assets/favicon-96.png"))

def sf(size, weight):
    f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)
    f.set_variation_by_name(weight)
    return f

W, H = 1200, 630
og = Image.new("RGBA", (W, H), RED + (255,))
d = ImageDraw.Draw(og)
og.alpha_composite(wordmark(230), (58, 52))
d.text((72, 318), "The music player with\nway too many settings.", font=sf(52, b"Bold"), fill="white", spacing=6)
d.text((74, 470), "Free · Offline · Liquid Glass · iPhone", font=sf(28, b"Semibold"), fill=(255, 255, 255, 215))

def phone(name, width):
    shot = Image.open(os.path.join(site, f"img/{name}.webp")).convert("RGBA")
    h = round(shot.height * width / shot.width)
    shot = shot.resize((width, h), Image.LANCZOS)
    pad = round(width * 0.035)
    body = Image.new("RGBA", (width + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    r_outer, r_inner = round(width * 0.17), round(width * 0.14)
    ImageDraw.Draw(body).rounded_rectangle((0, 0, body.width - 1, body.height - 1), r_outer, fill=(12, 12, 14, 255))
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width - 1, h - 1), r_inner, fill=255)
    body.paste(shot, (pad, pad), mask)
    return body

back = phone("home-mrsc", 250).rotate(6, resample=Image.BICUBIC, expand=True)
front = phone("player-mrsc", 270).rotate(-5, resample=Image.BICUBIC, expand=True)
og.alpha_composite(back, (930 - back.width // 2 + 90, 70))
og.alpha_composite(front, (840 - front.width // 2, 110))
og.convert("RGB").save(os.path.join(site, "img/og-image.jpg"), quality=88, optimize=True)
print("ok")
