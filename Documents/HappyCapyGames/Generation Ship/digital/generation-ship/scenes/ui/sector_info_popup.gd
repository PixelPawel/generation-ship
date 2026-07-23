class_name SectorInfoPopup
extends Control

const SUPPLY_ICON_PATHS: Array[String] = [
	"res://assets/ui/supply/Dust.png",
	"res://assets/ui/supply/Metals.png",
	"res://assets/ui/supply/Liquids.png",
	"res://assets/ui/supply/Organix.png",
	"res://assets/ui/supply/Electrix.png",
	"res://assets/ui/supply/Thrust.png",
]
const TECH_BACK_PATH := "res://assets/cards/tech/GS_Techs_Back_44x67mm.png"

var _content_vbox: VBoxContainer = null
var _scroll_container: ScrollContainer = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(24)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 16)
	outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(outer_vbox)

	_scroll_container = ScrollContainer.new()
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(_scroll_container)

	_content_vbox = VBoxContainer.new()
	_content_vbox.add_theme_constant_override("separation", 12)
	_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_container.add_child(_content_vbox)

	var close_btn := Button.new()
	close_btn.text = tr("Close")
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(func(): hide())
	outer_vbox.add_child(close_btn)

func show_sector(slot: SectorSlot) -> void:
	_rebuild(slot)
	show()

func _rebuild(slot: SectorSlot) -> void:
	_scroll_container.custom_minimum_size.y = 0
	for child: Node in _content_vbox.get_children():
		child.queue_free()

	# Title
	var title_str: String = tr("Sector")
	if slot.placed_card and slot.placed_card.card_data:
		var cd: CardData = slot.placed_card.card_data
		var is_adv: bool = bool(slot.placed_card.get("is_advanced"))
		title_str = cd.adv_name if is_adv else cd.card_name
	var title := Label.new()
	title.text = title_str
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_vbox.add_child(title)

	var has_content: bool = append_supply_and_tucked_sections(
		_content_vbox, get_viewport_rect().size, slot.stored_supply, slot.tucked_cards)

	if not has_content:
		_add_empty_state(tr("Nothing stored here"))

	_fit_scroll_height()

# Appends "Stored Supplies"/"Faceup Tucked"/"Facedown Tucked" sections (each
# only if non-empty) to any container — shared with OpponentBoardView, which
# has no live SectorSlot to read, only a network snapshot's plain dictionaries
# in the same shape. Returns whether anything was actually appended.
static func append_supply_and_tucked_sections(container: Node, viewport_size: Vector2, stored_supply: Dictionary, tucked_cards: Array) -> bool:
	var has_content: bool = false

	if has_stored_supply(stored_supply):
		has_content = true
		container.add_child(make_section_label(TranslationServer.translate("Stored Supplies")))
		container.add_child(make_supply_row(stored_supply))

	var faceup: Array = tucked_cards.filter(func(t: Dictionary) -> bool: return t.get("face_up", false))
	if not faceup.is_empty():
		has_content = true
		container.add_child(make_section_label(TranslationServer.translate("Faceup Tucked")))
		container.add_child(make_card_row(faceup, true, viewport_size))

	var facedown: Array = tucked_cards.filter(func(t: Dictionary) -> bool: return not t.get("face_up", false))
	if not facedown.is_empty():
		has_content = true
		container.add_child(make_section_label(TranslationServer.translate("Facedown Tucked")))
		container.add_child(make_card_row(facedown, false, viewport_size))

	return has_content

static func has_stored_supply(stored_supply: Dictionary) -> bool:
	for count: int in stored_supply.values():
		if count > 0:
			return true
	return false

static func make_supply_row(stored_supply: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i: int in 6:
		var count: int = stored_supply.get(i, 0)
		if count <= 0:
			continue
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		var icon := TextureRect.new()
		icon.texture = load(SUPPLY_ICON_PATHS[i])
		icon.custom_minimum_size = Vector2(34, 34)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.add_child(icon)
		var lbl := Label.new()
		lbl.text = str(count)
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		cell.add_child(lbl)
		row.add_child(cell)
	return row

static func make_section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.8, 1.0))
	return lbl

