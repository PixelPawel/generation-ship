extends Node
## Autoload singleton. Host-authoritative networking: the host holds the only
## GameState that matters. Every peer (including the host's own UI) submits
## action *requests*; only the host validates and applies them, then
## broadcasts the resulting authoritative state to everyone. This keeps a
## single source of truth and sidesteps a whole class of desync bugs, which
## matters a lot more for a rules-heavy game like this than raw bandwidth
## efficiency -- so v1 broadcasts the full state dict rather than deltas.

signal state_updated(state: GameState)
signal action_rejected(reason: String)
signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal connection_failed
signal connected_to_host
signal lobby_claims_updated(claims: Dictionary)
signal game_starting(state: GameState)

const DEFAULT_PORT := 8910

var is_host: bool = false
var game_state: GameState = null

## Lobby-phase-only state, before game_state exists: faction (String) ->
## {"peer_id": int, "hero": String}. Host-authoritative like everything
## else here; see request_claim/request_release/start_game below.
var lobby_claims: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(func() -> void: connection_failed.emit())
	multiplayer.connected_to_server.connect(func() -> void: connected_to_host.emit())


## No GameState yet -- that's built later by start_game(), once players
## have claimed factions in the Lobby. (The old dev-shortcut path that
## skips the Lobby entirely builds its own state first and assigns
## game_state directly; see game_board.gd._start_hosted_game().)
func host_game(port: int = DEFAULT_PORT, max_players: int = 4) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_players)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	return OK


func disconnect_game() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	is_host = false
	game_state = null
	lobby_claims = {}


func _on_peer_connected(id: int) -> void:
	peer_connected.emit(id)
	if not is_host:
		return
	if game_state != null:
		_receive_full_state.rpc_id(id, game_state.to_dict())
	else:
		_receive_lobby_claims.rpc_id(id, lobby_claims)


func _on_peer_disconnected(id: int) -> void:
	peer_disconnected.emit(id)
	if is_host and game_state == null:
		_apply_release(id)  # free up whatever faction they'd claimed in the Lobby


# ---------------------------------------------------------------------------
# Lobby: faction claiming, ahead of any GameState existing
# ---------------------------------------------------------------------------

## Claims `faction` (with `hero`) for the calling peer, releasing any other
## faction they'd already claimed first -- a peer only ever holds one.
## Silently ignored if `faction` is already claimed by a DIFFERENT peer
## (first-come-first-served; the host's arrival order is authoritative).
func request_claim(faction: String, hero: String) -> void:
	if is_host:
		_apply_claim(faction, hero, multiplayer.get_unique_id())
	else:
		_request_claim.rpc_id(1, faction, hero)


@rpc("any_peer", "call_remote", "reliable")
func _request_claim(faction: String, hero: String) -> void:
	if not is_host:
		return
	_apply_claim(faction, hero, multiplayer.get_remote_sender_id())


func _apply_claim(faction: String, hero: String, peer_id: int) -> void:
	if lobby_claims.has(faction) and int((lobby_claims[faction] as Dictionary)["peer_id"]) != peer_id:
		return
	for f in lobby_claims.keys():
		if int((lobby_claims[f] as Dictionary)["peer_id"]) == peer_id:
			lobby_claims.erase(f)
	lobby_claims[faction] = {"peer_id": peer_id, "hero": hero}
	_broadcast_lobby_claims()


## Releases whatever faction the calling peer currently holds, if any.
func request_release() -> void:
	if is_host:
		_apply_release(multiplayer.get_unique_id())
	else:
		_request_release.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_release() -> void:
	if not is_host:
		return
	_apply_release(multiplayer.get_remote_sender_id())


func _apply_release(peer_id: int) -> void:
	for f in lobby_claims.keys():
		if int((lobby_claims[f] as Dictionary)["peer_id"]) == peer_id:
			lobby_claims.erase(f)
			break
	_broadcast_lobby_claims()


func _broadcast_lobby_claims() -> void:
	_receive_lobby_claims.rpc(lobby_claims)


@rpc("authority", "call_local", "reliable")
func _receive_lobby_claims(claims: Dictionary) -> void:
	lobby_claims = claims
	lobby_claims_updated.emit(claims)


