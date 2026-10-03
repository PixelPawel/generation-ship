"""Build and ship Generation Ship: Windows (Steam) and Android (Google Play).

Close Godot first (exports and the Android sync need the editor closed).

    python tools/release.py windows           # export Build/Windows/GS.exe
    python tools/release.py android           # version code +1, sync, export the signed AAB
    python tools/release.py steam             # upload Build/Windows via steamcmd (app_build_4724920.vdf)
    python tools/release.py play [track]      # upload the AAB to Google Play (default track: internal)
    python tools/release.py all [track]       # all four, in that order

One-time setup:
  * Steam: uses the steamcmd that's already logged in (cached login); if it ever
    asks for Steam Guard again, run once by hand: <STEAMCMD> +login <STEAM_ACCOUNT> +quit
  * Play: a Google Cloud service account, invited in Play Console (Users and
    permissions) with "Release apps to testing tracks" (and production if wanted).
    Either its JSON key at PLAY_KEY (outside git), or — keys blocked by the org
    policy — once: your account gets "Service Account Token Creator" on it, then
        gcloud auth application-default login --impersonate-service-account=<its e-mail>
    Needs:
        pip install google-api-python-client google-auth

The Android version code lives in this project's export_presets.cfg ("Android Release
(AAB)"); `android` raises it by one and commits nothing — commit export_presets.cfg after.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
ANDROID = os.path.join(os.path.dirname(PROJECT), os.path.basename(PROJECT) + "-android")
GODOT = r"C:\Program Files (x86)\Godot 4\Godot_v4.7-stable_win64.exe"
WIN_PRESET, WIN_OUT = "GS Windows", "Build/Windows/GS.exe"
AAB_PRESET, AAB_OUT = "Android Release (AAB)", "Build/GS.aab"
PACKAGE = "com.happycapygames.generationship"
SDK = r"C:\Users\ptmaz\Documents\HappyCapyGames\steamworks_sdk_164\sdk\tools\ContentBuilder"
STEAMCMD = r"C:\Program Files (x86)\Steam\steamcmd\steamcmd.exe"   # has the cached login
STEAM_VDF = os.path.join(SDK, "scripts", "app_build_4724920.vdf")
STEAM_ACCOUNT = os.environ.get("STEAM_ACCOUNT", "tyrain@gmx.de")
PLAY_KEY = os.environ.get("PLAY_KEY", os.path.join(os.path.expanduser("~"), ".secrets", "play_service_account.json"))


def godot_running() -> bool:
    out = subprocess.run(["tasklist"], capture_output=True, text=True).stdout
    return "Godot_v4" in out


def run(cmd: list[str], cwd: str | None = None) -> None:
    print(">", " ".join(cmd))
    r = subprocess.run(cmd, cwd=cwd)
    if r.returncode != 0:
        sys.exit(f"failed ({r.returncode}): {cmd[0]}")


def export(project: str, preset: str, out: str) -> None:
    os.makedirs(os.path.join(project, os.path.dirname(out)), exist_ok=True)
    run([GODOT, "--headless", "--path", project, "--export-release", preset, out])
    path = os.path.join(project, out)
    if not os.path.exists(path):
        sys.exit("export produced no file: " + path)
    print("built", path, os.path.getsize(path) // (1024 * 1024), "MB")


def bump_version_code() -> int:
    p = os.path.join(PROJECT, "export_presets.cfg")
    s = open(p, encoding="utf-8").read()
    i = s.index('name="%s"' % AAB_PRESET)
    j = s.index("\n[preset.", i)                       # its [preset.N.options] header
    k = s.find("\n[preset.", j + 5)
    k = len(s) if k < 0 else k
    m = re.search(r"^version/code=(\d+)$", s[j:k], re.M)
    code = int(m.group(1)) + 1
    s = s[:j] + re.sub(r"^version/code=\d+$", "version/code=%d" % code, s[j:k], count=1, flags=re.M) + s[k:]
    open(p, "w", encoding="utf-8", newline="").write(s)
    print("Android version code ->", code)
    return code


def windows() -> None:
    export(PROJECT, WIN_PRESET, WIN_OUT)


def android() -> None:
    bump_version_code()
    run([sys.executable, os.path.join(HERE, "sync_android.py")])
    export(ANDROID, AAB_PRESET, AAB_OUT)


def steam() -> None:
    run([STEAMCMD, "+login", STEAM_ACCOUNT, "+run_app_build", STEAM_VDF, "+quit"])


def play(track: str = "internal") -> None:
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaFileUpload
    scopes = ["https://www.googleapis.com/auth/androidpublisher"]
    if os.path.exists(PLAY_KEY):
        creds = service_account.Credentials.from_service_account_file(PLAY_KEY, scopes=scopes)
    else:
        # no key file (the org policy blocks keys): the gcloud login, acting as the
        # service account — `gcloud auth application-default login
        # --impersonate-service-account=<service account e-mail>`
        import google.auth
        creds, _ = google.auth.default(scopes=scopes)
    api = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)
    edits = api.edits()
    edit_id = edits.insert(packageName=PACKAGE, body={}).execute()["id"]
    media = MediaFileUpload(os.path.join(ANDROID, AAB_OUT), mimetype="application/octet-stream", resumable=True)
    bundle = edits.bundles().upload(packageName=PACKAGE, editId=edit_id, media_body=media).execute()
    code = str(bundle["versionCode"])
    edits.tracks().update(packageName=PACKAGE, editId=edit_id, track=track, body={
        "track": track, "releases": [{"versionCodes": [code], "status": "completed"}]}).execute()
    edits.commit(packageName=PACKAGE, editId=edit_id).execute()
    print("Play: version code %s released to the %s track" % (code, track))


def main() -> None:
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    step, track = args[0], (args[1] if len(args) > 1 else "internal")
    if step in ("windows", "android", "all") and godot_running():
        sys.exit("Close Godot first.")
    if step in ("windows", "all"):
        windows()
    if step in ("android", "all"):
        android()
    if step in ("steam", "all"):
        steam()
    if step in ("play", "all"):
        play(track)


if __name__ == "__main__":
    main()
