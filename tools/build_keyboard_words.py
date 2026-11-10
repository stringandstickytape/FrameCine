#!/usr/bin/env python3
"""Rebuild the keyboard dictionary from SCOWL 2020.12.07 (only the Python standard library).

Levels 10-50 are popularity classes, not measured token frequencies. Keep lowercase ASCII English words plus US
spellings; no names, abbreviations or contractions. The source is pinned and checked before use.
Pass --archive to rebuild offline from the original tarball. Nothing is extracted onto the filesystem.
"""
import argparse
import hashlib
import gzip
import io
from pathlib import Path
import re
import tarfile
import urllib.request

URL = "https://deb.debian.org/debian/pool/main/s/scowl/scowl_2020.12.07.orig.tar.gz"
SHA256 = "5587667caa20c4891390c2d42dbb4d5c4c3f41bee77af1457ece3ba23fb859cc"
ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    data = args.archive.read_bytes() if args.archive else urllib.request.urlopen(URL, timeout=60).read()
    if hashlib.sha256(data).hexdigest() != SHA256:
        raise SystemExit("SCOWL archive checksum differs from the pinned source")
    words = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for member in archive.getmembers():
            match = re.fullmatch(r"scowl-2020.12.07/final/(english|american)-words\.(10|20|35|40|50)", member.name)
            if match:
                level = int(match[2])
                for word in archive.extractfile(member).read().decode("latin1").splitlines():
                    if re.fullmatch(r"[a-z]{1,24}", word):
                        words[word] = min(level, words.get(word, 100))
        # Retain the applicable legal notices; historical correspondence contains personal contact details and is
        # not a licence condition. No level above 50 is used, so its notices are not part of this derivative.
        notice = archive.extractfile("scowl-2020.12.07/Copyright").read().decode("utf-8")
        collective = notice[:notice.index("Alan Beale")]
        wordnet = notice[notice.index("  This software and database"):notice.index("The 40 level")]
        varcon = notice[notice.index("  Copyright 2000-2016"):]
    output = ROOT / "app/keyboard/words.tsv.gz"
    # Keep every common class, trimming only the longest rare entries to bound startup memory and search work.
    words = {w: words[w] for w in sorted(words, key=lambda w: (words[w], len(w), w))[:60000]}
    output.parent.mkdir(parents=True, exist_ok=True)
    payload = "".join(f"{word}\t{words[word]}\n" for word in sorted(words)).encode("utf-8")
    output.write_bytes(gzip.compress(payload, mtime=0))
    licences = ROOT / "LICENSES"
    licences.mkdir(exist_ok=True)
    (licences / "keyboard-words.txt").write_text(
        "SCOWL 2020.12.07: modified selection of lowercase ASCII words, levels 10-50.\n"
        "Source and recipe: tools/build_keyboard_words.py.\n"
        "Credits: Kevin Atkinson; Alan Beale (12Dicts, public domain); Brian Kelk (public domain);\n"
        "Grady Ward (public domain). Applicable permissive notices follow.\n\n"
        + collective + wordnet + varcon, encoding="utf-8")
    print(f"Keyboard dictionary: {len(words)} words, levels 10-50")


if __name__ == "__main__":
    main()
