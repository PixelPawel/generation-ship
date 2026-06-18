extends Control

signal sector_advanced_pressed(slot_idx: int)
signal sector_dust_pressed(slot_idx: int)
signal expedition_pressed(slot_idx: int)
signal opponent_pressed(peer_id: int)

const CARD_W: int = 112
const CARD_H: int = 104

const _SUPPLY_PATHS: Array[String] = [
	"res://assets/ui/supply/Dust.png",
	"res://assets/ui/supply/Metals.png",
	"res://assets/ui/supply/Liquids.png",
	"res://assets/ui/supply/Organix.png",
	"res://assets/ui/supply/Electrix.png",
	"res://assets/ui/supply/Thrust.png",
]

var _sector_market: Node = null
var _expedition_market: Node = null

var _adv_rects:       Array[TextureRect] = []
var _adv_counts:      Array[Label]       = []
var _dust_rects:      Array[TextureRect] = []
var _dust_counts:     Array[Label]       = []
var _dust_highlights: Array[ColorRect]   = []
var _exp_rects:       Array[TextureRect] = []
var _exp_counts:      Array[Label]       = []
var _dust_slots:      Array[Control]     = []
var _adv_slots:       Array[Control]     = []
var _exp_slots:       Array[Control]     = []

var _opp_vbox: VBoxContainer = null
var _opp_refs: Dictionary = {}
var _opp_slot_data: Array[Dictionary] = []
var _opp_next_slot: int = 0

var _main_hbox: HBoxContainer = null
var _detail_panel: Control = null
var _detail_image: TextureRect = null
var _detail_slot_idx: int = -1
var _detail_is_advanced: bool = false
var _detail_is_expedition: bool = false

func _ready() -> void:
	_build_ui()

func setup(sector_market: Node, expedition_market: Node) -> void:
	_sector_market = sector_market
	_expedition_market = expedition_market
	sector_market.market_changed.connect(_refresh)
	sector_market.reveal_mode_changed.connect(_on_reveal_mode_changed)
	expedition_market.market_changed.connect(_refresh)
	_refresh()

func _init_opponent_slots() -> void:
	_opp_slot_data.clear()
	_opp_next_slot = 0
	for _i: int in 3:
		var entry: PanelContainer = PanelContainer.new()
		entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.size_flags_vertical = Control.SIZE_EXPAND_FILL
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color(0.02, 0.03, 0.08, 0.30)
		style.border_color = Color(0.22, 0.44, 0.70, 0.12)
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.content_margin_left = 9.0
		style.content_margin_right = 9.0
		style.content_margin_top = 7.0
		style.content_margin_bottom = 7.0
		entry.add_theme_stylebox_override("panel", style)
		_opp_vbox.add_child(entry)

		var entry_hbox: HBoxContainer = HBoxContainer.new()
		entry_hbox.add_theme_constant_override("separation", 8)
		entry_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry_hbox.visible = false
		entry.add_child(entry_hbox)

		var entry_vbox: VBoxContainer = VBoxContainer.new()
		entry_vbox.add_theme_constant_override("separation", 3)
		entry_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry_hbox.add_child(entry_vbox)

		var row1: HBoxContainer = HBoxContainer.new()
		row1.add_theme_constant_override("separation", 8)
		row1.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry_vbox.add_child(row1)

		var name_lbl: Label = Label.new()
		name_lbl.add_theme_font_size_override("font_size", 18)
		name_lbl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.clip_text = true
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row1.add_child(name_lbl)

		var hand_lbl: Label = Label.new()
		hand_lbl.text = "♠ 0"
		hand_lbl.add_theme_font_size_override("font_size", 16)
		hand_lbl.add_theme_color_override("font_color", Color(0.70, 0.82, 1.0))
		hand_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row1.add_child(hand_lbl)

		var vp_lbl: Label = Label.new()
		vp_lbl.text = "⭐ 0"
		vp_lbl.add_theme_font_size_override("font_size", 16)
		vp_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
		vp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row1.add_child(vp_lbl)

		var row2: HBoxContainer = HBoxContainer.new()
		row2.add_theme_constant_override("separation", 10)
		row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry_vbox.add_child(row2)

		var supply_lbls: Array = []
		supply_lbls.resize(6)
		var display_order: Array[int] = [0, 1, 2, 4, 3, 5]
		for display_i: int in 6:
			var si: int = display_order[display_i]
			var col: VBoxContainer = VBoxContainer.new()
			col.add_theme_constant_override("separation", 4)
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row2.add_child(col)
			var icon: TextureRect = TextureRect.new()
			icon.texture = load(_SUPPLY_PATHS[si]) as Texture2D
			icon.custom_minimum_size = Vector2(27.0, 27.0)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(icon)
			var s_lbl: Label = Label.new()
			s_lbl.text = "0"
			s_lbl.add_theme_font_size_override("font_size", 15)
			s_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.90))
			s_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			s_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(s_lbl)
			supply_lbls[si] = s_lbl

		_opp_slot_data.append({
			"entry": entry,
			"style": style,
			"hbox": entry_hbox,
			"name_lbl": name_lbl,
			"hand_lbl": hand_lbl,
			"supply_lbls": supply_lbls,
			"vp_lbl": vp_lbl,
		})

