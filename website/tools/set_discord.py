#!/usr/bin/env python3
"""Swaps the Discord invite everywhere on the site.
Usage: python3 website/tools/set_discord.py https://discord.gg/NEWCODE"""
import os, re, sys

if len(sys.argv) != 2 or not re.fullmatch(r"https://discord\.gg/[A-Za-z0-9-]+", sys.argv[1]):
    sys.exit("usage: set_discord.py https://discord.gg/CODE")
site = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
for name in ["app.js", "index.html", "impressum.html", "datenschutz.html", "404.html", "open-source.html", "llms.txt"]:
    p = os.path.join(site, name)
    s = open(p).read()
    new, n = re.subn(r"https://discord\.gg/[A-Za-z0-9-]+", sys.argv[1], s)
    open(p, "w").write(new)
    print(name, n, "replaced")
