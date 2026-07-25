class_name ChoicePopup
extends Control

signal choice_made(index: int)
signal skipped()
signal multiselect_confirmed(indices: Array[int])

var _prompt_label: Label = null
var _buttons_row: HBoxContainer = null
var _scroll_container: ScrollContainer = null
var _skip_btn: Button = null
var _multiselect_done_btn: Button = null
var _selected_flags: Array[bool] = []
var _max_select: int = 0
var _vbox: VBoxContainer = null
var _card_image_rect: TextureRect = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(_PANEL_CONTENT_MARGIN)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var outer_hbox: HBoxContainer = HBoxContainer.new()
	outer_hbox.add_theme_constant_override("separation", _OUTER_HBOX_SEPARATION)
	outer_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(outer_hbox)

	_card_image_rect = TextureRect.new()
	_card_image_rect.custom_minimum_size = Vector2(250, 0)
	_card_image_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_image_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card_image_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card_image_rect.visible = false
	var card_mat: ShaderMaterial = ShaderMaterial.new()
	card_mat.shader = load("res://shaders/card_rounded.gdshader") as Shader
	_card_image_rect.material = card_mat
	outer_hbox.add_child(_card_image_rect)

	_vbox = VBoxContainer.new()
	var vbox: VBoxContainer = _vbox
	vbox.add_theme_constant_override("separation", 16)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_hbox.add_child(vbox)

	_prompt_label = Label.new()
	_prompt_label.add_theme_font_size_override("font_size", 26)
	_prompt_label.add_theme_color_override("font_color", Color.WHITE)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_prompt_label)

	_scroll_container = ScrollContainer.new()
	_scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	# SHRINK_CENTER, not EXPAND_FILL: a ScrollContainer never stretches its
	# child along a scrollable axis (it needs the child's own natural size to
	# know what's scrollable), so _buttons_row always sits at this
	# container's left edge regardless of _buttons_row.alignment. Since
	# _fit_scroll_width() already sizes this container to match the row
	# (or the available width, once the row needs to actually scroll),
	# shrink-centering IT within the vbox is what actually centers the
	# button row when it's narrower than the panel.
	_scroll_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_scroll_container)

	_buttons_row = HBoxContainer.new()
	_buttons_row.add_theme_constant_override("separation", 12)
	_buttons_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_container.add_child(_buttons_row)

	var footer_row := HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 16)
	footer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(footer_row)

	_skip_btn = Button.new()
	_skip_btn.text = tr("Skip")
	_skip_btn.add_theme_font_size_override("font_size", 40)
	_skip_btn.custom_minimum_size = Vector2(200, 80)
	_skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_skip_btn.pressed.connect(func(): hide(); skipped.emit())
	_skip_btn.visible = false
	footer_row.add_child(_skip_btn)

	_multiselect_done_btn = Button.new()
	_multiselect_done_btn.text = tr("Done")
	_multiselect_done_btn.add_theme_font_size_override("font_size", 40)
	_multiselect_done_btn.custom_minimum_size = Vector2(200, 80)
	_multiselect_done_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_multiselect_done_btn.pressed.connect(_on_multiselect_done)
	_multiselect_done_btn.visible = false
	footer_row.add_child(_multiselect_done_btn)

const _PANEL_CONTENT_MARGIN: int = 24
const _OUTER_HBOX_SEPARATION: int = 20

func _fit_scroll_width() -> void:
	if not _scroll_container:
		return
	# max_w must reflect what's actually left for the button row, not the
	# raw viewport width — the panel's own content margin, and (when the
	# optional card-art rect is showing, e.g. an in-place effect's own card)
	# its reserved width plus the separation before this vbox, both eat into
	# it too. Skipping those let wide rows — any prompt offering all 6
	# supply colors, e.g. Holoprinter — overflow past the visible panel edge.
	var reserved: float = _PANEL_CONTENT_MARGIN * 2.0
	if _card_image_rect and _card_image_rect.visible:
		reserved += _card_image_rect.custom_minimum_size.x + _OUTER_HBOX_SEPARATION
	var max_w: float = get_viewport_rect().size.x - reserved
	var w: float = min(_buttons_row.get_combined_minimum_size().x, max_w)
	_scroll_container.custom_minimum_size.x = w

