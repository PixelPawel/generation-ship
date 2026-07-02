extends Control

signal bid_confirmed(amount: int)
signal bid_cancelled
signal bid_raised(amount: int)
signal bid_passed

var _min_cost: int = 0
var _bid_amount: int = 0
var _auction_mode: bool = false
var _is_active_turn: bool = false
var _cached_color_name: String = ""
var _title_label: Label
var _hint_label: Label
var _status_label: Label
var _amount_label: Label
var _confirm_btn: Button
var _cancel_btn: Button
var _pass_btn: Button
var _dec_btn: Button
var _inc_btn: Button
var _card_image: TextureRect
var _accepted_row: HBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(20)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	_card_image = TextureRect.new()
	_card_image.custom_minimum_size = Vector2(0, 260)
	_card_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_image.visible = false
	var _bid_mat: ShaderMaterial = ShaderMaterial.new()
	_bid_mat.shader = load("res://shaders/card_rounded.gdshader")
	_card_image.material = _bid_mat
	vbox.add_child(_card_image)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 32)
	vbox.add_child(_title_label)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 20)
	_hint_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_hint_label)

	_accepted_row = HBoxContainer.new()
	_accepted_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_accepted_row.add_theme_constant_override("separation", 8)
	vbox.add_child(_accepted_row)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 20)
	_status_label.visible = false
	vbox.add_child(_status_label)

	var bid_row := HBoxContainer.new()
	bid_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bid_row.add_theme_constant_override("separation", 16)
	vbox.add_child(bid_row)

	_dec_btn = Button.new()
	_dec_btn.text = "−"
	_dec_btn.custom_minimum_size = Vector2(56, 56)
	_dec_btn.add_theme_font_size_override("font_size", 30)
	_dec_btn.pressed.connect(_on_decrease)
	bid_row.add_child(_dec_btn)

	_amount_label = Label.new()
	_amount_label.custom_minimum_size = Vector2(90, 56)
	_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_amount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_amount_label.add_theme_font_size_override("font_size", 40)
	bid_row.add_child(_amount_label)

	_inc_btn = Button.new()
	_inc_btn.text = "+"
	_inc_btn.custom_minimum_size = Vector2(56, 56)
	_inc_btn.add_theme_font_size_override("font_size", 30)
	_inc_btn.pressed.connect(_on_increase)
	bid_row.add_child(_inc_btn)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	btn_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_row.custom_minimum_size = Vector2(620, 0)
	vbox.add_child(btn_row)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel_btn.custom_minimum_size = Vector2(0, 56)
	_cancel_btn.add_theme_font_size_override("font_size", 24)
	_cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(_cancel_btn)

	_pass_btn = Button.new()
	_pass_btn.text = "Pass"
	_pass_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pass_btn.custom_minimum_size = Vector2(0, 56)
	_pass_btn.add_theme_font_size_override("font_size", 24)
	_pass_btn.pressed.connect(_on_pass)
	_pass_btn.visible = false
	btn_row.add_child(_pass_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = "Confirm Bid"
	_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_btn.custom_minimum_size = Vector2(0, 56)
	_confirm_btn.add_theme_font_size_override("font_size", 24)
	_confirm_btn.pressed.connect(_on_confirm)
	btn_row.add_child(_confirm_btn)

	visible = false

func _set_accepted_colors(cost_color: CardData.SupplyColor) -> void:
	for child: Node in _accepted_row.get_children():
		child.queue_free()
	var prefix := Label.new()
	prefix.text = "Pays with:"
	prefix.add_theme_font_size_override("font_size", 16)
	prefix.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8))
	_accepted_row.add_child(prefix)
	var colors: Array[CardData.SupplyColor] = CardData.valid_payment_colors(cost_color)
	for i: int in colors.size():
		var color: CardData.SupplyColor = colors[i]
		var lbl := Label.new()
		lbl.text = CardData.color_name(color) + ("," if i < colors.size() - 1 else "")
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", CardData.color_tint(color))
		_accepted_row.add_child(lbl)

