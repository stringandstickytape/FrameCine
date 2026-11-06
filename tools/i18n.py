#!/usr/bin/env python3
"""The menus' languages (docs/i18n.md): the key list, the check of a translation, and the Chinese font.

  tools/i18n.py extract              every key in app/ -> app/locale/messages.pot
  tools/i18n.py check [PO ...]       keys of messages.pot missing from each .po (default: all of app/locale), and keys
                                     a .po has that the template does not; exit 1 when a key is missing
  tools/i18n.py merge PO             adds the template's missing keys to a .po (empty, to translate) and moves the keys
                                     it no longer has to the end as #~ lines
  tools/i18n.py font --source FONT   the Simplified Chinese subset (app/ui/fonts/NotoSansSC-Medium-subset.woff2) from a
                                     full Noto Sans SC: GB 2312 level 1 (3755 common characters), every character of
                                     the .po files, CJK punctuation. Needs fontTools (pip install fonttools).

Run from the repository root or anywhere in it (Python 3.8+, no packages but fontTools for `font`).

What counts as a key (the English text is the key, gettext style):
  tr("..."), tr_n("...", "...", n), atr(), atr_n(), TranslationServer.translate() / translate_plural()
  the text of a W builder (ui/pane_widgets.gd): W.label("..."), W.caps, W.section, W.button, W.toggle, W.help,
      W.slider_row, and every literal of W.choices([...]); only when the text is a literal (or literals joined by +)
  a literal given to text, tooltip_text or placeholder_text: x.text = "...", or "..." if c else "..."
  every literal on a line that ends with the comment `# i18n`, dictionary keys left out
  between `# i18n: begin` and `# i18n: end`: the same; `# i18n: begin name` takes only the values of "name": ...
  the palettes' names in app/ui/themes/tablet.json
Text with no letter in it (numbers, "...") is never a key. Not scanned: app/tests and app/tools. In app/scripts/dev
(the dev link) and app/scripts/assistant (what an assistant reads) only tr() and the markers count, not the builders
or text = "..." (docs/i18n.md, "Not translated").
"""

import argparse
import io
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(REPO, "app")
LOCALE = os.path.join(APP, "locale")
POT = os.path.join(LOCALE, "messages.pot")
FONT_OUT = os.path.join(APP, "ui", "fonts", "NotoSansSC-Medium-subset.woff2")
SKIP_DIRS = ["tests", "tools", ".godot"]
## Only explicit keys (tr(), markers) here.
EXPLICIT_DIRS = [os.path.join("scripts", "dev"), os.path.join("scripts", "assistant")]
CALLS = {"tr": 1, "atr": 1, "tr_n": 2, "atr_n": 2}
SERVER_CALLS = {"translate": 1, "translate_plural": 2}
BUILDERS = {"label", "caps", "section", "button", "toggle", "help", "slider_row"}
TEXT_PROPS = {"text", "tooltip_text", "placeholder_text"}
JSON_SOURCES = [(os.path.join("ui", "themes", "tablet.json"), ["palettes", "*", "name"])]
LETTER = re.compile(r"[A-Za-z]")


# --- A small GDScript lexer: strings, names, punctuation and comments, with their lines -------------------------

def lex(text):
    toks = []
    i, line, n = 0, 1, len(text)
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            i += 1
        elif c in " \t\r\\":
            i += 1
        elif c == "#":
            j = text.find("\n", i)
            j = n if j < 0 else j
            toks.append(("comment", text[i + 1:j].strip(), line))
            i = j
        elif c in "\"'" or (c in "&^" and i + 1 < n and text[i + 1] in "\"'") or (c == "r" and i + 1 < n and text[i + 1] in "\"'"):
            prefix = ""
            if c in "&^r":
                prefix = c
                i += 1
                c = text[i]
            triple = text.startswith(c * 3, i)
            q = c * 3 if triple else c
            j = i + len(q)
            buf = []
            start_line = line
            while j < n and not text.startswith(q, j):
                ch = text[j]
                if ch == "\\" and prefix != "r" and j + 1 < n:
                    nxt = text[j + 1]
                    buf.append({"n": "\n", "t": "\t", "r": "\r", "\\": "\\", "\"": "\"", "'": "'"}.get(nxt, "\\" + nxt))
                    if nxt == "\n":
                        line += 1
                    j += 2
                    continue
                if ch == "\n":
                    line += 1
                buf.append(ch)
                j += 1
            kind = "string" if prefix in ("", "r") else "name_string"
            toks.append((kind, "".join(buf), start_line))
            i = j + len(q)
        elif c.isalpha() or c == "_":
            j = i
            while j < n and (text[j].isalnum() or text[j] == "_"):
                j += 1
            toks.append(("name", text[i:j], line))
            i = j
        elif c.isdigit():
            j = i
            while j < n and (text[j].isalnum() or text[j] in "._"):
                j += 1
            toks.append(("number", text[i:j], line))
            i = j
        else:
            two = text[i:i + 2]
            if two in ("==", "!=", "<=", ">=", "->", "+=", "-=", ":=", "**", "&&", "||"):
                toks.append(("punct", two, line))
                i += 2
            else:
                toks.append(("punct", c, line))
                i += 1
    return toks