const _CARD_SIZE_PORTRAIT: Vector2 = Vector2(200, 280)
const _CARD_SIZE_LANDSCAPE: Vector2 = Vector2(280, 200)
# Fraction of the info-viewport reserved for the card row itself (the rest
# goes to the prompt label and footer buttons above/below it).
const _CARD_ROW_WIDTH_FRACTION := 0.90
const _CARD_ROW_HEIGHT_FRACTION := 0.62
# Approx. height of each card's name label + its separation from the image,
# subtracted from the available height before fitting the image itself.
const _CARD_LABEL_RESERVE := 24.0

func _clear_options() -> void:
	for child: Node in _buttons_row.get_children():
		child.queue_free()

func show_choices(prompt: String, option_labels: Array, skippable: bool = false, tints: Array[Color] = [], card_data: CardData = null, is_advanced: bool = false) -> void:
	_scroll_container.custom_minimum_size.x = 0
	if _vbox:
		_vbox.custom_minimum_size.x = 0
	_prompt_label.text = prompt
	_clear_options()
	for i: int in option_labels.size():
		var btn := Button.new()
		btn.text = str(option_labels[i])
		btn.add_theme_font_size_override("font_size", 22)
		btn.custom_minimum_size = Vector2(140, 56)
		if i < tints.size():
			btn.add_theme_color_override("font_color", tints[i])
		var idx: int = i
		btn.pressed.connect(func(): _on_pressed(idx))
		_buttons_row.add_child(btn)
	_skip_btn.visible = skippable
	_multiselect_done_btn.visible = false
	# Must resolve the card-art rect's visibility for THIS call before
	# _fit_scroll_width() runs — that function reserves space for it only
	# when visible, so fitting first would size the row against whatever
	# state was left over from the previous popup instead of this one.
	if _card_image_rect:
		if card_data:
			var url: String = card_data.adv_image_url if (is_advanced and not card_data.adv_image_url.is_empty()) else card_data.image_url
			_card_image_rect.texture = ImageCache.get_texture(url) if not url.is_empty() else null
			_card_image_rect.visible = _card_image_rect.texture != null
		else:
			_card_image_rect.visible = false
	_fit_scroll_width()
	show()

func show_card_choices(prompt: String, cards: Array[CardData], skippable: bool = true, advanced_flags: Array[bool] = []) -> void:
	_scroll_container.custom_minimum_size.x = 0
	if _vbox:
		_vbox.custom_minimum_size.x = 0
	_prompt_label.text = prompt
	_clear_options()
	if _card_image_rect:
		_card_image_rect.visible = false
	_build_card_rows(cards, func(idx: int, _btn: Button) -> void: _on_pressed(idx), advanced_flags)
	_skip_btn.visible = skippable
	_multiselect_done_btn.visible = false
	_fit_scroll_width()
	show()

func show_multiselect_card_choices(prompt: String, cards: Array[CardData], max_select: int = 0) -> void:
	_scroll_container.custom_minimum_size.x = 0
	if _vbox:
		_vbox.custom_minimum_size.x = 0
	_prompt_label.text = prompt
	_clear_options()
	if _card_image_rect:
		_card_image_rect.visible = false
	_max_select = max_select
	_selected_flags = []
	for _i: int in cards.size():
		_selected_flags.append(false)
	_build_card_rows(cards, func(idx: int, btn: Button) -> void: _on_multiselect_toggle(idx, btn))
	_multiselect_done_btn.visible = true
	_skip_btn.visible = false
	_fit_scroll_width()
	show()

# Floor for _card_row_grow_scale — below this, cards fall back on the scroll
# container instead of shrinking further into illegibility.
const _CARD_MIN_SCALE: float = 0.85

# General "N same-width items must fit within an available row" rule: any
# panel laying out a variable-count row of fixed-width items (card art,
# sector tiles, supply/color buttons, ...) should reuse this instead of
# re-deriving its own version. Returns the RAW scale needed for `count`
# items (each base_w wide, `separation` apart) to fit avail_w — callers
# combine it with their own height/aspect constraints and floor (see
# _card_row_grow_scale below for the card-art case, or supply_cost_panel.gd
# for a plain-width case) rather than this doing it for them, since what
# "too small" means differs per use.
#
# This exists because _card_row_grow_scale used to floor at 1.0 (grow only,
# never shrink): once there were enough options (~4+), the row grew past
# the visible panel with no working scrollbar (horizontal_scroll_mode was
# never explicitly set, and the width-fitting call was missing from two of
# the three code paths that populate a row), so extra choices were silently
# unreachable — e.g. Inflatable Hull's free-sector-gain choice, whose "gain
# a Liquids sector" option went missing this way despite being correctly
# computed as eligible.
static func fit_scale(count: int, base_w: float, avail_w: float, separation: float) -> float:
	var per_item_w: float = (avail_w - separation * float(max(count - 1, 0))) / float(max(count, 1))
	return per_item_w / base_w

