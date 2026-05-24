class_name SectorSlot
extends Node3D

const TechSlotScript := preload("res://scenes/board/tech_slot.gd")
const TECH_BACK_URL := "https://generationship.s3.eu-central-1.amazonaws.com/TTS/Tech/GS+Techs+44x67mm138.png"

# Supply icon paths, indexed by SupplyColor enum (DUST=0 .. THRUST=5)
const SUPPLY_ICON_PATHS := [
	"res://assets/ui/supply/Dust.png",
	"res://assets/ui/supply/Metals.png",
	"res://assets/ui/supply/Liquids.png",
	"res://assets/ui/supply/Organix.png",
	"res://assets/ui/supply/Electrix.png",
	"res://assets/ui/supply/Thrust.png",
]

# Each offset: (0, Y, Z) relative to this slot — Z steps of 0.44 toward camera
static var TECH_OFFSETS: Array[Vector3] = [
	Vector3(0, 0.07, -0.44),
	Vector3(0, 0.08, -0.64),
	Vector3(0, 0.09, -0.84),
	Vector3(0, 0.10, -1.04),
	Vector3(0, 0.11, -1.24),
]


signal slot_clicked(slot: SectorSlot)

var occupied := false
var is_available: bool = true
var placed_card: Node3D = null
var is_optimized: bool = false
var optimize_count: int = 0
var max_optimizations: int = 1
var triggered_levels: Array[bool] = []
var last_placed_tech_cost: int = 0
var tucked_cards: Array = []   # Array of {data: CardData, face_up: bool}
var stored_supply: Dictionary = {}  # SupplyColor (int) -> int count
var _tech_slots: Array = []
const FLOAT_AMP: float = 0.012
const FLOAT_SPEED: float = 0.07
const CARD_REST_Y: float = 0.06

var _float_phase: float = 0.0
var _highlighted: bool = false
var _highlight_value: float = 0.0
var _highlight_tween: Tween = null
var _scale_tween: Tween = null
var _slot_mat: ShaderMaterial = null
var _supply_sprites: Array[Sprite3D] = []
var _supply_labels: Array[Label3D] = []
var _tuck_nodes: Array[Node3D] = []
var _faceup_vp_label: Label3D = null
var _facedown_vp_label: Label3D = null
var _faceup_count_icon: MeshInstance3D = null
var _facedown_count_icon: MeshInstance3D = null
var _faceup_count_label: Label3D = null
var _facedown_count_label: Label3D = null

@onready var _mesh: MeshInstance3D = $SlotMesh

func _ready() -> void:
	var mat: ShaderMaterial = _mesh.get_surface_override_material(0) as ShaderMaterial
	if mat:
		_slot_mat = mat.duplicate() as ShaderMaterial
		_mesh.set_surface_override_material(0, _slot_mat)
	for i in TECH_OFFSETS.size():
		var slot := Node3D.new()
		slot.set_script(TechSlotScript)
		slot.position = TECH_OFFSETS[i]
		slot.set("slot_index", i)
		add_child(slot)
		_tech_slots.append(slot)
	_float_phase = randf() * TAU
	_setup_display()
	set_process(false)

func _setup_display() -> void:
	const DISC_Z: float = 0.28
	const DISC_Y: float = 0.12
	const X_START: float = -0.37
	const X_STEP: float = 0.148

	for i: int in 6:
		var spr := Sprite3D.new()
		spr.texture = load(SUPPLY_ICON_PATHS[i])
		spr.pixel_size = 0.00004
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.no_depth_test = true
		spr.position = Vector3(X_START + i * X_STEP, DISC_Y, DISC_Z)
		spr.visible = false
		add_child(spr)
		_supply_sprites.append(spr)

		var lbl := _make_supply_badge(
			Vector3(X_START + i * X_STEP, DISC_Y + 0.01, DISC_Z))
		_supply_labels.append(lbl)

	_faceup_vp_label   = _make_tuck_badge(Vector3(-0.23, 0.14, 0.52), Color(1.0, 0.95, 0.3))
	_facedown_vp_label = _make_tuck_badge(Vector3( 0.23, 0.14, 0.52), Color(1.0, 0.95, 0.3))
	_faceup_count_icon   = _make_card_count_icon(Vector3(-0.29, 0.03, 0.67))
	_faceup_count_label  = _make_tuck_badge(Vector3(-0.17, 0.14, 0.67), Color(0.85, 0.9, 1.0))
	_facedown_count_icon  = _make_card_count_icon(Vector3( 0.17, 0.03, 0.67))
	_facedown_count_label = _make_tuck_badge(Vector3( 0.29, 0.14, 0.67), Color(0.85, 0.9, 1.0))

func _make_tuck_badge(pos: Vector3, color: Color) -> Label3D:
	var lbl := Label3D.new()
	lbl.font_size = 28
	lbl.pixel_size = 0.005
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.modulate = color
	lbl.position = pos
	lbl.visible = false
	add_child(lbl)
	return lbl

