extends Control

const SUPPLY_ICON_PATHS: Array[String] = [
	"res://assets/ui/supply/Dust.png",
	"res://assets/ui/supply/Metals.png",
	"res://assets/ui/supply/Liquids.png",
	"res://assets/ui/supply/Organix.png",
	"res://assets/ui/supply/Electrix.png",
	"res://assets/ui/supply/Thrust.png",
]

signal confirmed(allocations: Dictionary)
signal forfeited

var _needed: int = 0
var _allocations: Dictionary = {}
var _available: Dictionary = {}
var _colors: Array[CardData.SupplyColor] = []
var _valid_colors: Array[CardData.SupplyColor] = []
var _supply_ui: Control = null
var _count_labels: Dictionary = {}
var _avail_labels: Dictionary = {}
var _title_label: Label = null
var _total_label: Label = null
var _confirm_btn: Button = null
var _rows_container: VBoxContainer = null
var _card_image_rect: TextureRect = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(20)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	# Outer VBox fills the ScifiPanel (same proven pattern as all other panels)
	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 12)
	panel.add_child(outer_vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 32)
	outer_vbox.add_child(_title_label)

	# Inner HBox: card on left, supply rows on right.
	# Lives inside outer_vbox so PanelContainer never touches it directly.
	var content_hbox := HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 20)
	content_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(content_hbox)

	_card_image_rect = TextureRect.new()
	_card_image_rect.custom_minimum_size = Vector2(200, 0)
	_card_image_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card_image_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_image_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card_image_rect.visible = false
	content_hbox.add_child(_card_image_rect)

	var rows_vbox := VBoxContainer.new()
	rows_vbox.add_theme_constant_override("separation", 16)
	rows_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_child(rows_vbox)

	_rows_container = VBoxContainer.new()
	_rows_container.add_theme_constant_override("separation", 10)
	_rows_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows_vbox.add_child(_rows_container)

	_total_label = Label.new()
	_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_total_label.add_theme_font_size_override("font_size", 24)
	rows_vbox.add_child(_total_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	btn_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_row.custom_minimum_size = Vector2(560, 0)
	outer_vbox.add_child(btn_row)

	var forfeit_btn := Button.new()
	forfeit_btn.text = "Forfeit"
	forfeit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forfeit_btn.custom_minimum_size = Vector2(0, 56)
	forfeit_btn.add_theme_font_size_override("font_size", 24)
	forfeit_btn.pressed.connect(func() -> void: hide(); forfeited.emit())
	btn_row.add_child(forfeit_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = "Pay & Place"
	_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_btn.custom_minimum_size = Vector2(0, 56)
	_confirm_btn.add_theme_font_size_override("font_size", 24)
	_confirm_btn.pressed.connect(_on_confirm)
	btn_row.add_child(_confirm_btn)

func show_bid_payment(card_name: String, amount: int, valid_colors: Array[CardData.SupplyColor], supply_ui: Control, card_data: CardData = null, is_advanced: bool = false, confirm_text: String = "Pay & Place") -> void:
	_needed = amount
	_supply_ui = supply_ui
	_valid_colors = valid_colors
	_allocations.clear()
	_available.clear()
	_count_labels.clear()
	_avail_labels.clear()

	_colors = []
	for color: CardData.SupplyColor in valid_colors:
		var avail: int = supply_ui.get_supply(color)
		if avail > 0:
			_colors.append(color)
			_available[int(color)] = avail
			_allocations[int(color)] = 0

	var remaining: int = amount
	for color: CardData.SupplyColor in _colors:
		var take: int = mini(_available[int(color)], remaining)
		_allocations[int(color)] = take
		remaining -= take
		if remaining <= 0:
			break

	if card_data and _card_image_rect:
		var url: String = card_data.adv_image_url if (is_advanced and not card_data.adv_image_url.is_empty()) else card_data.image_url
		if not url.is_empty():
			var tex: ImageTexture = ImageCache.get_texture(url)
			_card_image_rect.texture = tex
			_card_image_rect.visible = tex != null
		else:
			_card_image_rect.visible = false
	elif _card_image_rect:
		_card_image_rect.visible = false

	_title_label.text = "Pay for %s" % card_name
	_confirm_btn.text = confirm_text
	_rebuild_rows()
	_update_total()
	show()

func refresh() -> void:
	if not visible or not _supply_ui:
		return
	var new_colors: Array[CardData.SupplyColor] = []
	var new_available: Dictionary = {}
	for color: CardData.SupplyColor in _valid_colors:
		var avail: int = _supply_ui.get_supply(color)
		if avail > 0:
			new_colors.append(color)
			new_available[int(color)] = avail
	var colors_changed: bool = new_colors.size() != _colors.size()
	if not colors_changed:
		for i: int in new_colors.size():
			if new_colors[i] != _colors[i]:
				colors_changed = true
				break
	if colors_changed:
		var old_allocs: Dictionary = _allocations.duplicate()
		_colors = new_colors
		_available = new_available
		_allocations.clear()
		for color: CardData.SupplyColor in _colors:
			var col_key: int = int(color)
			_allocations[col_key] = mini(old_allocs.get(col_key, 0), _available.get(col_key, 0))
		var rem: int = _needed - _get_total()
		for color: CardData.SupplyColor in _colors:
			if rem <= 0:
				break
			var col_key: int = int(color)
			var can_add: int = _available.get(col_key, 0) - int(_allocations.get(col_key, 0))
			var take: int = mini(can_add, rem)
			_allocations[col_key] = int(_allocations.get(col_key, 0)) + take
			rem -= take
		_count_labels.clear()
		_avail_labels.clear()
		_rebuild_rows()
	else:
		for color: CardData.SupplyColor in _colors:
			var col_key: int = int(color)
			var avail: int = new_available[col_key]
			_available[col_key] = avail
			_allocations[col_key] = mini(int(_allocations.get(col_key, 0)), avail)
			if _avail_labels.has(col_key):
				(_avail_labels[col_key] as Label).text = "(have %d)" % avail
			if _count_labels.has(col_key):
				(_count_labels[col_key] as Label).text = str(_allocations[col_key])
		var rem: int = _needed - _get_total()
		for color: CardData.SupplyColor in _colors:
			if rem <= 0:
				break
			var col_key: int = int(color)
			var can_add: int = _available.get(col_key, 0) - int(_allocations.get(col_key, 0))
			var take: int = mini(can_add, rem)
			if take > 0:
				_allocations[col_key] = int(_allocations.get(col_key, 0)) + take
				rem -= take
				if _count_labels.has(col_key):
					(_count_labels[col_key] as Label).text = str(_allocations[col_key])
	_update_total()

func _rebuild_rows() -> void:
	for child: Node in _rows_container.get_children():
		child.queue_free()
	for color: CardData.SupplyColor in _colors:
		_rows_container.add_child(_make_row(color))

func _make_row(color: CardData.SupplyColor) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var icon := TextureRect.new()
	icon.texture = load(SUPPLY_ICON_PATHS[int(color)])
	icon.custom_minimum_size = Vector2(40, 40)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = CardData.color_name(color)
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", CardData.color_tint(color))
	name_lbl.custom_minimum_size = Vector2(120, 0)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_lbl)

	var col_key: int = int(color)
	var avail_lbl := Label.new()
	avail_lbl.text = "(have %d)" % _available[col_key]
	avail_lbl.add_theme_font_size_override("font_size", 20)
	avail_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	avail_lbl.custom_minimum_size = Vector2(110, 0)
	avail_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avail_labels[col_key] = avail_lbl
	row.add_child(avail_lbl)

	var dec_btn := Button.new()
	dec_btn.text = "−"
	dec_btn.custom_minimum_size = Vector2(48, 48)
	dec_btn.add_theme_font_size_override("font_size", 26)
	dec_btn.pressed.connect(func() -> void: _change_alloc(col_key, -1))
	row.add_child(dec_btn)

	var count_lbl := Label.new()
	count_lbl.custom_minimum_size = Vector2(48, 48)
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_lbl.add_theme_font_size_override("font_size", 28)
	count_lbl.text = str(_allocations[col_key])
	_count_labels[col_key] = count_lbl
	row.add_child(count_lbl)

	var inc_btn := Button.new()
	inc_btn.text = "+"
	inc_btn.custom_minimum_size = Vector2(48, 48)
	inc_btn.add_theme_font_size_override("font_size", 26)
	inc_btn.pressed.connect(func() -> void: _change_alloc(col_key, 1))
	row.add_child(inc_btn)

	return row

func _change_alloc(color_key: int, delta: int) -> void:
	var current: int = _allocations.get(color_key, 0)
	var new_val: int = current + delta
	new_val = clampi(new_val, 0, _available.get(color_key, 0))
	if delta > 0 and _get_total() >= _needed:
		return
	_allocations[color_key] = new_val
	if _count_labels.has(color_key):
		(_count_labels[color_key] as Label).text = str(new_val)
	_update_total()

func _get_total() -> int:
	var total: int = 0
	for v: Variant in _allocations.values():
		total += int(v)
	return total

func _update_total() -> void:
	var total: int = _get_total()
	_total_label.text = "Allocated: %d / %d" % [total, _needed]
	if total == _needed:
		_total_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	else:
		_total_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))
	_confirm_btn.disabled = total != _needed

func _on_confirm() -> void:
	var result: Dictionary = {}
	for color_key: Variant in _allocations:
		var amount: int = int(_allocations[color_key])
		if amount > 0:
			result[color_key as CardData.SupplyColor] = amount
	hide()
	confirmed.emit(result)
