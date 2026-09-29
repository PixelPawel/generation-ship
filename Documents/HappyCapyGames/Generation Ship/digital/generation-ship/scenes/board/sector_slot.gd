class_name SectorSlot
extends Node3D

const TechSlotScript := preload("res://scenes/board/tech_slot.gd")

# Supply icon paths, indexed by SupplyColor enum (DUST=0 .. THRUST=5)
const SUPPLY_ICON_PATHS := [
	"res://assets/ui/supply/Dust.png",
	"res://assets/ui/supply/Metals.png",
	"res://assets/ui/supply/Liquids.png",
	"res://assets/ui/supply/Organix.png",
	"res://assets/ui/supply/Electrix.png",
	"res://assets/ui/supply/Thrust.png",
]

# Card icon paths, indexed by SupplyColor enum — used for the floating
# optimize-requirement display (which colors trigger each Optimize level).
const CARD_ICON_PATHS := [
	"res://assets/ui/cards/Dust_Card.png",
	"res://assets/ui/cards/Metals_Card.png",
	"res://assets/ui/cards/Liquids_Card.png",
	"res://assets/ui/cards/Organix_Card.png",
	"res://assets/ui/cards/Electrix_Card.png",
	"res://assets/ui/cards/Thrust_Card.png",
]
const ANY_CARD_ICON_PATH := "res://assets/ui/cards/Any_Card.png"

static var TECH_OFFSETS_COMPACT: Array[Vector3] = [
	Vector3(0, 0.070, -0.32),
	Vector3(0, 0.060, -0.76),
	Vector3(0, 0.050, -1.20),
	Vector3(0, 0.040, -1.64),
	Vector3(0, 0.030, -2.08),
]

