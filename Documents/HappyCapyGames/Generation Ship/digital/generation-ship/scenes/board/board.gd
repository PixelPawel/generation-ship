extends Node3D

const DRAG_Y := 0.55
const HAND_CARD_SCALE := 0.392
const TECH_BACK_PATH := "res://assets/cards/tech/GS_Techs_Back_44x67mm.png"
const EXPEDITION_BACK_PATH := "res://assets/cards/expedition/GS_Expeditions_Back_44x67mm.png"
const DROP_RADIUS := 0.4
const TECH_COLUMN_HALF_X := 0.1
const PENDING_HOVER_Y := 0.05
const TECH_ZONE_Z_FRONT := 0.2
const TECH_ZONE_Z_BACK := 0.3
const MIN_SLOT_DISTANCE := 0.075
const _SLOT_SCENE := preload("res://scenes/board/sector_slot.tscn")
const _MARKET_CARD_ROTATION := Vector3(-PI / 2.0, 0.0, 0.0)
# How far the market-inspect clone travels from the clicked screen point
# toward the camera (0 = stays at the screen, 1 = ends up at the camera).
const INSPECT_CAMERA_PULL := 0.5
# How far past the screen (away from the camera) the clone travels while
# shrinking away on collapse, as a fraction of the camera-to-screen distance.
const INSPECT_VANISH_PULL := 0.4
# Card footprint at scale 1.0 (see Card.set_card_data's landscape swap) —
# portrait for tech/expedition cards, landscape (swapped) for sector cards.
const _CARD_PORTRAIT_SIZE := Vector2(0.63, 0.88)
# Leaves a small gap so an auto-revealed card's corners don't exactly touch
# the physical screen's edges when scaled up to fill it. Also folds in a 66%
# reduction from the true max-fill size — filling the whole screen read as
# way too large in practice.
const _REVEAL_FILL_MARGIN := 0.92 * 0.34

signal card_recycled(supply_color: CardData.SupplyColor)
signal unplaceable_card_recycled(card_data: CardData)
signal recycle_confirm_required(card: Node3D, color: CardData.SupplyColor)
signal major_action_changed(taken: bool)
signal market_card_taken(card_data: CardData)
signal bid_required(card: Node3D, slot: Node3D, min_cost: int, cost_color: CardData.SupplyColor, is_tech: bool)
signal payment_confirm_required(card: Node3D, slot: Node3D, pay_amounts: Dictionary, is_tech: bool)
signal placement_confirm_required(card: Node3D, slot: SectorSlot, is_tech: bool)
signal card_placed(card: Node3D, slot: SectorSlot)
signal optimize_triggered(slot: SectorSlot, level: int)
signal action_committed
signal sector_revealed(card_data: CardData, slot_idx: int)
signal market_card_drag_failed(card: Node3D)
signal expedition_card_shuffled_back(card_data: CardData, deck_insert_idx: int)
signal expedition_reveal_requested(slot_idx: int)
signal sector_info_requested(slot: SectorSlot)
signal tech_card_drawn
# Fires whenever the drag-targeting arrow becomes visible/hidden (either
# origin — hand or market). Hand listens to this to suppress hover-enlarge
# while it's up, since a drag's own mouse movement passing over other hand
# cards would otherwise pop them up too.
signal arrow_drag_changed(active: bool)
# Right-click during an auction win's targeting arrow — main.gd re-shows the
# bid payment panel (it already has the winning amount/card cached from the
# original bid) and hands the chosen allocation back via
# resume_auction_win_drag once confirmed.
signal auction_payment_cancel_requested
signal tech_deck_reshuffled(cards: Array[CardData])
signal tech_card_discarded(cd: CardData)

enum DragOrigin { NONE, HAND, MARKET }

var _hand: Node3D = null
var _dragged_card: Node3D = null
var _drag_origin: DragOrigin = DragOrigin.NONE
var market_origin_3d: Vector3 = Vector3.ZERO
var _drag_start_global_pos: Vector3 = Vector3.ZERO
var _drag_start_scale: Vector3 = Vector3.ONE
# A 2D screen-space "what am I holding" readout for a hand-origin drag only,
# shown next to the mouse cursor — reuses the same CanvasLayer as the drag
# arrow (see _ready()) since that's the only reliably-visible approach
# during a drag: a 3D clone placed at the info screen's own world position
# isn't actually in view most of the time (the camera's pointed at the
# board while aiming a drop, not at the info screen), which is why an
# earlier version of this (a static 3D clone resting on the info screen)
# went unseen in practice.
var _drag_preview_rect: TextureRect = null
var _major_action_taken: bool = false
var _effect_active: bool = false  # kept in sync by Main whenever _effect_mode changes — see set_effect_active()
var _supply_ui: Control = null
var _card_scene: PackedScene = null
var _inspecting_card: Node3D = null
var _reveal_display_card: Node3D = null
var _pending_card: Node3D = null
var _pending_recycle_card: Node3D = null
var _pending_slot: Node3D = null
var _pending_is_tech: bool = false
var _pending_pay_amounts: Dictionary = {}
var _pending_drag_origin: DragOrigin = DragOrigin.NONE
var _pending_cost: int = 0
var _is_free_gain: bool = false
var _is_prepaid_placement: bool = false
var _pending_dynamic_slot: SectorSlot = null
var _drag_arrow: DragArrow = null
var _is_arrow_drag: bool = false
var _is_auction_win_placement: bool = false
var _prepaid_spent_amounts: Dictionary = {}
var _prepaid_market_notified: bool = false
# Holds the dragged card while its bid-payment window is being redone (see
# _cancel_prepaid_to_payment/resume_auction_win_drag) — unlike the direct-
# purchase cancel path, an auction win can't just re-run _resolve_card_payment
# (the amount owed is the fixed winning bid, not a recomputed cost), so main.gd
# re-shows the bid payment panel and hands the same node back here once done.
var _cancelled_auction_card: Node3D = null
var _pending_placement_card: Node3D = null
var _pending_placement_slot: SectorSlot = null
var _pending_placement_is_tech: bool = false
var _pending_placement_origin: DragOrigin = DragOrigin.NONE
var _pending_placement_spent: Dictionary = {}
var _placement_confirm_pending: bool = false
@onready var _sector_row: Node3D = $SectorRow
@onready var _market: Node3D = $SectorMarket
@onready var _expedition_market: Node3D = $ExpeditionMarket
@onready var _tech_deck: Node3D = $TechDeck
@onready var _expedition_deck: Node3D = $ExpeditionDeck
@onready var _sector_deck: Node3D = $SectorDeck
@onready var _discard_pile: Node3D = $DiscardPile

func _ready() -> void:
	for slot: SectorSlot in _sector_row.get_children():
		slot.slot_clicked.connect(_on_sector_slot_clicked)
	_market.position.x += 15.0
	_expedition_market.position.x += 15.0
	var arrow_canvas: CanvasLayer = CanvasLayer.new()
	arrow_canvas.layer = 10
	add_child(arrow_canvas)
	_drag_arrow = DragArrow.new()
	arrow_canvas.add_child(_drag_arrow)

	_drag_preview_rect = TextureRect.new()
	_drag_preview_rect.custom_minimum_size = _DRAG_PREVIEW_SIZE
	_drag_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drag_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_drag_preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_preview_rect.visible = false
	var preview_mat: ShaderMaterial = ShaderMaterial.new()
	preview_mat.shader = load("res://shaders/card_rounded.gdshader") as Shader
	_drag_preview_rect.material = preview_mat
	arrow_canvas.add_child(_drag_preview_rect)

func _on_sector_slot_clicked(slot: SectorSlot) -> void:
	sector_info_requested.emit(slot)

func show_payment_confirm_arrow(from_2d: Vector2, to_2d: Vector2) -> void:
	if _drag_arrow:
		_drag_arrow.show_arrow(from_2d, to_2d)

func hide_payment_confirm_arrow() -> void:
	if _drag_arrow:
		_drag_arrow.hide_arrow()

func add_sector_slot(slot: SectorSlot) -> void:
	slot.reparent(_sector_row, true)
	if not slot.slot_clicked.is_connected(_on_sector_slot_clicked):
		slot.slot_clicked.connect(_on_sector_slot_clicked)

func _find_nearest_empty_sector_slot(max_dist: float = DROP_RADIUS) -> SectorSlot:
	var pos: Vector3 = _dragged_card.global_position
	var best: SectorSlot = null
	var best_dist: float = max_dist
	for slot: SectorSlot in _sector_row.get_children():
		if slot.occupied or not slot.is_available:
			continue
		var dx: float = pos.x - slot.global_position.x
		var dz: float = pos.z - slot.global_position.z
		var dist: float = sqrt(dx * dx + dz * dz)
		if dist < best_dist:
			best_dist = dist
			best = slot
	return best

func set_card_scene(scene: PackedScene) -> void:
	_card_scene = scene

func setup_tech_deck(cards: Array[CardData]) -> void:
	_tech_deck.setup(cards, TECH_BACK_PATH)

func setup_expedition_deck(cards: Array[CardData]) -> void:
	_expedition_deck.setup(cards, EXPEDITION_BACK_PATH)

func setup_market_ordered(sector_order: Array) -> void:
	_market.setup_ordered(_card_scene, CardDatabase.sectors, sector_order)
	_connect_market_signals()

func setup_expedition_deck_ordered(exp_order: Array) -> void:
	_expedition_deck.setup_ordered(CardDatabase.expeditions, exp_order, EXPEDITION_BACK_PATH)

func setup_tech_deck_ordered(tech_order: Array) -> void:
	_tech_deck.setup_ordered(CardDatabase.techs, tech_order, TECH_BACK_PATH)

func setup_sector_deck(cards: Array[CardData]) -> void:
	_sector_deck.setup(cards)

func setup_market() -> void:
	_market.setup(_card_scene, CardDatabase.sectors)
	_connect_market_signals()

func _connect_market_signals() -> void:
	if not _market.card_drag_started.is_connected(_on_market_card_drag_started):
		_market.card_drag_started.connect(_on_market_card_drag_started)
	if not _market.sector_revealed.is_connected(_on_market_sector_revealed):
		_market.sector_revealed.connect(_on_market_sector_revealed)

func get_sector_slots() -> Array[SectorSlot]:
	var result: Array[SectorSlot] = []
	for child: Node in _sector_row.get_children():
		var slot: SectorSlot = child as SectorSlot
		if slot:
			result.append(slot)
	return result

