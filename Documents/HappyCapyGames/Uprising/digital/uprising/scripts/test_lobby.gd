extends SceneTree
## Headless smoke test: `godot --headless --script res://scripts/test_lobby.gd`
## Exercises NetworkManager's Lobby claim/release/start_game logic directly
## as the host (is_host lets request_claim/request_release skip the RPC
## layer and hit _apply_claim/_apply_release synchronously), plus the Lobby
## scene's claim-button wiring. Other peers' claims are simulated by
## calling _apply_claim/_apply_release with an arbitrary peer_id directly --
## the same "call the underscore-prefixed handler straight" pattern used
## throughout this test suite. See test_lobby_host.gd/test_lobby_client.gd
## for a real 2-process ENet round trip of the same claim flow.

const TEST_PORT := 8934  # distinct from NetworkManager.DEFAULT_PORT, so a real run isn't disturbed

var checks: Array = []


func _check(label: String, ok: bool) -> void:
	checks.append([label, ok])


func _initialize() -> void:
	await process_frame
	var net_mgr := root.get_node("/root/NetworkManager")

	var err: Error = net_mgr.host_game(TEST_PORT)
	_check("host_game succeeds", err == OK)
	_check("is_host true after hosting", net_mgr.is_host)
	_check("lobby_claims starts empty", net_mgr.lobby_claims.is_empty())

	# --- Claiming (host's own peer_id is always 1) ---
	var my_id: int = net_mgr.multiplayer.get_unique_id()
	net_mgr.request_claim("Druwhn", "Fhayanor")
	_check("claim recorded", net_mgr.lobby_claims.has("Druwhn"))
	_check(
		"claim carries the right peer_id and hero",
		int(net_mgr.lobby_claims["Druwhn"]["peer_id"]) == my_id and net_mgr.lobby_claims["Druwhn"]["hero"] == "Fhayanor"
	)

	# --- Switching factions releases the old one -- nobody holds two ---
	net_mgr.request_claim("Krowh", "Dugpa")
	_check("claiming a new faction releases the old one", not net_mgr.lobby_claims.has("Druwhn"))
	_check("new faction claimed", net_mgr.lobby_claims.has("Krowh"))

	# --- A different (simulated) peer can't steal an already-claimed faction ---
	net_mgr._apply_claim("Krowh", "Kha'al", 7)
	_check("a different peer can't steal an already-claimed faction", int(net_mgr.lobby_claims["Krowh"]["peer_id"]) == my_id)

	# --- ...but can claim a different, open one ---
	net_mgr._apply_claim("Duerkhar", "Yanny", 7)
	_check("a different peer can claim an open faction", int(net_mgr.lobby_claims["Duerkhar"]["peer_id"]) == 7)

	# --- Releasing frees the faction for someone else ---
	net_mgr._apply_release(7)
	_check("release frees the faction", not net_mgr.lobby_claims.has("Duerkhar"))

	# --- start_game fills unclaimed factions with bots ---
	net_mgr._apply_claim("Duerkhar", "Baranth", 7)  # Krowh(host)+Duerkhar(7) claimed, Druwhn/Mohyar open
	net_mgr.start_game(["Druwhn", "Duerkhar", "Krowh", "Mohyar"], "Veteran", 3)
	_check("start_game populates game_state", net_mgr.game_state != null)
	_check("4 players in the started game", net_mgr.game_state.players.size() == 4)

	var krowh: PlayerFactionState = net_mgr.game_state.get_player("Krowh")
	_check("claimed faction is not a bot", krowh != null and not krowh.is_bot)
	_check("claimed faction keeps its claimed Hero and peer_id", krowh.hero_name == "Dugpa" and krowh.controlled_by_peer_id == my_id)

	var duerkhar: PlayerFactionState = net_mgr.game_state.get_player("Duerkhar")
	_check("2nd claimed faction correct", duerkhar != null and not duerkhar.is_bot and duerkhar.controlled_by_peer_id == 7)

	var druwhn: PlayerFactionState = net_mgr.game_state.get_player("Druwhn")
	_check("unclaimed faction becomes a bot", druwhn != null and druwhn.is_bot)
	_check("bot got a real default Hero, not blank", druwhn.hero_name != "")
	_check("bot has no controlling peer", druwhn.controlled_by_peer_id == -1)

	var mohyar: PlayerFactionState = net_mgr.game_state.get_player("Mohyar")
	_check("2nd unclaimed faction also becomes a bot", mohyar != null and mohyar.is_bot)

	_check("started game is already in Actions Phase", net_mgr.game_state.phase == GameState.Phase.ACTIONS)
	_check("bots are already marked has_passed (simple dummy, never acts)", druwhn.has_passed and mohyar.has_passed)
	_check("claimed factions have NOT auto-passed", not krowh.has_passed and not duerkhar.has_passed)

	net_mgr.disconnect_game()
	_check("disconnect_game clears lobby_claims", net_mgr.lobby_claims.is_empty())
	_check("disconnect_game clears game_state", net_mgr.game_state == null)

	# --- Lobby scene UI wiring ---
	var scene: PackedScene = load("res://scenes/lobby.tscn")
	var lobby := scene.instantiate()
	root.add_child(lobby)
	await process_frame

	_check("setup panel visible before connecting", lobby._setup_panel.visible)
	_check("room panel hidden before connecting", not lobby._room_panel.visible)

	lobby._on_start_hosting_pressed()
	_check("room panel visible after hosting", lobby._room_panel.visible)
	_check("setup panel hidden after hosting", not lobby._setup_panel.visible)
	_check("Start Game button visible for the host", lobby._start_game_button.visible)

	var druwhn_button: Button = lobby._faction_claim_buttons["Druwhn"]
	_check("faction row starts as Open/Claim", druwhn_button.text == "Claim")

	# _apply_claim's own broadcast round-trips through an RPC (even for the
	# host's own call_local delivery) before lobby.gd's _refresh_room()
	# actually updates button text -- not synchronous, same reason every
	# other NetworkManager-driven UI test here waits a few frames post-action.
	lobby._on_claim_pressed("Druwhn")
	for i in 5:
		await process_frame
	_check("pressing Claim claims the faction", net_mgr.lobby_claims.has("Druwhn"))
	_check("claim button now offers Release", druwhn_button.text == "Release")

	lobby._on_claim_pressed("Druwhn")
	for i in 5:
		await process_frame
	_check("pressing Release frees the faction again", not net_mgr.lobby_claims.has("Druwhn"))
	_check("claim button offers Claim again", druwhn_button.text == "Claim")

	net_mgr.disconnect_game()

	var all_ok := true
	for c in checks:
		var label: String = c[0]
		var ok: bool = c[1]
		print(("OK   " if ok else "FAIL "), label)
		if not ok:
			all_ok = false

	print("\nALL CHECKS %s" % ("PASSED" if all_ok else "FAILED"))
	quit(0 if all_ok else 1)
