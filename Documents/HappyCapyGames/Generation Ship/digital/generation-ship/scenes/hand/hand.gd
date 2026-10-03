extends Node3D

signal card_drag_started(card: Node3D)
signal card_selected_for_discard(card: Node3D)
signal card_right_clicked(card: Node3D)
signal card_inspect_requested(card: Node3D)

const HAND_SCALE := 0.392
const BASE_SPACING := 0.25
const MAX_HAND_WIDTH := 2.5
const CARD_WIDTH := 0.504
const MIN_SPACING := CARD_WIDTH * 0.29
const ENLARGE_LIFT := 0.2
const ENLARGE_SCALE := HAND_SCALE * 2.2
const LAYOUT_DURATION := 0.2
const ENLARGE_Z_DEPTH := 0.05
# Extra clearance beyond the enlarged card's own edge, so its neighbors
# part with a visible gap instead of just touching it.
const HOVER_PUSH_MARGIN := 0.05
# Total z spread across the whole resting hand, split evenly per card gap
# (see _layout) — fixed regardless of hand size so it always stays well
# under ENLARGE_Z_DEPTH, no matter how many cards are in hand.
const HAND_Z_MAX_STAGGER := 0.03

var _cards: Array[Node3D] = []
var _enlarged_index: int = -1
var _discard_mode_active: bool = false
# Set by Board via its arrow_drag_changed signal (see main.gd wiring) —
# suppresses hover-enlarge while a drag's targeting arrow is up, so mouse
# movement passing over other hand cards on the way to a slot doesn't pop
# them up too.
var _arrow_drag_active: bool = false

func set_arrow_drag_active(active: bool) -> void:
	_arrow_drag_active = active

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
	if not card.inspect_requested.is_connected(_on_card_inspect_requested):
		card.inspect_requested.connect(_on_card_inspect_requested)
	if GameTheme.is_touch() and not card.clicked.is_connected(_on_card_tapped):
		card.clicked.connect(_on_card_tapped)
	# detach_card() deliberately leaves right_clicked connected, so guard
	# against double-connecting when a card comes back after a failed drop.
	if not card.right_clicked.is_connected(_on_card_right_clicked):
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
	if card.clicked.is_connected(_on_card_tapped):
		card.clicked.disconnect(_on_card_tapped)

func _fly_out_card(card: Node3D, on_done: Callable = Callable()) -> void:
	card.collider.monitoring = false
	var t: Tween = card.create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	# Vector3.ZERO here would leave the Collider Area3D with a singular basis,
	# which Jolt logs a warning about — see Card.NEGLIGIBLE_SCALE.
	t.tween_property(card, "scale", Vector3.ONE * Card.NEGLIGIBLE_SCALE, 0.28)
	t.tween_callback(func() -> void:
		if is_instance_valid(card):
			remove_child(card)
			card.queue_free()
		if on_done.is_valid():
			on_done.call()
	)

func remove_card(card: Node3D) -> void:
	_enlarged_index = -1
	card.managed_by_hand = false
	_disconnect_card_signals(card)
	remove_child(card)
	_cards.erase(card)
	_layout(false)

func remove_card_fly_out(card: Node3D) -> void:
	_enlarged_index = -1
	card.managed_by_hand = false
	_disconnect_card_signals(card)
	_cards.erase(card)
	_layout(true)
	_fly_out_card(card)

func detach_card(card: Node3D) -> void:
	_enlarged_index = -1
	card.managed_by_hand = false
	if card.hovered.is_connected(_on_card_hovered):
		card.hovered.disconnect(_on_card_hovered)
	if card.unhovered.is_connected(_on_card_unhovered):
		card.unhovered.disconnect(_on_card_unhovered)
	if card.drag_started.is_connected(_on_card_drag_started):
		card.drag_started.disconnect(_on_card_drag_started)
	# right_clicked is intentionally NOT disconnected here. This is called
	# the instant a real drag starts (mousedown starts dragging immediately —
	# see Card._on_input_event) as well as on a recycle request — a started
	# drag can still fail (miss every slot) and leave the card sitting right
	# back in its hand position, fully visible and clickable, for the ~0.3s
	# return animation before add_card() re-adds it. Recycling needs to keep
	# working through that window instead of silently going dead.
	_cards.erase(card)
	_layout(true)

