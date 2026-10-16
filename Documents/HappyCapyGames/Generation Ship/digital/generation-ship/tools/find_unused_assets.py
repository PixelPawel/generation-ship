"""Lists asset files nothing in the project refers to (candidates to remove).

    python tools/find_unused_assets.py

An asset counts as used if its res:// path, its path relative to the project,
or its bare file name (scripts often build paths: "%s.png" % name) appears in
any .gd, .tscn, .tres, .gdshader, project.godot, export_presets.cfg, .csv or
.json. Card art under assets/cards/ is looked up by names built from the card
sheets (Link column, paged print-export names) and is skipped here — check it
with the sheets instead.
"""
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SKIP_DIRS = {"addons", ".godot", "android", "androidarm64", "Build", "linux32", "linux64", "linuxarm64",
             "osx", "win64", "redistributable_bin", "SteamBuildOutput", "steam_build", "tools"}
# loaded by the engine itself (project icon, audio bus layout)
ENGINE_USED = {"icon.svg", "default_bus_layout.tres"}
REF_EXT = (".gd", ".tscn", ".tres", ".gdshader", ".godot", ".cfg", ".csv", ".json", ".gdextension")
ASSET_EXT = (".png", ".jpg", ".jpeg", ".webp", ".svg", ".wav", ".ogg", ".mp3", ".webm", ".mp4", ".ogv",
             ".ttf", ".otf", ".glb", ".gltf", ".obj", ".fbx", ".exr", ".hdr", ".tres", ".gdshader", ".res")


def walk():
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
        if os.path.exists(os.path.join(dirpath, ".gdignore")):
            dirnames[:] = []
            continue
        for fn in filenames:
            yield os.path.join(dirpath, fn)


def main() -> None:
    paths = list(walk())
    corpus = []
    for p in paths:
        if p.endswith(REF_EXT):
            corpus.append(open(p, encoding="utf-8", errors="ignore").read())
        elif p.endswith((".glb", ".gltf")):   # models name their textures inside
            corpus.append(open(p, "rb").read().decode("latin-1"))
    corpus = "\n".join(corpus)
    unused = []
    total = 0
    for p in paths:
        rel = os.path.relpath(p, ROOT).replace("\\", "/")
        if not p.lower().endswith(ASSET_EXT) or rel.startswith("assets/cards/"):
            continue
        total += 1
        name = os.path.basename(p)
        stem = os.path.splitext(name)[0]
        if rel in ENGINE_USED or ("res://" + rel) in corpus or rel in corpus or name in corpus:
            continue
        # loaded by a name list: "ship_hum_loop" -> ship_hum_loop.wav
        if ('"%s"' % stem) in corpus:
            continue
        # textures Godot extracted from a model sit next to it as <model>_<image>.png
        folder = os.path.dirname(p)
        if any(stem.startswith(os.path.splitext(g)[0] + "_") for g in os.listdir(folder) if g.endswith((".glb", ".gltf"))):
            continue
        # referenced by uid only (scenes keep uid:// next to the path; .import has the uid)
        imp = p + ".import"
        uid = ""
        if os.path.exists(imp):
            for line in open(imp, encoding="utf-8", errors="ignore"):
                if line.startswith("uid="):
                    uid = line.split("=", 1)[1].strip().strip('"')
        if uid and uid in corpus:
            continue
        unused.append((rel, os.path.getsize(p), stem))
    for rel, size, _ in sorted(unused):
        print("%8.1f KB  %s" % (size / 1024.0, rel))
    print("%d of %d assets unreferenced, %.1f MB" % (len(unused), total, sum(s for _, s, _ in unused) / 1048576.0))


if __name__ == "__main__":
    main()
