class_name Card
extends Node3D

static var screen_shake_enabled: bool = true

signal hovered(card: Node3D)
signal unhovered(card: Node3D)
signal drag_started(card: Node3D)
signal clicked(card: Node3D)
signal right_clicked(card: Node3D)
signal elevation_started(card: Node3D)
signal elevation_ended(card: Node3D)
# Phones: press and hold a hand card to read it big (see CardInspectOverlay).
signal inspect_requested(card: Node3D)

const HOVER_HEIGHT := 0.15
const HOVER_DURATION := 0.15
const PLACED_LIFT_HEIGHT: float = 0.85
const PLACED_LIFT_SCALE: float = 3.0
const PLACED_LIFT_DURATION: float = 0.35
const PLACED_LIFT_CENTER_PULL: float = 0.9
const DRAG_THRESHOLD_PX: float = 8.0
# Jolt rejects a near-zero scale on a node with an Area3D collider (treats
# the transform's basis as singular) — use this instead of Vector3.ZERO
# anywhere a card needs to read as "vanished" (market-inspect/reveal-display
# clones here, and hand.gd's fly-out-and-remove animation). 0.001 turned out
# to still be within Jolt's near-zero tolerance; 0.02 is comfortably clear of
# it and still reads as invisible at normal viewing distance. Public (no
# leading underscore) so other scripts share this exact tuned value instead
# of re-guessing their own.
const NEGLIGIBLE_SCALE: float = 0.02
const _LANDSCAPE_CHILD_SCALE := Vector3(0.88 / 0.63, 0.63 / 0.88, 1.0)

const _TECH_GLB := preload("res://assets/3d/gs_card_tech.glb")
const _SECTOR_GLB := preload("res://assets/3d/gs_card_sector.glb")
const _EXPEDITION_GLB := preload("res://assets/3d/gs_card_expedition.glb")

static var _elev_counter: int = 0
static var _any_dragging: bool = false

var managed_by_hand := false
var can_drag: bool = true
var drag_needs_movement: bool = false
var can_elevate: bool = true
var is_dragging := false
var is_placed := false
var is_advanced := false
var card_data: CardData = null
var _elev_rest_pos: Vector3 = Vector3.ZERO
var _elev_rest_scale: Vector3 = Vector3.ONE
var _elev_rest_rotation: Vector3 = Vector3.ZERO
var _elev_rest_sort_order: float = 0.0
var _tween: Tween
var _flying: bool = false  # mid fly_to_rest()
var _placed_elevated: bool = false
var _destroy_on_collapse: bool = false
var _drag_armed: bool = false
var _drag_arm_pos: Vector2 = Vector2.ZERO
# Phones: tap-and-hold on a placed card = right-click (enlarge/shrink).
var _long_press: LongPressGesture = LongPressGesture.new()
var _suppress_tap: bool = false   # the hold that opened the inspect view isn't also a tap
var _card_glb: Node3D = null
var _face_surface: MeshInstance3D = null
var _discount_badge: Label3D = null

@onready var card_mesh: MeshInstance3D = $CardMesh
@onready var collider: Area3D = $Collider

func _ready() -> void:
	add_to_group("cards")
	var mat := card_mesh.get_surface_override_material(0) as ShaderMaterial
	if mat:
		var m: ShaderMaterial = mat.duplicate() as ShaderMaterial
		m.render_priority = 1
		card_mesh.set_surface_override_material(0, m)
	collider.mouse_entered.connect(_on_hover_enter)
	collider.mouse_exited.connect(_on_hover_exit)
	collider.input_event.connect(_on_input_event)

func set_card_data(data: CardData) -> void:
	card_data = data
	if not data:
		return
	_instantiate_glb(data.card_type)
	var is_landscape := (data.card_type == CardData.CardType.SECTOR)
	var child_scale := _LANDSCAPE_CHILD_SCALE if is_landscape else Vector3.ONE
	card_mesh.scale = child_scale
	collider.scale = child_scale
	var art_path: String = data.adv_local_art_path if is_advanced else data.local_art_path
	if not art_path.is_empty():
		var local_tex: Texture2D = load(art_path) as Texture2D
		if local_tex:
			_apply_texture(local_tex)
			return
	var url: String = data.adv_image_url if is_advanced else data.image_url
	if url.is_empty():
		return
	var tex: Texture2D = ImageCache.get_texture(url)
	if tex:
		_apply_texture(tex)

