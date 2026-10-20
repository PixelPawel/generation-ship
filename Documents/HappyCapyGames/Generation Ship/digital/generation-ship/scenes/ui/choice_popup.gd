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
	GameTheme.size_info_button(_skip_btn)
	_skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_skip_btn.pressed.connect(func(): hide(); skipped.emit())
	GameTheme.style_negative(_skip_btn)
	_skip_btn.visible = false
	footer_row.add_child(_skip_btn)

	_multiselect_done_btn = Button.new()
	_multiselect_done_btn.text = tr("Done")
	GameTheme.size_info_button(_multiselect_done_btn)
	_multiselect_done_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_multiselect_done_btn.pressed.connect(_on_multiselect_done)
	GameTheme.style_positive(_multiselect_done_btn)
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

# ── Measured layout ──────────────────────────────────────────────────────────
# Card rows and the color diamond are sized from the space the row actually
# gets once the prompt (which may wrap) and the footer buttons have taken
# theirs — measured a frame after showing, with the row's content kept tiny
# until then so it can't inflate the measurement. Sizing them from fixed
# fractions of the viewport instead left cards small on a roomy panel, and
# pushed the footer off the panel whenever the prompt wrapped.

var _layout_gen: int = 0

func _schedule_layout(layout: Callable) -> void:
	_layout_gen += 1
	var gen: int = _layout_gen
	await get_tree().process_frame
	if gen != _layout_gen or not visible:
		return
	layout.call(Vector2(_vbox.size.x, _scroll_container.size.y))
	_fit_scroll_width()

func _clear_options() -> void:
	_layout_gen += 1
	_card_entries.clear()
	for child: Node in _buttons_row.get_children():
		child.queue_free()

func _set_card_art(card_data: CardData, is_advanced: bool) -> void:
	if not _card_image_rect:
		return
	if card_data:
		var url: String = card_data.adv_image_url if (is_advanced and not card_data.adv_image_url.is_empty()) else card_data.image_url
		_card_image_rect.texture = ImageCache.get_texture(url) if not url.is_empty() else null
		_card_image_rect.visible = _card_image_rect.texture != null
	else:
		_card_image_rect.visible = false

func _begin(prompt: String) -> void:
	_scroll_container.custom_minimum_size.x = 0
	if _vbox:
		_vbox.custom_minimum_size.x = 0
	_prompt_label.text = prompt
	_clear_options()

func show_choices(prompt: String, option_labels: Array, skippable: bool = false, tints: Array[Color] = [], card_data: CardData = null, is_advanced: bool = false) -> void:
	_begin(prompt)
	for i: int in option_labels.size():
		var btn := Button.new()
		btn.text = str(option_labels[i])
		GameTheme.size_info_button(btn)
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
	_set_card_art(card_data, is_advanced)
	_fit_scroll_width()
	show()

# ── Supply-color choices ─────────────────────────────────────────────────────
# The control screen's supply diamond (SupplyUI.FLOW_POSITIONS), stretched to
# fill the free space: wider than tall, so each icon gets room for its label
# underneath without running into the icon below, and the icons themselves
# grow as big as the row height allows — phones need large targets. Icon and
# label together form one tap target. colors[i] is option i's SupplyColor;
# colors that aren't offered stay in place, dimmed and unclickable, so the
# diamond keeps its familiar shape.
const _COLOR_ICON_MAX: float = 150.0
const _COLOR_ICON_MIN: float = 48.0
const _COLOR_LABEL_FONT: int = 24
const _COLOR_LABEL_GAP: float = 8.0
const _COLOR_X_SPREAD_MAX: float = 3.2

var _color_choices: Array[int] = []
var _color_diamond: Control = null

func show_color_choices(prompt: String, colors: Array[int], skippable: bool = false, card_data: CardData = null, is_advanced: bool = false) -> void:
	_begin(prompt)
	_set_card_art(card_data, is_advanced)
	_color_choices = colors.duplicate()
	_color_diamond = Control.new()
	_color_diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buttons_row.add_child(_color_diamond)
	_skip_btn.visible = skippable
	_multiselect_done_btn.visible = false
	show()
	_schedule_layout(_layout_color_diamond)

