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
const SUPPLY_NAMES: Array[String] = ["Dust", "Metals", "Liquids", "Organix", "Electrix", "Thrust"]
const TECH_BACK_URL := "https://generationship.s3.eu-central-1.amazonaws.com/TTS/Tech/GS+Techs+44x67mm138.png"

signal cargo_move_requested(slot: SectorSlot, supplies: Dictionary, tucked_indices: Array[int])
signal cargo_cancelled

var _content_vbox: VBoxContainer = null
var _scroll_container: ScrollContainer = null
var _cargo_source_slot: SectorSlot = null
var _cargo_supply_entries: Array = []   # {color: int, spinbox: SpinBox}
var _cargo_tucked_btns: Array[Button] = []

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
	panel.add_child(outer_vbox)

	_scroll_container = ScrollContainer.new()
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer_vbox.add_child(_scroll_container)

	_content_vbox = VBoxContainer.new()
	_content_vbox.add_theme_constant_override("separation", 12)
	_content_vbox.custom_minimum_size = Vector2(460, 0)
	_scroll_container.add_child(_content_vbox)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.add_theme_font_size_override("font_size", 15)
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
	var title_str: String = "Sector"
	if slot.placed_card and slot.placed_card.card_data:
		var cd: CardData = slot.placed_card.card_data
		var is_adv: bool = bool(slot.placed_card.get("is_advanced"))
		title_str = cd.adv_name if is_adv else cd.card_name
	var title := Label.new()
	title.text = title_str
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_vbox.add_child(title)

	var has_content: bool = false

	# Stored supplies
	if _has_stored_supply(slot):
		has_content = true
		_add_section_label("Stored Supplies")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		_content_vbox.add_child(row)
		for i: int in 6:
			var count: int = slot.stored_supply.get(i, 0)
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
			lbl.add_theme_font_size_override("font_size", 18)
			lbl.add_theme_color_override("font_color", Color.WHITE)
			cell.add_child(lbl)
			row.add_child(cell)

	# Faceup tucked
	var faceup: Array = slot.tucked_cards.filter(func(t: Dictionary) -> bool: return t.get("face_up", false))
	if not faceup.is_empty():
		has_content = true
		_add_section_label("Faceup Tucked")
		_content_vbox.add_child(_make_card_row(faceup, true))

	# Facedown tucked
	var facedown: Array = slot.tucked_cards.filter(func(t: Dictionary) -> bool: return not t.get("face_up", false))
	if not facedown.is_empty():
		has_content = true
		_add_section_label("Facedown Tucked")
		_content_vbox.add_child(_make_card_row(facedown, false))

	if not has_content:
		_add_empty_state("Nothing stored here")

	_fit_scroll_height()

func _fit_scroll_height() -> void:
	if not _scroll_container:
		return
	var max_h: float = get_viewport_rect().size.y * 0.75
	_scroll_container.custom_minimum_size.y = min(_content_vbox.get_combined_minimum_size().y, max_h)

func _add_section_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.8, 1.0))
	_content_vbox.add_child(lbl)

func _add_empty_state(text: String) -> void:
	var empty := Label.new()
	empty.text = text
	empty.add_theme_font_size_override("font_size", 14)
	empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_vbox.add_child(empty)

func _has_stored_supply(slot: SectorSlot) -> bool:
	for count: int in slot.stored_supply.values():
		if count > 0:
			return true
	return false

const CARDS_PER_ROW := 8

func _make_card_row(cards: Array, face_up: bool) -> VBoxContainer:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)

	var row: HBoxContainer = null
	for idx: int in cards.size():
		if idx % CARDS_PER_ROW == 0:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			outer.add_child(row)

		var tuck: Dictionary = cards[idx]
		var cd: CardData = tuck.get("data") as CardData
		var url: String = (cd.image_url if cd else "") if face_up else TECH_BACK_URL
		var tex: ImageTexture = ImageCache.get_texture(url) if not url.is_empty() else null

		var card_vbox := VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 4)

		var img := TextureRect.new()
		img.custom_minimum_size = Vector2(130, 183)
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		if tex:
			img.texture = tex
		else:
			img.modulate = Color(0.12, 0.18, 0.32) if not face_up else Color(0.92, 0.87, 0.76)
		card_vbox.add_child(img)

		if face_up and cd:
			var name_lbl := Label.new()
			name_lbl.text = cd.card_name
			name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_lbl.add_theme_font_size_override("font_size", 13)
			name_lbl.add_theme_color_override("font_color", Color.WHITE)
			name_lbl.custom_minimum_size = Vector2(130, 0)
			name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			card_vbox.add_child(name_lbl)

		row.add_child(card_vbox)
	return outer

