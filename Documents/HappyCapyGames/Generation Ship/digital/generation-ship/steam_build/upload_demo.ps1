# Uploads the Generation Ship Demo (Steam App 5006020) to Steamworks via
# SteamPipe. Does NOT set anything live on a branch (see app_build_5006020.vdf)
# — the build lands in Steamworks and stays inactive until pushed live
# manually from the "Builds" tab.
#
# Usage:
#   .\upload_demo.ps1 -Username your_steam_builder_account
#
# steamcmd prompts interactively for the password and, if needed, a Steam
# Guard code — never pass the password as a script argument or hardcode it
# here.

param(
	[Parameter(Mandatory = $true)]
	[string]$Username,

	[string]$SteamCmdPath = "C:\Program Files (x86)\Steam\steamcmd\steamcmd.exe"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$appBuildVdf = Join-Path $scriptDir "app_build_5006020.vdf"
$projectRoot = Resolve-Path (Join-Path $scriptDir "..")

if (-not (Test-Path $SteamCmdPath)) {
	Write-Error "steamcmd.exe not found at '$SteamCmdPath'. Pass -SteamCmdPath, or install it from https://developer.valvesoftware.com/wiki/SteamCMD."
	exit 1
}

foreach ($vdf in @("app_build_5006020.vdf", "depot_build_windows.vdf", "depot_build_mac.vdf", "depot_build_linux.vdf")) {
	$content = Get-Content (Join-Path $scriptDir $vdf) -Raw
	if ($content -match "REPLACE_WITH_") {
		Write-Error "$vdf still has a REPLACE_WITH_... placeholder depot ID. Fill in the real depot IDs from the Steamworks partner site (App 5006020 > SteamPipe > Depots) before uploading."
		exit 1
	}
}

$missing = @()
if (-not (Test-Path (Join-Path $projectRoot "Build\Windows\GS.exe"))) { $missing += "Build\Windows\GS.exe" }
if (-not (Test-Path (Join-Path $projectRoot "Build\Mac"))) { $missing += "Build\Mac\" }
if (-not (Test-Path (Join-Path $projectRoot "Build\Linux\GS"))) { $missing += "Build\Linux\GS" }
if ($missing.Count -gt 0) {
	Write-Warning "Missing expected build output: $($missing -join ', '). Export the missing platform(s) from Godot (or remove that depot from app_build_5006020.vdf) before uploading."
}

Write-Host "Running SteamPipe build for app 5006020 as $Username..."
& $SteamCmdPath +login $Username +run_app_build $appBuildVdf +quit
