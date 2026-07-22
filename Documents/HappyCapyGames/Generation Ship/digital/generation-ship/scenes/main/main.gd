class_name Main
extends Node3D

@export var card_scene: PackedScene

const MAX_ROUNDS := 4
const SETTINGS_PATH: String = "user://settings.cfg"

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
	EFFECT_RECYCLE,
	EFFECT_RECYCLE_OPTIONAL,
	EFFECT_TUCK,
	EFFECT_TUCK_OPTIONAL,
	EFFECT_RECYCLE_TUCK,
	EFFECT_RECYCLE_DOUBLE,
	EFFECT_REVEAL_SECTOR,
	EFFECT_REVEAL_EXPEDITION,
	EFFECT_REVEAL_DISPLAY,
	EFFECT_EXPEDITION_SHUFFLE,
	EFFECT_SEEDBANKS,
	EFFECT_CARGO_DRONES,
	EFFECT_CALDERA_SELECT_SECTOR,
	EFFECT_CALDERA_SELECT_CARDS,
	EFFECT_STORE_ON_SECTOR,
	EFFECT_CHOICE,
	EFFECT_RECYCLE_TUCK_STORE,
	EFFECT_RECYCLE_TUCK_STORE_DECIDE,
	EFFECT_RECYCLE_TUCK_STORE_SECTOR,
	EFFECT_TUCK_ANY_SECTOR,
	EFFECT_TUCK_ANY_SECTOR_SLOT,
	EFFECT_INTERFLEET_PICK,
	EFFECT_AWAITING_ALL_DRAW,
	PAYMENT_CONFIRM,
	SUPPLY_CHOICE,
}

var _effect_mode: EffectMode = EffectMode.NONE
var _effect_queue: Array[Dictionary] = []
var _effect_slot: SectorSlot = null
var _effect_source_name: String = ""
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
var _tuck_optional_no_bonus_draw: bool = false
var _sector_info_popup: SectorInfoPopup = null
var _recycle_panel: Control = null
var _sector_picker: SectorPickerPanel = null
var _supply_cost_panel: SupplyCostPanel = null
var _market_panel: Control = null
var _bid_payment_panel: Control = null
var _cargo_drones_panel: CargoDronesPanel = null
var _caldera_slots: Array[SectorSlot] = []
var _music_player: AudioStreamPlayer = null
var _pending_store_color: CardData.SupplyColor = CardData.SupplyColor.DUST
var _pending_store_amount: int = 0
var _pending_tuck_card_data: CardData = null
var _pending_target_slot: SectorSlot = null
var _effect_label: String = ""
var _has_passed: bool = false
var _has_researched: bool = false
var _opp_snapshots: Dictionary = {}      # peer_id (int) -> state Dictionary
var opp_widget: Control = null
var _opp_panels: Dictionary = {}         # peer_id → {hand_lbl, supply_lbls, vp_lbl, status_lbl}
var _opp_statuses: Dictionary = {}      # peer_id → String ("" | "passed" | "researching")
var opp_info_panel: Control = null
var _ending_turn: bool = false
var _pre_setup_done: bool = false
var _cached_sector_order: Array = []
var _cached_exp_order: Array = []
var _cached_tech_order: Array = []

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
var _pending_won_card_ref: Dictionary = {}
var _pending_auction_win: bool = false
var _auction_win_is_initiator: bool = false
var _auction_active: bool = false
var _auction_starting: bool = false  # true from bid-confirm until _auction_active (or a same-peer instant win) — closes the auto-end-turn race for the client that requested the auction
var _is_runner_up_offer: bool = false
var _runner_up_phase: bool = false
var _bots_passed_this_round: Array[int] = []

var _interfleet_active: bool = false
var _interfleet_initiator_id: int = 0
var _interfleet_remaining_order: Array[int] = []   # front = current active picker
var _interfleet_pool_refs: Array = []
var _interfleet_awaiting_pick: bool = false        # true only on the client currently showing the pick popup
var cs_viewport: SubViewport = null
var vp_button_held: bool = false
var vp_prev_pos: Dictionary = {}  # SubViewport -> Vector2
var _info_viewport: SubViewport = null
var log_viewport: SubViewport = null
var log_canvas: Control = null
var _log_vbox: VBoxContainer = null
var _log_scroll: ScrollContainer = null
var _log_font: FontVariation = null
var _tooltip_panel: Control = null
var _tooltip_title: Label = null
var _tooltip_desc: Label = null
var _sun_elevated_count: int = 0

var rumble_tweens: Dictionary = {}   # Node3D -> Tween
var _rumble_base_pos: Dictionary = {} # Node3D -> Vector3
var _rumble_base_rot: Dictionary = {} # Node3D -> Vector3
var _info_screen_mesh: MeshInstance3D = null
var _cs_display: SupplyUI = null
var _end_turn_btn_mesh: MeshInstance3D = null
var _end_turn_flash_tween: Tween = null
var _ui_control_shown: bool = false
var _ui_info_shown: bool = false
var _end_turn_flash_mat: StandardMaterial3D = null
var _pass_btn_mesh: MeshInstance3D = null
var _pass_btn_flash_tween: Tween = null
var _pass_btn_flash_mat: StandardMaterial3D = null
var _research_btn_mesh: MeshInstance3D = null
var _research_btn_flash_tween: Tween = null
var _research_btn_flash_mat: StandardMaterial3D = null
var _effect_hint_panel: Control = null
var _effect_hint_label: Label = null
var es_viewport: Control = null
var _bid_popup: Control = null
var _scoreboard: Control = null
var _pause_menu: Control = null
var _tutorial: FirstTurnTutorial = null
var info_panels: Array[Control] = []
var bot_hands: Dictionary = {}      # bot_id → Array[CardData]
var bot_supplies: Dictionary = {}   # bot_id → Dictionary (int color → int count)
var bot_boards: Dictionary = {}     # bot_id → Array[{sector, is_advanced, techs, stored}]
var es_back_btn: Button = null

# ── Setup ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added_to_tree)
	for node: Node3D in [$UiControl, $UiInfo, $UiLog, $UiCockpit]:
		_rumble_base_pos[node] = node.position
		_rumble_base_rot[node] = node.rotation
	CockpitRig.start_rumble_timer(self)
	$UILayer/StartButton.queue_free()
	var hand: Node3D = $Hand
	$Board.set_hand(hand)
	$Board.set_card_scene(card_scene)
	$Board.card_recycled.connect(_on_card_recycled)
	$Board.unplaceable_card_recycled.connect(_on_unplaceable_card_recycled)
	$Board.recycle_confirm_required.connect(_on_recycle_confirm_required)
	$Board.setup_sector_deck(CardDatabase.sectors)
	$Board.tech_card_drawn.connect(_on_tech_card_drawn)
	$Board.tech_deck_reshuffled.connect(_on_tech_deck_reshuffled)
	$Board.tech_card_discarded.connect(_on_tech_card_discarded)
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
	_scoreboard = $UILayer/Scoreboard
	_pause_menu = $UILayer/PauseMenu
	_pause_menu.main_menu_pressed.connect(_on_pause_main_menu)
	_bid_popup.bid_confirmed.connect(_on_bid_confirmed)
	_bid_popup.bid_cancelled.connect(_on_bid_cancelled)
	_bid_popup.bid_raised.connect(_on_bid_raised)
	_bid_popup.bid_passed.connect(_on_bid_passed)
	ImageCache.progress_updated.connect(_on_cache_progress)
	ImageCache.all_loaded.connect(_on_cache_ready)
	ImageCache.preload_urls(_collect_urls())

	CockpitRig.setup_info_screen_display(self)


	_bid_payment_panel = load("res://scenes/ui/bid_payment_panel.gd").new()
	_info_viewport.add_child(_bid_payment_panel)
	CockpitRig.register_info_panel(self, _bid_payment_panel)
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
	CockpitRig.register_info_panel(self, _choice_popup)

	_supply_cost_panel = SupplyCostPanel.new()
	_supply_cost_panel.supply_chosen.connect(_on_supply_chosen)
	_supply_cost_panel.cancelled.connect(_on_supply_choice_cancelled)
	_info_viewport.add_child(_supply_cost_panel)
	CockpitRig.register_info_panel(self, _supply_cost_panel)

	_sector_info_popup = SectorInfoPopup.new()
	_info_viewport.add_child(_sector_info_popup)
	CockpitRig.register_info_panel(self, _sector_info_popup)

	_cargo_drones_panel = CargoDronesPanel.new()
	_info_viewport.add_child(_cargo_drones_panel)
	CockpitRig.register_info_panel(self, _cargo_drones_panel)
	_cargo_drones_panel.move_requested.connect(_on_cargo_move_requested)
	_cargo_drones_panel.finished.connect(_finish_interactive_step)

	_recycle_panel = load("res://scenes/ui/recycle_panel.gd").new()
	_info_viewport.add_child(_recycle_panel)
	CockpitRig.register_info_panel(self, _recycle_panel)
	_recycle_panel.confirmed.connect(_on_recycle_panel_confirmed)
	_recycle_panel.cancelled.connect(_on_recycle_panel_cancelled)

	_sector_picker = load("res://scenes/ui/sector_picker_panel.gd").new()
	_info_viewport.add_child(_sector_picker)
	CockpitRig.register_info_panel(self, _sector_picker)
	_sector_picker.sector_selected.connect(_on_sector_selected_from_picker)
	_sector_picker.skipped.connect(_on_sector_picker_skipped)

	$Board.sector_info_requested.connect(_on_sector_info_requested)
	$Board.market_card_inspect_bought.connect(_on_market_card_inspect_bought)

	_setup_music()
	CockpitRig.setup_control_screen_display(self)
	OpponentBoardView.setup_enemy_screen_display(self)
	CockpitRig.setup_log_screen_display(self)
	CockpitRig.setup_floating_tooltip(self)
	CockpitRig.setup_cockpit_switches(self)

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
	if card.is_market_inspecting():
		desc = "Left-click to buy.\nRight-click to shrink."
	elif card.is_placed:
		desc = "Right-click to shrink card." if card.is_elevated() else "Right-click to enlarge card."
		_set_containing_sector_hover(card, true)
	elif card.managed_by_hand:
		desc = "Left-click and drag onto sector to buy or Right-click to Recycle."
	elif card.card_data:
		match card.card_data.card_type:
			CardData.CardType.EXPEDITION:
				desc = "left-click and drag onto sector card to start a bid."
			CardData.CardType.SECTOR:
				desc = "Left-click and drag onto a blue sector slot to start a bid." if card.is_advanced else "Left-click and drag onto a blue sector slot to buy sector. Base card to place other cards onto."
	if not desc.is_empty():
		_show_tooltip("", desc)

