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

const CARD_THUMB_SIZE := Vector2(70, 103)
const CARD_CHOICE_SIZE := Vector2(150, 221)

## Hero standee models vary wildly in native scale (same gotcha main.gd's
## asset showcase already solved) -- normalize every one to roughly this
## XZ footprint so it reads clearly on a hex without overwhelming it.
const HERO_MODEL_FOOTPRINT := 1.3

## One title banner per Phase (assets/images/PhaseHeadLines), flashed in and
## back out whenever state.phase changes -- see _check_phase_change(). The
## folder also has an "08_Omens.png" that doesn't correspond to any
## GameState.Phase value, so it's intentionally unused here.
const PHASE_HEADLINE_PATHS := {
	GameState.Phase.REFRESH: "res://assets/images/PhaseHeadLines/01_Refresh_01.png",
	GameState.Phase.EVENTS: "res://assets/images/PhaseHeadLines/02_Events.png",
	GameState.Phase.BUILD: "res://assets/images/PhaseHeadLines/03_Build.png",
	GameState.Phase.ACTIONS: "res://assets/images/PhaseHeadLines/04_Actions.png",
	GameState.Phase.NEMESIS: "res://assets/images/PhaseHeadLines/05_Nemesis.png",
	GameState.Phase.PRODUCTION: "res://assets/images/PhaseHeadLines/06_Production.png",
	GameState.Phase.SCORING: "res://assets/images/PhaseHeadLines/07_Scoring.png",
}
const PHASE_BANNER_WIDTH := 560.0
const PHASE_BANNER_FADE_IN := 0.25
const PHASE_BANNER_HOLD := 1.3
const PHASE_BANNER_FADE_OUT := 0.45

var state: GameState
var current_faction: String = ""
var selected_coord: Vector2i = NO_SELECTION

var _hex_mesh: Mesh
var _hex_instances: Dictionary = {}  # HexMath.key -> MeshInstance3D
var _hero_markers: Dictionary = {}  # faction -> MeshInstance3D
var _haven_markers: Dictionary = {}  # HexMath.key -> MeshInstance3D, once placed (Havens are never removed)

var _pivot: OrbitCamera
var _hud: CanvasLayer
var _status_label: Label
var _resources_label: Label
var _vp_label: Label
var _selection_label: Label
var _phase_log_label: Label
var _event_row: HBoxContainer
var _event_card_slot: HBoxContainer
var _combats_row: HBoxContainer
var _druids_label: Label
var _nemesis_label: Label
var _spawn_threat_spin: SpinBox
var _spawn_legion_button: Button
var _spawn_horde_button: Button
var _last_phase_message: String = ""
var _shown_event: String = ""  # which current_event _event_card_slot currently displays, to avoid needless rebuilds
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
var _draw_feats_button: Button

var _faction_option: OptionButton

var _market_option_items: Array[String] = []  # what _market_option currently lists, to avoid needless rebuilds
var _quest_option_items: Array[String] = []
var _build_unit_option_items: Array[String] = []
var _faction_option_items: Array[String] = []

## Bottom-of-screen card display: the current player's Items/Feats in play
## (CardView.make thumbnails), and, during Build Phase with a drawn-but-
## undecided Feat pair, a clickable choice between the two.
var _hand_bar: CanvasLayer
var _hand_row: HBoxContainer
var _feat_choice_row: HBoxContainer
var _feat_choice_label: Label

## Phase-change title banner (see PHASE_HEADLINE_PATHS).
var _phase_banner_layer: CanvasLayer
var _phase_banner_rect: TextureRect
var _phase_banner_tween: Tween
var _last_seen_phase: int = -1  # sentinel (no real Phase value) so the very first phase still flashes

## Escape-triggered pause menu: Resume / Main Menu / Quit.
var _pause_menu_layer: CanvasLayer


func _ready() -> void:
	_hex_mesh = load(HEX_MESH_PATH)
	_setup_environment()
	_setup_camera()
	_setup_hud()
	_setup_hand_bar()
	_setup_phase_banner()
	_setup_pause_menu()
	# Reached via the Lobby (scenes/lobby.tscn): hosting/joining and the
	# actual GameState (including bot assignment for factions nobody
	# claimed) already happened there -- NetworkManager.game_state is
	# already populated and broadcast to everyone. Otherwise this scene was
	# launched directly (dev iteration, tools/screenshot_scene.gd,
	# game_board_flow_test.gd), so fall back to LobbyConfig's defaults,
	# which reproduce a small 2-player local test game exactly like before
	# the Lobby existed.
	if NetworkManager.game_state != null:
		_start_from_lobby()
	elif LobbyConfig.is_host:
		_start_hosted_game()
	else:
		_start_joined_game()


