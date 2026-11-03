#!/usr/bin/env python3
"""Watch-along answers, the PC half (idea #54; docs/dev/watch-along.md). Python 3.8+, standard library only.

The user asks something about the film; an AI session in a terminal on the PC answers it on a card beside the screen.
There is no model call here: the AI session is the model. This module only does the two ends of it:

    gather(send, question, lines=8)   asks the headset (over the dev link) what an answer needs: the file, where it is,
                                      the chapter, the last subtitle lines said (director mode's text), the mode
    format_block(ctx)                 that context as one block of text, for the terminal and the log
    card_args(text, title, seconds)   the arguments of app-shell's `card` command for the answer

`send(cmd, args)` is the listener's command function: it returns the headset's reply dict ({ok, result | error}).
tools/listener.py uses these for `ask <question>` and `answer <text>`.
"""

import time

DEFAULT_LINES = 8
TITLE_MAX = 48


def clock(t):
    s = int(max(float(t or 0), 0))
    return "%d:%02d:%02d" % (s // 3600, (s // 60) % 60, s % 60) if s >= 3600 else "%d:%02d" % (s // 60, s % 60)


def file_name(path):
    """The last part of a path or URL, without a query (so no token in a URL is shown)."""
    p = str(path or "").split("?", 1)[0].rstrip("/")
    return p.rsplit("/", 1)[-1] if p else ""


def gather(send, question, lines=DEFAULT_LINES):
    """The context for a question. Every part is optional: what the headset can't give is left empty with a reason."""
    ctx = {"question": question.strip(), "asked": time.strftime("%Y-%m-%d %H:%M:%S"), "notes": []}
    r = send("get", {})
    state = r.get("result") if r.get("ok") else None
    if not isinstance(state, dict) or "state" in state:  # `get` with no setting: {state, settings}
        state = (state or {}).get("state") if isinstance(state, dict) else None
    if not state:
        ctx["notes"].append("no state: %s" % r.get("error", "no headset"))
        return ctx
    ctx["file"] = file_name(state.get("path"))
    ctx["title"] = state.get("title", "")
    ctx["position"] = float(state.get("position") or 0.0)
    ctx["duration"] = float(state.get("duration") or 0.0)
    ctx["playing"] = bool(state.get("playing"))
    ctx["mode"] = state.get("mode", "")
    ctx["environment"] = state.get("environment", "")

    r = send("chapters", {})
    if r.get("ok") and isinstance(r.get("result"), dict) and r["result"].get("count"):
        c = r["result"]
        cur = int(c.get("current") or 0)
        start = next((x.get("start") for x in c.get("list", []) if x.get("n") == cur), None)
        ctx["chapter"] = {"n": cur, "count": int(c["count"]), "title": c.get("title", ""), "start": start}
    elif not r.get("ok"):
        ctx["notes"].append("chapters: %s" % r.get("error"))

    if lines > 0:
        r = send("script_lines", {"offset": -1, "count": lines * 2})
        if r.get("ok") and isinstance(r.get("result"), dict):
            res = r["result"]
            cur = int(res.get("current", -1))
            said = [x for x in res.get("lines", []) if int(x.get("i", 0)) <= cur]
            ctx["subtitles"] = {"track": res.get("track", ""), "current": cur, "total": res.get("total", 0),
                                "lines": [{"i": x.get("i"), "start": x.get("start"), "text": x.get("text", "")}
                                          for x in said[-lines:]]}
        else:
            ctx["notes"].append("subtitle text: %s" % r.get("error"))
    return ctx


def format_block(ctx):
    out = ["=== watch-along question (%s) ===" % ctx.get("asked", ""), "Question: %s" % ctx.get("question", "")]
    if "file" in ctx:
        title = ctx.get("title") or ""
        out.append("File: %s%s" % (ctx["file"], ' ("%s")' % title if title and title != ctx["file"] else ""))
        out.append("Position: %s of %s (%s)" % (clock(ctx.get("position")), clock(ctx.get("duration")),
                                                 "playing" if ctx.get("playing") else "paused"))
        ch = ctx.get("chapter")
        if ch:
            out.append("Chapter: %d/%d \"%s\"%s" % (ch["n"], ch["count"], ch["title"],
                                                    " (from %s)" % clock(ch["start"]) if ch.get("start") is not None
                                                    else ""))
        out.append("Mode: %s; environment %s" % (ctx.get("mode", ""), ctx.get("environment", "")))
        subs = ctx.get("subtitles")
        if subs and subs["lines"]:
            out.append("Last %d subtitle lines (line %d of %d):" % (len(subs["lines"]), subs["current"] + 1,
                                                                    subs["total"]))
            for x in subs["lines"]:
                out.append("  [%s] %s" % (clock(x.get("start")), str(x.get("text", "")).replace("\n", " / ")))
        elif subs is not None:
            out.append("Subtitle lines: none said yet")
    for n in ctx.get("notes", []):
        out.append("(%s)" % n)
    out.append("Answer on the headset: python tools/listener.py answer \"<text>\"  (or type: answer <text>)")
    out.append("=== end ===")
    return "\n".join(out)


def card_args(text, title="", seconds=None):
    args = {"text": text.strip(), "title": title.strip()[:TITLE_MAX]}
    if seconds is not None:
        args["seconds"] = float(seconds)
    return args


def question_title(question):
    """A card heading from the question: short, on one line."""
    q = " ".join(str(question or "").split())
    return q if len(q) <= TITLE_MAX else q[:TITLE_MAX - 3].rstrip() + "..."


if __name__ == "__main__":
    print(__doc__)
