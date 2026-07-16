extends Node3D

@export var card_scene: PackedScene

const MAX_ROUNDS := 4

var _round: int = 0
var _bid_amount: int = 0
var _bid_color: CardData.SupplyColor = CardData.SupplyColor.DUST
var _bid_card_name: String = ""
var _bid_card_data: CardData = null
var _bid_is_advanced: bool = false

# ── Effect queue ──────────────────────────────────────────────────────��───────

enum EffectMode {
	NONE,
	RESEARCH,
	PAYMENT_RECYCLE,
	EFFECT_RECYCLE,
	EFFECT_RECYCLE_OPTIONAL,
	EFFECT_TUCK,
	EFFECT_TUCK_OPTIONAL,
	EFFECT_RECYCLE_TUCK,
	EFFECT_RECYCLE_DOUBLE,
	EFFECT_REVEAL_SECTOR,
	EFFECT_REVEAL_EXPEDITION,
	EFFECT_EXPEDITION_SHUFFLE,
	EFFECT_SEEDBANKS,
	EFFECT_CARGO_DRONES,
	EFFECT_CARGO_DRONES_DEST,
	EFFECT_CALDERA_SELECT_SECTOR,
	EFFECT_CALDERA_SELECT_CARDS,
	EFFECT_STORE_ON_SECTOR,
	EFFECT_CHOICE,
	EFFECT_RECYCLE_TUCK_STORE,
	EFFECT_RECYCLE_TUCK_STORE_DECIDE,
	EFFECT_RECYCLE_TUCK_STORE_SECTOR,
	EFFECT_TUCK_ANY_SECTOR,
	EFFECT_TUCK_ANY_SECTOR_SLOT,
	PAYMENT_CONFIRM,
	SUPPLY_CHOICE,
}

var _effect_mode: EffectMode = EffectMode.NONE
var _effect_queue: Array[Dictionary] = []
var _effect_slot: SectorSlot = null
var _effect_remaining: int = 0
var _effect_face_up: bool = false
var _effect_done_btn: Button = null
var _choice_popup: ChoicePopup = null
var _pending_choice_options: Array = []
var _pending_reveal_gain_supply: bool = false
var _pending_reveal_may_bid: bool = false
var _pending_reveal_may_free_gain: bool = false
var _pending_expedition_reveal_gain_supply: bool = false
var _pending_expedition_reveal_may_bid: bool = false
var _reveal_bid_pool: Array[CardData] = []
var _reveal_free_pool: Array[CardData] = []
var _bid_is_from_effect: bool = false
var _shuffle_count: int = 0
var _pending_recycle_cards: Array[Node3D] = []
var _pending_store_nodes: Array[Node3D] = []
var _last_drawn_cards: Array[Node3D] = []
var _restrict_picks_to_drawn: bool = false
var _sector_info_popup: SectorInfoPopup = null
var _recycle_panel: Control = null
var _sector_picker: SectorPickerPanel = null
var _supply_cost_panel: SupplyCostPanel = null
var _market_panel: Control = null
var _bid_payment_panel: Control = null
var _cargo_source_slot: SectorSlot = null
var _cargo_pending_supplies: Dictionary = {}
var _cargo_pending_tucked: Array[int] = []
var _caldera_slots: Array[SectorSlot] = []
var _music_player_a: AudioStreamPlayer = null
var _music_player_b: AudioStreamPlayer = null
var _music_use_a: bool = true
const MUSIC_CROSSFADE_SEC: float = 2.0
var _pending_store_color: CardData.SupplyColor = CardData.SupplyColor.DUST
var _pending_store_amount: int = 0
var _pending_tuck_card_data: CardData = null
var _pending_target_slot: SectorSlot = null
var _effect_label: String = ""
var _players_passed_this_round: int = 0
var _has_passed: bool = false
var _has_researched: bool = false
var _opp_snapshots: Dictionary = {}      # peer_id (int) -> state Dictionary
var _opp_widget: Control = null
var _opp_panels: Dictionary = {}         # peer_id → {hand_lbl, supply_lbls, vp_lbl, status_lbl}
var _opp_statuses: Dictionary = {}      # peer_id → String ("" | "passed" | "researching")
var _opp_info_panel: Control = null
var _ending_turn: bool = false
var _pre_setup_done: bool = false
var _cached_sector_order: Array = []
var _cached_exp_order: Array = []

var _auction_card_ref: Dictionary = {}
var _auction_slot_idx: int = -1
var _auction_is_tech: bool = false
var _auction_is_adv: bool = false
var _auction_cost_color: CardData.SupplyColor = CardData.SupplyColor.DUST
var _auction_current_bid: int = 0
var _auction_leader_id: int = 0
var _auction_initiator_id: int = 0
var _auction_remaining: Array[int] = []
var _auction_active_idx: int = 0
var _auction_second_id: int = -1
var _deferred_effect_queue: Array[Dictionary] = []
var _deferred_effect_slot: SectorSlot = null
var _defer_place_effects: bool = false
var _pending_auction: bool = false
var _pending_auction_card_ref: Dictionary = {}
var _pending_auction_slot_idx: int = -1
var _pending_auction_is_tech: bool = false
var _pending_auction_is_adv: bool = false
var _pending_won: bool = false
var _pending_won_card_ref: Dictionary = {}
var _pending_won_is_adv: bool = false
var _won_popup: Control = null
var _pending_auction_win: bool = false
var _auction_win_is_initiator: bool = false
var _auction_active: bool = false
var _is_runner_up_offer: bool = false
var _runner_up_phase: bool = false
var _bots_passed_this_round: Array[int] = []
var _cs_viewport: SubViewport = null
var _vp_button_held: bool = false
var _vp_prev_pos: Dictionary = {}  # SubViewport -> Vector2
var _info_viewport: SubViewport = null
var _log_viewport: SubViewport = null
var _log_canvas: Control = null
var _log_vbox: VBoxContainer = null
var _log_scroll: ScrollContainer = null
var _log_font: FontVariation = null
var _log_preview_panel: Control = null
var _log_preview_image: TextureRect = null
var _log_preview_pending_hide: bool = false
var _log_tooltip_panel: Control = null
var _log_tooltip_title: Label = null
var _log_tooltip_desc: Label = null
var _sun_elevated_count: int = 0

var _rumble_tweens: Dictionary = {}   # Node3D -> Tween
var _rumble_base_pos: Dictionary = {} # Node3D -> Vector3
var _rumble_base_rot: Dictionary = {} # Node3D -> Vector3
var _info_screen_mesh: MeshInstance3D = null
var _cs_display: SupplyUI = null
var _end_turn_btn_mesh: MeshInstance3D = null
var _end_turn_flash_tween: Tween = null
var _ui_control_shown: bool = false
var _ui_info_shown: bool = false
var _end_turn_flash_mat: StandardMaterial3D = null
var _effect_hint_panel: Control = null
var _effect_hint_label: Label = null
var _es_viewport: Control = null
var _bid_popup: Control = null
var _payment_panel: Control = null
var _scoreboard: Control = null
var _pause_menu: Control = null
var _info_panels: Array[Control] = []
var _bot_hands: Dictionary = {}      # bot_id → Array[CardData]
var _bot_supplies: Dictionary = {}   # bot_id → Dictionary (int color → int count)
var _bot_boards: Dictionary = {}     # bot_id → Array[{sector, is_advanced, techs, stored}]
var _es_back_btn: Button = null

# ── Setup ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added_to_tree)
	for node: Node3D in [$UiControl, $UiInfo, $UiLog, $UiCockpit]:
		_rumble_base_pos[node] = node.position
		_rumble_base_rot[node] = node.rotation
	_start_rumble_timer()
	$UILayer/StartButton.queue_free()
	var hand: Node3D = $Hand
	$Board.set_hand(hand)
	$Board.set_card_scene(card_scene)
	$Board.card_recycled.connect(_on_card_recycled)
	$Board.recycle_confirm_required.connect(_on_recycle_confirm_required)
	$Board.setup_tech_deck(CardDatabase.techs)
	$Board.setup_sector_deck(CardDatabase.sectors)
	$Hand.card_selected_for_discard.connect(_on_card_discarded)
	$Hand.card_right_clicked.connect(_on_card_right_clicked_free_recycle)
	$Board.bid_required.connect(_on_bid_required)
	$Board.card_placed.connect(_on_card_placed)
	$Board.optimize_triggered.connect(_on_optimize_triggered)
	$Board.action_committed.connect(_on_action_committed)
	$Board.major_action_changed.connect(_on_major_action_changed)
	$Board.sector_revealed.connect(_on_sector_revealed)
	$Board.market_card_drag_failed.connect(_on_market_card_drag_failed)
	$Board.payment_confirm_required.connect(_on_payment_confirm_required)
	$Board.expedition_card_shuffled_back.connect(_on_expedition_shuffled_back)
	$Board.expedition_reveal_requested.connect(_execute_expedition_reveal)
	$Board.market_card_taken.connect(_on_market_card_taken)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_bid_popup = $UILayer/BidPopup
	_payment_panel = $UILayer/PaymentPanel
	_scoreboard = $UILayer/Scoreboard
	_pause_menu = $UILayer/PauseMenu
	_pause_menu.main_menu_pressed.connect(_on_pause_main_menu)
	_bid_popup.bid_confirmed.connect(_on_bid_confirmed)
	_bid_popup.bid_cancelled.connect(_on_bid_cancelled)
	_bid_popup.bid_raised.connect(_on_bid_raised)
	_bid_popup.bid_passed.connect(_on_bid_passed)
	_payment_panel.recycle_requested.connect(_on_payment_recycle_requested)
	ImageCache.progress_updated.connect(_on_cache_progress)
	ImageCache.all_loaded.connect(_on_cache_ready)
	ImageCache.preload_urls(_collect_urls())

	_setup_info_screen_display()


	_bid_payment_panel = load("res://scenes/ui/bid_payment_panel.gd").new()
	_info_viewport.add_child(_bid_payment_panel)
	_register_info_panel(_bid_payment_panel)
	_bid_payment_panel.confirmed.connect(_on_bid_payment_confirmed)
	_bid_payment_panel.forfeited.connect(_on_bid_payment_forfeited)

	_effect_done_btn = Button.new()
	_effect_done_btn.text = "Done"
	_effect_done_btn.visible = false
	_effect_done_btn.add_theme_font_size_override("font_size", 18)
	GameTheme.apply_to_button(_effect_done_btn)
	_effect_done_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_effect_done_btn.offset_top = 50.0
	_effect_done_btn.offset_bottom = 90.0
	_effect_done_btn.offset_left = -60.0
	_effect_done_btn.offset_right = 60.0
	_effect_done_btn.pressed.connect(_on_effect_done_pressed)
	$UILayer.add_child(_effect_done_btn)

	_choice_popup = ChoicePopup.new()
	_choice_popup.name = "ChoicePopup"
	_choice_popup.choice_made.connect(_on_choice_made)
	_choice_popup.skipped.connect(_on_choice_skipped)
	_choice_popup.multiselect_confirmed.connect(_on_multiselect_confirmed)
	_info_viewport.add_child(_choice_popup)
	_register_info_panel(_choice_popup)

	_supply_cost_panel = SupplyCostPanel.new()
	_supply_cost_panel.supply_chosen.connect(_on_supply_chosen)
	_supply_cost_panel.cancelled.connect(_on_supply_choice_cancelled)
	_info_viewport.add_child(_supply_cost_panel)
	_register_info_panel(_supply_cost_panel)

	_sector_info_popup = SectorInfoPopup.new()
	_info_viewport.add_child(_sector_info_popup)
	_register_info_panel(_sector_info_popup)
	_sector_info_popup.cargo_move_requested.connect(_on_cargo_move_requested)
	_sector_info_popup.cargo_cancelled.connect(_on_cargo_cancelled)
	_sector_info_popup.effect_done.connect(_on_effect_done_pressed)

	_recycle_panel = load("res://scenes/ui/recycle_panel.gd").new()
	_info_viewport.add_child(_recycle_panel)
	_register_info_panel(_recycle_panel)
	_recycle_panel.confirmed.connect(_on_recycle_panel_confirmed)
	_recycle_panel.cancelled.connect(_on_recycle_panel_cancelled)

	_sector_picker = load("res://scenes/ui/sector_picker_panel.gd").new()
	_info_viewport.add_child(_sector_picker)
	_register_info_panel(_sector_picker)
	_sector_picker.sector_selected.connect(_on_sector_selected_from_picker)
	_sector_picker.skipped.connect(_on_sector_picker_skipped)

	$Board.sector_info_requested.connect(_on_sector_info_requested)

	_setup_music()
	_setup_control_screen_display()
	_setup_enemy_screen_display()
	_setup_log_screen_display()
	_setup_cockpit_switches()

	_wire_sector_slots_to_board()

func _on_node_added_to_tree(node: Node) -> void:
	if node is Card and not node.has_meta("_main_connected"):
		node.set_meta("_main_connected", true)
		node.elevation_started.connect(_on_card_elevation_started)
		node.elevation_ended.connect(_on_card_elevation_ended)
		node.hovered.connect(_on_any_card_hovered)
		node.unhovered.connect(_on_any_card_unhovered)

func _on_any_card_hovered(card_node: Node3D) -> void:
	var card: Card = card_node as Card
	if not card:
		return
	var desc: String = ""
	if card.is_placed:
		desc = "Right-click to shrink card." if card.is_elevated() else "Right-click to enlarge card."
	elif card.managed_by_hand:
		desc = "Left-click and drag onto sector to buy or Right-click to Recycle."
	elif card.card_data:
		match card.card_data.card_type:
			CardData.CardType.EXPEDITION:
				desc = "left-click and drag onto sector card to start a bid."
			CardData.CardType.SECTOR:
				desc = "Left-click and drag onto a blue sector slot to start a bid." if card.is_advanced else "Left-click and drag onto a blue sector slot to buy sector. Base card to place other cards onto."
	if not desc.is_empty():
		_show_log_tooltip("", desc)

func _on_any_card_unhovered(_card: Node3D) -> void:
	_hide_log_tooltip()

func _on_card_elevation_started(_card: Node3D) -> void:
	_sun_elevated_count += 1
	get_tree().create_timer(0.15).timeout.connect(func() -> void:
		if _sun_elevated_count > 0:
			$SunLayer.visible = false
	)

func _on_card_elevation_ended(_card: Node3D) -> void:
	_sun_elevated_count = max(0, _sun_elevated_count - 1)
	get_tree().create_timer(0.15).timeout.connect(func() -> void:
		if _sun_elevated_count == 0:
			$SunLayer.visible = true
	)

func _wire_sector_slots_to_board() -> void:
	for i: int in 6:
		var slot: SectorSlot = get_node_or_null("SectorSlot" + str(i + 1)) as SectorSlot
		if slot:
			$Board.add_sector_slot(slot)

func _build_opponent_widget() -> void:
	if _opp_widget:
		_opp_widget.queue_free()
	_opp_panels.clear()
	_es_back_btn = null

	var supply_paths: Array = [
		"res://assets/ui/supply/Dust.png",
		"res://assets/ui/supply/Metals.png",
		"res://assets/ui/supply/Liquids.png",
		"res://assets/ui/supply/Organix.png",
		"res://assets/ui/supply/Electrix.png",
		"res://assets/ui/supply/Thrust.png",
	]

	var widget: ScifiPanel = ScifiPanel.new()
	widget.set_content_margin(14)
	widget.theme = GameTheme.get_theme()
	_opp_widget = widget
	widget.mouse_filter = Control.MOUSE_FILTER_STOP
	_es_viewport.add_child(widget)
	widget.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	widget.grow_horizontal = Control.GROW_DIRECTION_BOTH
	widget.grow_vertical = Control.GROW_DIRECTION_BOTH

	var outer_vbox: VBoxContainer = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 6)
	widget.add_child(outer_vbox)

	var title_lbl: Label = Label.new()
	title_lbl.text = "Players"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer_vbox.add_child(title_lbl)

	var title_sep: HSeparator = HSeparator.new()
	title_sep.modulate = Color(0.4, 0.4, 0.5, 0.5)
	outer_vbox.add_child(title_sep)

	for peer_id: int in GameNetwork.player_order:
		if peer_id == multiplayer.get_unique_id():
			continue

		if _market_panel:
			_market_panel.add_opponent(peer_id, GameNetwork.player_names.get(peer_id, "Player"))

		var entry_sep: HSeparator = HSeparator.new()
		entry_sep.modulate = Color(0.4, 0.4, 0.5, 0.3)
		outer_vbox.add_child(entry_sep)

		var pid: int = peer_id

		var entry: PanelContainer = PanelContainer.new()
		entry.mouse_filter = Control.MOUSE_FILTER_STOP
		var entry_style: StyleBoxFlat = StyleBoxFlat.new()
		entry_style.bg_color = Color(0.05, 0.07, 0.15, 0.80)
		entry_style.border_color = Color(0.22, 0.44, 0.70, 0.38)
		entry_style.set_border_width_all(1)
		entry_style.set_corner_radius_all(4)
		entry_style.content_margin_left = 8.0
		entry_style.content_margin_right = 8.0
		entry_style.content_margin_top = 7.0
		entry_style.content_margin_bottom = 7.0
		entry.add_theme_stylebox_override("panel", entry_style)
		entry.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_show_opponent_board(pid)
			entry.accept_event()
		)
		outer_vbox.add_child(entry)

		var entry_vbox: VBoxContainer = VBoxContainer.new()
		entry_vbox.add_theme_constant_override("separation", 4)
		entry_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.add_child(entry_vbox)

		# Row 1: name (expand) + ♠ N
		var row1: HBoxContainer = HBoxContainer.new()
		row1.add_theme_constant_override("separation", 4)
		row1.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry_vbox.add_child(row1)

		var name_lbl: Label = Label.new()
		name_lbl.text = GameNetwork.player_names.get(peer_id, "Player")
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.clip_text = true
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row1.add_child(name_lbl)

		var status_lbl: Label = Label.new()
		status_lbl.add_theme_font_size_override("font_size", 11)
		status_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row1.add_child(status_lbl)

		var hand_lbl: Label = Label.new()
		hand_lbl.text = "♠ 0"
		hand_lbl.add_theme_font_size_override("font_size", 13)
		hand_lbl.add_theme_color_override("font_color", Color(0.70, 0.82, 1.0))
		hand_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row1.add_child(hand_lbl)

		# Row 2: 6 supply columns (icon above count)
		var row2: HBoxContainer = HBoxContainer.new()
		row2.add_theme_constant_override("separation", 2)
		row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry_vbox.add_child(row2)

		var supply_lbls: Array = []
		for si: int in 6:
			var col: VBoxContainer = VBoxContainer.new()
			col.add_theme_constant_override("separation", 0)
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row2.add_child(col)

			var icon: TextureRect = TextureRect.new()
			icon.texture = load(supply_paths[si]) as Texture2D
			icon.custom_minimum_size = Vector2(20.0, 20.0)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(icon)

			var s_lbl: Label = Label.new()
			s_lbl.text = "0"
			s_lbl.add_theme_font_size_override("font_size", 11)
			s_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.90))
			s_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			s_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(s_lbl)
			supply_lbls.append(s_lbl)

		# Row 3: VP right-aligned
		var row3: HBoxContainer = HBoxContainer.new()
		row3.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry_vbox.add_child(row3)

		var spacer: Control = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row3.add_child(spacer)

		var vp_lbl: Label = Label.new()
		vp_lbl.text = "⭐ 0"
		vp_lbl.add_theme_font_size_override("font_size", 12)
		vp_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
		vp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row3.add_child(vp_lbl)

		_opp_panels[peer_id] = {
			"hand_lbl": hand_lbl,
			"supply_lbls": supply_lbls,
			"vp_lbl": vp_lbl,
			"status_lbl": status_lbl,
		}

	var bottom_sep: HSeparator = HSeparator.new()
	bottom_sep.modulate = Color(0.4, 0.4, 0.5, 0.5)
	outer_vbox.add_child(bottom_sep)

	_es_back_btn = Button.new()
	_es_back_btn.text = "← Back to my board"
	_es_back_btn.visible = false
	_es_back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_es_back_btn.add_theme_font_size_override("font_size", 15)
	GameTheme.apply_to_button(_es_back_btn)
	_es_back_btn.pressed.connect(_close_opponent_board_view)
	outer_vbox.add_child(_es_back_btn)

