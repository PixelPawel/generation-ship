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
var _command_button: Button
var _pass_button: Button
var _end_phase_button: Button

var _market_option: OptionButton
var _market_button: Button
var _quest_option: OptionButton
var _quest_button: Button
var _build_unit_option: OptionButton
var _build_unit_button: Button
var _build_tower_button: Button
var _build_wall_button: Button

var _faction_option: OptionButton

var _market_option_items: Array[String] = []  # what _market_option currently lists, to avoid needless rebuilds
var _quest_option_items: Array[String] = []
var _build_unit_option_items: Array[String] = []
var _faction_option_items: Array[String] = []


func _ready() -> void:
	_hex_mesh = load(HEX_MESH_PATH)
	_setup_environment()
	_setup_camera()
	_setup_hud()
	# LobbyConfig.configured stays false, and its faction_hero_pairs/etc
	# default to a small 2-player local test game, when this scene is
	# launched directly (dev iteration, tools/screenshot_scene.gd,
	# game_board_flow_test.gd) rather than reached via scenes/lobby.tscn --
	# so is_host defaulting true there still does the right thing.
	if LobbyConfig.is_host:
		_start_hosted_game()
	else:
		_start_joined_game()


func _start_hosted_game() -> void:
	state = GameSetup.build_new_game(
		CardDatabase, LobbyConfig.faction_hero_pairs, LobbyConfig.difficulty, LobbyConfig.max_chapters
	)
	# GameSetup's output is a "post-Refresh Chapter 1" state (phase ==
	# REFRESH) -- walk it through GameFlow the same way a real game would,
	# rather than skipping straight to Actions, so Build purchases and the
	# Events threat step aren't silently bypassed for local/solo testing.
	GameFlow.advance_phase(state, CardDatabase)  # REFRESH -> EVENTS
	GameFlow.advance_phase(state, CardDatabase)  # EVENTS -> BUILD
	GameFlow.advance_phase(state, CardDatabase)  # BUILD -> ACTIONS
	current_faction = state.players[0].faction

	var err: Error = NetworkManager.host_game(state, LobbyConfig.port)
	if err != OK:
		push_warning("game_board: host_game failed (%s); board still renders `state` directly" % err)
	NetworkManager.state_updated.connect(_on_state_updated)
	NetworkManager.action_rejected.connect(_on_action_rejected)

	_rebuild_board()


## Client path: no local GameState exists yet -- `state` stays null until
## the host's first _receive_full_state RPC lands in _on_state_updated(),
## which is also where `current_faction` gets a default (the "Playing as"
## picker in the HUD lets the player switch which faction they're driving,
## same as on the host).
func _start_joined_game() -> void:
	NetworkManager.state_updated.connect(_on_state_updated)
	NetworkManager.action_rejected.connect(_on_action_rejected)
	NetworkManager.connection_failed.connect(_on_connection_failed)

	_status_label.text = "Connecting to %s:%d ..." % [LobbyConfig.join_address, LobbyConfig.join_port]
	var err: Error = NetworkManager.join_game(LobbyConfig.join_address, LobbyConfig.join_port)
	if err != OK:
		_status_label.text = "join_game failed (%s)" % err


func _on_connection_failed() -> void:
	_status_label.text = "Connection failed."