# Broadcast via get_tree().call_group("cards", ...) from pause_menu.gd after
# a locale change, so face-up cards already on screen re-pull their texture
# (card_data's local_art_path/adv_local_art_path were just re-resolved by
# CardDatabase.refresh_locale()). Face-down cards aren't covered — deck-back
# art is currently English-only regardless of locale, so there's nothing to
# refresh there yet.
func refresh_locale_art() -> void:
	if card_data:
		set_card_data(card_data)

func _instantiate_glb(card_type: CardData.CardType) -> void:
	if _card_glb:
		_card_glb.queue_free()
		_card_glb = null
		_face_surface = null
	var scene: PackedScene
	match card_type:
		CardData.CardType.TECH: scene = _TECH_GLB
		CardData.CardType.SECTOR: scene = _SECTOR_GLB
		CardData.CardType.EXPEDITION: scene = _EXPEDITION_GLB
	if not scene:
		return
	_card_glb = scene.instantiate()
	_card_glb.scale = Vector3(14.0, 14.0, 7.0)
	_card_glb.visible = false
	add_child(_card_glb)
	_face_surface = _card_glb.find_child("*screen_image*", true, false) as MeshInstance3D

func _apply_texture(tex: Texture2D) -> void:
	var mat: ShaderMaterial = card_mesh.get_surface_override_material(0) as ShaderMaterial
	if mat:
		mat.set_shader_parameter("card_texture", tex)

func _on_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int) -> void:
	if event is InputEventMouseMotion:
		_long_press.update_position((event as InputEventMouseMotion).position)
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		var touch_hand: bool = GameTheme.is_touch() and managed_by_hand and not is_placed
		if GameTheme.is_touch() and (is_placed or _placed_elevated):
			if event.pressed:
				_long_press.begin(get_tree(), event.position, _try_toggle_placed_elevation)
			else:
				_long_press.end()
		elif touch_hand:
			# a hand card on a phone: hold = inspect, move = drag, tap = pick up (tap-to-place)
			if event.pressed:
				_suppress_tap = false
				_long_press.begin(get_tree(), event.position, _on_hand_long_press)
			else:
				_long_press.end()
				if _suppress_tap:
					_suppress_tap = false
					_drag_armed = false
					return
		if event.pressed:
			if not is_placed and can_drag and not is_dragging:
				if drag_needs_movement or touch_hand:
					_drag_armed = true
					_drag_arm_pos = get_viewport().get_mouse_position()
				else:
					is_dragging = true
					_any_dragging = true
					drag_started.emit(self)
		else:
			_drag_armed = false
			if is_placed:
				# Left-click/tap-to-enlarge is intentionally Collection-only
				# (see collection_popup.gd) — a placed card on the actual
				# board only enlarges via right-click (desktop), matching
				# the original pre-touch-parity behavior here.
				return
			if (not can_drag or not is_dragging) and not _any_dragging:
				clicked.emit(self)
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if is_placed or _placed_elevated:
			_try_toggle_placed_elevation()
		else:
			right_clicked.emit(self)

func _on_hand_long_press() -> void:
	_drag_armed = false
	_suppress_tap = true
	inspect_requested.emit(self)

func _try_toggle_placed_elevation() -> void:
	if is_placed:
		if can_elevate and not _any_dragging:
			toggle_elevation(_elevate_target_local(global_position), Vector3.ONE * PLACED_LIFT_SCALE, 0.0)
	elif _placed_elevated:
		toggle_elevation(Vector3.ZERO, Vector3.ONE, 0.0)

func _input(event: InputEvent) -> void:
	if not _drag_armed:
		return
	if event is InputEventMouseMotion:
		if (event.position - _drag_arm_pos).length() >= DRAG_THRESHOLD_PX:
			_drag_armed = false
			_long_press.cancel()
			is_dragging = true
			_any_dragging = true
			drag_started.emit(self)

func _elevate_target_local(from_world_pos: Vector3) -> Vector3:
	var elev_global := Vector3(
		lerpf(from_world_pos.x, 0.0, PLACED_LIFT_CENTER_PULL),
		PLACED_LIFT_HEIGHT,
		lerpf(from_world_pos.z, 0.0, PLACED_LIFT_CENTER_PULL)
	)
	return (get_parent() as Node3D).to_local(elev_global)

