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
var _vbox: VBoxContainer = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(24)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	_vbox = VBoxContainer.new()
	var vbox: VBoxContainer = _vbox
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	_prompt_label = Label.new()
	_prompt_label.add_theme_font_size_override("font_size", 22)
	_prompt_label.add_theme_color_override("font_color", Color.WHITE)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_prompt_label)

	_scroll_container = ScrollContainer.new()
	_scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_scroll_container)

	_buttons_row = HBoxContainer.new()
	_buttons_row.add_theme_constant_override("separation", 12)
	_buttons_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_container.add_child(_buttons_row)

	_skip_btn = Button.new()
	_skip_btn.text = "Skip"
	_skip_btn.add_theme_font_size_override("font_size", 15)
	_skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_skip_btn.pressed.connect(func(): hide(); skipped.emit())
	_skip_btn.visible = false
	vbox.add_child(_skip_btn)

	_multiselect_done_btn = Button.new()
	_multiselect_done_btn.text = "Done"
	_multiselect_done_btn.add_theme_font_size_override("font_size", 15)
	_multiselect_done_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_multiselect_done_btn.pressed.connect(_on_multiselect_done)
	_multiselect_done_btn.visible = false
	vbox.add_child(_multiselect_done_btn)

	GameTheme.add_hide_button(self, "Options", [panel], true)

func _fit_scroll_width() -> void:
	if not _scroll_container:
		return
	var max_w: float = get_viewport_rect().size.x * 0.55
	var w: float = min(_buttons_row.get_combined_minimum_size().x, max_w)
	_scroll_container.custom_minimum_size.x = w
	if _vbox and w > 0:
		_vbox.custom_minimum_size.x = w

func _clear_options() -> void:
	for child: Node in _buttons_row.get_children():
		child.queue_free()

func show_choices(prompt: String, option_labels: Array, skippable: bool = false, tints: Array[Color] = []) -> void:
	_scroll_container.custom_minimum_size.x = 0
	if _vbox:
		_vbox.custom_minimum_size.x = 0
	_prompt_label.text = prompt
	_clear_options()
	for i: int in option_labels.size():
		var btn := Button.new()
		btn.text = str(option_labels[i])
		btn.add_theme_font_size_override("font_size", 18)
		btn.custom_minimum_size = Vector2(120, 52)
		if i < tints.size():
			btn.add_theme_color_override("font_color", tints[i])
		var idx: int = i
		btn.pressed.connect(func(): _on_pressed(idx))
		_buttons_row.add_child(btn)
	_skip_btn.visible = skippable
	_fit_scroll_width()
	show()

func show_card_choices(prompt: String, cards: Array[CardData], skippable: bool = false, advanced_flags: Array[bool] = []) -> void:
	_scroll_container.custom_minimum_size.x = 0
	if _vbox:
		_vbox.custom_minimum_size.x = 0
	_prompt_label.text = prompt
	_clear_options()
	for i: int in cards.size():
		var cd: CardData = cards[i]
		var is_adv: bool = advanced_flags[i] if i < advanced_flags.size() else cd.card_type == CardData.CardType.SECTOR
		var url: String = cd.adv_image_url if (is_adv and not cd.adv_image_url.is_empty()) else cd.image_url
		var tex: ImageTexture = ImageCache.get_texture(url) if not url.is_empty() else null
		var display: String = cd.adv_name if is_adv else cd.card_name

		var card_vbox := VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 4)

		var img_btn := Button.new()
		img_btn.custom_minimum_size = Vector2(150, 218)
		if tex:
			img_btn.icon = tex
			img_btn.expand_icon = true
		else:
			img_btn.text = display
			img_btn.add_theme_font_size_override("font_size", 13)
		var idx: int = i
		img_btn.pressed.connect(func(): _on_pressed(idx))
		var card_ref: CardData = cd
		var adv_flag: bool = is_adv
		img_btn.mouse_entered.connect(func() -> void: CursorManager.set_hover())
		img_btn.mouse_exited.connect(func() -> void: CursorManager.set_default())
		card_vbox.add_child(img_btn)

		var name_lbl := Label.new()
		name_lbl.text = display
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		name_lbl.custom_minimum_size = Vector2(150, 0)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_vbox.add_child(name_lbl)

		_buttons_row.add_child(card_vbox)
	_skip_btn.visible = skippable
	_fit_scroll_width()
	show()

func show_multiselect_card_choices(prompt: String, cards: Array[CardData]) -> void:
	_scroll_container.custom_minimum_size.x = 0
	if _vbox:
		_vbox.custom_minimum_size.x = 0
	_prompt_label.text = prompt
	_clear_options()
	_selected_flags = []
	for i: int in cards.size():
		var cd: CardData = cards[i]
		var is_sector: bool = cd.card_type == CardData.CardType.SECTOR
		var url: String = cd.adv_image_url if (is_sector and not cd.adv_image_url.is_empty()) else cd.image_url
		var tex: ImageTexture = ImageCache.get_texture(url) if not url.is_empty() else null
		var display: String = cd.adv_name if is_sector else cd.card_name

		_selected_flags.append(false)

		var card_vbox := VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 4)

		var img_btn := Button.new()
		img_btn.custom_minimum_size = Vector2(150, 218)
		if tex:
			img_btn.icon = tex
			img_btn.expand_icon = true
		else:
			img_btn.text = display
			img_btn.add_theme_font_size_override("font_size", 13)
		var idx: int = i
		img_btn.pressed.connect(func(): _on_multiselect_toggle(idx, img_btn))
		var card_ref: CardData = cd
		img_btn.mouse_entered.connect(func() -> void: CursorManager.set_hover())
		img_btn.mouse_exited.connect(func() -> void: CursorManager.set_default())
		card_vbox.add_child(img_btn)

		var name_lbl := Label.new()
		name_lbl.text = display
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		name_lbl.custom_minimum_size = Vector2(150, 0)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_vbox.add_child(name_lbl)

		_buttons_row.add_child(card_vbox)
	_skip_btn.visible = false
	_multiselect_done_btn.visible = true
	_fit_scroll_width()
	show()

func _on_multiselect_toggle(index: int, btn: Button) -> void:
	if index >= _selected_flags.size():
		return
	_selected_flags[index] = not _selected_flags[index]
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