func _set_card_image(card_data: CardData, is_advanced: bool) -> void:
	if not card_data:
		_card_image.visible = false
		return
	var url: String = card_data.adv_image_url if is_advanced else card_data.image_url
	if url.is_empty():
		_card_image.visible = false
		return
	var tex: Texture2D = ImageCache.get_texture(url)
	_card_image.texture = tex
	_card_image.visible = tex != null

# ── Solo mode ─────────────────────────────────────────────────────────────────

func show_bid(card_data: CardData, is_advanced: bool, min_cost: int, cost_color: CardData.SupplyColor) -> void:
	_set_card_image(card_data, is_advanced)
	_set_accepted_colors(cost_color)
	_auction_mode = false
	_is_active_turn = true
	_min_cost = min_cost
	_bid_amount = min_cost
	var color_name: String = (CardData.SupplyColor.keys()[int(cost_color)] as String).capitalize()
	var card_name: String = ""
	if card_data:
		card_name = card_data.adv_name if (is_advanced and not card_data.adv_name.is_empty()) else card_data.card_name
	_title_label.text = "Bid for %s" % card_name
	_hint_label.text = "Minimum bid: %d %s" % [min_cost, color_name]
	_status_label.visible = false
	_cancel_btn.show()
	_pass_btn.visible = false
	_confirm_btn.text = "Confirm Bid"
	_dec_btn.disabled = false
	_inc_btn.disabled = false
	_update()
	show()

# ── Auction mode ──────────────────────────────────────────────────────────────

func show_auction(card_data: CardData, is_advanced: bool, current_bid: int, leader_name: String, cost_color: CardData.SupplyColor, is_active: bool, can_pass: bool) -> void:
	_set_card_image(card_data, is_advanced)
	_set_accepted_colors(cost_color)
	_auction_mode = true
	_min_cost = current_bid
	_bid_amount = current_bid + 1
	_cached_color_name = (CardData.SupplyColor.keys()[int(cost_color)] as String).capitalize()
	var card_name: String = ""
	if card_data:
		card_name = card_data.adv_name if (is_advanced and not card_data.adv_name.is_empty()) else card_data.card_name
	_title_label.text = "Bid for %s" % card_name
	_hint_label.text = "Current bid: %d %s  —  Leader: %s" % [current_bid, _cached_color_name, leader_name]
	_cancel_btn.hide()
	_confirm_btn.text = "Raise"
	_set_auction_active(is_active, can_pass)
	_update()
	show()

func update_auction(current_bid: int, leader_name: String, is_active: bool, can_pass: bool) -> void:
	_min_cost = current_bid
	if _bid_amount <= current_bid:
		_bid_amount = current_bid + 1
	_hint_label.text = "Current bid: %d %s  —  Leader: %s" % [current_bid, _cached_color_name, leader_name]
	_set_auction_active(is_active, can_pass)
	_update()
	if not visible:
		show()

func _set_auction_active(is_active: bool, can_pass: bool) -> void:
	_is_active_turn = is_active
	_status_label.visible = true
	if is_active:
		_status_label.text = "Your turn — raise to win!"
		_status_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	else:
		_status_label.text = "Waiting for other players…"
		_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_dec_btn.disabled = not is_active
	_inc_btn.disabled = not is_active
	_pass_btn.visible = is_active and can_pass

# ── Shared controls ───────────────────────────────────────────────────────────

func _on_increase() -> void:
	_bid_amount += 1
	_update()

func _on_decrease() -> void:
	if _auction_mode:
		_bid_amount = maxi(_min_cost + 1, _bid_amount - 1)
	else:
		_bid_amount = maxi(_min_cost, _bid_amount - 1)
	_update()

func _update() -> void:
	_amount_label.text = str(_bid_amount)
	if _auction_mode:
		_confirm_btn.disabled = not _is_active_turn or _bid_amount <= _min_cost
	else:
		_confirm_btn.disabled = _bid_amount < _min_cost

func _on_confirm() -> void:
	if _auction_mode:
		bid_raised.emit(_bid_amount)
	else:
		hide()
		bid_confirmed.emit(_bid_amount)

func _on_cancel() -> void:
	hide()
	bid_cancelled.emit()

func _on_pass() -> void:
	bid_passed.emit()
