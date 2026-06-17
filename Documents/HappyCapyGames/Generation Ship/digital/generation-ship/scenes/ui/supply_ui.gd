class_name SupplyUI
extends Control

signal research_pressed
signal pass_pressed
signal supply_changed
signal end_turn_pressed
signal fuse_1to1_changed

const SUPPLY_DEFS := [
	{ "color": CardData.SupplyColor.DUST,     "path": "res://assets/ui/supply/Dust.png" },
	{ "color": CardData.SupplyColor.METALS,   "path": "res://assets/ui/supply/Metals.png" },
	{ "color": CardData.SupplyColor.LIQUIDS,  "path": "res://assets/ui/supply/Liquids.png" },
	{ "color": CardData.SupplyColor.ORGANIX,  "path": "res://assets/ui/supply/Organix.png" },
	{ "color": CardData.SupplyColor.ELECTRIX, "path": "res://assets/ui/supply/Electrix.png" },
	{ "color": CardData.SupplyColor.THRUST,   "path": "res://assets/ui/supply/Thrust.png" },
]

const FUSE_MAP: Dictionary = {
	CardData.SupplyColor.DUST:     [CardData.SupplyColor.METALS, CardData.SupplyColor.LIQUIDS],
	CardData.SupplyColor.METALS:   [CardData.SupplyColor.ELECTRIX],
	CardData.SupplyColor.LIQUIDS:  [CardData.SupplyColor.ORGANIX],
	CardData.SupplyColor.ORGANIX:  [CardData.SupplyColor.THRUST],
	CardData.SupplyColor.ELECTRIX: [CardData.SupplyColor.THRUST],
}

var _counts: Dictionary = {}
var _icon_textures: Dictionary = {}
var _flow: Control = null
var _fuse_1to1_remaining: int = 0
var _fuse_dust_1to1: bool = false
var _fuse_1to1_label: Label = null
var _fuse_history: Array[Dictionary] = []
var _undo_btn: Button = null
var _action_row: HBoxContainer = null
var _research_btn: Button = null
var _pass_btn: Button = null
var _end_turn_btn: Button = null
var _game_info_box: Control = null
var _round_label: Label = null
var _vp_label: Label = null
var _prev_vp: int = 0
var _end_turn_pulse_tween: Tween = null
var _tooltip_panel: PanelContainer = null
var _tooltip_title: Label = null
var _tooltip_desc: Label = null

func _ready() -> void:
	for def: Dictionary in SUPPLY_DEFS:
		_icon_textures[def["color"]] = load(def["path"])
	_build_ui()
