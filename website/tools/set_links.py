#!/usr/bin/env python3
"""Swaps the GitHub repo and/or the Ko-fi page everywhere on the site.
Usage: python3 website/tools/set_links.py --github https://github.com/NAME/REPO --kofi https://ko-fi.com/NAME"""
import argparse, os, re, sys

site = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ap = argparse.ArgumentParser()
ap.add_argument("--github")
ap.add_argument("--kofi")
args = ap.parse_args()
if not (args.github or args.kofi):
    sys.exit(__doc__)
if args.github and not re.fullmatch(r"https://github\.com/[\w.-]+/[\w.-]+", args.github):
    sys.exit("--github must look like https://github.com/NAME/REPO")
if args.kofi and not re.fullmatch(r"https://ko-fi\.com/[\w-]+", args.kofi):
    sys.exit("--kofi must look like https://ko-fi.com/NAME")

js = open(os.path.join(site, "app.js")).read()
swaps = []
for key, new in (("github", args.github), ("kofi", args.kofi)):
    if new:
        old = re.search(rf"{key}:\s*'([^']+)'", js).group(1)
        swaps.append((old, new.rstrip("/")))
for name in ["app.js", "index.html", "impressum.html", "datenschutz.html", "404.html", "open-source.html", "llms.txt"]:
    p = os.path.join(site, name)
    s = open(p).read()
    n = 0
    for old, new in swaps:
        n += s.count(old)
        s = s.replace(old, new)
    open(p, "w").write(s)
    print(name, n, "replaced")
