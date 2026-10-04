#!/usr/bin/env python3
"""Copies only what the live site needs into website/dist (about 2 MB instead of 100 MB).
Upload that folder to Cloudflare Pages. Run: python3 website/tools/build_dist.py"""
import os, shutil, subprocess, sys

site = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
dist = os.path.join(site, "dist")
SKIP = {"dist", "screenshots", "tools", "README.md", ".DS_Store"}
subprocess.run([sys.executable, os.path.join(site, "tools/discord_counts.py")])
js = open(os.path.join(site, "app.js")).read()
for placeholder in ("your-github/mrsc", "ko-fi.com/your-kofi"):
    if placeholder in js:
        print(f"WARNING: {placeholder} is still a placeholder. Set it with tools/set_links.py before going live.")
shutil.rmtree(dist, ignore_errors=True)
shutil.copytree(site, dist, ignore=lambda d, names: [n for n in names if n in SKIP or n.startswith(".")])
size = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(dist) for f in fs)
print(f"dist: {size / 1e6:.1f} MB")