# Grows each card image beyond its base size when there's room to spare (e.g.
# a single revealed card fills most of the available screen space), and
# shrinks it when there isn't — down to _CARD_MIN_SCALE, past which point it
# relies on the scroll container instead.
func _card_row_grow_scale(count: int, base_sz: Vector2) -> float:
	var separation: float = _buttons_row.get_theme_constant("separation")
	var vp_size: Vector2 = get_viewport_rect().size
	var avail_w: float = vp_size.x * _CARD_ROW_WIDTH_FRACTION
	var avail_h: float = vp_size.y * _CARD_ROW_HEIGHT_FRACTION - _CARD_LABEL_RESERVE
	var w_scale: float = fit_scale(count, base_sz.x, avail_w, separation)
	var h_scale: float = avail_h / base_sz.y
	return max(_CARD_MIN_SCALE, min(w_scale, h_scale))

func _build_card_rows(cards: Array[CardData], on_click: Callable, advanced_flags: Array[bool] = []) -> void:
	for i: int in cards.size():
		var cd: CardData = cards[i]
		var is_adv: bool = advanced_flags[i] if i < advanced_flags.size() else cd.card_type == CardData.CardType.SECTOR
		# Box aspect must track the card's physical shape (all sectors are
		# landscape, dust or advanced — see Card.set_card_data's landscape
		# swap), not is_adv, which only picks which face's art/name to show.
		# Using is_adv here left dust sectors in a portrait box that didn't
		# match their landscape art, letterboxing them.
		var is_landscape: bool = cd.card_type == CardData.CardType.SECTOR
		var base_sz: Vector2 = _CARD_SIZE_LANDSCAPE if is_landscape else _CARD_SIZE_PORTRAIT
		var card_sz: Vector2 = base_sz * _card_row_grow_scale(cards.size(), base_sz)
		var url: String = cd.adv_image_url if (is_adv and not cd.adv_image_url.is_empty()) else cd.image_url
		var tex: Texture2D = ImageCache.get_texture(url) if not url.is_empty() else null
		var display: String = cd.adv_name if is_adv else cd.card_name

		var card_vbox := VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 4)

		var img_btn := Button.new()
		img_btn.custom_minimum_size = card_sz
		if tex:
			img_btn.icon = tex
			img_btn.expand_icon = true
		else:
			img_btn.text = display
			img_btn.add_theme_font_size_override("font_size", 13)
		var idx: int = i
		img_btn.pressed.connect(func() -> void: on_click.call(idx, img_btn))
		img_btn.mouse_entered.connect(func() -> void: CursorManager.set_hover())
		img_btn.mouse_exited.connect(func() -> void: CursorManager.set_default())
		card_vbox.add_child(img_btn)

		var name_lbl := Label.new()
		name_lbl.text = display
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		name_lbl.custom_minimum_size = Vector2(card_sz.x, 0)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_vbox.add_child(name_lbl)

		_buttons_row.add_child(card_vbox)

func _on_multiselect_toggle(index: int, btn: Button) -> void:
	if index >= _selected_flags.size():
		return
	var currently_selected: bool = _selected_flags[index]
	if not currently_selected and _max_select > 0:
		var count: int = _selected_flags.count(true)
		if count >= _max_select:
			return
	_selected_flags[index] = not currently_selected
	btn.modulate = Color(0.5, 1.0, 0.5) if _selected_flags[index] else Color.WHITE

func _on_multiselect_done() -> void:
	var selected: Array[int] = []
	for i: int in _selected_flags.size():
		if _selected_flags[i]:
			selected.append(i)
	_selected_flags = []
	_multiselect_done_btn.visible = false
	hide()
	multiselect_confirmed.emit(selected)

func _on_pressed(index: int) -> void:
	hide()
	choice_made.emit(index)
