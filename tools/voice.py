#!/usr/bin/env python3
"""Voice commands for the dev link (ideas #14 and #41; docs/dev/voice.md). Python 3.8+, standard library only.

The headset records a clip while a button is held and sends it to tools/listener.py as a `voice_clip` event. The
listener saves it and calls this module:

    transcribe(wav_path) -> text or None     the pluggable transcriber (below)
    parse(sentence) -> [Action]              the grammar: one sentence, several actions
    run(sentence, send, ...) -> report       resolves relative actions with one `get`, sends each command

Transcribers, the first that works:
    1. the command in VOICE_TRANSCRIBE_CMD (or `serve --transcriber`), with {wav} for the clip's path; its standard
       output is the text. For example a local speech-to-text program:  mytranscriber --model base.en --file {wav}
    2. a Python package if one is installed: faster_whisper, whisper or vosk (VOICE_MODEL picks the model; vosk needs
       VOSK_MODEL, a model folder). Nothing is downloaded by this module.
    3. none: the listener logs the clip's path and you type the sentence:  python tools/listener.py say dim the lights

    python tools/voice.py "dim the lights and skip to chapter 9"   # prints the actions (no headset needed)
"""

import json
import os
import re
import shlex
import subprocess
import sys

NUMBER_WORDS = {
    "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
    "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
    "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
    "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90, "hundred": 100, "a": None, "an": None,
}
ORDINALS = {"first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8,
            "ninth": 9, "tenth": 10, "last": -1}
FILLER = r"\b(please|can you|could you|would you|hey|okay|ok|now|just|for me|i want to|i'd like to|let's|lets)\b"
UNIT_SECONDS = {"s": 1, "sec": 1, "secs": 1, "second": 1, "seconds": 1, "m": 60, "min": 60, "mins": 60, "minute": 60,
                "minutes": 60, "h": 3600, "hour": 3600, "hours": 3600}
ROOM_WORDS = {"cinema": "cinema", "theatre": "cinema", "theater": "cinema", "movie theatre": "cinema",
              "room": "dim_room", "living room": "dim_room", "dim room": "dim_room", "lounge": "dim_room",
              "void": "void", "nothing": "void", "black": "void", "darkness": "void", "empty": "void", "space": "void"}

# Defaults for relative changes.
SCREEN_STEP_M = 0.2
DISTANCE_STEP_M = 0.5
SIZE_FACTOR = 1.25
VOLUME_STEP = 0.15
DIM_FACTOR = 0.5


class Action:
    """One command. `args` may hold callables of the app state (resolved in run()), for relative changes."""

    def __init__(self, cmd, args=None, said=""):
        self.cmd = cmd
        self.args = args or {}
        self.said = said

    def needs_state(self):
        return any(callable(v) for v in self.args.values())

    def resolved(self, state):
        return {k: (v(state) if callable(v) else v) for k, v in self.args.items()}

    def __repr__(self):
        return "%s %s" % (self.cmd, json.dumps({k: ("<from state>" if callable(v) else v)
                                                 for k, v in self.args.items()}))


# --- transcription ------------------------------------------------------------------------------------------------

# Words the speaker uses that a small model mishears without a hint (with it, small.en got "port 47800" right where
# base.en heard "8.0.0"; 2026-10-31).
VOCABULARY = ("Talking to Claude about the VR video player on the Steam Frame headset: the listener on port 47800, the "
              "pane, the dev link, SMB, HEVC, HDR, pairing.")
_WHISPER = None  # (model name, WhisperModel): loaded once per process, not per clip