def _literal_arg(code, k):
    """Literals joined by + from token k, then the token after them: (text, next index) or (None, k)."""
    if k >= len(code) or code[k][0] != "string":
        return None, k
    parts = [code[k][1]]
    k += 1
    while k + 1 < len(code) and code[k] == ("punct", "+", code[k][2]) and code[k + 1][0] == "string":
        parts.append(code[k + 1][1])
        k += 2
    return "".join(parts), k


def keys_of_gd(path, rel, implicit=True):
    """[(msgid, plural or None, "rel:line"), ...] of one script."""
    text = io.open(path, encoding="utf-8").read()
    toks = lex(text)
    code = [t for t in toks if t[0] != "comment"]
    out = []

    def add(s, plural, line):
        if s and LETTER.search(s):
            out.append((s, plural, "%s:%d" % (rel, line)))

    # Calls and builders.
    for k, t in enumerate(code):
        if t[0] != "name" or k + 1 >= len(code) or code[k + 1][1] != "(":
            continue
        prev = code[k - 1][1] if k > 0 else ""
        prev2 = code[k - 2][1] if k > 1 else ""
        nargs = 0
        if t[1] in CALLS and prev != ".":
            nargs = CALLS[t[1]]
        elif t[1] in CALLS and prev == "." and prev2 != "TranslationServer":
            nargs = CALLS[t[1]]
        elif t[1] in SERVER_CALLS and prev == "." and prev2 == "TranslationServer":
            nargs = SERVER_CALLS[t[1]]
        if nargs:
            s, j = _literal_arg(code, k + 2)
            if s is None or j >= len(code) or code[j][1] not in (",", ")"):
                continue
            plural = None
            if nargs == 2:
                if code[j][1] != ",":
                    continue
                plural, j2 = _literal_arg(code, j + 1)
                if plural is None:
                    continue
            add(s, plural, t[2])
            continue
        if not implicit:
            continue
        if prev == "." and prev2 == "W" and t[1] in BUILDERS:
            s, j = _literal_arg(code, k + 2)
            if s is not None and j < len(code) and code[j][1] in (",", ")"):
                add(s, None, t[2])
        elif prev == "." and prev2 == "W" and t[1] == "choices" and k + 2 < len(code) and code[k + 2][1] == "[":
            j = k + 3
            found = []
            while j < len(code) and code[j][0] == "string":
                found.append(code[j])
                j += 1
                if j < len(code) and code[j][1] == ",":
                    j += 1
            if j < len(code) and code[j][1] == "]":
                for f in found:
                    add(f[1], None, f[2])
    # text = "..." / "..." if c else "..."
    for k, t in enumerate(code):
        if not implicit or t[0] != "name" or t[1] not in TEXT_PROPS or k + 2 >= len(code) or code[k + 1][1] != "=":
            continue
        s = code[k + 2]
        if s[0] != "string":
            continue
        joined, j0 = _literal_arg(code, k + 2)
        after = code[j0] if j0 < len(code) else ("end", "", 10 ** 9)
        if after[2] > code[j0 - 1][2] or after[1] == ")":
            add(joined, None, s[2])
        elif j0 == k + 3 and after == ("name", "if", after[2]):
            for j in range(k + 4, min(k + 20, len(code) - 1)):
                if code[j] == ("name", "else", code[j][2]) and code[j + 1][0] == "string":
                    end = code[j + 2] if j + 2 < len(code) else ("end", "", 10 ** 9)
                    if end[2] > code[j + 1][2] or end[1] == ")":
                        add(s[1], None, s[2])
                        add(code[j + 1][1], None, code[j + 1][2])
                    break
    # Markers.
    marked_lines = set(t[2] for t in toks if t[0] == "comment" and t[1] == "i18n")
    block = None
    blocks = []
    for t in toks:
        if t[0] != "comment":
            continue
        m = re.match(r"i18n:\s*begin\b\s*(.*)$", t[1])
        if m:
            block = [t[2], None, [f.strip() for f in m.group(1).split(",") if f.strip()]]
        elif re.match(r"i18n:\s*end\b", t[1]) and block is not None:
            block[1] = t[2]
            blocks.append(block)
            block = None
    k = 0
    while k < len(code):
        t = code[k]
        if t[0] != "string":
            k += 1
            continue
        # Literals joined by + are one text.
        s, nxt = _literal_arg(code, k)
        is_key = nxt < len(code) and code[nxt][1] == ":"
        if t[2] in marked_lines and not is_key:
            add(s, None, t[2])
        else:
            for b in blocks:
                if b[0] < t[2] < b[1] and not is_key:
                    fields = b[2]
                    if not fields:
                        add(s, None, t[2])
                    elif k >= 2 and code[k - 1][1] == ":" and code[k - 2][0] == "string" and code[k - 2][1] in fields:
                        add(s, None, t[2])
        k = nxt
    return out


