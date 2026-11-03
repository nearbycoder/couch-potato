#!/usr/bin/env python3
"""Builds the key-less series catalog that the apps read for service pages.

Without a TMDB key the apps only see what TVmaze's daily schedule mentions, so a
service page would show just the handful of shows with an episode this week.
This script walks TVmaze's full show index (~350 pages, too big for a phone),
keeps the shows that stream on a service Couch Potato knows about, and writes
one compact JSON file per service to docs/catalog/v1/, served by GitHub Pages.

Each file is a JSON array of TVmaze show objects (a subset of the API fields),
so the apps decode them with the same models they use for the live API.

Run: python3 scripts/build_catalog.py  (stdlib only; ~5 minutes)
"""

import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

API = "https://api.tvmaze.com/shows?page={}"
OUT = os.path.join(os.path.dirname(__file__), "..", "docs", "catalog", "v1")
PER_SERVICE = 600
BATCH = 4
SUMMARY_CHARS = 320

# Mirrors Provider.streamers in CouchPotato/Models/Provider.swift (and the Android
# Provider list): id, display name, aliases. Matching follows Provider.matching:
# an exact name/alias match first, then a substring match on aliases longer than 3.
SERVICES = [
    ("netflix", "Netflix", ["netflix"]),
    ("hulu", "Hulu", ["hulu", "fx", "fxx", "abc", "freeform"]),
    ("disney", "Disney+", ["disney", "national geographic", "nat geo"]),
    ("hbo", "HBO Max", ["hbo", "max", "cinemax", "tnt", "tbs", "adult swim", "cartoon network", "discovery", "hgtv", "food network", "tlc"]),
    ("apple", "Apple TV", ["apple tv+", "apple tv"]),
    ("prime", "Prime Video", ["prime video", "amazon", "freevee", "mgm+"]),
    ("peacock", "Peacock", ["peacock", "nbc", "bravo", "usa network", "syfy", "e!"]),
    ("paramount", "Paramount+", ["paramount", "cbs", "showtime", "mtv", "comedy central", "nickelodeon", "bet"]),
    ("starz", "Starz", ["starz"]),
    ("amc", "AMC+", ["amc", "shudder", "sundance", "acorn", "ifc"]),
    ("crunchyroll", "Crunchyroll", ["crunchyroll"]),
    ("tubi", "Tubi", ["tubi"]),
    ("youtube", "YouTube", ["youtube"]),
]


def match(channel_name):
    lower = channel_name.lower()
    for sid, name, aliases in SERVICES:
        if name.lower() == lower or lower in aliases:
            return sid
    for sid, _, aliases in SERVICES:
        if any(len(a) > 3 and a in lower for a in aliases):
            return sid
    return None


def services_for(show):
    found = []
    web = show.get("webChannel")
    if web:
        sid = match(web["name"])
        if sid:
            found.append(sid)
    network = show.get("network")
    # Broadcast/cable networks only map to a US streamer when they're US networks
    # (ABC Australia isn't on Hulu).
    if network and ((network.get("country") or {}).get("code") == "US"):
        sid = match(network["name"])
        if sid and sid not in found:
            found.append(sid)
    return found


def fetch(page):
    for attempt in range(6):
        try:
            req = urllib.request.Request(API.format(page), headers={"User-Agent": "CouchPotato catalog builder"})
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None  # past the last page
            if e.code == 429:
                time.sleep(2 + attempt * 2)
                continue
            raise
        except (urllib.error.URLError, TimeoutError):
            time.sleep(2 + attempt * 2)
    raise RuntimeError(f"page {page} kept failing")


def compact(show):
    summary = re.sub(r"<[^>]+>", "", show.get("summary") or "").strip()
    if len(summary) > SUMMARY_CHARS:
        summary = summary[:SUMMARY_CHARS].rsplit(" ", 1)[0] + "…"
    channel = lambda c: {"id": c["id"], "name": c["name"]} if c else None
    image = show.get("image") or {}
    out = {
        "id": show["id"],
        "url": show.get("url"),
        "name": show["name"],
        "type": show.get("type"),
        "language": show.get("language"),
        "genres": show.get("genres") or [],
        "status": show.get("status"),
        "averageRuntime": show.get("averageRuntime"),
        "premiered": show.get("premiered"),
        "officialSite": show.get("officialSite"),
        "rating": {"average": (show.get("rating") or {}).get("average")},
        "weight": show.get("weight") or 0,
        "network": channel(show.get("network")),
        "webChannel": channel(show.get("webChannel")),
        "externals": {"imdb": (show.get("externals") or {}).get("imdb")},
        "image": {"medium": image.get("medium"), "original": image.get("original")},
        "summary": summary,
    }
    return {k: v for k, v in out.items() if v is not None}


def main():
    buckets = {sid: [] for sid, _, _ in SERVICES}
    page, done = 0, False
    # TVmaze allows 20 requests / 10 s: fetch BATCH pages at a time, at most ~1.6/s.
    with ThreadPoolExecutor(max_workers=BATCH) as pool:
        while not done:
            started = time.monotonic()
            for shows in pool.map(fetch, range(page, page + BATCH)):
                if not shows:
                    done = True
                    continue
                for show in shows:
                    if not (show.get("image") or {}).get("medium"):
                        continue
                    if show.get("status") in ("In Development", "To Be Determined") and not show.get("premiered"):
                        continue
                    for sid in services_for(show):
                        buckets[sid].append(show)
            page += BATCH
            if page % 40 == 0:
                print(f"  page {page}", file=sys.stderr)
            time.sleep(max(0, BATCH / 1.6 - (time.monotonic() - started)))

    os.makedirs(OUT, exist_ok=True)
    index = {"updated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "services": {}}
    for sid, shows in buckets.items():
        # Most-followed first; newer premieres break ties.
        shows.sort(key=lambda s: (s.get("weight") or 0, s.get("premiered") or ""), reverse=True)
        kept = [compact(s) for s in shows[:PER_SERVICE]]
        with open(os.path.join(OUT, f"{sid}.json"), "w", encoding="utf-8") as f:
            json.dump(kept, f, ensure_ascii=False, separators=(",", ":"))
        index["services"][sid] = len(kept)
        print(f"{sid}: {len(shows)} matched, {len(kept)} written")
    with open(os.path.join(OUT, "index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f, indent=1)


if __name__ == "__main__":
    main()