def transcribe_pcm(pcm, rate=16000):
    """Live transcription of raw 16-bit mono PCM (the push-to-talk partials). faster_whisper only; None without it."""
    try:
        from faster_whisper import WhisperModel  # type: ignore
        import numpy  # type: ignore
    except Exception:  # noqa: BLE001
        return None
    if rate != 16000 or len(pcm) < 3200:
        return None
    model = os.environ.get("VOICE_MODEL", "small.en")
    global _WHISPER
    if _WHISPER is None or _WHISPER[0] != model:
        _WHISPER = (model, WhisperModel(model, device="cpu", compute_type="int8"))
    samples = numpy.frombuffer(bytes(pcm[: len(pcm) - len(pcm) % 2]), dtype=numpy.int16).astype(numpy.float32) / 32768.0
    # Greedy (beam 1) for speed: the final clip is transcribed again with beam search.
    segments, _ = _WHISPER[1].transcribe(samples, initial_prompt=VOCABULARY, beam_size=1)
    return " ".join(s.text.strip() for s in segments).strip() or None


def transcribe(wav_path, command=None):
    """The clip's text, or None when no transcriber is available or it fails. Never raises."""
    cmd = command or os.environ.get("VOICE_TRANSCRIBE_CMD")
    if cmd:
        try:
            # Windows keeps the quotes in non-POSIX mode; take them off.
            split = [w[1:-1] if len(w) > 1 and w[0] == w[-1] == '"' else w
                     for w in shlex.split(cmd, posix=os.name != "nt")]
            words = [w.replace("{wav}", wav_path) for w in split]
            if not any("{wav}" in w for w in split):
                words.append(wav_path)
            out = subprocess.run(words, capture_output=True, text=True, timeout=120)
            text = out.stdout.strip()
            if out.returncode == 0 and text:
                return " ".join(text.split())
        except (OSError, ValueError, subprocess.SubprocessError):
            pass
        return None
    model = os.environ.get("VOICE_MODEL", "small.en")
    try:
        from faster_whisper import WhisperModel  # type: ignore
        # The clip is our own 16 kHz mono 16-bit WAV: read the samples here rather than through faster_whisper's file
        # decoder, which needs a matching PyAV (faster-whisper 1.2.1 with PyAV 19 fails in av.open()).
        import wave
        import numpy  # type: ignore
        with wave.open(wav_path) as w:
            samples = numpy.frombuffer(w.readframes(w.getnframes()), dtype=numpy.int16).astype(numpy.float32) / 32768.0
        global _WHISPER
        if _WHISPER is None or _WHISPER[0] != model:
            _WHISPER = (model, WhisperModel(model, device="cpu", compute_type="int8"))
        segments, _ = _WHISPER[1].transcribe(samples, initial_prompt=VOCABULARY, beam_size=5)
        return " ".join(s.text.strip() for s in segments).strip() or None
    except Exception:  # noqa: BLE001 - optional package: any failure means "not available"
        pass
    try:
        import whisper  # type: ignore
        return (whisper.load_model(model).transcribe(wav_path).get("text") or "").strip() or None
    except Exception:  # noqa: BLE001
        pass
    try:
        import wave
        import vosk  # type: ignore
        folder = os.environ.get("VOSK_MODEL")
        if folder:
            rec = vosk.KaldiRecognizer(vosk.Model(folder), 16000)
            with wave.open(wav_path, "rb") as w:
                rec.AcceptWaveform(w.readframes(w.getnframes()))
            return (json.loads(rec.FinalResult()).get("text") or "").strip() or None
    except Exception:  # noqa: BLE001
        pass
    return None


def transcriber_name(command=None):
    if command or os.environ.get("VOICE_TRANSCRIBE_CMD"):
        return "command"
    for mod in ("faster_whisper", "whisper"):
        try:
            __import__(mod)
            return mod
        except Exception:  # noqa: BLE001
            pass
    if os.environ.get("VOSK_MODEL"):
        return "vosk"
    return None


# --- grammar ------------------------------------------------------------------------------------------------------