func set_sector_reveal_mode(active: bool) -> void:
	_market.set_reveal_mode(active)

func set_cargo_click_mode(active: bool) -> void:
	for slot: SectorSlot in _sector_row.get_children():
		if slot.occupied and slot.placed_card:
			slot.placed_card.can_drag = not active

func set_cards_can_elevate(enabled: bool) -> void:
	for slot: SectorSlot in _sector_row.get_children():
		for card: Node3D in slot.get_all_placed_cards():
			card.set("can_elevate", enabled)

func _on_market_sector_revealed(card_data: CardData, slot_idx: int) -> void:
	sector_revealed.emit(card_data, slot_idx)

func reveal_expedition_to_slot(slot_idx: int) -> CardData:
	return _expedition_market.reveal_to_slot(slot_idx)

func get_expedition_slot_sizes() -> Array[int]:
	return _expedition_market.get_slot_sizes()

func find_market_card(cd: CardData) -> Node3D:
	if cd.card_type == CardData.CardType.EXPEDITION:
		return _expedition_market.find_card(cd)
	var node: Node3D = _market.find_advanced_card(cd)
	if node:
		return node
	return _market.find_dust_card(cd)

func get_available_dust_sectors() -> Array[CardData]:
	var result: Array[CardData] = []
	for i: int in 3:
		var cd: CardData = _market.get_dust_card_data(i)
		if cd:
			result.append(cd)
	return result

# The top (clickable/biddable) card in each of the 3 expedition slots — what
# a player would actually see and be able to start an auction on right now.
# Used both for the normal market and for effects that offer a bid on any
# expedition (e.g. Probe Launcher) — older cards buried underneath a slot's
# current top aren't up for auction, so they're excluded here too.
func get_available_expeditions() -> Array[CardData]:
	var result: Array[CardData] = []
	for i: int in 3:
		var cd: CardData = _expedition_market.get_card_data(i)
		if cd:
			result.append(cd)
	return result

# Entry point for a card offered via an effect's bid pool (e.g. Ancient
# Airlock, Deep Space Radar, Cargo Bays) — these are always advanced sectors
# or expeditions, so always bid. Same left-click-then-bid, drag-to-place-after
# rule as the market panel: no destination slot is known yet.
func begin_revealed_card_bid(card: Node3D) -> void:
	var is_tech: bool = false
	if card.card_data and card.card_data.card_type == CardData.CardType.EXPEDITION:
		_expedition_market.detach_card(card)
		is_tech = true
	elif card.card_data and card.card_data.card_type == CardData.CardType.SECTOR:
		_market.detach_advanced_card(card)
	_drag_origin = DragOrigin.MARKET
	_begin_market_purchase(card, is_tech)

func begin_free_sector_gain(card: Node3D) -> void:
	if not GameNetwork.is_my_turn():
		return
	if card.is_advanced:
		_market.detach_advanced_card(card)
	else:
		var slot_idx: int = card.get_meta("market_slot", -1)
		if slot_idx >= 0:
			_market.detach_dust_card(slot_idx)
	_is_free_gain = true
	_drag_origin = DragOrigin.MARKET
	_begin_drag(card)

func get_market() -> Node3D:
	return _market

func get_expedition_market() -> Node3D:
	return _expedition_market

func begin_panel_sector_purchase(slot_idx: int, is_advanced: bool) -> void:
	if not GameNetwork.is_my_turn():
		return
	if _major_action_taken:
		return
	var card: Node3D
	if is_advanced:
		card = _market.get_advanced_top_node(slot_idx)
		if not card:
			return
		_market.detach_advanced_card(card)
	else:
		card = _market.detach_dust_card(slot_idx)
		if not card:
			return
	_drag_origin = DragOrigin.MARKET
	_begin_market_purchase(card, false)

func begin_panel_expedition_purchase(slot_idx: int) -> void:
	if not GameNetwork.is_my_turn() or _major_action_taken:
		return
	var card: Node3D = _expedition_market.detach_top_card(slot_idx)
	if not card:
		return
	_drag_origin = DragOrigin.MARKET
	_begin_market_purchase(card, true)

# Left-click entry point for market-panel purchases. No destination slot is
# known yet: bid/payment resolves first (slot=null throughout), and only once
# that's settled does _begin_prepaid_drag() let the player drag the card onto
# their board.
func _begin_market_purchase(card: Node3D, is_tech: bool) -> void:
	_dismiss_inspecting_card()
	_prepaid_market_notified = false
	if _should_bid(card):
		_start_bid(card, null, is_tech)
		return
	if not _resolve_card_payment(card, null, is_tech):
		return
	_begin_prepaid_drag(card)

# The real market/deck nodes sit far offscreen and are hidden (see
# SectorMarket/ExpeditionMarket in board.tscn) — moving the actual card would
# never make it visible, since visibility is inherited from that hidden
# ancestor no matter where the card itself is positioned. Instead, spawn a
# disposable clone parented directly under Board (which is visible) with the
# same data/art, and enlarge that; it self-destructs on collapse via
# Card.enlarge_from's _destroy_on_collapse flag. The real card never moves.
func inspect_market_card(slot_type: String, slot_idx: int, world_pos: Vector3, screen_center: Vector3) -> void:
	if _inspecting_card and is_instance_valid(_inspecting_card):
		return
	var source_card: Node3D
	match slot_type:
		"dust":
			source_card = _market.get_dust_display_node(slot_idx)
		"advanced":
			source_card = _market.get_advanced_top_node(slot_idx)
		"expedition":
			source_card = _expedition_market.get_top_node(slot_idx)
	if not source_card or not source_card.card_data:
		return
	var clone: Node3D = _card_scene.instantiate()
	add_child(clone)
	clone.is_advanced = source_card.is_advanced
	clone.set_card_data(source_card.card_data)
	clone.rotation = _MARKET_CARD_ROTATION
	clone.can_drag = false
	# The card emerges from wherever was actually clicked (world_pos), but
	# settles into a consistent reading spot centered in front of the screen
	# as a whole (screen_center) rather than centered on the camera's own
	# view axis, which wouldn't necessarily line up with the screen itself.
	var target: Vector3 = screen_center
	var vanish: Vector3 = world_pos
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam:
		target = screen_center.lerp(cam.global_position, INSPECT_CAMERA_PULL)
		var away_dir: Vector3 = (world_pos - cam.global_position).normalized()
		var dist: float = cam.global_position.distance_to(world_pos)
		vanish = world_pos + away_dir * (dist * INSPECT_VANISH_PULL)
	clone.enlarge_from(target, vanish, Vector3.ONE * _placed_card_enlarge_scale())
	_inspecting_card = clone
	# collapse_if_elevated()'s tween frees the clone once it finishes, but
	# nothing else clears this reference — every other read already guards
	# with is_instance_valid(), so a dangling pointer here is harmless in
	# practice, but leaving it dangling indefinitely (instead of nulling it
	# the moment the clone is actually gone) is fragile. Clear it as soon as
	# the clone leaves the tree, guarded so a newer clone (already inspecting
	# a different card by the time this old one finishes freeing) is never
	# clobbered by a stale callback.
	clone.tree_exited.connect(func() -> void:
		if _inspecting_card == clone:
			_inspecting_card = null
	)
	# Pulled toward the camera for readability (INSPECT_CAMERA_PULL), the
	# clone's own collider can end up spatially covering other market slots
	# behind it — since Godot's 3D click-picking delivers a click to only
	# the single closest collider along the ray, a left-click actually aimed
	# at, say, a dust sector could get swallowed by this clone instead,
	# silently re-triggering ITS OWN buy/bid flow (the wrong card) with no
	# way to back out. Making it unpickable removes it from ray-picking
	# entirely, so every click — on this same card's position or any other
	# slot — passes through to the real 2D market-panel button underneath,
	# which already dismisses this clone itself (_dismiss_inspecting_card,
	# called from _begin_market_purchase) as the first thing it does. See
	# _input() below for how right-click-to-shrink is preserved without it.
	clone.collider.input_ray_pickable = false

# Shrinks whatever card is currently enlarged from a market inspect, if any —
# called when the player's attention moves elsewhere (e.g. buying a
# different market card) so the old enlarged card doesn't get left stuck.
func _dismiss_inspecting_card() -> void:
	if _inspecting_card and is_instance_valid(_inspecting_card):
		_inspecting_card.collapse_if_elevated()

# Placed cards are children of a SectorSlot, which carries a ~0.15x scale
# baked into its transform (see SectorSlot1-6 in main.tscn) — an enlarged
# placed card ends up at that slot scale, not at the raw PLACED_LIFT_SCALE
# local value (Card.toggle_elevation's target scale is relative to the
# card's own parent). The inspect clone is parented directly under Board
# (no such reduction), so it needs this factor applied explicitly as its
# own target scale to end up the same size.
func _placed_card_enlarge_scale() -> float:
	if _sector_row.get_child_count() == 0:
		return 1.0
	var reference_slot: Node3D = _sector_row.get_child(0) as Node3D
	return reference_slot.global_transform.basis.get_scale().x

# Automatically shows a just-revealed card (Ice Mining, Ancient Airlock, Cargo
# Bays, etc.) enlarged as big as the physical info-screen can fit, so the
# player actually gets a moment to read it instead of only seeing the tiny
# market-panel icon update. Purely a visual moment — not clickable, unlike the
# right-click market-inspect clone — dismiss_reveal_display() shrinks it away
# again once the caller is ready to move on (e.g. right before the follow-up
# bid-choice popup needs the screen).
func show_revealed_card_big(cd: CardData, is_advanced: bool, world_pos: Vector3, screen_center: Vector3, screen_size: Vector2) -> void:
	dismiss_reveal_display()
	if not cd:
		return
	var clone: Node3D = _card_scene.instantiate()
	add_child(clone)
	clone.is_advanced = is_advanced
	clone.set_card_data(cd)
	clone.rotation = _MARKET_CARD_ROTATION
	clone.can_drag = false
	var target: Vector3 = screen_center
	var vanish: Vector3 = world_pos
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam:
		target = screen_center.lerp(cam.global_position, INSPECT_CAMERA_PULL)
		var away_dir: Vector3 = (world_pos - cam.global_position).normalized()
		var dist: float = cam.global_position.distance_to(world_pos)
		vanish = world_pos + away_dir * (dist * INSPECT_VANISH_PULL)
	var is_landscape: bool = cd.card_type == CardData.CardType.SECTOR
	clone.enlarge_from(target, vanish, Vector3.ONE * _max_fill_scale(screen_size, is_landscape))
	_reveal_display_card = clone

