extends Node3D

## First playable-loop UI (Milestone 5), now drawn as a real tabletop.
## Renders the live NetworkManager GameState through BoardView (the printed
## board, hex tiles and every piece from the extracted models), plays board
## effects for what changed between two states (StateDiff -> VfxLibrary),
## and keeps the HUD exposing every GameAction as a button.
##
## Simplifications, documented rather than silently limited: Market/Quest
## buttons act on the first face-up Item/Quest (a real "pick which one"
## UI is a reasonable follow-up); Rotate Hex turns a hex you just explored
## one step clockwise; build_unit always builds the faction's first Unit
## type, defaulting any OR/ANY cost choice to Salt.
##
## Camera: right-drag turns, wheel zooms, middle-drag or WASD pans, F
## reframes (board_camera.gd). Left click selects a hex.

const StateDiff := preload("res://scripts/ui/board/state_diff.gd")
const VfxLibrary := preload("res://scripts/ui/vfx/vfx_library.gd")

const PHASE_NAMES: Array[String] = ["Refresh", "Events", "Build", "Actions", "Nemesis", "Production", "Scoring"]
## Several effects from one update play in a quick cascade, not all at once.
const EVENT_STAGGER: float = 0.18

var selected_coord: Vector2i = Vector2i.ZERO
var has_selected_coord: bool = false

var _last_snapshot: Dictionary = {}
var _hover_coord: Vector2i = Vector2i(999, 999)

@onready var board: Node3D = $Board
@onready var effects_root: Node3D = $Effects
@onready var camera: Camera3D = $Camera3D
@onready var hud: CanvasLayer = $HUD
@onready var status_label: Label = $HUD/Panel/VBox/StatusLabel
@onready var resources_label: Label = $HUD/Panel/VBox/ResourcesLabel
@onready var selected_label: Label = $HUD/Panel/VBox/SelectedLabel
@onready var log_label: Label = $HUD/Panel/VBox/LogLabel


func _ready() -> void:
	var net: Node = get_node("/root/NetworkManager")
	net.state_updated.connect(_on_state_updated)
	net.peer_connected.connect(_on_peer_connected)
	net.action_rejected.connect(_on_action_rejected)

	_wire_button("MoveButton", _on_move_pressed)
	_wire_button("TradeButton", _on_trade_pressed)
	_wire_button("CommandButton", _on_command_pressed)
	_wire_button("ExploreButton", _on_explore_pressed)
	_wire_button("RotateButton", _on_rotate_pressed)
	_wire_button("HavenButton", _on_haven_pressed)
	_wire_button("MarketButton", _on_market_pressed)
	_wire_button("QuestButton", _on_quest_pressed)
	_wire_button("BuildUnitButton", _on_build_unit_pressed)
	_wire_button("BuildTowerButton", _on_build_tower_pressed)
	_wire_button("BuildWallButton", _on_build_wall_pressed)
	_wire_button("EndTurnButton", _on_end_turn_pressed)
	_wire_button("PassButton", _on_pass_pressed)
	_wire_button("EndPhaseButton", _on_end_phase_pressed)

	if net.current_state != null:
		_on_state_updated(net.current_state)


func _process(_delta: float) -> void:
	if camera.has_method("get_yaw"):
		board.set("camera_yaw", float(camera.call("get_yaw")))
	var look_at_point: Variant = camera.get("target")
	if look_at_point is Vector3:
		board.call("set_snow_center", look_at_point)


func _wire_button(name_path: String, handler: Callable) -> void:
	var b: Button = hud.get_node("Panel/VBox/Actions/%s" % name_path)
	b.pressed.connect(handler)


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
	var second_faction: String = net.current_state.players[1].faction
	net.assign_faction(id, second_faction)
	status_label.text = "Player 2 connected as %s" % second_faction


func _on_action_rejected(reason: String) -> void:
	log_label.text = "Not allowed: %s" % reason
	log_label.add_theme_color_override("font_color", Color(0.86, 0.36, 0.42))


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
	var my_faction: String = net.my_faction()
	var phase_name: String = PHASE_NAMES[state.phase] if state.phase < PHASE_NAMES.size() else "?"
	var turn_note: String = ""
	if state.phase == GameState.Phase.ACTIONS and state.players.size() > 0:
		var current: PlayerFactionState = state.players[state.current_player_index % state.players.size()]
		turn_note = "\n%s's turn%s" % [current.faction, " (YOU)" if current.faction == my_faction else ""]
	status_label.text = "Chapter %d of %d, %s phase%s" % [state.chapter, state.max_chapters, phase_name, turn_note]

	var p: PlayerFactionState = state.find_player(my_faction)
	if p != null:
		resources_label.text = "%s: %d AP, %d Salt, %d Plunder, %d Food, %d VP" % [p.faction, p.action_points, p.salt, p.plunder, p.food, p.vp]
	else:
		resources_label.text = "Waiting for the other player to connect"

	selected_label.text = _describe_hex(state, selected_coord) if has_selected_coord else "Click a hex to see what is on it."
	var sel_tile: HexTileState = state.get_hex(selected_coord) if has_selected_coord else null
	if sel_tile != null and sel_tile.orientable_by == my_faction:
		selected_label.text += "\nRotate hex turns its impassable edges."
	if not state.phase_log.is_empty():
		log_label.text = state.phase_log
		log_label.remove_theme_color_override("font_color")


