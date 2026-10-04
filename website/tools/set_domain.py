#!/usr/bin/env python3
"""Puts the real domain into every file that needs an absolute URL (canonical, share image, sitemap, llms.txt).
Usage: python3 website/tools/set_domain.py https://your-domain.tld"""
import os, sys

if len(sys.argv) != 2 or not sys.argv[1].startswith("https://"):
    sys.exit("usage: set_domain.py https://your-domain.tld")
new = sys.argv[1].rstrip("/")
site = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
marker = os.path.join(site, "tools/.domain")
old = open(marker).read().strip() if os.path.exists(marker) else "https://mrsc.app"
for name in ["index.html", "open-source.html", "robots.txt", "sitemap.xml", "llms.txt"]:
    p = os.path.join(site, name)
    s = open(p).read()
    open(p, "w").write(s.replace(old, new))
    print(name, s.count(old), "replaced")
open(marker, "w").write(new + "\n")