func _collect_urls() -> Array[String]:
	return CardDatabase.get_all_image_urls()

# ── Cache / start ─────────────────────────────────────────────────────────────

func _on_cache_progress(loaded: int, total: int) -> void:
	$UILayer/LoadingLabel.text = "Loading cards... %d / %d" % [loaded, total]

func _on_cache_ready() -> void:
	$UILayer/LoadingLabel.hide()
	if not GameNetwork.is_multiplayer:
		GameNetwork.setup_solo()
		_cached_sector_order = _generate_shuffled_order(CardDatabase.sectors.size())
		_cached_exp_order = _generate_shuffled_order(CardDatabase.expeditions.size())
		call_deferred("_deferred_pre_setup")
	elif GameNetwork.is_host:
		_cached_sector_order = _generate_shuffled_order(CardDatabase.sectors.size())
		_cached_exp_order = _generate_shuffled_order(CardDatabase.expeditions.size())
		call_deferred("_deferred_pre_setup")

func _deferred_pre_setup() -> void:
	_do_game_setup(_cached_sector_order, _cached_exp_order)
	await get_tree().create_timer(3.0).timeout
	if not GameNetwork.is_multiplayer:
		_rpc_start_game([], [])
	elif GameNetwork.is_host:
		_rpc_start_game.rpc(_cached_sector_order, _cached_exp_order)

func _do_game_setup(sector_order: Array, exp_order: Array) -> void:
	_pre_setup_done = true
	_round = 1
	_update_round_label()
	_init_supply()
	if sector_order.is_empty():
		$Board.setup_market()
	else:
		$Board.setup_market_ordered(sector_order)
	$Board.reveal_sector_round_cards()
	if exp_order.is_empty():
		$Board.setup_expedition_deck(CardDatabase.expeditions)
	else:
		$Board.setup_expedition_deck_ordered(exp_order)
	$Board.setup_expedition_market()
	if multiplayer.is_server() and not GameNetwork.bot_ids.is_empty():
		_init_bot_state()
	$Board.refresh_discount_glow()
	_market_panel.setup($Board.get_market(), $Board.get_expedition_market())
	_show_action_buttons(true)
	_show_end_turn_button(true)
	_set_end_turn_button_disabled(true)
	_refresh_vp()
	_update_turn_ui(false)
	if GameNetwork.is_multiplayer:
		_build_opponent_widget()
	_log_action("─── Round 1 / %d ───" % MAX_ROUNDS, Color(0.6, 0.82, 1.0))

func _setup_control_screen_display() -> void:
	_cs_viewport = SubViewport.new()
	_cs_viewport.size = Vector2i(360, 460)
	_cs_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_cs_viewport.transparent_bg = true
	_cs_viewport.gui_disable_input = false
	$UiControl.add_child(_cs_viewport)

	_cs_display = SupplyUI.new()
	_cs_viewport.add_child(_cs_display)

	var panel: Control = _cs_display.get_child(0) as Control
	if panel:
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	_cs_display.supply_changed.connect(_on_supply_changed)
	_cs_display.fuse_1to1_changed.connect(_try_auto_end_turn)

	var screen_mesh: MeshInstance3D = $UiControl.find_child("gs_ui_control_screen", true, false) as MeshInstance3D
	if screen_mesh:
		var aabb: AABB = screen_mesh.mesh.get_aabb()
		var shader: Shader = load("res://shaders/screen_display.gdshader") as Shader
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("viewport_tex", _cs_viewport.get_texture())
		mat.set_shader_parameter("aabb_min", aabb.position)
		mat.set_shader_parameter("aabb_max", aabb.position + aabb.size)
		mat.set_shader_parameter("emission_strength", 1.3)
		mat.set_shader_parameter("scanline_count", 120.0)
		mat.set_shader_parameter("scanline_depth", 0.08)
		mat.set_shader_parameter("vignette_strength", 0.35)
		mat.set_shader_parameter("vignette_falloff", 3.0)
		screen_mesh.set_surface_override_material(0, mat)
		_setup_screen_input(screen_mesh)

	var btn_callbacks: Array[Callable] = [_on_research_pressed, _on_pass_pressed, _on_end_turn_pressed]
	var btn_tooltip_titles: Array[String] = ["Research", "Pass", "End Turn"]
	var btn_tooltip_descs: Array[String] = [
		"Discard a hand card and draw a replacement, once this Action is taken, you can only Research or Pass.",
		"End your turn. Once all players pass the Generation is over.",
		"Finish your turn manually, after buying or placing a card. Mostly automated",
	]
	for i: int in 3:
		var btn_mesh: MeshInstance3D = $UiControl.find_child("gs_ui_control_button%d" % (i + 1), true, false) as MeshInstance3D
		if btn_mesh:
			_setup_button_input(btn_mesh, btn_callbacks[i], btn_tooltip_titles[i], btn_tooltip_descs[i])
			if i == 2:
				_end_turn_btn_mesh = btn_mesh

	$UILayer/SupplyUI.hide()
	$Board.set_supply_ui(_cs_display)

func _setup_screen_input(screen_mesh: MeshInstance3D) -> void:
	_setup_viewport_input(screen_mesh, _cs_viewport)

func _setup_button_input(btn_mesh: MeshInstance3D, callback: Callable, tooltip_title: String = "", tooltip_desc: String = "") -> void:
	var area: Area3D = Area3D.new()
	area.input_ray_pickable = true
	btn_mesh.add_child(area)
	var cshape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	var aabb: AABB = btn_mesh.mesh.get_aabb()
	box.size = Vector3(aabb.size.x, aabb.size.y, aabb.size.z + 0.01)
	cshape.shape = box
	cshape.position = aabb.get_center()
	area.add_child(cshape)
	area.input_event.connect(func(_cam: Node, event: InputEvent, _pos: Vector3, _norm: Vector3, _idx: int) -> void:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				_animate_button_press(btn_mesh)
				callback.call()
	)
	area.mouse_entered.connect(func() -> void:
		var base: Material = btn_mesh.mesh.surface_get_material(0)
		var mat: StandardMaterial3D = (base as StandardMaterial3D).duplicate() as StandardMaterial3D if base is StandardMaterial3D else StandardMaterial3D.new()
		mat.emission_enabled = true
		mat.emission = Color(0.8, 0.9, 1.0)
		mat.emission_energy_multiplier = 0.3
		btn_mesh.set_surface_override_material(0, mat)
		if not tooltip_title.is_empty():
			_show_log_tooltip(tooltip_title, tooltip_desc)
	)
	area.mouse_exited.connect(func() -> void:
		if btn_mesh == _end_turn_btn_mesh and _end_turn_flash_mat != null:
			btn_mesh.set_surface_override_material(0, _end_turn_flash_mat)
		else:
			btn_mesh.set_surface_override_material(0, null)
		_hide_log_tooltip()
	)

func _animate_button_press(btn_mesh: MeshInstance3D) -> void:
	var press_depth: float = btn_mesh.mesh.get_aabb().size.z * 0.35
	var rest_pos: Vector3 = btn_mesh.position
	var tween: Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(btn_mesh, "position", rest_pos + Vector3(0.0, 0.0, -press_depth), 0.07)
	tween.tween_property(btn_mesh, "position", rest_pos, 0.14)

func _setup_cockpit_switches() -> void:
	var cockpit_anim: AnimationPlayer = $UiCockpit.find_child("AnimationPlayer", true, false) as AnimationPlayer

	var switch1: MeshInstance3D = $UiCockpit.find_child("gs_ui_switch_flat1", true, false) as MeshInstance3D
	if switch1:
		_setup_switch_input(switch1, func() -> void:
			_ui_control_shown = not _ui_control_shown
			if cockpit_anim:
				if _ui_control_shown:
					cockpit_anim.play_backwards("gs_ui_switch_flat1_on")
				else:
					cockpit_anim.play("gs_ui_switch_flat1_on")
			var ctrl_anim: AnimationPlayer = $UiControl.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if ctrl_anim:
				if _ui_control_shown:
					ctrl_anim.play("intro")
				else:
					ctrl_anim.play_backwards("intro")
			var log_anim: AnimationPlayer = $UiLog.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if log_anim:
				if _ui_control_shown:
					log_anim.play("intro")
				else:
					log_anim.play_backwards("intro")
		)

	var switch2: MeshInstance3D = $UiCockpit.find_child("gs_ui_switch_flat2", true, false) as MeshInstance3D
	if switch2:
		_setup_switch_input(switch2, func() -> void:
			_ui_info_shown = not _ui_info_shown
			if cockpit_anim:
				if _ui_info_shown:
					cockpit_anim.play_backwards("gs_ui_switch_flat2_on")
				else:
					cockpit_anim.play("gs_ui_switch_flat2_on")
			var anim: AnimationPlayer = $UiInfo.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if anim:
				if _ui_info_shown:
					anim.play("intro")
				else:
					anim.play_backwards("intro")
		)

func _setup_switch_input(switch_mesh: MeshInstance3D, callback: Callable) -> void:
	var area: Area3D = Area3D.new()
	area.input_ray_pickable = true
	switch_mesh.add_child(area)
	var cshape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	var aabb: AABB = switch_mesh.mesh.get_aabb()
	box.size = Vector3(aabb.size.x, aabb.size.y, aabb.size.z + 0.01)
	cshape.shape = box
	cshape.position = aabb.get_center()
	area.add_child(cshape)
	area.input_event.connect(func(_cam: Node, event: InputEvent, _pos: Vector3, _norm: Vector3, _idx: int) -> void:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				callback.call()
	)

func _setup_viewport_input(screen_mesh: MeshInstance3D, vp: SubViewport) -> void:
	var area: Area3D = Area3D.new()
	area.input_ray_pickable = true
	screen_mesh.add_child(area)
	var cshape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	var aabb: AABB = screen_mesh.mesh.get_aabb()
	box.size = Vector3(aabb.size.x, aabb.size.y, 0.002)
	cshape.shape = box
	cshape.position = aabb.get_center()
	area.add_child(cshape)
	area.input_event.connect(func(_cam: Node, event: InputEvent, pos: Vector3, _norm: Vector3, _idx: int) -> void:
		_forward_to_viewport(event, pos, screen_mesh, vp)
	)
	area.mouse_exited.connect(func() -> void:
		if _vp_button_held:
			return
		_vp_prev_pos.erase(vp)
		var mm: InputEventMouseMotion = InputEventMouseMotion.new()
		mm.position = Vector2(-1.0, -1.0)
		vp.push_input(mm, true)
	)

func _forward_to_viewport(event: InputEvent, world_pos: Vector3, mesh: MeshInstance3D, vp: SubViewport) -> void:
	var local_pos: Vector3 = mesh.to_local(world_pos)
	var aabb: AABB = mesh.mesh.get_aabb()
	var u: float = (local_pos.x - aabb.position.x) / aabb.size.x
	var v: float = 1.0 - (local_pos.y - aabb.position.y) / aabb.size.y
	var vp_pos: Vector2 = Vector2(u * float(vp.size.x), v * float(vp.size.y))
	if event is InputEventMouseButton:
		var src: InputEventMouseButton = event as InputEventMouseButton
		_vp_button_held = src.pressed
		var mb: InputEventMouseButton = InputEventMouseButton.new()
		mb.button_index = src.button_index
		mb.pressed = src.pressed
		mb.button_mask = src.button_mask
		mb.position = vp_pos
		vp.push_input(mb, true)
	elif event is InputEventMouseMotion:
		var prev: Vector2 = _vp_prev_pos.get(vp, vp_pos)
		_vp_prev_pos[vp] = vp_pos
		var mm: InputEventMouseMotion = InputEventMouseMotion.new()
		mm.position = vp_pos
		mm.relative = vp_pos - prev
		vp.push_input(mm, true)

func _setup_info_screen_display() -> void:
	_info_viewport = SubViewport.new()
	_info_viewport.size = Vector2i(1200, 572)
	_info_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_info_viewport.transparent_bg = true
	_info_viewport.gui_disable_input = false
	$UiInfo.add_child(_info_viewport)

	var info_bg: ColorRect = ColorRect.new()
	info_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	info_bg.color = Color(0.03, 0.04, 0.09, 0.93)
	info_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_viewport.add_child(info_bg)

	_market_panel = load("res://scenes/ui/market_panel.gd").new()
	_info_viewport.add_child(_market_panel)
	_market_panel.scale = Vector2(1.68, 1.68)

	_market_panel.sector_advanced_pressed.connect(_on_market_sector_advanced_pressed)
	_market_panel.sector_dust_pressed.connect(_on_market_sector_dust_pressed)
	_market_panel.expedition_pressed.connect(_on_market_expedition_pressed)
	_market_panel.opponent_pressed.connect(_show_opponent_board)
	_market_panel.card_hovered.connect(_on_market_card_hovered)
	_market_panel.card_unhovered.connect(_on_market_card_unhovered)

	var screen_mesh: MeshInstance3D = $UiInfo.find_child("gs_ui_info_screen", true, false) as MeshInstance3D
	if screen_mesh:
		_info_screen_mesh = screen_mesh
		var aabb: AABB = screen_mesh.mesh.get_aabb()
		var shader: Shader = load("res://shaders/screen_display.gdshader") as Shader
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("viewport_tex", _info_viewport.get_texture())
		mat.set_shader_parameter("aabb_min", aabb.position)
		mat.set_shader_parameter("aabb_max", aabb.position + aabb.size)
		mat.set_shader_parameter("emission_strength", 0.45)
		mat.set_shader_parameter("exposure", 0.6)
		mat.set_shader_parameter("scanline_count", 60.0)
		mat.set_shader_parameter("scanline_depth", 0.06)
		mat.set_shader_parameter("vignette_strength", 0.25)
		mat.set_shader_parameter("vignette_falloff", 2.5)
		mat.set_shader_parameter("bloom_threshold", 0.7)
		screen_mesh.set_surface_override_material(0, mat)
		_setup_info_screen_input(screen_mesh)
	for p: Control in [_bid_popup, _payment_panel, _scoreboard]:
		p.reparent(_info_viewport, false)
		_register_info_panel(p)

	var hint_root := Control.new()
	hint_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint_root.offset_bottom = 56.0
	hint_root.z_index = 10
	hint_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hint_bg := ColorRect.new()
	hint_bg.color = Color(0.03, 0.04, 0.09, 0.92)
	hint_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_root.add_child(hint_bg)
	var hint_border := ColorRect.new()
	hint_border.color = Color(0.3, 0.6, 1.0, 0.55)
	hint_border.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint_border.offset_top = -2.0
	hint_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_root.add_child(hint_border)
	var hint_label := Label.new()
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 22)
	hint_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	hint_label.add_theme_constant_override("outline_size", 2)
	hint_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_root.add_child(hint_label)
	_effect_hint_panel = hint_root
	_effect_hint_label = hint_label
	_effect_hint_panel.hide()
	_info_viewport.add_child(hint_root)

func _setup_info_screen_input(screen_mesh: MeshInstance3D) -> void:
	_setup_viewport_input(screen_mesh, _info_viewport)

func _effect_card_origin(card_node: Node3D, cd: CardData) -> Vector3:
	if not _market_panel:
		return $UiInfo.global_position
	var slot_idx: int = card_node.get_meta("market_slot", 0)
	var slot_type: String
	if cd.card_type == CardData.CardType.EXPEDITION:
		slot_type = "expedition"
	elif bool(card_node.get("is_advanced")):
		slot_type = "advanced"
	else:
		slot_type = "dust"
	return _viewport_to_world(_market_panel.get_slot_center(slot_type, slot_idx))

func _viewport_to_world(vp_pos: Vector2) -> Vector3:
	if not _info_screen_mesh:
		return $UiInfo.global_position
	var aabb: AABB = _info_screen_mesh.mesh.get_aabb()
	var u: float = vp_pos.x / float(_info_viewport.size.x)
	var v: float = vp_pos.y / float(_info_viewport.size.y)
	var local_x: float = u * aabb.size.x + aabb.position.x
	var local_y: float = (1.0 - v) * aabb.size.y + aabb.position.y
	return _info_screen_mesh.to_global(Vector3(local_x, local_y, 0.0))

func _register_info_panel(panel: Control) -> void:
	_info_panels.append(panel)
	panel.visibility_changed.connect(func() -> void:
		if not _market_panel:
			return
		if panel.visible:
			_market_panel.visible = false
		else:
			var any_active: bool = false
			for p: Control in _info_panels:
				if p != panel and p.is_inside_tree() and p.visible:
					any_active = true
					break
			_market_panel.visible = not any_active
	)

func _setup_log_screen_display() -> void:
	var myriad: FontFile = load("res://assets/fonts/Myriad Variable Concept.ttf") as FontFile
	if myriad:
		_log_font = FontVariation.new()
		_log_font.base_font = myriad
		_log_font.variation_opentype = {"wght": 500}

	_log_viewport = SubViewport.new()
	# 686×408 viewport: 686 = 980 × 0.7 compensates for UiLog non-uniform world scale
	# so all content pixels are square in world space without per-element correction.
	# Canvas is portrait (408×686) rotated 90° CW to fill the landscape viewport.
	_log_viewport.size = Vector2i(686, 408)
	_log_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_log_viewport.transparent_bg = true
	_log_viewport.gui_disable_input = false
	$UiLog.add_child(_log_viewport)

	var canvas: Control = Control.new()
	canvas.size = Vector2(408.0, 686.0)
	canvas.rotation_degrees = 90.0
	canvas.position = Vector2(686.0, 0.0)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_viewport.add_child(canvas)
	_log_canvas = canvas

	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.09, 0.93)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(bg)

	var header: Label = Label.new()
	header.text = "Event Log"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 24)
	header.add_theme_color_override("font_color", Color(0.65, 0.80, 1.0))
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_top = 12.0
	header.offset_bottom = 64.0
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(header)

	var sep: ColorRect = ColorRect.new()
	sep.color = Color(0.25, 0.45, 0.80, 0.5)
	sep.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	sep.offset_top = 64.0
	sep.offset_bottom = 66.0
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(sep)

	_log_scroll = ScrollContainer.new()
	_log_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_log_scroll.offset_top = 68.0
	_log_scroll.follow_focus = false
	_log_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(_log_scroll)

	_log_vbox = VBoxContainer.new()
	_log_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_vbox.add_theme_constant_override("separation", 2)
	_log_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_scroll.add_child(_log_vbox)

	var screen_mesh: MeshInstance3D = $UiLog.find_child("gs_ui_log_screen", true, false) as MeshInstance3D
	if screen_mesh:
		var aabb: AABB = screen_mesh.mesh.get_aabb()
		var shader: Shader = load("res://shaders/screen_display.gdshader") as Shader
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("viewport_tex", _log_viewport.get_texture())
		mat.set_shader_parameter("aabb_min", aabb.position)
		mat.set_shader_parameter("aabb_max", aabb.position + aabb.size)
		mat.set_shader_parameter("emission_strength", 0.45)
		mat.set_shader_parameter("exposure", 0.6)
		mat.set_shader_parameter("scanline_count", 80.0)
		mat.set_shader_parameter("scanline_depth", 0.05)
		mat.set_shader_parameter("vignette_strength", 0.2)
		mat.set_shader_parameter("vignette_falloff", 2.5)
		mat.set_shader_parameter("bloom_threshold", 0.7)
		screen_mesh.set_surface_override_material(0, mat)
		_setup_viewport_input(screen_mesh, _log_viewport)

	# Preview panel – hidden until hover. Size is set in _on_market_card_hovered.
	var preview_wrap: Control = Control.new()
	preview_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_wrap.visible = false
	_log_canvas.add_child(preview_wrap)
	_log_preview_panel = preview_wrap

	var pp: PanelContainer = PanelContainer.new()
	var preview_style: StyleBoxFlat = StyleBoxFlat.new()
	preview_style.bg_color = Color(0.04, 0.04, 0.09, 0.97)
	preview_style.border_color = Color(0.3, 0.55, 0.85, 0.55)
	preview_style.set_border_width_all(1)
	preview_style.set_corner_radius_all(6)
	pp.add_theme_stylebox_override("panel", preview_style)
	pp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_wrap.add_child(pp)
	pp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_log_preview_image = TextureRect.new()
	_log_preview_image.stretch_mode = TextureRect.STRETCH_SCALE
	_log_preview_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_log_preview_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var preview_mat: ShaderMaterial = ShaderMaterial.new()
	preview_mat.shader = load("res://shaders/card_rounded.gdshader")
	_log_preview_image.material = preview_mat
	preview_wrap.add_child(_log_preview_image)

	var lt_panel: PanelContainer = PanelContainer.new()
	lt_panel.visible = false
	lt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lt_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lt_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	lt_panel.scale = Vector2(1.5, 1.5)
	lt_panel.resized.connect(func() -> void: lt_panel.pivot_offset = lt_panel.size / 2.0)
	var lt_style: StyleBoxFlat = StyleBoxFlat.new()
	lt_style.bg_color = Color(0.05, 0.07, 0.15, 0.94)
	lt_style.border_color = Color(0.3, 0.55, 0.85, 0.55)
	lt_style.set_border_width_all(1)
	lt_style.set_corner_radius_all(4)
	lt_style.content_margin_left = 12.0
	lt_style.content_margin_right = 12.0
	lt_style.content_margin_top = 8.0
	lt_style.content_margin_bottom = 8.0
	lt_panel.add_theme_stylebox_override("panel", lt_style)
	var lt_vbox: VBoxContainer = VBoxContainer.new()
	lt_vbox.add_theme_constant_override("separation", 3)
	lt_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lt_panel.add_child(lt_vbox)
	_log_tooltip_title = Label.new()
	_log_tooltip_title.add_theme_font_size_override("font_size", 20)
	_log_tooltip_title.add_theme_color_override("font_color", Color(0.82, 0.93, 1.0))
	_log_tooltip_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log_tooltip_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lt_vbox.add_child(_log_tooltip_title)
	_log_tooltip_desc = Label.new()
	_log_tooltip_desc.add_theme_font_size_override("font_size", 20)
	_log_tooltip_desc.add_theme_color_override("font_color", Color(0.60, 0.68, 0.82))
	_log_tooltip_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log_tooltip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_log_tooltip_desc.custom_minimum_size = Vector2(230, 0)
	_log_tooltip_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lt_vbox.add_child(_log_tooltip_desc)
	_log_canvas.add_child(lt_panel)
	_log_tooltip_panel = lt_panel

