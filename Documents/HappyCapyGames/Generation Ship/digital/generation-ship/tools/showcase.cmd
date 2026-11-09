@echo off
rem Screenshot set-up (scripts/game/showcase.gd): starts the game with --showcase.
rem In the game: Versus, add three bots (they become Pixel Pawel, Cornelius and Communi-Kate), Start.
rem After the opening deal every ship fills up (Generation 3); the game then plays on as usual.
start "" "C:\Program Files (x86)\Godot 4\Godot_v4.7-stable_win64.exe" --path "%~dp0.." -- --showcase
