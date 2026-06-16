extends Node3D

signal card_drag_started(card: Node3D)
signal card_shuffled_back(card_data: CardData, deck_insert_idx: int)
signal card_reveal_requested(slot_idx: int)
signal market_changed
signal card_added(slot_idx: int)
signal reveal_mode_changed(active: bool)

var _positions: Array[Vector3] = [
	Vector3(-0.7, 0.02, 0.0),
	Vector3( 0.0, 0.02, 0.0),
	Vector3( 0.7, 0.02, 0.0),
]
const CARD_ROTATION := Vector3(-PI / 2.0, 0.0, 0.0)
const STACK_Y_STEP := 0.015
const STACK_X_STEP := 0.008

var _stacks: Array = [[], [], []]
var _card_scene: PackedScene = null
var _expedition_deck: Node3D = null
var _shuffle_active: bool = false
var _reveal_active: bool = false

func setup(card_scene: PackedScene, expedition_deck: Node3D) -> void:
	_card_scene = card_scene
	_expedition_deck = expedition_deck
	add_round_cards()

func add_round_cards() -> void:
	for i: int in 3:
		var slot_idx: int = i
		get_tree().create_timer(float(i) * 0.45).timeout.connect(
			func() -> void: _add_card_to_slot(slot_idx))

func reveal_to_slot(slot_idx: int) -> CardData:
	return _add_card_to_slot(slot_idx)

func get_slot_sizes() -> Array[int]:
	var result: Array[int] = []
	for stack: Array in _stacks:
		result.append(stack.size())
	return result

func _add_card_to_slot(slot_idx: int) -> CardData:
	var data: CardData = _expedition_deck.draw_card()
	if not data:
		return null
	var card: Node3D = _card_scene.instantiate()
	add_child(card)
	card.set_card_data(data)
	card.set_meta("market_slot", slot_idx)
	_stacks[slot_idx].append(card)
	var top_idx: int = _stacks[slot_idx].size() - 1
	var target_pos: Vector3 = _positions[slot_idx] + Vector3(STACK_X_STEP * top_idx, STACK_Y_STEP * top_idx, 0.0)
	_update_slot_visuals(slot_idx, card)
	_play_reveal_animation(card, target_pos)
	market_changed.emit()
	card_added.emit(slot_idx)
	return data