func _show_log_tooltip(title: String, desc: String) -> void:
	if not _log_tooltip_panel:
		return
	_log_tooltip_title.text = title
	_log_tooltip_title.visible = not title.is_empty()
	_log_tooltip_desc.text = desc
	_log_tooltip_panel.visible = true

func _hide_log_tooltip() -> void:
	if _log_tooltip_panel:
		_log_tooltip_panel.visible = false

func _log_action(text: String, color: Color = Color(0.80, 0.88, 1.0)) -> void:
	if not _log_vbox:
		return
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.add_theme_color_override("font_color", color)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.clip_text = true
	if _log_font:
		lbl.add_theme_font_override("font", _log_font)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_vbox.add_child(lbl)
	_log_scroll.call_deferred("set_v_scroll", 999999)

# Host → All: append a line to the event log.
@rpc("authority", "reliable", "call_local")
func _rpc_log_event(text: String, color_r: float, color_g: float, color_b: float) -> void:
	_log_action(text, Color(color_r, color_g, color_b))

# Client → Host: broadcast a log entry to all players.
@rpc("any_peer", "reliable")
func _rpc_request_log_event(text: String, color_r: float, color_g: float, color_b: float) -> void:
	if not multiplayer.is_server():
		return
	_rpc_log_event.rpc(text, color_r, color_g, color_b)

func _broadcast_log(text: String, color: Color = Color(0.80, 0.88, 1.0)) -> void:
	if GameNetwork.is_multiplayer:
		if GameNetwork.is_host:
			_rpc_log_event.rpc(text, color.r, color.g, color.b)
		else:
			_rpc_request_log_event.rpc_id(1, text, color.r, color.g, color.b)
	else:
		_log_action(text, color)

func _setup_enemy_screen_display() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.visible = false
	$UILayer.add_child(panel)
	_es_viewport = panel

func _init_bot_state() -> void:
	for bot_id: int in GameNetwork.bot_ids:
		var supply: Dictionary = {
			int(CardData.SupplyColor.DUST):     4,
			int(CardData.SupplyColor.METALS):   2,
			int(CardData.SupplyColor.LIQUIDS):  2,
			int(CardData.SupplyColor.ORGANIX):  1,
			int(CardData.SupplyColor.ELECTRIX): 1,
			int(CardData.SupplyColor.THRUST):   0,
		}
		_bot_supplies[bot_id] = supply
		_bot_hands[bot_id] = $Board.draw_card_data(6)
		_bot_boards[bot_id] = []

func _update_bots_for_new_round() -> void:
	for bot_id: int in GameNetwork.bot_ids:
		var old_hand: Array = _bot_hands.get(bot_id, [])
		for cd: Variant in old_hand:
			$Board.add_to_discard(cd as CardData)
		_bot_hands[bot_id] = $Board.draw_card_data(6)
		var supply: Dictionary = _bot_supplies.get(bot_id, {})
		for color: CardData.SupplyColor in CardData.SupplyColor.values():
			supply[int(color)] = supply.get(int(color), 0) + 1
		_bot_supplies[bot_id] = supply

func _get_bot_snapshot(bot_id: int) -> Dictionary:
	var hand_arr: Array = _bot_hands.get(bot_id, []) as Array
	var board: Array = _bot_boards.get(bot_id, []) as Array
	var slot_snaps: Array = []
	for entry_v: Variant in board:
		var entry: Dictionary = entry_v as Dictionary
		var sector: CardData = entry.get("sector") as CardData
		if sector == null:
			continue
		var is_adv: bool = bool(entry.get("is_advanced", false))
		var techs: Array = entry.get("techs", []) as Array
		var tech_names: Array[String] = []
		for t: Variant in techs:
			var tc: CardData = t as CardData
			if tc:
				tech_names.append(tc.card_name)
		slot_snaps.append({
			"occupied": true,
			"optimize_count": 0,
			"max_optimizations": 0,
			"is_optimized": false,
			"tech_count": techs.size(),
			"sector_name": sector.adv_name if (is_adv and not sector.adv_name.is_empty()) else sector.card_name,
			"sector_advanced": is_adv,
			"tech_names": tech_names,
			"position": {"x": 0.0, "z": 0.0},
		})
	return {
		"peer_id": bot_id,
		"supply": _bot_supplies.get(bot_id, {}),
		"hand_size": hand_arr.size(),
		"vp": 0,
		"vp_lines": [],
		"slots": slot_snaps,
	}

# ── Bot AI turn engine ────────────────────────────────────────────────────────

func _run_bot_turn(bot_id: int) -> void:
	await get_tree().create_timer(1.0 + randf() * 0.5).timeout
	if GameNetwork.active_peer_id != bot_id:
		return
	if _bots_passed_this_round.has(bot_id):
		_server_handle_end_turn()
		return
	var difficulty: int = GameNetwork.bot_difficulty.get(bot_id, BotAI.Difficulty.EASY)
	var market_sectors: Array[CardData] = $Board.get_available_dust_sectors()
	var action: Dictionary = BotAI.decide_action(
		difficulty, _bot_hand(bot_id), _bot_supplies.get(bot_id, {}) as Dictionary,
		_bot_boards.get(bot_id, []) as Array, _round, market_sectors)
	match action.get("type", "pass"):
		"buy_sector":
			_bot_buy_sector(bot_id, action["card"] as CardData)
			_broadcast_bot_states()
			await get_tree().create_timer(0.5).timeout
			_server_handle_end_turn()
		"place_tech":
			_bot_place_tech(bot_id, action["card"] as CardData, action["slot_idx"] as int)
			_broadcast_bot_states()
			await get_tree().create_timer(0.5).timeout
			_server_handle_end_turn()
		"research":
			_bot_do_research(bot_id)
			_broadcast_bot_states()
			var _rname: String = GameNetwork.player_names.get(bot_id, "Bot")
			_broadcast_log("%s: researching…" % _rname, Color(0.50, 0.78, 1.0))
			await get_tree().create_timer(0.3).timeout
			_bot_pass(bot_id)
		_:
			_bot_pass(bot_id)


func _bot_hand(bot_id: int) -> Array[CardData]:
	var result: Array[CardData] = []
	for item: Variant in (_bot_hands.get(bot_id, []) as Array):
		if item is CardData:
			result.append(item as CardData)
	return result

func _bot_set_hand(bot_id: int, hand: Array[CardData]) -> void:
	_bot_hands[bot_id] = hand


func _bot_buy_sector(bot_id: int, card_data: CardData) -> void:
	var color: int = int(card_data.color)
	_bot_supplies[bot_id][color] = max(0, _bot_supplies[bot_id].get(color, 0) - max(0, card_data.cost))
	$Board.get_market().remove_card(card_data)
	_bot_boards[bot_id].append({"sector": card_data, "is_advanced": false, "techs": [], "stored": {}})
	_apply_bot_effect_steps(bot_id, _simple_bot_card_steps(card_data))
	var _bname: String = GameNetwork.player_names.get(bot_id, "Bot")
	_broadcast_log("%s: bought %s" % [_bname, card_data.card_name], CardData.color_tint(card_data.color))


func _bot_place_tech(bot_id: int, card_data: CardData, slot_idx: int) -> void:
	var hand: Array[CardData] = _bot_hand(bot_id)
	hand.erase(card_data)
	_bot_set_hand(bot_id, hand)
	var color: int = int(card_data.color)
	_bot_supplies[bot_id][color] = max(0, _bot_supplies[bot_id].get(color, 0) - max(0, card_data.cost))
	(_bot_boards[bot_id][slot_idx]["techs"] as Array).append(card_data)
	_apply_bot_effect_steps(bot_id, _simple_bot_card_steps(card_data))
	var _bname: String = GameNetwork.player_names.get(bot_id, "Bot")
	_broadcast_log("%s: placed %s" % [_bname, card_data.card_name], CardData.color_tint(card_data.color))


func _bot_do_research(bot_id: int) -> void:
	var hand: Array[CardData] = _bot_hand(bot_id)
	if hand.is_empty():
		return
	hand.sort_custom(func(a: CardData, b: CardData) -> bool: return a.cost < b.cost)
	$Board.add_to_discard(hand.pop_front())
	hand.append_array($Board.draw_card_data(1))
	_bot_set_hand(bot_id, hand)


func _bot_pass(bot_id: int) -> void:
	_bots_passed_this_round.append(bot_id)
	_server_handle_pass()


func _broadcast_bot_states() -> void:
	for bot_id: int in GameNetwork.bot_ids:
		var bot_state: Dictionary = _get_bot_snapshot(bot_id)
		_apply_opponent_state(bot_state)
		for peer_id: int in GameNetwork.player_order:
			if peer_id != 1 and not GameNetwork.is_bot(peer_id):
				_rpc_recv_board_state.rpc_id(peer_id, bot_state)


func _simple_bot_card_steps(_card_data: CardData) -> Array[Dictionary]:
	return []


func _apply_bot_effect_steps(bot_id: int, steps: Array[Dictionary]) -> void:
	for step: Dictionary in steps:
		match step.get("type"):
			"draw":
				var hand: Array[CardData] = _bot_hand(bot_id)
				hand.append_array($Board.draw_card_data(int(step.get("count", 1))))
				_bot_set_hand(bot_id, hand)
			"gain_supply":
				var c: int = int(step.get("color", 0))
				_bot_supplies[bot_id][c] = _bot_supplies[bot_id].get(c, 0) + int(step.get("amount", 1))
			"choice":
				var opts: Array = step.get("options", []) as Array
				if not opts.is_empty():
					_apply_bot_effect_steps(bot_id, opts[0].get("steps", []) as Array[Dictionary])


func _bot_decide_bid(bot_id: int) -> void:
	var cd: CardData = CardRef.from_ref(_auction_card_ref)
	if cd == null:
		_server_handle_pass_bid(bot_id)
		return
	var new_bid: int = BotAI.decide_bid(
		GameNetwork.bot_difficulty.get(bot_id, BotAI.Difficulty.EASY),
		_auction_current_bid, _bot_supplies.get(bot_id, {}), cd, _auction_is_adv)
	if new_bid > 0:
		_server_handle_raise(bot_id, new_bid)
	else:
		_server_handle_pass_bid(bot_id)

func _generate_shuffled_order(size: int) -> Array:
	var order: Array = []
	for i: int in size:
		order.append(i)
	order.shuffle()
	return order

func _flicker_sector_slots() -> void:
	var slots: Array[SectorSlot] = $Board.get_sector_slots()
	await get_tree().create_timer(0.15).timeout
	const STAGGER: float = 0.25
	const PATTERN_DURATION: float = 0.66  # sum of durations in _flicker_one_slot
	for i: int in slots.size():
		_flicker_one_slot(slots[i], float(i) * STAGGER)
	await get_tree().create_timer(float(slots.size() - 1) * STAGGER + PATTERN_DURATION).timeout

func _flicker_one_slot(slot: SectorSlot, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	var on_off: Array[float]    = [1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 0.0]
	var durations: Array[float] = [0.07, 0.09, 0.05, 0.14, 0.12, 0.06, 0.08, 0.05]
	for i: int in on_off.size():
		slot.set_slot_brightness(on_off[i])
		await get_tree().create_timer(durations[i]).timeout
	slot.set_slot_brightness(1.0)

@rpc("authority", "reliable", "call_local")
func _rpc_start_game(sector_order: Array, exp_order: Array) -> void:
	if not _pre_setup_done:
		_do_game_setup(sector_order, exp_order)

	for slot: SectorSlot in $Board.get_sector_slots():
		slot.set_slot_brightness(0.0)

	var ui_control_anim := $UiControl.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ui_control_anim:
		ui_control_anim.play("intro", -1, 0.5)
		_ui_control_shown = true
		await ui_control_anim.animation_finished

	var ui_info_anim := $UiInfo.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ui_info_anim:
		ui_info_anim.play("intro", -1, 0.5)
		_ui_info_shown = true
		await ui_info_anim.animation_finished

	var ui_log_anim := $UiLog.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ui_log_anim:
		ui_log_anim.play("intro", -1, 0.5)
		await ui_log_anim.animation_finished

	await _flicker_sector_slots()
	$Board.deal_opening_hand()
	if GameNetwork.is_multiplayer:
		_broadcast_my_state()
	await get_tree().create_timer(2.0).timeout
	if GameNetwork.is_my_turn():
		_show_your_turn_banner()
	if multiplayer.is_server() and GameNetwork.is_bot(GameNetwork.active_peer_id):
		_run_bot_turn(GameNetwork.active_peer_id)

# ── Round flow ────────────────────────────────────────────────────────────────

func _on_research_pressed() -> void:
	if not GameNetwork.is_my_turn():
		return
	_effect_mode = EffectMode.RESEARCH
	_set_action_buttons_disabled(true)
	_show_effect_hint("Click a card in your hand to discard it")
	$Hand.set_discard_mode(true)
	if GameNetwork.is_multiplayer:
		if GameNetwork.is_host:
			_rpc_sync_opp_status.rpc(multiplayer.get_unique_id(), "researching")
		else:
			_rpc_request_research_status.rpc_id(1)

func _on_pass_pressed() -> void:
	if not GameNetwork.is_my_turn():
		return
	_do_pass()

func _do_pass() -> void:
	_has_passed = true
	_ending_turn = true
	_cs_display.clear_fuse_1to1()
	_ending_turn = false
	_show_action_buttons(false)
	_broadcast_my_state()
	if GameNetwork.is_multiplayer:
		if GameNetwork.is_host:
			_server_handle_pass()
		else:
			_rpc_request_pass.rpc_id(1)
		return
	_log_action("You: passed", Color(0.55, 0.55, 0.70))
	var supply_dur: float = _apply_supply_generation()
	var delay: float = maxf(supply_dur + 0.15, 0.25)
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		_show_round_transition(_end_round))

func _apply_supply_generation() -> float:
	var generators: Array[Dictionary] = $Board.get_supply_generators()
	var cam: Camera3D = $Camera3D
	var ui: SupplyUI = _cs_display
	var totals: Dictionary = {}
	for i: int in generators.size():
		var entry: Dictionary = generators[i]
		var color: CardData.SupplyColor = entry["color"] as CardData.SupplyColor
		var card: Node3D = entry["card"] as Node3D
		var screen_pos: Vector2 = cam.unproject_position(card.global_position)
		ui.animate_supply_incoming(screen_pos, color, float(i) * 0.1)
		totals[color] = totals.get(color, 0) + 1
	for color: CardData.SupplyColor in totals:
		ui.add_supply(color, totals[color])
	if generators.is_empty():
		return 0.0
	return float(generators.size() - 1) * 0.1 + 0.45

