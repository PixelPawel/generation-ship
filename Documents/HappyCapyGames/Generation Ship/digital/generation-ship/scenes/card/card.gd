extends Node3D

signal hovered(card: Node3D)
signal unhovered(card: Node3D)
signal drag_started(card: Node3D)
signal clicked(card: Node3D)
signal right_clicked(card: Node3D)

const HOVER_HEIGHT := 0.15
const HOVER_DURATION := 0.15
const PLACED_LIFT_HEIGHT: float = 0.85
const PLACED_LIFT_SCALE: float = 3.0
const PLACED_LIFT_DURATION: float = 0.35
const PLACED_LIFT_CENTER_PULL: float = 0.9
const DRAG_THRESHOLD_PX: float = 8.0
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
var _pending_url: String = ""
var _drag_armed: bool = false
var _drag_arm_pos: Vector2 = Vector2.ZERO
var _card_glb: Node3D = null
var _face_surface: MeshInstance3D = null

@onready var card_mesh: MeshInstance3D = $CardMesh
@onready var collider: Area3D = $Collider

func _ready() -> void:
	var mat := card_mesh.get_surface_override_material(0) as ShaderMaterial
	if mat:
		card_mesh.set_surface_override_material(0, mat.duplicate())
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
	var url := data.adv_image_url if is_advanced else data.image_url
	if url.is_empty():
		return
	var cached := ImageCache.get_texture(url)
	if cached:
		_apply_texture(cached)
		return
	_pending_url = url
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_texture_loaded.bind(url, http))
	http.request(url)

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

func _on_texture_loaded(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, url: String, http: HTTPRequest) -> void:
	http.queue_free()
	if code != 200 or url != _pending_url:
		return
	var img := Image.new()
	if img.load_png_from_buffer(body) != OK:
		return
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_apply_texture(tex)

func _apply_texture(tex: ImageTexture) -> void:
	var mat := card_mesh.get_surface_override_material(0) as ShaderMaterial
	if mat:
		mat.set_shader_parameter("card_texture", tex)
	if _face_surface:
		var face_mat := StandardMaterial3D.new()
		face_mat.albedo_texture = tex
		face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_face_surface.set_surface_override_material(0, face_mat)

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
				var g: Vector3 = global_position
				var elev_global := Vector3(
					lerpf(g.x, 0.0, PLACED_LIFT_CENTER_PULL),
					PLACED_LIFT_HEIGHT,
					lerpf(g.z, 0.0, PLACED_LIFT_CENTER_PULL)
				)
				var local_target: Vector3 = (get_parent() as Node3D).to_local(elev_global)
				toggle_elevation(local_target, Vector3.ONE * PLACED_LIFT_SCALE, 0.0)
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
	if is_placed and _card_glb:
		_card_glb.visible = false
		card_mesh.visible = true
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
	if is_placed and _card_glb:
		_tween.tween_callback(func() -> void:
			if is_instance_valid(self) and not _placed_elevated:
				_card_glb.visible = true
				card_mesh.visible = false
		)

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

func set_face_down(back_url: String) -> void:
	can_drag = false
	collider.input_ray_pickable = false
	if back_url.is_empty():
		return
	var cached: ImageTexture = ImageCache.get_texture(back_url)
	if cached:
		_apply_texture(cached)
		return
	_pending_url = back_url
	ImageCache.all_loaded.connect(func() -> void:
		var tex: ImageTexture = ImageCache.get_texture(back_url)
		if tex and is_instance_valid(self):
			_apply_texture(tex)
	, CONNECT_ONE_SHOT)

func place() -> void:
	is_dragging = false
	_any_dragging = false
	is_placed = true
	visible = true
	if _card_glb:
		_card_glb.visible = true
		card_mesh.visible = false
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector3(1.12, 1.12, 1.12), 0.08).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector3.ONE, 0.14).set_ease(Tween.EASE_IN)
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
	if is_placed:
		return
	hovered.emit(self)
	if not managed_by_hand and not is_dragging:
		_kill_tween()
		_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		_tween.tween_property(self, "position:y", HOVER_HEIGHT, HOVER_DURATION)

func _on_hover_exit() -> void:
	CursorManager.set_default()
	if is_placed:
		return
	if not is_dragging:
		unhovered.emit(self)
	_kill_tween()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if not managed_by_hand and not is_dragging:
		_tween.tween_property(self, "position:y", 0.0, HOVER_DURATION)

func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