func _max_fill_scale(screen_size: Vector2, is_landscape: bool) -> float:
	if screen_size.x <= 0.0 or screen_size.y <= 0.0:
		return _placed_card_enlarge_scale()
	var card_size: Vector2 = Vector2(_CARD_PORTRAIT_SIZE.y, _CARD_PORTRAIT_SIZE.x) if is_landscape else _CARD_PORTRAIT_SIZE
	return min(screen_size.x / card_size.x, screen_size.y / card_size.y) * _REVEAL_FILL_MARGIN

# Shrinks the auto-revealed big-display card, if any is currently showing.
func dismiss_reveal_display() -> void:
	if _reveal_display_card and is_instance_valid(_reveal_display_card):
		_reveal_display_card.collapse_if_elevated()
	_reveal_display_card = null

func reveal_sector_panel_slot(slot_idx: int) -> void:
	_market.reveal_slot_panel(slot_idx)

func reveal_sector_round_cards() -> void:
	_market.reveal_round_cards()

func sync_market_reveal(slot_idx: int) -> void:
	_market.sync_reveal_slot(slot_idx)

func sync_expedition_shuffle_in(card_data: CardData, deck_insert_idx: int) -> void:
	_expedition_market.remove_card(card_data)
	_expedition_deck.insert_at(card_data, deck_insert_idx)

func sync_expedition_reveal(slot_idx: int) -> void:
	_expedition_market.reveal_to_slot(slot_idx)

func setup_expedition_market() -> void:
	_expedition_market.setup(_card_scene, _expedition_deck)
	if not _expedition_market.card_drag_started.is_connected(_on_market_card_drag_started):
		_expedition_market.card_drag_started.connect(_on_market_card_drag_started)
	if not _expedition_market.card_shuffled_back.is_connected(_on_expedition_card_shuffled_back):
		_expedition_market.card_shuffled_back.connect(_on_expedition_card_shuffled_back)
	if not _expedition_market.card_reveal_requested.is_connected(_on_expedition_reveal_requested):
		_expedition_market.card_reveal_requested.connect(_on_expedition_reveal_requested)

func set_expedition_shuffle_mode(active: bool) -> void:
	_expedition_market.set_shuffle_mode(active)

func set_expedition_reveal_mode(active: bool) -> void:
	_expedition_market.set_reveal_mode(active)

func shuffle_expedition_panel_slot(slot_idx: int) -> void:
	_expedition_market.shuffle_panel_slot(slot_idx)

func _on_expedition_card_shuffled_back(card_data: CardData, deck_insert_idx: int) -> void:
	expedition_card_shuffled_back.emit(card_data, deck_insert_idx)

func _on_expedition_reveal_requested(slot_idx: int) -> void:
	expedition_reveal_requested.emit(slot_idx)

func add_expedition_round_cards() -> void:
	_expedition_market.add_round_cards()

func set_supply_ui(ui: Control) -> void:
	_supply_ui = ui

func set_hand(hand_node: Node3D) -> void:
	_hand = hand_node
	_hand.card_drag_started.connect(_on_hand_card_drag_started)

func calculate_score() -> Array[Dictionary]:
	return Scoring.calculate(_sector_row)

func get_sector_row() -> Node3D:
	return _sector_row

func count_tech_by_name(tech_name: String) -> int:
	var count: int = 0
	for slot: SectorSlot in _sector_row.get_children():
		if not slot.occupied:
			continue
		for card: Node3D in slot.get_all_placed_cards():
			if card.card_data and card.card_data.card_name == tech_name:
				count += 1
	return count

func get_sector_count() -> int:
	var count: int = 0
	for slot: SectorSlot in _sector_row.get_children():
		if slot.occupied:
			count += 1
	return count

# Cost reductions only ever apply to tech cards (see get_purchase_discount),
# and tech cards only ever sit in hand — never in the market.
func refresh_hand_discounts() -> void:
	if not _hand:
		return
	for card: Node3D in _hand.get_cards():
		var cd: CardData = card.get("card_data") as CardData
		if cd:
			card.set_discount(get_purchase_discount(cd, null))

func get_all_sector_slots() -> Array[SectorSlot]:
	var result: Array[SectorSlot] = []
	for slot: SectorSlot in _sector_row.get_children():
		result.append(slot)
	return result

func get_all_placed_expeditions() -> Array[CardData]:
	var result: Array[CardData] = []
	for slot: SectorSlot in _sector_row.get_children():
		if not slot.occupied:
			continue
		for card_node: Node3D in slot.get_all_placed_cards():
			var cd: CardData = card_node.get("card_data")
			if cd and cd.card_type == CardData.CardType.EXPEDITION:
				result.append(cd)
	return result

func get_sector_count_by_color(color: CardData.SupplyColor) -> int:
	var count: int = 0
	for slot: SectorSlot in _sector_row.get_children():
		if not slot.occupied or not slot.placed_card or not slot.placed_card.card_data:
			continue
		var cd: CardData = slot.placed_card.card_data
		var slot_color: CardData.SupplyColor = cd.adv_color if bool(slot.placed_card.get("is_advanced")) else cd.color
		if slot_color == color:
			count += 1
	return count

func reset_sector_optimize() -> void:
	for slot: SectorSlot in _sector_row.get_children():
		slot.reset_optimize()

func get_purchase_discount(target: CardData, placement_slot: SectorSlot = null) -> int:
	var discount: int = 0
	for slot: SectorSlot in _sector_row.get_children():
		if not slot.occupied:
			continue
		# get_all_placed_cards is [sector card, tech slot 0, tech slot 1, ...]
		# in placement order, gap-free (get_next_tech_slot always fills the
		# lowest empty index, and compact_tech_cards keeps it that way after
		# a removal) — so the last entry is whichever tech is currently on
		# top, needed below for Day-Night Cycle/Seasons.
		var placed_cards: Array[Node3D] = slot.get_all_placed_cards()
		for card_node: Node3D in placed_cards:
			var cd: CardData = card_node.card_data
			if not cd:
				continue
			match cd.card_name:
				"Waste Management":
					if target.card_type == CardData.CardType.TECH and target.color == CardData.SupplyColor.LIQUIDS:
						discount += 1
				"Industrial Academy":
					if target.card_type == CardData.CardType.TECH and target.color == CardData.SupplyColor.METALS:
						discount += 1
				"Cloning Labs":
					if target.card_type == CardData.CardType.TECH and target.color == CardData.SupplyColor.ORGANIX:
						discount += 1
				"Physics Academy":
					if target.card_type == CardData.CardType.TECH and target.color == CardData.SupplyColor.ELECTRIX:
						discount += 1
				"Skyhook":
					if target.card_type == CardData.CardType.TECH and target.is_star_card:
						discount += 1
				"Day-Night Cycle":
					# "The next tech card placed here costs -1" — a one-time
					# discount for whatever lands directly on top of it, not
					# every tech this sector receives from then on. Only
					# applies while it's still the most recently placed tech
					# here — buried under a later tech, it stops, until
					# something like Caldera Colony clears what's on top of
					# it and restores it to the top.
					if placement_slot == slot and card_node == placed_cards[-1] and target.card_type == CardData.CardType.TECH:
						discount += 1
				"Seasons":
					if placement_slot == slot and card_node == placed_cards[-1] and target.card_type == CardData.CardType.TECH:
						discount += 2
	return discount

func get_supply_generators() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot: SectorSlot in _sector_row.get_children():
		if not slot.occupied:
			continue
		for card: Node3D in slot.get_all_placed_cards():
			if not card.card_data:
				continue
			var supply_color: CardData.SupplyColor
			if card.card_data.card_type == CardData.CardType.SECTOR and card.is_advanced:
				supply_color = card.card_data.adv_color
			else:
				supply_color = card.card_data.color
			result.append({ "card": card, "color": supply_color })
	return result

func add_to_discard(cd: CardData) -> void:
	if _discard_pile and cd:
		_discard_pile.add_discard(cd)
		tech_card_discarded.emit(cd)

# Shared-deck replay entry points — used exclusively by main.gd's RPC handlers
# on clients that did NOT perform the original action, to keep every
# client's local tech-deck mirror in lockstep. These must NOT re-emit the
# signals below (that would cause an RPC ping-pong back out to the network).
func replay_tech_draw() -> void:
	_tech_deck.draw_card()

func replay_tech_discard(cd: CardData) -> void:
	if _discard_pile and cd:
		_discard_pile.add_discard(cd)

func replay_tech_reshuffle(cards: Array[CardData]) -> void:
	_tech_deck.set_cards(cards)
	if _discard_pile:
		_discard_pile.take_all_cards()

# The tech deck is a single shared, finite resource across every client (see
# setup_tech_deck_ordered) — every successful pop and every reshuffle-on-empty
# is emitted individually, in the exact order it happens, so main.gd can relay
# each one and every other client's mirror can replay the identical sequence.
func _draw_from_tech_deck() -> CardData:
	var data: CardData = _tech_deck.draw_card()
	if data == null and _discard_pile:
		var recycled: Array[CardData] = _discard_pile.take_all_cards()
		if not recycled.is_empty():
			recycled.shuffle()
			_tech_deck.set_cards(recycled)
			tech_deck_reshuffled.emit(recycled)
			data = _tech_deck.draw_card()
	if data:
		tech_card_drawn.emit()
	return data

func draw_card_data(count: int) -> Array[CardData]:
	var result: Array[CardData] = []
	for _i: int in count:
		var data: CardData = _draw_from_tech_deck()
		if data:
			result.append(data)
	return result

func draw_and_recycle_top() -> void:
	var data: CardData = _draw_from_tech_deck()
	if data:
		add_to_discard(data)
		card_recycled.emit(data.color)

func draw_cards(count: int) -> void:
	var new_cards: Array[Node3D] = []
	for i: int in count:
		var data: CardData = _draw_from_tech_deck()
		if not data:
			break
		var card: Node3D = _card_scene.instantiate()
		_hand.add_card(card)
		card.set_card_data(data)
		new_cards.append(card)
	if not new_cards.is_empty():
		_hand.animate_draw_cards(new_cards)

# Adds a specific, externally-sourced CardData (e.g. one won from another
# player's Interfleet Comms pool) directly into hand — unlike draw_cards(),
# this doesn't pop from the local tech deck.
func add_specific_card_to_hand(cd: CardData) -> void:
	if not cd:
		return
	var card: Node3D = _card_scene.instantiate()
	_hand.add_card(card)
	card.set_card_data(cd)
	var new_cards: Array[Node3D] = [card]
	_hand.animate_draw_cards(new_cards)