func _make_banner_label(text: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lbl.grow_vertical = Control.GROW_DIRECTION_BOTH
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.modulate.a = 0.0
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UILayer.add_child(lbl)
	return lbl

func _show_round_transition(then: Callable) -> void:
	var lbl: Label = _make_banner_label("End of Round %d" % _round, 72, Color(0.75, 0.90, 1.0))
	var t: Tween = create_tween()
	t.tween_property(lbl, "modulate:a", 1.0, 0.3)
	t.tween_interval(0.85)
	t.tween_property(lbl, "modulate:a", 0.0, 0.35)
	t.tween_callback(lbl.queue_free)
	t.tween_callback(then)

func _end_round() -> void:
	_has_passed = false
	_has_researched = false
	_bots_passed_this_round.clear()
	_opp_statuses.clear()
	_refresh_all_opp_status_labels()
	$Board.reset_turn()
	if _round >= MAX_ROUNDS:
		_log_action("─── Game over ───", Color(0.6, 0.82, 1.0))
		_game_over()
		return
	_round += 1
	_log_action("─── Round %d / %d ───" % [_round, MAX_ROUNDS], Color(0.6, 0.82, 1.0))
	_update_round_label()
	$Board.draw_cards(6)
	if multiplayer.is_server() and not GameNetwork.bot_ids.is_empty():
		_update_bots_for_new_round()
	$Board.reveal_sector_round_cards()
	$Board.add_expedition_round_cards()
	_show_action_buttons(true)
	_set_action_buttons_disabled(false)

func _update_round_label() -> void:
	_cs_display.set_round(_round, MAX_ROUNDS)
	_cs_display.show_game_info(true)

# ── Multiplayer turn management ───────────────────────────────────────────────

func _update_turn_ui(show_banner: bool = true) -> void:
	if not GameNetwork.is_multiplayer:
		_cs_display.show_turn_indicator(false)
		return
	_cs_display.show_turn_indicator(true)
	var my_turn: bool = GameNetwork.is_my_turn()
	_cs_display.set_my_turn(my_turn)
	if show_banner and my_turn and _round > 0:
		_show_your_turn_banner()
	_set_action_buttons_disabled(not my_turn)

func _show_your_turn_banner() -> void:
	var lbl: Label = _make_banner_label("Your Turn", 56, Color(0.45, 1.0, 0.55))
	var t: Tween = create_tween()
	t.tween_property(lbl, "modulate:a", 1.0, 0.22).set_ease(Tween.EASE_OUT)
	t.tween_interval(1.0)
	t.tween_property(lbl, "modulate:a", 0.0, 0.38).set_ease(Tween.EASE_IN)
	t.tween_callback(lbl.queue_free)

func _server_handle_pass() -> void:
	_rpc_sync_opp_status.rpc(GameNetwork.active_peer_id, "passed")
	_players_passed_this_round += 1
	if _players_passed_this_round >= GameNetwork.player_order.size():
		_players_passed_this_round = 0
		_rpc_sync_end_round.rpc()
	else:
		GameNetwork.advance_turn()
		_rpc_sync_active_player.rpc(GameNetwork.active_peer_id)

# Client → Host: I have passed my turn.
@rpc("any_peer", "reliable")
func _rpc_request_pass() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != GameNetwork.active_peer_id:
		return
	_server_handle_pass()

# Host → All: active player changed.
@rpc("authority", "reliable", "call_local")
func _rpc_sync_active_player(peer_id: int) -> void:
	GameNetwork.active_peer_id = peer_id
	var already_passed: bool = GameNetwork.is_my_turn() and _has_passed
	if not already_passed:
		$Board.reset_turn()
		_show_action_buttons(true)
		if _has_researched and GameNetwork.is_my_turn():
			$Board.set_major_action_taken()
	else:
		$Board.set_major_action_taken()
	_update_turn_ui()
	if GameNetwork.is_my_turn() and not _deferred_effect_queue.is_empty():
		_effect_slot = _deferred_effect_slot
		_effect_queue.append_array(_deferred_effect_queue)
		_deferred_effect_queue.clear()
		_deferred_effect_slot = null
		_process_next_effect()
	_refresh_all_opp_status_labels()
	if multiplayer.is_server() and GameNetwork.is_bot(peer_id):
		_run_bot_turn(peer_id)

# Host → All: all players passed — end the round and start the next.
@rpc("authority", "reliable", "call_local")
func _rpc_sync_end_round() -> void:
	var supply_dur: float = _apply_supply_generation()
	var delay: float = maxf(supply_dur + 0.15, 1.1)
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		_show_round_transition(func() -> void:
			_end_round()
			if GameNetwork.is_multiplayer and not GameNetwork.player_order.is_empty():
				var first_idx: int = (_round - 1) % GameNetwork.player_order.size()
				GameNetwork.active_peer_id = GameNetwork.player_order[first_idx]
				_update_turn_ui()
				if multiplayer.is_server() and GameNetwork.is_bot(GameNetwork.active_peer_id):
					_run_bot_turn(GameNetwork.active_peer_id)
			_broadcast_my_state()))

# ── Multiplayer state broadcast ───────────────────────────────────────────────

func _get_public_snapshot() -> Dictionary:
	var supply_snap: Dictionary = {}
	for color: CardData.SupplyColor in CardData.SupplyColor.values():
		supply_snap[int(color)] = _cs_display.get_supply(color)
	var slot_snaps: Array = []
	for slot: SectorSlot in $Board.get_all_sector_slots():
		var slot_info: Dictionary = {
			"occupied": slot.occupied,
			"optimize_count": slot.optimize_count,
			"max_optimizations": slot.max_optimizations,
			"is_optimized": slot.is_optimized,
			"tech_count": slot.get_tech_count(),
			"sector_name": "",
			"sector_advanced": false,
		}
		if slot.occupied and slot.placed_card and slot.placed_card.card_data:
			var cd: CardData = slot.placed_card.card_data
			var is_adv: bool = bool(slot.placed_card.get("is_advanced"))
			slot_info["sector_name"] = cd.adv_name if is_adv else cd.card_name
			slot_info["sector_advanced"] = is_adv
		var tech_names: Array[String] = []
		for ts: Node3D in slot._tech_slots:
			if ts.get("occupied") and ts.get("placed_card") and ts.placed_card.card_data:
				tech_names.append(ts.placed_card.card_data.card_name)
		slot_info["tech_names"] = tech_names
		slot_info["position"] = {"x": slot.global_position.x, "z": slot.global_position.z}
		slot_snaps.append(slot_info)
	var vp_lines: Array[Dictionary] = $Board.calculate_score()
	var total_vp: int = 0
	for vp_line: Dictionary in vp_lines:
		total_vp += int(vp_line.get("vp", 0))
	return {
		"peer_id": multiplayer.get_unique_id(),
		"supply": supply_snap,
		"hand_size": $Hand.get_cards().size(),
		"vp": total_vp,
		"vp_lines": vp_lines,
		"slots": slot_snaps,
	}

func _broadcast_my_state() -> void:
	if not GameNetwork.is_multiplayer:
		return
	var state: Dictionary = _get_public_snapshot()
	if GameNetwork.is_host:
		for peer_id: int in GameNetwork.player_order:
			if peer_id != 1 and not GameNetwork.is_bot(peer_id):
				_rpc_recv_board_state.rpc_id(peer_id, state)
		for bot_id: int in GameNetwork.bot_ids:
			var bot_state: Dictionary = _get_bot_snapshot(bot_id)
			_apply_opponent_state(bot_state)
			for peer_id: int in GameNetwork.player_order:
				if peer_id != 1 and not GameNetwork.is_bot(peer_id):
					_rpc_recv_board_state.rpc_id(peer_id, bot_state)
	else:
		_rpc_send_board_state.rpc_id(1, state)

func _apply_opponent_state(state: Dictionary) -> void:
	var peer_id: int = state.get("peer_id", 0)
	_opp_snapshots[peer_id] = state
	if _market_panel:
		_market_panel.update_opponent(peer_id, state.get("hand_size", 0), state.get("supply", {}), state.get("vp", 0))
	if not _opp_panels.has(peer_id):
		return
	var refs: Dictionary = _opp_panels[peer_id]

	var hand_lbl: Label = refs["hand_lbl"] as Label
	hand_lbl.text = "♠ %d" % state.get("hand_size", 0)

	var supply_snap: Dictionary = state.get("supply", {})
	var supply_lbls: Array = refs["supply_lbls"] as Array
	for si: int in 6:
		var s_lbl: Label = supply_lbls[si] as Label
		s_lbl.text = str(supply_snap.get(si, 0))

	var vp_lbl: Label = refs["vp_lbl"] as Label
	vp_lbl.text = "⭐ %d" % state.get("vp", 0)

func _refresh_opp_status_label(peer_id: int) -> void:
	var status: String = _opp_statuses.get(peer_id, "") as String
	var is_active: bool = GameNetwork.active_peer_id == peer_id
	if _market_panel:
		_market_panel.update_opponent_status(peer_id, status, is_active)
	var refs: Dictionary = _opp_panels.get(peer_id, {}) as Dictionary
	var lbl: Label = refs.get("status_lbl") as Label
	if not is_instance_valid(lbl):
		return
	if status == "researching":
		lbl.text = "Researching"
		lbl.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
	elif status == "passed":
		lbl.text = "Passed"
		lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	elif is_active:
		lbl.text = "Active"
		lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	else:
		lbl.text = ""
		lbl.remove_theme_color_override("font_color")

func _refresh_all_opp_status_labels() -> void:
	for pid: int in _opp_panels:
		_refresh_opp_status_label(pid)

# Host → All: an opponent's action status changed.
@rpc("authority", "reliable", "call_local")
func _rpc_sync_opp_status(peer_id: int, status: String) -> void:
	_opp_statuses[peer_id] = status
	_refresh_opp_status_label(peer_id)
	var peer_name: String = GameNetwork.player_names.get(peer_id, "Player")
	if status == "passed":
		_log_action("%s: passed" % peer_name, Color(0.55, 0.55, 0.70))
	elif status == "researching":
		_log_action("%s: researching…" % peer_name, Color(0.50, 0.78, 1.0))

# Client → Host: I entered research mode.
@rpc("any_peer", "reliable")
func _rpc_request_research_status() -> void:
	if not multiplayer.is_server():
		return
	_rpc_sync_opp_status.rpc(multiplayer.get_remote_sender_id(), "researching")

# Client → Host: relay my board state to other players.
@rpc("any_peer", "reliable")
func _rpc_send_board_state(state: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_apply_opponent_state(state)
	var sender: int = multiplayer.get_remote_sender_id()
	for peer_id: int in GameNetwork.player_order:
		if peer_id != sender and peer_id != 1 and not GameNetwork.is_bot(peer_id):
			_rpc_recv_board_state.rpc_id(peer_id, state)

# Host → Client: an opponent's board state.
@rpc("authority", "reliable")
func _rpc_recv_board_state(state: Dictionary) -> void:
	_apply_opponent_state(state)

# ── Auction RPCs ──────────────────────────────────────────────────────────────

# Client → Host: I dragged a card that requires a bid.
@rpc("any_peer", "reliable")
func _rpc_request_auction(card_ref: Dictionary, slot_idx: int, is_tech: bool, is_adv: bool, min_bid: int, cost_color_int: int) -> void:
	if not multiplayer.is_server():
		return
	_server_start_auction(card_ref, slot_idx, is_tech, is_adv, min_bid, cost_color_int, multiplayer.get_remote_sender_id())

# Client → Host: I am raising the bid.
@rpc("any_peer", "reliable")
func _rpc_raise_bid(amount: int) -> void:
	if not multiplayer.is_server():
		return
	_server_handle_raise(multiplayer.get_remote_sender_id(), amount)

# Client → Host: I am passing on this bid.
@rpc("any_peer", "reliable")
func _rpc_pass_bid() -> void:
	if not multiplayer.is_server():
		return
	_server_handle_pass_bid(multiplayer.get_remote_sender_id())

# Client → Host: auction winner is forfeiting; offer card to runner-up.
@rpc("any_peer", "reliable")
func _rpc_notify_auction_forfeit() -> void:
	if not multiplayer.is_server():
		return
	var _sender: int = multiplayer.get_remote_sender_id()
	if _sender != _auction_initiator_id and _sender != _auction_leader_id:
		return
	_server_offer_to_runner_up()

# Client → Host: runner-up declined the offer; discard the card.
@rpc("any_peer", "reliable")
func _rpc_notify_runner_up_forfeit(card_ref: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_rpc_sync_market_removal.rpc(card_ref)
	_rpc_sync_runner_up_phase.rpc(false)

# Host → Runner-up: you may claim this card at printed cost.
@rpc("authority", "reliable")
func _rpc_offer_to_runner_up(card_ref: Dictionary, slot_idx: int, is_tech: bool, is_adv: bool, printed_cost: int, cost_color_int: int) -> void:
	_on_runner_up_offer(card_ref, slot_idx, is_tech, is_adv, printed_cost, cost_color_int)

# Host → All: runner-up phase started/ended; block end-turn until resolved.
@rpc("authority", "reliable", "call_local")
func _rpc_sync_runner_up_phase(active: bool) -> void:
	_runner_up_phase = active

# Host → All: auction has started, show bid popup.
@rpc("authority", "reliable", "call_local")
func _rpc_sync_auction_started(card_ref: Dictionary, slot_idx: int, is_tech: bool, is_adv: bool, min_bid: int, cost_color_int: int, initiator_id: int, active_id: int, leader_name: String) -> void:
	_auction_card_ref = card_ref
	_auction_slot_idx = slot_idx
	_auction_is_tech = is_tech
	_auction_is_adv = is_adv
	_auction_cost_color = cost_color_int as CardData.SupplyColor
	_auction_current_bid = min_bid
	_auction_leader_id = initiator_id
	_auction_initiator_id = initiator_id
	var cd: CardData = CardRef.from_ref(card_ref)
	var card_name: String = ""
	if cd:
		card_name = cd.adv_name if (is_adv and not cd.adv_name.is_empty()) else cd.card_name
	var my_id: int = multiplayer.get_unique_id()
	var is_active: bool = my_id == active_id
	var can_pass: bool = is_active and my_id != initiator_id
	if GameNetwork.is_multiplayer and initiator_id != multiplayer.get_unique_id():
		_flash_auction_warning()
	var _initiator_name: String = GameNetwork.player_names.get(initiator_id, "Player")
	_log_action("%s: auction for %s" % [_initiator_name, card_name], Color(1.0, 0.72, 0.28))
	_bid_popup.show_auction(cd, is_adv, min_bid, leader_name, _auction_cost_color, is_active, can_pass)
	_auction_active = true
	_show_action_buttons(false)
	UIAudio.play_auction_music()
	if multiplayer.is_server() and GameNetwork.is_bot(active_id):
		var _ab1: int = active_id
		get_tree().create_timer(0.6).timeout.connect(func() -> void: _bot_decide_bid(_ab1))

# Host → All: bid state has changed.
@rpc("authority", "reliable", "call_local")
func _rpc_sync_auction_state(current_bid: int, leader_id: int, active_id: int, leader_name: String) -> void:
	_auction_current_bid = current_bid
	_auction_leader_id = leader_id
	var my_id: int = multiplayer.get_unique_id()
	var is_active: bool = my_id == active_id
	var can_pass: bool = is_active and my_id != leader_id
	_bid_popup.update_auction(current_bid, leader_name, is_active, can_pass)
	if multiplayer.is_server() and GameNetwork.is_bot(active_id):
		var _ab2: int = active_id
		get_tree().create_timer(0.6).timeout.connect(func() -> void: _bot_decide_bid(_ab2))

# Host → All: auction resolved — winner places the card.
@rpc("authority", "reliable", "call_local")
func _rpc_sync_auction_won(initiator_id: int, winner_id: int, final_bid: int, card_ref: Dictionary, _slot_idx: int, _is_tech: bool, cost_color_int: int) -> void:
	_auction_active = false
	_is_runner_up_offer = false
	_bid_popup.hide()
	UIAudio.stop_auction_music()
	var cost_color: CardData.SupplyColor = cost_color_int as CardData.SupplyColor
	var my_id: int = multiplayer.get_unique_id()
	if my_id == winner_id:
		_pending_auction_win = true
		_auction_win_is_initiator = (my_id == initiator_id)
		if not _auction_win_is_initiator:
			_pending_won_card_ref = card_ref
			_pending_won_is_adv = _auction_is_adv
		var cd: CardData = CardRef.from_ref(card_ref)
		var c_name: String = ""
		if cd:
			c_name = cd.adv_name if (_auction_is_adv and not cd.adv_name.is_empty()) else cd.card_name
		var valid_colors: Array[CardData.SupplyColor] = CardData.valid_payment_colors(cost_color)
		_bid_payment_panel.show_bid_payment(c_name, final_bid, valid_colors, _cs_display, cd, _auction_is_adv)
	else:
		if my_id == initiator_id:
			$Board.cancel_purchase()
		_show_action_buttons(true)
	_update_turn_ui()
	var _cd_toast: CardData = CardRef.from_ref(card_ref)
	var _cn_toast: String = ""
	if _cd_toast:
		_cn_toast = _cd_toast.adv_name if (_auction_is_adv and not _cd_toast.adv_name.is_empty()) else _cd_toast.card_name
	var _wn_toast: String = GameNetwork.player_names.get(winner_id, "Player")
	_show_auction_toast("%s won %s for %d" % [_wn_toast, _cn_toast, final_bid])
	_log_action("%s won %s for %d" % [_wn_toast, _cn_toast, final_bid], Color(1.0, 0.92, 0.35))
	UIAudio.play_gavel_sfx()
	if _bid_is_from_effect:
		_bid_is_from_effect = false
		_process_next_effect()
	_broadcast_my_state()

func _show_auction_toast(message: String) -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.08
	panel.anchor_bottom = 0.08
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = -220.0
	panel.offset_right = 220.0
	panel.offset_top = 0.0
	panel.offset_bottom = 48.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.14, 0.90)
	style.border_color = Color(0.8, 0.7, 0.3, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.text = message
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)
	$UILayer.add_child(panel)
	var tween: Tween = create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(panel, "modulate:a", 0.0, 0.8)
	tween.tween_callback(panel.queue_free)

func _flash_auction_warning() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(1.0, 0.0, 0.0, 0.0)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = 10
	var lbl := Label.new()
	lbl.text = "⚠  AUCTION"
	lbl.add_theme_font_size_override("font_size", 72)
	lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.modulate.a = 0.0
	overlay.add_child(lbl)
	$UILayer.add_child(overlay)
	var t: Tween = create_tween()
	for i: int in 3:
		t.tween_property(overlay, "color:a", 0.35, 0.24)
		if i == 0:
			t.parallel().tween_property(lbl, "modulate:a", 1.0, 0.24)
		t.tween_property(overlay, "color:a", 0.0, 0.30)
		if i == 2:
			t.parallel().tween_property(lbl, "modulate:a", 0.0, 0.30)
	t.tween_callback(overlay.queue_free)

func _show_won_card_popup() -> void:
	if _won_popup:
		_won_popup.queue_free()
		_won_popup = null
	var cd: CardData = CardRef.from_ref(_pending_won_card_ref)
	if not cd:
		return
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_won_popup = root
	$UILayer.add_child(root)

	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(20)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.custom_minimum_size = Vector2(340, 0)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "You won the auction!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	vbox.add_child(title)

	var card_name: String = cd.adv_name if (_pending_won_is_adv and not cd.adv_name.is_empty()) else cd.card_name
	var name_lbl := Label.new()
	name_lbl.text = card_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 16)
	vbox.add_child(name_lbl)

	var image_url: String = cd.adv_image_url if _pending_won_is_adv else cd.image_url
	if not image_url.is_empty():
		var tex: Texture2D = ImageCache.get_texture(image_url)
		if tex:
			var img := TextureRect.new()
			img.texture = tex
			img.custom_minimum_size = Vector2(0, 200)
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			img.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var _place_mat: ShaderMaterial = ShaderMaterial.new()
			_place_mat.shader = load("res://shaders/card_rounded.gdshader")
			img.material = _place_mat
			vbox.add_child(img)

	var hint := Label.new()
	hint.text = "Click below to place the card"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(hint)

	var claim_btn := Button.new()
	claim_btn.text = "Place Card"
	claim_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	claim_btn.add_theme_font_size_override("font_size", 16)
	GameTheme.apply_to_button(claim_btn)
	claim_btn.pressed.connect(func() -> void:
		_pending_won = false
		_won_popup.queue_free()
		_won_popup = null
		var card: CardData = CardRef.from_ref(_pending_won_card_ref)
		if not $Board.begin_auction_win_drag(card):
			push_warning("AuctionWin: card not found in market"))
	vbox.add_child(claim_btn)

func _game_over() -> void:
	_show_action_buttons(false)
	_show_end_turn_button(false)
	_cs_display.show_game_info(false)
	var lines: Array[Dictionary] = $Board.calculate_score()
	var total: int = 0
	for line: Dictionary in lines:
		total += int(line.get("vp", 0))
	if not GameNetwork.is_multiplayer:
		_scoreboard.show_scores(lines, total)
		return
	var my_id: int = multiplayer.get_unique_id()
	var players: Array[Dictionary] = []
	players.append({
		"name": GameNetwork.player_names.get(my_id, "You"),
		"total": total,
		"lines": lines,
	})
	for peer_id: int in GameNetwork.player_order:
		if peer_id == my_id:
			continue
		var snap: Dictionary = _opp_snapshots.get(peer_id, {})
		var peer_lines: Array[Dictionary] = []
		for entry: Variant in snap.get("vp_lines", []):
			peer_lines.append(entry as Dictionary)
		players.append({
			"name": GameNetwork.player_names.get(peer_id, "Player"),
			"total": snap.get("vp", 0),
			"lines": peer_lines,
		})
	players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("total", 0)) > int(b.get("total", 0))
	)
	_scoreboard.show_multiplayer_scores(players)

# ── Card discarded (all modes) ────────────────────────────────────────────────

