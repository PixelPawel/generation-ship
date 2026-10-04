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
var _rows_container: GridContainer = null
var _card_image_rect: TextureRect = null
# the steppers and counts of each colour row (resized together by _fit_to_screen)
var _row_cells: Array[Control] = []

const ROW_SEPARATION: int = 12
const ROW_SEPARATION_TIGHT: int = 4
const ROW_MIN_H: float = 40.0     # never smaller than this, still a fair tap target

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

	var content_hbox := HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 20)
	content_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(content_hbox)

	_card_image_rect = TextureRect.new()
	_card_image_rect.custom_minimum_size = Vector2(600, 0)
	_card_image_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_image_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card_image_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card_image_rect.visible = false
	var _pay_mat: ShaderMaterial = ShaderMaterial.new()
	_pay_mat.shader = load("res://shaders/card_rounded.gdshader")
	_card_image_rect.material = _pay_mat
	content_hbox.add_child(_card_image_rect)

	var rows_vbox := VBoxContainer.new()
	rows_vbox.add_theme_constant_override("separation", 16)
	rows_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_child(rows_vbox)

	_rows_container = GridContainer.new()
	_rows_container.columns = 6
	_rows_container.add_theme_constant_override("h_separation", 16)
	_rows_container.add_theme_constant_override("v_separation", 12)
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
	forfeit_btn.text = tr("Cancel")
	forfeit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forfeit_btn.custom_minimum_size = Vector2(0, 56)
	forfeit_btn.add_theme_font_size_override("font_size", 24)
	forfeit_btn.pressed.connect(func() -> void: hide(); forfeited.emit())
	GameTheme.style_negative(forfeit_btn)
	btn_row.add_child(forfeit_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = tr("Pay & Place")
	_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_btn.custom_minimum_size = Vector2(0, 56)
	_confirm_btn.add_theme_font_size_override("font_size", 24)
	_confirm_btn.pressed.connect(_on_confirm)
	GameTheme.style_positive(_confirm_btn)
	btn_row.add_child(_confirm_btn)

func show_bid_payment(card_name: String, amount: int, valid_colors: Array[CardData.SupplyColor], supply_ui: Control, card_data: CardData = null, is_advanced: bool = false) -> void:
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
			var tex: Texture2D = ImageCache.get_texture(url)
			_card_image_rect.texture = tex
			_card_image_rect.visible = tex != null
		else:
			_card_image_rect.visible = false
	elif _card_image_rect:
		_card_image_rect.visible = false

	_title_label.text = tr("Pay for %s") % card_name
	_rebuild_rows()
	_update_total()
	show()
	_fit_to_screen()

# Fires on every supply change while this panel is open (fuse, recycle,
# anything else routed through SupplyUI.supply_changed — see
# main.gd:_on_supply_changed). Always re-auto-allocates from scratch with
# the same greedy, priority-order fill show_bid_payment used for the
# initial suggestion, rather than trying to preserve the previous split:
# topping up a stale allocation that's already fully funded (e.g. 2
# Metals + 2 Electrix for a cost of 4) would never reconsider it even
# after fusing into 3 Metals available, leaving the player's "best"
# option unreflected on screen.
func refresh() -> void:
	if not visible or not _supply_ui:
		return
	_colors = []
	_available.clear()
	for color: CardData.SupplyColor in _valid_colors:
		var avail: int = _supply_ui.get_supply(color)
		if avail > 0:
			_colors.append(color)
			_available[int(color)] = avail
	_allocations.clear()
	for color: CardData.SupplyColor in _colors:
		_allocations[int(color)] = 0
	var remaining: int = _needed
	for color: CardData.SupplyColor in _colors:
		if remaining <= 0:
			break
		var col_key: int = int(color)
		var take: int = mini(_available[col_key], remaining)
		_allocations[col_key] = take
		remaining -= take
	_count_labels.clear()
	_avail_labels.clear()
	_rebuild_rows()
	_update_total()
	_fit_to_screen()

func _rebuild_rows() -> void:
	for child: Node in _rows_container.get_children():
		child.queue_free()
	_count_labels.clear()
	_avail_labels.clear()
	_row_cells.clear()
	_rows_container.add_theme_constant_override("v_separation", ROW_SEPARATION)
	for color: CardData.SupplyColor in _colors:
		_add_row_cells(color)

func _add_row_cells(color: CardData.SupplyColor) -> void:
	var col_key: int = int(color)

	var icon := TextureRect.new()
	icon.texture = load(SUPPLY_ICON_PATHS[int(color)])
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rows_container.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = CardData.color_name(color)
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", CardData.color_tint(color))
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rows_container.add_child(name_lbl)

	var avail_lbl := Label.new()
	avail_lbl.text = tr("(have %d)") % _available[col_key]
	avail_lbl.add_theme_font_size_override("font_size", 20)
	avail_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	avail_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avail_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_avail_labels[col_key] = avail_lbl
	_rows_container.add_child(avail_lbl)

	var dec_btn := Button.new()
	dec_btn.text = "−"
	dec_btn.custom_minimum_size = Vector2(48, 48)
	dec_btn.add_theme_font_size_override("font_size", 26)
	dec_btn.pressed.connect(func() -> void: _change_alloc(col_key, -1))
	_rows_container.add_child(dec_btn)
	_row_cells.append(dec_btn)

	var count_lbl := Label.new()
	count_lbl.custom_minimum_size = Vector2(48, 48)
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_lbl.add_theme_font_size_override("font_size", 28)
	count_lbl.text = str(_allocations[col_key])
	_count_labels[col_key] = count_lbl
	_rows_container.add_child(count_lbl)
	_row_cells.append(count_lbl)

	var inc_btn := Button.new()
	inc_btn.text = "+"
	inc_btn.custom_minimum_size = Vector2(48, 48)
	inc_btn.add_theme_font_size_override("font_size", 26)
	inc_btn.pressed.connect(func() -> void: _change_alloc(col_key, 1))
	_rows_container.add_child(inc_btn)
	_row_cells.append(inc_btn)

# With every supply colour listed (5-6 rows), the rows plus the footer can be
# taller than the info screen — on phones especially, where every button there
# is made 1.3x taller for touch — pushing Pay/Cancel off the bottom. Once the
# layout has settled, measure how far the footer overshoots and take it out of
# the row spacing first, then the row height.
func _fit_to_screen() -> void:
	await get_tree().process_frame
	await get_tree().process_frame   # the phone's deferred button enlarging lands first
	if not is_inside_tree() or not visible or _row_cells.is_empty():
		return
	var limit: float = get_viewport_rect().size.y - 10.0
	var overflow: float = _confirm_btn.get_global_rect().end.y - limit
	if overflow <= 0.0:
		return
	var n: int = _colors.size()
	var gaps: int = maxi(n - 1, 0)
	_rows_container.add_theme_constant_override("v_separation", ROW_SEPARATION_TIGHT)
	overflow -= float((ROW_SEPARATION - ROW_SEPARATION_TIGHT) * gaps)
	if overflow <= 0.0:
		return
	var row_h: float = 0.0
	for c: Control in _row_cells:
		row_h = maxf(row_h, c.get_combined_minimum_size().y)
	var new_h: float = maxf(ROW_MIN_H, floorf(row_h - overflow / float(n)) - 1.0)
	for c: Control in _row_cells:
		c.set_meta(&"_info_enlarged", true)   # keep the phone enlarging from undoing it
		c.custom_minimum_size = Vector2(c.custom_minimum_size.x, new_h)

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
	_total_label.text = tr("Allocated: %d / %d") % [total, _needed]
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