func _flow_positions() -> Dictionary:
	return {
		CardData.SupplyColor.DUST:     Vector2(115, 34),
		CardData.SupplyColor.LIQUIDS:  Vector2(39, 100),
		CardData.SupplyColor.METALS:   Vector2(191, 100),
		CardData.SupplyColor.ORGANIX:  Vector2(39, 202),
		CardData.SupplyColor.ELECTRIX: Vector2(191, 202),
		CardData.SupplyColor.THRUST:   Vector2(115, 259),
	}

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	for def: Dictionary in SUPPLY_DEFS:
		_counts[def["color"]] = 0

	# ── Single panel — bottom-left ───────────────────────────────────────────
	var supply_panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	supply_panel.set_content_margin(10)
	supply_panel.anchor_left   = 0.0
	supply_panel.anchor_top    = 1.0
	supply_panel.anchor_right  = 0.0
	supply_panel.anchor_bottom = 1.0
	supply_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	supply_panel.offset_left   = 16.0
	supply_panel.offset_bottom = -16.0
	add_child(supply_panel)

	var ship_bg := TextureRect.new()
	ship_bg.texture = load("res://assets/ui/Player_Ship_1.png") as Texture2D
	ship_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ship_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ship_bg.modulate = Color(1.0, 1.0, 1.0, 0.35)
	ship_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	supply_panel.add_child(ship_bg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	supply_panel.add_child(vbox)

	# ── Game info (round + VP) ────────────────────────────────────────────────
	_game_info_box = VBoxContainer.new()
	_game_info_box.add_theme_constant_override("separation", 4)
	_game_info_box.visible = false
	vbox.add_child(_game_info_box)

	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 6)
	_game_info_box.add_child(info_row)

	_round_label = Label.new()
	_round_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_round_label.add_theme_font_size_override("font_size", 15)
	_round_label.add_theme_color_override("font_color", Color(0.72, 0.72, 0.82))
	info_row.add_child(_round_label)

	_vp_label = Label.new()
	_vp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_vp_label.add_theme_font_size_override("font_size", 15)
	_vp_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	info_row.add_child(_vp_label)

	var info_sep := HSeparator.new()
	info_sep.modulate = Color(0.4, 0.4, 0.5, 0.5)
	_game_info_box.add_child(info_sep)

	_undo_btn = Button.new()
	_undo_btn.text = "↩ Undo Fuse"
	_undo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_undo_btn.add_theme_font_size_override("font_size", 14)
	_undo_btn.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	_undo_btn.disabled = true
	_undo_btn.pressed.connect(_on_undo_fuse_pressed)
	vbox.add_child(_undo_btn)

	# ── Supply flow ───────────────────────────────────────────────────────────
	var flow_sep := HSeparator.new()
	flow_sep.modulate = Color(0.4, 0.4, 0.5, 0.5)
	vbox.add_child(flow_sep)

	var flow_center := CenterContainer.new()
	flow_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(flow_center)

	_flow = load("res://scenes/ui/supply_flow.gd").new()
	_flow.custom_minimum_size = Vector2(230, 280)
	_flow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_flow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_flow.setup(_flow_positions(), FUSE_MAP, _icon_textures)
	_flow.fuse_clicked.connect(_on_fuse_clicked)
	flow_center.add_child(_flow)

	_fuse_1to1_label = Label.new()
	_fuse_1to1_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fuse_1to1_label.add_theme_font_size_override("font_size", 13)
	_fuse_1to1_label.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	_fuse_1to1_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fuse_1to1_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_fuse_1to1_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_fuse_1to1_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_fuse_1to1_label.visible = false
	_flow.add_child(_fuse_1to1_label)

	_refresh_arrows()

	# ── Button tooltip overlay ────────────────────────────────────────────────
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_tooltip_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tooltip_panel.grow_vertical = Control.GROW_DIRECTION_END
	_tooltip_panel.offset_top = 8.0
	var tt_style: StyleBoxFlat = StyleBoxFlat.new()
	tt_style.bg_color = Color(0.05, 0.07, 0.15, 0.94)
	tt_style.border_color = Color(0.3, 0.55, 0.85, 0.55)
	tt_style.set_border_width_all(1)
	tt_style.set_corner_radius_all(4)
	tt_style.content_margin_left = 12.0
	tt_style.content_margin_right = 12.0
	tt_style.content_margin_top = 8.0
	tt_style.content_margin_bottom = 8.0
	_tooltip_panel.add_theme_stylebox_override("panel", tt_style)
	var tt_vbox: VBoxContainer = VBoxContainer.new()
	tt_vbox.add_theme_constant_override("separation", 3)
	tt_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.add_child(tt_vbox)
	_tooltip_title = Label.new()
	_tooltip_title.add_theme_font_size_override("font_size", 16)
	_tooltip_title.add_theme_color_override("font_color", Color(0.82, 0.93, 1.0))
	_tooltip_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tooltip_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tt_vbox.add_child(_tooltip_title)
	_tooltip_desc = Label.new()
	_tooltip_desc.add_theme_font_size_override("font_size", 13)
	_tooltip_desc.add_theme_color_override("font_color", Color(0.60, 0.68, 0.82))
	_tooltip_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tooltip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_tooltip_desc.custom_minimum_size = Vector2(230, 0)
	_tooltip_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tt_vbox.add_child(_tooltip_desc)
	add_child(_tooltip_panel)


func show_button_tooltip(title: String, desc: String) -> void:
	if not _tooltip_panel:
		return
	_tooltip_title.text = title
	_tooltip_desc.text = desc
	_tooltip_panel.visible = true

func hide_button_tooltip() -> void:
	if _tooltip_panel:
		_tooltip_panel.visible = false


func _on_fuse_clicked(src: int, dst: int) -> void:
	_fuse(src, dst)