func _on_card_discarded(card: Node3D) -> void:
	match _effect_mode:
		EffectMode.RESEARCH:
			_effect_mode = EffectMode.NONE
			_hide_effect_hint()
			$Hand.set_discard_mode(false)
			$Board.discard_and_draw(card)
			_has_researched = true
			if not GameNetwork.is_multiplayer:
				_log_action("You: researched", Color(0.50, 0.78, 1.0))
			_broadcast_my_state()
			if GameNetwork.is_multiplayer:
				if GameNetwork.is_host:
					_server_handle_end_turn()
				else:
					_rpc_request_end_turn.rpc_id(1)
			else:
				$Board.set_major_action_taken()
				_show_action_buttons(true)
				_set_action_buttons_disabled(false)

		EffectMode.PAYMENT_RECYCLE:
			_hide_effect_hint()
			UIAudio.play_recycle_sfx()
			var color: CardData.SupplyColor = card.card_data.color if card.card_data else CardData.SupplyColor.DUST
			_cs_display.add_supply(color, 1)
			_apply_recycle_bonus(color)
			$Board.add_to_discard(card.card_data)
			var screen_pos: Vector2 = $Camera3D.unproject_position(card.global_position)
			_cs_display.animate_supply_incoming(screen_pos, color)
			# card freed by fly-out animation in hand.gd


func _recycle_card_to_supply(card: Node3D, color: CardData.SupplyColor) -> void:
	var screen_pos: Vector2 = $Camera3D.unproject_position(card.global_position)
	_cs_display.animate_supply_incoming(screen_pos, color)
	$Hand.remove_card_fly_out(card)

func _on_card_right_clicked_free_recycle(card: Node3D) -> void:
	if _effect_mode != EffectMode.NONE:
		return
	if not GameNetwork.is_my_turn():
		return
	$Board.request_recycle(card)

func _on_recycle_confirm_required(card: Node3D, color: CardData.SupplyColor) -> void:
	var tc_count: int = $Board.count_tech_by_name("Trash Compactor") if color == CardData.SupplyColor.DUST else 0
	if _recycle_panel:
		_recycle_panel.call("show_recycle", card.card_data if card.card_data else null, color, tc_count)

func _on_recycle_panel_confirmed() -> void:
	$Board.confirm_recycle()

func _on_recycle_panel_cancelled() -> void:
	$Board.cancel_recycle()


func _gather_hand_source() -> Array[CardData]:
	var all_cards: Array[Node3D] = $Hand.get_cards()
	var source: Array[Node3D]
	if _restrict_picks_to_drawn and not _last_drawn_cards.is_empty():
		source = _last_drawn_cards.filter(func(c: Node3D) -> bool: return all_cards.has(c))
	else:
		source = all_cards
	_pending_recycle_cards = []
	var card_data: Array[CardData] = []
	for c: Node3D in source:
		var cd: CardData = c.get("card_data") as CardData
		if cd:
			_pending_recycle_cards.append(c)
			card_data.append(cd)
	return card_data

func _show_hand_popup(prompt: String, skippable: bool) -> void:
	var card_data: Array[CardData] = _gather_hand_source()
	if card_data.is_empty():
		_finish_interactive_step()
		return
	_choice_popup.show_card_choices(prompt, card_data, skippable)

func _show_hand_multiselect(prompt: String) -> void:
	var card_data: Array[CardData] = _gather_hand_source()
	if card_data.is_empty():
		_finish_interactive_step()
		return
	_choice_popup.show_multiselect_card_choices(prompt, card_data, _effect_remaining)

func _process_hand_choice(index: int) -> void:
	if index >= _pending_recycle_cards.size():
		_pending_recycle_cards = []
		_finish_interactive_step()
		return
	var card: Node3D = _pending_recycle_cards[index]
	_pending_recycle_cards = []

	match _effect_mode:
		EffectMode.EFFECT_RECYCLE:
			var color: CardData.SupplyColor = card.card_data.color if card.card_data else CardData.SupplyColor.DUST
			_cs_display.add_supply(color, 1)
			_apply_recycle_bonus(color)
			$Board.add_to_discard(card.card_data)
			_recycle_card_to_supply(card, color)
			_effect_remaining -= 1
			if _effect_remaining <= 0:
				_finish_interactive_step()
			else:
				_show_hand_popup("Recycle %d more card(s)" % _effect_remaining, false)

		EffectMode.EFFECT_RECYCLE_OPTIONAL:
			var color: CardData.SupplyColor = card.card_data.color if card.card_data else CardData.SupplyColor.DUST
			_cs_display.add_supply(color, 1)
			_apply_recycle_bonus(color)
			$Board.add_to_discard(card.card_data)
			_recycle_card_to_supply(card, color)
			$Board.draw_cards(1)
			_effect_remaining -= 1
			if _effect_remaining <= 0:
				_finish_interactive_step()
			else:
				_show_hand_popup("Recycle up to %d more card(s)" % _effect_remaining, true)

		EffectMode.EFFECT_TUCK:
			if _effect_slot and card.card_data:
				_effect_slot.add_tucked_card(card.card_data, _effect_face_up)
			$Hand.remove_card_fly_out(card)
			_effect_remaining -= 1
			if _effect_remaining <= 0:
				_finish_interactive_step()
			else:
				var face_str: String = "faceup" if _effect_face_up else "facedown"
				_show_hand_popup("Tuck %d more card(s) %s" % [_effect_remaining, face_str], false)

		EffectMode.EFFECT_TUCK_OPTIONAL:
			if _effect_slot and card.card_data:
				_effect_slot.add_tucked_card(card.card_data, _effect_face_up)
			$Hand.remove_card_fly_out(card)
			$Board.draw_cards(1)
			_effect_remaining -= 1
			if _effect_remaining <= 0:
				_finish_interactive_step()
			else:
				var face_str: String = "faceup" if _effect_face_up else "facedown"
				_show_hand_popup("Tuck up to %d more card(s) %s" % [_effect_remaining, face_str], true)

		EffectMode.EFFECT_TUCK_ANY_SECTOR:
			_pending_tuck_card_data = card.card_data
			$Hand.remove_card_fly_out(card)
			_effect_mode = EffectMode.EFFECT_TUCK_ANY_SECTOR_SLOT
			$Board.set_cargo_click_mode(true)
			var face_str_tuck: String = "faceup" if _effect_face_up else "facedown"
			var tuck_name: String = card.card_data.card_name if card.card_data else "card"
			_sector_picker.setup("Tuck %s %s — pick a sector" % [tuck_name, face_str_tuck], $Board.get_all_sector_slots())

		EffectMode.EFFECT_RECYCLE_TUCK:
			var color: CardData.SupplyColor = card.card_data.color if card.card_data else CardData.SupplyColor.DUST
			_cs_display.add_supply(color, 1)
			_apply_recycle_bonus(color)
			if _effect_slot and card.card_data:
				_effect_slot.add_tucked_card(card.card_data, false)
			_recycle_card_to_supply(card, color)
			_effect_remaining -= 1
			if _effect_remaining <= 0:
				$Board.draw_cards(int(_effect_slot.tucked_cards.size()) if _effect_slot else 0)
				_finish_interactive_step()
			else:
				_show_hand_popup("Recycle & tuck %d more card(s) facedown" % _effect_remaining, false)

		EffectMode.EFFECT_RECYCLE_DOUBLE:
			var color: CardData.SupplyColor = card.card_data.color if card.card_data else CardData.SupplyColor.DUST
			_cs_display.add_supply(color, 2)
			_apply_recycle_bonus(color)
			$Board.add_to_discard(card.card_data)
			_recycle_card_to_supply(card, color)
			_effect_remaining -= 1
			if _effect_remaining <= 0:
				_finish_interactive_step()
			else:
				_show_hand_popup("Recycle %d more card(s) — gain double supply" % _effect_remaining, false)

func _reset_effect_state() -> void:
	_effect_mode = EffectMode.NONE
	$Board.set_cards_can_elevate(true)
	_effect_remaining = 0
	_pending_choice_options = []
	_reveal_bid_pool.clear()
	_reveal_free_pool.clear()
	_bid_is_from_effect = false
	_shuffle_count = 0
	_pending_recycle_cards = []
	_pending_store_nodes = []
	_last_drawn_cards = []
	_restrict_picks_to_drawn = false
	_pending_tuck_card_data = null
	_pending_target_slot = null
	_effect_label = ""
	_cargo_source_slot = null
	_cargo_pending_supplies = {}
	_cargo_pending_tucked = []
	_caldera_slots = []
	_effect_done_btn.hide()
	_choice_popup.hide()
	_hide_effect_hint()
	$Hand.set_discard_mode(false)
	$Board.set_sector_reveal_mode(false)
	$Board.set_expedition_reveal_mode(false)
	$Board.set_expedition_shuffle_mode(false)
	$Board.set_cargo_click_mode(false)
	_market_panel.set_sector_reveal_mode(false)
	_market_panel.set_expedition_reveal_mode(false)

func _finish_interactive_step() -> void:
	_reset_effect_state()
	_process_next_effect()

func _on_effect_done_pressed() -> void:
	if _effect_mode == EffectMode.EFFECT_EXPEDITION_SHUFFLE:
		_finish_expedition_shuffle()
	else:
		_finish_interactive_step()

func _on_choice_made(index: int) -> void:
	if _effect_mode == EffectMode.EFFECT_RECYCLE_TUCK_STORE_DECIDE:
		_apply_recycle_tuck_store_decision(index == 0)
		return
	if not _pending_recycle_cards.is_empty():
		_process_hand_choice(index)
		return
	if _effect_mode == EffectMode.EFFECT_CALDERA_SELECT_SECTOR:
		_on_caldera_sector_chosen(index)
		return
	if index < _pending_choice_options.size():
		var chosen_steps: Array = _pending_choice_options[index].get("steps", [])
		for i: int in chosen_steps.size():
			_effect_queue.insert(i, chosen_steps[i])
	_pending_choice_options = []
	_effect_mode = EffectMode.NONE
	_process_next_effect()

func _on_multiselect_confirmed(indices: Array[int]) -> void:
	match _effect_mode:
		EffectMode.EFFECT_SEEDBANKS:
			_apply_seedbanks(indices)
		EffectMode.EFFECT_CALDERA_SELECT_CARDS:
			_apply_caldera_recycle(indices)
		EffectMode.EFFECT_RECYCLE_OPTIONAL:
			_apply_recycle_optional_multiselect(indices)
		EffectMode.EFFECT_TUCK_OPTIONAL:
			_apply_tuck_optional_multiselect(indices)
		EffectMode.EFFECT_RECYCLE_TUCK:
			_apply_recycle_tuck_multiselect(indices)
		EffectMode.EFFECT_RECYCLE_TUCK_STORE:
			_apply_recycle_tuck_store_multiselect(indices)

func _apply_seedbanks(indices: Array[int]) -> void:
	for i: int in indices:
		if i >= _pending_recycle_cards.size():
			continue
		var card: Node3D = _pending_recycle_cards[i]
		var color: CardData.SupplyColor = card.card_data.color if card.card_data else CardData.SupplyColor.DUST
		if _effect_slot:
			_effect_slot.add_stored_supply(color, 1)
		$Hand.remove_card_fly_out(card)
	_pending_recycle_cards = []
	_finish_interactive_step()

func _apply_recycle_optional_multiselect(indices: Array[int]) -> void:
	var count: int = 0
	for i: int in indices:
		if i >= _pending_recycle_cards.size():
			continue
		var card: Node3D = _pending_recycle_cards[i]
		var color: CardData.SupplyColor = card.card_data.color if card.card_data else CardData.SupplyColor.DUST
		_cs_display.add_supply(color, 1)
		_apply_recycle_bonus(color)
		$Board.add_to_discard(card.card_data)
		_recycle_card_to_supply(card, color)
		count += 1
	_pending_recycle_cards = []
	if count > 0:
		$Board.draw_cards(count)
	_finish_interactive_step()

func _apply_tuck_optional_multiselect(indices: Array[int]) -> void:
	var count: int = 0
	for i: int in indices:
		if i >= _pending_recycle_cards.size():
			continue
		var card: Node3D = _pending_recycle_cards[i]
		if _effect_slot and card.card_data:
			_effect_slot.add_tucked_card(card.card_data, _effect_face_up)
		$Hand.remove_card_fly_out(card)
		count += 1
	_pending_recycle_cards = []
	if count > 0 and not _restrict_picks_to_drawn:
			$Board.draw_cards(count)
	_finish_interactive_step()

func _apply_recycle_tuck_multiselect(indices: Array[int]) -> void:
	var count: int = 0
	for i: int in indices:
		if i >= _pending_recycle_cards.size():
			continue
		var card: Node3D = _pending_recycle_cards[i]
		var color: CardData.SupplyColor = card.card_data.color if card.card_data else CardData.SupplyColor.DUST
		_cs_display.add_supply(color, 1)
		_apply_recycle_bonus(color)
		if _effect_slot and card.card_data:
			_effect_slot.add_tucked_card(card.card_data, false)
		_recycle_card_to_supply(card, color)
		count += 1
	_pending_recycle_cards = []
	if count > 0:
			$Board.draw_cards(count)
	_finish_interactive_step()

func _apply_recycle_tuck_store_multiselect(indices: Array[int]) -> void:
	_pending_store_nodes = []
	for i: int in indices:
		if i < _pending_recycle_cards.size():
			_pending_store_nodes.append(_pending_recycle_cards[i])
	_pending_recycle_cards = []
	if _pending_store_nodes.is_empty():
		_finish_interactive_step()
		return
	_effect_mode = EffectMode.EFFECT_RECYCLE_TUCK_STORE_SECTOR
	$Board.set_cargo_click_mode(true)
	_sector_picker.setup("Terraformed Planet — pick a sector to tuck facedown", $Board.get_all_sector_slots())

func _apply_recycle_tuck_store_decision(store_on_sector: bool) -> void:
	var target: SectorSlot = _pending_target_slot if _pending_target_slot else _effect_slot
	for card: Node3D in _pending_store_nodes:
		var color: CardData.SupplyColor = card.card_data.color if card.card_data else CardData.SupplyColor.DUST
		var screen_pos: Vector2 = $Camera3D.unproject_position(card.global_position)
		if store_on_sector and target:
			target.add_stored_supply(color, 1)
		else:
			_cs_display.animate_supply_incoming(screen_pos, color)
			_cs_display.add_supply(color, 1)
			_apply_recycle_bonus(color)
		if target and card.card_data:
			target.add_tucked_card(card.card_data, false)
		$Hand.remove_card_fly_out(card)
	_pending_store_nodes = []
	_finish_interactive_step()

func _on_caldera_sector_chosen(index: int) -> void:
	if index >= _caldera_slots.size():
		_finish_interactive_step()
		return
	_pending_target_slot = _caldera_slots[index]
	_pending_recycle_cards = []
	var eligible_cards: Array[CardData] = []
	for card: Node3D in _pending_target_slot.get_all_placed_cards():
		var cd: CardData = card.get("card_data") as CardData
		if cd and (cd.card_type == CardData.CardType.TECH or cd.card_type == CardData.CardType.EXPEDITION):
			_pending_recycle_cards.append(card)
			eligible_cards.append(cd)
	if eligible_cards.is_empty():
		_pending_target_slot = null
		_finish_interactive_step()
		return
	_effect_mode = EffectMode.EFFECT_CALDERA_SELECT_CARDS
	_choice_popup.show_multiselect_card_choices(
		"Caldera Colony — select cards to recycle (supply stored on sector):", eligible_cards)

func _apply_caldera_recycle(indices: Array[int]) -> void:
	if not _pending_target_slot:
		_pending_recycle_cards = []
		_finish_interactive_step()
		return
	for i: int in indices:
		if i >= _pending_recycle_cards.size():
			continue
		var card: Node3D = _pending_recycle_cards[i]
		var cd: CardData = card.get("card_data") as CardData
		if cd:
			_pending_target_slot.add_stored_supply(cd.color, 1)
		_pending_target_slot.remove_tech_card(card)
		card.queue_free()
	_pending_recycle_cards = []
	_pending_target_slot.compact_tech_cards()
	_pending_target_slot.refresh_display()
	_pending_target_slot = null
	_finish_interactive_step()

func _on_choice_skipped() -> void:
	_pending_recycle_cards = []
	_pending_choice_options = []
	if _effect_mode != EffectMode.NONE:
		_finish_interactive_step()
	else:
		_process_next_effect()

func _on_sector_selected_from_picker(slot: SectorSlot) -> void:
	_on_sector_info_requested(slot)

func _on_sector_picker_skipped() -> void:
	$Board.set_cargo_click_mode(false)
	_finish_interactive_step()


func _on_sector_info_requested(slot: SectorSlot) -> void:
	match _effect_mode:
		EffectMode.EFFECT_CARGO_DRONES:
			_sector_info_popup.show_sector_for_cargo(slot)
			_sector_picker.hide()
		EffectMode.EFFECT_CARGO_DRONES_DEST:
			if slot != _cargo_source_slot and slot.occupied:
				_sector_picker.hide()
				_apply_cargo_move(slot)
		EffectMode.EFFECT_STORE_ON_SECTOR:
			if slot.occupied:
				_sector_picker.hide()
				slot.add_stored_supply(_pending_store_color, _pending_store_amount)
				_finish_interactive_step()
		EffectMode.EFFECT_RECYCLE_TUCK_STORE_SECTOR:
			if slot.occupied:
				_sector_picker.hide()
				_pending_target_slot = slot
				$Board.set_cargo_click_mode(false)
				_hide_effect_hint()
				_effect_mode = EffectMode.EFFECT_RECYCLE_TUCK_STORE_DECIDE
				var labels: Array[String] = ["Store on sector", "Gain as currency"]
				_choice_popup.show_choices("Terraformed Planet — what to do with recycled supply?", labels, false)
		EffectMode.EFFECT_TUCK_ANY_SECTOR_SLOT:
			if slot.occupied:
				_sector_picker.hide()
				if _pending_tuck_card_data:
					slot.add_tucked_card(_pending_tuck_card_data, _effect_face_up)
				_pending_tuck_card_data = null
				$Board.set_cargo_click_mode(false)
				_hide_effect_hint()
				_effect_remaining -= 1
				if _effect_remaining > 0:
					_effect_mode = EffectMode.EFFECT_TUCK_ANY_SECTOR
					var face_str_slot: String = "faceup" if _effect_face_up else "facedown"
					_show_hand_popup("%s — tuck a card %s? (%d remaining)" % [_effect_label, face_str_slot, _effect_remaining], true)
				else:
					_finish_interactive_step()
		_:
			_sector_info_popup.show_sector(slot)

func _on_cargo_move_requested(source: SectorSlot, supplies: Dictionary, tucked_indices: Array[int]) -> void:
	if supplies.is_empty() and tucked_indices.is_empty():
		return
	_cargo_source_slot = source
	_cargo_pending_supplies = supplies
	_cargo_pending_tucked = tucked_indices
	_effect_mode = EffectMode.EFFECT_CARGO_DRONES_DEST
	_sector_picker.setup("Cargo Drones — pick the destination sector", $Board.get_all_sector_slots(), _cargo_source_slot)

func _on_cargo_cancelled() -> void:
	_effect_mode = EffectMode.EFFECT_CARGO_DRONES
	_sector_picker.setup("Cargo Drones — pick a source sector", $Board.get_all_sector_slots())

func _apply_cargo_move(dest: SectorSlot) -> void:
	for color: int in _cargo_pending_supplies:
		var amount: int = _cargo_pending_supplies[color]
		var cur: int = _cargo_source_slot.stored_supply.get(color, 0)
		var remaining: int = cur - amount
		if remaining <= 0:
			_cargo_source_slot.stored_supply.erase(color)
		else:
			_cargo_source_slot.stored_supply[color] = remaining
		dest.add_stored_supply(color as CardData.SupplyColor, amount)
	_cargo_source_slot.refresh_display()
	var sorted_tucked: Array[int] = _cargo_pending_tucked.duplicate()
	sorted_tucked.sort()
	sorted_tucked.reverse()
	for idx: int in sorted_tucked:
		if idx < _cargo_source_slot.tucked_cards.size():
			var entry: Dictionary = _cargo_source_slot.tucked_cards[idx]
			_cargo_source_slot.tucked_cards.remove_at(idx)
			dest.tucked_cards.append(entry)
	_cargo_source_slot.refresh_display()
	dest.refresh_display()
	_cargo_source_slot = null
	_cargo_pending_supplies = {}
	_cargo_pending_tucked = []
	_effect_mode = EffectMode.EFFECT_CARGO_DRONES
	_sector_picker.setup("Cargo Drones — pick a source sector", $Board.get_all_sector_slots())

