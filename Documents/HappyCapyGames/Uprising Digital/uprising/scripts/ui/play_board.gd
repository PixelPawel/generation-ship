extends Node3D

## First playable-loop UI (Milestone 5). Renders the live NetworkManager
## GameState as real hex tiles (same HexMath as Milestone 1's board-setup
## scene, driven by live state instead of a static BoardLayout) plus a HUD
## exposing every GameAction as a button.
##
## Simplifications, documented rather than silently limited: Market/Quest
## buttons act on the first available Item/Quest in the deck (a real
## "pick which one" UI is a reasonable follow-up); build_unit always
## builds the faction's first Unit type, defaulting any OR/ANY cost
## choice to Salt; Hero position isn't rendered (GameState has no
## hero_coord field yet, see GameActions._move's own doc comment) - Move
## only deducts AP for now.

const HEX_MESH_PATH := "res://assets/images/3d/hex.obj"

const ROLE_COLORS := {
	"capital": Color(0.85, 0.7, 0.2),
	"home": Color(0.3, 0.55, 0.85),
	"sea_tower": Color(0.2, 0.65, 0.75),
	"interior": Color(0.35, 0.35, 0.38),
	"outer": Color(0.5, 0.2, 0.5),
}

var selected_coord: Vector2i = Vector2i.ZERO
var has_selected_coord: bool = false

@onready var hexes_root: Node3D = $Hexes
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


func _wire_button(name_path: String, handler: Callable) -> void:
	var b: Button = hud.get_node("Panel/VBox/Actions/%s" % name_path)
	b.pressed.connect(handler)


func _on_peer_connected(id: int) -> void:
	var net: Node = get_node("/root/NetworkManager")
	if not net.is_host():
		return
	if net.current_state == null or net.current_state.players.size() < 2:
		return
	var second_faction: String = net.current_state.players[1].faction
	net.assign_faction(id, second_faction)
	status_label.text = "Player 2 connected as %s" % second_faction


func _on_action_rejected(reason: String) -> void:
	log_label.text = "REJECTED: %s" % reason


func _on_state_updated(state: GameState) -> void:
	_rebuild_hexes(state)
	_update_hud(state)


func _rebuild_hexes(state: GameState) -> void:
	for child: Node in hexes_root.get_children():
		child.queue_free()
	var hex_mesh: Mesh = load(HEX_MESH_PATH)
	if hex_mesh == null:
		return
	for coord: Vector2i in state.hexes.keys():
		var tile: HexTileState = state.hexes[coord]
		var inst := MeshInstance3D.new()
		inst.mesh = hex_mesh
		inst.name = "Hex_%d_%d" % [coord.x, coord.y]
		hexes_root.add_child(inst)
		inst.position = HexMath.to_world(coord)
		var fallback_color: Color = ROLE_COLORS.get(tile.role, Color.GRAY)
		if not tile.explored and tile.role != "capital" and tile.role != "home" and tile.role != "sea_tower":
			fallback_color = Color(0.15, 0.15, 0.15)
		var tint := Color.WHITE
		if tile.curse:
			tint = Color(1.0, 0.3, 0.85)  # magenta-ish curse tint, multiplied over real art or fallback alike.
		if has_selected_coord and coord == selected_coord:
			tint = tint.lightened(0.5)
		HexTextureLibrary.apply_material(inst, tile.role, tile.hex_card_name, tile.owning_faction, tile.explored, fallback_color, tint)


func _update_hud(state: GameState) -> void:
	var net: Node = get_node("/root/NetworkManager")
	var my_faction: String = net.my_faction()
	var phase_name: String = ["Refresh", "Events", "Build", "Actions", "Nemesis", "Production", "Scoring"][state.phase]
	var turn_note: String = ""
	if state.phase == GameState.Phase.ACTIONS and state.players.size() > 0:
		var current: PlayerFactionState = state.players[state.current_player_index % state.players.size()]
		turn_note = " | Turn: %s%s" % [current.faction, " (YOU)" if current.faction == my_faction else ""]
	status_label.text = "Chapter %d/%d - %s Phase%s" % [state.chapter, state.max_chapters, phase_name, turn_note]

	var p: PlayerFactionState = state.find_player(my_faction)
	if p != null:
		resources_label.text = "%s | AP:%d Salt:%d Plunder:%d Food:%d VP:%d" % [p.faction, p.action_points, p.salt, p.plunder, p.food, p.vp]
	else:
		resources_label.text = "Waiting for opponent to connect..."

	selected_label.text = "Selected: %s" % (str(selected_coord) if has_selected_coord else "(none)")
	if not state.phase_log.is_empty():
		log_label.text = state.phase_log


func select_coord(coord: Vector2i) -> void:
	selected_coord = coord
	has_selected_coord = true
	var net: Node = get_node("/root/NetworkManager")
	if net.current_state != null:
		_rebuild_hexes(net.current_state)
		_update_hud(net.current_state)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var from: Vector3 = camera.project_ray_origin(event.position)
		var dir: Vector3 = camera.project_ray_normal(event.position)
		if absf(dir.y) < 0.0001:
			return
		var t: float = -from.y / dir.y
		var world_pos: Vector3 = from + dir * t
		select_coord(HexMath.from_world(world_pos))


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
	if not has_selected_coord:
		return
	_submit({"type": "explore", "at": _coord_dict(selected_coord)})


func _on_haven_pressed() -> void:
	if not has_selected_coord:
		return
	_submit({"type": "haven", "at": _coord_dict(selected_coord)})


func _on_market_pressed() -> void:
	var net: Node = get_node("/root/NetworkManager")
	var state: GameState = net.current_state
	if state == null or state.item_deck.is_empty():
		return
	_submit({"type": "market", "item": state.item_deck[0], "salt_cost": 0})


func _on_quest_pressed() -> void:
	var net: Node = get_node("/root/NetworkManager")
	var state: GameState = net.current_state
	if state == null or state.quest_deck.is_empty():
		return
	_submit({"type": "quest", "quest": state.quest_deck[0]})


func _on_build_unit_pressed() -> void:
	if not has_selected_coord:
		return
	var net: Node = get_node("/root/NetworkManager")
	var faction: String = net.my_faction()
	var board: PlayerboardTable.FactionBoard = PlayerboardTable.get_board(faction)
	if board == null or board.units.is_empty():
		return
	var unit: PlayerboardTable.UnitEntry = board.units[0]
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
