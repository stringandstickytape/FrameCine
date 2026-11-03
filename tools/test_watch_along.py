#!/usr/bin/env python3
"""Tests for tools/watch_along.py with a fake headset (standard library only):  python tools/test_watch_along.py"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import watch_along as w  # noqa: E402

STATE = {"path": "smb://nas/films/Quiet Water (2019).mkv?token=abc", "title": "Quiet Water", "playing": True,
         "position": 3723.4, "duration": 6300.0, "mode": "flat_mono", "environment": "cinema"}
CHAPTERS = {"count": 12, "current": 7, "title": "The Chase",
            "list": [{"n": n, "title": "C%d" % n, "start": 600.0 * (n - 1), "end": 600.0 * n} for n in range(1, 13)]}


def lines(cur, total=500):
    return [{"i": i, "start": 10.0 * i, "end": 10.0 * i + 2, "text": "line %d" % i, "before": "", "after": ""}
            for i in range(max(cur - 8, 0), min(cur + 8, total))]


def fake(state=STATE, chapters=CHAPTERS, script=None, fail=()):
    calls = []

    def send(cmd, args):
        calls.append((cmd, args))
        if cmd in fail:
            return {"ok": False, "error": "%s failed" % cmd}
        if cmd == "get":
            return {"ok": True, "result": {"state": state, "settings": {}}}
        if cmd == "chapters":
            return {"ok": True, "result": chapters}
        if cmd == "script_lines":
            return {"ok": True, "result": script or {"total": 500, "current": 372, "offset": 364, "track": "t3",
                                                      "lines": lines(372)}}
        return {"ok": False, "error": "no command %s" % cmd}
    return send, calls


class Gather(unittest.TestCase):
    def test_full_context(self):
        send, calls = fake()
        ctx = w.gather(send, "  who is the man in the hat? ", lines=4)
        self.assertEqual(ctx["question"], "who is the man in the hat?")
        self.assertEqual(ctx["file"], "Quiet Water (2019).mkv")  # no query part (a token) is shown
        self.assertEqual(ctx["chapter"], {"n": 7, "count": 12, "title": "The Chase", "start": 3600.0})
        self.assertEqual([x["i"] for x in ctx["subtitles"]["lines"]], [369, 370, 371, 372])  # said, not to come
        self.assertEqual(calls[2], ("script_lines", {"offset": -1, "count": 8}))
        block = w.format_block(ctx)
        for part in ("Question: who is the man in the hat?", 'File: Quiet Water (2019).mkv ("Quiet Water")',
                     "Position: 1:02:03 of 1:45:00 (playing)", 'Chapter: 7/12 "The Chase" (from 1:00:00)',
                     "Mode: flat_mono; environment cinema", "Last 4 subtitle lines (line 373 of 500):",
                     "  [1:02:00] line 372", "answer"):
            self.assertIn(part, block)
        self.assertNotIn("token", block)

    def test_missing_parts_are_noted(self):
        send, _ = fake(chapters={"count": 0, "current": 0, "title": "", "list": []}, fail=("script_lines",))
        ctx = w.gather(send, "q")
        self.assertNotIn("chapter", ctx)
        self.assertIn("subtitle text: script_lines failed", ctx["notes"])
        block = w.format_block(ctx)
        self.assertIn("(subtitle text: script_lines failed)", block)
        self.assertNotIn("Chapter:", block)

    def test_no_headset(self):
        send, calls = fake(fail=("get",))
        ctx = w.gather(send, "q")
        self.assertEqual(len(calls), 1)
        self.assertNotIn("file", ctx)
        self.assertIn("(no state: get failed)", w.format_block(ctx))

    def test_before_the_first_line(self):
        send, _ = fake(script={"total": 10, "current": -1, "offset": 0, "track": "t3", "lines": lines(0, 10)})
        ctx = w.gather(send, "q")
        self.assertEqual(ctx["subtitles"]["lines"], [])
        self.assertIn("Subtitle lines: none said yet", w.format_block(ctx))

    def test_no_lines_asked(self):
        send, calls = fake()
        w.gather(send, "q", lines=0)
        self.assertNotIn("script_lines", [c[0] for c in calls])


class Answer(unittest.TestCase):
    def test_card_args(self):
        self.assertEqual(w.card_args(" He is the brother. ", "Who is he?"), {"text": "He is the brother.",
                                                                            "title": "Who is he?"})
        self.assertEqual(w.card_args("x", "", 0)["seconds"], 0.0)
        self.assertLessEqual(len(w.card_args("x", "t" * 100)["title"]), w.TITLE_MAX)

    def test_question_title(self):
        self.assertEqual(w.question_title("who   is\nhe?"), "who is he?")
        long = w.question_title("word " * 30)
        self.assertTrue(long.endswith("...") and len(long) <= w.TITLE_MAX)

    def test_clock(self):
        self.assertEqual(w.clock(59.9), "0:59")
        self.assertEqual(w.clock(3723), "1:02:03")
        self.assertEqual(w.clock(None), "0:00")


if __name__ == "__main__":
    unittest.main()