func _on_sector_revealed(card_data: CardData, slot_idx: int) -> void:
	if GameNetwork.is_multiplayer:
		if GameNetwork.is_host:
			_server_sync_sector_reveal(slot_idx, 1)
		else:
			_rpc_notify_sector_revealed.rpc_id(1, slot_idx)
	_hide_effect_hint()
	_effect_mode = EffectMode.NONE
	$Board.set_sector_reveal_mode(false)
	_market_panel.set_sector_reveal_mode(false)
	if _pending_reveal_gain_supply and card_data:
		_cs_display.add_supply(card_data.adv_color, 1)
	if _pending_reveal_may_bid and card_data:
		_reveal_bid_pool.append(card_data)
	if _pending_reveal_may_free_gain and card_data:
		_reveal_free_pool.append(card_data)
	_pending_reveal_gain_supply = false
	_pending_reveal_may_bid = false
	_pending_reveal_may_free_gain = false
	_process_next_effect()

# ── Place effect processing ───────────────────────────────────────────────────

func _on_card_placed(card: Node3D, slot: SectorSlot) -> void:
	if not card.card_data:
		return
	var _cd: CardData = card.card_data
	var _is_adv: bool = bool(card.get("is_advanced"))
	var _cname: String = _cd.adv_name if _is_adv and not _cd.adv_name.is_empty() else _cd.card_name
	var _pname: String = GameNetwork.player_names.get(multiplayer.get_unique_id(), "You")
	var _supply: CardData.SupplyColor = _cd.adv_color if _is_adv else _cd.color
	_broadcast_log("%s: placed %s" % [_pname, _cname], CardData.color_tint(_supply))
	UIAudio.play_supply_sfx(_supply)
	$Board.refresh_discount_glow()
	if _effect_mode != EffectMode.NONE:
		_reset_effect_state()
	_effect_slot = slot
	_effect_queue.clear()

	var always_steps: Array[Dictionary] = []
	always_steps.append_array(AlwaysEffects.get_colocated_steps(card.card_data, slot))
	always_steps.append_array(AlwaysEffects.get_board_wide_placement_steps(card, $Board.get_all_sector_slots()))
	always_steps.append_array(AlwaysEffects.get_board_wide_steps(slot, $Board.get_all_sector_slots()))
	always_steps.append_array(AlwaysEffects.get_global_expedition_steps(card.card_data, $Board.get_all_placed_expeditions()))
	var place_steps: Array[Dictionary] = PlaceEffects.get_steps(card.card_data, slot)

	if _defer_place_effects:
		_defer_place_effects = false
		_deferred_effect_slot = slot
		_deferred_effect_queue.clear()
		_deferred_effect_queue.append_array(always_steps)
		_deferred_effect_queue.append_array(place_steps)
		_effect_slot = null
		_effect_queue.clear()
		return

	if not always_steps.is_empty() and not place_steps.is_empty():
		var cd: CardData = card.card_data
		var card_name: String = cd.adv_name if bool(card.get("is_advanced")) and not cd.adv_name.is_empty() else cd.card_name
		var always_first: Array = []; always_first.append_array(always_steps); always_first.append_array(place_steps)
		var card_first: Array = []; card_first.append_array(place_steps); card_first.append_array(always_steps)
		_pending_choice_options = [
			{steps = always_first},
			{steps = card_first},
		]
		_effect_mode = EffectMode.EFFECT_CHOICE
		_choice_popup.show_choices("Two effects triggered — resolve which first?", ["Sector effects", card_name], false)
		return

	_effect_queue.append_array(always_steps)
	_effect_queue.append_array(place_steps)
	_process_next_effect()

func _process_next_effect() -> void:
	if _effect_queue.is_empty():
		_effect_slot = null
		_refresh_vp()
		$Board.set_cards_can_elevate(true)
		_try_auto_end_turn()
		return
	$Board.set_cards_can_elevate(false)
	var step: Dictionary = _effect_queue.pop_front()
	_execute_effect_step(step)

func _execute_effect_step(step: Dictionary) -> void:
	match step.get("type", ""):

		"draw":
			var _before: Array[Node3D] = $Hand.get_cards()
			$Board.draw_cards(int(step.get("count", 0)))
			var _after: Array[Node3D] = $Hand.get_cards()
			_last_drawn_cards = _after.filter(func(c: Node3D) -> bool: return not _before.has(c))
			_process_next_effect()

		"draw_recycle_top":
			$Board.draw_and_recycle_top()
			_process_next_effect()

		"gain_supply":
			_cs_display.add_supply(step["color"] as CardData.SupplyColor, int(step.get("amount", 0)))
			_process_next_effect()

		"store_on_slot":
			if _effect_slot:
				_effect_slot.add_stored_supply(step["color"] as CardData.SupplyColor, int(step.get("amount", 0)))
			_process_next_effect()

		"store_on_any_sector":
			_pending_store_color = step["color"] as CardData.SupplyColor
			_pending_store_amount = int(step.get("amount", 1))
			_effect_mode = EffectMode.EFFECT_STORE_ON_SECTOR
			$Board.set_cargo_click_mode(true)
			var color_names: Array[String] = ["Dust", "Metals", "Liquids", "Organix", "Electrix", "Thrust"]
			_sector_picker.setup("Store %d %s — pick a sector" % [_pending_store_amount, color_names[_pending_store_color]], $Board.get_all_sector_slots())

		"store_per_card_here":
			if _effect_slot:
				for c: Node3D in _effect_slot.get_all_placed_cards():
					var cd: CardData = c.get("card_data")
					if cd:
						_effect_slot.add_stored_supply(cd.color, 1)
			_process_next_effect()

		"gain_supply_per_stored":
			if _effect_slot:
				var color: CardData.SupplyColor = step["color"] as CardData.SupplyColor
				var mult: int = int(step.get("multiplier", 1))
				var stored: int = _effect_slot.get_stored_supply(color)
				_cs_display.add_supply(color, stored * mult)
			_process_next_effect()

		"gain_supply_per_sector_count":
			var color: CardData.SupplyColor = step["color"] as CardData.SupplyColor
			var count: int
			if step.has("sector_color_filter"):
				count = $Board.get_sector_count_by_color(step["sector_color_filter"] as CardData.SupplyColor)
			else:
				count = $Board.get_sector_count()
			_cs_display.add_supply(color, count)
			_process_next_effect()

		"fuse_notice":
			var count: int = int(step.get("count", 0))
			_cs_display.add_fuse_1to1(count)
			_process_next_effect()

		"fuse_dust_1to1":
			_cs_display.set_dust_fuse_1to1(true)
			_process_next_effect()

		"recycle":
			_effect_mode = EffectMode.EFFECT_RECYCLE
			_effect_remaining = int(step.get("count", 1))
			_restrict_picks_to_drawn = bool(step.get("restrict_to_drawn", false))
			_show_hand_popup("Recycle %d card(s) from your hand" % _effect_remaining, false)

		"recycle_optional":
			_effect_mode = EffectMode.EFFECT_RECYCLE_OPTIONAL
			_effect_remaining = int(step.get("max", 1))
			_restrict_picks_to_drawn = bool(step.get("restrict_to_drawn", false))
			_show_hand_multiselect("Recycle up to %d card(s) — draw 1 per recycled" % _effect_remaining)

		"recycle_double":
			_effect_mode = EffectMode.EFFECT_RECYCLE_DOUBLE
			_effect_remaining = int(step.get("count", 1))
			_restrict_picks_to_drawn = bool(step.get("restrict_to_drawn", false))
			_show_hand_popup("Recycle %d card(s) — gain double supply" % _effect_remaining, false)

		"tuck":
			_effect_mode = EffectMode.EFFECT_TUCK
			_effect_remaining = int(step.get("count", 1))
			_effect_face_up = bool(step.get("face_up", false))
			_restrict_picks_to_drawn = bool(step.get("restrict_to_drawn", false))
			var face_str_t: String = "faceup" if _effect_face_up else "facedown"
			_show_hand_popup("Tuck %d card(s) %s under this sector" % [_effect_remaining, face_str_t], false)

		"tuck_optional":
			_effect_mode = EffectMode.EFFECT_TUCK_OPTIONAL
			_effect_remaining = int(step.get("max", 1))
			_effect_face_up = bool(step.get("face_up", false))
			_restrict_picks_to_drawn = bool(step.get("restrict_to_drawn", false))
			var face_str_to: String = "faceup" if _effect_face_up else "facedown"
			var prompt_to: String
			if _restrict_picks_to_drawn:
				prompt_to = "Tuck up to %d of the drawn cards %s" % [_effect_remaining, face_str_to]
			else:
				prompt_to = "Tuck up to %d card(s) %s — draw 1 per tucked" % [_effect_remaining, face_str_to]
			_show_hand_multiselect(prompt_to)

		"tuck_any_sector_optional":
			_effect_mode = EffectMode.EFFECT_TUCK_ANY_SECTOR
			_effect_remaining = int(step.get("max", 1))
			_effect_face_up = bool(step.get("face_up", false))
			_effect_label = step.get("label", "Tuck")
			var face_str_any: String = "faceup" if _effect_face_up else "facedown"
			_show_hand_popup("%s — tuck a card %s? (%d remaining)" % [_effect_label, face_str_any, _effect_remaining], true)

		"recycle_tuck":
			_effect_mode = EffectMode.EFFECT_RECYCLE_TUCK
			_effect_remaining = int(step.get("count", 2))
			_show_hand_multiselect("Recycle & tuck up to %d card(s) facedown — draw equal" % _effect_remaining)

		"recycle_tuck_store_choice":
			_effect_mode = EffectMode.EFFECT_RECYCLE_TUCK_STORE
			_effect_remaining = int(step.get("max", 4))
			_show_hand_multiselect("Recycle & tuck up to %d card(s) facedown — choose store or gain" % _effect_remaining)

		"reveal_sector":
			_pending_reveal_gain_supply = bool(step.get("gain_supply", false))
			_pending_reveal_may_bid = bool(step.get("may_bid", false))
			_pending_reveal_may_free_gain = bool(step.get("may_free_gain", false))
			_effect_mode = EffectMode.EFFECT_REVEAL_SECTOR
			_show_effect_hint("Click a free sector slot in the Market panel to reveal it")
			$Board.set_sector_reveal_mode(true)
			_market_panel.set_sector_reveal_mode(true)

		"reveal_expedition":
			_pending_expedition_reveal_gain_supply = bool(step.get("gain_supply", false))
			_pending_expedition_reveal_may_bid = bool(step.get("may_bid", false))
			_effect_mode = EffectMode.EFFECT_REVEAL_EXPEDITION
			_show_effect_hint("Click an expedition slot in the Market panel to reveal it")
			$Board.set_expedition_reveal_mode(true)
			_market_panel.set_expedition_reveal_mode(true)

		"reveal_expedition_slot":
			var exp_slot: int = int(step.get("slot", 0))
			var revealed: CardData = $Board.reveal_expedition_to_slot(exp_slot)
			if bool(step.get("gain_supply", false)) and revealed:
				_cs_display.add_supply(revealed.color, 1)
			if bool(step.get("may_bid", false)) and revealed:
				_reveal_bid_pool.append(revealed)
			if GameNetwork.is_multiplayer:
				if GameNetwork.is_host:
					_rpc_sync_expedition_reveal.rpc(exp_slot)
				else:
					_rpc_notify_expedition_reveal.rpc_id(1, exp_slot)
			_process_next_effect()

		"choice":
			_effect_mode = EffectMode.EFFECT_CHOICE
			_pending_choice_options = step.get("options", [])
			var labels: Array[String] = []
			var tints: Array[Color] = []
			for opt: Dictionary in _pending_choice_options:
				labels.append(str(opt.get("label", "?")))
				if opt.has("tint"):
					tints.append(opt["tint"] as Color)
			var choice_cd: CardData = null
			var choice_is_adv: bool = false
			if _effect_slot and is_instance_valid(_effect_slot) and _effect_slot.placed_card:
				choice_cd = _effect_slot.placed_card.card_data
				choice_is_adv = bool(_effect_slot.placed_card.get("is_advanced"))
			_choice_popup.show_choices(
				str(step.get("prompt", "Choose:")),
				labels,
				bool(step.get("skippable", false)),
				tints,
				choice_cd,
				choice_is_adv
			)

		"reflectors_choice":
			if not _effect_slot:
				_process_next_effect()
				return
			var eligible_cards: Array[CardData] = []
			var eligible_steps: Array = []
			for card_node: Node3D in _effect_slot.get_all_placed_cards():
				var cd: CardData = card_node.get("card_data")
				if not cd or cd.card_type != CardData.CardType.TECH or cd.card_name == "Reflectors":
					continue
				var copied: Array[Dictionary] = PlaceEffects.get_steps(cd, _effect_slot)
				if copied.is_empty():
					continue
				eligible_cards.append(cd)
				eligible_steps.append(copied)
			if eligible_cards.is_empty():
				_process_next_effect()
				return
			_pending_choice_options = []
			for i: int in eligible_cards.size():
				_pending_choice_options.append({steps = eligible_steps[i]})
			_effect_mode = EffectMode.EFFECT_CHOICE
			_choice_popup.show_card_choices("Reflectors — copy which effect?", eligible_cards, true)

		"offer_bid_pool":
			if _reveal_bid_pool.is_empty():
				_process_next_effect()
				return
			var pool: Array[CardData] = _reveal_bid_pool.duplicate()
			_reveal_bid_pool.clear()
			_pending_choice_options = []
			for cd: CardData in pool:
				_pending_choice_options.append({steps = [{type = "initiate_market_bid", card_data = cd}]})
			_effect_mode = EffectMode.EFFECT_CHOICE
			_choice_popup.show_card_choices("Bid on a revealed card?", pool, true)

		"offer_free_sector_gain":
			var eligible: Array[CardData] = []
			var eligible_adv: Array[bool] = []
			for cd: CardData in _reveal_free_pool:
				if cd.adv_color == CardData.SupplyColor.DUST or cd.adv_color == CardData.SupplyColor.LIQUIDS:
					eligible.append(cd)
					eligible_adv.append(true)
			_reveal_free_pool.clear()
			for cd: CardData in $Board.get_available_dust_sectors():
				if not eligible.has(cd):
					eligible.append(cd)
					eligible_adv.append(false)
			if eligible.is_empty():
				_process_next_effect()
				return
			_pending_choice_options = []
			for cd: CardData in eligible:
				_pending_choice_options.append({steps = [{type = "free_sector_gain", card_data = cd}]})
			_effect_mode = EffectMode.EFFECT_CHOICE
			_choice_popup.show_card_choices("Inflatable Hull — gain which sector for free?", eligible, false, eligible_adv)

		"free_sector_gain":
			var cd: CardData = step.get("card_data") as CardData
			if not cd:
				_process_next_effect()
				return
			var card_node: Node3D = $Board.find_market_card(cd)
			if not card_node:
				_process_next_effect()
				return
			$Board.market_origin_3d = _effect_card_origin(card_node, cd)
			$Board.begin_free_sector_gain(card_node)

		"initiate_market_bid":
			var cd: CardData = step.get("card_data") as CardData
			if not cd:
				_process_next_effect()
				return
			var card_node: Node3D = $Board.find_market_card(cd)
			if not card_node:
				_process_next_effect()
				return
			_bid_is_from_effect = true
			$Board.market_origin_3d = _effect_card_origin(card_node, cd)
			$Board.begin_drag_card(card_node)

		"seedbanks":
			_effect_mode = EffectMode.EFFECT_SEEDBANKS
			var all_cards: Array[Node3D] = $Hand.get_cards()
			_pending_recycle_cards = []
			var card_data: Array[CardData] = []
			for c: Node3D in all_cards:
				var cd: CardData = c.get("card_data") as CardData
				if cd:
					_pending_recycle_cards.append(c)
					card_data.append(cd)
			if card_data.is_empty():
				_finish_interactive_step()
			else:
				_choice_popup.show_multiselect_card_choices(
					"Seedbanks — select cards to recycle (supplies stored on sector)", card_data)

		"caldera_colony":
			_caldera_slots = []
			var caldera_cards: Array[CardData] = []
			for slot: SectorSlot in $Board.get_all_sector_slots():
				if not slot.occupied or not slot.placed_card or not slot.placed_card.card_data:
					continue
				_caldera_slots.append(slot)
				caldera_cards.append(slot.placed_card.card_data as CardData)
			if caldera_cards.is_empty():
				_finish_interactive_step()
				return
			_effect_mode = EffectMode.EFFECT_CALDERA_SELECT_SECTOR
			_choice_popup.show_card_choices("Caldera Colony — choose a sector:", caldera_cards, true)

		"cargo_drones":
			_effect_mode = EffectMode.EFFECT_CARGO_DRONES
			$Board.set_cargo_click_mode(true)
			_sector_picker.setup("Cargo Drones — pick a source sector", $Board.get_all_sector_slots())

		"black_hole_encounter":
			_effect_mode = EffectMode.EFFECT_EXPEDITION_SHUFFLE
			_effect_remaining = 3
			_shuffle_count = 0
			_show_effect_hint("Click up to 3 expeditions to shuffle back — then click Done")
			_effect_done_btn.show()
			$Board.set_expedition_shuffle_mode(true)
			_market_panel.set_expedition_shuffle_mode(true)

		_:
			_process_next_effect()

# ── Bid / payment flow ────────────────────────────────────────────────────────

func _on_bid_required(card: Node3D, slot: Node3D, min_cost: int, cost_color: CardData.SupplyColor, is_tech: bool) -> void:
	_show_action_buttons(false)
	_bid_color = cost_color
	_bid_card_data = card.card_data
	_bid_is_advanced = card.is_advanced
	_bid_card_name = card.card_data.adv_name if card.is_advanced else card.card_data.card_name
	var effective_min: int = max(0, min_cost - $Board.get_purchase_discount(card.card_data, slot as SectorSlot))
	if not GameNetwork.is_multiplayer:
		_bid_popup.show_bid(card.card_data, card.is_advanced, effective_min, cost_color)
		return
	_pending_auction_card_ref = CardRef.to_ref(card.card_data)
	_pending_auction_slot_idx = $Board.get_slot_index(slot as SectorSlot)
	_pending_auction_is_tech = is_tech
	_pending_auction_is_adv = card.is_advanced
	_pending_auction = true
	_bid_popup.show_bid(card.card_data, card.is_advanced, effective_min, cost_color)

func _on_bid_raised(amount: int) -> void:
	if GameNetwork.is_host:
		_server_handle_raise(1, amount)
	else:
		_rpc_raise_bid.rpc_id(1, amount)

func _on_bid_passed() -> void:
	if GameNetwork.is_host:
		_server_handle_pass_bid(1)
	else:
		_rpc_pass_bid.rpc_id(1)

func _server_start_auction(card_ref: Dictionary, slot_idx: int, is_tech: bool, is_adv: bool, min_bid: int, cost_color_int: int, initiator_id: int) -> void:
	_auction_card_ref = card_ref
	_auction_slot_idx = slot_idx
	_auction_is_tech = is_tech
	_auction_is_adv = is_adv
	_auction_cost_color = cost_color_int as CardData.SupplyColor
	_auction_current_bid = min_bid
	_auction_leader_id = initiator_id
	_auction_initiator_id = initiator_id
	var start_pos: int = GameNetwork.player_order.find(initiator_id)
	var n: int = GameNetwork.player_order.size()
	_auction_remaining = []
	_auction_second_id = -1
	for j: int in n:
		_auction_remaining.append(GameNetwork.player_order[(start_pos + j) % n])
	if _auction_remaining.size() <= 1:
		_rpc_sync_auction_won.rpc(initiator_id, initiator_id, min_bid, card_ref, slot_idx, is_tech, cost_color_int)
		return
	_auction_active_idx = 1
	var active_id: int = _auction_remaining[_auction_active_idx]
	var leader_name: String = GameNetwork.player_names.get(initiator_id, "Player")
	_rpc_sync_auction_started.rpc(card_ref, slot_idx, is_tech, is_adv, min_bid, cost_color_int, initiator_id, active_id, leader_name)