# Batched sibling of add_specific_card_to_hand — used for host-authoritative
# hand delivery (opening hand, round-start draw, Gas Cloud) so a dealt hand
# gets one fan-out animation instead of several small ones.
func add_specific_cards_to_hand(cards: Array[CardData]) -> void:
	var new_cards: Array[Node3D] = []
	for cd: CardData in cards:
		if not cd:
			continue
		var card: Node3D = _card_scene.instantiate()
		_hand.add_card(card)
		card.set_card_data(cd)
		new_cards.append(card)
	if not new_cards.is_empty():
		_hand.animate_draw_cards(new_cards)

func clear_hand() -> void:
	_hand.clear()

func discard_and_draw(card: Node3D) -> void:
	if card.card_data:
		add_to_discard(card.card_data)
	# card is freed by the fly-out animation in hand.gd
	var data: CardData = _draw_from_tech_deck()
	if not data:
		return
	var new_card: Node3D = _card_scene.instantiate()
	_hand.add_card(new_card)
	new_card.set_card_data(data)
	var draw_batch: Array[Node3D] = [new_card]
	_hand.animate_draw_cards(draw_batch)

func deal_opening_hand(count: int = 6) -> void:
	if not _card_scene or not _hand:
		return
	var new_cards: Array[Node3D] = []
	for i in count:
		var data: CardData = _draw_from_tech_deck()
		if not data:
			break
		var card: Node3D = _card_scene.instantiate()
		_hand.add_card(card)
		card.set_card_data(data)
		new_cards.append(card)
	if not new_cards.is_empty():
		_hand.animate_draw_cards(new_cards)

func reset_turn() -> void:
	_major_action_taken = false
	major_action_changed.emit(false)

func set_major_action_taken() -> void:
	_major_action_taken = true
	major_action_changed.emit(true)

func is_major_action_taken() -> bool:
	return _major_action_taken

# Called by Main whenever its _effect_mode enters/leaves EffectMode.NONE.
# Starting a hand/market card drag mid-effect used to clobber _effect_mode
# with PAYMENT_CONFIRM/PLACEMENT_CONFIRM, stranding the original effect with
# no way to resume once the drag's own payment dialog was confirmed or
# cancelled — this blocks the drag from starting at all while any effect
# (including this feature's own dialogs) is already active.
func set_effect_active(active: bool) -> void:
	_effect_active = active

# True whenever a card is following the mouse awaiting placement — including
# the post-payment placement drag for a market purchase, where the card is
# already paid for but not yet on the board. Used to keep the turn from
# ending mid-placement.
func is_card_drag_pending() -> bool:
	return _dragged_card != null

func _on_hand_card_drag_started(card: Node3D) -> void:
	# _dragged_card guards against a market card mid-arrow-drag (prepaid
	# purchase or placement-confirm): board.gd starts that drag directly
	# rather than through this card's own click handling, so Card's static
	# _any_dragging flag never gets set for it — without this, hovering a
	# hand card and clicking during that window would let the hand card
	# start its OWN drag too, silently stealing _dragged_card out from under
	# the market card (which is then orphaned, invisible, forever unplaceable).
	if not GameNetwork.is_my_turn() or _pending_card or _pending_recycle_card or _dragged_card or _effect_active:
		card.end_drag()
		_hand.add_card(card, true)
		return
	_drag_origin = DragOrigin.HAND
	_begin_drag(card)

func _on_market_card_drag_started(card: Node3D) -> void:
	# See _on_hand_card_drag_started's _dragged_card comment — same hazard,
	# just with a second market card instead of a hand card.
	if not GameNetwork.is_my_turn() or _major_action_taken or _dragged_card or _effect_active:
		card.end_drag()
		if card.card_data and card.card_data.card_type == CardData.CardType.EXPEDITION:
			_expedition_market.return_card(card)
		else:
			_market.return_card(card)
		return
	market_origin_3d = card.global_position
	_drag_origin = DragOrigin.MARKET
	_begin_drag(card)

func _begin_drag(card: Node3D) -> void:
	_drag_start_global_pos = card.global_position
	_drag_start_scale = card.scale
	_dragged_card = card
	card.set("is_dragging", true)
	card.reparent(self, true)
	card.visible = false
	if not _is_sector_card():
		_set_tech_drag_active(true, card.card_data.color if card.card_data else CardData.SupplyColor.DUST)
	if _drag_origin == DragOrigin.HAND:
		_show_drag_preview(card)
	if _drag_arrow != null:
		_set_arrow_drag_active(true)
		var cam: Camera3D = get_viewport().get_camera_3d()
		var from_3d: Vector3 = market_origin_3d if _drag_origin == DragOrigin.MARKET else (_hand.global_position if _hand else _drag_start_global_pos)
		var from_2d: Vector2 = cam.unproject_position(from_3d)
		_drag_arrow.show_arrow(from_2d, from_2d)

const _DRAG_PREVIEW_SIZE: Vector2 = Vector2(160, 160)
# Above and to the right of the cursor/arrowhead (both sit at roughly the
# same point — see DragArrow's _to) so the preview doesn't cover either one,
# but close enough to still read as attached to the arrow rather than
# floating disconnected from it.
const _DRAG_PREVIEW_MOUSE_OFFSET: Vector2 = Vector2(30, -120)

# Shows the dragged hand card's own art next to the cursor for the whole
# drag (see _process for the follow-the-mouse position update) — the real
# card stays hidden and mouse-tracked in 3D space like any other drag, same
# as before this preview existed.
func _show_drag_preview(card: Node3D) -> void:
	_drag_preview_rect.visible = false
	if not card.card_data:
		return
	var cd: CardData = card.card_data
	var is_adv: bool = bool(card.get("is_advanced"))
	var url: String = cd.adv_image_url if is_adv and not cd.adv_image_url.is_empty() else cd.image_url
	if url.is_empty():
		return
	var tex: Texture2D = ImageCache.get_texture(url)
	if not tex:
		return
	_drag_preview_rect.texture = tex
	_drag_preview_rect.visible = true

func _clear_drag_preview() -> void:
	_drag_preview_rect.visible = false

func _process(_delta: float) -> void:
	if not _dragged_card or _placement_confirm_pending:
		return
	var world_pos: Vector3 = _mouse_to_plane(DRAG_Y)
	_dragged_card.global_position = world_pos
	if _drag_preview_rect.visible:
		_drag_preview_rect.position = get_viewport().get_mouse_position() + _DRAG_PREVIEW_MOUSE_OFFSET
	if _is_arrow_drag and _drag_arrow != null:
		var cam: Camera3D = get_viewport().get_camera_3d()
		var snap_slot: SectorSlot = _find_nearest_empty_sector_slot() if _is_sector_card() else _find_nearest_tech_slot()
		if snap_slot == null:
			snap_slot = _find_nearest_empty_sector_slot(INF) if _is_sector_card() else _find_nearest_tech_slot(INF)
		var to_2d: Vector2 = cam.unproject_position(snap_slot.global_position) if snap_slot else get_viewport().get_mouse_position()
		_drag_arrow.update_to(to_2d)
	_update_slot_highlights()

func _input(event: InputEvent) -> void:
	# Right-click-to-shrink a market-inspect clone used to be handled by the
	# clone's own 3D collider — no longer possible now that it's deliberately
	# unpickable (see inspect_market_card), so it's replaced with a plain
	# "right-click anywhere dismisses the inspect view" here instead. Handled
	# (and consumed) before any of the drag-specific logic below, since
	# there's no dragged card at all while just inspecting.
	if _inspecting_card and is_instance_valid(_inspecting_card) and event is InputEventMouseButton:
		var mb_inspect: InputEventMouseButton = event as InputEventMouseButton
		if mb_inspect.button_index == MOUSE_BUTTON_RIGHT and mb_inspect.pressed:
			_dismiss_inspecting_card()
			get_viewport().set_input_as_handled()
			return
	# _placement_confirm_pending guard: the confirm panel lives on the info
	# screen, a 3D mesh — clicking its Confirm/Cancel button is a raw OS
	# click forwarded into its SubViewport via physics-object-picking, which
	# Godot resolves *after* plain _input(). Without this guard, the same
	# click hit this function first (since _dragged_card is deliberately
	# kept alive while the panel is up — see _request_placement_confirm),
	# re-triggering _try_drop() for the still-"dragged" card and clobbering
	# _effect_mode before the real button press ever landed — producing an
	# endless arrow/confirm-panel loop every time Confirm or Cancel was clicked.
	if not _dragged_card or _placement_confirm_pending:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_try_drop()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_cancel_prepaid_to_payment()

func _is_sector_card() -> bool:
	return _dragged_card.card_data != null and _dragged_card.card_data.card_type == CardData.CardType.SECTOR

func _set_arrow_drag_active(active: bool) -> void:
	_is_arrow_drag = active
	arrow_drag_changed.emit(active)

# Shows every sector's New/Completes-Next/Complete + Optimizes-Next/Optimized
# helper badges (see SectorSlot._refresh_state_badges) only while a tech or
# expedition card is actually being dragged — sector cards don't trigger any
# of those card-text conditions themselves, so their own drags leave this off.
# dragged_color is only meaningful while active — SectorSlot needs it to
# tell whether THIS specific card would actually satisfy the one remaining
# Optimize color, not just whether the sector is one card away in general.
func _set_tech_drag_active(active: bool, dragged_color: CardData.SupplyColor = CardData.SupplyColor.DUST) -> void:
	for slot: SectorSlot in _sector_row.get_children():
		slot.set_drag_helper_active(active, dragged_color)

func _end_arrow_drag() -> void:
	_set_tech_drag_active(false)
	if not _is_arrow_drag:
		return
	_set_arrow_drag_active(false)
	_clear_drag_preview()
	if _drag_arrow:
		_drag_arrow.hide_arrow()
	if is_instance_valid(_dragged_card):
		var ctype: CardData.CardType = _dragged_card.card_data.card_type if _dragged_card.card_data else CardData.CardType.TECH
		if ctype != CardData.CardType.SECTOR and ctype != CardData.CardType.EXPEDITION:
			_dragged_card.visible = true

