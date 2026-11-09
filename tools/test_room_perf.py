#!/usr/bin/env python3
"""Tests for tools/room_perf.py (standard library only): `format` on a made-up result (tools/fixtures/
room_perf_sample.json: four rooms at foveation off, 72 Hz, one over the budget, one note). Never reaches the headset.
  python3 tools/test_room_perf.py"""

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SAMPLE = os.path.join(HERE, "fixtures", "room_perf_sample.json")

checks = 0
failures = 0


def check(what, ok):
    global checks, failures
    checks += 1
    if not ok:
        failures += 1
        print("FAIL: %s" % what)


def main():
    p = subprocess.run([sys.executable, os.path.join(HERE, "room_perf.py"), "format", SAMPLE], capture_output=True,
                       text=True, encoding="utf-8")
    check("format exits 0 (%d: %s)" % (p.returncode, p.stderr.strip()), p.returncode == 0)
    md = p.stdout
    lines = md.splitlines()
    check("the title", lines[:1] == ["# The rooms on the headset"])
    check("one table", sum(1 for x in lines if x.startswith("|---")) == 1)
    rows = [x for x in lines if x.startswith("| ") and not x.startswith("| Room ")]
    names = [x.split("|")[1].strip() for x in rows]
    check("four rows, by p95, the highest first (%s)" % names, names == ["Bathysphere", "Cinema", "TV 1953", "Void"])
    bold = [x for x in rows if "**" in x]
    check("the row over the budget has its p95 in bold (%s)" % bold,
          len(bold) == 1 and bold[0].split("|")[3].strip() == "**15.02**")
    void = [x.split("|") for x in rows if x.split("|")[1].strip() == "Void"]
    check("the baseline's cell over the Void is blank (%s)" % void, len(void) == 1 and void[0][4].strip() == "")
    check("the note is there",
          "- the panel was open: it is in the numbers; close it for the rooms alone" in lines)
    print("test_room_perf: %d checks, %s" % (checks, "all passed" if failures == 0 else "%d FAILED" % failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
