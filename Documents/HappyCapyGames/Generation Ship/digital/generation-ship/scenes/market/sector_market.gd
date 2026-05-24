extends Node3D

signal card_drag_started(card: Node3D)
signal sector_revealed(card_data: CardData, slot_idx: int)
signal market_changed
signal reveal_mode_changed(active: bool)
signal card_revealed(slot_idx: int)

const CARD_ROTATION := Vector3(-PI / 2.0, 0.0, 0.0)
const STACK_Y_STEP := 0.015
const STACK_X_STEP := 0.008

var _adv_positions: Array[Vector3] = [
	Vector3(-0.55, 0.02, -0.73),
	Vector3(-0.55, 0.02,  0.0),
	Vector3(-0.55, 0.02,  0.73),
]
var _dust_positions: Array[Vector3] = [
	Vector3( 0.55, 0.02, -0.73),
	Vector3( 0.55, 0.02,  0.0),
	Vector3( 0.55, 0.02,  0.73),
]

var _dust_decks: Array = [[], [], []]
var _dust_display_cards: Array = [null, null, null]
var _advanced_stacks: Array = [[], [], []]
var _card_scene: PackedScene = null
var _in_reveal_mode: bool = false

func setup(card_scene: PackedScene, cards: Array[CardData]) -> void:
	_card_scene = card_scene
	var shuffled: Array[CardData] = cards.duplicate()
	shuffled.shuffle()
	for i: int in 3:
		var deck: Array = []
		for j: int in 10:
			deck.append(shuffled[i * 10 + j])
		_dust_decks[i] = deck
	for i: int in 3:
		_update_dust_display(i)

func setup_ordered(card_scene: PackedScene, cards: Array[CardData], order: Array) -> void:
	_card_scene = card_scene
	var ordered: Array[CardData] = []
	for idx: Variant in order:
		var i: int = int(idx)
		if i >= 0 and i < cards.size():
			ordered.append(cards[i])
	for i: int in 3:
		var deck: Array = []
		for j: int in 10:
			var card_idx: int = i * 10 + j
			if card_idx < ordered.size():
				deck.append(ordered[card_idx])
		_dust_decks[i] = deck
	for i: int in 3:
		_update_dust_display(i)

func reveal_round_cards() -> void:
	for i: int in 3:
		var slot_idx: int = i
		get_tree().create_timer(float(i) * 0.45).timeout.connect(
			func() -> void: _reveal_one_slot(slot_idx))

func sync_reveal_slot(slot_idx: int) -> void:
	_reveal_one_slot(slot_idx)

func _reveal_one_slot(slot_idx: int) -> CardData:
	var deck: Array = _dust_decks[slot_idx]
	if deck.is_empty():
		return null
	var data: CardData = deck.pop_back()
	_update_dust_display(slot_idx)
	var card: Node3D = _card_scene.instantiate()
	add_child(card)
	card.is_advanced = true
	card.set_card_data(data)
	card.set_meta("market_slot", slot_idx)
	card.position = _dust_positions[slot_idx]
	card.rotation = CARD_ROTATION + Vector3(0.0, PI, 0.0)
	_advanced_stacks[slot_idx].append(card)
	var top_idx: int = _advanced_stacks[slot_idx].size() - 1
	var target_pos: Vector3 = _adv_positions[slot_idx] + Vector3(STACK_X_STEP * top_idx, STACK_Y_STEP * top_idx, 0.0)
	_update_advanced_visuals(slot_idx, card)
	_play_reveal_animation(card, target_pos)
	market_changed.emit()
	card_revealed.emit(slot_idx)
	return data

func set_reveal_mode(active: bool) -> void:
	_in_reveal_mode = active
	reveal_mode_changed.emit(active)
	for i: int in 3:
		var card: Node3D = _dust_display_cards[i]
		if not card:
			continue
		card.can_drag = not active
		if active:
			if not card.clicked.is_connected(_on_dust_clicked_for_reveal):
				card.clicked.connect(_on_dust_clicked_for_reveal)
		else:
			if card.clicked.is_connected(_on_dust_clicked_for_reveal):
				card.clicked.disconnect(_on_dust_clicked_for_reveal)

