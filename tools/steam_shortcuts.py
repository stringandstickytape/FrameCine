#!/usr/bin/env python3
"""Lists, adds or removes a non-Steam shortcut in Steam's shortcuts.vdf (standard library only). docs/packaging.md.

This is a compatibility helper: it lets the player be started from the Steam library on the headset. It only edits
the per-user file userdata/<id>/config/shortcuts.vdf, after a time-stamped backup next to it. It needs no root.

    python3 steam_shortcuts.py --list [--file F]
    python3 steam_shortcuts.py --add --name "FrameCine" --exe ~/framecine/run.sh [--start-dir D]
                               [--icon I] [--launch-options "..."] [--openvr] [--file F] [--dry-run]
    python3 steam_shortcuts.py --remove --exe ~/framecine/run.sh [--file F] [--dry-run]

Without --file, every userdata/*/config/shortcuts.vdf under ~/.local/share/Steam and ~/.steam/steam is used (a
config folder with no shortcuts.vdf gets a new one). Steam reads the file at start and can write it back when it
quits, so close Steam (or restart it after the change) for the shortcut to stay.

The file is binary KeyValues: a type byte, a NUL-terminated key, then the value. Types: 0x00 map (ends with 0x08),
0x01 string (NUL-terminated UTF-8), 0x02 int32, 0x03 float32, 0x07 uint64, 0x0A int64; 0x08 ends a map. The root map
"shortcuts" holds maps keyed "0", "1", ... Parsing and writing are byte-exact for files this code did not change.
"""

import argparse
import glob
import os
import shutil
import struct
import sys
import time
import zlib

T_MAP, T_STR, T_INT, T_FLOAT, T_U64, T_END, T_I64 = 0x00, 0x01, 0x02, 0x03, 0x07, 0x08, 0x0A


class VdfError(ValueError):
    pass


# A map is a list of [type, key, value] (order and types kept, so an unchanged file writes back byte for byte).

def parse(data):
    pos = 0

    def cstr():
        nonlocal pos
        end = data.find(b"\0", pos)
        if end < 0:
            raise VdfError("unterminated string at %d" % pos)
        s = data[pos:end].decode("utf-8", "surrogateescape")
        pos = end + 1
        return s

    def read_map():
        nonlocal pos
        items = []
        while True:
            if pos >= len(data):
                raise VdfError("unexpected end of file")
            t = data[pos]
            pos += 1
            if t == T_END:
                return items
            key = cstr()
            if t == T_MAP:
                val = read_map()
            elif t == T_STR:
                val = cstr()
            elif t == T_INT:
                val = struct.unpack_from("<i", data, pos)[0]; pos += 4
            elif t == T_FLOAT:
                val = struct.unpack_from("<f", data, pos)[0]; pos += 4
            elif t == T_U64:
                val = struct.unpack_from("<Q", data, pos)[0]; pos += 8
            elif t == T_I64:
                val = struct.unpack_from("<q", data, pos)[0]; pos += 8
            else:
                raise VdfError("unknown type 0x%02x at %d" % (t, pos - 1))
            items.append([t, key, val])

    root = read_map()
    # The file ends with the end byte of the root map; some writers add one more.
    if pos < len(data) and data[pos:] != b"\x08":
        raise VdfError("%d trailing bytes" % (len(data) - pos))
    return root, data[pos:]


def dump(items, tail=b""):
    out = bytearray()

    def cstr(s):
        out.extend(s.encode("utf-8", "surrogateescape") + b"\0")

    def write_map(m):
        for t, key, val in m:
            out.append(t)
            cstr(key)
            if t == T_MAP:
                write_map(val)
            elif t == T_STR:
                cstr(val)
            elif t == T_INT:
                out.extend(struct.pack("<i", val))
            elif t == T_FLOAT:
                out.extend(struct.pack("<f", val))
            elif t == T_U64:
                out.extend(struct.pack("<Q", val))
            elif t == T_I64:
                out.extend(struct.pack("<q", val))
            else:
                raise VdfError("unknown type 0x%02x" % t)
        out.append(T_END)

    write_map(items)
    return bytes(out) + tail


def get(m, key, default=None):
    """Value of key in map m; Steam's own files differ in the case of some keys (appname / AppName)."""
    for _t, k, v in m:
        if k.lower() == key.lower():
            return v
    return default


def shortcuts_of(root):
    for t, k, v in root:
        if t == T_MAP and k.lower() == "shortcuts":
            return v
    shortcuts = []
    root.append([T_MAP, "shortcuts", shortcuts])
    return shortcuts


def app_id(exe_quoted, name):
    """The id other tools give a shortcut: CRC-32 of exe + name with the top bit set, as a signed int32. (Steam's
    own client now picks other ids for shortcuts it makes; it accepts these.)"""
    crc = (zlib.crc32((exe_quoted + name).encode("utf-8")) & 0xFFFFFFFF) | 0x80000000
    return struct.unpack("<i", struct.pack("<I", crc))[0]


