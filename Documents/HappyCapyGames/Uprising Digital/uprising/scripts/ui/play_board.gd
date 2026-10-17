extends Node3D

## The table: renders the live NetworkManager GameState through BoardView
## (the printed board, hex tiles and every piece from the extracted models),
## plays board effects for what changed between two states (StateDiff ->
## VfxLibrary), and runs the HUD (hud/game_hud.gd) - main actions on the
## left, options in the right-hand tray only when they apply - submitting
## what it asks for to the host.
##
## Camera: right-drag turns, wheel zooms, middle-drag or WASD pans, F
## reframes (board_camera.gd). Left click selects a hex; Move, Command,
## building and card targets act on the selected hex.

const StateDiff := preload("res://scripts/ui/board/state_diff.gd")
const VfxLibrary := preload("res://scripts/ui/vfx/vfx_library.gd")

## Several effects from one update play in a quick cascade, not all at once.
const EVENT_STAGGER: float = 0.18

var selected_coord: Vector2i = Vector2i.ZERO
var has_selected_coord: bool = false

var _last_snapshot: Dictionary = {}
var _hover_coord: Vector2i = Vector2i(999, 999)

@onready var board: Node3D = $Board
@onready var effects_root: Node3D = $Effects
@onready var camera: Camera3D = $Camera3D
@onready var hud: Control = $HUD/Hud


func _ready() -> void:
	var net: Node = get_node("/root/NetworkManager")
	net.state_updated.connect(_on_state_updated)
	net.peer_connected.connect(_on_peer_connected)
	net.action_rejected.connect(_on_action_rejected)
	hud.action_requested.connect(_submit)
	if net.current_state != null:
		_on_state_updated(net.current_state)


func _process(_delta: float) -> void:
	if camera.has_method("get_yaw"):
		board.set("camera_yaw", float(camera.call("get_yaw")))
	var look_at_point: Variant = camera.get("target")
	if look_at_point is Vector3:
		board.call("set_snow_center", look_at_point)


func _on_peer_connected(id: int) -> void:
	var net: Node = get_node("/root/NetworkManager")
	if not net.is_host():
		return
	# The lobby decides every player's faction before PlayBoard opens; only
	# a peer with no faction yet gets the leftover one.
	if (net.peer_factions as Dictionary).has(id):
		return
	if net.current_state == null or net.current_state.players.size() < 2:
		return
	net.assign_faction(id, net.current_state.players[1].faction)


func _on_action_rejected(reason: String) -> void:
	hud.call("show_rejection", reason)


func _on_state_updated(state: GameState) -> void:
	var snapshot: Dictionary = StateDiff.capture(state)
	var events: Array[Dictionary] = StateDiff.diff(_last_snapshot, snapshot)
	_last_snapshot = snapshot
	_rebuild_hexes(state)
	_play_events(events)
	_update_hud(state)


## Kept as the single entry point for redrawing the board.
func _rebuild_hexes(state: GameState) -> void:
	board.call("apply_state", state)
	board.call("set_selected", selected_coord, has_selected_coord)


func _play_events(events: Array[Dictionary]) -> void:
	var delay: float = 0.0
	for e: Dictionary in events:
		var kind: String = str(e["kind"])
		if not VfxLibrary.has_effect(kind):
			continue
		var coord: Vector2i = e["coord"]
		if delay <= 0.0:
			_spawn_effect(kind, coord)
		else:
			get_tree().create_timer(delay).timeout.connect(_spawn_effect.bind(kind, coord))
		delay += EVENT_STAGGER


func _spawn_effect(kind: String, coord: Vector2i) -> void:
	if not is_inside_tree():
		return
	var pos: Vector3 = board.call("hex_surface", coord)
	VfxLibrary.spawn(kind, effects_root, pos)


func _update_hud(state: GameState) -> void:
	var net: Node = get_node("/root/NetworkManager")
	hud.call("refresh", state, net.my_faction(), selected_coord, has_selected_coord)
	# A choice the game waits on (decisions.gd): ring the hexes to choose from.
	var options: Array = []
	if str(state.pending_decision.get("shape", "")) == "hex":
		for o: Variant in (state.pending_decision.get("options", []) as Array):
			options.append(Vector2i(int((o as Dictionary).get("x", 0)), int((o as Dictionary).get("y", 0))))
	board.call("set_options", options)


func select_coord(coord: Vector2i) -> void:
	selected_coord = coord
	has_selected_coord = true
	board.call("set_selected", coord, true)
	var net: Node = get_node("/root/NetworkManager")
	if net.current_state != null:
		_update_hud(net.current_state)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit: Variant = _board_point(event.position)
		if hit != null:
			select_coord(HexMath.from_world(hit))
	elif event is InputEventMouseMotion:
		var hit: Variant = _board_point(event.position)
		var net: Node = get_node("/root/NetworkManager")
		var state: GameState = net.current_state
		if hit != null and state != null:
			var c: Vector2i = HexMath.from_world(hit)
			if c != _hover_coord:
				_hover_coord = c
				board.call("set_hover", c, state.hexes.has(c))


## Where the mouse ray meets the board (the tile tops), or null.
func _board_point(screen_pos: Vector2) -> Variant:
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return null
	var t: float = (0.1 - from.y) / dir.y
	if t < 0.0:
		return null
	return from + dir * t


func _coord_dict(c: Vector2i) -> Dictionary:
	return {"x": c.x, "y": c.y}


## Sends an action to the host. In True Solo Mode, Hero actions go to the
## allied Hero while the HUD's Hero switch says so (unless the action
## already names its Hero, like keeping one of the ally's Feats).
func _submit(action: Dictionary) -> void:
	if bool(hud.get("ally_acting")) and GameActions.HERO_ACTIONS.has(str(action.get("type", ""))) and not action.has("hero_slot"):
		action["hero_slot"] = "ally"
	get_node("/root/NetworkManager").submit_action(action)


# --- The actions by name (tests and keyboard shortcuts call these) -----------

func _on_move_pressed() -> void:
	if has_selected_coord:
		_submit({"type": "move", "to": _coord_dict(selected_coord)})


func _on_trade_pressed() -> void:
	_submit({"type": "trade"})


func _on_command_pressed() -> void:
	if has_selected_coord:
		_submit({"type": "command", "to": _coord_dict(selected_coord)})


func _on_explore_pressed() -> void:
	_submit({"type": "explore"})  # always the Hero's own hex


func _on_haven_pressed() -> void:
	_submit({"type": "haven"})  # always the Hero's own hex


func _on_end_turn_pressed() -> void:
	_submit({"type": "end_turn"})


func _on_pass_pressed() -> void:
	_submit({"type": "pass"})


func _on_end_phase_pressed() -> void:
	_submit({"type": "end_phase"})
