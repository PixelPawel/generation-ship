extends Node3D

const DRAG_Y := 0.55
const HAND_CARD_SCALE := 0.392
const TECH_BACK_URL := "https://generationship.s3.eu-central-1.amazonaws.com/TTS/Tech/GS+Techs+44x67mm138.png"
const EXPEDITION_BACK_URL := "https://generationship.s3.eu-central-1.amazonaws.com/TTS/Expedition/GS+Expeditions++44x67mm27.png"
const DROP_RADIUS := 0.4
const TECH_COLUMN_HALF_X := 0.1
const DISCARD_RADIUS := 0.65
const PENDING_HOVER_Y := 0.05
const TECH_ZONE_Z_FRONT := 0.2
const TECH_ZONE_Z_BACK := 0.3
const MIN_SLOT_DISTANCE := 0.075
const _SLOT_SCENE := preload("res://scenes/board/sector_slot.tscn")

signal card_recycled(supply_color: CardData.SupplyColor)
signal major_action_changed(taken: bool)
signal market_card_taken(card_data: CardData)
signal market_drag_started(card: Node3D)
signal market_drag_resolved
signal bid_required(card: Node3D, slot: Node3D, min_cost: int, cost_color: CardData.SupplyColor, is_tech: bool)
signal payment_confirm_required(card: Node3D, slot: Node3D, pay_amounts: Dictionary, is_tech: bool)
signal supply_choice_required(card: Node3D, slot: Node3D, cost: int, options: Array[CardData.SupplyColor], is_tech: bool)
signal card_placed(card: Node3D, slot: SectorSlot)
signal optimize_triggered(slot: SectorSlot, level: int)
signal action_committed
signal sector_revealed(card_data: CardData, slot_idx: int)
signal market_card_drag_failed(card: Node3D)
signal expedition_card_shuffled_back(card_data: CardData, deck_insert_idx: int)
signal expedition_reveal_requested(slot_idx: int)
signal sector_info_requested(slot: SectorSlot)

enum DragOrigin { NONE, HAND, MARKET }

var _hand: Node3D = null
var _dragged_card: Node3D = null
var _drag_origin: DragOrigin = DragOrigin.NONE
var market_origin_3d: Vector3 = Vector3.ZERO
var _drag_start_global_pos: Vector3 = Vector3.ZERO
var _drag_start_scale: Vector3 = Vector3.ONE
var _major_action_taken: bool = false
var _view_only: bool = false
var _supply_ui: Control = null
var _card_scene: PackedScene = null
var _pending_card: Node3D = null
var _pending_slot: Node3D = null
var _pending_is_tech: bool = false
var _pending_pay_amounts: Dictionary = {}
var _pending_drag_origin: DragOrigin = DragOrigin.NONE
var _pending_cost: int = 0
var _is_free_gain: bool = false
var _is_auction_win: bool = false
var _pending_dynamic_slot: SectorSlot = null
var _pending_drop_pos: Vector3 = Vector3.ZERO
var _drag_arrow: DragArrow = null
var _is_arrow_drag: bool = false
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
	call_deferred("_refresh_slot_availability")
	var arrow_canvas: CanvasLayer = CanvasLayer.new()
	arrow_canvas.layer = 10
	add_child(arrow_canvas)
	_drag_arrow = DragArrow.new()
	arrow_canvas.add_child(_drag_arrow)

func _on_sector_slot_clicked(slot: SectorSlot) -> void:
	sector_info_requested.emit(slot)

func add_sector_slot(slot: SectorSlot) -> void:
	slot.reparent(_sector_row, true)
	if not slot.slot_clicked.is_connected(_on_sector_slot_clicked):
		slot.slot_clicked.connect(_on_sector_slot_clicked)

func _find_nearest_empty_sector_slot() -> SectorSlot:
	var pos: Vector3 = _dragged_card.global_position
	var best: SectorSlot = null
	var best_dist: float = DROP_RADIUS
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
	_tech_deck.setup(cards, TECH_BACK_URL)

func setup_expedition_deck(cards: Array[CardData]) -> void:
	_expedition_deck.setup(cards, EXPEDITION_BACK_URL)