func _play_reveal_animation(card: Node3D, target_pos: Vector3) -> void:
	card.position = target_pos
	card.rotation = CARD_ROTATION + Vector3(0.0, PI, 0.0)
	card.scale = Vector3.ONE
	var t: Tween = card.create_tween()
	t.tween_property(card, "position", target_pos + Vector3(0.0, 0.22, 0.0), 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.parallel().tween_property(card, "scale", Vector3.ONE * 1.12, 0.14)
	t.tween_property(card, "rotation", CARD_ROTATION, 0.38).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(card, "position", target_pos, 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.parallel().tween_property(card, "scale", Vector3.ONE, 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _update_slot_visuals(slot_idx: int, skip_card: Node3D = null) -> void:
	var stack: Array = _stacks[slot_idx]
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
		var base: Vector3 = _positions[slot_idx]
		var target_pos: Vector3 = base + Vector3(STACK_X_STEP * i, STACK_Y_STEP * i, 0.0)
		var t: Tween = card.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.tween_property(card, "position", target_pos, 0.3)
		t.parallel().tween_property(card, "rotation", CARD_ROTATION, 0.3)
		t.parallel().tween_property(card, "scale", Vector3.ONE, 0.3)

func set_shuffle_mode(active: bool) -> void:
	_shuffle_active = active
	_refresh_shuffle_connections()

func _refresh_connections(active: bool, callback: Callable) -> void:
	for stack: Array in _stacks:
		if stack.is_empty():
			continue
		var top: Node3D = stack.back() as Node3D
		if top.drag_started.is_connected(_on_card_drag_started):
			top.drag_started.disconnect(_on_card_drag_started)
		if top.clicked.is_connected(callback):
			top.clicked.disconnect(callback)
		if active:
			top.set("can_drag", false)
			top.clicked.connect(callback)
		else:
			top.set("can_drag", true)
			top.drag_started.connect(_on_card_drag_started)

func _refresh_shuffle_connections() -> void:
	_refresh_connections(_shuffle_active, _on_shuffle_card_clicked)

func shuffle_panel_slot(slot_idx: int) -> void:
	if not _shuffle_active:
		return
	var stack: Array = _stacks[slot_idx]
	if stack.is_empty():
		return
	_on_shuffle_card_clicked(stack.back() as Node3D)

func _on_shuffle_card_clicked(card: Node3D) -> void:
	var slot_idx: int = card.get_meta("market_slot", -1)
	if slot_idx < 0:
		return
	_stacks[slot_idx].erase(card)
	var data: CardData = card.get("card_data") as CardData
	var insert_idx: int = 0
	if data:
		insert_idx = _expedition_deck.shuffle_in(data)
	card.queue_free()
	_update_slot_visuals(slot_idx)
	card_shuffled_back.emit(data, insert_idx)
	if _shuffle_active:
		_refresh_shuffle_connections()

func get_all_visible_cards() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for stack: Array in _stacks:
		for card: Node3D in stack:
			result.append(card)
	return result

func find_card(cd: CardData) -> Node3D:
	for stack: Array in _stacks:
		for card: Node3D in stack:
			if card.get("card_data") == cd:
				return card
	return null

func remove_card(cd: CardData) -> void:
	for i: int in 3:
		var stack: Array = _stacks[i]
		for j: int in stack.size():
			if stack[j].get("card_data") == cd:
				stack[j].queue_free()
				stack.remove_at(j)
				_update_slot_visuals(i)
				market_changed.emit()
				return

func detach_card(card: Node3D) -> void:
	var slot_idx: int = card.get_meta("market_slot", -1)
	if slot_idx < 0:
		return
	_stacks[slot_idx].erase(card)
	if card.drag_started.is_connected(_on_card_drag_started):
		card.drag_started.disconnect(_on_card_drag_started)
	_update_slot_visuals(slot_idx)

func return_card(card: Node3D) -> void:
	var slot_idx: int = card.get_meta("market_slot", -1)
	if slot_idx < 0:
		return
	_stacks[slot_idx].append(card)
	card.reparent(self, true)
	_update_slot_visuals(slot_idx)
	market_changed.emit()

func set_reveal_mode(active: bool) -> void:
	_reveal_active = active
	reveal_mode_changed.emit(active)
	_refresh_reveal_connections()

func _refresh_reveal_connections() -> void:
	_refresh_connections(_reveal_active, _on_reveal_card_clicked)

func _on_reveal_card_clicked(card: Node3D) -> void:
	var slot_idx: int = card.get_meta("market_slot", -1)
	if slot_idx < 0:
		return
	card_reveal_requested.emit(slot_idx)

func _on_card_drag_started(card: Node3D) -> void:
	var slot_idx: int = card.get_meta("market_slot", -1)
	if slot_idx >= 0:
		_stacks[slot_idx].erase(card)
		_update_slot_visuals(slot_idx)
	if card.drag_started.is_connected(_on_card_drag_started):
		card.drag_started.disconnect(_on_card_drag_started)
	card_drag_started.emit(card)

# ── Panel accessors ───────────────────────────────────────────────────────────

func get_card_data(slot_idx: int) -> CardData:
	var stack: Array = _stacks[slot_idx]
	if stack.is_empty():
		return null
	return (stack.back() as Node3D).card_data as CardData

func get_count(slot_idx: int) -> int:
	return _stacks[slot_idx].size()

func detach_top_card(slot_idx: int) -> Node3D:
	var stack: Array = _stacks[slot_idx]
	if stack.is_empty():
		return null
	var card: Node3D = stack.back() as Node3D
	stack.erase(card)
	_update_slot_visuals(slot_idx)
	if card.drag_started.is_connected(_on_card_drag_started):
		card.drag_started.disconnect(_on_card_drag_started)
	market_changed.emit()
	return card