func _on_any_card_unhovered(card_node: Node3D) -> void:
	_hide_tooltip()
	var card: Card = card_node as Card
	if card and card.is_placed:
		_set_containing_sector_hover(card, false)

# A placed card's parent is either its SectorSlot directly (the main card)
# or a tech slot node one level below the SectorSlot (a tech card) — walk up
# to whichever it is and toggle that sector's tech-stack fan-out.
func _set_containing_sector_hover(card: Node3D, on: bool) -> void:
	var parent: Node = card.get_parent()
	var slot: SectorSlot = parent as SectorSlot
	if not slot:
		slot = parent.get_parent() as SectorSlot if parent else null
	if slot:
		slot.set_hover_expand(on)

func _on_card_elevation_started(card_node: Node3D) -> void:
	var card: Card = card_node as Card
	if card and card.is_market_inspecting():
		return
	_sun_elevated_count += 1
	get_tree().create_timer(0.15).timeout.connect(func() -> void:
		if _sun_elevated_count > 0:
			$SunLayer.visible = false
	)

func _on_card_elevation_ended(card_node: Node3D) -> void:
	var card: Card = card_node as Card
	if card and card.is_market_inspecting():
		return
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
		_cached_tech_order = _generate_shuffled_order(CardDatabase.techs.size())
		call_deferred("_deferred_pre_setup")
	elif GameNetwork.is_host:
		_cached_sector_order = _generate_shuffled_order(CardDatabase.sectors.size())
		_cached_exp_order = _generate_shuffled_order(CardDatabase.expeditions.size())
		_cached_tech_order = _generate_shuffled_order(CardDatabase.techs.size())
		call_deferred("_deferred_pre_setup")

func _deferred_pre_setup() -> void:
	_do_game_setup(_cached_sector_order, _cached_exp_order, _cached_tech_order)
	await get_tree().create_timer(3.0).timeout
	if not GameNetwork.is_multiplayer:
		_rpc_start_game([], [], [])
	elif GameNetwork.is_host:
		_rpc_start_game.rpc(_cached_sector_order, _cached_exp_order, _cached_tech_order)

func _do_game_setup(sector_order: Array, exp_order: Array, tech_order: Array) -> void:
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
	if tech_order.is_empty():
		$Board.setup_tech_deck(CardDatabase.techs)
	else:
		$Board.setup_tech_deck_ordered(tech_order)
	$Board.refresh_hand_discounts()
	_market_panel.setup($Board.get_market(), $Board.get_expedition_market())
	_show_action_buttons(true)
	_show_end_turn_button(true)
	_set_end_turn_button_disabled(true)
	_refresh_vp()
	_update_turn_ui(false)
	if GameNetwork.is_multiplayer:
		OpponentBoardView.build_opponent_widget(self)
	_log_action("─── Round 1 / %d ───" % MAX_ROUNDS, Color(0.6, 0.82, 1.0))

func _show_tooltip(title: String, desc: String) -> void:
	if not _tooltip_panel:
		return
	_tooltip_title.text = title
	_tooltip_title.visible = not title.is_empty()
	_tooltip_desc.text = desc
	_tooltip_panel.visible = true
	_tooltip_panel.reset_size()
	_update_tooltip_position()

func _hide_tooltip() -> void:
	if _tooltip_panel:
		_tooltip_panel.visible = false

func _process(_delta: float) -> void:
	if _tooltip_panel and _tooltip_panel.visible:
		_update_tooltip_position()

func _update_tooltip_position() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var target: Vector2 = get_viewport().get_mouse_position() + Vector2(20.0, 24.0)
	target.x = clamp(target.x, 8.0, max(8.0, vp_size.x - _tooltip_panel.size.x - 8.0))
	target.y = clamp(target.y, 8.0, max(8.0, vp_size.y - _tooltip_panel.size.y - 8.0))
	_tooltip_panel.position = target

func _log_action(text: String, color: Color = Color(0.80, 0.88, 1.0)) -> void:
	if not _log_vbox:
		return
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.add_theme_color_override("font_color", color)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
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

# Logs the concrete outcome of a card effect step, named after the card whose
# effect (sector place, tech Always, or sector optimize) produced the step —
# see _effect_source_name, set once per step in _execute_effect_step.
func _log_effect(message: String) -> void:
	var source: String = _effect_source_name if not _effect_source_name.is_empty() else "Effect"
	_broadcast_log("%s: %s" % [source, message], Color(0.6, 0.85, 0.75))

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

# Local, per-machine — not synced. Each peer independently checks/shows/
# marks its own settings.cfg, since "has this installation seen the
# tutorial" has nothing to do with the network session.
func _tutorial_seen() -> bool:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		return bool(cfg.get_value("tutorial", "seen", false))
	return false

func _mark_tutorial_seen() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("tutorial", "seen", true)
	cfg.save(SETTINGS_PATH)

# "Solo" in the sense that matters for the tutorial: no other real person
# at the table. GameNetwork.is_multiplayer is true even for a bots-only
# lobby (setup_multiplayer() is always called once a game is launched via
# the menu/lobby — is_multiplayer only reads false if main.tscn is opened
# directly, bypassing the lobby entirely) so it can't be used here.
func _is_true_solo_session() -> bool:
	var real_players: Array = GameNetwork.player_order.filter(
		func(id: int) -> bool: return not GameNetwork.is_bot(id))
	return real_players.size() <= 1

func _start_first_turn_tutorial_if_needed() -> void:
	if not _is_true_solo_session() or _tutorial_seen():
		return
	_mark_tutorial_seen()  # mark before starting — a crash mid-tutorial shouldn't re-nag
	_tutorial = FirstTurnTutorial.new()
	add_child(_tutorial)
	_tutorial.start(self)

@rpc("authority", "reliable", "call_local")
func _rpc_start_game(sector_order: Array, exp_order: Array, tech_order: Array) -> void:
	if not _pre_setup_done:
		_do_game_setup(sector_order, exp_order, tech_order)
	if multiplayer.is_server() and not GameNetwork.bot_ids.is_empty():
		BotTurn.init_bot_state(self)

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
	if not GameNetwork.is_multiplayer:
		$Board.deal_opening_hand()
	elif GameNetwork.is_host:
		_server_deal_hands_to_real_peers(6)
	if GameNetwork.is_multiplayer:
		_broadcast_my_state()
	await get_tree().create_timer(2.0).timeout
	_start_first_turn_tutorial_if_needed()
	if GameNetwork.is_my_turn():
		_show_your_turn_banner()
	if multiplayer.is_server() and GameNetwork.is_bot(GameNetwork.active_peer_id):
		BotTurn.run_bot_turn(self, GameNetwork.active_peer_id)

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
	if _tutorial:
		_tutorial.notify_passed()
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
	if not GameNetwork.is_multiplayer:
		$Board.draw_cards(6)
	elif GameNetwork.is_host:
		_server_deal_hands_to_real_peers(6)
	$Board.refresh_hand_discounts()
	if multiplayer.is_server() and not GameNetwork.bot_ids.is_empty():
		BotTurn.update_bots_for_new_round(self)
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
	# advance_turn() cycles through player_order blindly, so a player who has
	# already passed for the round can still land back on "active" again
	# (before immediately auto-advancing past them) — that's not a real new
	# turn, so skip the banner/chime for it, but leave everything else (turn
	# indicator, action button state) updating normally.
	if show_banner and my_turn and _round > 0 and not _has_passed:
		_show_your_turn_banner()
	_set_action_buttons_disabled(not my_turn)

