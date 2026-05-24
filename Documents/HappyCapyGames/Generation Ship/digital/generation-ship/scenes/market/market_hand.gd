extends Node3D


const CARD_SCALE        := 0.45
const HOVER_SCALE       := CARD_SCALE * 1.67
const HOVER_LIFT        := 0.50
const HOVER_CENTER_PULL := 0.15
const EXP_HOVER_LIFT_Y  := 0.20
const DUST_CENTER    := Vector3(-1.6, 0.88, -1.5)
const ADV_CENTER     := Vector3(-1.6, 0.48, -1.5)
const EXP_CENTER     := Vector3(-1.6, 0.08, -1.5)
const FAN_SPACING    := 0.20
const FAN_ARC        := 0.04
const FAN_ROT_DEG    := 2.5

const FLOAT_AMP   := 0.020
const FLOAT_SPEED := 0.07

var _sector_market: Node = null
var _expedition_market: Node = null
var _reveal_mode: bool = false
var _exp_reveal_mode: bool = false
var _adv_cards: Array[Node3D] = []
var _dust_cards: Array[Node3D] = []
var _exp_cards: Array[Node3D] = []
var _rest_positions: Dictionary = {}
var _rest_rotations: Dictionary = {}
var _rest_sort_orders: Dictionary = {}
var _hover_tweens: Dictionary = {}
var _float_phases: Dictionary = {}
var _hidden_drag_slot: int = -1
var _hidden_drag_type: String = ""

func setup(sector_market: Node, expedition_market: Node, card_scene: PackedScene) -> void:
	_sector_market = sector_market
	_expedition_market = expedition_market
	_build_cards(card_scene)
	sector_market.market_changed.connect(_refresh)
	sector_market.reveal_mode_changed.connect(_on_reveal_mode_changed)
	sector_market.card_revealed.connect(_on_sector_card_revealed)
	expedition_market.market_changed.connect(_refresh)
	expedition_market.card_added.connect(_on_expedition_card_added)
	expedition_market.reveal_mode_changed.connect(_on_expedition_reveal_mode_changed)
	_refresh()

func _make_card(card_scene: PackedScene, is_advanced: bool) -> Node3D:
	var card: Node3D = card_scene.instantiate()
	card.can_drag = false
	card.managed_by_hand = true
	card.is_advanced = is_advanced
	add_child(card)
	_float_phases[card] = randf() * TAU
	card.hovered.connect(func(_c: Node3D) -> void: CursorManager.set_hover())
	card.unhovered.connect(func(_c: Node3D) -> void: CursorManager.set_default())
	return card

func _connect_card_click(card: Node3D, is_exp: bool) -> void:
	card.right_clicked.connect(func(_c: Node3D) -> void:
		_do_market_toggle(card, is_exp)
	)

func _build_cards(card_scene: PackedScene) -> void:
	for i: int in 3:
		var card: Node3D = _make_card(card_scene, true)
		_connect_card_click(card, false)
		_adv_cards.append(card)
	for i: int in 3:
		var card: Node3D = _make_card(card_scene, false)
		_connect_card_click(card, false)
		_dust_cards.append(card)
	for i: int in 3:
		var card: Node3D = _make_card(card_scene, false)
		_connect_card_click(card, true)
		_exp_cards.append(card)
	_layout_fans()

func _layout_fans() -> void:
	_layout_fan(_dust_cards, DUST_CENTER, 0.0)
	_layout_fan(_adv_cards, ADV_CENTER, 0.0)
	_layout_fan(_exp_cards, EXP_CENTER, 0.0)

func _layout_fan(cards: Array[Node3D], center: Vector3, base_rot_z: float) -> void:
	var n: int = cards.size()
	var total_width: float = FAN_SPACING * (n - 1)
	for i: int in n:
		var x: float = -total_width * 0.5 + float(i) * FAN_SPACING
		var t: float = float(i) / float(max(n - 1, 1)) * 2.0 - 1.0
		var y_arc: float = -(t * t) * FAN_ARC
		var rot_z: float = base_rot_z + t * deg_to_rad(-FAN_ROT_DEG)
		var pos := Vector3(center.x + x, center.y + y_arc, center.z + float(i) * 0.001)
		var rot := Vector3(0.0, 0.0, rot_z)
		cards[i].position = pos
		cards[i].rotation = rot
		cards[i].scale = Vector3.ONE * CARD_SCALE
		var sort: float = float(i) * 0.01
		cards[i].set_sort_order(sort)
		_rest_positions[cards[i]] = pos
		_rest_rotations[cards[i]] = rot
		_rest_sort_orders[cards[i]] = sort
		cards[i].set("_elev_rest_pos", pos)
		cards[i].set("_elev_rest_scale", Vector3.ONE * CARD_SCALE)

func _refresh() -> void:
	if not _sector_market or not _expedition_market:
		return
	for i: int in 3:
		_refresh_adv(i)
		_refresh_dust(i)
		_refresh_exp(i)