func set_discard_mode(active: bool) -> void:
	_discard_mode_active = active
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
	_enlarged_index = -1
	card.managed_by_hand = false
	_disconnect_card_signals(card)
	_cards.erase(card)
	_layout(true)
	_fly_out_card(card)
	card_selected_for_discard.emit(card)

func _on_card_right_clicked(card: Node3D) -> void:
	card_right_clicked.emit(card)

func _on_card_inspect_requested(card: Node3D) -> void:
	card_inspect_requested.emit(card)

# Phones: a tap picks the card up the same way a drag does — the targeting arrow
# points at where it would go, and the next tap places it there (or, anywhere
# that isn't a slot, puts it back). Discard mode keeps its own tap handling.
func _on_card_tapped(card: Node3D) -> void:
	if _discard_mode_active or not _cards.has(card) or not card.can_drag:
		return
	card.set("is_dragging", true)
	_on_card_drag_started(card)

func _on_card_drag_started(card: Node3D) -> void:
	detach_card(card)
	card_drag_started.emit(card)

# Hovering enlarges the card — skipped entirely while the drag-targeting
# arrow is up (see set_arrow_drag_active), so a drag's mouse movement
# passing over other hand cards on its way to a slot doesn't pop them up too.
func _on_card_hovered(card: Node3D) -> void:
	if _arrow_drag_active:
		return
	_enlarged_index = _cards.find(card)
	_layout(true)

# Shrinks the card back down once the mouse actually leaves it — but only
# if it's still the one currently enlarged by the time this fires (a short
# delay smooths over brief accidental un-hovers), so a stale timer from an
# earlier card can't clobber a different card enlarged in the meantime.
func _on_card_unhovered(card: Node3D) -> void:
	var idx: int = _cards.find(card)
	if idx == -1 or idx != _enlarged_index:
		return
	get_tree().create_timer(0.1).timeout.connect(func() -> void:
		if _enlarged_index == idx:
			_enlarged_index = -1
			_layout(true)
	)

func _layout(animate: bool) -> void:
	var n := _cards.size()
	if n == 0:
		return

	var spacing := BASE_SPACING
	if n > 1 and (n - 1) * spacing > MAX_HAND_WIDTH:
		spacing = MAX_HAND_WIDTH / (n - 1)
	spacing = maxf(spacing, MIN_SPACING)
	var total_width := spacing * (n - 1)
	var z_step: float = HAND_Z_MAX_STAGGER / float(max(n - 1, 1))

	# The enlarged card scales up to ENLARGE_SCALE while every other card
	# stays at its normal evenly-spaced x — without this, its much wider
	# rendered width just overlaps (and visually hides) its immediate
	# neighbors instead of the hand parting around it.
	var push: float = 0.0
	if _enlarged_index != -1:
		push = CARD_WIDTH * (ENLARGE_SCALE - HAND_SCALE) * 0.5 + HOVER_PUSH_MARGIN

	for i in n:
		var x := -total_width * 0.5 + i * spacing
		if i < _enlarged_index:
			x -= push
		elif i > _enlarged_index:
			x += push

		var t := float(i) / float(max(n - 1, 1)) * 2.0 - 1.0
		var y_hover := ENLARGE_LIFT if i == _enlarged_index else 0.0
		var rot_z := t * deg_to_rad(-3.0)
		# Every resting card used to sit at the exact same z (0.0), which is a
		# real problem here specifically: the card face shader
		# (card_sheen.gdshader) renders with depth_draw_never +
		# depth_test_disabled, so overlapping cards have no depth buffer to
		# fall back on at all — ordering comes entirely from Godot's
		# transparent-sort distance tiebreak, which is ambiguous (and prone to
		# picking the wrong side) when two cards are exactly tied. A newly
		# drawn card landing back on z=0.0 after its fly-in tween could lose
		# that tie against an already-settled neighbor and render behind it
		# until something (e.g. hover-enlarging it) gave it a decisive z. A
		# small per-index stagger removes the tie entirely: later hand
		# positions sit a hair closer to the camera, so draw order no longer
		# depends on instance/tween history.
		var z_depth := ENLARGE_Z_DEPTH if i == _enlarged_index else float(i) * z_step

		var target_pos := Vector3(x, y_hover, z_depth)
		var target_scale := Vector3.ONE * ENLARGE_SCALE if i == _enlarged_index else Vector3.ONE * HAND_SCALE

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