func _fuse(source: int, target: int) -> void:
	var is_dust_free: bool = source == CardData.SupplyColor.DUST and _fuse_dust_1to1
	var used_token: bool = not is_dust_free and _fuse_1to1_remaining > 0
	var cost: int = 1 if (is_dust_free or used_token) else 2
	if _counts.get(source, 0) < cost:
		return
	UIAudio.play_fuse_sfx()
	if used_token:
		_fuse_1to1_remaining -= 1
		_update_fuse_1to1_label()
	spend_supply(source, cost)
	add_supply(target, 1)
	_fuse_history.append({source = source, target = target, cost = cost, used_1to1_token = used_token})
	_update_undo_btn()

func _on_undo_fuse_pressed() -> void:
	if _fuse_history.is_empty():
		return
	var entry: Dictionary = _fuse_history.pop_back()
	var src: int = int(entry.source)
	var tgt: int = int(entry.target)
	var cost: int = int(entry.cost)
	set_supply(src, _counts.get(src, 0) + cost)
	set_supply(tgt, maxi(0, _counts.get(tgt, 0) - 1))
	if bool(entry.used_1to1_token):
		_fuse_1to1_remaining += 1
		_update_fuse_1to1_label()
	_refresh_arrows()
	_update_undo_btn()

func _update_undo_btn() -> void:
	if _undo_btn:
		_undo_btn.disabled = _fuse_history.is_empty()

func _get_fuse_threshold(src: int) -> int:
	if src == CardData.SupplyColor.DUST and _fuse_dust_1to1:
		return 1
	if _fuse_1to1_remaining > 0:
		return 1
	return 2

func _refresh_arrows() -> void:
	if not _flow:
		return
	for src: int in FUSE_MAP:
		var can_fuse: bool = _counts.get(src, 0) >= _get_fuse_threshold(src)
		var is_1to1: bool = (src == CardData.SupplyColor.DUST and _fuse_dust_1to1) or _fuse_1to1_remaining > 0
		for dst: int in FUSE_MAP[src]:
			_flow.set_arrow_enabled(src, dst, can_fuse, is_1to1)

func set_supply(supply_color: CardData.SupplyColor, count: int) -> void:
	_counts[supply_color] = count
	if _flow:
		_flow.update_label(supply_color, count)
	_refresh_arrows()
	supply_changed.emit()

func add_supply(supply_color: CardData.SupplyColor, amount: int) -> void:
	set_supply(supply_color, _counts.get(supply_color, 0) + amount)
	if amount > 0:
		_spawn_floating_label(supply_color, "+%d" % amount)

func _spawn_floating_label(supply_color: CardData.SupplyColor, text: String) -> void:
	if not _flow:
		return
	var src_rect: Rect2 = _flow.get_label_global_rect(supply_color)
	if src_rect.size == Vector2.ZERO:
		return
	var local_pos: Vector2 = src_rect.position - get_global_rect().position
	_spawn_float_label(text, local_pos, Color(0.4, 1.0, 0.5), 24, 48.0, 0.8)

func animate_supply_incoming(from_screen_pos: Vector2, supply_color: CardData.SupplyColor, delay: float = 0.0) -> void:
	if not _flow:
		return
	var target_rect: Rect2 = _flow.get_label_global_rect(supply_color)
	if target_rect.size == Vector2.ZERO:
		return
	var self_rect: Rect2 = get_global_rect()
	var start_local: Vector2 = from_screen_pos - self_rect.position
	var end_local: Vector2 = target_rect.get_center() - self_rect.position
	var icon := TextureRect.new()
	icon.texture = _icon_textures.get(supply_color) as Texture2D
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.z_index = 20
	icon.modulate.a = 0.0
	add_child(icon)
	icon.custom_minimum_size = Vector2(44, 44)
	icon.size = Vector2(44, 44)
	icon.pivot_offset = Vector2(22, 22)
	icon.position = start_local - Vector2(22, 22)
	var t: Tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_property(icon, "modulate:a", 1.0, 0.08)
	t.tween_property(icon, "position", end_local - Vector2(22, 22), 0.45)
	t.parallel().tween_property(icon, "scale", Vector2(0.2, 0.2), 0.45)
	t.parallel().tween_property(icon, "modulate:a", 0.0, 0.45)
	t.tween_callback(icon.queue_free)

func spend_supply(supply_color: CardData.SupplyColor, amount: int) -> void:
	set_supply(supply_color, maxi(0, _counts.get(supply_color, 0) - amount))

func get_supply(supply_color: CardData.SupplyColor) -> int:
	return _counts.get(supply_color, 0)

