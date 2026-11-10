"""Build and ship Generation Ship: Windows (Steam) and Android (Google Play).

Close Godot first (exports and the Android sync need the editor closed).

    python tools/release.py windows           # export Build/Windows: GS_game.exe + GS_game.pck + crash launcher GS.exe
    python tools/release.py android           # version code +1, sync, export the signed AAB
    python tools/release.py steam             # upload Build/Windows via steamcmd (app_build_4724920.vdf)
    python tools/release.py play [track]      # upload the AAB to Google Play (default track: internal)
    python tools/release.py promote [track] [version code]
                                              # put an already uploaded build on another track (e.g.
                                              # production) without uploading again; default: the
                                              # build on the internal track
    python tools/release.py all [track]       # all four, in that order

One-time setup:
  * Steam: uses the steamcmd that's already logged in (cached login); if it ever
    asks for Steam Guard again, run once by hand: <STEAMCMD> +login <STEAM_ACCOUNT> +quit
  * Play: a Google Cloud service account, invited in Play Console (Users and
    permissions) with "Release apps to testing tracks" (and production if wanted).
    Either its JSON key at PLAY_KEY (outside git), or — keys blocked by the org
    policy — once: your account gets "Service Account Token Creator" on it, then
        gcloud auth application-default login --impersonate-service-account=play-uploader@happycapy-releases.iam.gserviceaccount.com
    Needs:
        pip install google-api-python-client google-auth

The Android version code lives in this project's export_presets.cfg ("Android Release
(AAB)"); `android` raises it by one and commits nothing — commit export_presets.cfg after.
"""
import datetime
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
ANDROID = os.path.join(os.path.dirname(PROJECT), os.path.basename(PROJECT) + "-android")
GODOT = r"C:\Program Files (x86)\Godot 4\Godot_v4.7-stable_win64.exe"
# Steam starts GS.exe = tools/launcher (invisible unless the game crashes); the game is GS_game.exe
# with its data in GS_game.pck beside it. The data used to be inside the exe (embed_pck): 1.4 GB, a
# new file with every build, and Windows Defender holds a program that large and new back for 10
# seconds every time it starts "cold" (after each update of the game and of Defender's definitions;
# measured 2026-11-10: a never-seen 100 or 300 MB exe starts at once, a 1.4 GB one after 10.5 s).
# Under Steam that wait sometimes never ended: the launcher sat there with no game process until the
# player pressed Stop, and the second try worked. The exe alone is the 100 MB Godot player.
WIN_PRESET, WIN_OUT, WIN_LAUNCHER = "GS Windows", "Build/Windows/GS_game.exe", "Build/Windows/GS.exe"
WIN_PCK = "Build/Windows/GS_game.pck"
WIN_EXE_MAX_MB = 250   # more than this and the data is inside the exe again
CSC = r"C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"   # ships with Windows
AAB_PRESET, AAB_OUT = "Android Release (AAB)", "Build/GS.aab"
PACKAGE = "com.happycapygames.generationship"
SDK = r"C:\Users\ptmaz\Documents\HappyCapyGames\_Shared\steamworks_sdk_164\sdk\tools\ContentBuilder"
STEAMCMD = r"C:\Program Files (x86)\Steam\steamcmd\steamcmd.exe"   # has the cached login
STEAM_VDF = os.path.join(SDK, "scripts", "app_build_4724920.vdf")
STEAM_ACCOUNT = os.environ.get("STEAM_ACCOUNT", "tyrain@gmx.de")
PLAY_SERVICE_ACCOUNT = "play-uploader@happycapy-releases.iam.gserviceaccount.com"
PLAY_KEY = os.environ.get("PLAY_KEY", os.path.join(os.path.expanduser("~"), ".secrets", "play_service_account.json"))


def godot_running() -> bool:
    # only a Godot with THIS project (or its Android copy) open blocks the export: another project's
    # editor (Uprising Digital) is fine. Its command line carries --path <project> (or the project.godot path).
    ps = ["powershell", "-NoProfile", "-Command",
          "Get-CimInstance Win32_Process -Filter \"Name like 'Godot%'\" | ForEach-Object { $_.CommandLine }"]
    out = subprocess.run(ps, capture_output=True, text=True).stdout
    return "generation-ship" in out.lower().replace("\\", "/").replace("%20", " ")


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
    exe, pck = os.path.join(PROJECT, WIN_OUT), os.path.join(PROJECT, WIN_PCK)
    if not os.path.exists(pck) or os.path.getsize(exe) > WIN_EXE_MAX_MB * 1024 * 1024:
        sys.exit("the Windows export must not embed its data (preset '%s': binary_format/embed_pck=false): "
                 "see the note at WIN_PRESET" % WIN_PRESET)
    print("data", pck, os.path.getsize(pck) // (1024 * 1024), "MB")
    src = os.path.join(HERE, "launcher")
    run([CSC, "-nologo", "-codepage:65001", "-target:winexe", "-optimize+", "-win32icon:gs.ico",
         "-r:System.Windows.Forms.dll", "-r:System.Drawing.dll", "-r:System.Management.dll",
         "-out:" + os.path.join(PROJECT, WIN_LAUNCHER), "Launcher.cs"], cwd=src)
    # build.txt: which build a crash report came from
    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=PROJECT, capture_output=True, text=True).stdout.strip()
    with open(os.path.join(PROJECT, os.path.dirname(WIN_OUT), "build.txt"), "w", encoding="utf-8") as f:
        f.write("%s %s" % (datetime.date.today().isoformat(), commit))
    print("launcher", WIN_LAUNCHER, "+ build.txt")