func add_opponent(peer_id: int, player_name: String) -> void:
	if _opp_refs.has(peer_id) or _opp_next_slot >= _opp_slot_data.size():
		return

	var slot: Dictionary = _opp_slot_data[_opp_next_slot]
	_opp_next_slot += 1

	var entry: PanelContainer = slot["entry"] as PanelContainer
	var style: StyleBoxFlat = slot["style"] as StyleBoxFlat
	style.bg_color = Color(0.05, 0.07, 0.15, 0.80)
	style.border_color = Color(0.22, 0.44, 0.70, 0.38)

	(slot["hbox"] as HBoxContainer).visible = true
	(slot["name_lbl"] as Label).text = player_name

	var pid: int = peer_id
	entry.mouse_filter = Control.MOUSE_FILTER_STOP
	entry.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			opponent_pressed.emit(pid)
		entry.accept_event()
	)
	entry.mouse_entered.connect(func() -> void: CursorManager.set_hover())
	entry.mouse_exited.connect(func() -> void: CursorManager.set_default())

	_opp_refs[peer_id] = {
		"hand_lbl": slot["hand_lbl"],
		"supply_lbls": slot["supply_lbls"],
		"vp_lbl": slot["vp_lbl"],
	}

func get_slot_center(card_type: String, slot_idx: int) -> Vector2:
	var slots: Array[Control]
	match card_type:
		"dust": slots = _dust_slots
		"advanced": slots = _adv_slots
		"expedition": slots = _exp_slots
		_: return Vector2.ZERO
	if slot_idx < 0 or slot_idx >= slots.size():
		return Vector2.ZERO
	return slots[slot_idx].get_global_rect().get_center()

func update_opponent(peer_id: int, hand_count: int, supply: Dictionary, vp: int) -> void:
	if not _opp_refs.has(peer_id):
		return
	var refs: Dictionary = _opp_refs[peer_id]
	(refs["hand_lbl"] as Label).text = "♠ %d" % hand_count
	var supply_lbls: Array = refs["supply_lbls"] as Array
	for si: int in 6:
		(supply_lbls[si] as Label).text = str(supply.get(si, 0))
	(refs["vp_lbl"] as Label).text = "⭐ %d" % vp

