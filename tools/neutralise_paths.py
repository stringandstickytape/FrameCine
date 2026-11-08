#!/usr/bin/env python3
"""Takes the builder's user name out of the build paths in release binaries (tools/package.sh, tools/release.sh).

    python3 tools/neutralise_paths.py FILE...

Compilers put source paths into binaries through __FILE__ (FFmpeg's and ggml's asserts, a log line in the PC app):
/home/<name>/src/... in a Linux build, C:\\Users\\<name>\\source\\... in a Windows one. In each ELF or PE file given,
the name in /home/<name>/ and <drive>:\\Users\\<name>\\ is replaced by a neutral one of the same length ("build",
cut or padded with "_"), so no offset in the file moves. /home/steamos (and the other names below) and OpenXR's
/input/home/... paths are left alone. Other files are skipped. Prints one line per changed file.
"""
import re
import sys

KEEP = {b"steamos", b"user", b"deck", b"build", b"public", b"default"}
PATTERNS = (
    re.compile(rb"(?<!/input)(/home/)([A-Za-z0-9._-]{1,64})(/)"),
    re.compile(rb"([A-Za-z]:\\+Users\\+)([A-Za-z0-9._ -]{1,64}?)(\\)", re.I),
    re.compile(rb"([A-Za-z]:/+Users/+)([A-Za-z0-9._ -]{1,64}?)(/)", re.I),
)


def neutral(name: bytes) -> bytes:
    return (b"build" + b"_" * len(name))[:len(name)]


def neutralise(data: bytes) -> tuple:
    count = 0

    def sub(m):
        nonlocal count
        if m.group(2).lower() in KEEP:
            return m.group(0)
        count += 1
        return m.group(1) + neutral(m.group(2)) + m.group(3)

    for rx in PATTERNS:
        data = rx.sub(sub, data)
    return data, count


def main(paths: list) -> int:
    for path in paths:
        with open(path, "rb") as f:
            data = f.read()
        if data[:4] != b"\x7fELF" and data[:2] != b"MZ":
            continue
        out, n = neutralise(data)
        assert len(out) == len(data)
        if n:
            with open(path, "wb") as f:
                f.write(out)
            print("  build paths neutralised in %s: %d" % (path.replace("\\", "/").rsplit("/", 1)[-1], n))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