func _show_your_turn_banner() -> void:
	UIAudio.play_shift_change_sfx()
	var lbl: Label = _make_banner_label("Your Turn", 56, Color(0.45, 1.0, 0.55))
	var t: Tween = create_tween()
	t.tween_property(lbl, "modulate:a", 1.0, 0.22).set_ease(Tween.EASE_OUT)
	t.tween_interval(1.0)
	t.tween_property(lbl, "modulate:a", 0.0, 0.38).set_ease(Tween.EASE_IN)
	t.tween_callback(lbl.queue_free)

# True once every player's most recent status this round is "passed" or
# "researching" — a player can research on multiple separate turns and still
# get called on again, but the round itself is over the moment nobody has
# anything left to do, without waiting for everyone to explicitly pass.
func _all_players_done_this_round() -> bool:
	for peer_id: int in GameNetwork.player_order:
		var status: String = _opp_statuses.get(peer_id, "") as String
		if status != "passed" and status != "researching":
			return false
	return true

# GameNetwork.advance_turn() just cycles player_order by one position — it
# doesn't know who's already passed, so left alone it can hand control right
# back to a player who's done for the round (e.g. with only one other
# player still going, it would just ping-pong between them). Skip anyone
# whose status is "passed" until landing on someone still eligible to act;
# _all_players_done_this_round() being false at the call site guarantees
# at least one such player exists.
func _advance_turn_skipping_passed() -> void:
	var guard: int = GameNetwork.player_order.size()
	while guard > 0:
		GameNetwork.advance_turn()
		if _opp_statuses.get(GameNetwork.active_peer_id, "") != "passed":
			return
		guard -= 1

func _server_handle_pass() -> void:
	_rpc_sync_opp_status.rpc(GameNetwork.active_peer_id, "passed")
	if _all_players_done_this_round():
		_rpc_sync_end_round.rpc()
	else:
		_advance_turn_skipping_passed()
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
	# A "researching" status only reflects that player's most recent turn —
	# unlike "passed" (permanent for the round), it must not stick around
	# once they're back up to act again, or a stale status from a prior
	# research could make _all_players_done_this_round() think this fresh
	# turn is already done before they've decided anything on it.
	if _opp_statuses.get(peer_id, "") == "researching":
		_opp_statuses[peer_id] = ""
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
		BotTurn.run_bot_turn(self, peer_id)

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
					BotTurn.run_bot_turn(self, GameNetwork.active_peer_id)
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
			var bot_state: Dictionary = BotTurn.get_bot_snapshot(self, bot_id)
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
	_auction_starting = false
	_show_action_buttons(false)
	UIAudio.play_auction_music()
	if multiplayer.is_server() and GameNetwork.is_bot(active_id):
		var _ab1: int = active_id
		get_tree().create_timer(0.6).timeout.connect(func() -> void: BotTurn.bot_decide_bid(self, _ab1))

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
		get_tree().create_timer(0.6).timeout.connect(func() -> void: BotTurn.bot_decide_bid(self, _ab2))

# Host → All: auction resolved — winner places the card.
@rpc("authority", "reliable", "call_local")
func _rpc_sync_auction_won(initiator_id: int, winner_id: int, final_bid: int, card_ref: Dictionary, _slot_idx: int, _is_tech: bool, cost_color_int: int) -> void:
	_auction_active = false
	_auction_starting = false
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

# ── Interfleet Comms RPCs ─────────────────────────────────────────────────────
# Host-authoritative pass-around: draw N (N = player count) into a shared
# pool, each player in turn order (starting at whoever placed the card)
# picks one, the last player automatically gets whatever's left. Mirrors the
# auction RPC pattern above — a rotating mini-sequence independent of whose
# real game-turn it is.

# Client → Host: I placed Interfleet Comms; draw the shared pool and start.
@rpc("any_peer", "reliable")
func _rpc_request_interfleet() -> void:
	if not multiplayer.is_server():
		return
	_server_start_interfleet(multiplayer.get_remote_sender_id())

# Client → Host: I'm keeping the pool card at this index.
@rpc("any_peer", "reliable")
func _rpc_request_interfleet_pick(idx: int) -> void:
	if not multiplayer.is_server():
		return
	_server_handle_interfleet_pick(multiplayer.get_remote_sender_id(), idx)

# Host → All: sequence started — full pool, full pick order, who triggered it.
@rpc("authority", "reliable", "call_local")
func _rpc_sync_interfleet_started(pool_refs: Array, order: Array, initiator_id: int) -> void:
	_interfleet_pool_refs = pool_refs.duplicate()
	_interfleet_remaining_order = []
	for v: Variant in order:
		_interfleet_remaining_order.append(int(v))
	_interfleet_initiator_id = initiator_id
	_interfleet_active = true
	_effect_mode = EffectMode.EFFECT_INTERFLEET_PICK
	var iname: String = GameNetwork.player_names.get(initiator_id, "Player")
	_log_action("%s: Interfleet Comms — drew %d card(s) to pass around" % [iname, _interfleet_pool_refs.size()], Color(0.6, 0.85, 1.0))
	if not _interfleet_remaining_order.is_empty():
		_update_interfleet_ui(_interfleet_remaining_order[0])

# Host → All: pool/order changed after a pick (still 2+ players left to serve).
@rpc("authority", "reliable", "call_local")
func _rpc_sync_interfleet_state(pool_refs: Array, order: Array) -> void:
	_interfleet_pool_refs = pool_refs.duplicate()
	_interfleet_remaining_order = []
	for v: Variant in order:
		_interfleet_remaining_order.append(int(v))
	if not _interfleet_remaining_order.is_empty():
		_update_interfleet_ui(_interfleet_remaining_order[0])

# Host → All: a specific player kept a specific card.
@rpc("authority", "reliable", "call_local")
func _rpc_sync_interfleet_pick_result(peer_id: int, card_ref: Dictionary) -> void:
	var my_id: int = multiplayer.get_unique_id()
	var cd: CardData = CardRef.from_ref(card_ref)
	if my_id == peer_id:
		if cd:
			$Board.add_specific_card_to_hand(cd)
			_log_action("You kept %s (Interfleet Comms)" % cd.card_name, Color(0.6, 1.0, 0.6))
		_broadcast_my_state()
	elif multiplayer.is_server() and GameNetwork.is_bot(peer_id):
		if cd:
			var hand: Array[CardData] = BotTurn.bot_hand(self, peer_id)
			hand.append(cd)
			BotTurn.bot_set_hand(self, peer_id, hand)
	else:
		var pname: String = GameNetwork.player_names.get(peer_id, "Player")
		_log_action("%s kept a card (Interfleet Comms)" % pname, Color(0.6, 0.85, 1.0))

# Host → All: sequence complete — the last player auto-received the final
# card; resumes the initiator's own effect queue.
@rpc("authority", "reliable", "call_local")
func _rpc_sync_interfleet_finished(recipient_id: int, card_ref: Dictionary, initiator_id: int) -> void:
	_interfleet_active = false
	_interfleet_awaiting_pick = false
	_hide_effect_hint()
	_choice_popup.hide()
	if _effect_mode == EffectMode.EFFECT_INTERFLEET_PICK:
		_effect_mode = EffectMode.NONE
	var my_id: int = multiplayer.get_unique_id()
	var cd: CardData = CardRef.from_ref(card_ref)
	if my_id == recipient_id:
		if cd:
			$Board.add_specific_card_to_hand(cd)
		_broadcast_my_state()
	elif multiplayer.is_server() and GameNetwork.is_bot(recipient_id):
		if cd:
			var hand: Array[CardData] = BotTurn.bot_hand(self, recipient_id)
			hand.append(cd)
			BotTurn.bot_set_hand(self, recipient_id, hand)
	var rname: String = GameNetwork.player_names.get(recipient_id, "Player")
	_log_action("%s automatically received the last Interfleet Comms card" % rname, Color(0.6, 0.85, 1.0))
	if my_id == initiator_id:
		_process_next_effect()

# ── "Every player draws" RPCs (Gas Cloud) ─────────────────────────────────────
# The tech deck is now a shared resource (see _server_deal_hands_to_real_peers)
# — every player independently drawing from what they each think is the same
# undiverged deck would race and could hand out duplicate cards. Host draws
# the whole batch once and distributes named cards explicitly instead.

# Client → Host: I placed a "draw_all_players" card; deal it for everyone.
@rpc("any_peer", "reliable")
func _rpc_request_draw_all_players(count: int, source: String) -> void:
	if not multiplayer.is_server():
		return
	_server_handle_draw_all_players(count, multiplayer.get_remote_sender_id(), source)

# Host-only: deal to real peers via the shared hand-delivery mechanism, deal
# to bots inline (their own separate, non-networked path), then tell
# everyone it's done so the initiator's effect queue can resume.
func _server_handle_draw_all_players(count: int, initiator_id: int, source: String) -> void:
	_server_deal_hands_to_real_peers(count)
	for bot_id: int in GameNetwork.bot_ids:
		BotTurn.apply_bot_effect_steps(self, bot_id, [{type = "draw", count = count}])
	BotTurn.broadcast_bot_states(self)
	_rpc_sync_draw_all_finished.rpc(initiator_id, source, count)