func setup_market_ordered(sector_order: Array) -> void:
	_market.setup_ordered(_card_scene, CardDatabase.sectors, sector_order)
	_connect_market_signals()

func setup_expedition_deck_ordered(exp_order: Array) -> void:
	_expedition_deck.setup_ordered(CardDatabase.expeditions, exp_order, EXPEDITION_BACK_URL)

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

func begin_drag_card(card: Node3D) -> void:
	if card.card_data and card.card_data.card_type == CardData.CardType.EXPEDITION:
		_expedition_market.detach_card(card)
	elif card.card_data and card.card_data.card_type == CardData.CardType.SECTOR:
		_market.detach_advanced_card(card)
	market_origin_3d = card.global_position
	_drag_origin = DragOrigin.MARKET
	_begin_drag(card)

func begin_free_sector_gain(card: Node3D) -> void:
	if not GameNetwork.is_my_turn():
		return
	if card.is_advanced:
		_market.detach_advanced_card(card)
	else:
		var slot_idx: int = card.get_meta("market_slot", -1)
		if slot_idx >= 0:
			_market.detach_dust_card(slot_idx)
	market_origin_3d = card.global_position
	_is_free_gain = true
	_drag_origin = DragOrigin.MARKET
	_begin_drag(card)

func get_market() -> Node3D:
	return _market

func get_expedition_market() -> Node3D:
	return _expedition_market

func begin_panel_sector_drag(slot_idx: int, is_advanced: bool) -> void:
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
	_begin_drag(card)

func begin_panel_expedition_drag(slot_idx: int) -> void:
	if not GameNetwork.is_my_turn() or _major_action_taken:
		return
	var card: Node3D = _expedition_market.detach_top_card(slot_idx)
	if not card:
		return
	_drag_origin = DragOrigin.MARKET
	_begin_drag(card)

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

func refresh_discount_glow() -> void:
	for card: Node3D in _market.get_all_visible_cards():
		var cd: CardData = card.get("card_data") as CardData
		if cd:
			card.set_discount_glow(get_purchase_discount(cd, null) > 0)
	for card: Node3D in _expedition_market.get_all_visible_cards():
		var cd: CardData = card.get("card_data") as CardData
		if cd:
			card.set_discount_glow(get_purchase_discount(cd, null) > 0)
	if _hand:
		for card: Node3D in _hand.get_cards():
			var cd: CardData = card.get("card_data") as CardData
			if cd:
				card.set_discount_glow(get_purchase_discount(cd, null) > 0)

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
		for card_node: Node3D in slot.get_all_placed_cards():
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
					if placement_slot == slot and target.card_type == CardData.CardType.TECH:
						discount += 1
				"Seasons":
					if placement_slot == slot and target.card_type == CardData.CardType.TECH:
						discount += 2
	return discount

func generate_supply() -> Dictionary:
	var totals: Dictionary = {}
	for entry: Dictionary in get_supply_generators():
		totals[entry["color"]] = totals.get(entry["color"], 0) + 1
	return totals

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

func _draw_from_tech_deck() -> CardData:
	var data: CardData = _tech_deck.draw_card()
	if data == null and _discard_pile:
		var recycled: Array[CardData] = _discard_pile.take_all_cards()
		if not recycled.is_empty():
			_tech_deck.refill(recycled)
			data = _tech_deck.draw_card()
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

func set_view_only(enabled: bool) -> void:
	_view_only = enabled

func _on_hand_card_drag_started(card: Node3D) -> void:
	if not GameNetwork.is_my_turn() or _major_action_taken or _view_only:
		card.end_drag()
		_hand.add_card(card, true)
		return
	_drag_origin = DragOrigin.HAND
	_begin_drag(card)

func _on_market_card_drag_started(card: Node3D) -> void:
	if not GameNetwork.is_my_turn() or _major_action_taken or _view_only:
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
	if _drag_arrow != null:
		card.visible = false
		_is_arrow_drag = true
		var cam: Camera3D = get_viewport().get_camera_3d()
		var from_3d: Vector3 = market_origin_3d if _drag_origin == DragOrigin.MARKET else (_hand.global_position if _hand else _drag_start_global_pos)
		var from_2d: Vector2 = cam.unproject_position(from_3d)
		_drag_arrow.show_arrow(from_2d, from_2d)
	if _drag_origin == DragOrigin.MARKET:
		market_drag_started.emit(card)