# Re-arms the drag-arrow visual — either after a placement click that missed
# every slot (prepaid market cards only: money's already spent, so there's no
# "cancel" there, just "keep dragging and try again"), or after the
# placement-confirm panel's own Cancel, for any origin. Mirrors _begin_drag's
# own origin -> "from" point logic so a re-armed hand-card arrow starts from
# the hand rather than the (irrelevant, for that origin) market position.
func _resume_drag_arrow() -> void:
	if _drag_arrow == null:
		return
	if not _is_sector_card():
		_set_tech_drag_active(true, _dragged_card.card_data.color if _dragged_card.card_data else CardData.SupplyColor.DUST)
	_set_arrow_drag_active(true)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if not cam:
		return
	var from_3d: Vector3 = market_origin_3d if _drag_origin == DragOrigin.MARKET else (_hand.global_position if _hand else _drag_start_global_pos)
	var from_2d: Vector2 = cam.unproject_position(from_3d)
	var snap_slot: SectorSlot = _find_nearest_empty_sector_slot() if _is_sector_card() else _find_nearest_tech_slot()
	if snap_slot == null:
		snap_slot = _find_nearest_empty_sector_slot(INF) if _is_sector_card() else _find_nearest_tech_slot(INF)
	var to_2d: Vector2 = cam.unproject_position(snap_slot.global_position) if snap_slot else get_viewport().get_mouse_position()
	_drag_arrow.show_arrow(from_2d, to_2d)

# Right-click during a post-purchase targeting arrow: re-opens the payment
# step for this same card, letting the player re-pick colors or forfeit
# outright — for a direct purchase, that's _resolve_card_payment's own panel
# again; for an auction win, the bid amount is already fixed (not a cost
# _resolve_card_payment could recompute), so it re-opens the bid payment
# panel instead via auction_payment_cancel_requested, using the same node
# once main.gd hands it back through resume_auction_win_drag. Safe for both
# now: supply is only ever actually spent once placement is confirmed (see
# _finalize_placement/complete_purchase), so _prepaid_spent_amounts at this
# point is still just the pending amount, not a real deduction — nothing to
# refund either way.
func _cancel_prepaid_to_payment() -> void:
	if not is_instance_valid(_dragged_card) or not _is_prepaid_placement:
		return
	if _placement_confirm_pending:
		return
	var card: Node3D = _dragged_card
	var is_auction_win: bool = _is_auction_win_placement
	var is_tech: bool = not _is_sector_card()
	_end_arrow_drag()
	_dragged_card = null
	_is_prepaid_placement = false
	_is_auction_win_placement = false
	_prepaid_spent_amounts = {}
	if is_auction_win:
		card.visible = false
		_cancelled_auction_card = card
		auction_payment_cancel_requested.emit()
		return
	if not _resolve_card_payment(card, null, is_tech):
		return
	_begin_prepaid_drag(card)

# Resumes a drag cancelled back to the bid-payment window via
# _cancel_prepaid_to_payment, once the player re-confirms payment — reuses
# the exact same card node (unlike begin_auction_win_drag's find-or-create,
# meant for a fresh win whose node might not exist locally) since it's
# already in hand here, just hidden.
func resume_auction_win_drag(spent: Dictionary) -> void:
	if not is_instance_valid(_cancelled_auction_card):
		_cancelled_auction_card = null
		return
	var card: Node3D = _cancelled_auction_card
	_cancelled_auction_card = null
	_begin_prepaid_drag(card, spent, true)

func _try_drop() -> void:
	_end_arrow_drag()
	_clear_slot_highlights()
	if _is_sector_card():
		_try_drop_sector()
	else:
		_try_drop_tech()

func request_recycle(card: Node3D) -> void:
	if _pending_recycle_card or not is_instance_valid(card):
		return
	if _hand:
		_hand.detach_card(card)
	var color: CardData.SupplyColor = card.card_data.color if card.card_data else CardData.SupplyColor.DUST
	_pending_recycle_card = card
	recycle_confirm_required.emit(card, color)

func confirm_recycle() -> void:
	if not is_instance_valid(_pending_recycle_card):
		_pending_recycle_card = null
		return
	var card: Node3D = _pending_recycle_card
	_pending_recycle_card = null
	_recycle_card_node(card)

# Shared by confirm_recycle() (player-chosen) and _begin_prepaid_drag()'s
# no-room-to-place fallback (forced) — adds the card's supply, discards it,
# and plays the same shrink-away animation either way. Previously only ever
# called with hand (tech) cards, which don't have an adv_color distinction —
# now also reached by unplaceable advanced-sector auction wins, so it must
# credit adv_color rather than the dust-sector color for those.
func _recycle_card_node(card: Node3D) -> void:
	var color: CardData.SupplyColor = CardData.SupplyColor.DUST
	if card.card_data:
		color = card.card_data.adv_color if card.is_advanced else card.card_data.color
	add_to_discard(card.card_data)
	card_recycled.emit(color)
	card.collider.monitoring = false
	var t: Tween = card.create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	# Vector3.ZERO here would leave the Collider Area3D with a singular basis,
	# which Jolt logs a warning about — see Card.NEGLIGIBLE_SCALE.
	t.tween_property(card, "scale", Vector3.ONE * Card.NEGLIGIBLE_SCALE, 0.25)
	t.tween_callback(func() -> void:
		if is_instance_valid(card):
			card.queue_free()
	)

# True if any occupied sector still has room for a tech/expedition card.
func _any_tech_slot_available() -> bool:
	for slot: SectorSlot in _sector_row.get_children():
		if slot.occupied and slot.has_tech_space():
			return true
	return false

# True if any of the fixed 6 sector slots is still empty.
func _has_free_sector_slot() -> bool:
	for slot: SectorSlot in _sector_row.get_children():
		if not slot.occupied and slot.is_available:
			return true
	return false

func cancel_recycle() -> void:
	if not is_instance_valid(_pending_recycle_card):
		_pending_recycle_card = null
		return
	var card: Node3D = _pending_recycle_card
	_pending_recycle_card = null
	if _hand:
		_hand.add_card(card, true)

func _spawn_slot_at_pos(pos: Vector3) -> SectorSlot:
	var slot: SectorSlot = _SLOT_SCENE.instantiate() as SectorSlot
	_sector_row.add_child(slot)
	slot.global_position = Vector3(pos.x, DRAG_Y, pos.z)
	slot.scale = Vector3(0.1, 0.1, 0.1)
	slot.slot_clicked.connect(_on_sector_slot_clicked)
	return slot

func _cleanup_pending_dynamic_slot() -> void:
	if is_instance_valid(_pending_dynamic_slot) and not _pending_dynamic_slot.occupied:
		_pending_dynamic_slot.queue_free()
	_pending_dynamic_slot = null

func _find_nearest_tech_slot(max_dist: float = TECH_COLUMN_HALF_X) -> SectorSlot:
	var best: SectorSlot = null
	var best_dx: float = max_dist
	for slot: SectorSlot in _sector_row.get_children():
		if not slot.occupied or not slot.has_tech_space():
			continue
		var dx: float = abs(_dragged_card.global_position.x - slot.global_position.x)
		var slot_z: float = slot.global_position.z
		var card_z: float = _dragged_card.global_position.z
		if dx < best_dx and card_z < slot_z + TECH_ZONE_Z_FRONT and card_z > slot_z - TECH_ZONE_Z_BACK:
			best_dx = dx
			best = slot
	return best

# Returns true if payment was resolved synchronously (caller should proceed with placement).
# Returns false if an async flow was started or the drop failed (caller should return immediately).
func _resolve_card_payment(placed: Node3D, slot: SectorSlot, is_tech: bool) -> bool:
	var cd: CardData = placed.card_data
	var pay_amounts: Dictionary = {}
	if cd and cd.cost > 0:
		var effective_cost: int = max(0, cd.cost - get_purchase_discount(cd, slot))
		if effective_cost > 0:
			var single_options: Array[CardData.SupplyColor] = _viable_single_color_options(cd.color, effective_cost)
			if single_options.size() > 1:
				pay_amounts = {single_options[0]: effective_cost}
			else:
				pay_amounts = _compute_payment(cd.color, effective_cost)
				if pay_amounts.is_empty():
					# Can't fully afford: open the payment window anyway so the player
					# can see what's needed and cancel deliberately.
					var valid: Array[CardData.SupplyColor] = CardData.valid_payment_colors(cd.color)
					if valid.is_empty():
						_handle_failed_drop()
						return false
					pay_amounts = {valid[0]: effective_cost}
	var needs_confirm: bool = GameNetwork.is_multiplayer or not pay_amounts.is_empty()
	if needs_confirm:
		_start_payment_confirm(placed, slot, pay_amounts, is_tech)
		return false
	# pay_amounts is always empty here (cost 0) — nothing to spend, and the
	# major action itself is now only committed once placement is actually
	# confirmed (see confirm_pending_placement), not at this earlier point.
	return true

func _try_drop_sector() -> void:
	var target_slot: SectorSlot = _find_nearest_empty_sector_slot()
	if not target_slot:
		if _is_prepaid_placement:
			_resume_drag_arrow()
			return
		_handle_failed_drop()
		return
	var placed: Node3D = _dragged_card
	if _is_prepaid_placement:
		_request_placement_confirm(placed, target_slot, false, DragOrigin.MARKET, _prepaid_spent_amounts)
		return
	if _is_free_gain:
		_dragged_card = null
		_drag_origin = DragOrigin.NONE
		_is_free_gain = false
		action_committed.emit()
		target_slot.accept_card(placed)
		placed.place()
		card_placed.emit(placed, target_slot)
		if placed.card_data:
			market_card_taken.emit(placed.card_data)
		return
	_pending_dynamic_slot = null
	if _should_bid(_dragged_card):
		_start_bid(_dragged_card, target_slot, false)
		return
	var origin: DragOrigin = _drag_origin
	var cd: CardData = placed.card_data
	if not _resolve_card_payment(placed, target_slot, false):
		return
	if origin == DragOrigin.MARKET and cd:
		market_card_taken.emit(cd)
	_request_placement_confirm(placed, target_slot, false, origin)

func _try_drop_tech() -> void:
	if _drag_origin == DragOrigin.HAND and _major_action_taken:
		_handle_failed_drop()
		return
	var best_sector: SectorSlot = _find_nearest_tech_slot()
	if not best_sector:
		if _is_prepaid_placement:
			_resume_drag_arrow()
			return
		_handle_failed_drop()
		return
	var placed: Node3D = _dragged_card
	if _is_prepaid_placement:
		_request_placement_confirm(placed, best_sector, true, DragOrigin.MARKET, _prepaid_spent_amounts)
		return
	if _should_bid(_dragged_card):
		_start_bid(_dragged_card, best_sector, true)
		return
	var origin: DragOrigin = _drag_origin
	if not _resolve_card_payment(placed, best_sector, true):
		return
	_request_placement_confirm(placed, best_sector, true, origin)