def android() -> None:
    bump_version_code()
    run([sys.executable, os.path.join(HERE, "sync_android.py")])
    export(ANDROID, AAB_PRESET, AAB_OUT)


def steam() -> None:
    run([STEAMCMD, "+login", STEAM_ACCOUNT, "+run_app_build", STEAM_VDF, "+quit"])


def play_api():
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    import socket
    socket.setdefaulttimeout(300)
    scopes = ["https://www.googleapis.com/auth/androidpublisher"]
    if os.path.exists(PLAY_KEY):
        creds = service_account.Credentials.from_service_account_file(PLAY_KEY, scopes=scopes)
    else:
        # no key file (the org policy blocks keys): the gcloud login, acting as the
        # service account — `gcloud auth application-default login
        # --impersonate-service-account=<service account e-mail>`
        import google.auth
        creds, _ = google.auth.default(scopes=scopes)
    return build("androidpublisher", "v3", credentials=creds, cache_discovery=False)


def play(track: str = "internal") -> None:
    from googleapiclient.http import MediaFileUpload
    edits = play_api().edits()
    edit_id = edits.insert(packageName=PACKAGE, body={}).execute()["id"]
    # 8 MB pieces with retries: the default 100 MB piece outlasts the 60 s socket
    # timeout on a home upload link
    media = MediaFileUpload(os.path.join(ANDROID, AAB_OUT), mimetype="application/octet-stream",
                            resumable=True, chunksize=8 * 1024 * 1024)
    req = edits.bundles().upload(packageName=PACKAGE, editId=edit_id, media_body=media)
    bundle = None
    while bundle is None:
        status, bundle = req.next_chunk(num_retries=5)
        if status:
            print("  uploaded %d%%" % int(status.progress() * 100), flush=True)
    code = str(bundle["versionCode"])
    edits.tracks().update(packageName=PACKAGE, editId=edit_id, track=track, body={
        "track": track, "releases": [{"versionCodes": [code], "status": "completed"}]}).execute()
    edits.commit(packageName=PACKAGE, editId=edit_id).execute()
    print("Play: version code %s released to the %s track" % (code, track))


def promote(track: str = "production", code: str = "") -> None:
    edits = play_api().edits()
    edit_id = edits.insert(packageName=PACKAGE, body={}).execute()["id"]
    if not code:
        internal = edits.tracks().get(packageName=PACKAGE, editId=edit_id, track="internal").execute()
        codes = [c for r in internal.get("releases", []) for c in r.get("versionCodes", [])]
        if not codes:
            sys.exit("nothing on the internal track to promote")
        code = max(codes, key=int)
    from googleapiclient.errors import HttpError
    edits.tracks().update(packageName=PACKAGE, editId=edit_id, track=track, body={
        "track": track, "releases": [{"versionCodes": [code], "status": "completed"}]}).execute()
    try:
        edits.commit(packageName=PACKAGE, editId=edit_id).execute()
    except HttpError as e:
        # an app that was never published ("draft app") only takes draft releases through the
        # API: the first one is sent for review by hand in the Play Console
        if "draft app" not in str(e):
            raise
        edit_id = edits.insert(packageName=PACKAGE, body={}).execute()["id"]
        edits.tracks().update(packageName=PACKAGE, editId=edit_id, track=track, body={
            "track": track, "releases": [{"versionCodes": [code], "status": "draft"}]}).execute()
        edits.commit(packageName=PACKAGE, editId=edit_id).execute()
        print("Play: the app isn't published yet - version code %s is a DRAFT release on the %s track;"
              " send it for review in the Play Console (Publishing overview)" % (code, track))
        return
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
    if step == "promote":
        promote(args[1] if len(args) > 1 else "production", args[2] if len(args) > 2 else "")


if __name__ == "__main__":
    main()
