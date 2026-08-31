"""Extract meshes/textures/materials from the game's .unity3d AssetBundles
(the standee/prop models shipped with the official Tabletop Simulator mod)
into OBJ+MTL+PNG that Godot can import directly.

Usage:
    pip install UnityPy
    python tools/extract_unity3d.py

Reads every *.unity3d under assets/images/3d/ and writes one output folder
per bundle under assets/models/<same relative path>/<bundle stem>/, containing:
  - one .obj per render GameObject (front/back/edge submeshes correctly
    tagged with `usemtl`, resolved via that GameObject's MeshRenderer)
  - one .obj per loose collision-only Mesh (not attached to any MeshRenderer)
  - materials.mtl (one entry per Material, mapped to its _MainTex if any)
  - one .png per Texture2D

Re-run any time new .unity3d files are added; it's safe to re-run over
existing output (files are overwritten, not appended).

After running this, force Godot to actually import the new files with:
    godot --headless --editor --quit --path .
(a plain `--script` run does NOT trigger the editor's asset-import pass).

Known quirk: some Unity meshes carry zero UV data (solid-color parts like
Havens/Garrisons/Tower/Walls) but still emit `v/vt/vn` face indices via
UnityPy's Mesh.export(), which Godot's OBJ importer rejects ("uvs.size() =
0"). This script strips the texcoord component from face lines whenever a
mesh has no `vt` lines at all.
"""

import re
from pathlib import Path

import UnityPy

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SRC_ROOT = PROJECT_ROOT / "assets" / "images" / "3d"
OUT_ROOT = PROJECT_ROOT / "assets" / "models"


def safe_name(name: str) -> str:
    name = name.strip() or "unnamed"
    return re.sub(r"[^A-Za-z0-9_.-]", "_", name)


def strip_uv_if_absent(obj_text: str) -> str:
    """Drop the texcoord index from face lines when the mesh has no `vt` data."""
    lines = obj_text.splitlines()
    if any(l.startswith("vt ") for l in lines):
        return obj_text
    out = []
    for line in lines:
        if line.startswith("f "):
            parts = line[2:].split()
            new_parts = []
            for p in parts:
                comps = p.split("/")
                if len(comps) == 3 and comps[1] != "":
                    new_parts.append(f"{comps[0]}//{comps[2]}")
                else:
                    new_parts.append(p)
            out.append("f " + " ".join(new_parts))
        else:
            out.append(line)
    return "\n".join(out)