func _layout_color_diamond(avail: Vector2) -> void:
	if not is_instance_valid(_color_diamond):
		return
	for child: Node in _color_diamond.get_children():
		child.queue_free()

	var font: Font = get_theme_default_font()
	var label_h: float = font.get_height(_COLOR_LABEL_FONT)
	var label_w: float = 0.0
	for def: Dictionary in SupplyUI.SUPPLY_DEFS:
		var name_w: float = font.get_string_size(CardData.color_name(int(def["color"]) as CardData.SupplyColor),
				HORIZONTAL_ALIGNMENT_LEFT, -1, _COLOR_LABEL_FONT).x
		label_w = maxf(label_w, name_w + 12.0)

	# Diamond rows (FLOW_POSITIONS y): Dust 34 | Liquids, Metals 100 |
	# Organix, Electrix 202 | Thrust 259. Within a column, the tightest
	# vertical step is Liquids -> Organix (102), which must hold an icon plus
	# its label; the whole span (225) plus one icon and label must fit avail.y.
	var pos: Dictionary = SupplyUI.FLOW_POSITIONS
	var col_step: float = (pos[CardData.SupplyColor.ORGANIX] as Vector2).y - (pos[CardData.SupplyColor.LIQUIDS] as Vector2).y
	var span: float = (pos[CardData.SupplyColor.THRUST] as Vector2).y - (pos[CardData.SupplyColor.DUST] as Vector2).y
	var fixed: float = label_h + _COLOR_LABEL_GAP
	var icon: float = (avail.y - label_h - span * fixed / col_step) / (1.0 + span / col_step)
	icon = clampf(icon, _COLOR_ICON_MIN, _COLOR_ICON_MAX)
	var sy: float = (icon + fixed) / col_step
	# Horizontally: the centre column (Dust, Thrust) and the side columns sit
	# 76 apart; spread them so neighbouring targets never touch, within avail.x.
	var cell_w: float = maxf(icon, label_w)
	var half_dx: float = (pos[CardData.SupplyColor.DUST] as Vector2).x - (pos[CardData.SupplyColor.LIQUIDS] as Vector2).x
	var sx: float = clampf((cell_w + 24.0) / half_dx, sy, _COLOR_X_SPREAD_MAX)
	sx = minf(sx, maxf((avail.x - cell_w) / (half_dx * 2.0), sy))

	var origin: Vector2 = Vector2((pos[CardData.SupplyColor.LIQUIDS] as Vector2).x, (pos[CardData.SupplyColor.DUST] as Vector2).y)
	_color_diamond.custom_minimum_size = Vector2(half_dx * 2.0 * sx + cell_w, span * sy + icon + fixed)

	for def: Dictionary in SupplyUI.SUPPLY_DEFS:
		var color: int = int(def["color"])
		var idx: int = _color_choices.find(color)
		var p: Vector2 = pos[color] as Vector2
		var center_x: float = (p.x - origin.x) * sx + cell_w * 0.5
		var top_y: float = (p.y - origin.y) * sy

		var target := Button.new()
		target.flat = true
		target.focus_mode = Control.FOCUS_NONE
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			target.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		_color_diamond.add_child(target)
		# Size/position after add_child (see SupplyUI/TextureRect sizing notes).
		target.size = Vector2(cell_w, icon + fixed)
		target.position = Vector2(center_x - cell_w * 0.5, top_y)
		target.pivot_offset = target.size * 0.5

		var img := TextureRect.new()
		img.texture = load(def["path"]) as Texture2D
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		target.add_child(img)
		img.size = Vector2(icon, icon)
		img.position = Vector2((cell_w - icon) * 0.5, 0.0)

		var lbl := Label.new()
		lbl.text = CardData.color_name(color as CardData.SupplyColor)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", _COLOR_LABEL_FONT)
		lbl.add_theme_color_override("font_color", CardData.color_tint(color as CardData.SupplyColor))
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		target.add_child(lbl)
		lbl.size = Vector2(cell_w, label_h)
		lbl.position = Vector2(0.0, icon + _COLOR_LABEL_GAP)

		if idx < 0:
			target.disabled = true
			target.modulate = Color(1, 1, 1, 0.18)
			target.mouse_filter = Control.MOUSE_FILTER_IGNORE
			continue
		target.pressed.connect(func() -> void: _on_pressed(idx))
		target.mouse_entered.connect(func() -> void:
			CursorManager.set_hover()
			target.create_tween().tween_property(target, "scale", Vector2.ONE * 1.08, 0.1)
			target.modulate = Color(1.25, 1.25, 1.25))
		target.mouse_exited.connect(func() -> void:
			CursorManager.set_default()
			target.create_tween().tween_property(target, "scale", Vector2.ONE, 0.12)
			target.modulate = Color.WHITE)

# ── Card choices ─────────────────────────────────────────────────────────────