def quote(path):
    return '"%s"' % path


def new_entry(name, exe, start_dir, icon="", launch_options="", openvr=False):
    exe_q = quote(exe)
    return [
        [T_INT, "appid", app_id(exe_q, name)],
        [T_STR, "AppName", name],
        [T_STR, "Exe", exe_q],
        [T_STR, "StartDir", quote(start_dir)],
        [T_STR, "icon", icon],
        [T_STR, "ShortcutPath", ""],
        [T_STR, "LaunchOptions", launch_options],
        [T_INT, "IsHidden", 0],
        [T_INT, "AllowDesktopConfig", 1],
        [T_INT, "AllowOverlay", 1],
        [T_INT, "OpenVR", 1 if openvr else 0],
        [T_INT, "Devkit", 0],
        [T_STR, "DevkitGameID", ""],
        [T_INT, "DevkitOverrideAppID", 0],
        [T_INT, "LastPlayTime", 0],
        [T_STR, "FlatpakAppID", ""],
        [T_STR, "sortas", ""],
        [T_MAP, "tags", []],
    ]


def same_exe(entry, exe):
    return (get(entry, "Exe", "") or "").strip('"') == exe


def add(root, name, exe, start_dir, icon="", launch_options="", openvr=False):
    """Adds the shortcut, or replaces the one with the same Exe (its slot and appid are kept). Returns 'added' or
    'updated'."""
    sc = shortcuts_of(root)
    entry = new_entry(name, exe, start_dir, icon, launch_options, openvr)
    for item in sc:
        if item[0] == T_MAP and same_exe(item[2], exe):
            old_id = get(item[2], "appid")
            if old_id is not None:
                entry[0][2] = old_id
            item[2] = entry
            return "updated"
    sc.append([T_MAP, str(len(sc)), entry])
    return "added"


def remove(root, exe):
    sc = shortcuts_of(root)
    keep = [it for it in sc if not (it[0] == T_MAP and same_exe(it[2], exe))]
    removed = len(sc) - len(keep)
    for i, it in enumerate(keep):  # Steam numbers the entries 0..n-1
        it[1] = str(i)
    sc[:] = keep
    return removed


def find_files():
    home = os.path.expanduser("~")
    found = []
    for base in (os.path.join(home, ".local/share/Steam"), os.path.join(home, ".steam/steam")):
        for cfg in glob.glob(os.path.join(base, "userdata", "*", "config")):
            path = os.path.realpath(os.path.join(cfg, "shortcuts.vdf"))
            if path not in found:
                found.append(path)
    return found


def load(path):
    if not os.path.exists(path):
        return [[T_MAP, "shortcuts", []]], b"\x08"
    with open(path, "rb") as f:
        return parse(f.read())


def save(path, root, tail, dry_run):
    data = dump(root, tail)
    parse(data)  # never write what we can't read back
    if dry_run:
        print("  (dry run: %d bytes not written)" % len(data))
        return
    if os.path.exists(path):
        backup = "%s.bak-%s" % (path, time.strftime("%Y%m%d-%H%M%S"))
        shutil.copy2(path, backup)
        print("  backup:", backup)
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, path)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    act = ap.add_mutually_exclusive_group(required=True)
    act.add_argument("--list", action="store_true")
    act.add_argument("--add", action="store_true")
    act.add_argument("--remove", action="store_true")
    ap.add_argument("--file", action="append", help="a shortcuts.vdf (default: every Steam user's)")
    ap.add_argument("--name", default="FrameCine")
    ap.add_argument("--exe")
    ap.add_argument("--start-dir")
    ap.add_argument("--icon", default="")
    ap.add_argument("--launch-options", default="")
    ap.add_argument("--openvr", action="store_true", help="mark the shortcut as a VR app (off by default)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)

    files = a.file or find_files()
    if not files:
        print("no Steam user folder found (userdata/*/config)", file=sys.stderr)
        return 1
    if (a.add or a.remove) and not a.exe:
        ap.error("--exe is needed")
    exe = os.path.abspath(os.path.expanduser(a.exe)) if a.exe else None
    for path in files:
        print(path)
        try:
            root, tail = load(path)
        except (OSError, VdfError, struct.error) as e:
            print("  can't read: %s" % e, file=sys.stderr)
            return 1
        if a.list:
            for _t, key, entry in shortcuts_of(root):
                print("  %s: %s  (appid %s)  %s" % (key, get(entry, "AppName", "?"), get(entry, "appid", "?"),
                                                   get(entry, "Exe", "?")))
            continue
        if a.add:
            start = os.path.abspath(os.path.expanduser(a.start_dir)) if a.start_dir else os.path.dirname(exe)
            print("  " + add(root, a.name, exe, start, a.icon, a.launch_options, a.openvr), a.name)
        else:
            print("  removed %d" % remove(root, exe))
        save(path, root, tail, a.dry_run)
    return 0


if __name__ == "__main__":
    sys.exit(main())
