class_name SupplyCostPanel
extends Control

signal supply_chosen(color: CardData.SupplyColor)
signal cancelled

var _title: Label
var _hint: Label
var _buttons_row: HBoxContainer
var _scroll: ScrollContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(20)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   0)
	margin.add_theme_constant_override("margin_right",  0)
	margin.add_theme_constant_override("margin_top",    0)
	margin.add_theme_constant_override("margin_bottom", 0)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(_title)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(_hint)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# SHRINK_CENTER, not EXPAND_FILL: a ScrollContainer never stretches its
	# child along a scrollable axis, so _buttons_row's own alignment=CENTER
	# had no extra space to center within — see show_cost(), which sizes
	# this container to match the row (or the available width, once the
	# row needs to actually scroll) so shrink-centering it actually centers
	# the button row. Same fix as ChoicePopup's own button row.
	_scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_scroll)

	_buttons_row = HBoxContainer.new()
	_buttons_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons_row.add_theme_constant_override("separation", 16)
	_scroll.add_child(_buttons_row)

	var cancel_btn := Button.new()
	cancel_btn.text = tr("Cancel")
	cancel_btn.add_theme_font_size_override("font_size", 22)
	cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel_btn.pressed.connect(func() -> void: hide(); cancelled.emit())
	vbox.add_child(cancel_btn)

const _BASE_BTN_SIZE: Vector2 = Vector2(200, 64)
const _MIN_BTN_SCALE: float = 0.5

func show_cost(card_name: String, cost: int, affordable: Array) -> void:
	_title.text = card_name
	_hint.text = tr("Choose supply to pay %d:") % cost
	for child: Node in _buttons_row.get_children():
		child.queue_free()
	# Shrinks buttons to fit rather than letting the row silently overflow
	# past the panel once affordable.size() gets large (valid_payment_colors
	# can return all 6 colors) — see ChoicePopup.fit_scale for why. Only
	# ever shrinks (min 1.0), since this panel's buttons were sized for a
	# fixed look at the common low-count case, not designed to grow.
	var avail_w: float = get_viewport_rect().size.x * 0.85
	var btn_scale: float = clampf(
		ChoicePopup.fit_scale(affordable.size(), _BASE_BTN_SIZE.x, avail_w, 16.0), _MIN_BTN_SCALE, 1.0)
	var btn_size: Vector2 = Vector2(_BASE_BTN_SIZE.x * btn_scale, _BASE_BTN_SIZE.y)
	for color: Variant in affordable:
		_buttons_row.add_child(_make_btn(color as CardData.SupplyColor, cost, btn_size, btn_scale))
	_scroll.custom_minimum_size.x = min(_buttons_row.get_combined_minimum_size().x, avail_w)
	show()

func _make_btn(color: CardData.SupplyColor, cost: int, btn_size: Vector2, btn_scale: float) -> Button:
	var btn := Button.new()
	btn.text = tr("%s ×%d") % [CardData.color_name(color), cost]
	btn.add_theme_font_size_override("font_size", clampi(roundi(26.0 * btn_scale), 14, 26))
	btn.add_theme_color_override("font_color", CardData.color_tint(color))
	btn.custom_minimum_size = btn_size
	btn.pressed.connect(func() -> void:
		supply_chosen.emit(color)
		hide()
	)
	return btn