# Host → All: the draw-for-everyone is complete — log it once, and resume the
# initiator's own effect queue if it's still waiting on this.
@rpc("authority", "reliable", "call_local")
func _rpc_sync_draw_all_finished(initiator_id: int, source: String, count: int) -> void:
	_log_action("%s: everyone draws %d card(s)" % [source, count], Color(0.6, 0.85, 0.75))
	if _effect_mode == EffectMode.EFFECT_AWAITING_ALL_DRAW and multiplayer.get_unique_id() == initiator_id:
		_effect_mode = EffectMode.NONE
		_process_next_effect()

func _server_start_interfleet(initiator_id: int) -> void:
	var order: Array[int] = GameNetwork.player_order.duplicate()
	var start_pos: int = maxi(order.find(initiator_id), 0)
	var n: int = order.size()
	var rotated: Array[int] = []
	for j: int in n:
		rotated.append(order[(start_pos + j) % n])
	var drawn: Array[CardData] = $Board.draw_card_data(n)
	if drawn.size() < n:
		rotated = rotated.slice(0, drawn.size())
	var pool_refs: Array = []
	for cd: CardData in drawn:
		pool_refs.append(CardRef.to_ref(cd))
	_interfleet_initiator_id = initiator_id
	_interfleet_remaining_order = rotated
	_interfleet_pool_refs = pool_refs
	_interfleet_active = true
	_rpc_sync_interfleet_started.rpc(pool_refs, rotated, initiator_id)
	_server_interfleet_advance()

func _server_interfleet_advance() -> void:
	if _interfleet_remaining_order.size() <= 1:
		_server_finish_interfleet()
		return
	var active_id: int = _interfleet_remaining_order[0]
	_rpc_sync_interfleet_state.rpc(_interfleet_pool_refs, _interfleet_remaining_order)
	if GameNetwork.is_bot(active_id):
		var _bid: int = active_id
		get_tree().create_timer(0.6).timeout.connect(func() -> void: BotTurn.bot_decide_interfleet_pick(self, _bid))

func _server_handle_interfleet_pick(peer_id: int, idx: int) -> void:
	if _interfleet_remaining_order.is_empty() or peer_id != _interfleet_remaining_order[0]:
		return
	if idx < 0 or idx >= _interfleet_pool_refs.size():
		return
	var chosen_ref: Dictionary = _interfleet_pool_refs[idx]
	_interfleet_pool_refs.remove_at(idx)
	_interfleet_remaining_order.remove_at(0)
	_rpc_sync_interfleet_pick_result.rpc(peer_id, chosen_ref)
	_server_interfleet_advance()

func _server_finish_interfleet() -> void:
	var recipient_id: int = _interfleet_remaining_order[0] if not _interfleet_remaining_order.is_empty() else _interfleet_initiator_id
	var card_ref: Dictionary = _interfleet_pool_refs[0] if not _interfleet_pool_refs.is_empty() else {}
	var initiator_id: int = _interfleet_initiator_id
	_interfleet_remaining_order = []
	_interfleet_pool_refs = []
	_interfleet_active = false
	_rpc_sync_interfleet_finished.rpc(recipient_id, card_ref, initiator_id)

# Shown only to the active picker (a mandatory choice, no skip); everyone
# else sees the existing effect-hint panel — same "your turn" vs. "waiting"
# framing the sector-reveal flow already uses, no new UI nodes needed.
func _update_interfleet_ui(active_id: int) -> void:
	var my_id: int = multiplayer.get_unique_id()
	if my_id == active_id:
		var pool: Array[CardData] = []
		for ref: Dictionary in _interfleet_pool_refs:
			var cd: CardData = CardRef.from_ref(ref)
			if cd:
				pool.append(cd)
		_interfleet_awaiting_pick = true
		_hide_effect_hint()
		_choice_popup.show_card_choices("Interfleet Comms — keep one card:", pool, false)
	else:
		_interfleet_awaiting_pick = false
		_choice_popup.hide()
		var pname: String = GameNetwork.player_names.get(active_id, "Player")
		_show_effect_hint("Waiting for %s to pick a card (Interfleet Comms)…" % pname)

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
			if _tutorial:
				_tutorial.notify_researched()
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


func _recycle_card_to_supply(card: Node3D, color: CardData.SupplyColor) -> void:
	var screen_pos: Vector2 = $Camera3D.unproject_position(card.global_position)
	_cs_display.animate_supply_incoming(screen_pos, color)
	$Hand.remove_card_fly_out(card)

func _on_card_right_clicked_free_recycle(card: Node3D) -> void:
	if _effect_mode != EffectMode.NONE:
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
			var recycled_name: String = card.card_data.card_name if card.card_data else "a card"
			_cs_display.add_supply(color, 1)
			_apply_recycle_bonus(color)
			$Board.add_to_discard(card.card_data)
			_recycle_card_to_supply(card, color)
			_log_effect("recycled %s, gained 1 %s" % [recycled_name, CardData.color_name(color)])
			_effect_remaining -= 1
			if _effect_remaining <= 0:
				_finish_interactive_step()
			else:
				_show_hand_popup("Recycle %d more card(s)" % _effect_remaining, false)

		EffectMode.EFFECT_RECYCLE_OPTIONAL:
			var color: CardData.SupplyColor = card.card_data.color if card.card_data else CardData.SupplyColor.DUST
			var recycled_name: String = card.card_data.card_name if card.card_data else "a card"
			_cs_display.add_supply(color, 1)
			_apply_recycle_bonus(color)
			$Board.add_to_discard(card.card_data)
			_recycle_card_to_supply(card, color)
			$Board.draw_cards(1)
			_log_effect("recycled %s, gained 1 %s, drew 1" % [recycled_name, CardData.color_name(color)])
			_effect_remaining -= 1
			if _effect_remaining <= 0:
				_finish_interactive_step()
			else:
				_show_hand_popup("Recycle up to %d more card(s)" % _effect_remaining, true)

		EffectMode.EFFECT_TUCK:
			var tucked_name: String = card.card_data.card_name if card.card_data else "a card"
			if _effect_slot and card.card_data:
				_effect_slot.add_tucked_card(card.card_data, _effect_face_up)
			$Hand.remove_card_fly_out(card)
			var face_str_log: String = "faceup" if _effect_face_up else "facedown"
			_log_effect("tucked %s %s under the sector" % [tucked_name, face_str_log])
			_effect_remaining -= 1
			if _effect_remaining <= 0:
				_finish_interactive_step()
			else:
				var face_str: String = "faceup" if _effect_face_up else "facedown"
				_show_hand_popup("Tuck %d more card(s) %s" % [_effect_remaining, face_str], false)

		EffectMode.EFFECT_TUCK_OPTIONAL:
			var tucked_name: String = card.card_data.card_name if card.card_data else "a card"
			if _effect_slot and card.card_data:
				_effect_slot.add_tucked_card(card.card_data, _effect_face_up)
			$Hand.remove_card_fly_out(card)
			$Board.draw_cards(1)
			var face_str_log_opt: String = "faceup" if _effect_face_up else "facedown"
			_log_effect("tucked %s %s under the sector, drew 1" % [tucked_name, face_str_log_opt])
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
			var rt_name: String = card.card_data.card_name if card.card_data else "a card"
			_cs_display.add_supply(color, 1)
			_apply_recycle_bonus(color)
			if _effect_slot and card.card_data:
				_effect_slot.add_tucked_card(card.card_data, false)
			_recycle_card_to_supply(card, color)
			_log_effect("recycled & tucked %s facedown, gained 1 %s" % [rt_name, CardData.color_name(color)])
			_effect_remaining -= 1
			if _effect_remaining <= 0:
				var tucked_count: int = int(_effect_slot.tucked_cards.size()) if _effect_slot else 0
				$Board.draw_cards(tucked_count)
				_log_effect("drew %d card(s)" % tucked_count)
				_finish_interactive_step()
			else:
				_show_hand_popup("Recycle & tuck %d more card(s) facedown" % _effect_remaining, false)

		EffectMode.EFFECT_RECYCLE_DOUBLE:
			var color: CardData.SupplyColor = card.card_data.color if card.card_data else CardData.SupplyColor.DUST
			var rd_name: String = card.card_data.card_name if card.card_data else "a card"
			_cs_display.add_supply(color, 2)
			_apply_recycle_bonus(color)
			$Board.add_to_discard(card.card_data)
			_recycle_card_to_supply(card, color)
			_log_effect("recycled %s, gained 2 %s" % [rd_name, CardData.color_name(color)])
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
	_tuck_optional_no_bonus_draw = false
	_pending_tuck_card_data = null
	_pending_target_slot = null
	_effect_label = ""
	_caldera_slots = []
	_interfleet_awaiting_pick = false
	_effect_done_btn.hide()
	_choice_popup.hide()
	_hide_effect_hint()
	$Hand.set_discard_mode(false)
	$Board.set_sector_reveal_mode(false)
	$Board.set_expedition_reveal_mode(false)
	$Board.set_expedition_shuffle_mode(false)
	$Board.set_cargo_click_mode(false)

