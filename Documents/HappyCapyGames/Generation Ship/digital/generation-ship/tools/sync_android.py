"""Mirror this project into ../generation-ship-android with mobile-sized textures.

The main project stays the only one anyone edits. Run this before an Android
release, then open ../generation-ship-android in Godot and export there.

    python tools/sync_android.py            # sync
    python tools/sync_android.py --dry-run  # only report what would change

Only image import settings differ in the copy (Godot can't import per
platform, and the desktop build keeps full-quality art):
  * LOSSY_DIRS images: lossless -> lossy WebP at LOSSY_QUALITY
  * every image: capped at MAX_SIZE px (process/size_limit)
Everything else is copied as-is. Files are only rewritten when their content
changes, so Godot re-imports just what actually changed.
"""
import filecmp
import os
import re
import shutil
import sys

SRC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DST = os.path.join(os.path.dirname(SRC), os.path.basename(SRC) + "-android")

LOSSY_DIRS = ("assets/cards/", "assets/frames/", "assets/manual/", "assets/art/", "assets/ui/Cover.")
LOSSY_QUALITY = "0.85"
MAX_SIZE = "2048"

# Relative paths (forward slashes) never mirrored: Godot's cache, build output,
# Android build products (regenerated on export), editor/OS temp files.
SKIP_PREFIXES = (".godot/", "Build/", "android/build/build/", "android/build/.gradle/",
                 "android/build/assetPackInstallTime/src/main/assets/", ".git/",
                 # desktop-only leftovers, not game resources
                 "GS.zip", "linux32/")
# Steam-only features left out of the Android build: their scripts aren't
# copied and their autoload lines are stripped from project.godot.
ANDROID_EXCLUDE = ("scripts/net/translation_votes.gd", "scripts/net/translation_votes.gd.uid")
ANDROID_DROP_AUTOLOADS = ("TranslationVotes",)
IMAGE_IMPORT = re.compile(r"\.(png|jpe?g|webp|svg)\.import$", re.I)
# Files carried over from inside .godot/ (export presets' keystore credentials).
EXTRA_FILES = (".godot/export_credentials.cfg",)


def skipped(rel: str) -> bool:
    name = rel.rsplit("/", 1)[-1]
    return (rel.startswith(SKIP_PREFIXES) or rel in ANDROID_EXCLUDE
            or name.startswith("~") or name.endswith((".TMP", ".tmp")))


def android_project(text: str) -> str:
    for name in ANDROID_DROP_AUTOLOADS:
        text = re.sub(r"^" + re.escape(name) + r'=".*"\r?\n', "", text, flags=re.M)
    return text


def set_param(text: str, key: str, value: str) -> str:
    pat = re.compile(r"^" + re.escape(key) + r"=.*$", re.M)
    if pat.search(text):
        return pat.sub(key + "=" + value, text)
    return text.replace("\n[params]\n", "\n[params]\n\n" + key + "=" + value, 1) if "\n[params]\n" in text else text


def android_import(rel: str, text: str) -> str:
    image = rel[: -len(".import")]
    if re.search(r"^compress/mode=0$", text, re.M) and image.startswith(LOSSY_DIRS):
        text = set_param(text, "compress/mode", "1")
        text = set_param(text, "compress/lossy_quality", LOSSY_QUALITY)
    return set_param(text, "process/size_limit", MAX_SIZE)


def write_if_changed(path: str, data: bytes, dry: bool) -> bool:
    if os.path.exists(path):
        with open(path, "rb") as f:
            if f.read() == data:
                return False
    if not dry:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
    return True


def main() -> None:
    dry = "--dry-run" in sys.argv
    copied = rewritten = 0
    removed: list[str] = []
    overwritten: list[str] = []  # existed in the copy with different content
    seen: set[str] = set()
    for d, dirs, files in os.walk(SRC):
        rel_dir = os.path.relpath(d, SRC).replace(os.sep, "/")
        rel_dir = "" if rel_dir == "." else rel_dir + "/"
        dirs[:] = [x for x in dirs if not skipped(rel_dir + x + "/")]
        for name in files:
            rel = rel_dir + name
            if skipped(rel):
                continue
            seen.add(rel)
            src, dst = os.path.join(SRC, rel), os.path.join(DST, rel)
            if rel == "project.godot":
                with open(src, "rb") as f:
                    data = android_project(f.read().decode("utf-8")).encode("utf-8")
                if write_if_changed(dst, data, dry):
                    rewritten += 1
            elif IMAGE_IMPORT.search(name):
                with open(src, encoding="utf-8") as f:
                    data = android_import(rel, f.read()).encode("utf-8")
                if write_if_changed(dst, data, dry):
                    rewritten += 1
            elif not os.path.exists(dst) or not filecmp.cmp(src, dst, shallow=True):
                copied += 1
                if os.path.exists(dst) and not filecmp.cmp(src, dst, shallow=False):
                    overwritten.append(rel)
                if not dry:
                    os.makedirs(os.path.dirname(dst), exist_ok=True)
                    shutil.copy2(src, dst)
    for rel in EXTRA_FILES:
        src = os.path.join(SRC, rel)
        if os.path.exists(src):
            seen.add(rel)
            with open(src, "rb") as f:
                if write_if_changed(os.path.join(DST, rel), f.read(), dry):
                    copied += 1
    # Remove files deleted from the main project. Never touches skipped paths
    # or android/ (Godot writes export-time files there in the copy).
    if os.path.isdir(DST):
        for d, dirs, files in os.walk(DST):
            rel_dir = os.path.relpath(d, DST).replace(os.sep, "/")
            rel_dir = "" if rel_dir == "." else rel_dir + "/"
            dirs[:] = [x for x in dirs if not skipped(rel_dir + x + "/") and rel_dir + x != "android"]
            for name in files:
                rel = rel_dir + name
                if rel not in seen and not skipped(rel):
                    removed.append(rel)
                    if not dry:
                        os.remove(os.path.join(d, name))
    verb = "would be" if dry else "were"
    print(f"{DST}\n  {copied} files {verb} copied, {rewritten} image imports {verb} rewritten, {len(removed)} {verb} removed")
    for label, paths in (("overwritten (changed in the copy)", overwritten), ("removed (only in the copy)", removed)):
        if paths:
            print(f"  {label}:")
            for p in paths[:40]:
                print("    " + p)
            if len(paths) > 40:
                print(f"    ... and {len(paths) - 40} more")


if __name__ == "__main__":
    main()
