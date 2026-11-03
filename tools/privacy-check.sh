#!/usr/bin/env bash
# Looks for personal data before it leaves the PC: names of films from a media library, user names in paths, home
# network addresses and e-mail addresses. Run from Git Bash or WSL, anywhere in the repository.
#
#   tools/privacy-check.sh                every tracked file of the working tree
#   tools/privacy-check.sh --tree REV     every file at a revision (for example HEAD)
#   tools/privacy-check.sh A..B           the lines added from A to B, and the commit messages of A..B
#   tools/privacy-check.sh --pre-push     what `git push` is about to send (reads the pre-push hook's stdin;
#                                         see tools/pre-push.sample)
#
# Generic patterns (always on):
#   release   a scene release name: a year, then a source tag (BluRay, WEB-DL, WEBRip, HDTV, DVDRip, ...)
#   path      /home/<name>/, /Users/<name>/, C:\Users\<name>\ (example names such as user, you, steamos, and
#             dot folders such as /home/.cache, are fine)
#   address   a private IPv4 address outside the example ranges 192.168.0.x, 192.168.1.x, 10.0.x.x, 172.16.0.x
#   email     an e-mail address, except noreply ones and example.com/org/net
# Private patterns: one Python regular expression per line (case-insensitive; # starts a comment) in
# $VRVP_PRIVATE_PATTERNS, default ~/.config/vrvp/private-patterns. Keep your own titles, share names, host names and
# so on there. That file is never in the repository.
# Binary files are checked too, as their printable strings (path, address, email and private patterns).
# A line that contains "privacy-check: allow" is skipped. Hits are printed as file:line, the kind, and the hit with
# its middle masked. Exit 0: nothing found; 1: hits; 2: usage or git error.
set -euo pipefail

PY=""
for c in python3 python py; do  # Windows has a python3 that only offers the Store: try each
  if command -v "$c" > /dev/null 2>&1 && "$c" -c 'import sys; sys.exit(sys.version_info < (3, 6))' > /dev/null 2>&1; then
    PY=$c
    break
  fi