# ── Cargo Drones mode ────────────────────────────────────────────────────────

func show_sector_for_cargo(slot: SectorSlot) -> void:
	_cargo_source_slot = slot
	_rebuild_cargo(slot)
	show()

func _rebuild_cargo(slot: SectorSlot) -> void:
	_scroll_container.custom_minimum_size.y = 0
	for child: Node in _content_vbox.get_children():
		child.queue_free()
	_cargo_supply_entries.clear()
	_cargo_tucked_btns.clear()

	var title_str: String = "Move from: "
	if slot.placed_card and slot.placed_card.card_data:
		var cd: CardData = slot.placed_card.card_data
		var is_adv: bool = bool(slot.placed_card.get("is_advanced"))
		title_str += cd.adv_name if is_adv else cd.card_name
	else:
		title_str += "Sector"
	var title := Label.new()
	title.text = title_str
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_vbox.add_child(title)

	var has_content: bool = false

	# Supplies with SpinBoxes
	if _has_stored_supply(slot):
		has_content = true
		_add_section_label("Move Supplies")
		for i: int in 6:
			var count: int = slot.stored_supply.get(i, 0)
			if count == 0:
				continue
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var name_lbl := Label.new()
			name_lbl.text = SUPPLY_NAMES[i]
			name_lbl.add_theme_font_size_override("font_size", 14)
			name_lbl.add_theme_color_override("font_color", Color.WHITE)
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_lbl)
			var avail_lbl := Label.new()
			avail_lbl.text = "(of %d)" % count
			avail_lbl.add_theme_font_size_override("font_size", 13)
			avail_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			row.add_child(avail_lbl)
			var spinbox := SpinBox.new()
			spinbox.min_value = 0
			spinbox.max_value = count
			spinbox.value = 0
			spinbox.step = 1
			spinbox.custom_minimum_size = Vector2(90, 0)
			row.add_child(spinbox)
			_content_vbox.add_child(row)
			_cargo_supply_entries.append({color = i, spinbox = spinbox})

	# Tucked cards with toggle buttons
	if not slot.tucked_cards.is_empty():
		has_content = true
		_add_section_label("Move Tucked Cards")
		for i: int in slot.tucked_cards.size():
			var entry: Dictionary = slot.tucked_cards[i]
			var cd: CardData = entry.get("data") as CardData
			var face_up: bool = entry.get("face_up", false)
			var url: String = (cd.image_url if cd else "") if face_up else TECH_BACK_URL
			var tex: ImageTexture = ImageCache.get_texture(url) if not url.is_empty() else null

			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var img := TextureRect.new()
			img.custom_minimum_size = Vector2(70, 98)
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			if tex:
				img.texture = tex
			else:
				img.modulate = Color(0.12, 0.18, 0.32) if not face_up else Color(0.92, 0.87, 0.76)
			row.add_child(img)
			var name_lbl := Label.new()
			name_lbl.text = (cd.card_name if cd else "?") if face_up else "Facedown"
			name_lbl.add_theme_font_size_override("font_size", 13)
			name_lbl.add_theme_color_override("font_color", Color.WHITE)
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			row.add_child(name_lbl)
			var btn := Button.new()
			btn.text = "Move"
			btn.toggle_mode = true
			btn.toggled.connect(func(on: bool) -> void:
				btn.modulate = Color(0.4, 1.0, 0.5) if on else Color.WHITE
			)
			row.add_child(btn)
			_content_vbox.add_child(row)
			_cargo_tucked_btns.append(btn)

	if not has_content:
		_add_empty_state("Nothing to move here")

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var move_btn := Button.new()
	move_btn.text = "Move to Sector →"
	move_btn.add_theme_font_size_override("font_size", 15)
	move_btn.pressed.connect(_on_cargo_move_pressed)
	btn_row.add_child(move_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.add_theme_font_size_override("font_size", 15)
	cancel_btn.pressed.connect(func() -> void: hide(); cargo_cancelled.emit())
	btn_row.add_child(cancel_btn)
	_content_vbox.add_child(btn_row)
	_fit_scroll_height()

func _on_cargo_move_pressed() -> void:
	var supplies: Dictionary = {}
	for e: Dictionary in _cargo_supply_entries:
		var amount: int = int((e.spinbox as SpinBox).value)
		if amount > 0:
			supplies[e.color] = amount
	var tucked_indices: Array[int] = []
	for i: int in _cargo_tucked_btns.size():
		if _cargo_tucked_btns[i].button_pressed:
			tucked_indices.append(i)
	hide()
	cargo_move_requested.emit(_cargo_source_slot, supplies, tucked_indices)