func _finish_interactive_step() -> void:
	_reset_effect_state()
	_process_next_effect()

func _on_effect_done_pressed() -> void:
	if _effect_mode == EffectMode.EFFECT_EXPEDITION_SHUFFLE:
		_finish_expedition_shuffle()
	else:
		_finish_interactive_step()

func _on_choice_made(index: int) -> void:
	if _interfleet_awaiting_pick:
		_interfleet_awaiting_pick = false
		if GameNetwork.is_host:
			_server_handle_interfleet_pick(multiplayer.get_unique_id(), index)
		else:
			_rpc_request_interfleet_pick.rpc_id(1, index)
		return
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
	var count: int = 0
	for i: int in indices:
		if i >= _pending_recycle_cards.size():
			continue
		var card: Node3D = _pending_recycle_cards[i]
		var color: CardData.SupplyColor = card.card_data.color if card.card_data else CardData.SupplyColor.DUST
		if _effect_slot:
			_effect_slot.add_stored_supply(color, 1)
		$Hand.remove_card_fly_out(card)
		count += 1
	_pending_recycle_cards = []
	if count > 0:
		_log_effect("recycled %d card(s), stored their supplies on the sector" % count)
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
		_log_effect("recycled %d card(s), drew %d" % [count, count])
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
	if count > 0:
		if not _restrict_picks_to_drawn and not _tuck_optional_no_bonus_draw:
			$Board.draw_cards(count)
			_log_effect("tucked %d card(s), drew %d" % [count, count])
		else:
			_log_effect("tucked %d card(s)" % count)
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
		_log_effect("recycled & tucked %d card(s) facedown, drew %d" % [count, count])
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
	var count: int = _pending_store_nodes.size()
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
	if count > 0:
		var dest_str: String = "stored their supply on the sector" if store_on_sector else "gained their supply as currency"
		_log_effect("recycled & tucked %d card(s) facedown, %s" % [count, dest_str])
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
	var count: int = 0
	for i: int in indices:
		if i >= _pending_recycle_cards.size():
			continue
		var card: Node3D = _pending_recycle_cards[i]
		var cd: CardData = card.get("card_data") as CardData
		if cd:
			_pending_target_slot.add_stored_supply(cd.color, 1)
		_pending_target_slot.remove_tech_card(card)
		card.queue_free()
		count += 1
	_pending_recycle_cards = []
	_pending_target_slot.compact_tech_cards()
	_pending_target_slot.refresh_display()
	_pending_target_slot = null
	if count > 0:
		_log_effect("recycled %d card(s) on the chosen sector, stored their supplies" % count)
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
		EffectMode.EFFECT_STORE_ON_SECTOR:
			if slot.occupied:
				_sector_picker.hide()
				slot.add_stored_supply(_pending_store_color, _pending_store_amount)
				_log_effect("stored %d %s on the chosen sector" % [_pending_store_amount, CardData.color_name(_pending_store_color)])
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
					var face_str_any_log: String = "faceup" if _effect_face_up else "facedown"
					_log_effect("tucked %s %s on the chosen sector" % [_pending_tuck_card_data.card_name, face_str_any_log])
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

func _on_cargo_move_requested(source: SectorSlot, dest: SectorSlot, supplies: Dictionary, tucked_indices: Array[int]) -> void:
	for color: int in supplies:
		var amount: int = supplies[color]
		var cur: int = source.stored_supply.get(color, 0)
		var remaining: int = cur - amount
		if remaining <= 0:
			source.stored_supply.erase(color)
		else:
			source.stored_supply[color] = remaining
		dest.add_stored_supply(color as CardData.SupplyColor, amount)
	source.refresh_display()
	var sorted_tucked: Array[int] = tucked_indices.duplicate()
	sorted_tucked.sort()
	sorted_tucked.reverse()
	for idx: int in sorted_tucked:
		if idx < source.tucked_cards.size():
			var entry: Dictionary = source.tucked_cards[idx]
			source.tucked_cards.remove_at(idx)
			dest.tucked_cards.append(entry)
	source.refresh_display()
	dest.refresh_display()
	var moved_supply_parts: Array[String] = []
	for color: int in supplies:
		moved_supply_parts.append("%d %s" % [supplies[color], CardData.color_name(color as CardData.SupplyColor)])
	var move_desc: String = ", ".join(moved_supply_parts) if not moved_supply_parts.is_empty() else ""
	if not move_desc.is_empty() and sorted_tucked.size() > 0:
		_log_effect("moved %s and %d tucked card(s) between sectors" % [move_desc, sorted_tucked.size()])
	elif not move_desc.is_empty():
		_log_effect("moved %s between sectors" % move_desc)
	elif sorted_tucked.size() > 0:
		_log_effect("moved %d tucked card(s) between sectors" % sorted_tucked.size())

# Auto-revealed cards (Ice Mining, Ancient Airlock, Cargo Bays, etc.) only
# ever show as a tiny market-panel icon otherwise — this shows the just-
# revealed card enlarged to fill the info screen for a beat, then shrinks it
# away and only then advances the effect queue, so it shrinks right before
# the next thing needing the screen (another reveal prompt, or the follow-up
# bid-choice popup) rather than fighting it for space. _effect_mode is held
# at EFFECT_REVEAL_DISPLAY (not NONE) for the duration so the player can't
# sneak in an unrelated market purchase while the big card is showing.
const REVEAL_BIG_DISPLAY_DURATION := 1.4

func _show_reveal_big_then_continue(slot_type: String, slot_idx: int, cd: CardData) -> void:
	if not cd:
		_effect_mode = EffectMode.NONE
		_process_next_effect()
		return
	_effect_mode = EffectMode.EFFECT_REVEAL_DISPLAY
	var origin: Vector3 = CockpitRig.viewport_to_world(self, _market_panel.get_slot_center(slot_type, slot_idx))
	var screen_center: Vector3 = CockpitRig.viewport_to_world(self, Vector2(_info_viewport.size) * 0.5)
	var screen_size: Vector2 = CockpitRig.info_screen_world_size(self)
	$Board.show_revealed_card_big(cd, slot_type == "advanced", origin, screen_center, screen_size)
	get_tree().create_timer(REVEAL_BIG_DISPLAY_DURATION).timeout.connect(func() -> void:
		$Board.dismiss_reveal_display()
		_effect_mode = EffectMode.NONE
		_process_next_effect()
	)

func _on_sector_revealed(card_data: CardData, slot_idx: int) -> void:
	if GameNetwork.is_multiplayer:
		if GameNetwork.is_host:
			_server_sync_sector_reveal(slot_idx, 1)
		else:
			_rpc_notify_sector_revealed.rpc_id(1, slot_idx)
	_hide_effect_hint()
	$Board.set_sector_reveal_mode(false)
	var reveal_name: String = card_data.card_name if card_data else "a card"
	var reveal_outcome_parts: Array[String] = ["revealed %s" % reveal_name]
	if _pending_reveal_gain_supply and card_data:
		_cs_display.add_supply(card_data.adv_color, 1)
		reveal_outcome_parts.append("gained 1 %s" % CardData.color_name(card_data.adv_color))
	if _pending_reveal_may_bid and card_data:
		_reveal_bid_pool.append(card_data)
		reveal_outcome_parts.append("added it to the bid pool")
	if _pending_reveal_may_free_gain and card_data:
		_reveal_free_pool.append(card_data)
		reveal_outcome_parts.append("added it to the free-gain pool")
	_log_effect(", ".join(reveal_outcome_parts))
	_pending_reveal_gain_supply = false
	_pending_reveal_may_bid = false
	_pending_reveal_may_free_gain = false
	_show_reveal_big_then_continue("advanced", slot_idx, card_data)

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
	$Board.refresh_hand_discounts()
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
		var is_adv: bool = bool(card.get("is_advanced"))
		var always_first: Array = []; always_first.append_array(always_steps); always_first.append_array(place_steps)
		var card_first: Array = []; card_first.append_array(place_steps); card_first.append_array(always_steps)
		_pending_choice_options = [
			{steps = always_first},
			{steps = card_first},
		]
		_effect_mode = EffectMode.EFFECT_CHOICE
		var always_source_name: String = str(always_steps[0].get("_source_name", ""))
		var always_cd: CardData = _find_card_data_by_name(always_source_name)
		if always_cd:
			_choice_popup.show_card_choices("Two effects triggered — resolve which first?",
				[always_cd, cd], false, [false, is_adv])
		else:
			var card_name: String = cd.adv_name if is_adv and not cd.adv_name.is_empty() else cd.card_name
			_choice_popup.show_choices("Two effects triggered — resolve which first?", ["Sector effects", card_name], false)
		return

	_effect_queue.append_array(always_steps)
	_effect_queue.append_array(place_steps)
	_process_next_effect()

