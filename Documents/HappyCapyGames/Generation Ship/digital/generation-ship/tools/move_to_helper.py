"""Moves functions out of scenes/main/main.gd into a static helper script
(the BotTurn / CockpitRig / FleetFlow pattern: static funcs taking `main`).

    python tools/move_to_helper.py <helper.gd> <Const> "<doc>" f1 f2 ...   (--dry-run)

Inside the moved bodies every reference to a Main member becomes main.<x>
(vars, funcs, signals, inherited Node calls like tr()/get_tree()), consts and
enums become Main.<x>, $Node paths become main.get_node("..."), self -> main,
and calls between moved functions call the helper's statics directly. A moved
function still used anywhere else keeps a one-line wrapper in main.gd under
its old name, so no caller changes. Prints any identifier it can't classify.
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
MAIN = os.path.join(ROOT, "scenes", "main", "main.gd")

NODE_API = {"tr", "tr_n", "get_node", "get_node_or_null", "get_tree", "get_viewport", "create_tween", "add_child",
            "remove_child", "call_deferred", "multiplayer", "is_inside_tree", "get_window", "set_process",
            "get_children", "find_child", "has_node", "set_meta", "get_meta", "has_meta", "remove_meta",
            "emit_signal", "get_child", "get_child_count", "set_process_input", "get_parent", "name",
            "is_node_ready", "propagate_call", "queue_free", "get_path"}
GLOBALS = {"true", "false", "null", "self", "PI", "TAU", "INF", "NAN", "and", "or", "not", "in", "is", "as", "if",
           "elif", "else", "for", "while", "match", "return", "pass", "break", "continue", "var", "const", "func",
           "await", "static", "void", "int", "float", "bool", "String", "Array", "Dictionary", "Vector2", "Vector3",
           "Vector2i", "Vector3i", "Color", "Callable", "Variant", "Object", "Node", "Node3D", "Node2D", "Control",
           "PackedStringArray", "PackedInt32Array", "PackedFloat32Array", "PackedByteArray", "Signal", "StringName",
           "NodePath", "Transform3D", "Basis", "Rect2", "AABB", "Plane", "Quaternion", "super", "preload", "load",
           "print", "push_warning", "push_error", "str", "int", "len", "range", "min", "max", "mini", "maxi",
           "minf", "maxf", "clamp", "clampi", "clampf", "abs", "absi", "absf", "randi", "randf", "randi_range",
           "randf_range", "is_instance_valid", "typeof", "lerp", "lerpf", "floor", "ceil", "round", "floori",
           "ceili", "roundi", "sqrt", "pow", "sin", "cos", "deg_to_rad", "rad_to_deg", "sign", "signi", "signf",
           "snapped", "fmod", "posmod", "hash", "var_to_str", "str_to_var", "assert", "weakref", "instance_from_id",
           "print_rich", "printerr", "TYPE_ARRAY", "TYPE_DICTIONARY", "TYPE_INT", "TYPE_STRING", "TYPE_FLOAT",
           "TYPE_BOOL", "TYPE_NIL", "TYPE_OBJECT", "OK", "FAILED", "KEY_ESCAPE", "MOUSE_BUTTON_LEFT",
           "MOUSE_BUTTON_RIGHT", "Engine", "OS", "Time", "Input", "ResourceLoader", "TranslationServer",
           "ProjectSettings", "JSON", "ClassDB", "RandomNumberGenerator", "Tween", "Timer", "Label", "Button",
           "HBoxContainer", "VBoxContainer", "TextureRect", "Texture2D", "Image", "ImageTexture", "Camera3D",
           "MeshInstance3D", "Area3D", "Environment", "AudioStreamPlayer", "SceneTree", "Resource", "RefCounted",
           "Panel", "PanelContainer", "StyleBoxFlat", "Font", "Theme", "BoxContainer", "Container",
           "HORIZONTAL_ALIGNMENT_CENTER", "VERTICAL_ALIGNMENT_CENTER", "Vector2i", "Callable", "Array"}


def tokens_outside_strings(line):
    """(start, end, ident, prev_char) for identifiers outside strings/comments."""
    out = []
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if c == "#":
            break
        if c in "\"'":
            q = c
            if line.startswith(q * 3, i):
                j = line.find(q * 3, i + 3)
                i = n if j < 0 else j + 3
                continue
            j = i + 1
            while j < n and line[j] != q:
                j += 2 if line[j] == "\\" else 1
            i = j + 1
            continue
        if c == "$":
            m = re.match(r"\$(\"[^\"]*\"|[A-Za-z_][\w/]*)", line[i:])
            if m:
                out.append((i, i + m.end(), m.group(0), "$"))
                i += m.end()
                continue
        if c.isalpha() or c == "_":
            m = re.match(r"[A-Za-z_]\w*", line[i:])
            j = i + m.end()
            k = i - 1
            while k >= 0 and line[k] == " ":
                k -= 1
            prev = line[k] if k >= 0 else ""
            out.append((i, j, m.group(0), prev))
            i = j
            continue
        i += 1
    return out


def parse_main(text):
    lines = text.split("\n")
    members = {"var": set(), "func": set(), "const": set(), "signal": set(), "enum": set(), "static_func": set()}
    funcs = {}   # name -> (start, end) line indices (end exclusive), start includes leading comment/annotations
    for i, l in enumerate(lines):
        m = re.match(r"^(?:@\w+(?:\([^)]*\))?\s*)*(static\s+)?(var|const|signal|enum|func)\s+(\w+)", l)
        if not m:
            continue
        kind = m.group(2)
        members[kind].add(m.group(3))
        if kind == "func":
            if m.group(1):
                members["static_func"].add(m.group(3))
            # body: until the next top-level line
            j = i + 1
            while j < len(lines) and not (lines[j].strip() and not lines[j].startswith(("\t", " "))):
                j += 1
            while lines[j - 1].strip() == "":
                j -= 1
            s = i
            while s > 0 and (lines[s - 1].startswith("#") or lines[s - 1].startswith("@")):
                s -= 1
            funcs[m.group(3)] = (s, i, j)
    return lines, members, funcs


def locals_of(body_lines, sig):
    names = set()
    for l in [sig] + body_lines:
        for m in re.finditer(r"\bvar\s+(\w+)", l):
            names.add(m.group(1))
        for m in re.finditer(r"\bconst\s+(\w+)", l):
            names.add(m.group(1))
        for m in re.finditer(r"\bfor\s+(\w+)", l):
            names.add(m.group(1))
        for m in re.finditer(r"\bfunc\s*\w*\s*\(([^)]*)\)", l):
            for p in m.group(1).split(","):
                pm = re.match(r"\s*(\w+)", p)
                if pm:
                    names.add(pm.group(1))
    return names


def main():
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    dry = "--dry-run" in sys.argv
    helper_rel, const_name, doc = args[0], args[1], args[2]
    moved = args[3:]
    text = open(MAIN, encoding="utf-8").read()
    lines, members, funcs = parse_main(text)
    for f in moved:
        assert f in funcs, f
    moved_set = set(moved)
    # usage outside the moved set (main.gd and every other script)
    others = ""
    for dp, dn, fns in os.walk(ROOT):
        dn[:] = [d for d in dn if d not in {"addons", ".godot", "android", "androidarm64", "Build"}]
        for fn in fns:
            if fn.endswith((".gd", ".tscn")) and os.path.join(dp, fn) != MAIN:
                others += open(os.path.join(dp, fn), encoding="utf-8", errors="ignore").read()
    keep_lines = [l for idx, l in enumerate(lines)
                  if not any(funcs[f][0] <= idx < funcs[f][2] for f in moved)]
    # comments don't count as uses
    rest_main = "\n".join(l.split("#", 1)[0] for l in keep_lines)
    others = "\n".join(l.split("#", 1)[0] for l in others.split("\n"))
    # RPC functions must stay on the Main node: always a wrapper (with its @rpc),
    # and moved code reaches them through main.
    rpc_funcs = {f for f in moved if any(l.startswith("@rpc") for l in lines[funcs[f][0]:funcs[f][1]])}
    needs_wrapper = [f for f in moved if f in rpc_funcs or re.search(r"(?<![\w])%s\b" % f, rest_main + others)]
    moved_set = moved_set - rpc_funcs
    unknown = {}
    out_funcs = []
    for f in moved:
        s, sig_i, e = funcs[f]
        block = lines[s:e]
        sig_off = sig_i - s
        sig = block[sig_off]
        body = block[sig_off + 1:]
        loc = locals_of(body, sig)
        new_block = []
        for k, l in enumerate(block):
            if k < sig_off:
                if not l.startswith("@"):   # annotations (@rpc) stay on the wrapper in main.gd
                    new_block.append(l)
                continue
            if k == sig_off:
                m = re.match(r"^(static\s+)?func\s+(\w+)\s*\((.*)$", l)
                rest = m.group(3)
                # an already-static function needs no main
                params = "" if f in members["static_func"] else "main: Main" + ("" if rest.lstrip().startswith(")") else ", ")
                new_block.append("static func %s(%s%s" % (m.group(2).lstrip("_") if False else m.group(2), params, rest))
                continue
            toks = tokens_outside_strings(l)
            res = ""
            pos = 0
            for (a, b, ident, prev) in toks:
                rep = None
                if prev == "$":
                    path = ident[1:].strip('"')
                    rep = 'main.get_node("%s")' % path
                elif prev == "." :
                    rep = None
                elif ident == "self":
                    rep = "main"
                elif ident in loc:
                    rep = None
                elif ident in moved_set:
                    rep = None   # helper static, same script; add main arg below
                elif ident in members["const"] or ident in members["enum"]:
                    rep = "Main." + ident
                elif ident in members["static_func"]:
                    rep = "Main." + ident
                elif ident in members["var"] or ident in members["func"] or ident in members["signal"] or ident in NODE_API:
                    rep = "main." + ident
                elif ident not in GLOBALS and not ident[0].isupper() and not re.match(r"^[A-Z0-9_]+$", ident):
                    unknown.setdefault(ident, f)
                if rep is not None:
                    res += l[pos:a] + rep
                    pos = b
                elif ident in moved_set and l[b:b + 1] == "(" and prev != "." and ident not in members["static_func"]:
                    close = l[b + 1:b + 2]
                    res += l[pos:b] + "(main" + ("" if close == ")" else ", ")
                    pos = b + 1
                else:
                    res += l[pos:b]
                    pos = b
            res += l[pos:]
            new_block.append(res)
        out_funcs.append("\n".join(new_block))
    # main.gd: drop moved funcs, add wrappers where still referenced
    new_lines = []
    idx = 0
    placed_wrappers = set()
    while idx < len(lines):
        hit = [f for f in moved if funcs[f][0] == idx]
        if hit:
            f = hit[0]
            s, sig_i, e = funcs[f]
            if f in needs_wrapper:
                sig = lines[sig_i]
                m = re.match(r"^(static\s+)?func\s+(\w+)\s*\((.*)\)\s*(->\s*[^:]+)?:", sig)
                if not m:
                    # multi-line signature: join it
                    j = sig_i
                    joined = sig
                    while not re.search(r"\)\s*(->\s*[^:]+)?:\s*$", joined):
                        j += 1
                        joined += " " + lines[j].strip()
                    m = re.match(r"^(static\s+)?func\s+(\w+)\s*\((.*)\)\s*(->\s*[^:]+)?:", joined)
                    sig = joined
                params = m.group(3)
                names = [re.match(r"\s*(\w+)", p).group(1) for p in params.split(",") if p.strip()]
                ret = (m.group(4) or "").strip()
                args = ([] if f in members["static_func"] else ["self"]) + names
                call = "%s.%s(%s)" % (const_name, f, ", ".join(args))
                body = ("\treturn " if ret and ret != "-> void" else "\t") + call
                is_coro = "await" in "\n".join(lines[sig_i:e])
                if is_coro:
                    body = ("\treturn await " if ret and ret != "-> void" else "\tawait ") + call
                new_lines.extend(l for l in lines[s:sig_i] if l.startswith("@"))   # e.g. @rpc(...)
                new_lines.append(sig)
                new_lines.append(body)
                placed_wrappers.add(f)
            idx = e
            continue
        new_lines.append(lines[idx])
        idx += 1
    new_main = "\n".join(new_lines)
    # preload the helper next to the other preloads
    pre = 'const %s = preload("res://%s")' % (const_name, helper_rel)
    if pre not in new_main:
        new_main = re.sub(r'(const FleetFlow = preload\("[^"]+"\)\n)', r"\1" + pre + "\n", new_main, count=1)
    helper_path = os.path.join(ROOT, helper_rel)
    if os.path.exists(helper_path):
        # append to an existing helper: its own preloads need no Main. prefix,
        # its own name none at all, and no function may exist twice
        existing = open(helper_path, encoding="utf-8").read()
        own = set(re.findall(r"^const\s+(\w+)\s*:?=\s*preload", existing, re.M))
        code = "\n\n".join(out_funcs)
        code = code.replace("Main.%s." % const_name, "")
        for c in own:
            code = code.replace("Main.%s." % c, "%s." % c)
        clash = set(re.findall(r"^static func (\w+)", existing, re.M)) & set(re.findall(r"^static func (\w+)", code, re.M))
        assert not clash, ("already in the helper", clash)
        header = "\n\n# " + "\n# ".join(doc.split("\n")) + "\n\n" if doc else "\n\n"
        helper = existing.rstrip("\n") + header + code + "\n"
    else:
        helper = "extends RefCounted\n" + "\n".join("# " + d if d else "#" for d in doc.split("\n")) + "\n\n" + \
                 "\n\n".join(out_funcs) + "\n"
    print("moved:", len(moved), " wrappers kept in main:", sorted(placed_wrappers))
    print("unclassified identifiers (check!):", sorted(unknown))
    if dry:
        return
    open(helper_path, "w", encoding="utf-8", newline="").write(helper)
    open(MAIN, "w", encoding="utf-8", newline="").write(new_main)


if __name__ == "__main__":
    main()