static var TECH_OFFSETS_EXPANDED: Array[Vector3] = [
	Vector3(0, 0.070, -0.55),
	Vector3(0, 0.060, -1.1925),
	Vector3(0, 0.050, -1.835),
	Vector3(0, 0.040, -2.4775),
	Vector3(0, 0.030, -3.12),
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
var _stack_expanded: bool = false
var _hover_expand_requested: bool = false
const FLOAT_AMP: float = 0.010
const FLOAT_SPEED: float = 0.07
const CARD_REST_Y: float = 0.085

var _float_phase: float = 0.0
var _highlighted: bool = false
var _highlight_value: float = 0.0
var _highlight_tween: Tween = null
var _scale_tween: Tween = null
var _slot_mat: ShaderMaterial = null
var _supply_sprites: Array[MeshInstance3D] = []
var _supply_labels: Array[Label3D] = []
var _tuck_nodes: Array[Node3D] = []
var _faceup_vp_label: Label3D = null
var _facedown_vp_label: Label3D = null
var _faceup_count_icon: MeshInstance3D = null
var _facedown_count_icon: MeshInstance3D = null
var _faceup_count_label: Label3D = null
var _facedown_count_label: Label3D = null
var _optimize_icons: Array = []  # index = level (0..2), value = Array[MeshInstance3D] for that level's icons
var _optimize_level_reqs: Array = []  # index = level (0..2), value = Array[int] (that level's required colors, same order as _optimize_icons)
var _optimize_nodes: Array[Node3D] = []  # every icon node, tracked for cleanup
var _stage_badge: Label3D = null            # "NEW" / "COMPLETES NEXT" / "COMPLETE"
var _optimize_state_badge: Label3D = null   # "OPTIMIZES NEXT" / "OPTIMIZED"
# Set by Board via _set_tech_drag_active while a tech/expedition card is
# being dragged — the two badges above only ever show during that window
# (see _refresh_state_badges), not as a permanent always-on overlay.
var _drag_helper_active: bool = false
# Color of the card currently being dragged (only meaningful while
# _drag_helper_active) — Optimizes Next only fires for the color that
# would actually complete the sector, not merely "one card away" in
# the abstract.
var _dragged_card_color: CardData.SupplyColor = CardData.SupplyColor.DUST

@onready var _mesh: MeshInstance3D = $SlotMesh

func _ready() -> void:
	var mat: ShaderMaterial = _mesh.get_surface_override_material(0) as ShaderMaterial
	if mat:
		_slot_mat = mat.duplicate() as ShaderMaterial
		_mesh.set_surface_override_material(0, _slot_mat)
		_slot_mat.set_shader_parameter("slot_power", 0.0)
	for i in TECH_OFFSETS_COMPACT.size():
		var slot := Node3D.new()
		slot.set_script(TechSlotScript)
		slot.position = TECH_OFFSETS_COMPACT[i]
		slot.set("slot_index", i)
		add_child(slot)
		_tech_slots.append(slot)
	_float_phase = randf() * TAU
	_setup_display()
	set_process(false)

# Shared local Y for every overlay element on this slot (stored-supply
# icons/counts, tucked-card count badges, optimize-requirement icons — see
# _make_icon_plane and _make_badge). Labels sit a touch above their paired
# icon so the two opaque/transparent planes don't coincide exactly.
const ELEMENT_ICON_Y: float = 0.15
const ELEMENT_LABEL_Y: float = 0.17
# Cancels this SectorSlot's own baked-in ~12.6 degree local X tilt (see the
# SectorSlot transforms in main.tscn) so a flat textured plane lies parallel
# to the camera instead of following the slot's own tilted surface.
const ICON_TILT_COMPENSATION_DEG: float = -12.6
const SUPPLY_ICON_PIXEL_SIZE: float = 0.00004  # matches the old Sprite3D pixel_size, keeps supply icons' on-screen size unchanged

# Comparing local Y against placed_card (or projecting toward the camera —
# also tried, also wrong) never reliably cleared these elements, because
# neither actually matches what the depth test does here. Confirmed by
# instrumenting the real game (placing an actual card, adding real stored
# supply/tucked cards, then rendering the live scene to an image and
# inspecting it directly): placed_card sits at local Z=0, and pushing an
# element further forward in local Z — away from the card, not "up" in Y —
# is what actually clears it. Local Y barely matters for depth here at all.
# Clamping every element's Z up to this shared floor (rather than adding
# a flat amount to all of them) only moves the ones that actually need
# it, and only by as much as they need — supply icons (base Z=0.28) barely
# move, while still landing just past the card's own Z extent. Kept low
# enough to stay clear of the tuck badges' own Z range (0.52-0.67, already
# past the card on their own) so the two groups don't crowd each other.
const MIN_FRONT_Z: float = 0.4

func _add_z_clearance(base_local: Vector3) -> Vector3:
	return Vector3(base_local.x, base_local.y, max(base_local.z, MIN_FRONT_Z))

func _setup_display() -> void:
	const DISC_Z: float = 0.28
	const X_START: float = -0.37
	const X_STEP: float = 0.148

	for i: int in 6:
		var tex: Texture2D = load(SUPPLY_ICON_PATHS[i])
		var spr := _make_icon_plane(
			_add_z_clearance(Vector3(X_START + i * X_STEP, ELEMENT_ICON_Y, DISC_Z)),
			tex.get_size() * SUPPLY_ICON_PIXEL_SIZE, tex, false)
		_supply_sprites.append(spr)

		var lbl := _make_badge(
			_add_z_clearance(Vector3(X_START + i * X_STEP, ELEMENT_LABEL_Y, DISC_Z)), Color.WHITE, true)
		_supply_labels.append(lbl)

	_faceup_vp_label   = _make_badge(_add_z_clearance(Vector3(-0.23, ELEMENT_LABEL_Y, 0.52)), Color(1.0, 0.95, 0.3))
	_facedown_vp_label = _make_badge(_add_z_clearance(Vector3( 0.23, ELEMENT_LABEL_Y, 0.52)), Color(1.0, 0.95, 0.3))
	_faceup_count_icon    = _make_icon_plane(_add_z_clearance(Vector3(-0.29, ELEMENT_ICON_Y, 0.67)), Vector2(0.07, 0.10), null, false)
	_faceup_count_label   = _make_badge(_add_z_clearance(Vector3(-0.17, ELEMENT_LABEL_Y, 0.67)), Color(0.85, 0.9, 1.0))
	_facedown_count_icon  = _make_icon_plane(_add_z_clearance(Vector3( 0.17, ELEMENT_ICON_Y, 0.67)), Vector2(0.07, 0.10), null, false)
	_facedown_count_label = _make_badge(_add_z_clearance(Vector3( 0.29, ELEMENT_LABEL_Y, 0.67)), Color(0.85, 0.9, 1.0))

	# State-helper badges — centered on the sector (X=0) rather than off to
	# the side like the Optimize-requirement column, since these read as a
	# headline for the whole sector, not a per-color icon list. Sits dead
	# center over the card itself (unlike every other badge here, which
	# sits to the side or past the card's own footprint), so depth-testing
	# it the normal way left it flickering in and out behind the card as it
	# floats (see _process's FLOAT_AMP bob) — no_depth_test below fixes
	# that outright rather than chasing a Z offset that clears a card
	# that's itself moving through a Z range. Kept at the same near-zero Z
	# the rest of this slot's centered content uses (NOT pushed forward the
	# way _add_z_clearance does for depth-tested elements) since pushing it
	# further from the card also pushes it further from the camera, making
	# the same font size read noticeably smaller — confirmed by it nearly
	# vanishing at Z=0.44 even at 3x the font size that reads clearly here.
	# Separated from each other in Y (not Z) since both can be visible at
	# once and a Y gap reads as two stacked lines regardless of camera
	# angle — needs MORE gap than it looks like it should, since a line's
	# own rendered height (~font_size * pixel_size, here ~0.11) is on the
	# same order as any gap that looks reasonable at a glance; too small a
	# gap let the two opaque billboards paint over each other's middle,
	# leaving only each line's outermost letters visible.
	_stage_badge = _make_badge(Vector3(0, ELEMENT_LABEL_Y + 0.14, 0.08), STAGE_COLOR_READY, true, 22, 11)
	_optimize_state_badge = _make_badge(Vector3(0, ELEMENT_LABEL_Y - 0.14, -0.08), OPTIMIZE_COLOR_DONE, true, 22, 11)
	# no_depth_test alone wasn't enough to stay clear of the tech-card stack
	# (a tall stack still painted over the middle of the text — depth test
	# or not, later-drawn opaque geometry still wins the color buffer). A
	# high render_priority forces these to draw dead last among
	# transparent-sorted objects regardless, guaranteeing nothing else can
	# paint over them.
	_stage_badge.no_depth_test = true
	_stage_badge.render_priority = 100
	_optimize_state_badge.no_depth_test = true
	_optimize_state_badge.render_priority = 100

# Shared text badge used for every label on this slot (stored-supply counts,
# tucked-card VP/count labels). Real depth-tested (Label3D's own default —
# no no_depth_test bypass) so it's occluded by placed_card exactly like
# every other element, matching _make_icon_plane below.
func _make_badge(pos: Vector3, color: Color, outlined: bool = false, font_size: int = 28, outline_size: int = 15) -> Label3D:
	var lbl := Label3D.new()
	lbl.font_size = font_size
	lbl.pixel_size = 0.005
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.modulate = color
	if outlined:
		lbl.outline_size = outline_size
		lbl.outline_modulate = Color.BLACK
	lbl.position = pos
	lbl.visible = false
	add_child(lbl)
	return lbl

# Shared textured plane used for every icon-type element on this slot
# (stored-supply icons, tucked-card count icons, optimize-requirement
# icons — see _make_optimize_icon). Real depth-tested — no no_depth_test/
# billboard bypass — so it properly occludes and is occluded by
# placed_card like everything else in the scene, with a fixed rotation
# canceling this slot's own tilt (see ICON_TILT_COMPENSATION_DEG) so it
# still lies flat facing the camera.
func _make_icon_plane(pos: Vector3, size: Vector2, tex: Texture2D = null, start_visible: bool = true) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = size
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if tex:
		mat.albedo_texture = tex
		# Icon PNGs with transparent backgrounds (e.g. supply icons) need this
		# — without it, StandardMaterial3D ignores the texture's alpha channel
		# and renders it fully opaque, showing a solid box with a white fringe
		# right at the icon's edge (anti-aliased semi-transparent pixels drawn
		# at full opacity instead of blending out). Scissor, not alpha-blend,
		# so it still writes depth normally and stays real depth-tested like
		# everything else here.
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	else:
		mat.albedo_color = Color(0.12, 0.18, 0.32)
	mesh_inst.material_override = mat
	mesh_inst.position = pos
	mesh_inst.rotation_degrees.x = ICON_TILT_COMPENSATION_DEG
	mesh_inst.visible = start_visible
	add_child(mesh_inst)
	return mesh_inst

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
	const TUCK_Y: float = 0.002   # opaque, renders before all transparent cards
	const CARD_W: float = 0.38
	const CARD_H: float = 0.54
	const COL_X_FACEUP: float = -0.23
	const COL_X_FACEDOWN: float = 0.23

	var faceup_idx: int = 0
	var facedown_idx: int = 0

	for entry: Dictionary in tucked_cards:
		var face_up: bool = entry.get("face_up", false)
		var data: CardData = entry.get("data") as CardData

		var url: String = (data.image_url if data else "") if face_up else CardDatabase.tech_back_path()
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
	var back_tex: Texture2D = ImageCache.get_texture(CardDatabase.tech_back_path())
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

func reset_optimize() -> void:
	optimize_count = 0
	is_optimized = false
	triggered_levels.fill(false)
	refresh_optimize_display()

func _process(_delta: float) -> void:
	if _slot_mat:
		_slot_mat.set_shader_parameter("highlight_t", _highlight_value)
	if placed_card:
		if placed_card.get("_placed_elevated"):
			return
		var card_tween: Tween = placed_card.get("_tween") as Tween
		if card_tween and card_tween.is_valid():
			return
		var t: float = Time.get_ticks_msec() / 1000.0
		placed_card.position.y = CARD_REST_Y + sin(t * FLOAT_SPEED * TAU + _float_phase) * FLOAT_AMP
		_check_stack_hover()

# Called from main.gd whenever the mouse enters/exits any card belonging to
# this sector (the main placed card or one of its tech cards) — lets a player
# see every stacked card's color just by hovering, without needing to
# right-click one to elevate it.
func set_hover_expand(on: bool) -> void:
	_hover_expand_requested = on

func _check_stack_hover() -> void:
	var want_expanded: bool = _any_tech_elevated() or _hover_expand_requested
	if want_expanded != _stack_expanded:
		_fan_tech_slots(want_expanded)

func _any_tech_elevated() -> bool:
	for ts: Node3D in _tech_slots:
		if ts.occupied and ts.placed_card and bool(ts.placed_card.get("_placed_elevated")):
			return true
	return false

func _fan_tech_slots(expanded: bool) -> void:
	_stack_expanded = expanded
	var offsets: Array[Vector3] = TECH_OFFSETS_EXPANDED if expanded else TECH_OFFSETS_COMPACT
	for i: int in _tech_slots.size():
		var ts: Node3D = _tech_slots[i]
		var tw: Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(ts, "position", offsets[i], 0.20)

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

func set_slot_brightness(v: float) -> void:
	if _slot_mat:
		_slot_mat.set_shader_parameter("slot_power", v)

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

const OPT_ICON_PIXEL_SIZE: float = 0.0001
# Sector slots are now spaced 0.20 apart in world space (~1.333 in this
# slot's own local frame, given its ~0.15 scale) — with the sector card's
# own left edge at -0.44 and the neighboring slot's card right edge at
# roughly -0.89, there's a real ~0.45-wide gap between the two cards to
# sit in, instead of the near-zero one before the slots were spaced out.
# Sitting mid-gap keeps clear margin from both this card and the next.
const OPT_COLUMN_X: float = -0.62
# Stage track (New / Completes Next / Complete) and Optimize track (Optimizes
# Next / Optimized) get entirely separate color families, not just separate
# text — the two badges can be visible at once (e.g. a sector one tech away
# from Complete that's also one matching card away from Optimize), and a
# shared "done" or "soon" color made the two lines visually blend into an
# unreadable overlap where they'd otherwise sit close together. Color alone
# still tells the two tracks apart even when their text does overlap.
const STAGE_COLOR_READY: Color = Color(0.55, 0.85, 1.0)   # New — empty, ready for its first tech card
const STAGE_COLOR_SOON: Color = Color(1.0, 0.75, 0.3)     # Completes Next
const STAGE_COLOR_DONE: Color = Color(1.0, 0.88, 0.35)    # Complete
const OPTIMIZE_COLOR_SOON: Color = Color(0.78, 0.6, 1.0)  # Optimizes Next
const OPTIMIZE_COLOR_DONE: Color = Color(0.4, 1.0, 0.55)  # Optimized
# Now that the column sits out in X (OPT_COLUMN_X, clear of both this card
# and the neighbor's), it no longer needs to dodge the sector card's own Z
# extent the way it did back when it shared the card's own X range — so it
# sits centered on the card's own Z-center (0) instead of hiding back near
# the tech slots. The actual starting Z is computed per-card in
# _build_optimize_display, not a fixed constant here, since how far that
# needs to be depends on how many icons/levels that specific card has —
# a fixed start would center correctly only for one particular count.
const OPT_ICON_Z_STEP: float = -0.115
const OPT_LEVEL_GAP_Z: float = -0.05
const OPT_PENDING_EMISSION: Color = Color(0.9, 0.15, 0.15)
const OPT_EMISSION_ENERGY: float = 0.8

# Floating "recipe" icons stacked front-to-back on the sector's left side,
# one icon per required color across all Optimize levels (per the Optimize
# 1/2/3 CSV columns) — glowing red while its color is still needed, hidden
# entirely once a placed tech of that color satisfies it (see
# refresh_optimize_display). Built once at placement time since a slot's
# requirement set never changes after accept_card() (dust vs. advanced is
# fixed then).
func _build_optimize_display(card: Node3D) -> void:
	_clear_optimize_display()
	_optimize_icons.resize(3)
	_optimize_level_reqs.resize(3)
	for i: int in 3:
		_optimize_icons[i] = []
		_optimize_level_reqs[i] = []
	if not card.card_data:
		return
	var cd: CardData = card.card_data
	var is_adv: bool = bool(card.get("is_advanced"))
	var level_reqs: Array = (
		[cd.adv_opt1_req, cd.adv_opt2_req, cd.adv_opt3_req] if is_adv
		else [cd.opt1_req, [], []]
	)
	# Dry run first, using the exact same step constants as the real loop
	# below, to collect every icon's Z position in creation order (so the
	# whole span can be centered on 0 regardless of how many icons/levels
	# this specific card needs), then hand them out in REVERSE — the first
	# icon created (e.g. an advanced sector's own Optimize 1, first color)
	# ends up at the position the last one used to get, and vice versa, per
	# feedback that creation order had ended up visually inverted.
	var z_slots: Array[float] = []
	var probe_z: float = 0.0
	for level_idx: int in 3:
		var req: Array = level_reqs[level_idx]
		if req.is_empty():
			continue
		for _i: int in req.size():
			z_slots.append(probe_z)
			probe_z += OPT_ICON_Z_STEP
		probe_z += OPT_LEVEL_GAP_Z
	if not z_slots.is_empty():
		var center: float = (z_slots[0] + z_slots[-1]) * 0.5
		for i: int in z_slots.size():
			z_slots[i] -= center
	z_slots.reverse()

	var slot_idx: int = 0
	for level_idx: int in 3:
		var req: Array = level_reqs[level_idx]
		if req.is_empty():
			continue
		var row: Array = []
		for color_id: int in req:
			var tex_path: String = ANY_CARD_ICON_PATH if color_id == CardData.OPTIMIZE_ANY else CARD_ICON_PATHS[color_id]
			row.append(_make_optimize_icon(Vector3(OPT_COLUMN_X, ELEMENT_ICON_Y, z_slots[slot_idx]), tex_path))
			slot_idx += 1
		_optimize_icons[level_idx] = row
		_optimize_level_reqs[level_idx] = req
	refresh_optimize_display()

# Built on the same shared _make_icon_plane as every other icon on this
# slot, with a fixed "still needed" red glow — refresh_optimize_display()
# only ever toggles these icons' visibility, never their look, since once
# a color's requirement is met the icon simply disappears.
func _make_optimize_icon(pos: Vector3, tex_path: String) -> MeshInstance3D:
	var tex: Texture2D = load(tex_path)
	var mesh_inst := _make_icon_plane(pos, tex.get_size() * OPT_ICON_PIXEL_SIZE, tex)
	var mat: StandardMaterial3D = mesh_inst.material_override
	mat.emission_enabled = true
	mat.emission_energy_multiplier = OPT_EMISSION_ENERGY
	mat.emission = OPT_PENDING_EMISSION
	_optimize_nodes.append(mesh_inst)

	return mesh_inst

func _clear_optimize_display() -> void:
	for n: Node3D in _optimize_nodes:
		n.queue_free()
	_optimize_nodes.clear()
	_optimize_icons.clear()
	_optimize_level_reqs.clear()

# Hides each icon whose specific color has already been satisfied by a
# currently-placed tech, leaving only the colors still needed visible —
# matched the same way OptimizeLogic actually decides a level is
# satisfied (specific colors first, ANY last), consuming the pool level by
# level in order so a single placed tech is never counted toward two
# different levels' displays at once. A level that's already fully
# triggered (a permanent one-way flag, see OptimizeLogic) hides all its
# icons outright and still consumes its share of the pool, regardless of
# whether the exact tech that satisfied it is still in place, since the
# achievement itself doesn't revert.
func refresh_optimize_display() -> void:
	var pool: Array[int] = get_placed_tech_colors()
	for level_idx: int in _optimize_icons.size():
		var req: Array[int] = []
		req.assign(_optimize_level_reqs[level_idx])
		var row: Array = _optimize_icons[level_idx]
		if level_idx < triggered_levels.size() and triggered_levels[level_idx]:
			for mesh_inst: MeshInstance3D in row:
				mesh_inst.visible = false
		else:
			var matched: Array[bool] = OptimizeLogic.matched_indices(pool, req)
			for i: int in row.size():
				row[i].visible = not matched[i]
		OptimizeLogic.consume_from_pool(pool, req)
	_refresh_state_badges()

# True only when exactly one Optimize level is left untriggered (so
# satisfying it alone would flip is_optimized true), that level's
# requirement is missing exactly one color, AND the card currently being
# dragged (_dragged_card_color) is that missing color — an ANY requirement
# slot accepts whatever's being dragged, but a specific-color slot only
# reads as "Optimizes Next" for the one color that actually completes it,
# not for every card that happens to be one-away in the abstract. Mirrors
# OptimizeLogic's own level-by-level pool consumption (see
# refresh_optimize_display above) so a card already counted toward an
# earlier level's requirement is never double-counted here.
func _one_card_from_fully_optimized() -> bool:
	if is_optimized or optimize_count != max_optimizations - 1:
		return false
	var pool: Array[int] = get_placed_tech_colors()
	for level_idx: int in max_optimizations:
		var req: Array[int] = []
		req.assign(_optimize_level_reqs[level_idx])
		if level_idx < triggered_levels.size() and triggered_levels[level_idx]:
			OptimizeLogic.consume_from_pool(pool, req)
			continue
		var matched: Array[bool] = OptimizeLogic.matched_indices(pool, req)
		if matched.count(false) != 1:
			return false
		var missing_color: int = req[matched.find(false)]
		return missing_color == CardData.OPTIMIZE_ANY or missing_color == int(_dragged_card_color)
	return false

# Called by Board (_set_tech_drag_active) while a tech/expedition card is
# being dragged, on every sector slot regardless of whether it's a valid
# target — lets players compare New/Complete/Optimized state across the
# whole board before choosing where to drop, not just the slot they're
# already hovering. dragged_color only matters while active, but is always
# passed together so the two stay in sync.
func set_drag_helper_active(active: bool, dragged_color: CardData.SupplyColor = CardData.SupplyColor.DUST) -> void:
	if _drag_helper_active == active and _dragged_card_color == dragged_color:
		return
	_drag_helper_active = active
	_dragged_card_color = dragged_color
	_refresh_state_badges()

# Refreshes the two state badges (see _setup_display) that help players
# read, at a glance, which of a sector's New/Complete/Optimized conditions
# currently apply — i.e. which "if ___" card-text effects would fire on
# whatever gets placed here next. Only actually shown while
# _drag_helper_active (a tech/expedition drag is in progress) — otherwise
# they'd be a permanent, distracting overlay on every sector at all times.
# Piggybacks on refresh_optimize_display's own call sites (every tech
# placement, sector placement, and Caldera-Colony-style re-validation)
# rather than needing any new call sites of its own.
func _refresh_state_badges() -> void:
	if not occupied or not _drag_helper_active:
		_stage_badge.visible = false
		_optimize_state_badge.visible = false
		return
	var tech_count: int = get_tech_count()
	var total_slots: int = _tech_slots.size()
	if tech_count == 0:
		_stage_badge.text = "NEW"
		_stage_badge.modulate = STAGE_COLOR_READY
		_stage_badge.visible = true
	elif tech_count == total_slots - 1:
		_stage_badge.text = "COMPLETES NEXT"
		_stage_badge.modulate = STAGE_COLOR_SOON
		_stage_badge.visible = true
	elif tech_count == total_slots:
		_stage_badge.text = "COMPLETE"
		_stage_badge.modulate = STAGE_COLOR_DONE
		_stage_badge.visible = true
	else:
		_stage_badge.visible = false

	if is_optimized:
		_optimize_state_badge.text = "OPTIMIZED"
		_optimize_state_badge.modulate = OPTIMIZE_COLOR_DONE
		_optimize_state_badge.visible = true
	elif _one_card_from_fully_optimized():
		_optimize_state_badge.text = "OPTIMIZES NEXT"
		_optimize_state_badge.modulate = OPTIMIZE_COLOR_SOON
		_optimize_state_badge.visible = true
	else:
		_optimize_state_badge.visible = false

func _on_placed_card_clicked(_card: Node3D) -> void:
	slot_clicked.emit(self)

# Set on a just-placed Karma Chameleon until its Place effect picks a color
# (see Board._mark_color_choice_pending / apply_placing_color).
const COLOR_CHOICE_PENDING_META: StringName = &"color_choice_pending"

func get_placed_tech_colors() -> Array[int]:
	var result: Array[int] = []
	for ts: Node3D in _tech_slots:
		if ts.occupied and ts.placed_card and ts.placed_card.card_data:
			if ts.placed_card.has_meta(COLOR_CHOICE_PENDING_META):
				continue
			var cd: CardData = ts.placed_card.card_data
			result.append(cd.placing_color_override if cd.placing_color_override >= 0 else int(cd.color))
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
		card.call("set_sort_order", 0.0)
		var tween := card.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(card, "position", Vector3.ZERO, 0.25)

func accept_card(card: Node3D) -> void:
	occupied = true
	placed_card = card
	_mesh.visible = false
	_setup_max_optimizations(card)
	_build_optimize_display(card)
	if card.has_signal("clicked") and not card.clicked.is_connected(_on_placed_card_clicked):
		card.clicked.connect(_on_placed_card_clicked)
	card.reparent(self, true)
	card.managed_by_hand = false
	card.set("_elev_rest_pos", Vector3(0, CARD_REST_Y, 0))
	card.call("set_sort_order", 0.0)
	# Bought from the market: fly in from the market screen (see Board).
	if card.has_meta(&"place_from"):
		var from: Vector3 = card.get_meta(&"place_from")
		card.remove_meta(&"place_from")
		card.call("fly_to_rest", from, Vector3(0, CARD_REST_Y, 0), Vector3(-PI / 2.0, 0.0, 0.0),
			func() -> void: set_process(true))
		return
	var tween := card.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(card, "position", Vector3(0, CARD_REST_Y, 0), 0.3)
	tween.parallel().tween_property(card, "rotation", Vector3(-PI / 2.0, 0.0, 0.0), 0.3)
	tween.parallel().tween_property(card, "scale", Vector3.ONE, 0.2)
	tween.tween_callback(func() -> void: set_process(true))