# A tech/expedition drop that found a valid target no longer places
# immediately — it freezes the card in place (see _process's
# _placement_confirm_pending guard) and asks main.gd to show a "Place X on
# Y?" panel first, since it attaches to a specific existing sector among
# possibly several. Used for both a prepaid market arrow-drop and a regular
# hand/board drag once its payment has resolved (origin is passed explicitly
# rather than read from _drag_origin, since by the time a hand card's
# payment confirms, _start_payment_confirm already nulled it — see
# cancel_pending_placement_to_arrow). Sectors skip the panel and finalize
# immediately instead — there's rarely any ambiguity about where a sector
# card should land (it just snaps to the nearest empty slot), so the extra
# click was more friction than it was worth.
func _request_placement_confirm(card: Node3D, slot: SectorSlot, is_tech: bool, origin: DragOrigin, spent: Dictionary = {}) -> void:
	if not is_tech:
		_finalize_placement(card, slot, false, spent)
		return
	_placement_confirm_pending = true
	_pending_placement_card = card
	_pending_placement_slot = slot
	_pending_placement_is_tech = is_tech
	_pending_placement_origin = origin
	_pending_placement_spent = spent.duplicate()
	_dragged_card = card
	_drag_origin = origin
	placement_confirm_required.emit(card, slot, is_tech)

# Preview-only: the effect steps this tech card would generate if placed on
# this slot right now — its own place effect, plus (once per newly-triggered
# level) the sector's optimize effect if this placement would complete it.
# Never mutates slot state (the card isn't actually placed yet at this
# point — see _request_placement_confirm) — mirrors _finalize_placement's
# real resolution order and OptimizeLogic.update_optimize_state's pool
# rules exactly, but against a hypothetical "as if this card already
# landed" pool instead of the slot's actual placed cards. Used by the
# placement confirmation panel to show what to expect before committing.
func preview_placement_steps(card: Node3D, slot: SectorSlot) -> Array[Dictionary]:
	if not card or not card.card_data or not slot or not slot.placed_card or not slot.placed_card.card_data:
		return []
	var cd: CardData = card.card_data
	var sector_cd: CardData = slot.placed_card.card_data
	var sector_is_adv: bool = bool(slot.placed_card.get("is_advanced"))

	# PlaceEffects' placed_colors: every card already on the slot (sector +
	# techs) plus this incoming card, each by raw .color — mirrors
	# PlaceEffects._slot_placed_colors/get_steps exactly.
	var place_colors: Array[int] = []
	for c: Node3D in slot.get_all_placed_cards():
		var c_cd: CardData = c.get("card_data")
		if c_cd:
			place_colors.append(int(c_cd.color))
	place_colors.append(int(cd.color))

	# Optimize-trigger pool: tech colors only, never the sector itself
	# (mirrors _update_optimize_state), plus this incoming card.
	var opt_pool: Array[int] = slot.get_placed_tech_colors()
	opt_pool.append(int(cd.color))

	var is_new: bool = slot.get_tech_count() == 0
	var is_complete: bool = slot.get_tech_count() + 1 >= SectorSlot.TECH_OFFSETS_COMPACT.size()

	# triggered_levels is duplicated because OptimizeLogic mutates the array
	# it's given in place — without this, a mere preview would silently
	# alter the slot's real optimize-progress state.
	var opt_result: Dictionary = OptimizeLogic.update_optimize_state(
		sector_cd, sector_is_adv, opt_pool,
		slot.optimize_count, slot.max_optimizations, slot.triggered_levels.duplicate())
	var is_opt: bool = opt_result["is_optimized"]

	var steps: Array[Dictionary] = PlaceEffects.get_steps_for_state(cd, is_new, is_complete, is_opt, place_colors)

	# SectorEffects' placed_colors: every card on the slot (sector + techs),
	# EFFECTIVE color, plus this incoming card — mirrors
	# SectorEffects._slot_effective_colors/get_optimize_steps exactly.
	var opt_effect_colors: Array[int] = []
	for c2: Node3D in slot.get_all_placed_cards():
		var c2_cd: CardData = c2.get("card_data")
		if c2_cd:
			opt_effect_colors.append(int(CardData.effective_color(c2_cd, bool(c2.get("is_advanced")))))
	opt_effect_colors.append(int(cd.color))

	var triggered: Array = opt_result["triggered"]
	for _level: int in triggered:
		steps.append_array(SectorEffects.get_optimize_steps_for_state(sector_cd, sector_is_adv, opt_effect_colors, cd.cost))

	return steps

func confirm_pending_placement() -> void:
	if not _pending_placement_card:
		return
	var card: Node3D = _pending_placement_card
	var slot: SectorSlot = _pending_placement_slot
	var is_tech: bool = _pending_placement_is_tech
	var spent: Dictionary = _pending_placement_spent
	_pending_placement_card = null
	_pending_placement_slot = null
	_pending_placement_is_tech = false
	_pending_placement_origin = DragOrigin.NONE
	_pending_placement_spent = {}
	_placement_confirm_pending = false
	_finalize_placement(card, slot, is_tech, spent)

# The one true commit point for a direct buy/hand-card placement: the major
# action and the supply cost both land here, not back when the payment
# panel was confirmed — including an auction win that needed a fresh drag
# (see complete_purchase for the other auction-win case, one that already
# had a slot pre-selected before bidding interrupted it, which spends and
# places directly there instead of coming through here). action_committed
# re-firing for an auction win is harmless too, since starting the auction
# already committed the major action.
func _finalize_placement(card: Node3D, slot: SectorSlot, is_tech: bool, spent: Dictionary) -> void:
	_dragged_card = null
	_drag_origin = DragOrigin.NONE
	_is_prepaid_placement = false
	_is_auction_win_placement = false
	_prepaid_spent_amounts = {}
	action_committed.emit()
	for col: CardData.SupplyColor in spent:
		_supply_ui.spend_supply(col, spent[col])
	if is_tech:
		slot.accept_tech_card(card)
		card.place()
		var opt_levels: Array[int] = _update_optimize_state(slot)
		# optimize_triggered before card_placed (not after) deliberately —
		# main.gd's _on_optimize_triggered just stages its steps now, and
		# _on_card_placed (which decides ordering when this placement
		# triggered more than one effect at once) needs that already staged
		# by the time it runs, not arriving a moment too late.
		for level: int in opt_levels:
			optimize_triggered.emit(slot, level)
		card_placed.emit(card, slot)
	else:
		slot.accept_card(card)
		card.place()
		card_placed.emit(card, slot)

# The confirm panel's own Cancel. For a market card (prepaid purchase or
# direct market drag), this just re-arms the arrow so the player can aim at
# a different slot. For a hand card, there's no "try a different slot" — it
# hands the card back and leaves the targeting arrow cancelled rather than
# resuming it. Neither branch needs to refund anything: supply is only ever
# actually spent in confirm_pending_placement, once placement lands for
# real, so cancelling before that point never took anything to begin with.
func cancel_pending_placement_to_arrow() -> void:
	if not _pending_placement_card:
		return
	var card: Node3D = _pending_placement_card
	var origin: DragOrigin = _pending_placement_origin
	_pending_placement_card = null
	_pending_placement_slot = null
	_pending_placement_is_tech = false
	_pending_placement_origin = DragOrigin.NONE
	_pending_placement_spent = {}
	_placement_confirm_pending = false
	if origin == DragOrigin.HAND:
		_dragged_card = null
		_drag_origin = DragOrigin.NONE
		card.visible = true
		card.end_drag()
		_hand.add_card(card, true)
		return
	_dragged_card = card
	_drag_origin = origin
	_resume_drag_arrow()

func _should_bid(card: Node3D) -> bool:
	if _is_free_gain:
		return false
	if _drag_origin != DragOrigin.MARKET:
		return false
	if not card.card_data:
		return false
	if card.card_data.card_type == CardData.CardType.EXPEDITION:
		return true
	if card.card_data.card_type == CardData.CardType.SECTOR and card.is_advanced:
		return true
	return false

func _start_bid(card: Node3D, slot: Node3D, is_tech: bool) -> void:
	_pending_card = card
	_pending_slot = slot
	_pending_is_tech = is_tech
	_pending_drag_origin = DragOrigin.MARKET
	_dragged_card = null
	_drag_origin = DragOrigin.NONE
	card.end_drag()
	var hover_target: Vector3 = (slot.global_position if slot else card.global_position) + Vector3(0.0, PENDING_HOVER_Y, 0.0)
	var t: Tween = card.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(card, "global_position", hover_target, 0.2)
	var min_cost: int
	var cost_color: CardData.SupplyColor
	if card.card_data.card_type == CardData.CardType.EXPEDITION:
		min_cost = card.card_data.cost
		cost_color = card.card_data.color
	else:
		min_cost = card.card_data.adv_cost
		cost_color = card.card_data.adv_color
	bid_required.emit(card, slot, min_cost, cost_color, is_tech)

