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
signal lobby_bot_enabled_updated(bot_enabled: Dictionary)
signal game_starting(state: GameState)
## Fires for everyone right after a successful advance_phase(), carrying
## its full result dict (reason/event/scoring/pending_combats/game_over/
## result -- whichever keys that phase's transition returned). Separate
## from state_updated because the useful "what just happened, what do you
## do next" text lives in this ephemeral result, not in GameState itself.
signal phase_advanced(info: Dictionary)

const DEFAULT_PORT := 8910

var is_host: bool = false
var game_state: GameState = null

## Lobby-phase-only state, before game_state exists: faction (String) ->
## {"peer_id": int, "hero": String}. Host-authoritative like everything
## else here; see request_claim/request_release/start_game below.
var lobby_claims: Dictionary = {}

## Host-only decision, faction (String) -> bool: whether an unclaimed
## faction gets a bot (true, the default -- a missing entry reads as true
## via lobby_bot_enabled.get(faction, true)) or is left out of the game
## entirely (false) when start_game() runs. Broadcast to everyone so
## clients can see what the host has chosen, but only the host's own
## set_bot_enabled() call has any effect -- see there.
var lobby_bot_enabled: Dictionary = {}


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
	lobby_bot_enabled = {}


func _on_peer_connected(id: int) -> void:
	peer_connected.emit(id)
	if not is_host:
		return
	if game_state != null:
		_receive_full_state.rpc_id(id, game_state.to_dict())
	else:
		_receive_lobby_claims.rpc_id(id, lobby_claims)
		_receive_lobby_bot_enabled.rpc_id(id, lobby_bot_enabled)


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


## Host-only: whether an unclaimed faction gets a bot (the default) or is
## left out of the game entirely when start_game() runs. No-op for a
## client -- only the host's own call has any effect, but the choice is
## still broadcast so everyone can see it.
func set_bot_enabled(faction: String, enabled: bool) -> void:
	if not is_host:
		return
	lobby_bot_enabled[faction] = enabled
	_receive_lobby_bot_enabled.rpc(lobby_bot_enabled)


@rpc("authority", "call_local", "reliable")
func _receive_lobby_bot_enabled(bot_enabled: Dictionary) -> void:
	lobby_bot_enabled = bot_enabled
	lobby_bot_enabled_updated.emit(bot_enabled)


## Host-only: builds the GameState from the current lobby_claims -- any of
## `all_factions` nobody claimed becomes a "simple dummy" bot (see
## PlayerFactionState.is_bot) with a default Hero, UNLESS the host turned
## that off via set_bot_enabled(), in which case the faction is left out of
## the game entirely (the rulebook already supports fewer than 4 factions).
## Walks the fresh state through GameFlow up to Actions Phase (same as a
## real Chapter start), then broadcasts it so every connected peer --
## including the host itself, via call_local -- transitions into the real
## game. No-op (does not start anything) if that would leave zero players.
func start_game(all_factions: Array, difficulty: String, max_chapters: int) -> Dictionary:
	if not is_host:
		return {"ok": false, "reason": "only the host can start the game"}
	var pairs: Array = []
	for faction in all_factions:
		if lobby_claims.has(faction):
			var c: Dictionary = lobby_claims[faction]
			pairs.append([faction, c["hero"], int(c["peer_id"]), false])
		elif bool(lobby_bot_enabled.get(faction, true)):
			pairs.append([faction, _default_hero_for(faction), -1, true])
		# else: host turned off the bot for this faction -- excluded entirely.

	if pairs.is_empty():
		return {"ok": false, "reason": "no factions in play -- claim one or leave at least one Bot enabled"}

	var state := GameSetup.build_new_game(CardDatabase, pairs, difficulty, max_chapters)
	GameFlow.advance_phase(state, CardDatabase)  # REFRESH -> EVENTS
	GameFlow.advance_phase(state, CardDatabase)  # EVENTS -> BUILD
	GameFlow.advance_phase(state, CardDatabase)  # BUILD -> ACTIONS
	game_state = state
	_game_starting.rpc(state.to_dict())
	return {"ok": true, "reason": ""}


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
	_receive_phase_advanced.rpc(result)


@rpc("authority", "call_local", "reliable")
func _receive_phase_advanced(info: Dictionary) -> void:
	phase_advanced.emit(info)


## Clears one hex off GameState.pending_combats -- the fight itself stays
## manual (Combat resolution needs per-Unit dice-color data not yet
## digitized, see NemesisAI), this is just the bookkeeping once a player
## has fought it out at the table. Any connected peer can call this; it's
## board housekeeping, not one faction's Action.
func submit_resolve_combat(coord: Vector2i) -> void:
	if is_host:
		_apply_resolve_combat(coord, multiplayer.get_unique_id())
	else:
		_request_resolve_combat.rpc_id(1, coord)


@rpc("any_peer", "call_remote", "reliable")
func _request_resolve_combat(coord: Vector2i) -> void:
	if not is_host:
		return
	_apply_resolve_combat(coord, multiplayer.get_remote_sender_id())


func _apply_resolve_combat(coord: Vector2i, sender_id: int) -> void:
	if game_state == null:
		_reject(sender_id, "no active game")
		return
	if not game_state.pending_combats.has(coord):
		_reject(sender_id, "no pending combat at that hex")
		return
	game_state.pending_combats.erase(coord)
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
