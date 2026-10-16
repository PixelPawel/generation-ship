"""Lists GDScript functions, signals, consts and member variables that nothing
references (candidates for dead code — check each before deleting).

    python tools/find_dead_code.py

A name counts as used if it appears anywhere else in the project's .gd, .tscn,
.tres or project.godot as a whole word (calls, connect("name"), call_deferred,
rpc, signals wired in scenes…). Engine callbacks (_ready, _process, _input…)
and RPC handlers called through .rpc() are skipped. Names reused by another
definition elsewhere are only reported if no use exists at all.
"""
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SKIP_DIRS = {"addons", ".godot", "android", "androidarm64", "Build", "linux32", "linux64", "linuxarm64",
             "osx", "win64", "redistributable_bin", "SteamBuildOutput", "steam_build"}
ENGINE = {"_ready", "_process", "_physics_process", "_input", "_unhandled_input", "_gui_input", "_init",
          "_enter_tree", "_exit_tree", "_notification", "_draw", "_get_minimum_size", "_initialize",
          "_finalize", "_unhandled_key_input", "_shortcut_input", "_has_point", "_make_custom_tooltip",
          "_get_drag_data", "_can_drop_data", "_drop_data", "_to_string", "_get", "_set", "_get_property_list",
          "_validate_property", "_integrate_forces", "_run"}
DEF_RE = re.compile(r"^(?:static\s+)?func\s+([A-Za-z_]\w*)", re.M)
SIG_RE = re.compile(r"^signal\s+([A-Za-z_]\w*)", re.M)
CONST_RE = re.compile(r"^(?:static\s+)?const\s+([A-Za-z_]\w*)", re.M)
VAR_RE = re.compile(r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?var\s+([A-Za-z_]\w*)", re.M)


def files():
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
        for fn in filenames:
            if fn.endswith((".gd", ".tscn", ".tres")) or fn == "project.godot":
                yield os.path.join(dirpath, fn)


def main() -> None:
    texts = {p: open(p, encoding="utf-8", errors="ignore").read() for p in files()}
    words = {}
    for p, t in texts.items():
        for w in re.findall(r"[A-Za-z_]\w*", t):
            words[w] = words.get(w, 0) + 1
    report = []
    for p, t in texts.items():
        if not p.endswith(".gd"):
            continue
        rel = os.path.relpath(p, ROOT).replace("\\", "/")
        for kind, rx in (("func", DEF_RE), ("signal", SIG_RE), ("const", CONST_RE), ("var", VAR_RE)):
            for m in rx.finditer(t):
                name = m.group(1)
                if kind == "func" and (name in ENGINE or name.startswith("_rpc_")):
                    continue
                # engine virtuals of an *Extension class (e.g. MultiplayerPeerExtension)
                if kind == "func" and name.startswith("_") and re.search(r"^extends \w+Extension", t, re.M):
                    continue
                defs = len(re.findall(r"^(?:static\s+)?(?:func|signal|const|var)\s+%s\b" % re.escape(name), t, re.M))
                total_defs = sum(len(re.findall(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?(?:func|signal|const|var)\s+%s\b" % re.escape(name), x, re.M))
                                 for x in texts.values())
                if words.get(name, 0) <= max(defs, total_defs):
                    line = t.count("\n", 0, m.start()) + 1
                    report.append("%-6s %-40s %s:%d" % (kind, name, rel, line))
    for r in sorted(report, key=lambda s: s.split()[2]):
        print(r)
    print(len(report), "candidates")


if __name__ == "__main__":
    main()