# spent lands here (not earlier, at bid-payment time) so an auction win only
# actually costs supply once the card is placed for real — same rule as
# every other purchase (see _finalize_placement). The occupied/no-tech-space
# fallbacks below recycle the card instead of placing it, and deliberately
# don't spend anything in that case either: nothing was ever actually taken
# from the player for a card that didn't end up placed.
func complete_purchase(spent: Dictionary = {}) -> void:
	if not _pending_card:
		return
	_pending_dynamic_slot = null
	_prepaid_market_notified = false
	set_major_action_taken()
	var card: Node3D = _pending_card
	var slot: Node3D = _pending_slot
	var is_tech: bool = _pending_is_tech
	var drag_origin: DragOrigin = _pending_drag_origin
	_pending_card = null
	_pending_slot = null
	_pending_is_tech = false
	_pending_drag_origin = DragOrigin.NONE
	if not slot:
		_begin_prepaid_drag(card, spent, true)
		return
	var sector_slot: SectorSlot = slot as SectorSlot
	if not sector_slot:
		card_recycled.emit(card.card_data.color)
		card.queue_free()
		return
	if is_tech:
		if sector_slot.has_tech_space():
			for col: CardData.SupplyColor in spent:
				_supply_ui.spend_supply(col, spent[col])
			sector_slot.accept_tech_card(card)
			card.place()
			var opt_levels_bid: Array[int] = _update_optimize_state(sector_slot)
			# See _finalize_placement for why optimize_triggered fires
			# before card_placed here too.
			for level: int in opt_levels_bid:
				optimize_triggered.emit(sector_slot, level)
			card_placed.emit(card, sector_slot)
			if drag_origin == DragOrigin.MARKET and card.card_data:
				market_card_taken.emit(card.card_data)
		else:
			# The pre-targeted slot filled up while the auction/payment was
			# in progress — same "recycled instead of placed" case as
			# _begin_prepaid_drag's no-room branch, so payment has to be
			# taken here too, or the card never actually cost anything.
			for col: CardData.SupplyColor in spent:
				_supply_ui.spend_supply(col, spent[col])
			if card.card_data:
				add_to_discard(card.card_data)
			card_recycled.emit(card.card_data.color)
			card.queue_free()
	else:
		if not sector_slot.occupied:
			for col: CardData.SupplyColor in spent:
				_supply_ui.spend_supply(col, spent[col])
			sector_slot.accept_card(card)
			card.place()
			card_placed.emit(card, sector_slot)
			if drag_origin == DragOrigin.MARKET and card.card_data:
				market_card_taken.emit(card.card_data)
		else:
			for col: CardData.SupplyColor in spent:
				_supply_ui.spend_supply(col, spent[col])
			card_recycled.emit(card.card_data.adv_color if card.is_advanced else card.card_data.color)
			card.queue_free()

func get_slot_index(slot: SectorSlot) -> int:
	return _sector_row.get_children().find(slot)

# Kicks off the drag-to-place step for a market card whose payment/bid has
# already resolved (a direct dust-sector buy, or an advanced-sector/expedition
# auction win — whether by the auction's initiator or another player). The
# card already belongs to the buyer at this point, so this is also where
# market_card_taken fires — removing it from every client's market view as
# soon as ownership is settled, rather than waiting for the physical
# placement to land.
# spent/is_auction_win let a right-click-cancel-to-payment redo (see
# _cancel_prepaid_to_payment) call this again for the same card without
# re-notifying the market (notify_taken guard) or losing track of what to
# refund if cancelled again.
func _begin_prepaid_drag(card: Node3D, spent: Dictionary = {}, is_auction_win: bool = false) -> void:
	if not _prepaid_market_notified and card.card_data:
		market_card_taken.emit(card.card_data)
		_prepaid_market_notified = true
	# Tech/expedition cards need an occupied sector with a free tech slot,
	# and sector cards need one of the fixed 6 sector slots to be empty —
	# either way that space is capped, so a bought/won card can end up with
	# nowhere to go. The physical game's rule for this is to recycle it
	# instead of leaving the buyer stuck holding an unplaceable card forever.
	var ctype: CardData.CardType = card.card_data.card_type if card.card_data else CardData.CardType.TECH
	var has_room: bool = _has_free_sector_slot() if ctype == CardData.CardType.SECTOR else _any_tech_slot_available()
	if not has_room:
		# Payment is normally deferred all the way to actual placement (see
		# the has_room branch below, and complete_purchase/confirm_payment),
		# but this card is never going to reach that point — it's about to
		# be recycled instead. Skipping the spend here would let a player
		# win an auction (or buy a sector) for free and still collect the
		# recycle bonus, since nothing would ever have left their supply.
		for col: CardData.SupplyColor in spent:
			_supply_ui.spend_supply(col, spent[col])
		card.reparent(self, true)
		card.global_position = market_origin_3d
		unplaceable_card_recycled.emit(card.card_data)
		_recycle_card_node(card)
		return
	_is_prepaid_placement = true
	_is_auction_win_placement = is_auction_win
	_prepaid_spent_amounts = spent.duplicate()
	_drag_origin = DragOrigin.MARKET
	_begin_drag(card)

# cd's own node may no longer be findable by the time a DIFFERENT player
# than the auction's initiator confirms payment for winning it: a human
# initiator's own buy-flow already detached it from the market's trackable
# stacks (find_market_card searches those same stacks), and a bot
# initiator's BotTurn.bot_start_auction() goes further and queue_frees it
# outright. Either way, build a fresh instance from the card data instead
# of depending on a node that might already be gone.
func begin_auction_win_drag(cd: CardData, spent: Dictionary = {}) -> bool:
	var card: Node3D = find_market_card(cd)
	if not card:
		card = _card_scene.instantiate()
		add_child(card)
		if cd.card_type == CardData.CardType.SECTOR:
			card.set("is_advanced", true)
		card.set_card_data(cd)
	_prepaid_market_notified = false
	if cd.card_type == CardData.CardType.EXPEDITION:
		_expedition_market.detach_card(card)
	else:
		_market.detach_advanced_card(card)
	_begin_prepaid_drag(card, spent, true)
	return true

func cancel_purchase() -> void:
	_end_pending_purchase(true)

func forfeit_purchase() -> void:
	_end_pending_purchase(false)

func _end_pending_purchase(return_to_market: bool) -> void:
	if not _pending_card:
		return
	_cleanup_pending_dynamic_slot()
	var card: Node3D = _pending_card
	_pending_card = null
	_pending_slot = null
	_pending_is_tech = false
	_pending_drag_origin = DragOrigin.NONE
	card.end_drag()
	if return_to_market:
		if card.card_data and card.card_data.card_type == CardData.CardType.EXPEDITION:
			_expedition_market.return_card(card)
		else:
			_market.return_card(card)
	else:
		card.queue_free()

func remove_market_card(cd: CardData) -> void:
	if cd.card_type == CardData.CardType.EXPEDITION:
		_expedition_market.remove_card(cd)
	else:
		_market.remove_card(cd)

func _compute_payment(card_color: CardData.SupplyColor, cost: int) -> Dictionary:
	var result: Dictionary = {}
	var remaining: int = cost
	for color: CardData.SupplyColor in CardData.valid_payment_colors(card_color):
		if remaining <= 0:
			break
		var available: int = _supply_ui.get_supply(color)
		if available <= 0:
			continue
		var take: int = min(available, remaining)
		result[color] = take
		remaining -= take
	if remaining > 0:
		return {}
	return result

func _viable_single_color_options(card_color: CardData.SupplyColor, cost: int) -> Array[CardData.SupplyColor]:
	var options: Array[CardData.SupplyColor] = []
	for color: CardData.SupplyColor in CardData.valid_payment_colors(card_color):
		if _supply_ui.get_supply(color) >= cost:
			options.append(color)
	return options

func apply_supply_choice(color: CardData.SupplyColor) -> void:
	_pending_pay_amounts = {color: _pending_cost}
	confirm_payment()

func _start_payment_confirm(card: Node3D, slot: SectorSlot, pay_amounts: Dictionary, is_tech: bool) -> void:
	_pending_card = card
	_pending_slot = slot
	_pending_is_tech = is_tech
	_pending_pay_amounts = pay_amounts
	_pending_drag_origin = _drag_origin
	_dragged_card = null
	_drag_origin = DragOrigin.NONE
	card.end_drag()
	card.visible = false
	payment_confirm_required.emit(card, slot, pay_amounts, is_tech)

func confirm_payment_with_allocations(allocations: Dictionary) -> void:
	_pending_pay_amounts = allocations
	confirm_payment()

func confirm_payment() -> void:
	if not _pending_card:
		return
	_pending_dynamic_slot = null
	var card: Node3D = _pending_card
	var slot: SectorSlot = _pending_slot as SectorSlot
	var is_tech: bool = _pending_is_tech
	var pay_amounts: Dictionary = _pending_pay_amounts
	var pay_origin: DragOrigin = _pending_drag_origin
	_pending_card = null
	_pending_slot = null
	_pending_is_tech = false
	_pending_pay_amounts = {}
	_pending_drag_origin = DragOrigin.NONE
	# Neither the supply nor the major action are committed here anymore —
	# only once placement is actually confirmed (see confirm_pending_placement)
	# — so cancelling later (return to hand, or right-click back to this same
	# payment step) never has to undo a spend or a turn-ending flag that
	# shouldn't have landed yet.
	if not slot:
		_begin_prepaid_drag(card, pay_amounts)
		return
	if pay_origin == DragOrigin.MARKET and card.card_data:
		market_card_taken.emit(card.card_data)
	_request_placement_confirm(card, slot, is_tech, pay_origin, pay_amounts)

func cancel_payment_confirm() -> void:
	if not _pending_card:
		return
	_cleanup_pending_dynamic_slot()
	var card: Node3D = _pending_card
	var origin: DragOrigin = _pending_drag_origin
	_pending_card = null
	_pending_slot = null
	_pending_is_tech = false
	_pending_pay_amounts = {}
	_pending_drag_origin = DragOrigin.NONE
	card.end_drag()
	card.visible = true
	if origin == DragOrigin.HAND:
		_hand.add_card(card, true)
	elif card.card_data and card.card_data.card_type == CardData.CardType.EXPEDITION:
		_expedition_market.return_card(card)
	else:
		_market.return_card(card)

func restore_visual_from_public_snapshot(snap: Dictionary) -> void:
	if _dragged_card:
		_dragged_card.queue_free()
		_dragged_card = null
		_drag_origin = DragOrigin.NONE
		_clear_slot_highlights()
	var supply: Dictionary = snap.get("supply", {})
	for color: CardData.SupplyColor in CardData.SupplyColor.values():
		_supply_ui.set_supply(color, supply.get(int(color), 0))
	for old_slot: SectorSlot in _sector_row.get_children().duplicate():
		_sector_row.remove_child(old_slot)
		old_slot.queue_free()
	var slots: Array = snap.get("slots", [])
	for s: Dictionary in slots:
		if not s.get("occupied", false):
			continue
		var pos: Dictionary = s.get("position", {})
		var slot: SectorSlot = _spawn_slot_at_pos(Vector3(pos.get("x", 0.0), 0.0, pos.get("z", 0.5)))
		var sector_name: String = s.get("sector_name", "")
		var is_adv: bool = s.get("sector_advanced", false)
		var sec_data: CardData = _find_sector_by_name(sector_name, is_adv)
		if sec_data:
			var sec_card: Node3D = _card_scene.instantiate()
			add_child(sec_card)
			sec_card.global_position = slot.global_position + Vector3(0.0, 0.3, 0.0)
			if is_adv:
				sec_card.set("is_advanced", true)
			sec_card.set_card_data(sec_data)
			slot.accept_card(sec_card)
			sec_card.place()
		slot.optimize_count = s.get("optimize_count", 0)
		slot.max_optimizations = s.get("max_optimizations", 1)
		slot.is_optimized = s.get("is_optimized", false)
		for tech_name: Variant in s.get("tech_names", []):
			var tech_data: CardData = _find_placed_card_by_name(str(tech_name))
			if tech_data and slot.has_tech_space():
				var tech_card: Node3D = _card_scene.instantiate()
				add_child(tech_card)
				tech_card.global_position = slot.global_position + Vector3(0.0, 0.3, 0.0)
				tech_card.set_card_data(tech_data)
				slot.accept_tech_card(tech_card)
				tech_card.place()

