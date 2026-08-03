# Steam upload — Generation Ship Demo (App 5006020)

SteamPipe scripts for uploading the demo build to Steamworks. Separate from
the main game's app (4724920, see `steam_appid.txt`) — demos need their own
App ID on Steam.

## One-time setup

1. In the [Steamworks partner site](https://partner.steamgames.com), under
   App 5006020 > SteamPipe > Depots, create a depot per platform you plan to
   ship (Windows/Mac/Linux) and note their Depot IDs.
2. Replace the `REPLACE_WITH_..._DEPOT_ID` placeholders in
   `app_build_5006020.vdf` and the matching `depot_build_*.vdf` file with
   those real IDs.
3. Make sure the Steam account you'll build with has publishing permissions
   on App 5006020.

## Every time you upload

1. Export the build(s) from Godot (Project > Export, or the CLI equivalent)
   using the presets in `export_presets.cfg` — "GS Windows", "macOS", "Linux".
   This writes to `Build/Windows/`, `Build/Mac/GS.zip`, `Build/Linux/GS.zip`.
2. Mac and Linux export as zips — unzip each into its own `Build/<Platform>/`
   folder in place (so `Build/Mac/Generation Ship.app` and `Build/Linux/GS`
   exist directly on disk). Skip a platform entirely if you're only shipping
   Windows for now — just remove its line from the `depots` block in
   `app_build_5006020.vdf`.
3. Run:
   ```
   .\upload_demo.ps1 -Username your_steam_builder_account
   ```
   steamcmd will prompt for the password and, if needed, a Steam Guard code —
   it's never passed as an argument or stored anywhere here.
4. The build lands in Steamworks but isn't live on any branch yet (see the
   `setlive` note in `app_build_5006020.vdf`). Push it live from the
   Steamworks "Builds" tab once you've smoke-tested it.

## Notes

- `SteamBuildOutput/` (steamcmd's own log/cache folder, gitignored) gets
  created next to this folder on first run — safe to delete anytime.
- The Linux depot script marks the `GS` binary executable explicitly
  (`posixexecutable`), since uploading from Windows otherwise drops the
  Unix executable bit.
