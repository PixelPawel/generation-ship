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
const SUB_GAP := 8.0  # gap between advanced and dust sub-cards within a sector slot

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

func show_sector_reveal(slot_counts: Array[int], adv_cards: Array[CardData] = [], dust_cards: Array[CardData] = []) -> void:
	_title_label.text = "Reveal a Sector — choose a slot"
	_build_slots(slot_counts, adv_cards, dust_cards, true)
	show()

func show_expedition_reveal(slot_cards: Array[CardData], slot_counts: Array[int]) -> void:
	_title_label.text = "Add an Expedition Card — choose a slot"
	_build_slots(slot_counts, slot_cards, [], false)
	show()

func _build_slots(counts: Array[int], cards: Array[CardData], dust_cards: Array[CardData], face_down: bool) -> void:
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
		var dust_cd: CardData = dust_cards[i] if i < dust_cards.size() else null
		var x: float = start_x + float(i) * (card_w + GAP)
		_build_slot_btn(i, Vector2(x, start_y), Vector2(card_w, card_h), count, cd, dust_cd, face_down)

func _build_slot_btn(slot_idx: int, pos: Vector2, sz: Vector2, count: int, cd: CardData, dust_cd: CardData, face_down: bool) -> void:
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
	if empty:
		btn.modulate = Color(1.0, 1.0, 1.0, 0.4)
	_card_container.add_child(btn)

	if face_down:
		# Sector slots: advanced card (left, landscape) + dust card (right, portrait face-up)
		var sub_w: float = (sz.x - SUB_GAP) / 2.0
		# Landscape h = w * (63/88); portrait h = w / (63/88) = w * (88/63)
		var adv_h: float = sub_w * CARD_W_H_RATIO
		var dust_h: float = sub_w / CARD_W_H_RATIO

		# Advanced (revealed) card — left half, centered vertically
		var adv_y: float = (sz.y - adv_h) / 2.0
		if cd != null:
			var adv_url: String = cd.adv_image_url if not cd.adv_image_url.is_empty() else cd.image_url
			if not adv_url.is_empty():
				var adv_rect: TextureRect = TextureRect.new()
				adv_rect.position = Vector2(0.0, adv_y)
				adv_rect.size = Vector2(sub_w, adv_h)
				adv_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				adv_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				adv_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				adv_rect.texture = ImageCache.get_texture(adv_url)
				btn.add_child(adv_rect)
			else:
				_add_outline(btn, Vector2(0.0, adv_y), Vector2(sub_w, adv_h))
		else:
			_add_outline(btn, Vector2(0.0, adv_y), Vector2(sub_w, adv_h))

		# Dust card — right half, centered vertically, shown face-up (portrait image_url)
		var dust_x: float = sub_w + SUB_GAP
		var dust_y: float = (sz.y - dust_h) / 2.0
		if dust_cd != null:
			var dust_url: String = dust_cd.local_art_path if not dust_cd.local_art_path.is_empty() else dust_cd.image_url
			if not dust_url.is_empty():
				var dust_rect: TextureRect = TextureRect.new()
				dust_rect.position = Vector2(dust_x, dust_y)
				dust_rect.size = Vector2(sub_w, dust_h)
				dust_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				dust_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				dust_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				dust_rect.texture = ImageCache.get_texture(dust_url)
				btn.add_child(dust_rect)
			else:
				_add_outline(btn, Vector2(dust_x, dust_y), Vector2(sub_w, dust_h))
		else:
			_add_outline(btn, Vector2(dust_x, dust_y), Vector2(sub_w, dust_h))
	else:
		# Expedition slots: single card, full slot size
		if cd != null and not cd.image_url.is_empty():
			var rect: TextureRect = TextureRect.new()
			rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rect.texture = ImageCache.get_texture(cd.image_url)
			btn.add_child(rect)
		else:
			_add_outline(btn, Vector2.ZERO, sz)

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

func _add_outline(parent: Control, pos: Vector2, sz: Vector2) -> void:
	var outline: Panel = Panel.new()
	outline.position = pos
	outline.size = sz
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.set_border_width_all(2)
	style.border_color = Color(0.6, 0.65, 0.75, 0.45)
	style.set_corner_radius_all(8)
	outline.add_theme_stylebox_override("panel", style)
	parent.add_child(outline)