# Always-effect source cards (Insects, Crops, 1-G Thrust, Einstein-Rosen
# Portal, etc.) are always techs or expeditions, never sectors.
func _find_card_data_by_name(card_name: String) -> CardData:
	if card_name.is_empty():
		return null
	for cd: CardData in CardDatabase.techs:
		if cd.card_name == card_name:
			return cd
	for cd: CardData in CardDatabase.expeditions:
		if cd.card_name == card_name:
			return cd
	return null

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
	_effect_source_name = str(step.get("_source_name", "Effect"))
	match step.get("type", ""):

		"draw":
			var _before: Array[Node3D] = $Hand.get_cards()
			$Board.draw_cards(int(step.get("count", 0)))
			var _after: Array[Node3D] = $Hand.get_cards()
			_last_drawn_cards = _after.filter(func(c: Node3D) -> bool: return not _before.has(c))
			_log_effect("drew %d card(s)" % _last_drawn_cards.size())
			_process_next_effect()

		"draw_recycle_top":
			# Lambdas capture locals by value, so plain reassignment inside one
			# never reaches the outer variable — box it in an Array (captured by
			# reference) so the connected callback can actually report back.
			var recycled_color_box: Array = [null]
			var capture_color: Callable = func(c: CardData.SupplyColor) -> void: recycled_color_box[0] = c
			$Board.card_recycled.connect(capture_color, CONNECT_ONE_SHOT)
			$Board.draw_and_recycle_top()
			if $Board.card_recycled.is_connected(capture_color):
				$Board.card_recycled.disconnect(capture_color)
			if recycled_color_box[0] != null:
				_log_effect("drew and recycled the top card, gained 1 %s" % CardData.color_name(recycled_color_box[0] as CardData.SupplyColor))
			else:
				_log_effect("drew and recycled the top card")
			_process_next_effect()

		"gain_supply":
			var gs_color: CardData.SupplyColor = step["color"] as CardData.SupplyColor
			var gs_amount: int = int(step.get("amount", 0))
			_cs_display.add_supply(gs_color, gs_amount)
			_log_effect("gained %d %s" % [gs_amount, CardData.color_name(gs_color)])
			_process_next_effect()

		"store_on_slot":
			if _effect_slot:
				var ss_color: CardData.SupplyColor = step["color"] as CardData.SupplyColor
				var ss_amount: int = int(step.get("amount", 0))
				_effect_slot.add_stored_supply(ss_color, ss_amount)
				_log_effect("stored %d %s on the sector" % [ss_amount, CardData.color_name(ss_color)])
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
			_log_effect("gained %d %s" % [count, CardData.color_name(color)])
			_process_next_effect()

		"fuse_notice":
			var count: int = int(step.get("count", 0))
			_cs_display.add_fuse_1to1(count)
			_log_effect("granted %d fuse action(s)" % count)
			_process_next_effect()

		"fuse_dust_1to1":
			_cs_display.set_dust_fuse_1to1(true)
			_log_effect("granted a Dust fuse action")
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
			_effect_step_tuck_optional(step)

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

		"reveal_expedition":
			_pending_expedition_reveal_gain_supply = bool(step.get("gain_supply", false))
			_pending_expedition_reveal_may_bid = bool(step.get("may_bid", false))
			_effect_mode = EffectMode.EFFECT_REVEAL_EXPEDITION
			_show_effect_hint("Click an expedition slot in the Market panel to reveal it")
			$Board.set_expedition_reveal_mode(true)

		"reveal_expedition_slot":
			_effect_step_reveal_expedition_slot(step)

		"choice":
			_effect_step_choice(step)

		"reflectors_choice":
			_effect_step_reflectors_choice()

		"offer_bid_pool":
			_effect_step_offer_bid_pool()

		"offer_free_sector_gain":
			_effect_step_offer_free_sector_gain()

		"free_sector_gain":
			var cd: CardData = step.get("card_data") as CardData
			if not cd:
				_process_next_effect()
				return
			var card_node: Node3D = $Board.find_market_card(cd)
			if not card_node:
				_process_next_effect()
				return
			$Board.market_origin_3d = CockpitRig.effect_card_origin(self, card_node, cd)
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
			$Board.market_origin_3d = CockpitRig.effect_card_origin(self, card_node, cd)
			$Board.begin_revealed_card_bid(card_node)

		"seedbanks":
			_effect_step_seedbanks()

		"caldera_colony":
			_effect_step_caldera_colony()

		"cargo_drones":
			_effect_mode = EffectMode.EFFECT_CARGO_DRONES
			_cargo_drones_panel.start($Board.get_all_sector_slots())

		"interfleet_comms":
			_effect_step_interfleet_comms()

		"draw_all_players":
			_effect_step_draw_all_players(int(step.get("count", 1)))

		"offer_bid_any_expedition":
			_effect_step_offer_bid_any_expedition()

		"black_hole_encounter":
			_effect_step_black_hole_encounter()

		_:
			_process_next_effect()

# ── Effect step handlers (complex cases) ─────────────────────────────────────────

func _effect_step_tuck_optional(step: Dictionary) -> void:
	_effect_mode = EffectMode.EFFECT_TUCK_OPTIONAL
	_effect_remaining = int(step.get("max", 1))
	_effect_face_up = bool(step.get("face_up", false))
	_restrict_picks_to_drawn = bool(step.get("restrict_to_drawn", false))
	_tuck_optional_no_bonus_draw = bool(step.get("no_bonus_draw", false))
	var face_str_to: String = "faceup" if _effect_face_up else "facedown"
	var prompt_to: String
	if _restrict_picks_to_drawn:
		prompt_to = "Tuck up to %d of the drawn cards %s" % [_effect_remaining, face_str_to]
	elif _tuck_optional_no_bonus_draw:
		prompt_to = "Tuck up to %d card(s) %s" % [_effect_remaining, face_str_to]
	else:
		prompt_to = "Tuck up to %d card(s) %s — draw 1 per tucked" % [_effect_remaining, face_str_to]
	_show_hand_multiselect(prompt_to)

func _effect_step_reveal_expedition_slot(step: Dictionary) -> void:
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

func _effect_step_choice(step: Dictionary) -> void:
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

func _effect_step_reflectors_choice() -> void:
	if not _effect_slot:
		_process_next_effect()
		return
	var eligible_cards: Array[CardData] = []
	var eligible_steps: Array = []
	for card_node: Node3D in _effect_slot.get_all_placed_cards():
		var cd: CardData = card_node.get("card_data")
		# get_all_placed_cards() includes the sector itself (placed_card) —
		# exclude that (sectors have no place effect to copy) and Reflectors
		# itself, but allow both Tech AND Expedition place effects, since an
		# Expedition can occupy this same sector slot.
		if not cd or cd.card_type == CardData.CardType.SECTOR or cd.card_name == "Reflectors":
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

func _effect_step_offer_bid_pool() -> void:
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

# Unlike _effect_step_offer_bid_pool (only the card(s) this same effect just
# revealed), Probe Launcher's text is "you may bid on any expedition" — the
# pool is every expedition currently visible in the market, reveal or not.
func _effect_step_offer_bid_any_expedition() -> void:
	var pool: Array[CardData] = $Board.get_visible_expedition_cards()
	if pool.is_empty():
		_process_next_effect()
		return
	_pending_choice_options = []
	for cd: CardData in pool:
		_pending_choice_options.append({steps = [{type = "initiate_market_bid", card_data = cd}]})
	_effect_mode = EffectMode.EFFECT_CHOICE
	_choice_popup.show_card_choices("Probe Launcher — bid on any expedition?", pool, true)

func _effect_step_offer_free_sector_gain() -> void:
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

func _effect_step_seedbanks() -> void:
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

func _effect_step_caldera_colony() -> void:
	_caldera_slots = []
	var caldera_cards: Array[CardData] = []
	var caldera_advanced_flags: Array[bool] = []
	for slot: SectorSlot in $Board.get_all_sector_slots():
		if not slot.occupied or not slot.placed_card or not slot.placed_card.card_data:
			continue
		_caldera_slots.append(slot)
		caldera_cards.append(slot.placed_card.card_data as CardData)
		caldera_advanced_flags.append(bool(slot.placed_card.get("is_advanced")))
	if caldera_cards.is_empty():
		_finish_interactive_step()
		return
	_effect_mode = EffectMode.EFFECT_CALDERA_SELECT_SECTOR
	_choice_popup.show_card_choices("Caldera Colony — choose a sector:", caldera_cards, true, caldera_advanced_flags)

# "Draw 1 per player, keep 1, then pass cards left" — needs real network sync
# since every other player must see and pick from the same shared pool. Async
# like reveal_sector/cargo_drones: does not call _process_next_effect() itself,
# that happens once the whole pass-around sequence resolves (see
# _rpc_sync_interfleet_finished).
func _effect_step_interfleet_comms() -> void:
	if not GameNetwork.is_multiplayer:
		$Board.draw_cards(1)
		_log_effect("drew 1 card (Interfleet Comms, solo)")
		_process_next_effect()
		return
	_effect_mode = EffectMode.EFFECT_INTERFLEET_PICK
	if GameNetwork.is_host:
		_server_start_interfleet(multiplayer.get_unique_id())
	else:
		_rpc_request_interfleet.rpc_id(1)