def _numbers(text):
    """'twenty five' -> '25', 'one hundred' -> '100', 'a minute' -> '1 minute'."""
    words = text.split()
    out, i = [], 0
    while i < len(words):
        w = words[i]
        if w in NUMBER_WORDS and NUMBER_WORDS[w] is not None:
            total, cur = 0, 0
            while i < len(words) and words[i] in NUMBER_WORDS and NUMBER_WORDS[words[i]] is not None:
                v = NUMBER_WORDS[words[i]]
                if v == 100:
                    cur = max(cur, 1) * 100
                else:
                    cur += v
                i += 1
            if i < len(words) and words[i] == "and" and i + 1 < len(words) and words[i + 1] in NUMBER_WORDS \
                    and NUMBER_WORDS[words[i + 1]] not in (None, 100):
                i += 1
                continue_value = 0
                while i < len(words) and words[i] in NUMBER_WORDS and NUMBER_WORDS[words[i]] not in (None, 100):
                    continue_value += NUMBER_WORDS[words[i]]
                    i += 1
                cur += continue_value
            total += cur
            out.append(str(total))
            continue
        if w in ("a", "an") and i + 1 < len(words) and words[i + 1].rstrip("s") in ("second", "minute", "hour"):
            out.append("1")
            i += 1
            continue
        if w in ("half",) and i + 2 < len(words) and words[i + 1] in ("a", "an") and words[i + 2] in ("minute", "hour"):
            out.append("30" if words[i + 2] == "minute" else "1800")
            out.append("seconds")
            i += 3
            continue
        out.append(w)
        i += 1
    return " ".join(out)