# Enlarges a standalone card (e.g. a disposable market-inspect clone, parented
# under a node that's actually visible). Starts at zero scale at
# vanish_target_world (e.g. a point behind the screen it's inspecting) and
# grows toward elev_target_world (e.g. partway to the camera), so it reads as
# emerging from the screen — the exact time-reversal of collapsing, which
# shrinks back down to that same vanish point before self-destructing, rather
# than returning to a "rest" position that only makes sense for a card that's
# staying around.
func enlarge_from(elev_target_world: Vector3, vanish_target_world: Vector3, elev_scale: Vector3 = Vector3.ONE * PLACED_LIFT_SCALE) -> void:
	if _placed_elevated:
		return
	_destroy_on_collapse = true
	var parent: Node3D = get_parent() as Node3D
	global_position = vanish_target_world
	scale = Vector3.ONE * NEGLIGIBLE_SCALE
	_elev_rest_pos = parent.to_local(vanish_target_world) if parent else vanish_target_world
	_elev_rest_scale = Vector3.ONE * NEGLIGIBLE_SCALE
	var target_local: Vector3 = parent.to_local(elev_target_world) if parent else elev_target_world
	toggle_elevation(target_local, elev_scale, 0.0)

func toggle_elevation(elev_pos: Vector3, elev_scale: Vector3, grace_sec: float) -> void:
	if _flying:
		return
	if _placed_elevated:
		_collapse_elevation()
		return
	_elev_rest_sort_order = card_mesh.sorting_offset
	_elev_rest_rotation = global_rotation
	_elev_counter += 1
	set_sort_order(float(_elev_counter))
	_kill_tween()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "position", elev_pos, PLACED_LIFT_DURATION)
	_tween.parallel().tween_property(self, "scale", elev_scale, PLACED_LIFT_DURATION)
	_tween.parallel().tween_property(self, "global_rotation", Vector3(deg_to_rad(-90.0), global_rotation.y, global_rotation.z), PLACED_LIFT_DURATION)
	_placed_elevated = true
	elevation_started.emit(self)
	if grace_sec > 0.0:
		get_tree().create_timer(grace_sec).timeout.connect(func() -> void:
			if _placed_elevated:
				_collapse_elevation()
		)

func _collapse_elevation() -> void:
	_placed_elevated = false
	set_sort_order(_elev_rest_sort_order)
	_kill_tween()
	_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "position", _elev_rest_pos, PLACED_LIFT_DURATION)
	_tween.parallel().tween_property(self, "scale", _elev_rest_scale, PLACED_LIFT_DURATION)
	_tween.parallel().tween_property(self, "global_rotation", _elev_rest_rotation, PLACED_LIFT_DURATION)
	if _destroy_on_collapse:
		_tween.tween_callback(queue_free)
	elevation_ended.emit(self)

# Shows a "-N" badge next to the printed cost (cost reductions only ever
# apply to tech cards, so this is only ever called for hand cards — see
# Board.refresh_hand_discounts()).
func set_discount(amount: int) -> void:
	if amount <= 0:
		if _discount_badge:
			_discount_badge.visible = false
		return
	if not _discount_badge:
		_discount_badge = _make_discount_badge()
	_discount_badge.text = "-%d" % amount
	_discount_badge.visible = true

func _make_discount_badge() -> Label3D:
	var lbl := Label3D.new()
	lbl.font_size = 32
	lbl.pixel_size = 0.003
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.render_priority = 2
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.modulate = Color(0.35, 1.0, 0.45)
	lbl.outline_size = 6
	lbl.outline_modulate = Color.BLACK
	lbl.position = Vector3(-0.08, 0.35, 0.015)
	add_child(lbl)
	return lbl

func set_sort_order(priority: float) -> void:
	card_mesh.sorting_offset = priority

func end_drag() -> void:
	is_dragging = false
	_any_dragging = false
	card_mesh.sorting_offset = 0.0

func collapse_if_elevated() -> void:
	if _placed_elevated:
		_collapse_elevation()

func is_elevated() -> bool:
	return _placed_elevated

# True while this card is showing as a market-inspect enlargement (right-click
# from the market screen) rather than a normal placed-card elevation — see
# enlarge_from(), which is the only place _destroy_on_collapse gets set.
func is_market_inspecting() -> bool:
	return _destroy_on_collapse

func set_face_down(back_path: String) -> void:
	can_drag = false
	collider.input_ray_pickable = false
	if back_path.is_empty():
		return
	var tex: Texture2D = ImageCache.get_texture(back_path)
	if not tex:
		tex = load(back_path) as Texture2D
	if tex:
		_apply_texture(tex)