func _on_state_updated(new_state: GameState) -> void:
	state = new_state
	if current_faction == "" and not state.players.is_empty():
		current_faction = state.players[0].faction
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

	var faction_row := HBoxContainer.new()
	vbox.add_child(faction_row)
	var faction_label := Label.new()
	faction_label.text = "Playing as:"
	faction_row.add_child(faction_label)
	_faction_option = OptionButton.new()
	_faction_option.item_selected.connect(_on_faction_option_selected)
	faction_row.add_child(_faction_option)

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

	_command_button = Button.new()
	_command_button.text = "Command Here"
	_command_button.pressed.connect(_on_command_pressed)
	buttons.add_child(_command_button)

	_pass_button = Button.new()
	_pass_button.text = "Pass"
	_pass_button.pressed.connect(_on_pass_pressed)
	buttons.add_child(_pass_button)

	_end_phase_button = Button.new()
	_end_phase_button.text = "End Phase"
	_end_phase_button.pressed.connect(_on_end_phase_pressed)
	buttons.add_child(_end_phase_button)

	var market_row := HBoxContainer.new()
	vbox.add_child(market_row)
	market_row.add_child(Label.new())
	(market_row.get_child(0) as Label).text = "Market:"
	_market_option = OptionButton.new()
	market_row.add_child(_market_option)
	_market_button = Button.new()
	_market_button.text = "Buy Item"
	_market_button.pressed.connect(_on_market_pressed)
	market_row.add_child(_market_button)

	var quest_row := HBoxContainer.new()
	vbox.add_child(quest_row)
	quest_row.add_child(Label.new())
	(quest_row.get_child(0) as Label).text = "Quest:"
	_quest_option = OptionButton.new()
	quest_row.add_child(_quest_option)
	_quest_button = Button.new()
	_quest_button.text = "Attempt Quest"
	_quest_button.pressed.connect(_on_quest_pressed)
	quest_row.add_child(_quest_button)

	var build_row := HBoxContainer.new()
	vbox.add_child(build_row)
	build_row.add_child(Label.new())
	(build_row.get_child(0) as Label).text = "Build:"
	_build_unit_option = OptionButton.new()
	build_row.add_child(_build_unit_option)
	_build_unit_button = Button.new()
	_build_unit_button.text = "Build Unit"
	_build_unit_button.pressed.connect(_on_build_unit_pressed)
	build_row.add_child(_build_unit_button)
	_build_tower_button = Button.new()
	_build_tower_button.text = "Build Tower"
	_build_tower_button.pressed.connect(_on_build_tower_pressed)
	build_row.add_child(_build_tower_button)
	_build_wall_button = Button.new()
	_build_wall_button.text = "Build Wall"
	_build_wall_button.pressed.connect(_on_build_wall_pressed)
	build_row.add_child(_build_wall_button)


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
	var faction_names: Array[String] = []
	for p in state.players:
		faction_names.append(p.faction)
	if faction_names != _faction_option_items:
		_faction_option.clear()
		for f in faction_names:
			_faction_option.add_item(f)
		_faction_option_items.assign(faction_names)
	var current_idx := faction_names.find(current_faction)
	if current_idx >= 0 and _faction_option.selected != current_idx:
		_faction_option.select(current_idx)

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

	_command_button.disabled = not (
		state.phase == GameState.Phase.ACTIONS
		and selected_tile != null and selected_tile.explored
		and player.action_points >= 1 and player.food >= 1
		and not GameActions._other_faction_present(selected_tile, player.faction)
		and (selected_tile.haven_faction == "" or selected_tile.haven_faction == player.faction)
	)

	_pass_button.disabled = not (state.phase == GameState.Phase.ACTIONS and not player.has_passed)
	_end_phase_button.text = "End Phase (%s)" % GameState.Phase.keys()[state.phase]

	_sync_option_button(_market_option, _market_option_items, state.market)
	_market_button.disabled = not (state.phase == GameState.Phase.ACTIONS and not state.market.is_empty())

	_sync_option_button(_quest_option, _quest_option_items, state.quests_available)
	_quest_button.disabled = not (state.phase == GameState.Phase.ACTIONS and not state.quests_available.is_empty())

	var unit_names: Array[String] = []
	for u in FactionData.get_units(player.faction):
		unit_names.append(u["name"])
	_sync_option_button(_build_unit_option, _build_unit_option_items, unit_names)
	var can_build_here := state.phase == GameState.Phase.BUILD and GameActions._valid_build_hex(state, player, selected_coord)
	_build_unit_button.disabled = not (can_build_here and not unit_names.is_empty())
	_build_tower_button.disabled = not (
		can_build_here and selected_tile.haven_faction == player.faction
		and not selected_tile.has_tower and player.plunder >= 1
	)
	_build_wall_button.disabled = not (
		can_build_here and selected_tile.haven_faction == player.faction
		and not selected_tile.has_wall and player.plunder >= 1
	)