## Both host and client land here once NetworkManager.game_state is
## populated (see NetworkManager.start_game/_game_starting) -- hosting/
## joining the ENet connection itself already happened in the Lobby, so
## this only needs to pick up the state and figure out which faction (if
## any) this peer controls.
func _start_from_lobby() -> void:
	state = NetworkManager.game_state
	current_faction = _faction_for_this_peer()
	_connect_network_signals()
	_rebuild_board()


func _connect_network_signals() -> void:
	NetworkManager.state_updated.connect(_on_state_updated)
	NetworkManager.action_rejected.connect(_on_action_rejected)
	NetworkManager.phase_advanced.connect(_on_phase_advanced)


func _on_phase_advanced(info: Dictionary) -> void:
	_last_phase_message = info.get("reason", "")
	_update_hud()


func _faction_for_this_peer() -> String:
	var my_id := NetworkManager.multiplayer.get_unique_id()
	for p in state.players:
		if p.controlled_by_peer_id == my_id:
			return p.faction
	return state.players[0].faction if not state.players.is_empty() else ""


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

	var err: Error = NetworkManager.host_game(LobbyConfig.port)
	if err != OK:
		push_warning("game_board: host_game failed (%s); board still renders `state` directly" % err)
	else:
		NetworkManager.game_state = state
	_connect_network_signals()

	_rebuild_board()


## Client path: no local GameState exists yet -- `state` stays null until
## the host's first _receive_full_state RPC lands in _on_state_updated(),
## which is also where `current_faction` gets a default (the "Playing as"
## picker in the HUD lets the player switch which faction they're driving,
## same as on the host).
func _start_joined_game() -> void:
	_connect_network_signals()
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
	_check_phase_change()
	_rebuild_hexes()
	_rebuild_hero_markers()
	_rebuild_haven_markers()
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

	_phase_log_label = Label.new()
	_phase_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_phase_log_label.custom_minimum_size = Vector2(520, 0)
	vbox.add_child(_phase_log_label)

	_event_row = HBoxContainer.new()
	_event_row.visible = false
	vbox.add_child(_event_row)
	var event_label := Label.new()
	event_label.text = "This Chapter's Event:"
	_event_row.add_child(event_label)
	# A Container (not a plain Control) so it actually reserves layout space
	# for the CardView added to it later -- a plain Control's minimum size
	# doesn't grow with its children, so the card would visually overlap
	# whatever renders below it instead of pushing the row's height out.
	_event_card_slot = HBoxContainer.new()
	_event_row.add_child(_event_card_slot)

	_combats_row = HBoxContainer.new()
	vbox.add_child(_combats_row)

	_druids_label = Label.new()
	_druids_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_druids_label.custom_minimum_size = Vector2(520, 0)
	vbox.add_child(_druids_label)

	_nemesis_label = Label.new()
	_nemesis_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_nemesis_label.custom_minimum_size = Vector2(520, 0)
	vbox.add_child(_nemesis_label)

	var spawn_row := HBoxContainer.new()
	vbox.add_child(spawn_row)
	var spawn_label := Label.new()
	spawn_label.text = "Spawn at selected hex, Threat:"
	spawn_row.add_child(spawn_label)
	_spawn_threat_spin = SpinBox.new()
	_spawn_threat_spin.min_value = 1
	_spawn_threat_spin.max_value = 20
	_spawn_threat_spin.value = 4
	spawn_row.add_child(_spawn_threat_spin)
	_spawn_legion_button = Button.new()
	_spawn_legion_button.text = "Spawn Legion"
	_spawn_legion_button.pressed.connect(_on_spawn_legion_pressed)
	spawn_row.add_child(_spawn_legion_button)
	_spawn_horde_button = Button.new()
	_spawn_horde_button.text = "Spawn Horde"
	_spawn_horde_button.pressed.connect(_on_spawn_horde_pressed)
	spawn_row.add_child(_spawn_horde_button)

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

	_draw_feats_button = Button.new()
	_draw_feats_button.text = "Draw Feats"
	_draw_feats_button.pressed.connect(_on_draw_feats_pressed)
	buttons.add_child(_draw_feats_button)

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