# "Every player draws 1" (Gas Cloud) — unlike Interfleet Comms there's no
# shared pool or picking, each player just draws from their own independent
# deck, but since a placed card's effect queue only ever runs on the placing
# player's own client, every other client still needs an explicit RPC to
# know to draw at all. Async like _effect_step_interfleet_comms: resumes via
# _rpc_sync_draw_all_finished once the deal completes.
func _effect_step_draw_all_players(count: int) -> void:
	if not GameNetwork.is_multiplayer:
		$Board.draw_cards(count)
		_log_effect("everyone draws %d card(s), solo" % count)
		_process_next_effect()
		return
	_effect_mode = EffectMode.EFFECT_AWAITING_ALL_DRAW
	var source: String = _effect_source_name if not _effect_source_name.is_empty() else "Effect"
	if GameNetwork.is_host:
		_server_handle_draw_all_players(count, 1, source)
	else:
		_rpc_request_draw_all_players.rpc_id(1, count, source)

func _effect_step_black_hole_encounter() -> void:
	_effect_mode = EffectMode.EFFECT_EXPEDITION_SHUFFLE
	_effect_remaining = 3
	_shuffle_count = 0
	_show_effect_hint("Click up to 3 expeditions to shuffle back — then click Done")
	_effect_done_btn.show()
	$Board.set_expedition_shuffle_mode(true)

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

# ── Tech deck sync (shared, finite deck across all players) ──────────────────
# The tech deck is a single shared resource across every client (see
# setup_tech_deck_ordered) — whoever draws/discards/reshuffles does it locally
# first, then relays a bare event so every other client's mirror replays the
# identical mutation. Mirrors the sector-reveal RPC triple above, except an
# explicit actor_id is used instead of GameNetwork.is_my_turn() to decide who
# skips replaying — tech draws aren't always tied to whoever's turn it is
# (bots, Interfleet Comms' auto-delivered final card), unlike sector reveals.

func _on_tech_card_drawn() -> void:
	if GameNetwork.is_multiplayer:
		if GameNetwork.is_host:
			_server_sync_tech_draw(1)
		else:
			_rpc_notify_tech_draw.rpc_id(1)

@rpc("any_peer", "reliable")
func _rpc_notify_tech_draw() -> void:
	if not multiplayer.is_server():
		return
	_server_sync_tech_draw(multiplayer.get_remote_sender_id())

func _server_sync_tech_draw(actor_id: int) -> void:
	if actor_id != 1:
		$Board.replay_tech_draw()
	_rpc_sync_tech_draw.rpc(actor_id)

@rpc("authority", "reliable")
func _rpc_sync_tech_draw(actor_id: int) -> void:
	if multiplayer.get_unique_id() == actor_id:
		return
	$Board.replay_tech_draw()

func _on_tech_card_discarded(cd: CardData) -> void:
	if GameNetwork.is_multiplayer:
		var card_ref: Dictionary = CardRef.to_ref(cd)
		if GameNetwork.is_host:
			_server_sync_tech_discard(card_ref, 1)
		else:
			_rpc_notify_tech_discard.rpc_id(1, card_ref)