def process_bundle(bundle_path: Path, out_dir: Path) -> dict:
    stats = {"textures": 0, "meshes": 0, "materials": 0, "objects_exported": 0, "primary_objs": [], "errors": []}
    try:
        env = UnityPy.load(str(bundle_path))
    except Exception as e:
        stats["errors"].append(f"load failed: {e}")
        return stats

    objs = list(env.objects)
    by_id = {o.path_id: o for o in objs}
    out_dir.mkdir(parents=True, exist_ok=True)

    # --- Textures ---
    tex_names = {}  # path_id -> filename stem
    for o in objs:
        if o.type.name != "Texture2D":
            continue
        try:
            d = o.read()
            img = d.image
            if img is None or img.width == 0:
                continue
            fname = safe_name(d.m_Name) or f"tex_{o.path_id}"
            img.save(out_dir / f"{fname}.png")
            tex_names[o.path_id] = fname
            stats["textures"] += 1
        except Exception as e:
            stats["errors"].append(f"texture {o.path_id}: {e}")

    # --- Materials ---
    mat_info = {}  # path_id -> {name, tex, color}
    for o in objs:
        if o.type.name != "Material":
            continue
        try:
            d = o.read()
            name = safe_name(d.m_Name) or f"mat_{o.path_id}"
            main_tex = None
            for key, texenv in d.m_SavedProperties.m_TexEnvs:
                if key == "_MainTex" and texenv.m_Texture.m_PathID != 0:
                    main_tex = tex_names.get(texenv.m_Texture.m_PathID)
            color = None
            for key, c in d.m_SavedProperties.m_Colors:
                if key in ("_Color", "_BaseColor"):
                    color = (c.r, c.g, c.b, c.a)
            mat_info[o.path_id] = {"name": name, "tex": main_tex, "color": color}
            stats["materials"] += 1
        except Exception as e:
            stats["errors"].append(f"material {o.path_id}: {e}")

    if mat_info:
        with open(out_dir / "materials.mtl", "w", encoding="utf-8") as f:
            seen = set()
            for info in mat_info.values():
                if info["name"] in seen:
                    continue
                seen.add(info["name"])
                f.write(f"newmtl {info['name']}\n")
                r, g, b, a = info["color"] if info["color"] else (1, 1, 1, 1)
                f.write(f"Kd {r:.4f} {g:.4f} {b:.4f}\n")
                if a < 1.0:
                    f.write(f"d {a:.4f}\n")
                if info["tex"]:
                    f.write(f"map_Kd {info['tex']}.png\n")
                f.write("\n")

    # --- Meshes, grouped by owning GameObject (via MeshFilter+MeshRenderer) ---
    exported_mesh_ids = set()
    for o in objs:
        if o.type.name != "GameObject":
            continue
        try:
            gd = o.read_typetree()
        except Exception as e:
            stats["errors"].append(f"gameobject {o.path_id}: {e}")
            continue
        go_name = safe_name(gd.get("m_Name", "GameObject"))

        mesh_filter = None
        mesh_renderer = None
        for comp in gd.get("m_Component", []):
            cid = comp.get("component", {}).get("m_PathID")
            cobj = by_id.get(cid)
            if cobj is None:
                continue
            if cobj.type.name == "MeshFilter":
                mesh_filter = cobj
            elif cobj.type.name == "MeshRenderer":
                mesh_renderer = cobj

        if mesh_filter is None:
            continue

        try:
            mf_tree = mesh_filter.read_typetree()
            mesh_pid = mf_tree["m_Mesh"]["m_PathID"]
            mesh_obj = by_id.get(mesh_pid)
            if mesh_obj is None:
                continue
            mesh_data = mesh_obj.read()
            obj_text = mesh_data.export()
        except Exception as e:
            stats["errors"].append(f"mesh for {go_name}: {e}")
            continue

        mat_ids = []
        if mesh_renderer is not None:
            try:
                mr_tree = mesh_renderer.read_typetree()
                mat_ids = [m["m_PathID"] for m in mr_tree.get("m_Materials", [])]
            except Exception as e:
                stats["errors"].append(f"renderer for {go_name}: {e}")

        lines = obj_text.splitlines()
        out_lines = ["mtllib materials.mtl"] if mat_info else []
        for line in lines:
            out_lines.append(line)
            if line.startswith("g ") and mat_ids:
                parts = line[2:].rsplit("_", 1)
                if len(parts) == 2 and parts[1].isdigit():
                    idx = int(parts[1])
                    if idx < len(mat_ids):
                        mat = mat_info.get(mat_ids[idx])
                        if mat:
                            out_lines.append(f"usemtl {mat['name']}")

        final_text = strip_uv_if_absent("\n".join(out_lines))

        fname = go_name
        n = 1
        while (out_dir / f"{fname}.obj").exists():
            n += 1
            fname = f"{go_name}_{n}"
        (out_dir / f"{fname}.obj").write_text(final_text, encoding="utf-8")
        exported_mesh_ids.add(mesh_pid)
        stats["objects_exported"] += 1
        stats.setdefault("primary_objs", []).append(str(out_dir / f"{fname}.obj"))

    # --- Any meshes not attached to a GameObject/MeshRenderer (e.g. collision-only) ---
    for o in objs:
        if o.type.name != "Mesh" or o.path_id in exported_mesh_ids:
            continue
        try:
            d = o.read()
            obj_text = strip_uv_if_absent(d.export())
            name = safe_name(d.m_Name) or f"mesh_{o.path_id}"
            fname = name
            n = 1
            while (out_dir / f"{fname}.obj").exists():
                n += 1
                fname = f"{name}_{n}"
            (out_dir / f"{fname}.obj").write_text(obj_text, encoding="utf-8")
            stats["meshes"] += 1
        except Exception as e:
            stats["errors"].append(f"loose mesh {o.path_id}: {e}")

    return stats


def main():
    import csv

    bundles = sorted(SRC_ROOT.rglob("*.unity3d"))
    print(f"Found {len(bundles)} .unity3d bundles under {SRC_ROOT}")

    total_stats = {"textures": 0, "meshes": 0, "materials": 0, "objects_exported": 0}
    error_bundles = []
    manifest_rows = []  # (folder relative to project root, primary_obj res:// path)

    for i, bundle_path in enumerate(bundles, 1):
        rel = bundle_path.relative_to(SRC_ROOT)
        out_dir = OUT_ROOT / rel.parent / rel.stem
        stats = process_bundle(bundle_path, out_dir)
        for k in total_stats:
            total_stats[k] += stats[k]
        if stats["errors"]:
            error_bundles.append((str(rel), stats["errors"]))
        for p in stats["primary_objs"]:
            p_rel = Path(p).resolve().relative_to(PROJECT_ROOT).as_posix()
            manifest_rows.append({
                "folder": (out_dir.resolve().relative_to(PROJECT_ROOT)).as_posix(),
                "primary_obj": "res://" + p_rel,
            })
        if i % 10 == 0 or i == len(bundles):
            print(f"[{i}/{len(bundles)}] ...")

    print("\n=== Totals ===")
    print(total_stats)
    print(f"Bundles with errors: {len(error_bundles)}")
    for name, errs in error_bundles[:20]:
        print(f"  {name}: {errs}")

    manifest_path = PROJECT_ROOT / "assets" / "data" / "_model_manifest.csv"
    with open(manifest_path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["folder", "primary_obj"])
        w.writeheader()
        w.writerows(manifest_rows)
    print(f"\nWrote {manifest_path} ({len(manifest_rows)} primary meshes)")

    print(
        "\nNow force Godot to import the new files:\n"
        '  godot --headless --editor --quit --path "%s"' % PROJECT_ROOT
    )


if __name__ == "__main__":
    main()