func _on_dust_clicked_for_reveal(card: Node3D) -> void:
	var slot_idx: int = card.get_meta("market_slot", -1)
	if slot_idx < 0:
		return
	set_reveal_mode(false)
	var data: CardData = _reveal_one_slot(slot_idx)
	if data:
		sector_revealed.emit(data, slot_idx)

func _update_dust_display(deck_idx: int) -> void:
	if _dust_display_cards[deck_idx]:
		_dust_display_cards[deck_idx].queue_free()
		_dust_display_cards[deck_idx] = null
	var deck: Array = _dust_decks[deck_idx]
	if deck.is_empty():
		return
	var data: CardData = deck.back()
	var card: Node3D = _card_scene.instantiate()
	add_child(card)
	card.is_advanced = false
	card.set_card_data(data)
	card.position = _dust_positions[deck_idx]
	card.rotation = CARD_ROTATION
	card.set_meta("market_slot", deck_idx)
	card.drag_started.connect(_on_dust_card_drag_started)
	_dust_display_cards[deck_idx] = card

func _update_advanced_visuals(stack_idx: int, skip_card: Node3D = null) -> void:
	var stack: Array = _advanced_stacks[stack_idx]
	for i: int in stack.size():
		var card: Node3D = stack[i]
		var is_top: bool = i == stack.size() - 1
		if is_top:
			if not card.drag_started.is_connected(_on_card_drag_started):
				card.drag_started.connect(_on_card_drag_started)
		else:
			if card.drag_started.is_connected(_on_card_drag_started):
				card.drag_started.disconnect(_on_card_drag_started)
		if card == skip_card:
			continue
		var target_pos: Vector3 = _adv_positions[stack_idx] + Vector3(STACK_X_STEP * i, STACK_Y_STEP * i, 0.0)
		var t: Tween = card.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.tween_property(card, "position", target_pos, 0.3)
		t.parallel().tween_property(card, "rotation", CARD_ROTATION, 0.3)
		t.parallel().tween_property(card, "scale", Vector3.ONE, 0.3)

