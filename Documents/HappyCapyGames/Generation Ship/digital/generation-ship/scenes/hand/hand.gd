extends Node3D

signal card_drag_started(card: Node3D)
signal card_selected_for_discard(card: Node3D)
signal card_right_clicked(card: Node3D)

const CARD_SCALE: float = 0.4       # card node scale while in hand (GLB inside stays 2,2,1)
const SPACING: float = 0.25
const MAX_FAN_WIDTH: float = 1.25
const HOVER_LIFT: float = 0.50
const NEIGHBOR_PUSH: float = 0.05
const HOVER_SCALE: float = 1.15
const LAYOUT_DURATION: float = 0.2
const DRAW_STAGGER: float = 0.12

var _cards: Array[Node3D] = []
var _hovered_idx: int = -1
var _unhover_pending: bool = false

func add_card(card: Node3D, animate: bool = false) -> void:
	if _cards.has(card):
		return
	if card.get_parent() and card.get_parent() != self:
		card.reparent(self, true)
	elif not card.get_parent():
		add_child(card)
	_cards.append(card)
	card.managed_by_hand = true
	card.hovered.connect(_on_hovered)
	card.unhovered.connect(_on_unhovered)
	card.drag_started.connect(_on_drag_started)
	card.right_clicked.connect(_on_right_clicked)
	_layout(animate)

func animate_draw_cards(cards: Array[Node3D]) -> void:
	for i: int in cards.size():
		var card: Node3D = cards[i]
		if not _cards.has(card):
			continue
		var tp: Vector3 = card.position
		var ts: Vector3 = card.scale
		card.position = Vector3(tp.x, tp.y - 2.0, tp.z + 0.15)
		card.scale = Vector3(0.1, 0.1, 0.1)
		var tw: Tween = card.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_interval(float(i) * DRAW_STAGGER)
		tw.tween_property(card, "position", tp, 0.38)
		tw.parallel().tween_property(card, "scale", ts, 0.32)

func remove_card(card: Node3D) -> void:
	_hovered_idx = -1
	card.managed_by_hand = false
	_disconnect(card)
	if card.get_parent() == self:
		remove_child(card)
	_cards.erase(card)
	_layout(false)

func remove_card_fly_out(card: Node3D) -> void:
	_hovered_idx = -1
	card.managed_by_hand = false
	_disconnect(card)
	_cards.erase(card)
	_layout(true)
	_fly_out(card)

func detach_card(card: Node3D) -> void:
	_hovered_idx = -1
	card.managed_by_hand = false
	_disconnect(card)
	_cards.erase(card)
	_layout(true)

func set_discard_mode(active: bool) -> void:
	for card: Node3D in _cards:
		card.can_drag = not active
		if active:
			if not card.clicked.is_connected(_on_clicked_discard):
				card.clicked.connect(_on_clicked_discard)
		else:
			if card.clicked.is_connected(_on_clicked_discard):
				card.clicked.disconnect(_on_clicked_discard)

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

func _disconnect(card: Node3D) -> void:
	if card.hovered.is_connected(_on_hovered):
		card.hovered.disconnect(_on_hovered)
	if card.unhovered.is_connected(_on_unhovered):
		card.unhovered.disconnect(_on_unhovered)
	if card.drag_started.is_connected(_on_drag_started):
		card.drag_started.disconnect(_on_drag_started)
	if card.right_clicked.is_connected(_on_right_clicked):
		card.right_clicked.disconnect(_on_right_clicked)
	if card.clicked.is_connected(_on_clicked_discard):
		card.clicked.disconnect(_on_clicked_discard)

func _fly_out(card: Node3D) -> void:
	var tw: Tween = card.create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(card, "scale", Vector3.ZERO, 0.28)
	tw.tween_callback(func() -> void:
		if is_instance_valid(card):
			if card.get_parent():
				card.get_parent().remove_child(card)
			card.queue_free()
	)

func _on_hovered(card: Node3D) -> void:
	_unhover_pending = false
	_hovered_idx = _cards.find(card)
	_layout(true)

func _on_unhovered(_card: Node3D) -> void:
	_unhover_pending = true
	get_tree().create_timer(0.1).timeout.connect(func() -> void:
		if _unhover_pending:
			_unhover_pending = false
			_hovered_idx = -1
			_layout(true)
	)

func _on_drag_started(card: Node3D) -> void:
	detach_card(card)
	card.scale = Vector3.ONE
	card_drag_started.emit(card)

func _on_right_clicked(card: Node3D) -> void:
	card_right_clicked.emit(card)

func _on_clicked_discard(card: Node3D) -> void:
	set_discard_mode(false)
	_hovered_idx = -1
	card.managed_by_hand = false
	_disconnect(card)
	_cards.erase(card)
	_layout(true)
	_fly_out(card)
	card_selected_for_discard.emit(card)

func _layout(animate: bool) -> void:
	var n: int = _cards.size()
	if n == 0:
		return

	var spacing: float = SPACING
	if n > 1 and float(n - 1) * spacing > MAX_FAN_WIDTH:
		spacing = MAX_FAN_WIDTH / float(n - 1)

	var total_width: float = spacing * float(n - 1)
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() else null
	var mouse_y: float = get_viewport().get_mouse_position().y if get_viewport() else 0.0

	for i: int in n:
		var t: float = float(i) / float(max(n - 1, 1)) * 2.0 - 1.0
		var x: float = -total_width * 0.5 + float(i) * spacing

		if _hovered_idx >= 0 and i != _hovered_idx:
			var dist: int = i - _hovered_idx
			x += NEIGHBOR_PUSH * sign(float(dist)) / float(abs(dist))

		var y_arc: float = -(t * t) * 0.08
		var y_hover: float = 0.0
		if i == _hovered_idx:
			y_hover = HOVER_LIFT
			if cam:
				var base_sy: float = cam.unproject_position(to_global(Vector3(x, y_arc, 0.0))).y
				var lift_sy: float = cam.unproject_position(to_global(Vector3(x, y_arc + HOVER_LIFT, 0.0))).y
				var screen_lift: float = base_sy - lift_sy
				if screen_lift > 0.0:
					y_hover = HOVER_LIFT * clampf((base_sy - mouse_y) / screen_lift, 0.0, 1.0)

		var rot_z: float = t * deg_to_rad(-3.0)
		# Negative Z in hand-local space = closer to camera (world +Y). Stagger per index
		# so higher-index cards are always in front and win the raycast.
		var z_depth: float = -float(i) * 0.015
		if i == _hovered_idx:
			z_depth -= 0.05
		var target_pos: Vector3 = Vector3(x, y_arc + y_hover, z_depth)
		var base_scale: Vector3 = Vector3.ONE * CARD_SCALE
		var target_scale: Vector3 = base_scale * HOVER_SCALE if i == _hovered_idx else base_scale

		if animate:
			var tw: Tween = _cards[i].create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tw.tween_property(_cards[i], "position", target_pos, LAYOUT_DURATION)
			tw.parallel().tween_property(_cards[i], "rotation", Vector3(0.0, 0.0, rot_z), LAYOUT_DURATION)
			tw.parallel().tween_property(_cards[i], "scale", target_scale, LAYOUT_DURATION)
		else:
			_cards[i].position = target_pos
			_cards[i].rotation = Vector3(0.0, 0.0, rot_z)
			_cards[i].scale = target_scale