func place() -> void:
	is_dragging = false
	_any_dragging = false
	is_placed = true
	visible = true
	_kill_tween()
	# A card flying in from the market screen gets its sparkle/shake on
	# landing instead (see fly_to_rest), not back at the screen.
	if not _flying:
		_spawn_sparkle()
		_shake_camera()
	set_discount(0)

# Market placements: the card emerges small from the market screen
# (from_global), arcs up and over to its slot while turning onto the board,
# then settles with the same overshoot as the market reveal animation
# (see ExpeditionMarket._play_reveal_animation). rest_pos/rest_rot are local
# to the card's (already reparented) slot. done runs after it lands.
const FLY_DURATION: float = 0.55
const FLY_SETTLE_DURATION: float = 0.32
const FLY_ARC_HEIGHT: float = 0.6
const FLY_SETTLE_LIFT: float = 0.12

func fly_to_rest(from_global: Vector3, rest_pos: Vector3, rest_rot: Vector3, done: Callable = Callable()) -> void:
	var parent: Node3D = get_parent() as Node3D
	if not parent:
		position = rest_pos
		rotation = rest_rot
		return
	_flying = true
	_kill_tween()
	var start: Vector3 = parent.to_local(from_global)
	var hover: Vector3 = rest_pos + Vector3(0.0, FLY_SETTLE_LIFT, 0.0)
	var mid_global: Vector3 = (from_global + parent.to_global(hover)) * 0.5 + Vector3.UP * FLY_ARC_HEIGHT
	var control: Vector3 = parent.to_local(mid_global)
	position = start
	scale = Vector3.ONE * 0.35
	var t: Tween = create_tween()
	t.tween_method(func(k: float) -> void:
		var a: Vector3 = start.lerp(control, k)
		var b: Vector3 = control.lerp(hover, k)
		position = a.lerp(b, k)
	, 0.0, 1.0, FLY_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(self, "rotation", rest_rot, FLY_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	t.parallel().tween_property(self, "scale", Vector3.ONE * 1.12, FLY_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(self, "position", rest_pos, FLY_SETTLE_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.parallel().tween_property(self, "scale", Vector3.ONE, FLY_SETTLE_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_callback(func() -> void:
		_flying = false
		_spawn_sparkle()
		_shake_camera()
		if done.is_valid():
			done.call()
	)

func _spawn_sparkle() -> void:
	var fx: CPUParticles3D = load("res://scenes/card/card_sparkle.gd").new()
	if card_data:
		fx.set("particle_color", _supply_sparkle_color(card_data.color))
	var parent: Node = get_parent()
	if parent:
		parent.add_child(fx)
		fx.global_position = global_position + Vector3(0.0, 0.05, 0.0)

func _supply_sparkle_color(supply: CardData.SupplyColor) -> Color:
	match supply:
		CardData.SupplyColor.DUST:     return Color(0.85, 0.75, 0.55)
		CardData.SupplyColor.METALS:   return Color(0.55, 0.75, 0.95)
		CardData.SupplyColor.LIQUIDS:  return Color(0.20, 0.60, 1.00)
		CardData.SupplyColor.ORGANIX:  return Color(0.25, 0.90, 0.35)
		CardData.SupplyColor.ELECTRIX: return Color(0.95, 0.90, 0.15)
		CardData.SupplyColor.THRUST:   return Color(1.00, 0.42, 0.10)
	return Color(1.00, 0.85, 0.05)

func shake_camera() -> void:
	_shake_camera()

func _shake_camera() -> void:
	if not screen_shake_enabled:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if not cam:
		return
	var t: Tween = cam.create_tween()
	t.tween_property(cam, "h_offset", randf_range(-0.04, 0.04), 0.05).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(cam, "v_offset", randf_range(-0.02, 0.02), 0.05).set_ease(Tween.EASE_OUT)
	t.tween_property(cam, "h_offset", 0.0, 0.12).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(cam, "v_offset", 0.0, 0.12).set_ease(Tween.EASE_OUT)

func _on_hover_enter() -> void:
	CursorManager.set_hover()
	hovered.emit(self)
	if is_placed or _destroy_on_collapse:
		return
	if not managed_by_hand and not is_dragging:
		_kill_tween()
		_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		_tween.tween_property(self, "position:y", HOVER_HEIGHT, HOVER_DURATION)

func _on_hover_exit() -> void:
	CursorManager.set_default()
	if not is_dragging:
		unhovered.emit(self)
	if is_placed or _destroy_on_collapse:
		return
	_kill_tween()
	if not managed_by_hand and not is_dragging:
		_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_tween.tween_property(self, "position:y", 0.0, HOVER_DURATION)

func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