## Plain-text summary of everything on a hex, for the HUD.
func _describe_hex(state: GameState, coord: Vector2i) -> String:
	var tile: HexTileState = state.get_hex(coord)
	if tile == null:
		return "%s (off the board)" % coord
	var title: String = tile.hex_card_name if tile.explored and not tile.hex_card_name.is_empty() else ("Unexplored hex" if not tile.explored else tile.role.capitalize())
	if tile.role == "outer":
		title = RegionMath.region_for(coord, state.capital_coord)
	var parts: Array[String] = [title]
	if tile.curse:
		parts.append("Cursed")
	if not tile.haven_faction.is_empty():
		parts.append("%s Haven%s%s" % [tile.haven_faction, " with Tower" if tile.tower else "", " and Wall" if tile.wall else ""])
	var faction: String = tile.player_faction_here()
	if not faction.is_empty():
		var stack: Dictionary = tile.unit_stack(faction)
		var bits: Array[String] = []
		for unit_name: Variant in stack.keys():
			bits.append("%d %s" % [int(stack[unit_name]), unit_name])
		parts.append("%s: %s" % [faction, ", ".join(bits)])
	if tile.garrison_level > 0:
		parts.append("Garrison level %d" % tile.garrison_level)
	if tile.skeleton_count > 0:
		parts.append("%d Skeleton%s" % [tile.skeleton_count, "" if tile.skeleton_count == 1 else "s"])
	for n: Variant in EffectUtil.nemesis_at(state, coord):
		parts.append("%s, Threat %d, %d token%s" % [n.card_name, n.threat, n.activation_tokens, "" if n.activation_tokens == 1 else "s"])
	for p: PlayerFactionState in state.players:
		if p.hero_coord == coord:
			parts.append("Hero %s" % p.hero_name)
	return "\n".join(parts)


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


func _submit(action: Dictionary) -> void:
	get_node("/root/NetworkManager").submit_action(action)


func _on_move_pressed() -> void:
	if not has_selected_coord:
		return
	_submit({"type": "move", "to": _coord_dict(selected_coord)})


func _on_trade_pressed() -> void:
	_submit({"type": "trade"})


func _on_command_pressed() -> void:
	if not has_selected_coord:
		return
	_submit({"type": "command", "to": _coord_dict(selected_coord)})


func _on_explore_pressed() -> void:
	_submit({"type": "explore"})  # always the Hero's own hex


func _on_rotate_pressed() -> void:
	if not has_selected_coord:
		return
	var state: GameState = get_node("/root/NetworkManager").current_state
	var tile: HexTileState = state.get_hex(selected_coord) if state != null else null
	if tile == null:
		return
	_submit({"type": "orient", "at": _coord_dict(selected_coord), "rotation": (tile.rotation + 1) % 6})


func _on_haven_pressed() -> void:
	_submit({"type": "haven"})  # always the Hero's own hex


func _on_market_pressed() -> void:
	var net: Node = get_node("/root/NetworkManager")
	var state: GameState = net.current_state
	if state == null or state.item_market.is_empty():
		return
	_submit({"type": "market", "item": state.item_market[0]})


func _on_quest_pressed() -> void:
	var net: Node = get_node("/root/NetworkManager")
	var state: GameState = net.current_state
	if state == null or state.quest_row.is_empty():
		return
	_submit({"type": "quest", "quest": state.quest_row[0]})


func _on_build_unit_pressed() -> void:
	if not has_selected_coord:
		return
	var net: Node = get_node("/root/NetworkManager")
	var faction: String = net.my_faction()
	var board_table: PlayerboardTable.FactionBoard = PlayerboardTable.get_board(faction)
	if board_table == null or board_table.units.is_empty():
		return
	var unit: PlayerboardTable.UnitEntry = board_table.units[0]
	var action: Dictionary = {"type": "build_unit", "unit": unit.name, "at": _coord_dict(selected_coord)}
	if unit.cost.get("type", "fixed") == "or":
		action["or_choice"] = "Salt"
	elif unit.cost.get("type", "fixed") == "any":
		action["any_allocation"] = {"Salt": int(unit.cost.get("amount", 0)), "Plunder": 0, "Food": 0}
	_submit(action)


func _on_build_tower_pressed() -> void:
	if not has_selected_coord:
		return
	_submit({"type": "build_defense", "kind": "Tower", "at": _coord_dict(selected_coord)})


func _on_build_wall_pressed() -> void:
	if not has_selected_coord:
		return
	_submit({"type": "build_defense", "kind": "Wall", "at": _coord_dict(selected_coord)})


func _on_end_turn_pressed() -> void:
	_submit({"type": "end_turn"})


func _on_pass_pressed() -> void:
	_submit({"type": "pass"})


func _on_end_phase_pressed() -> void:
	_submit({"type": "end_phase"})