func show_action_buttons(visible_state: bool) -> void:
	if _action_row:
		_action_row.visible = visible_state

func show_end_turn_button(visible_state: bool) -> void:
	if not _end_turn_btn:
		return
	_end_turn_btn.visible = visible_state
	if visible_state and not _end_turn_btn.disabled:
		_start_end_turn_pulse()
	else:
		_stop_end_turn_pulse()

func set_end_turn_button_disabled(disabled: bool) -> void:
	if not _end_turn_btn:
		return
	_end_turn_btn.disabled = disabled
	if disabled or not _end_turn_btn.visible:
		_stop_end_turn_pulse()
	else:
		_start_end_turn_pulse()

func _start_end_turn_pulse() -> void:
	if _end_turn_pulse_tween:
		_end_turn_pulse_tween.kill()
	_end_turn_pulse_tween = create_tween().set_loops()
	_end_turn_pulse_tween.tween_property(_end_turn_btn, "modulate",
		Color(1.5, 0.22, 0.22, 1.0), 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_end_turn_pulse_tween.tween_property(_end_turn_btn, "modulate",
		Color(1.0, 0.52, 0.52, 1.0), 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _stop_end_turn_pulse() -> void:
	if _end_turn_pulse_tween:
		_end_turn_pulse_tween.kill()
		_end_turn_pulse_tween = null
	if _end_turn_btn:
		_end_turn_btn.modulate = Color.WHITE

func can_end_turn() -> bool:
	return _end_turn_btn != null and _end_turn_btn.visible and not _end_turn_btn.disabled

func set_action_buttons_disabled(disabled: bool) -> void:
	if _research_btn:
		_research_btn.disabled = disabled
	if _pass_btn:
		_pass_btn.disabled = disabled

func add_fuse_1to1(count: int) -> void:
	_fuse_1to1_remaining += count
	_update_fuse_1to1_label()
	_refresh_arrows()

func set_dust_fuse_1to1(enabled: bool) -> void:
	_fuse_dust_1to1 = enabled
	_update_fuse_1to1_label()
	_refresh_arrows()

func clear_fuse_1to1() -> void:
	_fuse_1to1_remaining = 0
	_fuse_dust_1to1 = false
	_fuse_history.clear()
	_update_fuse_1to1_label()
	_update_undo_btn()
	_refresh_arrows()

func has_fuse_1to1_active() -> bool:
	return _fuse_1to1_remaining > 0 or _fuse_dust_1to1

func _update_fuse_1to1_label() -> void:
	if not _fuse_1to1_label:
		return
	if _fuse_dust_1to1:
		_fuse_1to1_label.text = "⚡ DUST FUSE 1:1\nUnlimited"
		_fuse_1to1_label.visible = true
	elif _fuse_1to1_remaining > 0:
		_fuse_1to1_label.text = "⚡ FUSE 1:1\n%d left" % _fuse_1to1_remaining
		_fuse_1to1_label.visible = true
	else:
		_fuse_1to1_label.visible = false
	fuse_1to1_changed.emit()

func set_round(current: int, max_rounds: int) -> void:
	if _round_label:
		_round_label.text = "Round %d / %d" % [current, max_rounds]

func set_vp(vp: int) -> void:
	var gained: int = vp - _prev_vp
	_prev_vp = vp
	if _vp_label:
		_vp_label.text = "⭐ %d VP" % vp
	if gained > 0 and _vp_label:
		_spawn_vp_label("+%d VP" % gained)

func _spawn_vp_label(text: String) -> void:
	var src_rect: Rect2 = _vp_label.get_global_rect()
	var local_pos: Vector2 = src_rect.get_center() - get_global_rect().position - Vector2(30.0, 13.0)
	_spawn_float_label(text, local_pos, Color(1.0, 0.88, 0.35), 26, 56.0, 1.0)

func _spawn_float_label(text: String, local_pos: Vector2, color: Color, font_size: int, rise: float, duration: float) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 10
	add_child(lbl)
	lbl.position = local_pos
	var t: Tween = create_tween()
	t.tween_property(lbl, "position:y", lbl.position.y - rise, duration).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(lbl, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)
	t.tween_callback(lbl.queue_free)

func show_game_info(visible_state: bool) -> void:
	if _game_info_box:
		_game_info_box.visible = visible_state