func _make_supply_badge(pos: Vector3) -> Label3D:
	var lbl := Label3D.new()
	lbl.font_size = 28
	lbl.pixel_size = 0.005
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.modulate = Color.WHITE
	lbl.outline_size = 30
	lbl.outline_modulate = Color.BLACK
	lbl.position = pos
	lbl.visible = false
	add_child(lbl)
	return lbl

func _make_card_count_icon(pos: Vector3) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.07, 0.10)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.12, 0.18, 0.32)
	mi.material_override = mat
	mi.visible = false
	add_child(mi)
	return mi

func refresh_display() -> void:
	if _supply_sprites.is_empty():
		return
	for i: int in 6:
		var count: int = stored_supply.get(i, 0)
		_supply_sprites[i].visible = count > 0
		_supply_labels[i].visible = count > 0
		if count > 0:
			_supply_labels[i].text = str(count)
	_refresh_tuck_display()

func _refresh_tuck_display() -> void:
	for n: Node3D in _tuck_nodes:
		n.queue_free()
	_tuck_nodes.clear()

	const TUCK_Z_START: float = 0.38
	const TUCK_Z_STEP: float = 0.07
	const TUCK_Y: float = 0.03
	const CARD_W: float = 0.38
	const CARD_H: float = 0.54
	const COL_X_FACEUP: float = -0.23
	const COL_X_FACEDOWN: float = 0.23

	var faceup_idx: int = 0
	var facedown_idx: int = 0

	for entry: Dictionary in tucked_cards:
		var face_up: bool = entry.get("face_up", false)
		var data: CardData = entry.get("data") as CardData

		var url: String = (data.image_url if data else "") if face_up else TECH_BACK_URL
		var tex: Texture2D = ImageCache.get_texture(url) if not url.is_empty() else null

		var plane := PlaneMesh.new()
		plane.size = Vector2(CARD_W, CARD_H)

		var mi := MeshInstance3D.new()
		mi.mesh = plane
		if face_up:
			mi.position = Vector3(COL_X_FACEUP, TUCK_Y, TUCK_Z_START + faceup_idx * TUCK_Z_STEP)
			faceup_idx += 1
		else:
			mi.position = Vector3(COL_X_FACEDOWN, TUCK_Y, TUCK_Z_START + facedown_idx * TUCK_Z_STEP)
			facedown_idx += 1

		var mat := StandardMaterial3D.new()
		if tex:
			mat.albedo_texture = tex
		else:
			mat.albedo_color = Color(0.92, 0.87, 0.76) if face_up else Color(0.12, 0.18, 0.32)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat

		add_child(mi)
		_tuck_nodes.append(mi)

	# Update VP and count badges
	var faceup_vp: int = 0
	var facedown_count: int = 0
	for entry: Dictionary in tucked_cards:
		var cd: CardData = entry.get("data") as CardData
		if entry.get("face_up", false):
			if cd:
				faceup_vp += cd.stars
		else:
			facedown_count += 1
	if _faceup_vp_label:
		_faceup_vp_label.text = "⭐ %d" % faceup_vp
		_faceup_vp_label.visible = faceup_vp > 0
	if _facedown_vp_label:
		_facedown_vp_label.text = "⭐ %d" % facedown_count
		_facedown_vp_label.visible = facedown_count > 0
	var back_tex: Texture2D = ImageCache.get_texture(TECH_BACK_URL)
	_update_count_badge(_faceup_count_icon, _faceup_count_label, faceup_idx, back_tex)
	_update_count_badge(_facedown_count_icon, _facedown_count_label, facedown_idx, back_tex)

func _update_count_badge(icon: MeshInstance3D, lbl: Label3D, count: int, tex: Texture2D) -> void:
	if icon:
		var mat := icon.material_override as StandardMaterial3D
		if mat:
			if tex:
				mat.albedo_texture = tex
				mat.albedo_color = Color.WHITE
			else:
				mat.albedo_color = Color(0.12, 0.18, 0.32)
		icon.visible = count > 0
	if lbl:
		lbl.text = "x%d" % count
		lbl.visible = count > 0

func has_tech_space() -> bool:
	if not occupied:
		return false
	for slot in _tech_slots:
		if not slot.occupied:
			return true
	return false

func get_next_tech_slot() -> Node3D:
	for slot in _tech_slots:
		if not slot.occupied:
			return slot
	return null

func accept_tech_card(card: Node3D) -> void:
	var ts := get_next_tech_slot()
	if ts:
		ts.accept_card(card)
		if card.card_data:
			last_placed_tech_cost = card.card_data.cost

func can_optimize() -> bool:
	return occupied and optimize_count < max_optimizations

func do_optimize() -> void:
	for i: int in triggered_levels.size():
		if not triggered_levels[i]:
			triggered_levels[i] = true
			optimize_count += 1
			break
	if optimize_count >= max_optimizations:
		is_optimized = true

func reset_optimize() -> void:
	optimize_count = 0
	is_optimized = false
	triggered_levels.fill(false)

func _process(_delta: float) -> void:
	if _slot_mat:
		_slot_mat.set_shader_parameter("highlight_t", _highlight_value)
	if placed_card:
		var card_tween: Tween = placed_card.get("_tween") as Tween
		if card_tween and card_tween.is_valid():
			return
		var t: float = Time.get_ticks_msec() / 1000.0
		placed_card.position.y = CARD_REST_Y + sin(t * FLOAT_SPEED * TAU + _float_phase) * FLOAT_AMP