func _process(_delta: float) -> void:
	if not _dragged_card:
		return
	var world_pos: Vector3 = _mouse_to_plane(DRAG_Y)
	_dragged_card.global_position = world_pos
	if _is_arrow_drag and _drag_arrow != null:
		var cam: Camera3D = get_viewport().get_camera_3d()
		var snap_slot: SectorSlot = _find_nearest_empty_sector_slot() if _is_sector_card() else _find_nearest_tech_slot()
		var to_2d: Vector2 = cam.unproject_position(snap_slot.global_position) if snap_slot else get_viewport().get_mouse_position()
		_drag_arrow.update_to(to_2d)
	_update_slot_highlights()

func _input(event: InputEvent) -> void:
	if not _dragged_card:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_try_drop()

func _is_sector_card() -> bool:
	return _dragged_card.card_data != null and _dragged_card.card_data.card_type == CardData.CardType.SECTOR

func _end_arrow_drag() -> void:
	if not _is_arrow_drag:
		return
	_is_arrow_drag = false
	if _drag_arrow:
		_drag_arrow.hide_arrow()
	if is_instance_valid(_dragged_card):
		var ctype: CardData.CardType = _dragged_card.card_data.card_type if _dragged_card.card_data else CardData.CardType.TECH
		if ctype != CardData.CardType.SECTOR and ctype != CardData.CardType.EXPEDITION:
			_dragged_card.visible = true

func _try_drop() -> void:
	_end_arrow_drag()
	_clear_slot_highlights()
	if _is_near_discard_pile():
		_do_recycle()
	elif _is_sector_card():
		_try_drop_sector()
	else:
		_try_drop_tech()

func _is_near_discard_pile() -> bool:
	if not _discard_pile or not _dragged_card:
		return false
	var dx: float = _dragged_card.global_position.x - _discard_pile.global_position.x
	var dz: float = _dragged_card.global_position.z - _discard_pile.global_position.z
	return sqrt(dx * dx + dz * dz) < DISCARD_RADIUS

func _do_recycle() -> void:
	var card: Node3D = _dragged_card
	_dragged_card = null
	_drag_origin = DragOrigin.NONE
	if card.card_data:
		card_recycled.emit(card.card_data.color)
	if _discard_pile:
		_discard_pile.add_discard(card.card_data)
	card.queue_free()

func _try_capture_drop_pos() -> bool:
	var pos: Vector3 = _dragged_card.global_position
	for slot: SectorSlot in _sector_row.get_children():
		if not slot.occupied:
			continue
		var dx: float = pos.x - slot.global_position.x
		var dz: float = pos.z - slot.global_position.z
		if sqrt(dx * dx + dz * dz) < MIN_SLOT_DISTANCE:
			return false
	_pending_drop_pos = pos
	return true

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

func _find_nearest_tech_slot() -> SectorSlot:
	var best: SectorSlot = null
	var best_dx: float = TECH_COLUMN_HALF_X
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
					_handle_failed_drop()
					return false
	var needs_confirm: bool = GameNetwork.is_multiplayer or not pay_amounts.is_empty()
	if needs_confirm:
		_start_payment_confirm(placed, slot, pay_amounts, is_tech)
		return false
	action_committed.emit()
	for col: CardData.SupplyColor in pay_amounts:
		_supply_ui.spend_supply(col, pay_amounts[col])
	return true

