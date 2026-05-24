extends Node

var is_initialized: bool = false

func _ready() -> void:
	var result: Dictionary = Steam.steamInitEx()
	if result["status"] == Steam.STEAM_API_INIT_RESULT_OK:
		is_initialized = true
	else:
		push_error("Steam failed to initialize: %s" % result["verbal"])

func _process(_delta: float) -> void:
	if is_initialized:
		Steam.run_callbacks()