done
[ -n "$PY" ] || { echo "privacy-check: needs Python 3" >&2; exit 2; }
cd "$(git rev-parse --show-toplevel)"
export VRVP_PRIVATE_PATTERNS=${VRVP_PRIVATE_PATTERNS:-$HOME/.config/vrvp/private-patterns}
# The program goes in as -c, so stdin stays the hook's.
PROGRAM=$(cat <<'PYTHON'
import os
import re
import subprocess
import sys

SELF = "tools/privacy-check.sh"
ZERO = "0" * 40

# A source tag ends a release name; only lines with one are searched for the rest (the patterns are bounded, so a long
# line stays quick).
SOURCE = r"(?:blu-?ray|bdrip|brrip|bd25|bd50|web-?dl|webrip|web\.h26[45]|hdtv|dvdrip|dvdscr|hdts|remux|amzn|hmax|pmtp|dsnp|atvp)"
SOURCE_ANY = re.compile(r"(?<![a-z])" + SOURCE + r"\b|(?<![a-z])s\d{1,2}e\d{1,3}\b", re.I)
WORD = r"[\w'&!,+()\[\]-]{1,40}"
RELEASE = re.compile(
    r"(?:" + WORD + r"[ ._]){1,12}?\(?(?:19[2-9]\d|20[0-4]\d)\)?[ ._](?:" + WORD + r"[ ._]){0,10}?" + SOURCE + r"\b",
    re.I)
EPISODE = re.compile(
    r"(?:" + WORD + r"[ ._]){1,10}?s\d{1,2}e\d{1,3}[ ._](?:" + WORD + r"[ ._]){0,10}?"
    r"(?:" + SOURCE + r"|x26[45]|xvid|h\.?26[45])\b", re.I)
EXAMPLE_USERS = r"(?:user|users|username|you|your-?name|name|me|example|steamos|deck|runner|public|default|all users|<[^>]*>|\$\w+|%\w+%|\*)"
PATH = re.compile(
    r"(?:/home/|/Users/|[A-Za-z]:[\\/]+Users[\\/]+|\\\\wsl[^\\]*\\[^\\]+\\home\\|/mnt/[a-z]/Users/)"
    r"(?!" + EXAMPLE_USERS + r"(?:[\\/\s\"'`)]|$))[A-Za-z0-9_][A-Za-z0-9._-]+", re.I)
IPV4 = re.compile(r"(?<![\d.])(10|172|192)\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?![\d.]*\d)")
EMAIL = re.compile(r"(?<![\w:/.%+-])[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}\b")
ALLOW = "privacy-check: allow"


def private_address(m: re.Match) -> bool:
    a, b, c = int(m.group(1)), int(m.group(2)), int(m.group(3))
    if a == 192:
        return b == 168 and c not in (0, 1)
    if a == 172:
        return 16 <= b <= 31 and not (b == 16 and c == 0)
    return b != 0 and (b, c, int(m.group(4))) not in ((1, 2, 3), (255, 255, 1))


def email_ok(s: str) -> bool:
    local, _, domain = s.partition("@")
    return "noreply" in local.lower() or "no-reply" in local.lower() or domain.lower().split(".")[-2:-1] == ["example"]


def load_private() -> list:
    path = os.path.expanduser(os.environ.get("VRVP_PRIVATE_PATTERNS", ""))
    out = []
    if path and os.path.isfile(path):
        for n, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            try:
                out.append(re.compile(line, re.I))
            except re.error as e:
                print("privacy-check: %s:%d: bad pattern (%s)" % (path, n, e), file=sys.stderr)
                sys.exit(2)
    return out


PRIVATE = load_private()


def mask(s: str) -> str:
    s = s.strip()
    if len(s) <= 4:
        return "*" * len(s)
    keep = 2 if len(s) < 12 else 3
    return s[:keep] + "*" * (len(s) - 2 * keep) + s[-keep:]


def hits_in(line: str, binary: bool) -> list:
    if ALLOW in line:
        return []
    found = []
    if not binary and SOURCE_ANY.search(line):
        for rx in (RELEASE, EPISODE):
            found += [("release", m.group(0)) for m in rx.finditer(line)]
    found += [("path", m.group(0)) for m in PATH.finditer(line)]
    found += [("address", m.group(0)) for m in IPV4.finditer(line) if private_address(m)]
    found += [("email", m.group(0)) for m in EMAIL.finditer(line) if not email_ok(m.group(0))]
    for rx in PRIVATE:
        found += [("private", m.group(0)) for m in rx.finditer(line) if m.group(0)]
    return found


def git(*args: str) -> bytes:
    try:
        return subprocess.check_output(("git",) + args)
    except subprocess.CalledProcessError as e:
        print("privacy-check: git %s failed (%d)" % (" ".join(args), e.returncode), file=sys.stderr)
        sys.exit(2)


TOTAL = 0


def report(where: str, line: str, binary: bool) -> None:
    global TOTAL
    for kind, s in hits_in(line, binary):
        TOTAL += 1
        print("%s: %s: %s" % (where, kind, mask(s)))


def check_blob(name: str, data: bytes) -> None:
    if name == SELF:
        return
    binary = b"\0" in data[:8000]
    if binary:
        for m in re.finditer(rb"[\x20-\x7e]{6,}", data):
            report(name + " (binary)", m.group(0).decode("ascii"), True)
        return
    for n, line in enumerate(data.decode("utf-8", "replace").splitlines(), 1):
        report("%s:%d" % (name, n), line, False)


def check_worktree() -> None:
    for name in git("ls-files", "-z").decode("utf-8", "replace").split("\0"):
        if name and os.path.isfile(name):
            with open(name, "rb") as f:
                check_blob(name, f.read())


def check_tree(rev: str) -> None:
    for entry in git("ls-tree", "-r", "-z", "--full-tree", rev).split(b"\0"):
        if not entry:
            continue
        meta, name = entry.split(b"\t", 1)
        if meta.split()[1] != b"blob":
            continue
        check_blob(name.decode("utf-8", "replace"), git("cat-file", "blob", meta.split()[2].decode()))


def check_messages(revs: list) -> None:
    for rev in revs:
        msg = git("log", "-1", "--format=%B", rev).decode("utf-8", "replace")
        for n, line in enumerate(msg.splitlines(), 1):
            report("commit %s message:%d" % (rev[:10], n), line, False)


def check_commits(revs: list) -> None:
    """The lines each commit adds (text), and the binary files it adds or changes."""
    for rev in revs:
        diff = git("show", "--format=", "--no-color", "--unified=0", "--no-renames", rev).decode("utf-8", "replace")
        name, n = "", 0
        for line in diff.splitlines():
            if line.startswith("+++ "):
                name = line[6:] if line.startswith("+++ b/") else ""
            elif line.startswith("@@"):
                m = re.search(r"\+(\d+)", line)
                n = int(m.group(1)) - 1 if m else 0
            elif line.startswith("+") and name and name != SELF:
                n += 1
                report("%s:%d (%s)" % (name, n, rev[:10]), line[1:], False)
            elif line.startswith("Binary files") and " and b/" in line:
                path = line.split(" and b/", 1)[1].rsplit(" differ", 1)[0]
                check_blob(path, git("cat-file", "blob", "%s:%s" % (rev, path)))
        check_messages([rev])


def main(argv: list) -> int:
    if not argv:
        check_worktree()
    elif argv[0] == "--tree" and len(argv) == 2:
        check_tree(argv[1])
    elif argv[0] == "--pre-push":
        for line in sys.stdin.read().splitlines():
            parts = line.split()
            if len(parts) != 4 or parts[1] == ZERO:
                continue  # malformed, or a delete
            local, remote = parts[1], parts[3]
            if remote != ZERO:
                revs = git("rev-list", "%s..%s" % (remote, local)).decode().split()
            else:
                revs = git("rev-list", local, "--not", "--remotes").decode().split()
                if not git("for-each-ref", "refs/remotes").strip():
                    check_tree(local)  # a first push: the whole tree
                    check_messages(revs)
                    revs = []
            check_commits(revs)
    elif len(argv) == 1 and ".." in argv[0]:
        check_commits(git("rev-list", argv[0]).decode().split())
    else:
        print(__doc__ or "usage: tools/privacy-check.sh [--tree REV | A..B | --pre-push]", file=sys.stderr)
        return 2
    if TOTAL:
        print("privacy-check: %d hit(s). Fix them, or mark a line that is fine with \"%s\"." % (TOTAL, ALLOW),
              file=sys.stderr)
        return 1
    return 0


sys.exit(main(sys.argv[1:]))
PYTHON
)
exec "$PY" -c "$PROGRAM" "$@"
