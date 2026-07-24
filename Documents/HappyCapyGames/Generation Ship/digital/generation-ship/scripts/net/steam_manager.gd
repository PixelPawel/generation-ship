extends Node

var is_initialized: bool = false

func _ready() -> void:
	var result: Dictionary = Steam.steamInitEx()
	if result["status"] == Steam.STEAM_API_INIT_RESULT_OK:
		is_initialized = true
		# Kicks off Steam's connection to its relay network in the background —
		# needed for SteamMultiplayerPeer's create_host()/create_client() P2P
		# listen sockets to work at all. Calling it here, at app startup, gives
		# it the most possible time to finish before a player ever reaches the
		# lobby's Host button, per Valve's own guidance to call this as early
		# as possible rather than right before it's needed.
		Steam.initRelayNetworkAccess()
	else:
		push_error("Steam failed to initialize: %s" % result["verbal"])

func _process(_delta: float) -> void:
	if is_initialized:
		Steam.run_callbacks()