def keys_of_json(path, rel, walk):
    data = json.load(io.open(path, encoding="utf-8"))
    out = []

    def go(node, steps):
        if not steps:
            if isinstance(node, str) and LETTER.search(node):
                out.append((node, None, rel))
            return
        step = steps[0]
        if step == "*":
            items = node.values() if isinstance(node, dict) else node if isinstance(node, list) else []
            for v in items:
                go(v, steps[1:])
        elif isinstance(node, dict) and step in node:
            go(node[step], steps[1:])

    go(data, walk)
    return out


def collect():
    """Keys in order of first use: {msgid: {"plural": str or None, "refs": [...]}} (an ordered dict)."""
    keys = {}
    skip = [os.path.join(APP, d) for d in SKIP_DIRS]
    files = []
    for root, dirs, names in os.walk(APP):
        dirs[:] = sorted(d for d in dirs if os.path.join(root, d) not in skip)
        for name in sorted(names):
            if name.endswith(".gd"):
                files.append(os.path.join(root, name))
    found = []
    for path in files:
        rel = os.path.relpath(path, APP).replace(os.sep, "/")
        implicit = not any(rel.startswith(d.replace(os.sep, "/") + "/") for d in EXPLICIT_DIRS)
        found += keys_of_gd(path, rel, implicit)
    for rel, walk in JSON_SOURCES:
        found += keys_of_json(os.path.join(APP, rel), rel.replace(os.sep, "/"), walk)
    for msgid, plural, ref in found:
        e = keys.setdefault(msgid, {"plural": None, "refs": []})
        if plural:
            e["plural"] = plural
        if ref not in e["refs"]:
            e["refs"].append(ref)
    return keys


# --- gettext files ------------------------------------------------------------------------------------------------

def po_quote(s):
    s = s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\t", "\\t")
    if "\n" in s.rstrip("\n"):
        lines = s.split("\n")
        parts = [l + "\\n" for l in lines[:-1]] + ([lines[-1]] if lines[-1] else [])
        return "\"\"\n" + "\n".join("\"%s\"" % p for p in parts)
    return "\"%s\"" % s.replace("\n", "\\n")


def po_unquote(s):
    s = s.strip()
    if len(s) < 2:
        return ""
    s = s[1:-1]
    out, i = [], 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            out.append({"n": "\n", "t": "\t", "\\": "\\", "\"": "\""}.get(s[i + 1], s[i + 1]))
            i += 2
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