func _try_drop_sector() -> void:
	var target_slot: SectorSlot = _find_nearest_empty_sector_slot()
	if not target_slot:
		_handle_failed_drop()
		return
	var placed: Node3D = _dragged_card
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
		market_drag_resolved.emit()
		return
	if _is_auction_win:
		_dragged_card = null
		_drag_origin = DragOrigin.NONE
		_is_auction_win = false
		target_slot.accept_card(placed)
		placed.place()
		card_placed.emit(placed, target_slot)
		if placed.card_data:
			market_card_taken.emit(placed.card_data)
		market_drag_resolved.emit()
		return
	_pending_dynamic_slot = null
	if _should_bid(_dragged_card):
		_start_bid(_dragged_card, target_slot, false)
		return
	var origin: DragOrigin = _drag_origin
	var cd: CardData = placed.card_data
	if not _resolve_card_payment(placed, target_slot, false):
		return
	_dragged_card = null
	_drag_origin = DragOrigin.NONE
	target_slot.accept_card(placed)
	placed.place()
	card_placed.emit(placed, target_slot)
	if origin == DragOrigin.MARKET and cd:
		market_card_taken.emit(cd)
	market_drag_resolved.emit()

func _try_drop_tech() -> void:
	if _drag_origin == DragOrigin.HAND and _major_action_taken:
		_handle_failed_drop()
		return
	var best_sector: SectorSlot = _find_nearest_tech_slot()
	if not best_sector:
		_handle_failed_drop()
		return
	if _is_auction_win:
		var placed: Node3D = _dragged_card
		_dragged_card = null
		_drag_origin = DragOrigin.NONE
		_is_auction_win = false
		best_sector.accept_tech_card(placed)
		placed.place()
		var opt_levels: Array[int] = _update_optimize_state(best_sector)
		card_placed.emit(placed, best_sector)
		for level: int in opt_levels:
			optimize_triggered.emit(best_sector, level)
		market_drag_resolved.emit()
		return
	if _should_bid(_dragged_card):
		_start_bid(_dragged_card, best_sector, true)
		return
	var placed: Node3D = _dragged_card
	if not _resolve_card_payment(placed, best_sector, true):
		return
	_dragged_card = null
	_drag_origin = DragOrigin.NONE
	best_sector.accept_tech_card(placed)
	placed.place()
	var opt_levels: Array[int] = _update_optimize_state(best_sector)
	card_placed.emit(placed, best_sector)
	for level: int in opt_levels:
		optimize_triggered.emit(best_sector, level)
	market_drag_resolved.emit()

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
	var t: Tween = card.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(card, "global_position", slot.global_position + Vector3(0.0, PENDING_HOVER_Y, 0.0), 0.2)
	var min_cost: int
	var cost_color: CardData.SupplyColor
	if card.card_data.card_type == CardData.CardType.EXPEDITION:
		min_cost = card.card_data.cost
		cost_color = card.card_data.color
	else:
		min_cost = card.card_data.adv_cost
		cost_color = card.card_data.adv_color
	bid_required.emit(card, slot, min_cost, cost_color, is_tech)

func complete_purchase() -> void:
	if not _pending_card or not _pending_slot:
		return
	_pending_dynamic_slot = null
	set_major_action_taken()
	var card: Node3D = _pending_card
	var slot: Node3D = _pending_slot
	var is_tech: bool = _pending_is_tech
	var drag_origin: DragOrigin = _pending_drag_origin
	_pending_card = null
	_pending_slot = null
	_pending_is_tech = false
	_pending_drag_origin = DragOrigin.NONE
	var sector_slot: SectorSlot = slot as SectorSlot
	if not sector_slot:
		card_recycled.emit(card.card_data.color)
		card.queue_free()
		market_drag_resolved.emit()
		return
	if is_tech:
		if sector_slot.has_tech_space():
			sector_slot.accept_tech_card(card)
			card.place()
			var opt_levels_bid: Array[int] = _update_optimize_state(sector_slot)
			card_placed.emit(card, sector_slot)
			for level: int in opt_levels_bid:
				optimize_triggered.emit(sector_slot, level)
			if drag_origin == DragOrigin.MARKET and card.card_data:
				market_card_taken.emit(card.card_data)
		else:
			if card.card_data:
				add_to_discard(card.card_data)
			card_recycled.emit(card.card_data.color)
			card.queue_free()
	else:
		if not sector_slot.occupied:
			sector_slot.accept_card(card)
			card.place()
			_refresh_slot_availability()
			card_placed.emit(card, sector_slot)
			if drag_origin == DragOrigin.MARKET and card.card_data:
				market_card_taken.emit(card.card_data)
		else:
			card_recycled.emit(card.card_data.adv_color if card.is_advanced else card.card_data.color)
			card.queue_free()
	market_drag_resolved.emit()

