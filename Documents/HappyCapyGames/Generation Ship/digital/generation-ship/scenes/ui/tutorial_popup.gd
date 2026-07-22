extends Control

# "How to Play" onboarding — a short, guided companion to the full Rule
# Book (manual_popup.gd). Same paginated-popup skeleton as manual_popup,
# but each page is built live from a title + bullet list + a small diagram
# assembled from pieces already used elsewhere in the game (supply icons,
# card-rounded placeholders) instead of a static page image.

signal closed

const PAGE_COUNT: int = 5

const PANELS: Array[Dictionary] = [
	{
		title = "The Ship & Sectors",
		bullets = [
			"Your ship has up to 6 Sector slots.",
			"Dust Sectors are bought outright from the market; Advanced Sectors and Expeditions are won at auction.",
			"Each Sector holds up to 5 Tech cards.",
			"Every card belongs to one of 6 supply colors.",
		],
	},
	{
		title = "Your Hand & Research",
		bullets = [
			"Your hand is made of Tech cards, drawn blind from one shared deck.",
			"Play a Tech card onto an open slot on one of your Sectors by paying its cost.",
			"Nothing useful? Research: discard 1 card, then draw a fresh one.",
			"The deck reshuffles from the discard pile automatically if it ever runs dry.",
		],
	},
	{
		title = "Supplies & Fusing",
		bullets = [
			"Passing generates supply in 6 colors from your sectors.",
			"Fuse 2 of one supply into 1 of the next, along either of two chains.",
			"Fusing is a free action — do it any time, as often as you can.",
			"Supply stored on a sector is worth 1★ each at game end.",
		],
	},
	{
		title = "Buying, Bidding & Actions",
		bullets = [
			"The market always shows 3 Dust Sectors, 3 Advanced Sectors, and 3 Expeditions.",
			"Dust Sectors: pay the cost, place immediately.",
			"Advanced Sectors & Expeditions: won by auction — highest bidder pays and wins.",
			"You get 1 major action per turn, plus unlimited free actions.",
		],
	},
	{
		title = "Turns, Generations & Scoring",
		bullets = [
			"The game lasts 4 Generations (rounds).",
			"A Generation ends once every player has passed.",
			"Score VP from printed stars, stored supply (1★ each), and tucked cards.",
			"Highest total VP after Generation 4 wins.",
		],
	},
]

var _page: int = 1
var _title_label: Label = null
var _bullets_box: VBoxContainer = null
var _diagram_container: CenterContainer = null
var _diagram_roots: Array[Control] = []
var _page_label: Label = null

func _ready() -> void:
	_build_ui()
	_build_diagrams()
	visible = false

func open() -> void:
	_go_to(1)
	visible = true

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel: Control = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(20)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(720, 680)
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.custom_minimum_size = Vector2(680, 0)
	panel.add_child(vbox)

	# — Title bar —
	var title_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(title_row)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title_label)

	var close_btn: Button = _make_button("✕")
	close_btn.custom_minimum_size = Vector2(36, 0)
	close_btn.pressed.connect(_on_close_pressed)
	title_row.add_child(close_btn)

	var sep: HSeparator = HSeparator.new()
	sep.modulate = Color(0.4, 0.4, 0.5, 0.5)
	vbox.add_child(sep)

	# — Bullets —
	_bullets_box = VBoxContainer.new()
	_bullets_box.add_theme_constant_override("separation", 10)
	_bullets_box.custom_minimum_size = Vector2(0, 170)
	vbox.add_child(_bullets_box)

	var sep2: HSeparator = HSeparator.new()
	sep2.modulate = Color(0.4, 0.4, 0.5, 0.5)
	vbox.add_child(sep2)

	# — Diagram area —
	_diagram_container = CenterContainer.new()
	_diagram_container.custom_minimum_size = Vector2(680, 300)
	vbox.add_child(_diagram_container)

	var sep3: HSeparator = HSeparator.new()
	sep3.modulate = Color(0.4, 0.4, 0.5, 0.5)
	vbox.add_child(sep3)

	# — Navigation —
	var nav: HBoxContainer = HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 12)
	vbox.add_child(nav)

	var prev_btn: Button = _make_button("◀  Prev")
	prev_btn.pressed.connect(_on_prev)
	nav.add_child(prev_btn)

	_page_label = Label.new()
	_page_label.add_theme_font_size_override("font_size", 15)
	_page_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.custom_minimum_size = Vector2(80, 0)
	nav.add_child(_page_label)

	var next_btn: Button = _make_button("Next  ▶")
	next_btn.pressed.connect(_on_next)
	nav.add_child(next_btn)

func _build_diagrams() -> void:
	_diagram_roots.resize(PAGE_COUNT)
	_diagram_roots[0] = _build_diagram_1()
	_diagram_roots[1] = _build_diagram_2()
	_diagram_roots[2] = _build_diagram_3()
	_diagram_roots[3] = _build_diagram_4()
	_diagram_roots[4] = _build_diagram_5()
	for root: Control in _diagram_roots:
		root.visible = false
		_diagram_container.add_child(root)

