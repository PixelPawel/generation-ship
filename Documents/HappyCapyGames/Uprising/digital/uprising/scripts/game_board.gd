extends Node3D
## The actual playable board: renders GameState as real hex tiles (not the
## asset-showcase grid in main.gd), lets you orbit/zoom the camera, click a
## hex to select it, and act through NetworkManager the same way a real
## networked player would -- this scene hosts its own local game so even
## solo testing exercises the exact host-authoritative code path.

const HEX_MESH_PATH := "res://assets/images/3d/hex.obj"
const NO_SELECTION := Vector2i(999999, 999999)

const COLOR_UNEXPLORED := Color(0.25, 0.25, 0.28)
const COLOR_EXPLORED := Color(0.62, 0.55, 0.38)
const COLOR_CAPITAL := Color(0.55, 0.1, 0.55)
const COLOR_HAVEN := Color(0.2, 0.65, 0.3)
const COLOR_CURSE := Color(0.35, 0.05, 0.5)
const COLOR_SELECTED := Color(0.95, 0.85, 0.2)

const FACTION_COLORS := {
	"Druwhn": Color(0.2, 0.7, 0.3),
	"Duerkhar": Color(0.25, 0.45, 0.9),
	"Mohyar": Color(0.85, 0.2, 0.2),
	"Krowh": Color(0.9, 0.65, 0.1),
}

var state: GameState
var current_faction: String = ""
var selected_coord: Vector2i = NO_SELECTION

var _hex_mesh: Mesh
var _hex_instances: Dictionary = {}  # HexMath.key -> MeshInstance3D
var _hero_markers: Dictionary = {}  # faction -> MeshInstance3D

var _pivot: OrbitCamera
var _hud: CanvasLayer
var _status_label: Label
var _resources_label: Label
var _vp_label: Label
var _selection_label: Label
var _trade_button: Button
var _explore_button: Button
var _move_button: Button
var _haven_button: Button


func _ready() -> void:
	_hex_mesh = load(HEX_MESH_PATH)
	_setup_environment()
	_setup_camera()
	_setup_hud()
	_start_local_game()


func _start_local_game() -> void:
	state = GameSetup.build_new_game(
		CardDatabase, [["Druwhn", "Fhayanor"], ["Krowh", "Kha'al"]], "Veteran", 3
	)
	state.phase = GameState.Phase.ACTIONS
	current_faction = state.players[0].faction

	var err: Error = NetworkManager.host_game(state, NetworkManager.DEFAULT_PORT)
	if err != OK:
		push_warning("game_board: host_game failed (%s); board still renders `state` directly" % err)
	NetworkManager.state_updated.connect(_on_state_updated)
	NetworkManager.action_rejected.connect(_on_action_rejected)

	_rebuild_board()


func _on_state_updated(new_state: GameState) -> void:
	state = new_state
	_rebuild_board()


func _on_action_rejected(reason: String) -> void:
	if _status_label != null:
		_status_label.text = "Rejected: %s" % reason


func _rebuild_board() -> void:
	_rebuild_hexes()
	_rebuild_hero_markers()
	_update_hud()


# ---------------------------------------------------------------------------
# Scene setup
# ---------------------------------------------------------------------------

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)


func _setup_camera() -> void:
	_pivot = OrbitCamera.new()
	_pivot.name = "CameraPivot"
	add_child(_pivot)
	var cam := Camera3D.new()
	cam.far = 300.0
	_pivot.add_child(cam)
	_pivot.camera = cam
	_pivot.update_camera_transform()
	cam.current = true


func _setup_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)

	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	_hud.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	_status_label = Label.new()
	_status_label.text = "Uprising"
	vbox.add_child(_status_label)

	_resources_label = Label.new()
	vbox.add_child(_resources_label)

	_vp_label = Label.new()
	vbox.add_child(_vp_label)

	_selection_label = Label.new()
	vbox.add_child(_selection_label)

	var buttons := HBoxContainer.new()
	vbox.add_child(buttons)

	_trade_button = Button.new()
	_trade_button.text = "Trade (1 AP -> 1 Salt)"
	_trade_button.pressed.connect(_on_trade_pressed)
	buttons.add_child(_trade_button)

	_explore_button = Button.new()
	_explore_button.text = "Explore"
	_explore_button.pressed.connect(_on_explore_pressed)
	buttons.add_child(_explore_button)

	_move_button = Button.new()
	_move_button.text = "Move Here"
	_move_button.pressed.connect(_on_move_pressed)
	buttons.add_child(_move_button)

	_haven_button = Button.new()
	_haven_button.text = "Build Haven"
	_haven_button.pressed.connect(_on_haven_pressed)
	buttons.add_child(_haven_button)


# ---------------------------------------------------------------------------
# Board rendering
# ---------------------------------------------------------------------------