@rpc("any_peer", "reliable")
func _rpc_notify_tech_discard(card_ref: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_server_sync_tech_discard(card_ref, multiplayer.get_remote_sender_id())

func _server_sync_tech_discard(card_ref: Dictionary, actor_id: int) -> void:
	if actor_id != 1:
		var cd: CardData = CardRef.from_ref(card_ref)
		if cd:
			$Board.replay_tech_discard(cd)
	_rpc_sync_tech_discard.rpc(card_ref, actor_id)

@rpc("authority", "reliable")
func _rpc_sync_tech_discard(card_ref: Dictionary, actor_id: int) -> void:
	if multiplayer.get_unique_id() == actor_id:
		return
	var cd: CardData = CardRef.from_ref(card_ref)
	if cd:
		$Board.replay_tech_discard(cd)

func _on_tech_deck_reshuffled(cards: Array[CardData]) -> void:
	if GameNetwork.is_multiplayer:
		var refs: Array = []
		for cd: CardData in cards:
			refs.append(CardRef.to_ref(cd))
		if GameNetwork.is_host:
			_server_sync_tech_reshuffle(refs, 1)
		else:
			_rpc_notify_tech_reshuffle.rpc_id(1, refs)

@rpc("any_peer", "reliable")
func _rpc_notify_tech_reshuffle(refs: Array) -> void:
	if not multiplayer.is_server():
		return
	_server_sync_tech_reshuffle(refs, multiplayer.get_remote_sender_id())

func _server_sync_tech_reshuffle(refs: Array, actor_id: int) -> void:
	if actor_id != 1:
		$Board.replay_tech_reshuffle(_tech_refs_to_cards(refs))
	_rpc_sync_tech_reshuffle.rpc(refs, actor_id)

@rpc("authority", "reliable")
func _rpc_sync_tech_reshuffle(refs: Array, actor_id: int) -> void:
	if multiplayer.get_unique_id() == actor_id:
		return
	$Board.replay_tech_reshuffle(_tech_refs_to_cards(refs))

func _tech_refs_to_cards(refs: Array) -> Array[CardData]:
	var result: Array[CardData] = []
	for ref: Variant in refs:
		var cd: CardData = CardRef.from_ref(ref as Dictionary)
		if cd:
			result.append(cd)
	return result

# Host-only. Draws count*N cards from the shared deck in one batch (each pop
# already fires tech_card_drawn above, keeping every mirror in sync) and
# delivers `count` of them to each REAL (non-bot) peer. Bots are each
# caller's own responsibility — round-start and Gas Cloud each already treat
# bot hands differently and would double-deal if this handled bots too.
# Used for cases where every player "acts" at the same moment (opening hand,
# round-start draw, Gas Cloud) — unlike a sequential per-turn draw, letting
# each client pop independently here would race and could hand out the same
# card to more than one player.
func _server_deal_hands_to_real_peers(count: int) -> void:
	var real_peers: Array[int] = []
	for peer_id: int in GameNetwork.player_order:
		if not GameNetwork.is_bot(peer_id):
			real_peers.append(peer_id)
	if real_peers.is_empty():
		return
	var drawn: Array[CardData] = $Board.draw_card_data(count * real_peers.size())
	var idx: int = 0
	for peer_id: int in real_peers:
		var refs: Array = []
		for _c: int in count:
			if idx < drawn.size():
				refs.append(CardRef.to_ref(drawn[idx]))
				idx += 1
		_rpc_sync_hand_dealt.rpc(peer_id, refs)

@rpc("authority", "reliable", "call_local")
func _rpc_sync_hand_dealt(peer_id: int, card_refs: Array) -> void:
	if multiplayer.get_unique_id() != peer_id:
		return
	var cards: Array[CardData] = []
	for ref: Variant in card_refs:
		var cd: CardData = CardRef.from_ref(ref as Dictionary)
		if cd:
			cards.append(cd)
	$Board.add_specific_cards_to_hand(cards)
	$Board.refresh_hand_discounts()
	_broadcast_my_state()

func _on_bid_confirmed(amount: int) -> void:
	if _pending_auction:
		_pending_auction = false
		_auction_starting = true
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
			var card: CardData = CardRef.from_ref(_pending_won_card_ref)
			if not $Board.begin_auction_win_drag(card):
				push_warning("AuctionWin: card not found in market")
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

func _on_market_sector_advanced_pressed(slot_idx: int) -> void:
	if _effect_mode != EffectMode.NONE:
		return
	$Board.market_origin_3d = CockpitRig.viewport_to_world(self, _market_panel.get_slot_center("advanced", slot_idx))
	$Board.begin_panel_sector_purchase(slot_idx, true)

func _on_market_sector_dust_pressed(slot_idx: int) -> void:
	if _effect_mode == EffectMode.EFFECT_REVEAL_SECTOR:
		$Board.reveal_sector_panel_slot(slot_idx)
	elif _effect_mode == EffectMode.NONE:
		$Board.market_origin_3d = CockpitRig.viewport_to_world(self, _market_panel.get_slot_center("dust", slot_idx))
		$Board.begin_panel_sector_purchase(slot_idx, false)

func _on_market_expedition_pressed(slot_idx: int) -> void:
	if _effect_mode == EffectMode.EFFECT_EXPEDITION_SHUFFLE:
		$Board.shuffle_expedition_panel_slot(slot_idx)
	elif _effect_mode == EffectMode.EFFECT_REVEAL_EXPEDITION:
		_execute_expedition_reveal(slot_idx)
	elif _effect_mode == EffectMode.NONE:
		$Board.market_origin_3d = CockpitRig.viewport_to_world(self, _market_panel.get_slot_center("expedition", slot_idx))
		$Board.begin_panel_expedition_purchase(slot_idx)

func _on_market_card_inspect_requested(slot_type: String, slot_idx: int) -> void:
	var origin: Vector3 = CockpitRig.viewport_to_world(self, _market_panel.get_slot_center(slot_type, slot_idx))
	var screen_center: Vector3 = CockpitRig.viewport_to_world(self, Vector2(_info_viewport.size) * 0.5)
	$Board.inspect_market_card(slot_type, slot_idx, origin, screen_center)

# Left-clicking the enlarged inspect card shrinks it, then buys it — same
# entry points and effect_mode/market_origin_3d handling as a direct
# market-panel click.
func _on_market_card_inspect_bought(slot_type: String, slot_idx: int) -> void:
	if _effect_mode != EffectMode.NONE:
		return
	$Board.market_origin_3d = CockpitRig.viewport_to_world(self, _market_panel.get_slot_center(slot_type, slot_idx))
	match slot_type:
		"dust":
			$Board.begin_panel_sector_purchase(slot_idx, false)
		"advanced":
			$Board.begin_panel_sector_purchase(slot_idx, true)
		"expedition":
			$Board.begin_panel_expedition_purchase(slot_idx)

func _on_market_card_hover_started(slot_type: String, slot_idx: int) -> void:
	var cd: CardData = null
	var is_adv: bool = false
	match slot_type:
		"dust":
			cd = $Board.get_market().get_dust_card_data(slot_idx)
		"advanced":
			cd = $Board.get_market().get_advanced_card_data(slot_idx)
			is_adv = true
		"expedition":
			cd = $Board.get_expedition_market().get_card_data(slot_idx)
	if not cd:
		return
	var card_name: String = cd.adv_name if is_adv and not cd.adv_name.is_empty() else cd.card_name
	var cost: int = CardData.effective_cost(cd, is_adv)
	var cost_color: CardData.SupplyColor = cd.adv_color if is_adv else cd.color
	var effect: String = cd.adv_effect_text if is_adv and not cd.adv_effect_text.is_empty() else cd.effect_text
	var desc_parts: Array[String] = []
	if not effect.is_empty():
		desc_parts.append(effect)
	desc_parts.append("Left-click to buy.")
	desc_parts.append("Right-click to enlarge.")
	_show_tooltip("%s — %d %s" % [card_name, cost, CardData.color_name(cost_color)], "\n".join(desc_parts))

func _on_supply_icon_hovered(color: int) -> void:
	var supply_color: CardData.SupplyColor = color as CardData.SupplyColor
	var count: int = _cs_display.get_supply(supply_color)
	var desc: String = "You have %d." % count
	var fuses_into: Array = SupplyUI.FUSE_MAP.get(color, [])
	if not fuses_into.is_empty():
		var dest_names: Array[String] = []
		for dst: int in fuses_into:
			dest_names.append(CardData.color_name(dst as CardData.SupplyColor))
		desc += " Fuses into %s." % ", ".join(dest_names)
	_show_tooltip(CardData.color_name(supply_color), desc)

func _execute_expedition_reveal(slot_idx: int) -> void:
	$Board.set_expedition_reveal_mode(false)
	_hide_effect_hint()
	var revealed: CardData = $Board.reveal_expedition_to_slot(slot_idx)
	var exp_reveal_parts: Array[String] = ["revealed %s" % (revealed.card_name if revealed else "a card")]
	if _pending_expedition_reveal_gain_supply and revealed:
		_cs_display.add_supply(revealed.color, 1)
		exp_reveal_parts.append("gained 1 %s" % CardData.color_name(revealed.color))
	if _pending_expedition_reveal_may_bid and revealed:
		_reveal_bid_pool.append(revealed)
		exp_reveal_parts.append("added it to the bid pool")
	_log_effect(", ".join(exp_reveal_parts))
	_pending_expedition_reveal_gain_supply = false
	_pending_expedition_reveal_may_bid = false
	if GameNetwork.is_multiplayer:
		if GameNetwork.is_host:
			_rpc_sync_expedition_reveal.rpc(slot_idx)
		else:
			_rpc_notify_expedition_reveal.rpc_id(1, slot_idx)
	_show_reveal_big_then_continue("expedition", slot_idx, revealed)

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
	_effect_mode = EffectMode.NONE
	_effect_remaining = 0
	_hide_effect_hint()
	_effect_done_btn.hide()
	if _shuffle_count > 0:
		_log_effect("shuffled %d expedition(s) back into the deck" % _shuffle_count)
	for _i: int in _shuffle_count:
		_effect_queue.insert(0, {type = "reveal_expedition", _source_name = _effect_source_name})
	_shuffle_count = 0
	_process_next_effect()

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
	if _auction_active or _auction_starting or _runner_up_phase or _pending_auction or _pending_auction_win:
		return
	if _pending_reveal_gain_supply or _pending_reveal_may_bid or _pending_reveal_may_free_gain:
		return
	if _cs_display.has_fuse_1to1_active():
		return
	if $Board.is_card_drag_pending():
		return
	_on_end_turn_pressed()

func _on_end_turn_pressed() -> void:
	if not GameNetwork.is_my_turn():
		return
	if not $Board.is_major_action_taken():
		return
	if _runner_up_phase:
		return
	if _effect_mode == EffectMode.EFFECT_INTERFLEET_PICK:
		return
	if _effect_mode == EffectMode.EFFECT_AWAITING_ALL_DRAW:
		return
	if $Board.is_card_drag_pending():
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
	if _all_players_done_this_round():
		_rpc_sync_end_round.rpc()
		return
	_advance_turn_skipping_passed()
	_rpc_sync_active_player.rpc(GameNetwork.active_peer_id)

@rpc("any_peer", "reliable")
func _rpc_request_end_turn() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != GameNetwork.active_peer_id:
		return
	_server_handle_end_turn()

func _on_supply_changed() -> void:
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
	music_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_music_player = AudioStreamPlayer.new()
	_music_player.stream = music_stream
	_music_player.bus = &"Music"
	add_child(_music_player)
	_music_player.play()

# ── Helpers ───────────────────────────────────────────────────────────────────

func _on_card_recycled(color: CardData.SupplyColor) -> void:
	UIAudio.play_recycle_sfx()
	_cs_display.add_supply(color, 1)
	_apply_recycle_bonus(color)

# A bought/won tech or expedition card had nowhere to go (every sector's tech
# slots were full) — Board already recycled it and card_recycled will credit
# its supply as usual; this just explains to the player why it vanished
# instead of asking them to place it.
func _on_unplaceable_card_recycled(card_data: CardData) -> void:
	var c_name: String = card_data.card_name if card_data else "Card"
	_show_auction_toast("No room to place %s — recycled instead" % c_name)
	_log_action("No room to place %s, recycled instead" % c_name, Color(1.0, 0.6, 0.4))
	_broadcast_my_state()

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

# Tutorial-only attention cue on the Pass console button — mirrors
# _start_end_turn_3d_flash()/_stop_end_turn_3d_flash() exactly, just
# retargeted, since there's no independent "disabled" concept for these
# 3D mesh buttons to hook into like the End Turn flash does.
func _start_pass_btn_3d_flash() -> void:
	if not _pass_btn_mesh:
		return
	if _pass_btn_flash_tween:
		_pass_btn_flash_tween.kill()
	var base: Material = _pass_btn_mesh.mesh.surface_get_material(0)
	var mat: StandardMaterial3D = (base as StandardMaterial3D).duplicate() as StandardMaterial3D if base is StandardMaterial3D else StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.6, 1.0)
	mat.emission_energy_multiplier = 0.0
	_pass_btn_flash_mat = mat
	_pass_btn_mesh.set_surface_override_material(0, mat)
	_pass_btn_flash_tween = create_tween().set_loops()
	_pass_btn_flash_tween.tween_property(mat, "emission_energy_multiplier", 2.5, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_pass_btn_flash_tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _stop_pass_btn_3d_flash() -> void:
	if _pass_btn_flash_tween:
		_pass_btn_flash_tween.kill()
		_pass_btn_flash_tween = null
	_pass_btn_flash_mat = null
	if _pass_btn_mesh:
		_pass_btn_mesh.set_surface_override_material(0, null)

# Tutorial-only attention cue on the Research console button — same shape
# as _start_pass_btn_3d_flash()/_stop_pass_btn_3d_flash().
func _start_research_btn_3d_flash() -> void:
	if not _research_btn_mesh:
		return
	if _research_btn_flash_tween:
		_research_btn_flash_tween.kill()
	var base: Material = _research_btn_mesh.mesh.surface_get_material(0)
	var mat: StandardMaterial3D = (base as StandardMaterial3D).duplicate() as StandardMaterial3D if base is StandardMaterial3D else StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.6, 1.0)
	mat.emission_energy_multiplier = 0.0
	_research_btn_flash_mat = mat
	_research_btn_mesh.set_surface_override_material(0, mat)
	_research_btn_flash_tween = create_tween().set_loops()
	_research_btn_flash_tween.tween_property(mat, "emission_energy_multiplier", 2.5, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_research_btn_flash_tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _stop_research_btn_3d_flash() -> void:
	if _research_btn_flash_tween:
		_research_btn_flash_tween.kill()
		_research_btn_flash_tween = null
	_research_btn_flash_mat = null
	if _research_btn_mesh:
		_research_btn_mesh.set_surface_override_material(0, null)
