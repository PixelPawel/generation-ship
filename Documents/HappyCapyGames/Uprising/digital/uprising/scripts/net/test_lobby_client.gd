extends SceneTree
## Headless networking smoke test (client side) for the Lobby claim flow.
## Run alongside test_lobby_host.gd (see that file for the full pair
## invocation). Joins, claims Krowh/Kha'al, then waits to see the host's
## broadcast confirm it and, once the host starts the game, checks the
## received GameState has this peer correctly controlling Krowh with an
## unclaimed faction (Druwhn) filled in as a bot.

const PORT := 8935
const MAX_WAIT_FRAMES := 3600  # ~60s at 60fps


func _initialize() -> void:
	await process_frame
	var net_mgr := root.get_node("/root/NetworkManager")

	var err: Error = net_mgr.join_game("127.0.0.1", PORT)
	print("CLIENT join_game result: ", err, " (OK == 0)")

	# 1-element Arrays: a lambda captures locals BY VALUE, so a plain `var
	# connected := false` mutated inside the lambda would never be seen by
	# this outer scope -- a mutable Array cell sidesteps that (same gotcha
	# noted throughout this project's memory).
	var connected := [false]
	net_mgr.connected_to_host.connect(func() -> void: connected[0] = true)

	var frames := 0
	while frames < MAX_WAIT_FRAMES and not connected[0]:
		await process_frame
		frames += 1
	print("CLIENT connected=", connected[0], " frames_waited=", frames)
	if not connected[0]:
		print("CLIENT FAILED: never connected")
		quit(1)
		return

	net_mgr.request_claim("Krowh", "Kha'al")

	var claim_confirmed := [false]
	net_mgr.lobby_claims_updated.connect(func(claims: Dictionary) -> void:
		if claims.has("Krowh") and int(claims["Krowh"]["peer_id"]) == net_mgr.multiplayer.get_unique_id():
			claim_confirmed[0] = true
	)
	frames = 0
	while frames < MAX_WAIT_FRAMES and not claim_confirmed[0]:
		await process_frame
		frames += 1
	print("CLIENT claim_confirmed=", claim_confirmed[0], " frames_waited=", frames)
	if not claim_confirmed[0]:
		print("CLIENT FAILED: never saw its own claim echoed back")
		quit(1)
		return

	var game_started := [false]
	net_mgr.game_starting.connect(func(_state: GameState) -> void: game_started[0] = true)
	frames = 0
	while frames < MAX_WAIT_FRAMES and not game_started[0]:
		await process_frame
		frames += 1
	print("CLIENT game_started=", game_started[0], " frames_waited=", frames)
	if not game_started[0]:
		print("CLIENT FAILED: never saw the game start")
		quit(1)
		return

	var my_id: int = net_mgr.multiplayer.get_unique_id()
	var krowh = net_mgr.game_state.get_player("Krowh")
	var druwhn = net_mgr.game_state.get_player("Druwhn")
	var krowh_ok: bool = krowh != null and not krowh.is_bot and krowh.controlled_by_peer_id == my_id and krowh.hero_name == "Kha'al"
	var bot_ok: bool = druwhn != null and druwhn.is_bot and druwhn.controlled_by_peer_id == -1

	print("CLIENT result: my_id=", my_id, " krowh_ok=", krowh_ok, " bot_ok=", bot_ok)
	var ok: bool = krowh_ok and bot_ok
	print("CLIENT done. ok=", ok)
	quit(0 if ok else 1)