func _go_to(page: int) -> void:
	_page = clampi(page, 1, PAGE_COUNT)
	var data: Dictionary = PANELS[_page - 1]
	_title_label.text = data.get("title", "") as String
	for child: Node in _bullets_box.get_children():
		child.queue_free()
	for line: String in (data.get("bullets", []) as Array):
		var lbl: Label = Label.new()
		lbl.text = "•  " + line
		lbl.add_theme_font_size_override("font_size", 17)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		_bullets_box.add_child(lbl)
	for i: int in _diagram_roots.size():
		_diagram_roots[i].visible = (i == _page - 1)
	if _page_label:
		_page_label.text = "%d / %d" % [_page, PAGE_COUNT]

func _on_prev() -> void:
	_go_to(_page - 1)

func _on_next() -> void:
	_go_to(_page + 1)

func _on_close_pressed() -> void:
	if not visible:
		return
	visible = false
	closed.emit()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				_on_close_pressed()
				get_viewport().set_input_as_handled()
			KEY_LEFT, KEY_A:
				_on_prev()
				get_viewport().set_input_as_handled()
			KEY_RIGHT, KEY_D:
				_on_next()
				get_viewport().set_input_as_handled()

func _make_button(label_text: String) -> Button:
	var btn: Button = Button.new()
	btn.text = label_text
	btn.add_theme_font_size_override("font_size", 14)
	GameTheme.apply_to_button(btn)
	return btn

# ── Diagram-building helpers ──────────────────────────────────────────────
# No new artwork: every "card" is a plain TextureRect rounded via the same
# shader used for face-down tucked cards elsewhere
# (scenes/ui/cargo_drones_panel.gd). That shader samples TEXTURE directly
# and writes COLOR from scratch — it never reads the incoming (pre-modulate)
# color, so a node's .modulate has no effect on the render at all. The tint
# has to be baked into the source texture itself instead.

var _solid_tex_cache: Dictionary = {}

func _get_solid_texture(color: Color) -> ImageTexture:
	var key: String = color.to_html(true)
	if not _solid_tex_cache.has(key):
		var img: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(color)
		_solid_tex_cache[key] = ImageTexture.create_from_image(img)
	return _solid_tex_cache[key] as ImageTexture

func _make_card_rect(rect_size: Vector2, color: Color) -> TextureRect:
	var img: TextureRect = TextureRect.new()
	img.custom_minimum_size = rect_size
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.texture = _get_solid_texture(color)
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://shaders/card_rounded.gdshader")
	img.material = mat
	return img

func _make_caption(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return lbl

func _make_arrow_label(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl

func _build_diagram_1() -> Control:
	var root: VBoxContainer = VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 8)

	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	root.add_child(row)

	var fill_colors: Array[Color] = [
		CardData.color_tint(CardData.SupplyColor.DUST),
		CardData.color_tint(CardData.SupplyColor.METALS),
		CardData.color_tint(CardData.SupplyColor.LIQUIDS),
	]
	for i: int in 6:
		var color: Color = fill_colors[i] if i < fill_colors.size() else Color(0.22, 0.24, 0.3, 0.4)
		row.add_child(_make_card_rect(Vector2(78, 110), color))

	root.add_child(_make_caption("Your ship — 6 Sector slots (3 built, 3 open)"))

	var tech_row: HBoxContainer = HBoxContainer.new()
	tech_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tech_row.add_theme_constant_override("separation", 5)
	for i: int in 5:
		tech_row.add_child(_make_card_rect(Vector2(24, 34), Color(0.5, 0.5, 0.55, 0.55)))
	root.add_child(tech_row)
	root.add_child(_make_caption("Up to 5 Tech cards per Sector"))
	return root

func _build_diagram_2() -> Control:
	var root: VBoxContainer = VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 14)

	var hand_row: HBoxContainer = HBoxContainer.new()
	hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_row.add_theme_constant_override("separation", 10)
	var hand_colors: Array[CardData.SupplyColor] = [
		CardData.SupplyColor.ORGANIX, CardData.SupplyColor.ELECTRIX, CardData.SupplyColor.THRUST,
	]
	for color: CardData.SupplyColor in hand_colors:
		hand_row.add_child(_make_card_rect(Vector2(60, 84), CardData.color_tint(color)))
	root.add_child(hand_row)
	root.add_child(_make_caption("Your hand"))

	var research_row: HBoxContainer = HBoxContainer.new()
	research_row.alignment = BoxContainer.ALIGNMENT_CENTER
	research_row.add_theme_constant_override("separation", 10)
	research_row.add_child(_make_card_rect(Vector2(50, 70), Color(0.35, 0.35, 0.4, 0.7)))
	research_row.add_child(_make_arrow_label("discard 1  →"))
	research_row.add_child(_make_card_rect(Vector2(50, 70), Color(0.10, 0.12, 0.28)))
	research_row.add_child(_make_arrow_label("→  draw 1"))
	research_row.add_child(_make_card_rect(Vector2(50, 70), Color(0.6, 0.85, 0.6)))
	root.add_child(research_row)
	root.add_child(_make_caption("Research: discard 1, draw a fresh card from the Tech Deck"))
	return root

