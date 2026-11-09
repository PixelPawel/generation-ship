extends RefCounted
## Bot-vs-bot test games (2026-11-09, to make the bots stronger and measure it): with the command-line flag
## --botsim the main menu starts an offline Versus game with three bots by itself, the player's seat passes
## every turn and every bid (so the bots play each other), the game runs sped up, and at the end each bot's
## score and score lines are appended to a JSON-lines file; then the game quits. No leaderboard submission,
## no Steam. Run headless from tools/bot_league.py. Preloaded (no class_name).
##   --botsim                      on
##   --botsim-diff=2,2,2           the three bots' difficulties (0 Easy, 1 Normal, 2 Hard)
##   --botsim-seed=N               shuffles (global RNG)
##   --botsim-speed=30             Engine.time_scale
##   --botsim-out=<file.jsonl>     results (default user://botsim.jsonl)

static func active() -> bool:
	return OS.get_cmdline_user_args().has("--botsim")

static func _arg(key: String, fallback: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return a.trim_prefix(key + "=")
	return fallback

static func difficulties() -> Array[int]:
	var out: Array[int] = []
	for s: String in _arg("--botsim-diff", "2,2,2").split(",", false):
		out.append(int(s))
	return out

## Main menu: what Versus, Add Bot x3 (at the chosen difficulties) and Start would do.
static func start_from_menu(menu: Control) -> void:
	seed(int(_arg("--botsim-seed", "1")))
	Engine.time_scale = float(_arg("--botsim-speed", "30"))
	await menu.get_tree().create_timer(0.5).timeout
	var lobby: Control = menu.get_node("Panels/LobbyView") as Control
	lobby.call("set_coop", false)
	lobby.set("_player_name", "Sim")
	lobby.call("_start_offline_host")
	var diff_btn: OptionButton = lobby.get("_diff_btn") as OptionButton
	for d: int in difficulties():
		if diff_btn:
			diff_btn.selected = d
		lobby.call("_on_add_bot_pressed")
	lobby.call("_on_start_pressed")

## Main: the player's seat never plays — it passes as soon as it is its turn.
static func auto_pass(main: Main) -> void:
	if GameNetwork.is_my_turn() and not bool(main.get("_has_passed")) and not bool(main.get("_game_finished")):
		main.call_deferred("_do_pass")

## Main, game over: every bot's final score and lines, one JSON line, then quit.
static func record(main: Main) -> void:
	var bots: Array = []
	for bot_id: int in GameNetwork.bot_ids:
		var board: Array = main.bot_boards.get(bot_id, []) as Array
		Scoring.other_players_expeditions = main._alliance_count_for(bot_id)
		var lines: Array = []
		for l: Dictionary in BotScoring.board_vp_lines(board):
			lines.append({"label": str(l.get("label", "")), "vp": int(l.get("vp", 0))})
		var sectors: Array = []
		for e_v: Variant in board:
			var e: Dictionary = e_v as Dictionary
			var cd: CardData = e.get("sector") as CardData
			var adv: bool = bool(e.get("is_advanced", false))
			sectors.append({"name": (cd.adv_name if adv else cd.card_name) if cd else "?", "adv": adv,
					"cards": (e.get("techs", []) as Array).size(), "tucked": (e.get("tucked_cards", []) as Array).size()})
		bots.append({"id": bot_id, "name": str(GameNetwork.player_names.get(bot_id, "")),
				"diff": int(GameNetwork.bot_difficulty.get(bot_id, 0)), "vp": BotScoring.board_vp(board),
				"lines": lines, "sectors": sectors, "supply": main.bot_supplies.get(bot_id, {})})
	var row: Dictionary = {"seed": int(_arg("--botsim-seed", "1")), "rounds": int(main.get("_round")), "bots": bots}
	var path: String = _arg("--botsim-out", "user://botsim.jsonl")
	var f: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(JSON.stringify(row))
		f.close()
	print("botsim: ", JSON.stringify(row))
	main.get_tree().quit()