def read_po(path):
    """[{"id", "plural", "strs": [..], "comments": [..], "fuzzy", "obsolete"}] in file order; the header first."""
    entries = []
    cur = None
    field = None

    def new():
        return {"id": None, "plural": None, "strs": [], "comments": [], "fuzzy": False, "obsolete": False}

    for raw in io.open(path, encoding="utf-8").read().split("\n"):
        line = raw.strip()
        obsolete = line.startswith("#~")
        if obsolete:
            line = line[2:].strip()
        if not line:
            if cur is not None and cur["id"] is not None:
                entries.append(cur)
                cur = None
            continue
        if line.startswith("#") and not obsolete:
            if cur is not None and cur["id"] is not None:
                entries.append(cur)
                cur = None
            cur = cur or new()
            cur["comments"].append(raw.rstrip())
            if line.startswith("#,") and "fuzzy" in line:
                cur["fuzzy"] = True
            continue
        if line.startswith("msgid_plural"):
            cur["plural"] = po_unquote(line[12:])
            field = ("plural", None)
        elif line.startswith("msgid"):
            if cur is not None and cur["id"] is not None:
                entries.append(cur)
                cur = None
            cur = cur or new()
            cur["id"] = po_unquote(line[5:])
            cur["obsolete"] = obsolete
            field = ("id", None)
        elif line.startswith("msgstr["):
            idx = int(line[7:line.index("]")])
            while len(cur["strs"]) <= idx:
                cur["strs"].append("")
            cur["strs"][idx] = po_unquote(line[line.index("]") + 1:])
            field = ("str", idx)
        elif line.startswith("msgstr"):
            cur["strs"] = [po_unquote(line[6:])]
            field = ("str", 0)
        elif line.startswith("\"") and cur is not None:
            if field[0] == "id":
                cur["id"] += po_unquote(line)
            elif field[0] == "plural":
                cur["plural"] += po_unquote(line)
            elif field[0] == "str":
                cur["strs"][field[1]] += po_unquote(line)
    if cur is not None and cur["id"] is not None:
        entries.append(cur)
    return entries


def write_entry(f, e, obsolete=False):
    pre = "#~ " if obsolete else ""
    for c in e.get("comments", []):
        f.write(c + "\n")
    f.write(pre + "msgid " + po_quote(e["id"]).replace("\n", "\n" + pre) + "\n")
    if e.get("plural"):
        f.write(pre + "msgid_plural " + po_quote(e["plural"]).replace("\n", "\n" + pre) + "\n")
        strs = e.get("strs") or ["", ""]
        for i, s in enumerate(strs):
            f.write(pre + "msgstr[%d] " % i + po_quote(s).replace("\n", "\n" + pre) + "\n")
    else:
        f.write(pre + "msgstr " + po_quote((e.get("strs") or [""])[0]).replace("\n", "\n" + pre) + "\n")
    f.write("\n")


POT_HEADER = """# The menus' text: every key of app/, written by tools/i18n.py extract. Do not edit; see docs/i18n.md.
msgid ""
msgstr ""
"Project-Id-Version: VR Video Player\\n"
"MIME-Version: 1.0\\n"
"Content-Type: text/plain; charset=UTF-8\\n"
"Content-Transfer-Encoding: 8-bit\\n"

"""


def cmd_extract(_args):
    keys = collect()
    os.makedirs(LOCALE, exist_ok=True)
    with io.open(POT, "w", encoding="utf-8", newline="\n") as f:
        f.write(POT_HEADER)
        for msgid, e in keys.items():
            refs = e["refs"]
            comments = ["#: " + " ".join(refs[i:i + 4]) for i in range(0, len(refs), 4)]
            if "%" in msgid:
                comments.append("#, c-format")
            write_entry(f, {"id": msgid, "plural": e["plural"], "strs": ["", ""] if e["plural"] else [""],
                            "comments": comments})
    print("%s: %d keys" % (os.path.relpath(POT, REPO), len(keys)))
    return 0


def pot_keys():
    return [(e["id"], e["plural"]) for e in read_po(POT) if e["id"]]


