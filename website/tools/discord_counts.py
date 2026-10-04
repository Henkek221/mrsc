#!/usr/bin/env python3
"""Fetches member and online counts for the Discord invite in app.js (LINKS.discord) into img/discord.json.
Runs at build time so visitors never talk to Discord. build_dist.py calls it automatically."""
import json, os, re, subprocess, sys

site = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
m = re.search(r"discord:\s*'https://discord\.gg/([A-Za-z0-9-]+)'", open(os.path.join(site, "app.js")).read())
out = os.path.join(site, "img/discord.json")
if not m:
    print("discord: no invite in app.js"); sys.exit(0)
try:
    # curl instead of urllib: python.org builds on macOS often lack root certificates.
    raw = subprocess.run(["curl", "-sf", "-m", "15", f"https://discord.com/api/v10/invites/{m.group(1)}?with_counts=true"], capture_output=True, check=True).stdout
    d = json.loads(raw)
except Exception as e:
    print("discord: could not fetch counts, keeping the old ones:", e); sys.exit(0)
info = {"name": d["guild"]["name"], "members": d.get("approximate_member_count"), "online": d.get("approximate_presence_count")}
json.dump(info, open(out, "w"))
print("discord:", info)
if d.get("expires_at"):
    print(f"WARNING: this invite expires {d['expires_at']}. Create one that never expires for the website.")