func get_slot_index(slot: SectorSlot) -> int:
	return _sector_row.get_children().find(slot)

func accept_auction_win(card_data: CardData, slot_idx: int, is_tech: bool) -> bool:
	var card: Node3D = find_market_card(card_data)
	if not card:
		return false
	var slots: Array[SectorSlot] = get_all_sector_slots()
	var slot: SectorSlot = null
	if slot_idx >= 0 and slot_idx < slots.size():
		var candidate: SectorSlot = slots[slot_idx]
		if is_tech:
			if candidate.occupied and candidate.has_tech_space():
				slot = candidate
		else:
			if not candidate.occupied:
				slot = candidate
	if not slot:
		for s: SectorSlot in slots:
			if is_tech:
				if s.occupied and s.has_tech_space():
					slot = s
					break
			else:
				if not s.occupied:
					slot = s
					break
	if not slot:
		return false
	_pending_card = card
	_pending_slot = slot
	_pending_is_tech = is_tech
	_pending_drag_origin = DragOrigin.MARKET
	card.reparent(self, true)
	card.global_position = slot.global_position + Vector3(0.0, PENDING_HOVER_Y, 0.0)
	return true

func begin_auction_win_drag(cd: CardData) -> bool:
	var card: Node3D = find_market_card(cd)
	if not card:
		return false
	if cd.card_type == CardData.CardType.EXPEDITION:
		_expedition_market.detach_card(card)
	else:
		_market.detach_advanced_card(card)
	_is_auction_win = true
	_drag_origin = DragOrigin.MARKET
	_begin_drag(card)
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
	_refresh_slot_availability()
	market_drag_resolved.emit()

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

func _start_supply_choice(card: Node3D, slot: SectorSlot, cost: int, options: Array[CardData.SupplyColor], is_tech: bool) -> void:
	_pending_card = card
	_pending_slot = slot
	_pending_is_tech = is_tech
	_pending_cost = cost
	_pending_pay_amounts = {}
	_pending_drag_origin = _drag_origin
	_dragged_card = null
	_drag_origin = DragOrigin.NONE
	card.end_drag()
	var t: Tween = card.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(card, "global_position", slot.global_position + Vector3(0.0, PENDING_HOVER_Y, 0.0), 0.2)
	supply_choice_required.emit(card, slot, cost, options, is_tech)

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
	var t: Tween = card.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(card, "global_position", slot.global_position + Vector3(0.0, PENDING_HOVER_Y, 0.0), 0.2)
	payment_confirm_required.emit(card, slot, pay_amounts, is_tech)

func confirm_payment_with_allocations(allocations: Dictionary) -> void:
	_pending_pay_amounts = allocations
	confirm_payment()

func confirm_payment() -> void:
	if not _pending_card or not _pending_slot:
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
	if not slot:
		card.end_drag()
		return
	action_committed.emit()
	for col: CardData.SupplyColor in pay_amounts:
		_supply_ui.spend_supply(col, pay_amounts[col])
	if is_tech:
		slot.accept_tech_card(card)
		card.place()
		var opt_levels: Array[int] = _update_optimize_state(slot)
		card_placed.emit(card, slot)
		for level: int in opt_levels:
			optimize_triggered.emit(slot, level)
	else:
		slot.accept_card(card)
		card.place()
		_refresh_slot_availability()
		card_placed.emit(card, slot)
	if pay_origin == DragOrigin.MARKET and card.card_data:
		market_card_taken.emit(card.card_data)
	market_drag_resolved.emit()

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
	if origin == DragOrigin.HAND:
		_hand.add_card(card, true)
	elif card.card_data and card.card_data.card_type == CardData.CardType.EXPEDITION:
		_expedition_market.return_card(card)
	else:
		_market.return_card(card)
	market_drag_resolved.emit()

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

