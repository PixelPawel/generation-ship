extends Control
class_name SectorPickerPanel

signal sector_selected(slot: SectorSlot)

const SECTOR_W_H_RATIO := 88.0 / 63.0
const TITLE_H := 52.0
const PADDING := 16.0
const GAP := 12.0

var _title_label: Label = null
var _card_container: Control = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	_title_label.position = Vector2(0.0, 10.0)
	_title_label.size = Vector2(1200.0, TITLE_H)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_label)

	_card_container = Control.new()
	_card_container.position = Vector2(0.0, TITLE_H + 10.0)
	_card_container.size = Vector2(1200.0, 572.0 - TITLE_H - 10.0)
	_card_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card_container)

func setup(title: String, all_slots: Array[SectorSlot], exclude: SectorSlot = null) -> void:
	_title_label.text = title
	for child: Node in _card_container.get_children():
		child.queue_free()

	var slots: Array[SectorSlot] = []
	for slot: SectorSlot in all_slots:
		if slot.occupied and slot != exclude:
			slots.append(slot)

	if not slots.is_empty():
		_build_cards(slots)
	show()

func _build_cards(slots: Array[SectorSlot]) -> void:
	var n: int = slots.size()
	var avail_w: float = 1200.0 - PADDING * 2.0 - GAP * float(n - 1)
	var avail_h: float = 572.0 - TITLE_H - 28.0

	var card_w: float = avail_w / float(n)
	var card_h: float = card_w / SECTOR_W_H_RATIO
	if card_h > avail_h:
		card_h = avail_h
		card_w = card_h * SECTOR_W_H_RATIO

	var total_w: float = card_w * float(n) + GAP * float(n - 1)
	var start_x: float = (1200.0 - total_w) / 2.0
	var start_y: float = (avail_h - card_h) / 2.0

	for i: int in n:
		var x: float = start_x + float(i) * (card_w + GAP)
		var y: float = start_y
		_build_card_btn(slots[i], Vector2(x, y), Vector2(card_w, card_h))

func _build_card_btn(slot: SectorSlot, pos: Vector2, sz: Vector2) -> void:
	var btn := Button.new()
	btn.position = pos
	btn.size = sz
	btn.flat = true
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(1.0, 1.0, 1.0, 0.15)
	hover_style.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", hover_style)
	_card_container.add_child(btn)

	var rect := TextureRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(rect)

	var lbl := Label.new()
	lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	lbl.offset_top = -38.0
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)

	if slot.placed_card and slot.placed_card.card_data:
		var cd: CardData = slot.placed_card.card_data as CardData
		var is_adv: bool = bool(slot.placed_card.get("is_advanced"))
		var url: String = cd.adv_image_url if is_adv else cd.image_url
		var card_name: String = (cd.adv_name if (is_adv and not cd.adv_name.is_empty()) else cd.card_name)
		lbl.text = card_name
		if not url.is_empty():
			rect.texture = ImageCache.get_texture(url)

	var captured: SectorSlot = slot
	btn.pressed.connect(func() -> void: sector_selected.emit(captured))
