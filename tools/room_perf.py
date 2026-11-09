#!/usr/bin/env python3
"""Each room's GPU time on the headset (docs/environments/checks.md, "On the headset"): the headless checks cannot
measure what a room's shading costs; the headset can. This runs the dev link's perf_rooms over every room that ships
and writes the table to docs/environments/perf.md.

  tools/room_perf.py run [--seconds 10] [--settle 4] [--foveation off] [--rooms a,b,c]
                                     every room of app/environments/*.env.json (sorted), or the ones given, measured
                                     on the headset through `tools/listener.py send perf_rooms` (the Void first, the
                                     baseline); the result saved as docs/environments/perf.json and the table written
                                     to docs/environments/perf.md. Needs the listener running and the headset on the
                                     dev link; play a film first and close the panel.
  tools/room_perf.py format RESULT [OUT]
                                     the same table from a saved result (OUT: default stdout)

It never starts the listener and never reaches the headset by any other way: when the send fails it prints the
listener's error and exits 1, writing nothing. Python 3.8+, standard library only.
"""

import argparse
import datetime
import glob
import json
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENVIRONMENTS = os.path.join(REPO, "app", "environments")
LISTENER = os.path.join(REPO, "tools", "listener.py")
PERF_JSON = os.path.join(REPO, "docs", "environments", "perf.json")
PERF_MD = os.path.join(REPO, "docs", "environments", "perf.md")
BASELINE = "void"
PART_OF = ("Part of the environments engine: [`docs/environments.md`](../environments.md) has the design and says "
           "where each part is.")
# A table's columns: the heading and the key of a perf_rooms row it shows.
COLUMNS = [("Room", "name"), ("GPU ms", "gpu_ms"), ("p95", "gpu_ms_p95"), ("over the Void", "delta_gpu_ms"),
           ("CPU ms", "cpu_ms"), ("fps", "fps"), ("dropped", "dropped")]


def room_ids():
    """The rooms that ship: app/environments/*.env.json, their file names without .env.json, sorted."""
    return sorted(os.path.basename(p)[:-len(".env.json")] for p in glob.glob(os.path.join(ENVIRONMENTS, "*.env.json")))


def cell(v):
    # UNDECIDED (brief): how a number is shown: as the result gives it; a value the row lacks (no frames) is blank.
    return "" if v is None else str(v)


def format_markdown(result, today=None):
    """The page from a perf_rooms result: title, date, refresh rate and budget, the notes, a table a foveation level
    sorted by p95 (the highest first, over the budget in bold), and how it was measured."""
    today = today or datetime.date.today().isoformat()
    budget = float(result.get("budget_ms", 0.0))
    out = ["# The rooms on the headset", "", PART_OF, "",
           "Measured %s at %s Hz: a frame budget of %s ms." % (today, result.get("refresh_hz"), result.get("budget_ms")),
           ""]
    notes = result.get("notes") or []
    for n in notes:
        out.append("- %s" % n)
    if notes:
        out.append("")
    rows = result.get("rows") or []
    levels = list(result.get("levels") or [])
    for r in rows:
        if r.get("foveation") not in levels:
            levels.append(r.get("foveation"))
    for level in levels:
        mine = [r for r in rows if r.get("foveation") == level]
        if not mine:
            continue
        mine.sort(key=lambda r: float(r.get("gpu_ms_p95", -1.0)), reverse=True)
        # UNDECIDED (brief): each table under a heading naming its foveation level.
        out.append("## Foveation %s" % level)
        out.append("")
        out.append("| %s |" % " | ".join(c[0] for c in COLUMNS))
        out.append("|%s" % ("---|" * len(COLUMNS)))
        for r in mine:
            cells = []
            for _, key in COLUMNS:
                v = cell(r.get(key))
                if key == "gpu_ms_p95" and r.get(key) is not None and float(r[key]) > budget:
                    v = "**%s**" % v
                cells.append(v)
            out.append("| %s |" % " | ".join(cells))
        out.append("")
    out.append("Measured by `tools/room_perf.py run`; play a film first and close the panel.")
    return "\n".join(out) + "\n"


def write(path, text):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def cmd_format(args):
    with open(args.result, encoding="utf-8") as f:
        result = json.load(f)
    text = format_markdown(result)
    if args.out:
        write(args.out, text)
    else:
        sys.stdout.write(text)
    return 0


def cmd_run(args):
    rooms = [r.strip() for r in args.rooms.split(",") if r.strip()] if args.rooms else room_ids()
    levels = [x.strip() for x in args.foveation.split(",") if x.strip()]
    timeout = (len(rooms) + 1) * len(levels) * (args.settle + args.seconds) + 60
    cmd = [sys.executable, LISTENER, "send", "-t", "%g" % timeout, "perf_rooms", "rooms=" + ",".join(rooms),
           "foveation=" + ",".join(levels), "baseline=" + BASELINE, "settle=%g" % args.settle,
           "seconds=%g" % args.seconds]
    print("measuring %d rooms at %s on the headset (up to %.0f s)" % (len(rooms), ", ".join(levels), timeout),
          flush=True)
    p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode != 0:
        print((p.stderr.strip() + "\n" + p.stdout.strip()).strip(), file=sys.stderr)
        return 1
    try:
        result = json.loads(p.stdout)
    except ValueError:
        print("the listener's answer is not JSON:\n%s" % p.stdout.strip(), file=sys.stderr)
        return 1
    if not isinstance(result, dict) or "rows" not in result:
        print("the listener's answer has no rows:\n%s" % p.stdout.strip(), file=sys.stderr)
        return 1
    write(PERF_JSON, json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    write(PERF_MD, format_markdown(result))
    print("%s, %s" % (os.path.relpath(PERF_JSON, REPO), os.path.relpath(PERF_MD, REPO)))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--seconds", type=float, default=10.0)
    r.add_argument("--settle", type=float, default=4.0)
    r.add_argument("--foveation", default="off")
    r.add_argument("--rooms", default="")
    f = sub.add_parser("format")
    f.add_argument("result")
    f.add_argument("out", nargs="?")
    args = p.parse_args(argv)
    return {"run": cmd_run, "format": cmd_format}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