func _find_sector_by_name(sec_name: String, is_adv: bool) -> CardData:
	for cd: CardData in CardDatabase.sectors:
		if is_adv:
			if cd.adv_name == sec_name:
				return cd
		else:
			if cd.card_name == sec_name:
				return cd
	return null

func _find_placed_card_by_name(card_name: String) -> CardData:
	for cd: CardData in CardDatabase.techs:
		if cd.card_name == card_name:
			return cd
	for cd: CardData in CardDatabase.expeditions:
		if cd.card_name == card_name:
			return cd
	return null

func get_snapshot() -> Dictionary:
	var supply_snap: Dictionary = {}
	for color: CardData.SupplyColor in CardData.SupplyColor.values():
		supply_snap[int(color)] = _supply_ui.get_supply(color)
	var hand_snap: Array[CardData] = _hand.get_card_data_list()
	var drag_card_data: CardData = null
	var drag_origin_val: int = DragOrigin.NONE
	var drag_market_slot: int = -1
	if _dragged_card and _dragged_card.card_data:
		drag_card_data = _dragged_card.card_data
		drag_origin_val = int(_drag_origin)
		drag_market_slot = int(_dragged_card.get_meta("market_slot", -1))
	var slots_snap: Array = []
	for slot: SectorSlot in _sector_row.get_children():
		var tech_data: Array[CardData] = []
		for ts: Node3D in slot._tech_slots:
			if ts.occupied and ts.placed_card and ts.placed_card.card_data:
				tech_data.append(ts.placed_card.card_data as CardData)
		slots_snap.append({
			"occupied": slot.occupied,
			"position": {"x": slot.global_position.x, "z": slot.global_position.z},
			"sector_data": slot.placed_card.card_data if slot.placed_card else null,
			"sector_advanced": bool(slot.placed_card.get("is_advanced")) if slot.placed_card else false,
			"optimize_count": slot.optimize_count,
			"max_optimizations": slot.max_optimizations,
			"is_optimized": slot.is_optimized,
			"triggered_levels": slot.triggered_levels.duplicate(),
			"last_placed_tech_cost": slot.last_placed_tech_cost,
			"tucked_cards": slot.tucked_cards.duplicate(true),
			"stored_supply": slot.stored_supply.duplicate(),
			"tech_data": tech_data,
		})
	return {
		"supply": supply_snap,
		"hand": hand_snap,
		"slots": slots_snap,
		"drag_card_data": drag_card_data,
		"drag_origin": drag_origin_val,
		"drag_market_slot": drag_market_slot,
	}

func restore_from_snapshot(snap: Dictionary) -> void:
	if _dragged_card:
		_dragged_card.queue_free()
		_dragged_card = null
		_drag_origin = DragOrigin.NONE
		_clear_slot_highlights()
	for color: CardData.SupplyColor in CardData.SupplyColor.values():
		_supply_ui.set_supply(color, snap["supply"][int(color)])
	_hand.clear()
	for cd: Variant in snap["hand"]:
		var card_data: CardData = cd as CardData
		if not card_data:
			continue
		var card: Node3D = _card_scene.instantiate()
		_hand.add_card(card)
		card.set_card_data(card_data)
	var drag_data: CardData = snap["drag_card_data"] as CardData
	if drag_data:
		var restored: Node3D = _card_scene.instantiate()
		add_child(restored)
		restored.set_card_data(drag_data)
		match snap["drag_origin"]:
			DragOrigin.HAND:
				_hand.add_card(restored)
			DragOrigin.MARKET:
				var slot_idx: int = snap["drag_market_slot"]
				if slot_idx >= 0:
					restored.set_meta("market_slot", slot_idx)
					restored.end_drag()
					if drag_data.card_type == CardData.CardType.EXPEDITION:
						_expedition_market.return_card(restored)
					else:
						_market.return_card(restored)
				else:
					restored.queue_free()
	for old_slot: SectorSlot in _sector_row.get_children().duplicate():
		_sector_row.remove_child(old_slot)
		old_slot.queue_free()
	for slot_snap: Dictionary in snap["slots"]:
		var pos: Dictionary = slot_snap.get("position", {})
		var slot: SectorSlot = _spawn_slot_at_pos(Vector3(pos.get("x", 0.0), 0.0, pos.get("z", 0.5)))
		slot.highlight(false)
		if not slot_snap["occupied"]:
			continue
		slot.tucked_cards = slot_snap["tucked_cards"]
		slot.stored_supply = slot_snap["stored_supply"]
		slot.refresh_display()
		var sec_data: CardData = slot_snap["sector_data"] as CardData
		if sec_data:
			var sec_card: Node3D = _card_scene.instantiate()
			add_child(sec_card)
			sec_card.global_position = slot.global_position + Vector3(0.0, 0.3, 0.0)
			if slot_snap["sector_advanced"]:
				sec_card.set("is_advanced", true)
			sec_card.set_card_data(sec_data)
			slot.accept_card(sec_card)
			sec_card.place()
		for td: Variant in slot_snap["tech_data"]:
			var tech_data: CardData = td as CardData
			if not tech_data:
				continue
			var tech_card: Node3D = _card_scene.instantiate()
			add_child(tech_card)
			tech_card.global_position = slot.global_position + Vector3(0.0, 0.3, 0.0)
			tech_card.set_card_data(tech_data)
			slot.accept_tech_card(tech_card)
			tech_card.place()
		slot.optimize_count = slot_snap["optimize_count"]
		slot.max_optimizations = slot_snap["max_optimizations"]
		slot.is_optimized = slot_snap["is_optimized"]
		slot.last_placed_tech_cost = slot_snap["last_placed_tech_cost"]
		if slot_snap.has("triggered_levels"):
			slot.triggered_levels = (slot_snap["triggered_levels"] as Array).duplicate()
		else:
			slot.triggered_levels.resize(slot.max_optimizations)
			slot.triggered_levels.fill(false)
			for j: int in slot.optimize_count:
				if j < slot.triggered_levels.size():
					slot.triggered_levels[j] = true
		slot.refresh_optimize_display()

func _update_optimize_state(slot: SectorSlot) -> Array[int]:
	if not slot.occupied or not slot.placed_card or not slot.placed_card.card_data:
		return []
	var cd: CardData = slot.placed_card.card_data
	var is_adv: bool = bool(slot.placed_card.get("is_advanced"))
	var pool: Array[int] = slot.get_placed_tech_colors()
	var result: Dictionary = OptimizeLogic.update_optimize_state(
		cd, is_adv, pool, slot.optimize_count, slot.max_optimizations, slot.triggered_levels)
	slot.optimize_count = result["optimize_count"]
	slot.is_optimized = result["is_optimized"]
	slot.triggered_levels = result["triggered_levels"] as Array[bool]
	slot.refresh_optimize_display()
	return result["triggered"] as Array[int]

# Called after a tech card is removed from a sector (e.g. Caldera Colony
# recycling a tucked tech) — a placement alone can never un-satisfy an
# already-triggered optimize level (it only ever adds colors), but a
# removal can, so this needs to run there too, not just after placements.
# Also fires optimize_triggered for the rare case where freeing up the pool
# indirectly lets an untriggered level satisfy now (see
# OptimizeLogic.update_optimize_state).
func revalidate_optimize_after_removal(slot: SectorSlot) -> void:
	for level: int in _update_optimize_state(slot):
		optimize_triggered.emit(slot, level)

func _handle_failed_drop() -> void:
	_end_arrow_drag()
	_cleanup_pending_dynamic_slot()
	var card: Node3D = _dragged_card
	var origin: DragOrigin = _drag_origin
	var start_pos: Vector3 = _drag_start_global_pos
	_dragged_card = null
	_drag_origin = DragOrigin.NONE
	_is_free_gain = false
	card.end_drag()
	match origin:
		DragOrigin.HAND:
			card.visible = true
			var t: Tween = card.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(card, "global_position", start_pos, 0.3)
			t.parallel().tween_property(card, "scale", Vector3.ONE * HAND_CARD_SCALE, 0.3)
			t.tween_callback(func() -> void: _hand.add_card(card, false))
		DragOrigin.MARKET:
			market_card_drag_failed.emit(card)
			card.collider.monitoring = false
			var t: Tween = card.create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
			# Vector3.ZERO here would leave the Collider Area3D with a singular
			# basis, which Jolt logs a warning about — see Card.NEGLIGIBLE_SCALE.
			t.tween_property(card, "scale", Vector3.ONE * Card.NEGLIGIBLE_SCALE, 0.25)
			t.tween_callback(func() -> void:
				if card.card_data and card.card_data.card_type == CardData.CardType.EXPEDITION:
					_expedition_market.return_card(card)
				else:
					_market.return_card(card)
					)

func _update_slot_highlights() -> void:
	var is_sector: bool = _is_sector_card()
	if is_sector:
		var snap_slot: SectorSlot = _find_nearest_empty_sector_slot()
		for slot: SectorSlot in _sector_row.get_children():
			slot.highlight(slot == snap_slot)
	else:
		var best_tech_slot: SectorSlot = _find_nearest_tech_slot()
		for slot: SectorSlot in _sector_row.get_children():
			slot.highlight(slot == best_tech_slot)

func _clear_slot_highlights() -> void:
	for slot: SectorSlot in _sector_row.get_children():
		slot.highlight(false)

func _mouse_to_plane(y: float) -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		return Vector3.ZERO
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = camera.project_ray_origin(mouse)
	var ray_dir: Vector3 = camera.project_ray_normal(mouse)
	if abs(ray_dir.y) < 0.001:
		return Vector3.ZERO
	var t: float = (y - ray_origin.y) / ray_dir.y
	return ray_origin + ray_dir * t
