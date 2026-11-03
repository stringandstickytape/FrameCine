#!/usr/bin/env python3
"""Tests for tools/steam_shortcuts.py on synthetic files (standard library only):  python tools/test_steam_shortcuts.py"""

import contextlib
import io
import os
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import steam_shortcuts as s  # noqa: E402


def cli(args):
    with contextlib.redirect_stdout(io.StringIO()):
        return s.main(args)


def kv_str(key, val):
    return b"\x01" + key.encode() + b"\0" + val.encode() + b"\0"


def kv_int(key, val):
    return b"\x02" + key.encode() + b"\0" + struct.pack("<i", val)


def sample():
    """One entry, written the way Steam writes it (lower-case 'appname' in older files, a tags map with one tag)."""
    entry = (kv_int("appid", -1234567) + kv_str("appname", "Some Tool") + kv_str("Exe", '"/opt/tool/run"')
             + kv_str("StartDir", '"/opt/tool/"') + kv_int("OpenVR", 0) + kv_int("LastPlayTime", 1700000000)
             + b"\x00tags\0" + kv_str("0", "favourite") + b"\x08")
    return b"\x00shortcuts\0" + b"\x000\0" + entry + b"\x08" + b"\x08" + b"\x08"


class Format(unittest.TestCase):
    def test_round_trip_is_byte_exact(self):
        data = sample()
        root, tail = s.parse(data)
        self.assertEqual(s.dump(root, tail), data)
        entry = s.shortcuts_of(root)[0][2]
        self.assertEqual(s.get(entry, "AppName"), "Some Tool")  # key case differs between Steam versions
        self.assertEqual(s.get(entry, "appid"), -1234567)

    def test_other_types_round_trip(self):
        data = (b"\x00shortcuts\0\x000\0" + b"\x03f\0" + struct.pack("<f", 1.5) + b"\x07u\0" + struct.pack("<Q", 2**63)
                + b"\x0ai\0" + struct.pack("<q", -5) + b"\x08\x08\x08")
        root, tail = s.parse(data)
        self.assertEqual(s.dump(root, tail), data)

    def test_bad_files_are_refused(self):
        for bad in (b"", b"\x00shortcuts\0", b"\x05x\0\x08", sample() + b"junk"):
            with self.assertRaises((s.VdfError, struct.error)):
                s.parse(bad)

    def test_app_id_has_the_top_bit(self):
        aid = s.app_id('"/home/steamos/vr-video-player/run.sh"', "VR Video Player")
        self.assertLess(aid, 0)  # top bit set, stored signed
        self.assertEqual(aid, s.app_id('"/home/steamos/vr-video-player/run.sh"', "VR Video Player"))


class Edit(unittest.TestCase):
    EXE = "/home/steamos/vr-video-player/run.sh"

    def test_add_then_update_then_remove(self):
        root, tail = s.parse(sample())
        self.assertEqual(s.add(root, "VR Video Player", self.EXE, "/home/steamos/vr-video-player"), "added")
        sc = s.shortcuts_of(root)
        self.assertEqual([k for _t, k, _v in sc], ["0", "1"])
        first_id = s.get(sc[1][2], "appid")
        self.assertEqual(s.get(sc[1][2], "Exe"), '"%s"' % self.EXE)
        self.assertEqual(s.get(sc[1][2], "OpenVR"), 0)
        root2, _ = s.parse(s.dump(root, tail))  # what we write, we can read
        self.assertEqual(len(s.shortcuts_of(root2)), 2)

        self.assertEqual(s.add(root, "VR Video Player", self.EXE, "/x", launch_options="--env=cinema", openvr=True),
                         "updated")
        self.assertEqual(len(sc), 2)
        self.assertEqual(s.get(sc[1][2], "appid"), first_id)  # the slot keeps its id (and its library art)
        self.assertEqual(s.get(sc[1][2], "LaunchOptions"), "--env=cinema")
        self.assertEqual(s.get(sc[1][2], "OpenVR"), 1)

        self.assertEqual(s.remove(root, self.EXE), 1)
        self.assertEqual(s.dump(root, tail), sample())  # back to the original bytes

    def test_remove_renumbers(self):
        root, tail = s.parse(sample())
        s.remove(root, "/opt/tool/run")
        s.add(root, "A", "/a", "/")
        s.add(root, "B", "/b", "/")
        s.remove(root, "/a")
        self.assertEqual([(k, s.get(v, "AppName")) for _t, k, v in s.shortcuts_of(root)], [("0", "B")])

    def test_cli_backs_up_and_dry_run_writes_nothing(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "shortcuts.vdf")
            with open(path, "wb") as f:
                f.write(sample())
            cli(["--add", "--exe", self.EXE, "--file", path, "--dry-run"])
            with open(path, "rb") as f:
                self.assertEqual(f.read(), sample())
            self.assertEqual(os.listdir(d), ["shortcuts.vdf"])
            cli(["--add", "--exe", self.EXE, "--file", path])
            backups = [n for n in os.listdir(d) if n.startswith("shortcuts.vdf.bak-")]
            self.assertEqual(len(backups), 1)
            with open(os.path.join(d, backups[0]), "rb") as f:
                self.assertEqual(f.read(), sample())
            root, _ = s.load(path)
            self.assertEqual(len(s.shortcuts_of(root)), 2)

    def test_cli_creates_a_missing_file(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "shortcuts.vdf")
            cli(["--add", "--exe", self.EXE, "--file", path])
            root, _ = s.load(path)
            self.assertEqual(s.get(s.shortcuts_of(root)[0][2], "AppName"), "VR Video Player")


if __name__ == "__main__":
    unittest.main()