func _rebuild_hexes() -> void:
	for key in state.hexes:
		var tile: HexTile = state.hexes[key]
		var inst: MeshInstance3D = _hex_instances.get(key)
		if inst == null:
			inst = MeshInstance3D.new()
			inst.mesh = _hex_mesh
			inst.position = HexMath.to_world(tile.coord)
			add_child(inst)
			_hex_instances[key] = inst
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _color_for_tile(tile, tile.coord == selected_coord)
		inst.set_surface_override_material(0, mat)


func _color_for_tile(tile: HexTile, is_selected: bool) -> Color:
	if is_selected:
		return COLOR_SELECTED
	if tile.card_name == "The Capital":
		return COLOR_CAPITAL
	if tile.has_curse:
		return COLOR_CURSE
	if not tile.explored:
		return COLOR_UNEXPLORED
	if tile.haven_faction != "":
		return FACTION_COLORS.get(tile.haven_faction, COLOR_HAVEN)
	return COLOR_EXPLORED


func _rebuild_hero_markers() -> void:
	for player in state.players:
		var marker: MeshInstance3D = _hero_markers.get(player.faction)
		if marker == null:
			marker = MeshInstance3D.new()
			var mesh := SphereMesh.new()
			mesh.radius = 0.5
			mesh.height = 1.0
			marker.mesh = mesh
			var mat := StandardMaterial3D.new()
			mat.albedo_color = FACTION_COLORS.get(player.faction, Color.WHITE)
			marker.set_surface_override_material(0, mat)
			add_child(marker)
			_hero_markers[player.faction] = marker
		var world := HexMath.to_world(player.hero_hex)
		world.y = 0.6
		marker.position = world


func _update_hud() -> void:
	var player := state.get_player(current_faction)
	if player == null:
		return
	_status_label.text = "%s (%s) -- Chapter %d, %s" % [
		player.faction, player.hero_name, state.chapter, GameState.Phase.keys()[state.phase]
	]
	_resources_label.text = "Salt %d  Plunder %d  Food %d  |  AP %d" % [
		player.salt, player.plunder, player.food, player.action_points
	]
	_vp_label.text = "VP -- You: %d   Empire: %d   Chaos: %d" % [
		player.victory_points, state.empire_vp, state.chaos_vp
	]

	if selected_coord == NO_SELECTION:
		_selection_label.text = "(no hex selected -- click one)"
	else:
		var tile := state.get_hex(selected_coord)
		if tile == null:
			_selection_label.text = "Selected %s: (empty)" % [selected_coord]
		else:
			_selection_label.text = "Selected %s: %s" % [
				selected_coord, (tile.card_name if tile.explored else "??? (unexplored)")
			]

	var on_selected_hex := selected_coord == player.hero_hex
	var selected_tile := state.get_hex(selected_coord)
	_explore_button.disabled = not (
		on_selected_hex and selected_tile != null and not selected_tile.explored and not selected_tile.has_curse
	)
	_move_button.disabled = not (
		selected_coord != NO_SELECTION
		and selected_coord != player.hero_hex
		and selected_tile != null  # a "neighbor" coordinate may not have a generated tile at all
		and HexMath.distance(player.hero_hex, selected_coord) == 1
	)

	var hero_tile := state.get_hex(player.hero_hex)
	var plunder_cost := 3 if player.faction == "Krowh" else 2
	_haven_button.disabled = not (
		hero_tile != null and hero_tile.explored and not hero_tile.no_haven
		and hero_tile.haven_faction == "" and player.plunder >= plunder_cost
	)


# ---------------------------------------------------------------------------
# Input / picking
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var coord := hex_at_screen_pos(mb.position)
			if coord != NO_SELECTION:
				selected_coord = coord
				_rebuild_hexes()
				_update_hud()


## Ray from the camera through a screen point, intersected with the Y=0
## ground plane, converted to a hex coordinate. Separated out from the input
## handler so it's directly testable without simulating real mouse events.
func hex_at_screen_pos(screen_pos: Vector2) -> Vector2i:
	if _pivot == null or _pivot.camera == null:
		return NO_SELECTION
	var cam := _pivot.camera
	var origin := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return NO_SELECTION
	var t := -origin.y / dir.y
	if t < 0.0:
		return NO_SELECTION
	var world := origin + dir * t
	return HexMath.from_world(world)


# ---------------------------------------------------------------------------
# Action buttons
# ---------------------------------------------------------------------------

func _on_trade_pressed() -> void:
	NetworkManager.submit_action({"type": "trade", "faction": current_faction})


func _on_explore_pressed() -> void:
	NetworkManager.submit_action({"type": "explore", "faction": current_faction})


func _on_move_pressed() -> void:
	if selected_coord == NO_SELECTION:
		return
	NetworkManager.submit_action({
		"type": "move", "faction": current_faction, "to": [selected_coord.x, selected_coord.y]
	})


func _on_haven_pressed() -> void:
	NetworkManager.submit_action({"type": "haven", "faction": current_faction})