## Only rebuilds `option`'s item list when `names` actually differs from
## what it already shows (`cached`) -- OptionButton loses its selection on
## every clear(), and _update_hud() runs after every action, so rebuilding
## unconditionally would reset the player's pick constantly.
func _sync_option_button(option: OptionButton, cached: Array[String], names: Array[String]) -> void:
	if names == cached:
		return
	option.clear()
	for n in names:
		option.add_item(n)
	if not names.is_empty():
		option.select(0)
	cached.assign(names)


func _selected_option_text(option: OptionButton) -> String:
	if option.selected < 0:
		return ""
	return option.get_item_text(option.selected)


# ---------------------------------------------------------------------------
# Input / picking
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if state == null:
		return  # client hasn't received the host's first state broadcast yet
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

func _on_faction_option_selected(index: int) -> void:
	if index < 0 or index >= _faction_option_items.size():
		return
	current_faction = _faction_option_items[index]
	selected_coord = NO_SELECTION
	_rebuild_hexes()
	_update_hud()


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


func _on_command_pressed() -> void:
	if selected_coord == NO_SELECTION:
		return
	NetworkManager.submit_action({
		"type": "command", "faction": current_faction, "to": [selected_coord.x, selected_coord.y]
	})


func _on_pass_pressed() -> void:
	NetworkManager.submit_action({"type": "pass", "faction": current_faction})


func _on_end_phase_pressed() -> void:
	NetworkManager.submit_advance_phase()


func _on_market_pressed() -> void:
	var item := _selected_option_text(_market_option)
	if item == "":
		return
	NetworkManager.submit_action({"type": "market", "faction": current_faction, "item": item})


func _on_quest_pressed() -> void:
	var quest := _selected_option_text(_quest_option)
	if quest == "":
		return
	NetworkManager.submit_action({"type": "quest", "faction": current_faction, "quest": quest})


func _on_build_unit_pressed() -> void:
	if selected_coord == NO_SELECTION:
		return
	var unit_name := _selected_option_text(_build_unit_option)
	if unit_name == "":
		return
	var player := state.get_player(current_faction)
	var unit_def := FactionData.find_unit(player.faction, unit_name)
	var action := {
		"type": "build_unit", "faction": current_faction, "unit": unit_name,
		"at": [selected_coord.x, selected_coord.y],
	}
	var cost_options: Array = unit_def.get("cost_options", [])
	if cost_options.size() == 1 and (cost_options[0] as Dictionary).has("any"):
		action["any_alloc"] = _greedy_any_alloc(player, int((cost_options[0] as Dictionary)["any"]))
	NetworkManager.submit_action(action)


## Mohyar's Units cost "N resource points, any mix" -- the UI doesn't yet
## have a control for the player to choose the exact split, so this greedily
## spends Salt first, then Plunder, then Food, up to the required amount.
## Documented simplification (same class as Command's "engine picks which
## Units move"): the backend (GameActions._build_unit) supports any explicit
## split via "any_alloc", this default just isn't player-directed yet.
func _greedy_any_alloc(player: PlayerFactionState, amount: int) -> Dictionary:
	var alloc := {"salt": 0, "plunder": 0, "food": 0}
	var remaining := amount
	for res in ["salt", "plunder", "food"]:
		var take: int = mini(remaining, int(player.get(res)))
		alloc[res] = take
		remaining -= take
	return alloc


func _on_build_tower_pressed() -> void:
	if selected_coord == NO_SELECTION:
		return
	NetworkManager.submit_action({
		"type": "build_defense", "faction": current_faction, "defense": "tower",
		"at": [selected_coord.x, selected_coord.y],
	})


func _on_build_wall_pressed() -> void:
	if selected_coord == NO_SELECTION:
		return
	NetworkManager.submit_action({
		"type": "build_defense", "faction": current_faction, "defense": "wall",
		"at": [selected_coord.x, selected_coord.y],
	})