def normalise(sentence):
    s = sentence.lower().strip()
    s = re.sub(r"[“”\"]", "", s)
    s = re.sub(r"[!?.]+$", "", s)
    s = re.sub(r"(\d),(\d{3})", r"\1\2", s)
    s = re.sub(r"(\d+)\s*%", r"\1 percent", s)
    s = re.sub(r"\s*([,;])\s*", r" \1 ", s)
    s = re.sub(FILLER, " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return _numbers(s)


# A clause that takes the rest of the sentence as its text (no splitting after it).
LINE_RE = re.compile(r"^(?:find|jump to|go to|skip to|take me to|where)? ?(?:the )?(?:line|part|bit|scene|moment)?"
                     r" ?(?:where|when)? ?(?:(?:he|she|they|someone|somebody|it) )?(?:says?|said|say) (?P<q>.+)$")


def split_clauses(s):
    """Clauses joined by 'and', 'then', commas; a 'where he says ...' clause keeps the rest whole."""
    out = []
    rest = s
    while rest:
        m = re.search(r"\s*(?:,|;|\band then\b|\bthen\b|\band\b|\balso\b)\s*", rest)
        head = rest if not m else rest[:m.start()]
        if LINE_RE.match(head.strip()) or not m:
            if LINE_RE.match(head.strip()):
                head = rest
            out.append(head.strip())
            break
        out.append(head.strip())
        rest = rest[m.end():]
    return [c for c in out if c]


def _duration(text):
    """'1 hour 20 minutes', '1:20:00', '90 seconds', '20' (minutes when bare after 'minute'?) -> seconds or None."""
    text = text.strip()
    m = re.fullmatch(r"(\d+):(\d{1,2})(?::(\d{1,2}))?", text)
    if m:
        a, b, c = m.groups()
        return int(a) * 3600 + int(b) * 60 + int(c) if c is not None else int(a) * 60 + int(b)
    total, found = 0, False
    for n, unit in re.findall(r"(\d+(?:\.\d+)?) ?(hours?|h|minutes?|mins?|m|seconds?|secs?|s)\b", text):
        total += float(n) * UNIT_SECONDS[unit]
        found = True
    if found:
        return total
    if re.fullmatch(r"\d+(?:\.\d+)?", text):
        return float(text)
    return None


def _setting(name, fn):
    return lambda st: fn(float(st.get("settings", {}).get(name, 0.0)))


def _clamp(v, lo, hi):
    return max(lo, min(hi, v))


def parse_clause(c):
    """One clause -> [Action] ([] when nothing matches)."""
    A = lambda cmd, args=None: [Action(cmd, args, c)]  # noqa: E731
    m = LINE_RE.match(c)
    if m:
        return A("jump_to_line", {"query": m.group("q").strip()})
    # Playback.
    if re.fullmatch(r"(play|resume|continue|unpause|keep going|go|start)( (it|the (video|film|movie)|playing|playback))?", c):
        return A("play")
    if re.fullmatch(r"(pause|stop|hold on|hold it|wait|freeze)( (it|the (video|film|movie)|playing|playback|here))?", c):
        return A("pause")
    # Chapters (before seeking: "skip to chapter 9").
    m = re.fullmatch(r"(?:skip|go|jump|move)? ?(?:to )?(?:the )?chapter (\d+)", c) or \
        re.fullmatch(r"(?:skip|go|jump)? ?(?:to )?(?:the )?(\d+)(?:st|nd|rd|th)? chapter", c)
    if m:
        return A("chapter", {"n": int(m.group(1))})
    m = re.fullmatch(r"(?:skip|go|jump)? ?(?:to )?(?:the )?(" + "|".join(ORDINALS) + r") chapter", c)
    if m and ORDINALS[m.group(1)] > 0:
        return A("chapter", {"n": ORDINALS[m.group(1)]})
    if re.fullmatch(r"(?:skip|go|jump)? ?(?:to )?(?:the )?next chapter|chapter forward|skip (?:this |the )?chapter", c):
        return A("chapter", {"step": 1})
    if re.fullmatch(r"(?:go|jump)? ?(?:back )?(?:to )?(?:the )?(?:previous|last) chapter|chapter back", c):
        return A("chapter", {"step": -1})
    # Files.
    if re.fullmatch(r"(?:play |go to |skip to )?(?:the )?next( (file|video|one|film|movie|episode))?|skip (?:this )?(file|video|film|movie|episode)", c):
        return A("next")
    if re.fullmatch(r"(?:play |go to )?(?:the )?previous( (file|video|one|film|movie|episode))?|go back (?:a|one) (file|video|film|movie|episode)", c):
        return A("previous")
    # Seeking.
    m = re.fullmatch(r"(?:skip|go|jump|seek|fast)? ?(forward|forwards|ahead|back|backward|backwards|rewind)"
                     r"(?: by)? ?(.+)?", c) or re.fullmatch(r"(rewind)(?: by)? ?(.+)?", c)
    if m:
        amount = _duration(m.group(2) or "") if m.group(2) else 10.0
        if amount is not None:
            sign = -1 if m.group(1) in ("back", "backward", "backwards", "rewind") else 1
            return A("seek", {"seconds": sign * amount, "relative": True})
    if re.fullmatch(r"(?:go |skip |jump )?(?:back )?to the (?:start|beginning)|start over|restart( (it|the (video|film|movie)))?|from the (?:start|top)", c):
        return A("seek", {"seconds": 0.0})
    m = re.fullmatch(r"(?:go|skip|jump|seek)? ?to (?:minute |time )?(.+)", c)
    if m and not re.search(r"chapter|cinema|room|void|screen|light", m.group(1)):
        t = _duration(m.group(1))
        if t is not None:
            if re.fullmatch(r"\d+(?:\.\d+)?", m.group(1).strip()) and "minute" in c:
                t *= 60
            return A("seek", {"seconds": t})
    # Volume.
    m = re.fullmatch(r"(?:set |turn )?(?:the )?(?:volume|sound) (?:to |at )?(\d+)(?: percent)?", c)
    if m:
        return A("set", {"setting": "volume", "value": _clamp(int(m.group(1)) / 100.0, 0, 1)})
    if re.fullmatch(r"(?:turn (?:it |the volume |the sound )?up|volume up|louder|(?:make it )?louder|raise the volume|more volume)", c):
        return A("set", {"setting": "volume", "value": _setting("volume", lambda v: _clamp(v + VOLUME_STEP, 0, 1))})
    if re.fullmatch(r"(?:turn (?:it |the volume |the sound )?down|volume down|quieter|softer|(?:make it )?quieter|lower the volume|less volume)", c):
        return A("set", {"setting": "volume", "value": _setting("volume", lambda v: _clamp(v - VOLUME_STEP, 0, 1))})
    if re.fullmatch(r"mute(?: (?:it|the sound|the volume|audio))?|(?:turn )?(?:the )?sound off", c):
        return A("set", {"setting": "volume", "value": 0.0})
    if re.fullmatch(r"unmute(?: (?:it|the sound))?|(?:turn )?(?:the )?sound (?:back )?on", c):
        return A("set", {"setting": "volume", "value": 0.7})
    # Room light.
    m = re.fullmatch(r"(?:set |turn )?(?:the )?lights? (?:to |at )?(\d+)(?: percent)?", c)
    if m:
        return A("set", {"setting": "room_light", "value": _clamp(int(m.group(1)) / 100.0, 0, 2)})
    if re.fullmatch(r"(?:dim|lower) (?:the )?lights?|(?:the )?lights? down|(?:turn )?(?:the )?lights? down|darker|(?:make it )?darker", c):
        return A("set", {"setting": "room_light", "value": _setting("room_light", lambda v: round(v * DIM_FACTOR, 3))})
    if re.fullmatch(r"(?:turn )?(?:the )?lights? off|lights out|(?:make it )?dark", c):
        return A("set", {"setting": "room_light", "value": 0.0})
    if re.fullmatch(r"(?:turn )?(?:the )?lights? (?:on|up)|(?:raise|brighten) (?:the )?lights?|brighter|(?:make it )?brighter|full lights", c):
        return A("set", {"setting": "room_light", "value": 1.0})
    # Screen.
    m = re.fullmatch(r"(?:move |put |raise |lower |bring )?(?:the )?screen (up|down|higher|lower|closer|nearer|in|further|farther|away|back|out)"
                     r"(?: (?:by )?(\d+(?:\.\d+)?) ?(cm|centimet(?:re|er)s?|m|met(?:re|er)s?))?", c) or \
        re.fullmatch(r"(?:move |bring )?(?:it )?(up|down|closer|nearer|further|farther|away)"
                     r"(?: (?:by )?(\d+(?:\.\d+)?) ?(cm|centimet(?:re|er)s?|m|met(?:re|er)s?))?", c)
    if m:
        d, n, unit = m.group(1), m.group(2), m.group(3)
        amount = None
        if n:
            amount = float(n) / (100.0 if unit and unit.startswith("c") else 1.0)
        if d in ("up", "higher", "down", "lower"):
            step = amount if amount is not None else SCREEN_STEP_M
            sign = 1 if d in ("up", "higher") else -1
            return A("set", {"setting": "screen_height", "value": _setting("screen_height",
                                                                             lambda v: round(v + sign * step, 3))})
        step = amount if amount is not None else DISTANCE_STEP_M
        sign = -1 if d in ("closer", "nearer", "in") else 1
        return A("set", {"setting": "screen_distance",
                         "value": _setting("screen_distance", lambda v: round(_clamp(v + sign * step, 0.5, 40), 3))})
    if re.fullmatch(r"(?:make )?(?:the )?screen (?:bigger|larger)|(?:make )?(?:it )?(?:bigger|larger)(?: screen)?|zoom in", c):
        return A("set", {"setting": "screen_width", "value": _setting("screen_width",
                                                                        lambda v: round(_clamp(v * SIZE_FACTOR, 0.2, 40), 3))})
    if re.fullmatch(r"(?:make )?(?:the )?screen smaller|(?:make )?(?:it )?smaller(?: screen)?|zoom out", c):
        return A("set", {"setting": "screen_width", "value": _setting("screen_width",
                                                                        lambda v: round(_clamp(v / SIZE_FACTOR, 0.2, 40), 3))})
    if re.fullmatch(r"(?:re-?cent(?:er|re)|cent(?:er|re))(?: (?:the )?(?:screen|view|it))?|(?:bring |put )?(?:the )?screen (?:in front|here|in front of me)", c):
        return A("recenter")
    # Rooms.
    m = re.fullmatch(r"(?:go to|switch to|take me to|change to|use|put me in|open)? ?(?:the |a )?(" + "|".join(ROOM_WORDS) + r")(?: room| environment| mode)?", c)
    if m:
        return A("set", {"setting": "environment", "value": ROOM_WORDS[m.group(1)]})
    m = re.fullmatch(r"(?:load|go to|switch to|use)? ?(?:the )?recipe (.+)", c)
    if m:
        return A("load_recipe", {"name": m.group(1).strip()})
    # Subtitles, menu, overlay.
    if re.fullmatch(r"(?:turn |switch )?(?:the )?(?:subtitles?|captions?|subs) on|(?:show|turn on|enable) (?:the )?(?:subtitles?|captions?|subs)", c):
        return A("subtitles", {"on": True})
    if re.fullmatch(r"(?:turn |switch )?(?:the )?(?:subtitles?|captions?|subs) off|(?:hide|turn off|disable) (?:the )?(?:subtitles?|captions?|subs)|no subtitles", c):
        return A("subtitles", {"on": False})
    if re.fullmatch(r"(?:show|open|bring up) (?:the )?(?:menu|pane|panel)|menu", c):
        return A("menu", {"shown": True})
    if re.fullmatch(r"(?:hide|close) (?:the )?(?:menu|pane|panel)", c):
        return A("menu", {"shown": False})
    if re.fullmatch(r"(?:show|open) (?:the )?(?:info|overlay|stats|information)", c):
        return A("set", {"setting": "overlay", "value": True})
    if re.fullmatch(r"(?:hide|close) (?:the )?(?:info|overlay|stats|information)", c):
        return A("set", {"setting": "overlay", "value": False})
    if re.fullmatch(r"(?:take a |grab a )?screenshot|take a picture", c):
        return A("screenshot")
    return []


def parse(sentence):
    """(actions, unknown clauses)."""
    actions, unknown = [], []
    for c in split_clauses(normalise(sentence)):
        got = parse_clause(c)
        if got:
            actions.extend(got)
        else:
            unknown.append(c)
    return actions, unknown


def run(sentence, send, get_state=None, dry_run=False):
    """Parses and runs a sentence. send(cmd, args) -> reply dict ({ok, result | error}); get_state() -> the `get`
    command's result ({settings, state}), fetched once if a relative action needs it. Returns a report."""
    actions, unknown = parse(sentence)
    report = {"sentence": sentence, "actions": [], "unknown": unknown}
    state = None
    for a in actions:
        if a.needs_state() and state is None:
            state = get_state() if get_state else {}
            if state is None:
                state = {}
        args = a.resolved(state or {}) if a.needs_state() else dict(a.args)
        entry = {"cmd": a.cmd, "args": args, "said": a.said}
        if dry_run:
            entry["ok"] = None
        else:
            reply = send(a.cmd, args)
            entry["ok"] = bool(reply.get("ok"))
            if not entry["ok"]:
                entry["error"] = reply.get("error")
        report["actions"].append(entry)
        if a.needs_state() and entry.get("ok") and a.cmd == "set":
            state.setdefault("settings", {})[args["setting"]] = args["value"]
    report["ok"] = bool(report["actions"]) and all(e.get("ok") is not False for e in report["actions"])
    return report


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    sentence = " ".join(argv[1:])
    actions, unknown = parse(sentence)
    for a in actions:
        print("%-24s <- %s" % (a, a.said))
    for u in unknown:
        print("not understood: %s" % u)
    return 0 if actions and not unknown else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