func _fit_scroll_height() -> void:
	if not _scroll_container:
		return
	var max_h: float = get_viewport_rect().size.y * 0.75
	_scroll_container.custom_minimum_size.y = min(_content_vbox.get_combined_minimum_size().y, max_h)

func _add_empty_state(text: String) -> void:
	var empty := Label.new()
	empty.text = text
	empty.add_theme_font_size_override("font_size", 18)
	empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_vbox.add_child(empty)

static func make_card_row(cards: Array, face_up: bool, viewport_size: Vector2) -> Control:
	# Fixed card size — same as if there were exactly one card
	var vp: Vector2 = viewport_size
	var avail_w: float = vp.x - 48.0
	var card_w: float = avail_w
	var card_h: float = card_w * (183.0 / 130.0)
	var max_card_h: float = vp.y * 0.60
	if card_h > max_card_h:
		card_h = max_card_h
		card_w = card_h * (130.0 / 183.0)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)

	var hscroll := ScrollContainer.new()
	hscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hscroll.custom_minimum_size = Vector2(0, card_h + 16)
	outer.add_child(hscroll)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	# Must NOT expand — expansion distributes width equally among children, shrinking cards
	hbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hscroll.add_child(hbox)

	for idx: int in cards.size():
		var tuck: Dictionary = cards[idx]
		var cd: CardData = tuck.get("data") as CardData
		var url: String = (cd.image_url if cd else "") if face_up else TECH_BACK_PATH
		var tex: Texture2D = ImageCache.get_texture(url) if not url.is_empty() else null

		var card_vbox := VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 4)
		card_vbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

		var img := TextureRect.new()
		img.custom_minimum_size = Vector2(card_w, card_h)
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		var sip_mat: ShaderMaterial = ShaderMaterial.new()
		sip_mat.shader = load("res://shaders/card_rounded.gdshader")
		img.material = sip_mat
		if tex:
			img.texture = tex
		else:
			img.modulate = Color(0.12, 0.18, 0.32) if not face_up else Color(0.92, 0.87, 0.76)
		card_vbox.add_child(img)

		if face_up and cd:
			var name_lbl := Label.new()
			name_lbl.text = cd.card_name
			name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_lbl.add_theme_font_size_override("font_size", 16)
			name_lbl.add_theme_color_override("font_color", Color.WHITE)
			name_lbl.custom_minimum_size = Vector2(card_w, 0)
			name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			card_vbox.add_child(name_lbl)

		hbox.add_child(card_vbox)

	# Apply glowy blue scrollbar once the node is in the tree
	hscroll.ready.connect(func() -> void: style_blue_scrollbar(hscroll))
	return outer

static func style_blue_scrollbar(scroll: ScrollContainer) -> void:
	var hsb: HScrollBar = scroll.get_h_scroll_bar()
	if not hsb:
		return
	hsb.custom_minimum_size = Vector2(0, 12)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.04, 0.08, 0.20, 0.75)
	track.set_corner_radius_all(6)
	track.content_margin_top = 2.0
	track.content_margin_bottom = 2.0

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(0.18, 0.55, 1.0, 0.9)
	grabber.set_corner_radius_all(6)
	grabber.shadow_color = Color(0.18, 0.55, 1.0, 0.55)
	grabber.shadow_size = 6
	grabber.shadow_offset = Vector2.ZERO

	var grabber_hl := StyleBoxFlat.new()
	grabber_hl.bg_color = Color(0.38, 0.72, 1.0, 1.0)
	grabber_hl.set_corner_radius_all(6)
	grabber_hl.shadow_color = Color(0.38, 0.72, 1.0, 0.75)
	grabber_hl.shadow_size = 9
	grabber_hl.shadow_offset = Vector2.ZERO

	hsb.add_theme_stylebox_override("scroll", track)
	hsb.add_theme_stylebox_override("grabber", grabber)
	hsb.add_theme_stylebox_override("grabber_highlight", grabber_hl)
	hsb.add_theme_stylebox_override("grabber_pressed", grabber_hl)
