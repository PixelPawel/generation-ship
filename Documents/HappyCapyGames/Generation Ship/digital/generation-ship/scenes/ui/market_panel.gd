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

var _opp_vbox: VBoxContainer = null
var _opp_refs: Dictionary = {}

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

func add_opponent(peer_id: int, player_name: String) -> void:
	if _opp_refs.has(peer_id) or not _opp_vbox:
		return

	var pid: int = peer_id

	var entry: PanelContainer = PanelContainer.new()
	entry.mouse_filter = Control.MOUSE_FILTER_STOP
	entry.size_flags_vertical = Control.SIZE_EXPAND_FILL
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var entry_style: StyleBoxFlat = StyleBoxFlat.new()
	entry_style.bg_color = Color(0.05, 0.07, 0.15, 0.80)
	entry_style.border_color = Color(0.22, 0.44, 0.70, 0.38)
	entry_style.set_border_width_all(1)
	entry_style.set_corner_radius_all(4)
	entry_style.content_margin_left = 6.0
	entry_style.content_margin_right = 6.0
	entry_style.content_margin_top = 5.0
	entry_style.content_margin_bottom = 5.0
	entry.add_theme_stylebox_override("panel", entry_style)
	entry.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			opponent_pressed.emit(pid)
		entry.accept_event()
	)
	entry.mouse_entered.connect(func() -> void: CursorManager.set_hover())
	entry.mouse_exited.connect(func() -> void: CursorManager.set_default())
	_opp_vbox.add_child(entry)

	var entry_vbox: VBoxContainer = VBoxContainer.new()
	entry_vbox.add_theme_constant_override("separation", 3)
	entry_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(entry_vbox)

	var row1: HBoxContainer = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 4)
	row1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry_vbox.add_child(row1)

	var name_lbl: Label = Label.new()
	name_lbl.text = player_name
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row1.add_child(name_lbl)

	var hand_lbl: Label = Label.new()
	hand_lbl.text = "♠ 0"
	hand_lbl.add_theme_font_size_override("font_size", 12)
	hand_lbl.add_theme_color_override("font_color", Color(0.70, 0.82, 1.0))
	hand_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row1.add_child(hand_lbl)

	var row2: HBoxContainer = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 2)
	row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry_vbox.add_child(row2)

	var supply_lbls: Array = []
	for si: int in 6:
		var col: VBoxContainer = VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row2.add_child(col)

		var icon: TextureRect = TextureRect.new()
		icon.texture = load(_SUPPLY_PATHS[si]) as Texture2D
		icon.custom_minimum_size = Vector2(18.0, 18.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(icon)

		var s_lbl: Label = Label.new()
		s_lbl.text = "0"
		s_lbl.add_theme_font_size_override("font_size", 10)
		s_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.90))
		s_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(s_lbl)
		supply_lbls.append(s_lbl)

	var row3: HBoxContainer = HBoxContainer.new()
	row3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry_vbox.add_child(row3)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row3.add_child(spacer)

	var vp_lbl: Label = Label.new()
	vp_lbl.text = "⭐ 0"
	vp_lbl.add_theme_font_size_override("font_size", 11)
	vp_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	vp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row3.add_child(vp_lbl)

	_opp_refs[peer_id] = {
		"hand_lbl": hand_lbl,
		"supply_lbls": supply_lbls,
		"vp_lbl": vp_lbl,
	}

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
					sector_dust_pressed.emit(idx)
		)
		slot.mouse_entered.connect(func() -> void: CursorManager.set_hover())
		slot.mouse_exited.connect(func() -> void: CursorManager.set_default())
		basic_vbox.add_child(slot)

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
					sector_advanced_pressed.emit(idx)
		)
		slot.mouse_entered.connect(func() -> void: CursorManager.set_hover())
		slot.mouse_exited.connect(func() -> void: CursorManager.set_default())
		adv_vbox.add_child(slot)

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
					expedition_pressed.emit(idx)
		)
		slot.mouse_entered.connect(func() -> void: CursorManager.set_hover())
		slot.mouse_exited.connect(func() -> void: CursorManager.set_default())
		exp_vbox.add_child(slot)

	# ── Column 4: Players ──────────────────────────────────────────────────────
	var vsep3 := VSeparator.new()
	vsep3.modulate = Color(0.4, 0.4, 0.5, 0.6)
	main_hbox.add_child(vsep3)

	var players_vbox := VBoxContainer.new()
	players_vbox.add_theme_constant_override("separation", 4)
	players_vbox.custom_minimum_size = Vector2(268.0, 0.0)
	players_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(players_vbox)

	_opp_vbox = VBoxContainer.new()
	_opp_vbox.add_theme_constant_override("separation", 4)
	_opp_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	players_vbox.add_child(_opp_vbox)

func _make_slot(size: Vector2, rect: TextureRect, count_lbl: Label, highlight: ColorRect) -> Control:
	var root := Control.new()
	root.custom_minimum_size = size
	root.mouse_filter = Control.MOUSE_FILTER_STOP

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