func _build_ui() -> void:
	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(10)
	panel.custom_minimum_size = Vector2(714.0, 340.0)
	add_child(panel)

	var main_hbox := HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 14)
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(main_hbox)
	_main_hbox = main_hbox

	# ── Column 1: Basic Sectors (stacked vertically) ──────────────────────────
	var basic_vbox := VBoxContainer.new()
	basic_vbox.add_theme_constant_override("separation", 4)
	basic_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	basic_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(basic_vbox)

	for i: int in 3:
		var rect := TextureRect.new()
		var count_lbl := Label.new()
		var highlight := ColorRect.new()
		var slot := _make_slot(Vector2(CARD_W, CARD_H), rect, count_lbl, highlight)
		_dust_rects.append(rect)
		_dust_counts.append(count_lbl)
		_dust_highlights.append(highlight)
		var idx: int = i
		slot.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton:
				var mb: InputEventMouseButton = ev as InputEventMouseButton
				if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
					var cd: CardData = _sector_market.get_dust_card_data(idx) if _sector_market else null
					if cd:
						_show_detail(cd, idx, false, false)
		)
		slot.mouse_entered.connect(func() -> void: CursorManager.set_hover())
		slot.mouse_exited.connect(func() -> void: CursorManager.set_default())
		basic_vbox.add_child(slot)
		_dust_slots.append(slot)

	# ── Column 2: Advanced Sectors (stacked vertically) ───────────────────────
	var vsep1 := VSeparator.new()
	vsep1.modulate = Color(0.4, 0.4, 0.5, 0.6)
	main_hbox.add_child(vsep1)

	var adv_vbox := VBoxContainer.new()
	adv_vbox.add_theme_constant_override("separation", 4)
	adv_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	adv_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(adv_vbox)

	for i: int in 3:
		var rect := TextureRect.new()
		var count_lbl := Label.new()
		var slot := _make_slot(Vector2(CARD_W, CARD_H), rect, count_lbl, null)
		_adv_rects.append(rect)
		_adv_counts.append(count_lbl)
		var idx: int = i
		slot.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton:
				var mb: InputEventMouseButton = ev as InputEventMouseButton
				if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
					var cd: CardData = _sector_market.get_advanced_card_data(idx) if _sector_market else null
					if cd:
						_show_detail(cd, idx, true, false)
		)
		slot.mouse_entered.connect(func() -> void: CursorManager.set_hover())
		slot.mouse_exited.connect(func() -> void: CursorManager.set_default())
		adv_vbox.add_child(slot)
		_adv_slots.append(slot)

	# ── Column 3: Expeditions (stacked vertically) ────────────────────────────
	var vsep2 := VSeparator.new()
	vsep2.modulate = Color(0.4, 0.4, 0.5, 0.6)
	main_hbox.add_child(vsep2)

	var exp_vbox := VBoxContainer.new()
	exp_vbox.add_theme_constant_override("separation", 4)
	exp_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	exp_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(exp_vbox)

	for i: int in 3:
		var rect := TextureRect.new()
		var count_lbl := Label.new()
		var slot := _make_slot(Vector2(CARD_W, CARD_H), rect, count_lbl, null)
		_exp_rects.append(rect)
		_exp_counts.append(count_lbl)
		var idx: int = i
		slot.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton:
				var mb: InputEventMouseButton = ev as InputEventMouseButton
				if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
					var cd: CardData = _expedition_market.get_card_data(idx) if _expedition_market else null
					if cd:
						_show_detail(cd, idx, false, true)
		)
		slot.mouse_entered.connect(func() -> void: CursorManager.set_hover())
		slot.mouse_exited.connect(func() -> void: CursorManager.set_default())
		exp_vbox.add_child(slot)
		_exp_slots.append(slot)

	# ── Column 4: Players ──────────────────────────────────────────────────────
	var vsep3 := VSeparator.new()
	vsep3.modulate = Color(0.4, 0.4, 0.5, 0.6)
	main_hbox.add_child(vsep3)

	var players_vbox := VBoxContainer.new()
	players_vbox.add_theme_constant_override("separation", 4)
	players_vbox.custom_minimum_size = Vector2(240.0, 0.0)
	players_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(players_vbox)

	_opp_vbox = VBoxContainer.new()
	_opp_vbox.add_theme_constant_override("separation", 4)
	_opp_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	players_vbox.add_child(_opp_vbox)
	_init_opponent_slots()

	_build_detail_overlay(panel)

func _make_slot(size: Vector2, rect: TextureRect, count_lbl: Label, highlight: ColorRect) -> Control:
	var root := Control.new()
	root.custom_minimum_size = size
	root.mouse_filter = Control.MOUSE_FILTER_STOP

	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://shaders/card_rounded.gdshader")
	rect.material = mat
	root.add_child(rect)

	count_lbl.add_theme_font_size_override("font_size", 14)
	count_lbl.add_theme_color_override("font_color", Color.WHITE)
	count_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	count_lbl.add_theme_constant_override("shadow_offset_x", 1)
	count_lbl.add_theme_constant_override("shadow_offset_y", 1)
	count_lbl.position = Vector2(3.0, 2.0)
	count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(count_lbl)

	if highlight:
		highlight.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		highlight.color = Color(0.2, 0.85, 0.3, 0.28)
		highlight.visible = false
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(highlight)

	return root

