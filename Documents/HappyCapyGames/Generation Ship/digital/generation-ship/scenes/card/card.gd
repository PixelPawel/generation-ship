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

const HOVER_HEIGHT := 0.15
const HOVER_DURATION := 0.15
const PLACED_LIFT_HEIGHT: float = 0.85
const PLACED_LIFT_SCALE: float = 3.0
const PLACED_LIFT_DURATION: float = 0.35
const PLACED_LIFT_CENTER_PULL: float = 0.9
const DRAG_THRESHOLD_PX: float = 8.0
# Jolt rejects an exactly-zero scale on a node with an Area3D collider (a
# singular transform basis) — used instead of Vector3.ZERO wherever a
# market-inspect clone needs to read as "vanished".
const _NEGLIGIBLE_SCALE: float = 0.001
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
var _placed_elevated: bool = false
var _destroy_on_collapse: bool = false
var _drag_armed: bool = false
var _drag_arm_pos: Vector2 = Vector2.ZERO
var _card_glb: Node3D = null
var _face_surface: MeshInstance3D = null

@onready var card_mesh: MeshInstance3D = $CardMesh
@onready var collider: Area3D = $Collider

func _ready() -> void:
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
	var url: String = data.adv_image_url if is_advanced else data.image_url
	if url.is_empty():
		return
	var tex: Texture2D = ImageCache.get_texture(url)
	if tex:
		_apply_texture(tex)

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

func _apply_local_art_to_glb() -> void:
	if not _face_surface or not card_data:
		return
	var art_path: String = card_data.adv_local_art_path if is_advanced else card_data.local_art_path
	if art_path.is_empty():
		return
	var tex: Texture2D = load(art_path) as Texture2D
	if not tex:
		return
	var face_mat := StandardMaterial3D.new()
	face_mat.albedo_texture = tex
	face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face_mat.no_depth_test = true
	face_mat.render_priority = 1
	_face_surface.set_surface_override_material(0, face_mat)

func _apply_texture(tex: Texture2D) -> void:
	var mat: ShaderMaterial = card_mesh.get_surface_override_material(0) as ShaderMaterial
	if mat:
		mat.set_shader_parameter("card_texture", tex)

func _on_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int) -> void:
	if not (event is InputEventMouseButton):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not is_placed and can_drag and not is_dragging:
				if drag_needs_movement:
					_drag_armed = true
					_drag_arm_pos = get_viewport().get_mouse_position()
				else:
					is_dragging = true
					_any_dragging = true
					drag_started.emit(self)
		else:
			_drag_armed = false
			if is_placed:
				return
			if (not can_drag or not is_dragging) and not _any_dragging:
				clicked.emit(self)
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if is_placed:
			if can_elevate and not _any_dragging:
				toggle_elevation(_elevate_target_local(global_position), Vector3.ONE * PLACED_LIFT_SCALE, 0.0)
		elif _placed_elevated:
			toggle_elevation(Vector3.ZERO, Vector3.ONE, 0.0)
		else:
			right_clicked.emit(self)

func _input(event: InputEvent) -> void:
	if not _drag_armed:
		return
	if event is InputEventMouseMotion:
		if (event.position - _drag_arm_pos).length() >= DRAG_THRESHOLD_PX:
			_drag_armed = false
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
	scale = Vector3.ONE * _NEGLIGIBLE_SCALE
	_elev_rest_pos = parent.to_local(vanish_target_world) if parent else vanish_target_world
	_elev_rest_scale = Vector3.ONE * _NEGLIGIBLE_SCALE
	var target_local: Vector3 = parent.to_local(elev_target_world) if parent else elev_target_world
	toggle_elevation(target_local, elev_scale, 0.0)

func toggle_elevation(elev_pos: Vector3, elev_scale: Vector3, grace_sec: float) -> void:
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

func set_discount_glow(active: bool) -> void:
	var mat: ShaderMaterial = card_mesh.get_surface_override_material(0) as ShaderMaterial
	if mat:
		mat.set_shader_parameter("discount_glow_color",
			Vector3(1.0, 0.82, 0.15) if active else Vector3.ZERO)

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
	_spawn_sparkle()
	_shake_camera()

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