func _server_handle_raise(peer_id: int, amount: int) -> void:
	if _auction_remaining.is_empty():
		return
	if peer_id != _auction_remaining[_auction_active_idx]:
		return
	if amount <= _auction_current_bid:
		return
	_auction_second_id = _auction_leader_id
	_auction_current_bid = amount
	_auction_leader_id = peer_id
	_auction_active_idx = (_auction_active_idx + 1) % _auction_remaining.size()
	var active_id: int = _auction_remaining[_auction_active_idx]
	var leader_name: String = GameNetwork.player_names.get(_auction_leader_id, "Player")
	_rpc_sync_auction_state.rpc(_auction_current_bid, _auction_leader_id, active_id, leader_name)

func _server_handle_pass_bid(peer_id: int) -> void:
	if _auction_remaining.is_empty():
		return
	if peer_id != _auction_remaining[_auction_active_idx]:
		return
	if peer_id == _auction_leader_id:
		return
	_auction_remaining.remove_at(_auction_active_idx)
	if _auction_active_idx >= _auction_remaining.size():
		_auction_active_idx = 0
	if _auction_remaining.size() == 1:
		_rpc_sync_auction_won.rpc(_auction_initiator_id, _auction_leader_id, _auction_current_bid, _auction_card_ref, _auction_slot_idx, _auction_is_tech, int(_auction_cost_color))
		return
	var active_id: int = _auction_remaining[_auction_active_idx]
	var leader_name: String = GameNetwork.player_names.get(_auction_leader_id, "Player")
	_rpc_sync_auction_state.rpc(_auction_current_bid, _auction_leader_id, active_id, leader_name)

func _server_offer_to_runner_up() -> void:
	if _auction_second_id == -1:
		return
	var cd: CardData = CardRef.from_ref(_auction_card_ref)
	if not cd:
		return
	_rpc_sync_runner_up_phase.rpc(true)
	var printed_cost: int = cd.adv_cost if _auction_is_adv else cd.cost
	if _auction_second_id == multiplayer.get_unique_id():
		_on_runner_up_offer(_auction_card_ref, _auction_slot_idx, _auction_is_tech, _auction_is_adv, printed_cost, int(_auction_cost_color))
	else:
		_rpc_offer_to_runner_up.rpc_id(_auction_second_id, _auction_card_ref, _auction_slot_idx, _auction_is_tech, _auction_is_adv, printed_cost, int(_auction_cost_color))

func _on_runner_up_offer(card_ref: Dictionary, _slot_idx: int, _is_tech: bool, is_adv: bool, printed_cost: int, cost_color_int: int) -> void:
	var cd: CardData = CardRef.from_ref(card_ref)
	if not cd:
		return
	_pending_won_card_ref = card_ref
	_pending_won_is_adv = is_adv
	_pending_auction_win = true
	_auction_win_is_initiator = false
	_is_runner_up_offer = true
	var c_name: String = cd.adv_name if (is_adv and not cd.adv_name.is_empty()) else cd.card_name
	var cost_color: CardData.SupplyColor = cost_color_int as CardData.SupplyColor
	var valid_colors: Array[CardData.SupplyColor] = CardData.valid_payment_colors(cost_color)
	_bid_payment_panel.show_bid_payment(c_name, printed_cost, valid_colors, _cs_display, cd, is_adv)
	_update_turn_ui()

func _on_market_card_taken(cd: CardData) -> void:
	if not GameNetwork.is_multiplayer:
		return
	var card_ref: Dictionary = CardRef.to_ref(cd)
	if GameNetwork.is_host:
		_rpc_sync_market_removal.rpc(card_ref)
		if _runner_up_phase:
			_rpc_sync_runner_up_phase.rpc(false)
	else:
		_rpc_notify_market_taken.rpc_id(1, card_ref)

# Client → Host: I placed a card from the shared market.
@rpc("any_peer", "reliable")
func _rpc_notify_market_taken(card_ref: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_rpc_sync_market_removal.rpc(card_ref)
	if _runner_up_phase:
		_rpc_sync_runner_up_phase.rpc(false)

# Host → All: remove this card from the shared market view.
@rpc("authority", "reliable", "call_local")
func _rpc_sync_market_removal(card_ref: Dictionary) -> void:
	var cd: CardData = CardRef.from_ref(card_ref)
	if cd:
		$Board.remove_market_card(cd)

func _server_sync_sector_reveal(slot_idx: int, sender_id: int) -> void:
	if sender_id != 1:
		$Board.sync_market_reveal(slot_idx)
	_rpc_sync_sector_revealed.rpc(slot_idx)

# Client → Host: I revealed a dust sector via an effect.
@rpc("any_peer", "reliable")
func _rpc_notify_sector_revealed(slot_idx: int) -> void:
	if not multiplayer.is_server():
		return
	_server_sync_sector_reveal(slot_idx, multiplayer.get_remote_sender_id())

# Host → Clients: sync this sector reveal (no call_local — active player already revealed).
@rpc("authority", "reliable")
func _rpc_sync_sector_revealed(slot_idx: int) -> void:
	if GameNetwork.is_my_turn():
		return
	$Board.sync_market_reveal(slot_idx)

func _on_bid_confirmed(amount: int) -> void:
	if _pending_auction:
		_pending_auction = false
		$Board.set_major_action_taken()
		var my_id: int = multiplayer.get_unique_id()
		if GameNetwork.is_host:
			_server_start_auction(_pending_auction_card_ref, _pending_auction_slot_idx, _pending_auction_is_tech, _pending_auction_is_adv, amount, int(_bid_color), my_id)
		else:
			_rpc_request_auction.rpc_id(1, _pending_auction_card_ref, _pending_auction_slot_idx, _pending_auction_is_tech, _pending_auction_is_adv, amount, int(_bid_color))
		return
	_bid_amount = amount
	var valid_colors: Array[CardData.SupplyColor] = CardData.valid_payment_colors(_bid_color)
	_bid_payment_panel.show_bid_payment(_bid_card_name, amount, valid_colors, _cs_display, _bid_card_data, _bid_is_advanced)

func _on_bid_payment_confirmed(allocations: Dictionary) -> void:
	if _effect_mode == EffectMode.PAYMENT_CONFIRM:
		_effect_mode = EffectMode.NONE
		$Board.hide_payment_confirm_arrow()
		$Board.confirm_payment_with_allocations(allocations)
		return
	for color: Variant in allocations:
		_cs_display.spend_supply(color as CardData.SupplyColor, int(allocations[color]))
	if _pending_auction_win:
		_pending_auction_win = false
		if _auction_win_is_initiator:
			$Board.complete_purchase()
		else:
			_pending_won = true
			_show_won_card_popup()
		_show_action_buttons(true)
		_broadcast_my_state()
		return
	$Board.complete_purchase()
	_show_action_buttons(true)
	if _bid_is_from_effect:
		_bid_is_from_effect = false
		_process_next_effect()

func _on_bid_payment_forfeited() -> void:
	if _effect_mode == EffectMode.PAYMENT_CONFIRM:
		_effect_mode = EffectMode.NONE
		$Board.hide_payment_confirm_arrow()
		$Board.cancel_payment_confirm()
		return
	if _pending_auction_win:
		_pending_auction_win = false
		if _auction_win_is_initiator:
			$Board.cancel_purchase()
			$Board.reset_turn()
			if GameNetwork.is_host:
				_server_offer_to_runner_up()
			else:
				_rpc_notify_auction_forfeit.rpc_id(1)
		else:
			if _is_runner_up_offer:
				_is_runner_up_offer = false
				if GameNetwork.is_host:
					_rpc_sync_market_removal.rpc(_pending_won_card_ref)
					_rpc_sync_runner_up_phase.rpc(false)
				else:
					_rpc_notify_runner_up_forfeit.rpc_id(1, _pending_won_card_ref)
			else:
				if GameNetwork.is_host:
					_server_offer_to_runner_up()
				else:
					_rpc_notify_auction_forfeit.rpc_id(1)
		_show_action_buttons(true)
		return
	$Board.cancel_purchase()
	_show_action_buttons(true)
	if _bid_is_from_effect:
		_bid_is_from_effect = false
		_process_next_effect()

func _on_bid_cancelled() -> void:
	_pending_auction = false
	$Board.cancel_purchase()
	_show_action_buttons(true)
	if _bid_is_from_effect:
		_bid_is_from_effect = false
		_process_next_effect()

func _on_market_card_drag_failed(_card: Node3D) -> void:
	if _bid_is_from_effect:
		_bid_is_from_effect = false
		_process_next_effect()

func _on_market_card_hovered(url: String, card_scale: float) -> void:
	if not _log_preview_panel:
		return
	_log_preview_pending_hide = false
	var tex: Texture2D = ImageCache.get_texture(url) if not url.is_empty() else null
	_log_preview_image.texture = tex
	if tex == null:
		_log_preview_panel.visible = false
		return
	var img: Vector2i = tex.get_size()
	var pad: float = 6.0
	var lx: float = 408.0
	var ly: float = lx * float(img.y) / float(img.x)
	if card_scale > 1.0:  # expedition slot
		lx *= 0.65
		ly *= 0.95
	else:  # sector
		ly *= 1.5
	_log_preview_panel.size     = Vector2(lx + 2.0 * pad, ly + 2.0 * pad)
	_log_preview_panel.position = Vector2((408.0 - lx - 2.0 * pad) / 2.0, (686.0 - ly - 2.0 * pad) / 2.0)
	_log_preview_image.size     = Vector2(lx, ly)
	_log_preview_image.position = Vector2(pad, pad)
	_log_preview_panel.visible = true

func _on_market_card_unhovered() -> void:
	if not _log_preview_panel:
		return
	_log_preview_pending_hide = true
	get_tree().create_timer(0.08).timeout.connect(func() -> void:
		if _log_preview_pending_hide:
			_log_preview_panel.visible = false
	)

func _on_market_sector_advanced_pressed(slot_idx: int) -> void:
	if _effect_mode != EffectMode.NONE:
		return
	$Board.market_origin_3d = _viewport_to_world(_market_panel.get_slot_center("advanced", slot_idx))
	$Board.begin_panel_sector_drag(slot_idx, true)

func _on_market_sector_dust_pressed(slot_idx: int) -> void:
	if _effect_mode == EffectMode.EFFECT_REVEAL_SECTOR:
		$Board.reveal_sector_panel_slot(slot_idx)
	elif _effect_mode == EffectMode.NONE:
		$Board.market_origin_3d = _viewport_to_world(_market_panel.get_slot_center("dust", slot_idx))
		$Board.begin_panel_sector_drag(slot_idx, false)

func _on_market_expedition_pressed(slot_idx: int) -> void:
	if _effect_mode == EffectMode.EFFECT_EXPEDITION_SHUFFLE:
		$Board.shuffle_expedition_panel_slot(slot_idx)
	elif _effect_mode == EffectMode.EFFECT_REVEAL_EXPEDITION:
		_execute_expedition_reveal(slot_idx)
	elif _effect_mode == EffectMode.NONE:
		$Board.market_origin_3d = _viewport_to_world(_market_panel.get_slot_center("expedition", slot_idx))
		$Board.begin_panel_expedition_drag(slot_idx)

func _execute_expedition_reveal(slot_idx: int) -> void:
	_effect_mode = EffectMode.NONE
	$Board.set_expedition_reveal_mode(false)
	_hide_effect_hint()
	var revealed: CardData = $Board.reveal_expedition_to_slot(slot_idx)
	if _pending_expedition_reveal_gain_supply and revealed:
		_cs_display.add_supply(revealed.color, 1)
	if _pending_expedition_reveal_may_bid and revealed:
		_reveal_bid_pool.append(revealed)
	_pending_expedition_reveal_gain_supply = false
	_pending_expedition_reveal_may_bid = false
	if GameNetwork.is_multiplayer:
		if GameNetwork.is_host:
			_rpc_sync_expedition_reveal.rpc(slot_idx)
		else:
			_rpc_notify_expedition_reveal.rpc_id(1, slot_idx)
	_process_next_effect()

func _on_payment_confirm_required(card: Node3D, slot: SectorSlot, pay_amounts: Dictionary, _is_tech: bool) -> void:
	_effect_mode = EffectMode.PAYMENT_CONFIRM
	var card_name: String = ""
	var cost_color: CardData.SupplyColor = CardData.SupplyColor.DUST
	var total: int = 0
	var cd: CardData = null
	var is_adv: bool = false
	if card.card_data:
		cd = card.card_data
		is_adv = bool(card.get("is_advanced"))
		card_name = cd.adv_name if is_adv and not cd.adv_name.is_empty() else cd.card_name
		cost_color = cd.color
		for v: Variant in pay_amounts.values():
			total += int(v)
	if total == 0:
		_effect_mode = EffectMode.NONE
		$Board.confirm_payment()
		return
	var valid_colors: Array[CardData.SupplyColor] = CardData.valid_payment_colors(cost_color)
	_bid_payment_panel.show_bid_payment(card_name, total, valid_colors, _cs_display, cd, is_adv)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam and _info_screen_mesh and slot:
		var aabb: AABB = _info_screen_mesh.mesh.get_aabb()
		var from_world: Vector3 = _info_screen_mesh.to_global(aabb.get_center())
		var from_2d: Vector2 = cam.unproject_position(from_world)
		var to_2d: Vector2 = cam.unproject_position(slot.global_position)
		$Board.show_payment_confirm_arrow(from_2d, to_2d)

func _on_supply_choice_required(card: Node3D, _slot: SectorSlot, cost: int, options: Array[CardData.SupplyColor], _is_tech: bool) -> void:
	_effect_mode = EffectMode.SUPPLY_CHOICE
	var card_name: String = ""
	if card.card_data:
		var cd: CardData = card.card_data
		var is_adv: bool = bool(card.get("is_advanced"))
		card_name = cd.adv_name if is_adv and not cd.adv_name.is_empty() else cd.card_name
	_supply_cost_panel.show_cost(card_name, cost, options)

func _on_supply_chosen(color: CardData.SupplyColor) -> void:
	if _effect_mode == EffectMode.SUPPLY_CHOICE:
		_effect_mode = EffectMode.NONE
		$Board.apply_supply_choice(color)

func _on_supply_choice_cancelled() -> void:
	if _effect_mode == EffectMode.SUPPLY_CHOICE:
		_effect_mode = EffectMode.NONE
		$Board.cancel_payment_confirm()

func _on_expedition_shuffled_back(card_data: CardData, deck_insert_idx: int) -> void:
	if _effect_mode != EffectMode.EFFECT_EXPEDITION_SHUFFLE:
		return
	if GameNetwork.is_multiplayer and card_data:
		var card_ref: Dictionary = CardRef.to_ref(card_data)
		if GameNetwork.is_host:
			_rpc_sync_expedition_shuffle.rpc(card_ref, deck_insert_idx)
		else:
			_rpc_notify_expedition_shuffle.rpc_id(1, card_ref, deck_insert_idx)
	_shuffle_count += 1
	_effect_remaining -= 1
	if _effect_remaining <= 0:
		_finish_expedition_shuffle()
	else:
		_show_effect_hint("Click up to %d more expedition(s) to shuffle back — or Done" % _effect_remaining)

func _finish_expedition_shuffle() -> void:
	$Board.set_expedition_shuffle_mode(false)
	_market_panel.set_expedition_shuffle_mode(false)
	_effect_mode = EffectMode.NONE
	_effect_remaining = 0
	_hide_effect_hint()
	_effect_done_btn.hide()
	for _i: int in _shuffle_count:
		_effect_queue.insert(0, {type = "reveal_expedition"})
	_shuffle_count = 0
	_process_next_effect()

func _on_payment_recycle_requested() -> void:
	_effect_mode = EffectMode.PAYMENT_RECYCLE
	_show_effect_hint("Click a card to recycle it for payment")
	$Hand.set_discard_mode(true)

func _on_major_action_changed(taken: bool) -> void:
	_set_end_turn_button_disabled(not taken)
	if taken:
		call_deferred("_try_auto_end_turn")

func _on_action_committed() -> void:
	$Board.set_major_action_taken()
	_broadcast_my_state()

func _on_optimize_triggered(slot: SectorSlot, _level: int) -> void:
	_effect_slot = slot
	_effect_queue.append_array(SectorEffects.get_optimize_steps(slot))
	if _effect_mode == EffectMode.NONE:
		_process_next_effect()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if _info_viewport:
		_info_viewport.push_input(event)
	if event.is_action("pause_menu"):
		_pause_menu.toggle()
	elif event.is_action("end_turn") and not _pause_menu.visible:
		if _cs_display.can_end_turn():
			_on_end_turn_pressed()

func _on_pause_main_menu() -> void:
	SceneTransition.change_scene("res://scenes/main_menu/main_menu.tscn")

func _try_auto_end_turn() -> void:
	if _ending_turn:
		return
	if _has_researched:
		return
	if not GameNetwork.is_my_turn():
		return
	if not $Board.is_major_action_taken():
		return
	if _effect_mode != EffectMode.NONE:
		return
	if not _effect_queue.is_empty():
		return
	if _auction_active or _runner_up_phase or _pending_auction or _pending_auction_win or _pending_won:
		return
	if _pending_reveal_gain_supply or _pending_reveal_may_bid or _pending_reveal_may_free_gain:
		return
	if _cs_display.has_fuse_1to1_active():
		return
	_on_end_turn_pressed()

func _on_end_turn_pressed() -> void:
	if not GameNetwork.is_my_turn():
		return
	if not $Board.is_major_action_taken():
		return
	if _runner_up_phase:
		return
	_ending_turn = true
	_effect_queue.clear()
	_effect_slot = null
	_pending_reveal_gain_supply = false
	_pending_reveal_may_bid = false
	_pending_reveal_may_free_gain = false
	_reset_effect_state()
	if GameNetwork.is_multiplayer:
		_do_end_turn()
	else:
		$Board.reset_turn()
		_cs_display.clear_fuse_1to1()
		_show_action_buttons(true)
	_ending_turn = false

func _do_end_turn() -> void:
	_cs_display.clear_fuse_1to1()
	_show_action_buttons(false)
	_broadcast_my_state()
	if GameNetwork.is_host:
		_server_handle_end_turn()
	else:
		_rpc_request_end_turn.rpc_id(1)

func _server_handle_end_turn() -> void:
	GameNetwork.advance_turn()
	_rpc_sync_active_player.rpc(GameNetwork.active_peer_id)

@rpc("any_peer", "reliable")
func _rpc_request_end_turn() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != GameNetwork.active_peer_id:
		return
	_server_handle_end_turn()

func _on_supply_changed() -> void:
	_payment_panel.refresh()
	_bid_payment_panel.refresh()

func _refresh_vp() -> void:
	var lines: Array[Dictionary] = $Board.calculate_score()
	var total: int = 0
	for line: Dictionary in lines:
		total += int(line.get("vp", 0))
	_cs_display.set_vp(total)

# ── Expedition sync RPCs ──────────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func _rpc_notify_expedition_shuffle(card_ref: Dictionary, deck_insert_idx: int) -> void:
	if not multiplayer.is_server():
		return
	_rpc_sync_expedition_shuffle.rpc(card_ref, deck_insert_idx)

@rpc("authority", "reliable")
func _rpc_sync_expedition_shuffle(card_ref: Dictionary, deck_insert_idx: int) -> void:
	if GameNetwork.is_my_turn():
		return
	var cd: CardData = CardRef.from_ref(card_ref)
	if cd:
		$Board.sync_expedition_shuffle_in(cd, deck_insert_idx)

@rpc("any_peer", "reliable")
func _rpc_notify_expedition_reveal(slot_idx: int) -> void:
	if not multiplayer.is_server():
		return
	_rpc_sync_expedition_reveal.rpc(slot_idx)

@rpc("authority", "reliable")
func _rpc_sync_expedition_reveal(slot_idx: int) -> void:
	if GameNetwork.is_my_turn():
		return
	$Board.sync_expedition_reveal(slot_idx)

# ── Opponent board view ───────────────────────────────────────────────────────

func _show_opponent_board(peer_id: int) -> void:
	if not _opp_snapshots.has(peer_id):
		return
	if _opp_info_panel:
		_close_opponent_board_view()
	if _market_panel:
		_market_panel.visible = false
	_build_opp_info_panel(peer_id)

func _build_opp_info_panel(peer_id: int) -> void:
	if _opp_info_panel:
		_opp_info_panel.queue_free()
	var snap: Dictionary = _opp_snapshots.get(peer_id, {})
	var player_name: String = GameNetwork.player_names.get(peer_id, "Opponent")

	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_info_viewport.add_child(root)
	_opp_info_panel = root

	var scifi: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	scifi.set_content_margin(20)
	scifi.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(scifi)

	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	scifi.add_child(outer)

	# ── Header ──────────────────────────────────────────────────────────────────
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	outer.add_child(header)

	var name_lbl: Label = Label.new()
	name_lbl.text = player_name
	name_lbl.add_theme_font_size_override("font_size", 30)
	name_lbl.add_theme_color_override("font_color", Color(0.80, 0.90, 1.0))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(name_lbl)

	var return_btn: Button = Button.new()
	return_btn.text = "← Return"
	return_btn.add_theme_font_size_override("font_size", 20)
	return_btn.custom_minimum_size = Vector2(160, 48)
	return_btn.pressed.connect(_close_opponent_board_view)
	header.add_child(return_btn)

	var hsep: HSeparator = HSeparator.new()
	hsep.modulate = Color(0.4, 0.4, 0.5, 0.5)
	outer.add_child(hsep)

	# ── Stats bar ───────────────────────────────────────────────────────────────
	var stats_bar: HBoxContainer = HBoxContainer.new()
	stats_bar.add_theme_constant_override("separation", 16)
	outer.add_child(stats_bar)

	var supply_dict: Dictionary = snap.get("supply", {})
	var supply_paths: Array[String] = [
		"res://assets/ui/supply/Dust.png",
		"res://assets/ui/supply/Metals.png",
		"res://assets/ui/supply/Liquids.png",
		"res://assets/ui/supply/Organix.png",
		"res://assets/ui/supply/Electrix.png",
		"res://assets/ui/supply/Thrust.png",
	]
	for si: int in 6:
		var cell: HBoxContainer = HBoxContainer.new()
		cell.add_theme_constant_override("separation", 5)
		stats_bar.add_child(cell)
		var icon: TextureRect = TextureRect.new()
		icon.texture = load(supply_paths[si]) as Texture2D
		icon.custom_minimum_size = Vector2(22, 22)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(icon)
		var amt_lbl: Label = Label.new()
		amt_lbl.text = str(supply_dict.get(si, 0))
		amt_lbl.add_theme_font_size_override("font_size", 18)
		amt_lbl.add_theme_color_override("font_color", Color(0.75, 0.82, 1.0))
		amt_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(amt_lbl)

	var sv1: VSeparator = VSeparator.new()
	sv1.modulate = Color(0.4, 0.4, 0.5, 0.5)
	stats_bar.add_child(sv1)

	var hand_lbl: Label = Label.new()
	hand_lbl.text = "♠  %d cards" % snap.get("hand_size", 0)
	hand_lbl.add_theme_font_size_override("font_size", 18)
	hand_lbl.add_theme_color_override("font_color", Color(0.70, 0.82, 1.0))
	hand_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stats_bar.add_child(hand_lbl)

	var sv2: VSeparator = VSeparator.new()
	sv2.modulate = Color(0.4, 0.4, 0.5, 0.5)
	stats_bar.add_child(sv2)

	var vp_lbl: Label = Label.new()
	vp_lbl.text = "⭐  VP: %d" % snap.get("vp", 0)
	vp_lbl.add_theme_font_size_override("font_size", 20)
	vp_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	vp_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stats_bar.add_child(vp_lbl)

	var hsep2: HSeparator = HSeparator.new()
	hsep2.modulate = Color(0.4, 0.4, 0.5, 0.5)
	outer.add_child(hsep2)

	# ── Sector columns ──────────────────────────────────────────────────────────
	var sectors_row: HBoxContainer = HBoxContainer.new()
	sectors_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sectors_row.add_theme_constant_override("separation", 8)
	outer.add_child(sectors_row)

	var slots: Array = snap.get("slots", []) as Array
	var occupied_slots: Array = []
	for sv: Variant in slots:
		if bool((sv as Dictionary).get("occupied", false)):
			occupied_slots.append(sv as Dictionary)
	while occupied_slots.size() < 6:
		occupied_slots.append({"occupied": false})

	for slot_v: Variant in occupied_slots:
		sectors_row.add_child(_build_opp_sector_widget(slot_v as Dictionary))

func _build_opp_sector_widget(slot: Dictionary) -> Control:
	var occupied: bool = bool(slot.get("occupied", false))
	var sector_name: String = str(slot.get("sector_name", ""))
	var is_adv: bool = bool(slot.get("sector_advanced", false))
	var tech_names: Array = slot.get("tech_names", []) as Array

	var cd: CardData = null
	if occupied:
		for c: CardData in CardDatabase.sectors:
			if c.card_name == sector_name or c.adv_name == sector_name:
				cd = c
				break

	var supply_color: CardData.SupplyColor = CardData.SupplyColor.DUST
	if cd:
		supply_color = cd.adv_color if is_adv else cd.color
	var border_col: Color = CardData.color_tint(supply_color)

	var outer: PanelContainer = PanelContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.09, 0.18, 0.95) if occupied else Color(0.04, 0.06, 0.12, 0.6)
	panel_style.border_color = border_col if occupied else Color(0.25, 0.28, 0.38, 0.5)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(4)
	panel_style.content_margin_left = 6
	panel_style.content_margin_right = 6
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	outer.add_theme_stylebox_override("panel", panel_style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	outer.add_child(vbox)

	if not occupied:
		var empty_lbl: Label = Label.new()
		empty_lbl.text = "—"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty_lbl.add_theme_font_size_override("font_size", 28)
		empty_lbl.add_theme_color_override("font_color", Color(0.25, 0.28, 0.38, 0.6))
		vbox.add_child(empty_lbl)
		return outer

	var img_url: String = ""
	if cd:
		img_url = cd.adv_image_url if is_adv else cd.image_url
	var tex: Texture2D = ImageCache.get_texture(img_url) if not img_url.is_empty() else null

	if tex:
		var art: TextureRect = TextureRect.new()
		art.texture = tex
		art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vbox.add_child(art)
	else:
		var placeholder: ColorRect = ColorRect.new()
		placeholder.color = border_col.darkened(0.55)
		placeholder.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(placeholder)

	var name_lbl: Label = Label.new()
	name_lbl.text = ("▲ " if is_adv else "") + sector_name
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color",
		Color(1.0, 0.90, 0.50) if is_adv else Color(0.85, 0.92, 1.0))
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(name_lbl)

	if not tech_names.is_empty():
		var sep: HSeparator = HSeparator.new()
		sep.modulate = Color(0.35, 0.40, 0.55, 0.5)
		vbox.add_child(sep)
		for t: Variant in tech_names:
			var t_lbl: Label = Label.new()
			t_lbl.text = "• " + str(t)
			t_lbl.add_theme_font_size_override("font_size", 11)
			t_lbl.add_theme_color_override("font_color", Color(0.65, 0.80, 1.0))
			t_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(t_lbl)

	outer.mouse_filter = Control.MOUSE_FILTER_STOP
	outer.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	outer.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_show_opp_sector_detail(slot)
	)

	return outer