func refresh() -> void:
	_refresh()

func _refresh() -> void:
	if not _sector_market or not _expedition_market:
		return
	for i: int in 3:
		_refresh_adv(i)
		_refresh_dust(i)
		_refresh_exp(i)

func _refresh_adv(i: int) -> void:
	var cd: CardData = _sector_market.get_advanced_card_data(i)
	if cd:
		var url: String = cd.adv_image_url if not cd.adv_image_url.is_empty() else cd.image_url
		_adv_rects[i].texture = ImageCache.get_texture(url) if not url.is_empty() else null
	else:
		_adv_rects[i].texture = null
	var cnt: int = _sector_market.get_advanced_count(i)
	_adv_counts[i].text = "×%d" % cnt if cnt > 0 else ""

func _refresh_dust(i: int) -> void:
	var cd: CardData = _sector_market.get_dust_card_data(i)
	if cd:
		_dust_rects[i].texture = ImageCache.get_texture(cd.image_url) if not cd.image_url.is_empty() else null
	else:
		_dust_rects[i].texture = null
	var cnt: int = _sector_market.get_dust_count(i)
	_dust_counts[i].text = "×%d" % cnt if cnt > 0 else ""

func _refresh_exp(i: int) -> void:
	var cd: CardData = _expedition_market.get_card_data(i)
	if cd:
		_exp_rects[i].texture = ImageCache.get_texture(cd.image_url) if not cd.image_url.is_empty() else null
	else:
		_exp_rects[i].texture = null
	var cnt: int = _expedition_market.get_count(i)
	_exp_counts[i].text = "×%d" % cnt if cnt > 0 else ""

func _on_reveal_mode_changed(active: bool) -> void:
	for highlight: ColorRect in _dust_highlights:
		highlight.visible = active

func _build_detail_overlay(panel: Control) -> void:
	_detail_panel = Control.new()
	_detail_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_panel.visible = false
	panel.add_child(_detail_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	_detail_panel.add_child(vbox)

	_detail_image = TextureRect.new()
	_detail_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var _detail_mat: ShaderMaterial = ShaderMaterial.new()
	_detail_mat.shader = load("res://shaders/card_rounded.gdshader")
	_detail_image.material = _detail_mat
	vbox.add_child(_detail_image)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var back_btn := Button.new()
	back_btn.text = "← Back"
	back_btn.custom_minimum_size = Vector2(120.0, 40.0)
	back_btn.pressed.connect(_hide_detail)
	btn_row.add_child(back_btn)

	var buy_btn := Button.new()
	buy_btn.text = "Buy Card"
	buy_btn.custom_minimum_size = Vector2(120.0, 40.0)
	buy_btn.pressed.connect(_on_detail_buy_pressed)
	btn_row.add_child(buy_btn)

func _show_detail(cd: CardData, slot_idx: int, is_advanced: bool, is_expedition: bool) -> void:
	_detail_slot_idx = slot_idx
	_detail_is_advanced = is_advanced
	_detail_is_expedition = is_expedition
	var url: String = cd.adv_image_url if is_advanced and not cd.adv_image_url.is_empty() else cd.image_url
	_detail_image.texture = ImageCache.get_texture(url) if not url.is_empty() else null
	_main_hbox.visible = false
	_detail_panel.visible = true

func _hide_detail() -> void:
	_detail_panel.visible = false
	_main_hbox.visible = true
	_detail_slot_idx = -1

func _on_detail_buy_pressed() -> void:
	var idx: int = _detail_slot_idx
	var is_adv: bool = _detail_is_advanced
	var is_exp: bool = _detail_is_expedition
	_hide_detail()
	if is_exp:
		expedition_pressed.emit(idx)
	elif is_adv:
		sector_advanced_pressed.emit(idx)
	else:
		sector_dust_pressed.emit(idx)