func highlight(on: bool) -> void:
	if _highlighted == on:
		return
	_highlighted = on
	if not _slot_mat:
		return
	if _highlight_tween:
		_highlight_tween.kill()
		_highlight_tween = null
	if _scale_tween:
		_scale_tween.kill()
		_scale_tween = null
	if on:
		set_process(true)
		_highlight_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_highlight_tween.tween_property(self, "_highlight_value", 1.0, 0.15)
		_scale_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		_scale_tween.tween_property(_mesh, "scale", Vector3(1.06, 1.0, 1.06), 0.18)
	else:
		_highlight_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_highlight_tween.tween_property(self, "_highlight_value", 0.0, 0.2)
		_highlight_tween.tween_callback(func() -> void:
			if not placed_card:
				set_process(false))
		_scale_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_scale_tween.tween_property(_mesh, "scale", Vector3.ONE, 0.2)

func set_available(available: bool) -> void:
	is_available = available
	if not occupied:
		_mesh.visible = true

func get_all_placed_cards() -> Array[Node3D]:
	var result: Array[Node3D] = []
	if placed_card:
		result.append(placed_card)
	for ts: Node3D in _tech_slots:
		if ts.occupied and ts.placed_card:
			result.append(ts.placed_card)
	return result

func get_tech_count() -> int:
	var count: int = 0
	for slot: Node3D in _tech_slots:
		if slot.occupied:
			count += 1
	return count

func is_complete() -> bool:
	return occupied and not has_tech_space()

func add_tucked_card(data: CardData, face_up: bool) -> void:
	tucked_cards.append({"data": data, "face_up": face_up})
	refresh_display()

func add_stored_supply(color: CardData.SupplyColor, amount: int) -> void:
	stored_supply[color] = stored_supply.get(color, 0) + amount
	refresh_display()

func get_stored_supply(color: CardData.SupplyColor) -> int:
	return stored_supply.get(color, 0)

func get_total_stored_supply() -> int:
	var total: int = 0
	for count: int in stored_supply.values():
		total += count
	return total

func _setup_max_optimizations(card: Node3D) -> void:
	if not card.card_data:
		return
	var cd: CardData = card.card_data
	var is_adv: bool = bool(card.get("is_advanced"))
	if is_adv:
		max_optimizations = 0
		if not cd.adv_opt1_req.is_empty():
			max_optimizations = 1
		if not cd.adv_opt2_req.is_empty():
			max_optimizations = 2
		if not cd.adv_opt3_req.is_empty():
			max_optimizations = 3
	else:
		max_optimizations = 1 if not cd.opt1_req.is_empty() else 0
	triggered_levels.resize(max_optimizations)
	triggered_levels.fill(false)

func _on_placed_card_clicked(_card: Node3D) -> void:
	slot_clicked.emit(self)

func get_placed_tech_colors() -> Array[int]:
	var result: Array[int] = []
	for ts: Node3D in _tech_slots:
		if ts.occupied and ts.placed_card and ts.placed_card.card_data:
			result.append(int(ts.placed_card.card_data.color))
	return result

func remove_tech_card(card: Node3D) -> void:
	for ts: Node3D in _tech_slots:
		if ts.placed_card == card:
			ts.occupied = false
			ts.placed_card = null
			break

func compact_tech_cards() -> void:
	var remaining: Array[Node3D] = []
	for ts: Node3D in _tech_slots:
		if ts.occupied and ts.placed_card:
			remaining.append(ts.placed_card)
		ts.occupied = false
		ts.placed_card = null
	for i: int in remaining.size():
		var ts: Node3D = _tech_slots[i]
		var card: Node3D = remaining[i]
		ts.occupied = true
		ts.placed_card = card
		if card.get_parent() != ts:
			card.reparent(ts, true)
		card.call("set_sort_order", i * 0.5)
		var tween := card.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(card, "position", Vector3.ZERO, 0.25)

func accept_card(card: Node3D) -> void:
	occupied = true
	placed_card = card
	_mesh.visible = false
	_setup_max_optimizations(card)
	if card.has_signal("clicked") and not card.clicked.is_connected(_on_placed_card_clicked):
		card.clicked.connect(_on_placed_card_clicked)
	card.reparent(self, true)
	card.managed_by_hand = false
	card.set("_elev_rest_pos", Vector3(0, CARD_REST_Y, 0))
	# Negative offset pushes sector card behind all tech slots in transparent sort.
	card.call("set_sort_order", -(TECH_OFFSETS.size() * 0.5))
	var tween := card.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(card, "position", Vector3(0, CARD_REST_Y, 0), 0.3)
	tween.parallel().tween_property(card, "rotation", Vector3(-PI / 2.0, PI / 2.0, 0.0), 0.3)
	tween.parallel().tween_property(card, "scale", Vector3.ONE, 0.2)
	tween.tween_callback(func() -> void: set_process(true))
