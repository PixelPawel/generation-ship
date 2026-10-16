"""Finds local variables declared in a GDScript function and never used again in
it, and parameters the function never uses — what Godot's editor reports as
UNUSED_VARIABLE / UNUSED_PARAMETER (headless runs can't show editor warnings).
Names starting with "_" are intentionally unused and skipped; so are the
parameters of "_"-functions (engine callbacks and overrides keep their signature).

    python tools/find_unused_locals.py
"""
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SKIP_DIRS = {"addons", ".godot", "android", "androidarm64", "Build", "linux32", "linux64", "linuxarm64",
             "osx", "win64", "redistributable_bin", "SteamBuildOutput", "steam_build"}
FUNC_RE = re.compile(r"^(\s*)(?:static\s+)?func\s+(\w+)")
VAR_RE = re.compile(r"^\s+var\s+([A-Za-z]\w*)")
SIG_END_RE = re.compile(r"\)\s*(->\s*[\w\[\], .]+)?\s*:\s*(#.*)?$")


def strip_strings_comments(line: str) -> str:
    line = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
    line = re.sub(r"'(?:[^'\\]|\\.)*'", "''", line)
    return line.split("#", 1)[0]


def indent_of(s: str) -> int:
    t = s.expandtabs(4)
    return len(t) - len(t.lstrip())


def check(path: str, rel: str, out: list) -> None:
    lines = open(path, encoding="utf-8").read().split("\n")
    i = 0
    while i < len(lines):
        m = FUNC_RE.match(lines[i])
        if not m:
            i += 1
            continue
        indent = indent_of(lines[i])
        fname = m.group(2)
        # the signature may span lines, up to the ':' that opens the body
        sig = lines[i]
        n = i
        while not SIG_END_RE.search(strip_strings_comments(sig).rstrip()) and n + 1 < len(lines):
            n += 1
            sig += " " + lines[n].strip()
        j = n + 1
        while j < len(lines):
            s = lines[j]
            if s.strip() and not s.lstrip().startswith("#") and indent_of(s) <= indent:
                break
            j += 1
        body = [strip_strings_comments(l) for l in lines[n + 1:j]]
        body_text = "\n".join(body)
        for k, l in enumerate(body):
            vm = VAR_RE.match(l)
            if not vm:
                continue
            name = vm.group(1)
            uses = len(re.findall(r"\b%s\b" % re.escape(name), l[vm.end():]))
            for l2 in body[k + 1:]:
                uses += len(re.findall(r"\b%s\b" % re.escape(name), l2))
            if uses == 0:
                out.append("%s:%d  var %s" % (rel, n + 2 + k, name))
        pm = re.search(r"func\s+\w+\s*\((.*)\)", strip_strings_comments(sig))
        if pm and not fname.startswith("_"):
            for param in [x.strip() for x in pm.group(1).split(",") if x.strip()]:
                pn = re.match(r"([A-Za-z]\w*)", param)
                if pn and not re.search(r"\b%s\b" % re.escape(pn.group(1)), body_text):
                    out.append("%s:%d  param %s" % (rel, i + 1, pn.group(1)))
        i = j


def main() -> None:
    out = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
        for fn in filenames:
            if fn.endswith(".gd"):
                p = os.path.join(dirpath, fn)
                check(p, os.path.relpath(p, ROOT).replace("\\", "/"), out)
    for o in out:
        print(o)
    print(len(out), "unused locals/parameters")


if __name__ == "__main__":
    main()