def cmd_check(args):
    pots = pot_keys()
    ids = set(k for k, _ in pots)
    paths = args.po or sorted(os.path.join(LOCALE, n) for n in os.listdir(LOCALE) if n.endswith(".po"))
    bad = 0
    for path in paths:
        entries = [e for e in read_po(path) if e["id"] and not e["obsolete"]]
        have = {e["id"]: e for e in entries}
        missing = [k for k, _ in pots if k not in have or not any(s.strip() for s in have[k]["strs"])]
        extra = [k for k in have if k not in ids]
        fuzzy = [k for k in have if have[k]["fuzzy"]]
        holes = []
        for k, e in have.items():
            if k in ids and any(s.strip() for s in e["strs"]):
                want = sorted(re.findall(r"%[-+0 #]*[0-9]*(?:\.[0-9]+)?[sdifxXeEgGcov]", k))
                for s in e["strs"]:
                    if sorted(re.findall(r"%[-+0 #]*[0-9]*(?:\.[0-9]+)?[sdifxXeEgGcov]", s)) != want:
                        holes.append(k)
                        break
        name = os.path.relpath(path, REPO)
        print("%s: %d of %d keys translated, %d missing, %d not in the template, %d fuzzy (skipped by Godot), "
              "%d with other placeholders" % (name, len(pots) - len(missing), len(pots), len(missing), len(extra),
                                              len(fuzzy), len(holes)))
        for k in missing:
            print("  missing: %r" % k)
        for k in extra:
            print("  not in the template: %r" % k)
        for k in holes:
            print("  placeholders differ: %r" % k)
        bad += len(missing) + len(holes)
    return 1 if bad else 0


def cmd_merge(args):
    pots = pot_keys()
    entries = read_po(args.po)
    header = [e for e in entries if e["id"] == ""]
    have = {e["id"]: e for e in entries if e["id"]}
    ids = set(k for k, _ in pots)
    with io.open(args.po, "w", encoding="utf-8", newline="\n") as f:
        for e in header:
            write_entry(f, e)
        for k, plural in pots:
            e = have.get(k) or {"id": k, "plural": plural, "strs": ["", ""] if plural else [""], "comments": []}
            e["obsolete"] = False
            write_entry(f, e)
        for k, e in have.items():
            if k not in ids:
                write_entry(f, dict(e, comments=[]), obsolete=True)
    print("%s: %d keys, %d added, %d obsolete" % (args.po, len(pots), len([k for k, _ in pots if k not in have]),
                                                 len([k for k in have if k not in ids])))
    return 0


# --- The font -----------------------------------------------------------------------------------------------------

def gb2312_level1():
    out = []
    for hi in range(0xB0, 0xD8):
        for lo in range(0xA1, 0xFF):
            try:
                out.append(bytes([hi, lo]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return out


def cmd_font(args):
    try:
        from fontTools import subset
    except ImportError:
        print("fontTools is needed: pip install fonttools", file=sys.stderr)
        return 2
    chars = set(gb2312_level1())
    for name in os.listdir(LOCALE):
        if name.endswith(".po"):
            for e in read_po(os.path.join(LOCALE, name)):
                for s in e["strs"]:
                    chars.update(c for c in s if ord(c) > 0x7F)
    chars.update(chr(c) for c in range(0x3000, 0x3040))
    chars.update(chr(c) for c in range(0xFF01, 0xFF5F))
    chars.update("…·—–‘’“”•×÷°")
    options = subset.Options()
    options.layout_features = ["*"]
    options.hinting = False
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.notdef_outline = True
    # WOFF2: smaller, and the compressed bytes hold none of the runs that read as an e-mail address to
    # tools/privacy-check.sh (plain CFF charstrings did). Godot loads it as it is.
    options.flavor = "woff2"
    font = subset.load_font(args.source, options)
    sub = subset.Subsetter(options)
    sub.populate(unicodes=[ord(c) for c in chars])
    sub.subset(font)
    subset.save_font(font, args.out, options)
    print("%s: %d characters, %d bytes" % (os.path.relpath(args.out, REPO), len(chars), os.path.getsize(args.out)))
    return 0


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("extract")
    c = sub.add_parser("check")
    c.add_argument("po", nargs="*")
    m = sub.add_parser("merge")
    m.add_argument("po")
    fo = sub.add_parser("font")
    fo.add_argument("--source", required=True)
    fo.add_argument("--out", default=FONT_OUT)
    args = p.parse_args()
    return {"extract": cmd_extract, "check": cmd_check, "merge": cmd_merge, "font": cmd_font}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
