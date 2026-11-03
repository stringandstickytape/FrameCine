#!/usr/bin/env python3
"""Tests for tools/voice.py's grammar and runner (standard library only):  python tools/test_voice.py"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import voice  # noqa: E402

STATE = {"settings": {"volume": 0.5, "room_light": 0.8, "screen_height": 0.0, "screen_distance": 3.0,
                      "screen_width": 2.0}}


def actions(sentence):
    acts, unknown = voice.parse(sentence)
    return [(a.cmd, a.resolved(STATE)) for a in acts], unknown


class Grammar(unittest.TestCase):
    def check(self, sentence, expected, unknown=()):
        got, unk = actions(sentence)
        self.assertEqual(got, expected, sentence)
        self.assertEqual(list(unknown), unk, sentence)

    def test_examples_from_the_brief(self):
        self.check("dim the lights", [("set", {"setting": "room_light", "value": 0.4})])
        self.check("skip to chapter 9", [("chapter", {"n": 9})])
        self.check("move the screen up", [("set", {"setting": "screen_height", "value": 0.2})])

    def test_several_actions(self):
        self.check("Dim the lights and skip to chapter nine, then pause.",
                   [("set", {"setting": "room_light", "value": 0.4}), ("chapter", {"n": 9}), ("pause", {})])

    def test_numbers(self):
        self.check("skip forward twenty five seconds", [("seek", {"seconds": 25.0, "relative": True})])
        self.check("rewind a minute", [("seek", {"seconds": -60.0, "relative": True})])
        self.check("go to 1:20:05", [("seek", {"seconds": 4805})])
        self.check("go to 1 hour 20 minutes", [("seek", {"seconds": 4800.0})])
        self.check("set the volume to 40%", [("set", {"setting": "volume", "value": 0.4})])
        self.check("skip to the third chapter", [("chapter", {"n": 3})])

    def test_relative(self):
        self.check("louder", [("set", {"setting": "volume", "value": 0.65})])
        self.check("move the screen closer by 50 cm", [("set", {"setting": "screen_distance", "value": 2.5})])
        self.check("make it bigger", [("set", {"setting": "screen_width", "value": 2.5})])

    def test_rooms_and_toggles(self):
        self.check("go to the cinema", [("set", {"setting": "environment", "value": "cinema"})])
        self.check("switch to the room", [("set", {"setting": "environment", "value": "dim_room"})])
        self.check("subtitles off", [("subtitles", {"on": False})])
        self.check("recenter the screen", [("recenter", {})])
        self.check("go back to the start", [("seek", {"seconds": 0.0})])
        self.check("next chapter", [("chapter", {"step": 1})])
        self.check("next", [("next", {})])

    def test_line_keeps_its_and(self):
        self.check("pause and find where he says rock and roll",
                   [("pause", {}), ("jump_to_line", {"query": "rock and roll"})])

    def test_unknown(self):
        self.check("make me a sandwich", [], ["make me a sandwich"])
        self.check("play and juggle", [("play", {})], ["juggle"])


class Runner(unittest.TestCase):
    def test_state_fetched_once_and_carried(self):
        sent, gets = [], []

        def send(cmd, args):
            sent.append((cmd, args))
            return {"ok": True}

        def get_state():
            gets.append(1)
            return {"settings": {"volume": 0.5}}

        report = voice.run("louder and louder", send, get_state)
        self.assertEqual(len(gets), 1)
        self.assertEqual([round(a["value"], 2) for _, a in sent], [0.65, 0.8])
        self.assertTrue(report["ok"])

    def test_failure_reported(self):
        report = voice.run("skip to chapter 40", lambda c, a: {"ok": False, "error": "there are 5 chapters"})
        self.assertFalse(report["ok"])
        self.assertEqual(report["actions"][0]["error"], "there are 5 chapters")

    def test_transcriber_command(self):
        fake = os.path.join(os.path.dirname(os.path.abspath(__file__)), "test_voice.py")
        cmd = '"%s" "%s" --echo {wav}' % (sys.executable, fake)
        self.assertEqual(voice.transcribe("clip.wav", cmd), "echo clip.wav")


if __name__ == "__main__":
    if "--echo" in sys.argv:
        print("echo", sys.argv[-1])
        sys.exit(0)
    unittest.main()