## Host-only: builds the GameState from the current lobby_claims -- any of
## `all_factions` nobody claimed becomes a "simple dummy" bot (see
## PlayerFactionState.is_bot) with a default Hero rather than being left
## out of the game or forcing a human to run two factions. Walks the fresh
## state through GameFlow up to Actions Phase (same as a real Chapter
## start), then broadcasts it so every connected peer -- including the
## host itself, via call_local -- transitions into the real game.
func start_game(all_factions: Array, difficulty: String, max_chapters: int) -> void:
	if not is_host:
		return
	var pairs: Array = []
	for faction in all_factions:
		if lobby_claims.has(faction):
			var c: Dictionary = lobby_claims[faction]
			pairs.append([faction, c["hero"], int(c["peer_id"]), false])
		else:
			pairs.append([faction, _default_hero_for(faction), -1, true])

	var state := GameSetup.build_new_game(CardDatabase, pairs, difficulty, max_chapters)
	GameFlow.advance_phase(state, CardDatabase)  # REFRESH -> EVENTS
	GameFlow.advance_phase(state, CardDatabase)  # EVENTS -> BUILD
	GameFlow.advance_phase(state, CardDatabase)  # BUILD -> ACTIONS
	game_state = state
	_game_starting.rpc(state.to_dict())


func _default_hero_for(faction: String) -> String:
	for h in CardDatabase.heroes:
		if h.lang == "EN" and h.box == "Core" and h.faction == faction:
			return h.card_name
	return ""


@rpc("authority", "call_local", "reliable")
func _game_starting(state_dict: Dictionary) -> void:
	game_state = GameState.from_dict(state_dict)
	game_starting.emit(game_state)


## Call this from game logic on ANY peer (host or client) to request an
## action. Actions are plain Dictionaries, e.g. {"type": "move", "faction":
## "Krowh", "to": [1, 0]} -- kept as data (not custom objects) so they marshal
## over RPC with no extra work and double as a natural action-log format.
func submit_action(action: Dictionary) -> void:
	if is_host:
		_apply_action(action, multiplayer.get_unique_id())
	else:
		_request_action.rpc_id(1, action)


@rpc("any_peer", "call_remote", "reliable")
func _request_action(action: Dictionary) -> void:
	if not is_host:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_apply_action(action, sender_id)


func _apply_action(action: Dictionary, sender_id: int) -> void:
	if game_state == null:
		_reject(sender_id, "no active game")
		return
	var result := GameActions.apply(game_state, action, sender_id, CardDatabase)
	if not result.get("ok", false):
		_reject(sender_id, result.get("reason", "action rejected"))
		return
	_receive_full_state.rpc(game_state.to_dict())


## Requests moving to the next Phase (GameFlow.advance_phase) -- separate
## from submit_action() since it isn't scoped to one faction; any connected
## peer can request it (e.g. whoever notices everyone's done with Actions).
## A refusal (still waiting on active players, etc.) surfaces the same way a
## rejected action does, via action_rejected.
func submit_advance_phase() -> void:
	if is_host:
		_apply_advance_phase(multiplayer.get_unique_id())
	else:
		_request_advance_phase.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_advance_phase() -> void:
	if not is_host:
		return
	_apply_advance_phase(multiplayer.get_remote_sender_id())


func _apply_advance_phase(sender_id: int) -> void:
	if game_state == null:
		_reject(sender_id, "no active game")
		return
	var result := GameFlow.advance_phase(game_state, CardDatabase)
	if not result.get("ok", false):
		_reject(sender_id, result.get("reason", "cannot advance yet"))
		return
	_receive_full_state.rpc(game_state.to_dict())


func _reject(sender_id: int, reason: String) -> void:
	if sender_id == multiplayer.get_unique_id():
		action_rejected.emit(reason)
	else:
		_notify_rejected.rpc_id(sender_id, reason)


@rpc("authority", "call_remote", "reliable")
func _notify_rejected(reason: String) -> void:
	action_rejected.emit(reason)


@rpc("authority", "call_local", "reliable")
func _receive_full_state(state_dict: Dictionary) -> void:
	game_state = GameState.from_dict(state_dict)
	state_updated.emit(game_state)