func _show_opp_sector_detail(slot: Dictionary) -> void:
	var existing: Node = _opp_info_panel.get_node_or_null("SectorDetail")
	if existing:
		existing.queue_free()

	var sector_name: String = str(slot.get("sector_name", ""))
	var is_adv: bool = bool(slot.get("sector_advanced", false))
	var tech_names: Array = slot.get("tech_names", []) as Array

	var sector_cd: CardData = null
	for c: CardData in CardDatabase.sectors:
		if c.card_name == sector_name or c.adv_name == sector_name:
			sector_cd = c
			break

	var overlay: Control = Control.new()
	overlay.name = "SectorDetail"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_opp_info_panel.add_child(overlay)

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			overlay.queue_free()
	)
	overlay.add_child(dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var ps: StyleBoxFlat = StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.09, 0.20, 0.98)
	ps.border_color = Color(0.35, 0.42, 0.62)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(6)
	ps.content_margin_left = 24
	ps.content_margin_right = 24
	ps.content_margin_top = 20
	ps.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var inner: VBoxContainer = VBoxContainer.new()
	inner.add_theme_constant_override("separation", 14)
	panel.add_child(inner)

	var hdr: Label = Label.new()
	hdr.text = ("▲ " if is_adv else "") + sector_name
	hdr.add_theme_font_size_override("font_size", 26)
	hdr.add_theme_color_override("font_color",
		Color(1.0, 0.90, 0.50) if is_adv else Color(0.80, 0.90, 1.0))
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(hdr)

	var hsep_d: HSeparator = HSeparator.new()
	hsep_d.modulate = Color(0.4, 0.4, 0.5, 0.5)
	inner.add_child(hsep_d)

	var cards_row: HBoxContainer = HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 16)
	inner.add_child(cards_row)

	cards_row.add_child(_build_detail_card(sector_cd, is_adv, sector_name))

	if not tech_names.is_empty():
		var vsep_d: VSeparator = VSeparator.new()
		vsep_d.modulate = Color(0.4, 0.4, 0.5, 0.4)
		cards_row.add_child(vsep_d)
		for t: Variant in tech_names:
			var t_name: String = str(t)
			var tech_cd: CardData = null
			for c: CardData in CardDatabase.techs:
				if c.card_name == t_name:
					tech_cd = c
					break
			cards_row.add_child(_build_detail_card(tech_cd, false, t_name))

	var close_sep: HSeparator = HSeparator.new()
	close_sep.modulate = Color(0.4, 0.4, 0.5, 0.5)
	inner.add_child(close_sep)

	var close_btn: Button = Button.new()
	close_btn.text = "✕  Close"
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.custom_minimum_size = Vector2(160, 44)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(func() -> void: overlay.queue_free())
	inner.add_child(close_btn)


func _build_detail_card(cd: CardData, is_adv: bool, fallback_name: String) -> Control:
	var supply_color: CardData.SupplyColor = CardData.SupplyColor.DUST
	if cd:
		supply_color = cd.adv_color if is_adv else cd.color
	var border_col: Color = CardData.color_tint(supply_color)

	var outer: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.16)
	style.border_color = border_col
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	outer.add_theme_stylebox_override("panel", style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	outer.add_child(vbox)

	var img_url: String = ""
	if cd:
		img_url = cd.adv_image_url if is_adv else cd.image_url
	var tex: Texture2D = ImageCache.get_texture(img_url) if not img_url.is_empty() else null

	if tex:
		var art: TextureRect = TextureRect.new()
		art.texture = tex
		art.custom_minimum_size = Vector2(240, 336)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vbox.add_child(art)
	else:
		var placeholder: ColorRect = ColorRect.new()
		placeholder.color = border_col.darkened(0.55)
		placeholder.custom_minimum_size = Vector2(240, 336)
		vbox.add_child(placeholder)

	var card_name: String = ((cd.adv_name if is_adv else cd.card_name) if cd else fallback_name)
	var name_lbl: Label = Label.new()
	name_lbl.text = card_name
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color",
		Color(1.0, 0.90, 0.50) if is_adv else Color(0.85, 0.92, 1.0))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.custom_minimum_size = Vector2(240, 0)
	vbox.add_child(name_lbl)

	if cd and cd.stars > 0:
		var stars_lbl: Label = Label.new()
		stars_lbl.text = "⭐".repeat(cd.stars)
		stars_lbl.add_theme_font_size_override("font_size", 13)
		stars_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(stars_lbl)

	return outer


func _close_opponent_board_view() -> void:
	if _opp_info_panel:
		_opp_info_panel.queue_free()
		_opp_info_panel = null
	if _market_panel:
		_market_panel.visible = true

# ── Market card hologram ───────────────────────────────────────────────────────

# ── Connection loss ───────────────────────────────────────────────────────────

func _on_peer_disconnected(peer_id: int) -> void:
	if not GameNetwork.is_multiplayer:
		return
	var msg: String
	if peer_id == 1:
		msg = "Host disconnected."
	else:
		msg = "%s disconnected." % GameNetwork.player_names.get(peer_id, "Opponent")
	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(32)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.z_index = 100
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	vbox.custom_minimum_size = Vector2(380.0, 0.0)
	var lbl: Label = Label.new()
	lbl.text = msg + "\n\nThe game session has ended."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	var btn: Button = Button.new()
	btn.text = "Main Menu"
	btn.custom_minimum_size = Vector2(200.0, 48.0)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(func() -> void:
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer.close()
			multiplayer.multiplayer_peer = null
		SceneTransition.change_scene("res://scenes/main_menu/main_menu.tscn")
	)
	vbox.add_child(lbl)
	vbox.add_child(btn)
	panel.add_child(vbox)
	$UILayer.add_child(panel)

# ── Music ─────────────────────────────────────────────────────────────────────

func _setup_music() -> void:
	var music_stream: AudioStreamWAV = load("res://assets/music/ambience.wav") as AudioStreamWAV
	if not music_stream:
		return
	_music_player_a = AudioStreamPlayer.new()
	_music_player_a.stream = music_stream
	_music_player_a.bus = &"Music"
	add_child(_music_player_a)
	_music_player_b = AudioStreamPlayer.new()
	_music_player_b.stream = music_stream
	_music_player_b.bus = &"Music"
	_music_player_b.volume_db = -80.0
	add_child(_music_player_b)
	_music_player_a.play()
	var length: float = music_stream.get_length()
	get_tree().create_timer(length - MUSIC_CROSSFADE_SEC).timeout.connect(_crossfade_music)

func _crossfade_music() -> void:
	if not _music_player_a or not _music_player_b:
		return
	var outgoing: AudioStreamPlayer = _music_player_a if _music_use_a else _music_player_b
	var incoming: AudioStreamPlayer = _music_player_b if _music_use_a else _music_player_a
	_music_use_a = not _music_use_a
	incoming.volume_db = -80.0
	incoming.play()
	var t: Tween = create_tween()
	t.tween_property(incoming, "volume_db", 0.0, MUSIC_CROSSFADE_SEC)
	t.parallel().tween_property(outgoing, "volume_db", -80.0, MUSIC_CROSSFADE_SEC)
	var length: float = incoming.stream.get_length()
	get_tree().create_timer(length - MUSIC_CROSSFADE_SEC).timeout.connect(_crossfade_music)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _on_card_recycled(color: CardData.SupplyColor) -> void:
	UIAudio.play_recycle_sfx()
	_cs_display.add_supply(color, 1)
	_apply_recycle_bonus(color)

func _apply_recycle_bonus(color: CardData.SupplyColor) -> void:
	if color != CardData.SupplyColor.DUST:
		return
	var count: int = $Board.count_tech_by_name("Trash Compactor")
	if count > 0:
		_cs_display.add_supply(CardData.SupplyColor.DUST, count)

func _init_supply() -> void:
	var ui: SupplyUI = _cs_display
	ui.set_supply(CardData.SupplyColor.DUST,     4)
	ui.set_supply(CardData.SupplyColor.METALS,   2)
	ui.set_supply(CardData.SupplyColor.LIQUIDS,  2)
	ui.set_supply(CardData.SupplyColor.ORGANIX,  1)
	ui.set_supply(CardData.SupplyColor.ELECTRIX, 1)
	ui.set_supply(CardData.SupplyColor.THRUST,   0)

func _show_effect_hint(text: String) -> void:
	if _effect_hint_label:
		_effect_hint_label.text = text
	if _effect_hint_panel:
		_effect_hint_panel.show()

func _hide_effect_hint() -> void:
	if _effect_hint_panel:
		_effect_hint_panel.hide()

func _show_action_buttons(v: bool) -> void:
	_cs_display.show_action_buttons(v)

func _show_end_turn_button(v: bool) -> void:
	_cs_display.show_end_turn_button(v)
	if not v:
		_stop_end_turn_3d_flash()

func _set_action_buttons_disabled(v: bool) -> void:
	_cs_display.set_action_buttons_disabled(v)

func _set_end_turn_button_disabled(v: bool) -> void:
	_cs_display.set_end_turn_button_disabled(v)
	if v:
		_stop_end_turn_3d_flash()
	else:
		_start_end_turn_3d_flash()

func _start_end_turn_3d_flash() -> void:
	if not _end_turn_btn_mesh:
		return
	if _end_turn_flash_tween:
		_end_turn_flash_tween.kill()
	var base: Material = _end_turn_btn_mesh.mesh.surface_get_material(0)
	var mat: StandardMaterial3D = (base as StandardMaterial3D).duplicate() as StandardMaterial3D if base is StandardMaterial3D else StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.08, 0.08)
	mat.emission_energy_multiplier = 0.0
	_end_turn_flash_mat = mat
	_end_turn_btn_mesh.set_surface_override_material(0, mat)
	_end_turn_flash_tween = create_tween().set_loops()
	_end_turn_flash_tween.tween_property(mat, "emission_energy_multiplier", 2.5, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_end_turn_flash_tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _stop_end_turn_3d_flash() -> void:
	if _end_turn_flash_tween:
		_end_turn_flash_tween.kill()
		_end_turn_flash_tween = null
	_end_turn_flash_mat = null
	if _end_turn_btn_mesh:
		_end_turn_btn_mesh.set_surface_override_material(0, null)

# ── Cockpit rumble ────────────────────────────────────────────────────────────

func _start_rumble_timer() -> void:
	get_tree().create_timer(randf_range(30.0, 60.0)).timeout.connect(_play_rumble)

func _play_rumble() -> void:
	const JOLT_SEC: float = 0.10
	const JOLT_COUNT: int = 15  # 15 × 0.10 s = 1.5 s
	var targets: Array[Node3D] = [$UiCockpit, $UiControl, $UiInfo, $UiLog]
	for slot: SectorSlot in $Board.get_all_sector_slots():
		targets.append(slot)
	for node: Node3D in targets:
		var tw: Tween = _rumble_tweens.get(node) as Tween
		if tw and tw.is_valid():
			tw.kill()
		tw = create_tween()
		_rumble_tweens[node] = tw
		var base_pos: Vector3 = _rumble_base_pos.get(node, node.position)
		var base_rot: Vector3 = _rumble_base_rot.get(node, node.rotation)
		for _i: int in JOLT_COUNT:
			var dp: Vector3 = Vector3(randf_range(-0.003, 0.003), randf_range(-0.0015, 0.0015), randf_range(-0.0024, 0.0024))
			var dr: Vector3 = base_rot + Vector3(randf_range(-0.0015, 0.0015), randf_range(-0.0009, 0.0009), randf_range(-0.0015, 0.0015))
			tw.tween_property(node, "position", base_pos + dp, JOLT_SEC).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			tw.parallel().tween_property(node, "rotation", dr, JOLT_SEC).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(node, "position", base_pos, 0.40).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.parallel().tween_property(node, "rotation", base_rot, 0.40).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_rumble_tweens[$UiCockpit].tween_callback(_start_rumble_timer)
