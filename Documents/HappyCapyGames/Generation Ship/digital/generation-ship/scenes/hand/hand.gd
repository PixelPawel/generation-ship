extends Node3D

signal card_drag_started(card: Node3D)
signal card_selected_for_discard(card: Node3D)
signal card_right_clicked(card: Node3D)

const HAND_SCALE := 0.392
const BASE_SPACING := 0.25
const MAX_HAND_WIDTH := 2.5
const CARD_WIDTH := 0.504
const MIN_SPACING := CARD_WIDTH * 0.29
const HOVER_LIFT := 0.50
const HOVER_NEIGHBOR_SHIFT := 0.3
const HOVER_SCALE := 0.686
const LAYOUT_DURATION := 0.2

var _cards: Array[Node3D] = []
var _hovered_index := -1

func add_card(card: Node3D, animate: bool = false) -> void:
	if _cards.has(card):
		return
	if card.get_parent() and card.get_parent() != self:
		card.reparent(self, true)
	elif not card.get_parent():
		add_child(card)
	_cards.append(card)
	card.managed_by_hand = true
	card.hovered.connect(_on_card_hovered)
	card.unhovered.connect(_on_card_unhovered)
	card.drag_started.connect(_on_card_drag_started)
	card.right_clicked.connect(_on_card_right_clicked)
	_layout(animate)

func animate_draw_cards(cards: Array[Node3D]) -> void:
	for i: int in cards.size():
		var card: Node3D = cards[i]
		if not _cards.has(card):
			continue
		var target_pos: Vector3 = card.position
		var target_scale: Vector3 = card.scale
		card.position = Vector3(target_pos.x, target_pos.y - 2.0, target_pos.z + 0.15)
		card.scale = Vector3(0.3, 0.3, 0.3)
		var t: Tween = card.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		t.tween_interval(float(i) * 0.12)
		t.tween_property(card, "position", target_pos, 0.38)
		t.parallel().tween_property(card, "scale", target_scale, 0.32)

func _disconnect_card_signals(card: Node3D) -> void:
	if card.hovered.is_connected(_on_card_hovered):
		card.hovered.disconnect(_on_card_hovered)
	if card.unhovered.is_connected(_on_card_unhovered):
		card.unhovered.disconnect(_on_card_unhovered)
	if card.drag_started.is_connected(_on_card_drag_started):
		card.drag_started.disconnect(_on_card_drag_started)
	if card.right_clicked.is_connected(_on_card_right_clicked):
		card.right_clicked.disconnect(_on_card_right_clicked)

func _fly_out_card(card: Node3D, on_done: Callable = Callable()) -> void:
	var t: Tween = card.create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(card, "scale", Vector3.ZERO, 0.28)
	t.tween_callback(func() -> void:
		if is_instance_valid(card):
			remove_child(card)
			card.queue_free()
		if on_done.is_valid():
			on_done.call()
	)

func remove_card(card: Node3D) -> void:
	_hovered_index = -1
	card.managed_by_hand = false
	_disconnect_card_signals(card)
	remove_child(card)
	_cards.erase(card)
	_layout(false)

func remove_card_fly_out(card: Node3D) -> void:
	_hovered_index = -1
	card.managed_by_hand = false
	_disconnect_card_signals(card)
	_cards.erase(card)
	_layout(true)
	_fly_out_card(card)

func detach_card(card: Node3D) -> void:
	_hovered_index = -1
	card.managed_by_hand = false
	_disconnect_card_signals(card)
	_cards.erase(card)
	_layout(true)

func set_discard_mode(active: bool) -> void:
	for card: Node3D in _cards:
		card.can_drag = not active
		if active:
			if not card.clicked.is_connected(_on_card_clicked_for_discard):
				card.clicked.connect(_on_card_clicked_for_discard)
		else:
			if card.clicked.is_connected(_on_card_clicked_for_discard):
				card.clicked.disconnect(_on_card_clicked_for_discard)

func get_cards() -> Array[Node3D]:
	return _cards.duplicate()

func get_card_data_list() -> Array[CardData]:
	var result: Array[CardData] = []
	for card: Node3D in _cards:
		if card.card_data:
			result.append(card.card_data)
	return result

func clear() -> void:
	for card: Node3D in _cards.duplicate():
		remove_card(card)
		card.queue_free()

func _on_card_clicked_for_discard(card: Node3D) -> void:
	set_discard_mode(false)
	_hovered_index = -1
	card.managed_by_hand = false
	_disconnect_card_signals(card)
	_cards.erase(card)
	_layout(true)
	_fly_out_card(card)
	card_selected_for_discard.emit(card)

func _on_card_right_clicked(card: Node3D) -> void:
	card_right_clicked.emit(card)

func _on_card_drag_started(card: Node3D) -> void:
	detach_card(card)
	card_drag_started.emit(card)

func _on_card_hovered(card: Node3D) -> void:
	_hovered_index = _cards.find(card)
	_layout(true)

func _on_card_unhovered(_card: Node3D) -> void:
	_hovered_index = -1
	_layout(true)

func _layout(animate: bool) -> void:
	var n := _cards.size()
	if n == 0:
		return

	var spacing := BASE_SPACING
	if n > 1 and (n - 1) * spacing > MAX_HAND_WIDTH:
		spacing = MAX_HAND_WIDTH / (n - 1)
	spacing = maxf(spacing, MIN_SPACING)
	var total_width := spacing * (n - 1)

	for i in n:
		var x := -total_width * 0.5 + i * spacing

		if _hovered_index >= 0 and i != _hovered_index:
			var dist := i - _hovered_index
			x += HOVER_NEIGHBOR_SHIFT * sign(float(dist)) / float(abs(dist))

		var t := float(i) / float(max(n - 1, 1)) * 2.0 - 1.0
		var y_arc := -(t * t) * 0.08
		var y_hover := HOVER_LIFT if i == _hovered_index else 0.0
		var rot_z := t * deg_to_rad(-3.0)
		var z_depth := 0.05 if i == _hovered_index else 0.0

		var target_pos := Vector3(x, y_arc + y_hover, z_depth)
		var target_scale := Vector3.ONE * HOVER_SCALE if i == _hovered_index else Vector3.ONE * HAND_SCALE

		if animate:
			var tween := _cards[i].create_tween()
			tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tween.tween_property(_cards[i], "position", target_pos, LAYOUT_DURATION)
			tween.parallel().tween_property(_cards[i], "rotation", Vector3(0.0, 0.0, rot_z), LAYOUT_DURATION)
			tween.parallel().tween_property(_cards[i], "scale", target_scale, LAYOUT_DURATION)
		else:
			_cards[i].position = target_pos
			_cards[i].rotation = Vector3(0.0, 0.0, rot_z)
			_cards[i].scale = target_scale