func _build_diagram_3() -> Control:
	var flow: Control = load("res://scenes/ui/supply_flow.gd").new()
	flow.custom_minimum_size = Vector2(240, 300)
	var positions: Dictionary = {
		CardData.SupplyColor.DUST:     Vector2(115, 34),
		CardData.SupplyColor.LIQUIDS:  Vector2(39, 100),
		CardData.SupplyColor.METALS:   Vector2(191, 100),
		CardData.SupplyColor.ORGANIX:  Vector2(39, 202),
		CardData.SupplyColor.ELECTRIX: Vector2(191, 202),
		CardData.SupplyColor.THRUST:   Vector2(115, 259),
	}
	var icon_textures: Dictionary = {}
	for def: Dictionary in SupplyUI.SUPPLY_DEFS:
		icon_textures[def["color"]] = load(def["path"] as String)
	flow.setup(positions, SupplyUI.FUSE_MAP, icon_textures)
	for src: int in SupplyUI.FUSE_MAP:
		for dst: int in (SupplyUI.FUSE_MAP[src] as Array):
			flow.set_arrow_enabled(src, dst, true)
	for color: int in positions:
		flow.update_label(color, 2)

	var root: VBoxContainer = VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 8)
	root.add_child(flow)
	root.add_child(_make_caption("Fuse 2 → 1 along either chain (free action, any time)"))
	return root

func _build_diagram_4() -> Control:
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)

	var groups: HBoxContainer = HBoxContainer.new()
	groups.alignment = BoxContainer.ALIGNMENT_CENTER
	groups.add_theme_constant_override("separation", 36)
	root.add_child(groups)

	var buy_col: VBoxContainer = VBoxContainer.new()
	buy_col.alignment = BoxContainer.ALIGNMENT_CENTER
	buy_col.add_theme_constant_override("separation", 6)
	var buy_row: HBoxContainer = HBoxContainer.new()
	buy_row.add_theme_constant_override("separation", 8)
	for i: int in 3:
		buy_row.add_child(_make_card_rect(Vector2(56, 78), CardData.color_tint(CardData.SupplyColor.DUST)))
	buy_col.add_child(buy_row)
	buy_col.add_child(_make_caption("Dust Sectors — pay & place"))
	groups.add_child(buy_col)

	var bid_col: VBoxContainer = VBoxContainer.new()
	bid_col.alignment = BoxContainer.ALIGNMENT_CENTER
	bid_col.add_theme_constant_override("separation", 6)
	var bid_row: HBoxContainer = HBoxContainer.new()
	bid_row.add_theme_constant_override("separation", 8)
	var bid_colors: Array[CardData.SupplyColor] = [
		CardData.SupplyColor.METALS, CardData.SupplyColor.THRUST, CardData.SupplyColor.ELECTRIX,
	]
	for color: CardData.SupplyColor in bid_colors:
		bid_row.add_child(_make_card_rect(Vector2(56, 78), CardData.color_tint(color)))
	bid_col.add_child(bid_row)
	bid_col.add_child(_make_caption("Advanced Sectors & Expeditions — bid to win"))
	groups.add_child(bid_col)

	root.add_child(_make_caption("1 major action per turn, plus unlimited free actions"))
	return root

func _build_diagram_5() -> Control:
	var root: VBoxContainer = VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 16)

	var gens_row: HBoxContainer = HBoxContainer.new()
	gens_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gens_row.add_theme_constant_override("separation", 10)
	for i: int in 4:
		var pip: PanelContainer = PanelContainer.new()
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.14, 0.24)
		style.border_color = Color(0.35, 0.6, 0.95)
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.content_margin_left = 14.0
		style.content_margin_right = 14.0
		style.content_margin_top = 8.0
		style.content_margin_bottom = 8.0
		pip.add_theme_stylebox_override("panel", style)
		var lbl: Label = Label.new()
		lbl.text = "Gen %d" % (i + 1)
		lbl.add_theme_font_size_override("font_size", 15)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
		pip.add_child(lbl)
		gens_row.add_child(pip)
	root.add_child(gens_row)
	root.add_child(_make_caption("4 Generations — each ends once everyone has passed"))

	var vp_row: HBoxContainer = HBoxContainer.new()
	vp_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vp_row.add_theme_constant_override("separation", 28)
	vp_row.add_child(_make_vp_source("★", "Printed stars"))
	vp_row.add_child(_make_vp_source("◆", "Stored supply (1★ each)"))
	vp_row.add_child(_make_vp_source("▤", "Tucked cards"))
	root.add_child(vp_row)
	return root

func _make_vp_source(icon_text: String, caption: String) -> Control:
	var col: VBoxContainer = VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	var icon: Label = Label.new()
	icon.text = icon_text
	icon.add_theme_font_size_override("font_size", 30)
	icon.add_theme_color_override("font_color", Color(0.95, 0.8, 0.35))
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(icon)
	col.add_child(_make_caption(caption))
	return col
