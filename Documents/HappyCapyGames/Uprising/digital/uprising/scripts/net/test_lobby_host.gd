extends SceneTree
## Headless networking smoke test (host side) for the Lobby claim flow. Run
## alongside test_lobby_client.gd:
##   godot --headless --script res://scripts/net/test_lobby_host.gd
##   godot --headless --script res://scripts/net/test_lobby_client.gd
## Verifies a real ENet round trip: client connects, claims a faction, host
## sees the claim, host starts the game (Druwhn left unclaimed -> bot), and
## the resulting GameState is correct on the host's own side. See
## test_lobby_client.gd for what the client itself should observe.

const PORT := 8935  # distinct from test_host.gd's PORT, so both suites could run concurrently
const MAX_WAIT_FRAMES := 3600  # ~60s at 60fps


func _initialize() -> void:
	await process_frame
	var net_mgr := root.get_node("/root/NetworkManager")

	var err: Error = net_mgr.host_game(PORT)
	print("HOST host_game result: ", err, " (OK == 0)")

	# See test_client.gd for why this is a 1-element Array, not a plain bool.
	var claimed := [false]
	net_mgr.lobby_claims_updated.connect(func(claims: Dictionary) -> void:
		if claims.has("Krowh"):
			claimed[0] = true
	)

	var frames := 0
	while frames < MAX_WAIT_FRAMES and not claimed[0]:
		await process_frame
		frames += 1
	print("HOST saw claim=", claimed[0], " claims=", net_mgr.lobby_claims, " frames_waited=", frames)

	if not claimed[0]:
		print("HOST FAILED: never saw the client's claim")
		quit(1)
		return

	var client_peer_id: int = int(net_mgr.lobby_claims["Krowh"]["peer_id"])
	var hero_ok: bool = net_mgr.lobby_claims["Krowh"]["hero"] == "Kha'al"
	var peer_id_ok: bool = client_peer_id != 1 and client_peer_id != net_mgr.multiplayer.get_unique_id()

	net_mgr.start_game(["Druwhn", "Duerkhar", "Krowh", "Mohyar"], "Veteran", 3)
	await process_frame

	var krowh = net_mgr.game_state.get_player("Krowh") if net_mgr.game_state != null else null
	var druwhn = net_mgr.game_state.get_player("Druwhn") if net_mgr.game_state != null else null
	var krowh_ok: bool = krowh != null and not krowh.is_bot and krowh.controlled_by_peer_id == client_peer_id
	var bot_ok: bool = druwhn != null and druwhn.is_bot

	print(
		"HOST result: hero_ok=", hero_ok, " peer_id_ok=", peer_id_ok,
		" krowh_ok=", krowh_ok, " bot_ok=", bot_ok
	)
	var ok: bool = claimed[0] and hero_ok and peer_id_ok and krowh_ok and bot_ok
	print("HOST done. ok=", ok)
	quit(0 if ok else 1)