func _update_optimize_state(slot: SectorSlot) -> Array[int]:
	var triggered: Array[int] = []
	if not slot.occupied or not slot.placed_card or not slot.placed_card.card_data:
		return triggered
	var cd: CardData = slot.placed_card.card_data
	var is_adv: bool = bool(slot.placed_card.get("is_advanced"))
	var level_reqs: Array = [
		(cd.adv_opt1_req if is_adv else cd.opt1_req),
		(cd.adv_opt2_req if is_adv else []),
		(cd.adv_opt3_req if is_adv else []),
	]
	# Ensure triggered_levels is sized (guards against slots restored from old snapshots)
	if slot.triggered_levels.size() != slot.max_optimizations:
		slot.triggered_levels.resize(slot.max_optimizations)
		for i: int in slot.triggered_levels.size():
			if i >= slot.optimize_count:
				slot.triggered_levels[i] = false
	# Pool of placed tech colors; each level "consumes" its own required colors so
	# levels with identical requirements (e.g. Greenhouses) don't all fire at once.
	var pool: Array[int] = slot.get_placed_tech_colors()
	for level_idx: int in 3:
		var req: Array = level_reqs[level_idx]
		if req.is_empty():
			break
		if level_idx < slot.triggered_levels.size() and slot.triggered_levels[level_idx]:
			# Already triggered — remove its colors from the shared pool and skip.
			_consume_from_pool(pool, req)
			continue
		# Not yet triggered — check this level's own requirements against what's left.
		if _satisfies_optimize(pool, req):
			if level_idx < slot.triggered_levels.size():
				slot.triggered_levels[level_idx] = true
			slot.optimize_count += 1
			if slot.optimize_count >= slot.max_optimizations:
				slot.is_optimized = true
			triggered.append(level_idx + 1)
			_consume_from_pool(pool, req)
	return triggered

# Removes one instance of each required color from pool (specific colors first, ANY last).
func _consume_from_pool(pool: Array[int], req: Array[int]) -> void:
	var any_count: int = 0
	for r: int in req:
		if r == CardData.OPTIMIZE_ANY:
			any_count += 1
		else:
			var idx: int = pool.find(r)
			if idx >= 0:
				pool.remove_at(idx)
	for _i: int in any_count:
		if not pool.is_empty():
			pool.pop_back()

func _satisfies_optimize(placed: Array[int], required: Array[int]) -> bool:
	var counts: Dictionary = {}
	for c: int in placed:
		counts[c] = counts.get(c, 0) + 1
	var any_needed: int = 0
	for req: int in required:
		if req == CardData.OPTIMIZE_ANY:
			any_needed += 1
		else:
			if counts.get(req, 0) == 0:
				return false
			counts[req] -= 1
	var total_remaining: int = 0
	for v: Variant in counts.values():
		total_remaining += int(v)
	return total_remaining >= any_needed

func _handle_failed_drop() -> void:
	_end_arrow_drag()
	_cleanup_pending_dynamic_slot()
	var card: Node3D = _dragged_card
	var origin: DragOrigin = _drag_origin
	var start_pos: Vector3 = _drag_start_global_pos
	var start_scale: Vector3 = _drag_start_scale
	_dragged_card = null
	_drag_origin = DragOrigin.NONE
	_is_free_gain = false
	card.end_drag()
	match origin:
		DragOrigin.HAND:
			var t: Tween = card.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(card, "global_position", start_pos, 0.3)
			t.parallel().tween_property(card, "scale", Vector3.ONE * HAND_CARD_SCALE, 0.3)
			t.tween_callback(func() -> void: _hand.add_card(card, false))
			market_drag_resolved.emit()
		DragOrigin.MARKET:
			market_card_drag_failed.emit(card)
			var t: Tween = card.create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(card, "scale", Vector3.ZERO, 0.25)
			t.tween_callback(func() -> void:
				if card.card_data and card.card_data.card_type == CardData.CardType.EXPEDITION:
					_expedition_market.return_card(card)
				else:
					_market.return_card(card)
				market_drag_resolved.emit()
			)

func _refresh_slot_availability() -> void:
	pass

func _update_slot_highlights() -> void:
	if _discard_pile:
		_discard_pile.highlight(_is_near_discard_pile())
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
	if _discard_pile:
		_discard_pile.highlight(false)
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