const _CARD_ASPECT_PORTRAIT: float = 200.0 / 280.0   # width / height
const _CARD_ASPECT_LANDSCAPE: float = 280.0 / 200.0
const _CARD_NAME_FONT: int = 16
# Cards are as tall as the row allows. When they don't all fit side by side,
# they shrink to fit only while that keeps at least this fraction of the full
# height; below it they stay big and the row scrolls instead.
const _CARD_SHRINK_TO_FIT_MIN: float = 0.85

var _card_entries: Array[Dictionary] = []   # {btn: Button, lbl: Label, aspect: float}

func show_card_choices(prompt: String, cards: Array[CardData], skippable: bool = true, advanced_flags: Array[bool] = []) -> void:
	_begin(prompt)
	if _card_image_rect:
		_card_image_rect.visible = false
	_build_card_rows(cards, func(idx: int, _btn: Button) -> void: _on_pressed(idx), advanced_flags)
	_skip_btn.visible = skippable
	_multiselect_done_btn.visible = false
	show()
	_schedule_layout(_layout_cards)

func show_multiselect_card_choices(prompt: String, cards: Array[CardData], max_select: int = 0) -> void:
	_begin(prompt)
	if _card_image_rect:
		_card_image_rect.visible = false
	_max_select = max_select
	_selected_flags = []
	for _i: int in cards.size():
		_selected_flags.append(false)
	_build_card_rows(cards, func(idx: int, btn: Button) -> void: _on_multiselect_toggle(idx, btn))
	_multiselect_done_btn.visible = true
	_skip_btn.visible = false
	show()
	_schedule_layout(_layout_cards)

# General "N same-width items must fit within an available row" rule: any
# panel laying out a variable-count row of fixed-width items (sector tiles,
# supply/color buttons, ...) can reuse this instead of re-deriving its own
# version. Returns the RAW scale needed for `count` items (each base_w wide,
# `separation` apart) to fit avail_w — callers combine it with their own
# constraints and floor (see supply_cost_panel.gd), since what "too small"
# means differs per use.
static func fit_scale(count: int, base_w: float, avail_w: float, separation: float) -> float:
	var per_item_w: float = (avail_w - separation * float(max(count - 1, 0))) / float(max(count, 1))
	return per_item_w / base_w

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
		var url: String = cd.adv_image_url if (is_adv and not cd.adv_image_url.is_empty()) else cd.image_url
		var tex: Texture2D = ImageCache.get_texture(url) if not url.is_empty() else null
		var display: String = cd.adv_name if is_adv else cd.card_name

		var card_vbox := VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 4)

		# Real size comes from _layout_cards once the row has been measured;
		# kept tiny until then so it can't inflate that measurement.
		var img_btn := Button.new()
		img_btn.custom_minimum_size = Vector2(1, 1)
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
		name_lbl.add_theme_font_size_override("font_size", _CARD_NAME_FONT)
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Hidden until _layout_cards gives it a width: a word-wrapping label
		# with no width reports a huge minimum height, which would distort
		# the row measurement.
		name_lbl.visible = false
		card_vbox.add_child(name_lbl)

		_buttons_row.add_child(card_vbox)
		_card_entries.append({btn = img_btn, lbl = name_lbl, aspect = _CARD_ASPECT_LANDSCAPE if is_landscape else _CARD_ASPECT_PORTRAIT})

func _layout_cards(avail: Vector2) -> void:
	var n: int = _card_entries.size()
	if n == 0:
		return
	var sep: float = float(_buttons_row.get_theme_constant("separation"))
	var name_h: float = get_theme_default_font().get_height(_CARD_NAME_FONT) * 2.0 + 4.0   # up to 2 lines + gap
	var aspect_sum: float = 0.0
	for e: Dictionary in _card_entries:
		aspect_sum += float(e["aspect"])
	var gaps: float = sep * float(n - 1)

	var h: float = avail.y - name_h
	if h * aspect_sum + gaps > avail.x:
		var fit_h: float = (avail.x - gaps) / aspect_sum
		if fit_h >= h * _CARD_SHRINK_TO_FIT_MIN:
			h = fit_h
		else:
			var bar: float = maxf(_scroll_container.get_h_scroll_bar().get_combined_minimum_size().y, 12.0)
			h -= bar + 4.0
	h = maxf(h, 60.0)

	for e: Dictionary in _card_entries:
		var w: float = h * float(e["aspect"])
		if is_instance_valid(e["btn"]):
			(e["btn"] as Button).custom_minimum_size = Vector2(w, h)
		if is_instance_valid(e["lbl"]):
			(e["lbl"] as Label).custom_minimum_size = Vector2(w, 0)
			(e["lbl"] as Label).visible = true

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
