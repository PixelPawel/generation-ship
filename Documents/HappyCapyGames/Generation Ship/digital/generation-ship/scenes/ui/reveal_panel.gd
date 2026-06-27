class_name RevealPanel
extends Control

signal slot_chosen(slot_idx: int)
signal skipped

const CARD_W_H_RATIO := 63.0 / 88.0  # portrait cards
const TITLE_H := 60.0
const SKIP_BTN_H := 80.0
const PADDING := 24.0
const GAP := 16.0
const LABEL_H := 32.0

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
	_card_container.size = Vector2(1200.0, 572.0 - TITLE_H - 10.0 - SKIP_BTN_H)
	_card_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card_container)

	var skip_btn: Button = Button.new()
	skip_btn.text = "Skip"
	skip_btn.add_theme_font_size_override("font_size", 26)
	skip_btn.custom_minimum_size = Vector2(200, 56)
	skip_btn.anchor_left = 0.5
	skip_btn.anchor_right = 0.5
	skip_btn.anchor_top = 1.0
	skip_btn.anchor_bottom = 1.0
	skip_btn.offset_left = -100.0
	skip_btn.offset_right = 100.0
	skip_btn.offset_top = -SKIP_BTN_H + 12.0
	skip_btn.offset_bottom = -12.0
	skip_btn.pressed.connect(func() -> void: hide(); skipped.emit())
	add_child(skip_btn)

func show_sector_reveal(slot_counts: Array[int], slot_cards: Array[CardData] = []) -> void:
	_title_label.text = "Reveal a Sector — choose a slot"
	_build_slots(slot_counts, slot_cards, true)
	show()

func show_expedition_reveal(slot_cards: Array[CardData], slot_counts: Array[int]) -> void:
	_title_label.text = "Add an Expedition Card — choose a slot"
	_build_slots(slot_counts, slot_cards, false)
	show()

func _build_slots(counts: Array[int], cards: Array[CardData], face_down: bool) -> void:
	for child: Node in _card_container.get_children():
		child.queue_free()

	var avail_w: float = 1200.0 - PADDING * 2.0 - GAP * 2.0
	var avail_h: float = _card_container.size.y - LABEL_H - 8.0

	var card_w: float = avail_w / 3.0
	var card_h: float = card_w / CARD_W_H_RATIO
	if card_h > avail_h:
		card_h = avail_h
		card_w = card_h * CARD_W_H_RATIO

	var total_w: float = card_w * 3.0 + GAP * 2.0
	var start_x: float = (1200.0 - total_w) / 2.0
	var start_y: float = (_card_container.size.y - LABEL_H - card_h) / 2.0

	for i: int in 3:
		var count: int = counts[i] if i < counts.size() else 0
		var cd: CardData = cards[i] if i < cards.size() else null
		var x: float = start_x + float(i) * (card_w + GAP)
		_build_slot_btn(i, Vector2(x, start_y), Vector2(card_w, card_h), count, cd, face_down)

func _build_slot_btn(slot_idx: int, pos: Vector2, sz: Vector2, count: int, cd: CardData, face_down: bool) -> void:
	var empty: bool = face_down and count == 0

	var btn: Button = Button.new()
	btn.position = pos
	btn.size = sz
	btn.flat = true
	btn.disabled = empty
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var hover_style: StyleBoxFlat = StyleBoxFlat.new()
	hover_style.bg_color = Color(1.0, 1.0, 1.0, 0.15)
	hover_style.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", hover_style)
	_card_container.add_child(btn)

	if cd != null and not cd.image_url.is_empty():
		var rect: TextureRect = TextureRect.new()
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.texture = ImageCache.get_texture(cd.image_url)
		btn.add_child(rect)
	else:
		var outline: Panel = Panel.new()
		outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		style.set_border_width_all(2)
		style.border_color = Color(0.6, 0.65, 0.75, 0.45)
		style.set_corner_radius_all(8)
		outline.add_theme_stylebox_override("panel", style)
		if empty:
			outline.modulate = Color(1.0, 1.0, 1.0, 0.4)
		btn.add_child(outline)

	var sub_lbl: Label = Label.new()
	sub_lbl.position = Vector2(pos.x, pos.y + sz.y + 4.0)
	sub_lbl.size = Vector2(sz.x, LABEL_H)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 18)
	sub_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.8) if not empty else Color(0.5, 0.5, 0.5, 0.8))
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if face_down:
		sub_lbl.text = "%d card(s)" % count if not empty else "Empty"
	else:
		sub_lbl.text = "%d stacked" % count if count > 0 else "Empty slot"
	_card_container.add_child(sub_lbl)

	var captured: int = slot_idx
	btn.pressed.connect(func() -> void: hide(); slot_chosen.emit(captured))
