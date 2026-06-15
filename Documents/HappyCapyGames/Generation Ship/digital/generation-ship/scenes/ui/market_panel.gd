extends Control

signal sector_advanced_pressed(slot_idx: int)
signal sector_dust_pressed(slot_idx: int)
signal expedition_pressed(slot_idx: int)

const CARD_W: int = 70
const CARD_H: int = 98

var _sector_market: Node = null
var _expedition_market: Node = null

var _adv_rects:       Array[TextureRect] = []
var _adv_counts:      Array[Label]       = []
var _dust_rects:      Array[TextureRect] = []
var _dust_counts:     Array[Label]       = []
var _dust_highlights: Array[ColorRect]   = []
var _exp_rects:       Array[TextureRect] = []
var _exp_counts:      Array[Label]       = []

var _pinned: bool = false

func _ready() -> void:
	_build_ui()

func _process(_delta: float) -> void:
	if _pinned:
		return
	var inner: Control = get_child(0) as Control
	if inner and inner.size.x > 0:
		var vp: Vector2 = get_viewport().get_visible_rect().size
		position = Vector2((vp.x - inner.size.x) * 0.5, 12.0)
		_pinned = true
		set_process(false)

func setup(sector_market: Node, expedition_market: Node) -> void:
	_sector_market = sector_market
	_expedition_market = expedition_market
	sector_market.market_changed.connect(_refresh)
	sector_market.reveal_mode_changed.connect(_on_reveal_mode_changed)
	expedition_market.market_changed.connect(_refresh)
	_refresh()

func _build_ui() -> void:
	var main_hbox := HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 14)
	main_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(main_hbox)

	# ── Sectors group ─────────────────────────────────────────────────────────
	var sec_vbox := VBoxContainer.new()
	sec_vbox.add_theme_constant_override("separation", 4)
	sec_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_hbox.add_child(sec_vbox)

	var sec_hdr := Label.new()
	sec_hdr.text = "SECTORS"
	sec_hdr.add_theme_font_size_override("font_size", 13)
	sec_hdr.add_theme_color_override("font_color", Color(0.75, 0.8, 1.0))
	sec_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sec_vbox.add_child(sec_hdr)

	var sec_row := HBoxContainer.new()
	sec_row.add_theme_constant_override("separation", 5)
	sec_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sec_vbox.add_child(sec_row)

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
					sector_advanced_pressed.emit(idx)
		)
		slot.mouse_entered.connect(func() -> void: CursorManager.set_hover())
		slot.mouse_exited.connect(func() -> void: CursorManager.set_default())
		sec_row.add_child(slot)

	var vsep1 := VSeparator.new()
	vsep1.modulate = Color(0.4, 0.4, 0.5, 0.5)
	sec_row.add_child(vsep1)

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
					sector_dust_pressed.emit(idx)
		)
		slot.mouse_entered.connect(func() -> void: CursorManager.set_hover())
		slot.mouse_exited.connect(func() -> void: CursorManager.set_default())
		sec_row.add_child(slot)

	# ── Separator ─────────────────────────────────────────────────────────────
	var vsep_main := VSeparator.new()
	vsep_main.modulate = Color(0.4, 0.4, 0.5, 0.6)
	main_hbox.add_child(vsep_main)

	# ── Expeditions group ─────────────────────────────────────────────────────
	var exp_vbox := VBoxContainer.new()
	exp_vbox.add_theme_constant_override("separation", 4)
	exp_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_hbox.add_child(exp_vbox)

	var exp_hdr := Label.new()
	exp_hdr.text = "EXPEDITIONS"
	exp_hdr.add_theme_font_size_override("font_size", 13)
	exp_hdr.add_theme_color_override("font_color", Color(0.75, 0.8, 1.0))
	exp_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	exp_vbox.add_child(exp_hdr)

	var exp_row := HBoxContainer.new()
	exp_row.add_theme_constant_override("separation", 5)
	exp_row.alignment = BoxContainer.ALIGNMENT_CENTER
	exp_vbox.add_child(exp_row)

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
					expedition_pressed.emit(idx)
		)
		slot.mouse_entered.connect(func() -> void: CursorManager.set_hover())
		slot.mouse_exited.connect(func() -> void: CursorManager.set_default())
		exp_row.add_child(slot)

func _make_slot(size: Vector2, rect: TextureRect, count_lbl: Label, highlight: ColorRect) -> Control:
	var root := Control.new()
	root.custom_minimum_size = size
	root.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.10, 0.16, 0.85)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