func _refresh_slot(i: int, cards: Array[Node3D], hidden_type: String, get_data: Callable) -> void:
	if _hidden_drag_type == hidden_type and _hidden_drag_slot == i:
		cards[i].visible = false
		return
	var cd: CardData = get_data.call(i)
	cards[i].visible = cd != null
	if cd:
		cards[i].set_card_data(cd)

func _refresh_adv(i: int) -> void:
	_refresh_slot(i, _adv_cards, "adv", _sector_market.get_advanced_card_data)

func _refresh_dust(i: int) -> void:
	_refresh_slot(i, _dust_cards, "dust", _sector_market.get_dust_card_data)

func _refresh_exp(i: int) -> void:
	_refresh_slot(i, _exp_cards, "exp", _expedition_market.get_card_data)

func on_market_drag_started(card: Node3D) -> void:
	var slot_idx: int = card.get_meta("market_slot", -1)
	if slot_idx < 0:
		return
	var cd: CardData = card.get("card_data") as CardData
	if not cd:
		return
	if cd.card_type == CardData.CardType.EXPEDITION:
		_hidden_drag_type = "exp"
	elif bool(card.get("is_advanced")):
		_hidden_drag_type = "adv"
	else:
		_hidden_drag_type = "dust"
	_hidden_drag_slot = slot_idx
	_refresh()

func on_market_drag_ended() -> void:
	_hidden_drag_slot = -1
	_hidden_drag_type = ""
	_refresh()

func _process(_delta: float) -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	var shared_z: float = sin(t * FLOAT_SPEED * TAU) * FLOAT_AMP
	var all_cards: Array[Node3D] = _adv_cards + _dust_cards + _exp_cards
	var any_elevated: bool = false
	for card: Node3D in all_cards:
		if card.get("_placed_elevated") as bool:
			any_elevated = true
			break
	for card: Node3D in all_cards:
		if not card.visible or any_elevated:
			continue
		var tween: Tween = _hover_tweens.get(card) as Tween
		if tween and tween.is_valid():
			continue
		var rest: Vector3 = _rest_positions.get(card, card.position) as Vector3
		var phase: float = _float_phases.get(card, 0.0) as float
		var bob_y: float = sin(t * FLOAT_SPEED * TAU * 1.37 + phase + 1.1) * FLOAT_AMP * 0.35
		card.position = rest + Vector3(0.0, bob_y, shared_z)

func _do_market_toggle(card: Node3D, is_exp: bool) -> void:
	_kill_hover_tween(card)
	card.toggle_elevation(_market_elev_target(card, is_exp), Vector3.ONE * HOVER_SCALE, 0.0)
	_hover_tweens[card] = card.get("_tween")

func _market_elev_target(card: Node3D, is_exp: bool) -> Vector3:
	var rest: Vector3 = _rest_positions.get(card, card.position) as Vector3
	var s: float = (rest.z + HOVER_LIFT) / rest.z
	var y_boost: float = EXP_HOVER_LIFT_Y if is_exp else 0.0
	return Vector3(
		lerpf(rest.x * s, 0.0, HOVER_CENTER_PULL),
		lerpf(rest.y * s, 0.0, HOVER_CENTER_PULL) + y_boost,
		rest.z + HOVER_LIFT)

func _kill_hover_tween(card: Node3D) -> void:
	if _hover_tweens.has(card):
		var t: Tween = _hover_tweens[card] as Tween
		if t and t.is_valid():
			t.kill()

func _on_sector_card_revealed(slot_idx: int) -> void:
	_play_reveal_card(_adv_cards[slot_idx])

func _on_expedition_card_added(slot_idx: int) -> void:
	_play_reveal_card(_exp_cards[slot_idx])

func _play_reveal_card(card: Node3D) -> void:
	if not card.visible:
		return
	var rest_pos: Vector3 = _rest_positions.get(card, card.position) as Vector3
	var rest_rot: Vector3 = _rest_rotations.get(card, card.rotation) as Vector3
	_kill_hover_tween(card)
	card.position = rest_pos
	card.rotation = Vector3(0.0, PI, rest_rot.z)
	card.scale = Vector3.ONE * (CARD_SCALE * 0.8)
	var t: Tween = card.create_tween()
	t.tween_property(card, "rotation", rest_rot, 0.40).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	t.parallel().tween_property(card, "scale", Vector3.ONE * (CARD_SCALE * 1.1), 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(card, "scale", Vector3.ONE * CARD_SCALE, 0.18).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	_hover_tweens[card] = t

func _on_reveal_mode_changed(active: bool) -> void:
	_reveal_mode = active
	for card: Node3D in _dust_cards:
		_set_dust_glow(card, active)

func _on_expedition_reveal_mode_changed(active: bool) -> void:
	_exp_reveal_mode = active

func _set_dust_glow(card: Node3D, active: bool) -> void:
	var mesh_node: MeshInstance3D = card.get_node_or_null("CardMesh") as MeshInstance3D
	if not mesh_node:
		return
	var mat: ShaderMaterial = mesh_node.get_surface_override_material(0) as ShaderMaterial
	if mat:
		mat.set_shader_parameter("discount_glow_color",
			Vector3(0.2, 1.0, 0.3) if active else Vector3.ZERO)