func _play_reveal_animation(card: Node3D, target_pos: Vector3) -> void:
	var lift_pos: Vector3 = card.position + Vector3(0.0, 0.28, 0.0)
	var t: Tween = card.create_tween()
	# Phase 1 — rise off the dust pile and scale up slightly
	t.tween_property(card, "position", lift_pos, 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.parallel().tween_property(card, "scale", Vector3.ONE * 1.12, 0.14)
	# Phase 2 — flip to reveal the advanced face
	t.tween_property(card, "rotation", CARD_ROTATION, 0.38).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	# Phase 3 — slide to the advanced stack position with a satisfying bounce settle
	t.tween_property(card, "position", target_pos, 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.parallel().tween_property(card, "scale", Vector3.ONE, 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func get_all_visible_cards() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for card: Node3D in _dust_display_cards:
		if card:
			result.append(card)
	for stack: Array in _advanced_stacks:
		for card: Node3D in stack:
			result.append(card)
	return result

func find_dust_card(cd: CardData) -> Node3D:
	for i: int in 3:
		var card: Node3D = _dust_display_cards[i] as Node3D
		if card and card.get("card_data") == cd:
			return card
	return null

func find_advanced_card(cd: CardData) -> Node3D:
	for stack: Array in _advanced_stacks:
		for card: Node3D in stack:
			if card.get("card_data") == cd:
				return card
	return null

func return_card(card: Node3D) -> void:
	var slot_idx: int = card.get_meta("market_slot", -1)
	if slot_idx < 0:
		return
	card.reparent(self, true)
	if card.is_advanced:
		_advanced_stacks[slot_idx].append(card)
		_update_advanced_visuals(slot_idx)
	else:
		_dust_decks[slot_idx].append(card.card_data)
		if _dust_display_cards[slot_idx]:
			_dust_display_cards[slot_idx].queue_free()
			_dust_display_cards[slot_idx] = null
		card.drag_started.connect(_on_dust_card_drag_started)
		_dust_display_cards[slot_idx] = card
		var t: Tween = card.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.tween_property(card, "position", _dust_positions[slot_idx], 0.3)
		t.parallel().tween_property(card, "rotation", CARD_ROTATION, 0.3)
		t.parallel().tween_property(card, "scale", Vector3.ONE, 0.3)
	market_changed.emit()

func _on_dust_card_drag_started(card: Node3D) -> void:
	var slot_idx: int = card.get_meta("market_slot", -1)
	if slot_idx >= 0:
		_dust_decks[slot_idx].pop_back()
		_dust_display_cards[slot_idx] = null
		if card.drag_started.is_connected(_on_dust_card_drag_started):
			card.drag_started.disconnect(_on_dust_card_drag_started)
		_update_dust_display(slot_idx)
	card_drag_started.emit(card)

func remove_card(cd: CardData) -> void:
	for i: int in 3:
		var stack: Array = _advanced_stacks[i]
		for j: int in stack.size():
			if stack[j].get("card_data") == cd:
				stack[j].queue_free()
				stack.remove_at(j)
				_update_advanced_visuals(i)
				market_changed.emit()
				return
	for i: int in 3:
		var idx: int = _dust_decks[i].find(cd)
		if idx >= 0:
			_dust_decks[i].remove_at(idx)
			_update_dust_display(i)
			market_changed.emit()
			return
			return

func detach_advanced_card(card: Node3D) -> void:
	var slot_idx: int = card.get_meta("market_slot", -1)
	if slot_idx >= 0 and slot_idx < _advanced_stacks.size():
		_advanced_stacks[slot_idx].erase(card)
		_update_advanced_visuals(slot_idx)
	if card.drag_started.is_connected(_on_card_drag_started):
		card.drag_started.disconnect(_on_card_drag_started)
	market_changed.emit()

func _on_card_drag_started(card: Node3D) -> void:
	detach_advanced_card(card)
	card_drag_started.emit(card)

# ── Panel accessors ───────────────────────────────────────────────────────────

func get_dust_card_data(slot_idx: int) -> CardData:
	var deck: Array = _dust_decks[slot_idx]
	return deck.back() as CardData if not deck.is_empty() else null

func get_dust_count(slot_idx: int) -> int:
	return _dust_decks[slot_idx].size()

func get_advanced_card_data(slot_idx: int) -> CardData:
	var stack: Array = _advanced_stacks[slot_idx]
	if stack.is_empty():
		return null
	return (stack.back() as Node3D).card_data as CardData

func get_advanced_count(slot_idx: int) -> int:
	return _advanced_stacks[slot_idx].size()

func get_advanced_top_node(slot_idx: int) -> Node3D:
	var stack: Array = _advanced_stacks[slot_idx]
	return stack.back() as Node3D if not stack.is_empty() else null

func detach_dust_card(slot_idx: int) -> Node3D:
	var card: Node3D = _dust_display_cards[slot_idx] as Node3D
	if not card:
		return null
	_dust_decks[slot_idx].pop_back()
	_dust_display_cards[slot_idx] = null
	if card.drag_started.is_connected(_on_dust_card_drag_started):
		card.drag_started.disconnect(_on_dust_card_drag_started)
	_update_dust_display(slot_idx)
	market_changed.emit()
	return card

func reveal_slot_panel(slot_idx: int) -> void:
	set_reveal_mode(false)
	var data: CardData = _reveal_one_slot(slot_idx)
	if data:
		sector_revealed.emit(data, slot_idx)
	market_changed.emit()