## Bottom-of-screen bar showing the current player's Items/Feats in play as
## real card art (CardView), plus -- when a Build Phase draw_feats is
## pending -- a clickable choice between the 2 drawn Feats.
func _setup_hand_bar() -> void:
	_hand_bar = CanvasLayer.new()
	add_child(_hand_bar)

	# Anchored to a zero-height strip pinned to the bottom edge; growing
	# UPWARD from there by its own content's natural size (GROW_DIRECTION_
	# BEGIN) means this is correctly placed regardless of viewport height,
	# instead of a brittle hardcoded pixel offset that could overlap the
	# top-left HUD panel on a small window.
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	vbox.grow_vertical = Control.GROW_DIRECTION_BEGIN
	vbox.offset_left = 12
	vbox.offset_right = -12
	vbox.offset_bottom = -12
	_hand_bar.add_child(vbox)

	_feat_choice_label = Label.new()
	_feat_choice_label.text = "Choose a Feat:"
	_feat_choice_label.visible = false
	vbox.add_child(_feat_choice_label)

	_feat_choice_row = HBoxContainer.new()
	vbox.add_child(_feat_choice_row)

	var hand_label := Label.new()
	hand_label.text = "Hand (Items + Feats in play):"
	vbox.add_child(hand_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, CARD_THUMB_SIZE.y + 16)
	vbox.add_child(scroll)

	_hand_row = HBoxContainer.new()
	scroll.add_child(_hand_row)


## Centered, top-of-screen title banner (assets/images/PhaseHeadLines) that
## _check_phase_change() flashes in and back out whenever state.phase
## changes. A CenterContainer spanning the full width, not a manually
## centered TextureRect, so this stays centered regardless of viewport
## size without hand-computing offsets.
func _setup_phase_banner() -> void:
	_phase_banner_layer = CanvasLayer.new()
	_phase_banner_layer.layer = 10  # above the HUD/hand bar's default layer
	add_child(_phase_banner_layer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_TOP_WIDE)
	center.custom_minimum_size = Vector2(0, 200)
	center.position.y = 30
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phase_banner_layer.add_child(center)

	_phase_banner_rect = TextureRect.new()
	_phase_banner_rect.custom_minimum_size = Vector2(PHASE_BANNER_WIDTH, 0)
	_phase_banner_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_phase_banner_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_phase_banner_rect.modulate = Color(1, 1, 1, 0)
	_phase_banner_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_phase_banner_rect)


## Flashes the Phase banner in whenever state.phase actually changes (not
## on every state broadcast -- most actions don't touch phase at all). The
## sentinel start value for _last_seen_phase means the very first phase the
## board ever sees (game start, or a fresh client joining mid-game) also
## flashes once, same as any later transition.
func _check_phase_change() -> void:
	if state == null or int(state.phase) == _last_seen_phase:
		return
	_last_seen_phase = int(state.phase)
	_flash_phase_banner(state.phase)


func _flash_phase_banner(phase: GameState.Phase) -> void:
	var path: String = PHASE_HEADLINE_PATHS.get(phase, "")
	if path == "" or not ResourceLoader.exists(path):
		return
	var texture: Texture2D = load(path)
	_phase_banner_rect.texture = texture
	# CenterContainer sizes its child at the child's OWN minimum size --
	# it doesn't stretch children to fill available space -- and
	# EXPAND_FIT_WIDTH_PROPORTIONAL only affects how the texture draws
	# WITHIN the rect's existing bounds, not the bounds themselves. Without
	# this, custom_minimum_size stayed (width, 0) from setup and the rect
	# rendered at zero height: invisible despite a correct texture/alpha.
	var tex_size := texture.get_size()
	if tex_size.x > 0.0:
		_phase_banner_rect.custom_minimum_size = Vector2(PHASE_BANNER_WIDTH, PHASE_BANNER_WIDTH * tex_size.y / tex_size.x)

	if _phase_banner_tween != null and _phase_banner_tween.is_valid():
		_phase_banner_tween.kill()
	_phase_banner_rect.modulate = Color(1, 1, 1, 0)
	_phase_banner_tween = create_tween()
	_phase_banner_tween.tween_property(_phase_banner_rect, "modulate:a", 1.0, PHASE_BANNER_FADE_IN)
	_phase_banner_tween.tween_interval(PHASE_BANNER_HOLD)
	_phase_banner_tween.tween_property(_phase_banner_rect, "modulate:a", 0.0, PHASE_BANNER_FADE_OUT)


