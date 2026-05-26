extends Node

# Set to true once a multiplayer session is active. Solo play leaves this false
# so all is_my_turn() checks pass unconditionally.
var is_multiplayer: bool = false
var is_host: bool = false

# Peer ID of the player whose turn it currently is.
var active_peer_id: int = 1

# Ordered list of peer IDs — determines turn rotation within a generation.
var player_order: Array[int] = []

# peer_id → player name string, populated from lobby before scene change.
var player_names: Dictionary = {}

# IDs of bot (dummy) players managed locally by the host.
var bot_ids: Array[int] = []

# Returns true when the local player is allowed to take an action.
func is_my_turn() -> bool:
	if not is_multiplayer:
		return true
	return multiplayer.get_unique_id() == active_peer_id

# Call this when starting a solo game.
func setup_solo() -> void:
	is_multiplayer = false
	is_host = true
	active_peer_id = 1
	player_order = [1]

# Call this from the lobby before changing to the game scene.
# ordered_peer_ids must be in the same order on every client (sort them first).
func setup_multiplayer(host: bool, ordered_peer_ids: Array[int]) -> void:
	is_multiplayer = true
	is_host = host
	player_order = ordered_peer_ids
	active_peer_id = ordered_peer_ids[0]

func is_bot(peer_id: int) -> bool:
	return bot_ids.has(peer_id)

# Advance to the next player in turn order.
func advance_turn() -> void:
	if player_order.is_empty():
		return
	var idx: int = player_order.find(active_peer_id)
	active_peer_id = player_order[(idx + 1) % player_order.size()]