## Escape-triggered pause overlay: a dimmed background (also catches clicks
## so they can't fall through to hex-picking underneath while paused) plus
## a centered Resume / Main Menu / Quit panel. Hidden by default; toggled
## in _unhandled_input() on the "ui_cancel" action (Escape by default).
func _setup_pause_menu() -> void:
	_pause_menu_layer = CanvasLayer.new()
	_pause_menu_layer.layer = 20  # above the phase banner (10) and everything else
	_pause_menu_layer.visible = false
	add_child(_pause_menu_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_menu_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_menu_layer.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(240, 0)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var resume_button := Button.new()
	resume_button.text = "Resume"
	resume_button.pressed.connect(_on_resume_pressed)
	vbox.add_child(resume_button)

	var main_menu_button := Button.new()
	main_menu_button.text = "Main Menu"
	main_menu_button.pressed.connect(_on_pause_main_menu_pressed)
	vbox.add_child(main_menu_button)

	var quit_button := Button.new()
	quit_button.text = "Quit"
	quit_button.pressed.connect(_on_pause_quit_pressed)
	vbox.add_child(quit_button)


func _toggle_pause_menu() -> void:
	_pause_menu_layer.visible = not _pause_menu_layer.visible


func _on_resume_pressed() -> void:
	_pause_menu_layer.visible = false


## Leaving mid-game disconnects cleanly (closes the ENet connection --
## whether this peer was hosting or a client) instead of abandoning it
## silently in the background while the scene changes out from under it.
func _on_pause_main_menu_pressed() -> void:
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_pause_quit_pressed() -> void:
	get_tree().quit()


## Rebuilds the hand bar from scratch every call -- Items/Feats in play
## change rarely (only via Market/Feat actions), so unlike the OptionButtons
## there's no user selection state to lose by doing this unconditionally.
func _update_hand_bar() -> void:
	var player := state.get_player(current_faction)
	if player == null:
		return

	for child in _hand_row.get_children():
		child.queue_free()
	for item_name in player.items_in_play:
		var card := _find_item_card(item_name)
		var texture_path: String = card.texture_path if card != null else ""
		_hand_row.add_child(CardView.make(texture_path, item_name, CARD_THUMB_SIZE))
	for feat_name in player.feats_in_play:
		var fcard := _find_feat_card(feat_name)
		var texture_path: String = fcard.texture_path if fcard != null else ""
		_hand_row.add_child(CardView.make(texture_path, feat_name, CARD_THUMB_SIZE))

	for child in _feat_choice_row.get_children():
		child.queue_free()
	var has_choice := not player.pending_feat_choice.is_empty()
	_feat_choice_label.visible = has_choice
	if has_choice:
		for feat_name in player.pending_feat_choice:
			var fcard := _find_feat_card(feat_name)
			var texture_path: String = fcard.texture_path if fcard != null else ""
			_feat_choice_row.add_child(CardView.make_button(
				texture_path, feat_name, CARD_CHOICE_SIZE,
				func() -> void: _on_choose_feat_pressed(feat_name)
			))


func _find_item_card(item_name: String) -> ItemCard:
	for c in CardDatabase.items:
		if c.lang == "EN" and c.card_name == item_name:
			return c
	return null


func _find_feat_card(feat_name: String) -> FeatCard:
	for c in CardDatabase.feats:
		if c.lang == "EN" and c.card_name == feat_name:
			return c
	return null


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
		inst.set_surface_override_material(0, _material_for_tile(tile, tile.coord == selected_coord))


## Explored hexes show their actual printed card art (HexCard.texture_path,
## already wired up since the asset pipeline was built -- CardView proved
## the pattern for Feat/Item cards, this is the same idea applied to the
## board itself) with a color tint for Selected/Curse; anything without art
## (unexplored hexes -- there's no card-back scan to show, or The Capital,
## which has no Core-box HexCard entry) falls back to the flat color scheme
## this always used. Haven ownership moved to a small marker (see
## _rebuild_haven_markers) instead of replacing the tile's color entirely,
## so the terrain art underneath stays visible.
func _material_for_tile(tile: HexTile, is_selected: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var texture := _texture_for_tile(tile)
	if texture == null:
		mat.albedo_color = _color_for_tile(tile, is_selected)
		return mat

	mat.albedo_texture = texture
	if is_selected:
		mat.albedo_color = COLOR_SELECTED
	elif tile.has_curse:
		mat.albedo_color = COLOR_CURSE
	else:
		mat.albedo_color = Color.WHITE
	return mat


func _texture_for_tile(tile: HexTile) -> Texture2D:
	if not tile.explored or tile.card_name == "" or tile.card_name == "The Capital":
		return null
	var hex_card := _find_hex_card(tile.card_name)
	if hex_card == null or hex_card.texture_path == "" or not ResourceLoader.exists(hex_card.texture_path):
		return null
	return load(hex_card.texture_path)


func _find_hex_card(card_name: String) -> HexCard:
	for h in CardDatabase.hexes:
		if h.lang == "EN" and h.card_name == card_name:
			return h
	return null


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
			marker = _build_hero_marker(player)
			add_child(marker)
			_hero_markers[player.faction] = marker
		var world := HexMath.to_world(player.hero_hex)
		world.y = 0.21  # just above the hex puck's top surface (0.2)
		marker.position = world


## The Hero's own extracted standee model (tools/extract_unity3d.py; see
## ModelDatabase), matched by name -- "if I move a hero named Fhayanor it
## should be that model." Falls back to the flat colored sphere this always
## used if a Hero somehow has no extracted model, so a lookup miss stays
## visible instead of silently disappearing.
func _build_hero_marker(player: PlayerFactionState) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	var model_path := ModelDatabase.find_model_path(player.hero_name)
	var mesh: Mesh = load(model_path) if (model_path != "" and ResourceLoader.exists(model_path)) else null

	if mesh != null:
		marker.mesh = mesh
		var aabb := mesh.get_aabb()
		var footprint := maxf(aabb.size.x, aabb.size.z)
		if footprint > 0.001:
			var s := HERO_MODEL_FOOTPRINT / footprint
			marker.scale = Vector3(s, s, s)
		return marker

	push_warning("game_board: no extracted model found for Hero '%s'; using a placeholder sphere" % player.hero_name)
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	marker.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = FACTION_COLORS.get(player.faction, Color.WHITE)
	marker.set_surface_override_material(0, mat)
	return marker


## Small colored disc on top of each Haven, since the tile's own material
## now shows real terrain art instead of a flat faction color. Havens are
## never removed once placed, so this only ever adds markers, never frees
## them (same simplification _rebuild_hero_markers already relies on).
func _rebuild_haven_markers() -> void:
	for key in state.hexes:
		if _haven_markers.has(key):
			continue
		var tile: HexTile = state.hexes[key]
		if tile.haven_faction == "":
			continue
		var marker := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.4
		mesh.bottom_radius = 0.4
		mesh.height = 0.1
		marker.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = FACTION_COLORS.get(tile.haven_faction, COLOR_HAVEN)
		marker.set_surface_override_material(0, mat)
		add_child(marker)
		var world := HexMath.to_world(tile.coord)
		world.y = 0.25
		marker.position = world
		_haven_markers[key] = marker


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

	_phase_log_label.text = _last_phase_message
	_update_event_card()
	_update_combats_row()
	_update_druids_label()
	_update_nemesis_label()

	var can_spawn := state.phase == GameState.Phase.EVENTS and selected_coord != NO_SELECTION and state.get_hex(selected_coord) != null
	_spawn_legion_button.disabled = not can_spawn
	_spawn_horde_button.disabled = not can_spawn

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
	_draw_feats_button.disabled = not (
		state.phase == GameState.Phase.BUILD
		and player.pending_feat_choice.is_empty()
		and not player.feat_deck.is_empty()
	)

	_update_hand_bar()


## Shows this Chapter's revealed Event card (rulebook p16 step 2 -- the
## mechanical Threat/token step is automated, but the printed text still
## needs a human to read and resolve it, so this just makes sure they
## actually see WHICH card that is). Stays visible for the rest of the
## Chapter, same as state.current_event itself.
func _update_event_card() -> void:
	if state.current_event == "":
		_event_row.visible = false
		return
	_event_row.visible = true
	if state.current_event == _shown_event:
		return
	_shown_event = state.current_event
	for child in _event_card_slot.get_children():
		child.queue_free()
	var event_card := _find_event_card(state.current_event)
	var texture_path: String = event_card.texture_path if event_card != null else ""
	# CARD_THUMB_SIZE, not the bigger CARD_CHOICE_SIZE used for the Feat
	# picker -- this row lives in the fixed top-left HUD panel above the
	# separately-anchored Hand bar, and a tall card here grows the panel
	# enough to visually collide with it on a small viewport.
	_event_card_slot.add_child(CardView.make(texture_path, state.current_event, CARD_THUMB_SIZE))


func _find_event_card(event_name: String) -> EventCard:
	for c in CardDatabase.events:
		if c.lang == "EN" and c.card_name == event_name:
			return c
	return null


## Nemesis Phase auto-resolves Legion/Horde movement but stops the instant
## one lands on enemy presence (Combat itself needs per-Unit dice-color
## data that isn't digitized -- see NemesisAI); this is the only thing that
## tells the player a fight is even waiting, since nothing else surfaces
## GameState.pending_combats.
func _update_combats_row() -> void:
	for child in _combats_row.get_children():
		child.queue_free()
	if state.pending_combats.is_empty():
		return
	var label := Label.new()
	label.text = "Pending Combat:"
	_combats_row.add_child(label)
	for coord in state.pending_combats:
		_combats_row.add_child(_build_resolve_button(coord))


## Shows the 4 Druids revealed at Setup and how much AETHER each has
## accrued -- otherwise ChapterFlow.refresh_phase's AETHER placement
## (DruidData.check_condition, checked fresh every Refresh) would be
## invisible; nothing else in the UI surfaces druids_in_play at all.
func _update_druids_label() -> void:
	if state.druids_in_play.is_empty():
		_druids_label.text = ""
		return
	var parts: Array[String] = []
	for d in state.druids_in_play:
		parts.append("%s (AETHER %d)" % [d.card_name, d.aether])
	_druids_label.text = "Druids: " + ", ".join(parts)


## Shows every Legion/Horde currently in play -- otherwise there's no way to
## see what an Event's manual Spawn Legion/Spawn Horde actions actually
## placed, or how many Activation Tokens events_phase_token_step handed
## out, since nothing renders their standees on the board itself yet.
func _update_nemesis_label() -> void:
	if state.legions.is_empty() and state.hordes.is_empty():
		_nemesis_label.text = ""
		return
	var parts: Array[String] = []
	for l in state.legions:
		parts.append("%s Legion @%s (Threat %d, %d tokens)" % [l.card_name, l.coord, l.threat, l.activation_tokens])
	for h in state.hordes:
		parts.append("%s Horde @%s (Threat %d, %d tokens)" % [h.card_name, h.coord, h.threat, h.activation_tokens])
	_nemesis_label.text = "In play: " + ", ".join(parts)


## `coord` is this call's own parameter (a fresh local binding, not a
## shared loop variable), same closure-safety reasoning as lobby.gd's
## _build_faction_row.
func _build_resolve_button(coord: Vector2i) -> Button:
	var button := Button.new()
	button.text = "%s [Resolve]" % [coord]
	button.pressed.connect(func() -> void: _on_resolve_combat_pressed(coord))
	return button


func _on_resolve_combat_pressed(coord: Vector2i) -> void:
	NetworkManager.submit_resolve_combat(coord)


## Mechanically places what an Events Phase card instructs ("Place 1 Legion/
## Horde at Threat N..."): the player reads that text off the revealed
## Event card, clicks the hex it names (or the best legal match -- see
## NemesisAI.spawn_legion's docstring on why exact free-text region parsing
## stays out of scope), sets the Threat via the SpinBox, and presses this.
func _on_spawn_legion_pressed() -> void:
	if selected_coord == NO_SELECTION:
		return
	NetworkManager.submit_spawn_legion(int(_spawn_threat_spin.value), selected_coord)


func _on_spawn_horde_pressed() -> void:
	if selected_coord == NO_SELECTION:
		return
	NetworkManager.submit_spawn_horde(int(_spawn_threat_spin.value), selected_coord)


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
	if event.is_action_pressed("ui_cancel"):  # Escape, by Godot's default input map
		_toggle_pause_menu()
		return
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


func _on_draw_feats_pressed() -> void:
	NetworkManager.submit_action({"type": "draw_feats", "faction": current_faction})


func _on_choose_feat_pressed(feat_name: String) -> void:
	NetworkManager.submit_action({"type": "choose_feat", "faction": current_faction, "feat": feat_name})
