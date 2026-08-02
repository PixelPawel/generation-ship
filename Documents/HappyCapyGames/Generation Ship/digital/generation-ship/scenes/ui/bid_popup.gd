extends Control

signal bid_confirmed(amount: int)
signal bid_cancelled
signal bid_raised(amount: int)
signal bid_passed

var _min_cost: int = 0
var _bid_amount: int = 0
var _auction_mode: bool = false
var _is_active_turn: bool = false
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

	# Only the left ~58% of the info screen — the market panel's Players
	# column (opponent supply/hand/VP + auction status, see market_panel.gd)
	# lives in the rightmost ~40% and must stay visible/live during an
	# auction, not get painted over by this popup's own background.
	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(20)
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.58
	panel.anchor_bottom = 1.0
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0
	add_child(panel)

	# VBoxContainer top-packs by default — with the smaller sizing below no
	# longer needing the panel's full height, that left content stranded
	# near the top with dead space below instead of sitting centered in
	# the available area. CenterContainer sizes to its child's own minimum
	# size and centers that within the panel, both horizontally (already
	# true today, coincidentally) and vertically (which top-packing did not).
	var center := CenterContainer.new()
	panel.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	# Sized down from a full popup's card image (was 260) — this panel only
	# gets ~58% of the info screen's width now (see above), so the
	# full-size image plus every other row no longer fits the available
	# height without overflowing past the bottom of the 572-tall canvas.
	_card_image = TextureRect.new()
	_card_image.custom_minimum_size = Vector2(0, 210)
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
	_title_label.add_theme_font_size_override("font_size", 28)
	# Unwrapped, a long "Bid for <card name>" line was wider than this
	# panel's own ~58%-width content area, forcing the whole panel wider
	# than its anchors and pushing content past the info screen's edge —
	# same fix _hint_label below already uses.
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_title_label)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 19)
	_hint_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_hint_label)

	_accepted_row = HBoxContainer.new()
	_accepted_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_accepted_row.add_theme_constant_override("separation", 8)
	vbox.add_child(_accepted_row)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 19)
	_status_label.visible = false
	vbox.add_child(_status_label)

	var bid_row := HBoxContainer.new()
	bid_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bid_row.add_theme_constant_override("separation", 16)
	vbox.add_child(bid_row)

	_dec_btn = Button.new()
	_dec_btn.text = "−"
	_dec_btn.custom_minimum_size = Vector2(52, 52)
	_dec_btn.add_theme_font_size_override("font_size", 27)
	_dec_btn.pressed.connect(_on_decrease)
	bid_row.add_child(_dec_btn)

	_amount_label = Label.new()
	_amount_label.custom_minimum_size = Vector2(84, 52)
	_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_amount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_amount_label.add_theme_font_size_override("font_size", 36)
	bid_row.add_child(_amount_label)

	_inc_btn = Button.new()
	_inc_btn.text = "+"
	_inc_btn.custom_minimum_size = Vector2(52, 52)
	_inc_btn.add_theme_font_size_override("font_size", 27)
	_inc_btn.pressed.connect(_on_increase)
	bid_row.add_child(_inc_btn)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	btn_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Was 620 — sized for the popup's old full-width layout; this panel's
	# own content area is only ~656px (58% of the 1200-wide info screen
	# minus margins), so the button row needs real headroom below that,
	# not just barely under it.
	btn_row.custom_minimum_size = Vector2(560, 0)
	vbox.add_child(btn_row)

	_cancel_btn = Button.new()
	_cancel_btn.text = tr("Cancel")
	_cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel_btn.custom_minimum_size = Vector2(0, 52)
	_cancel_btn.add_theme_font_size_override("font_size", 22)
	_cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(_cancel_btn)

	_pass_btn = Button.new()
	_pass_btn.text = tr("Pass")
	_pass_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pass_btn.custom_minimum_size = Vector2(0, 52)
	_pass_btn.add_theme_font_size_override("font_size", 22)
	_pass_btn.pressed.connect(_on_pass)
	_pass_btn.visible = false
	btn_row.add_child(_pass_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = tr("Confirm Bid")
	_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_btn.custom_minimum_size = Vector2(0, 52)
	_confirm_btn.add_theme_font_size_override("font_size", 22)
	_confirm_btn.pressed.connect(_on_confirm)
	btn_row.add_child(_confirm_btn)

	visible = false

func _set_accepted_colors(cost_color: CardData.SupplyColor) -> void:
	for child: Node in _accepted_row.get_children():
		child.queue_free()
	var prefix := Label.new()
	prefix.text = tr("Pays with:")
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
	var color_name: String = CardData.color_name(cost_color)
	var card_name: String = ""
	if card_data:
		card_name = card_data.adv_name if (is_advanced and not card_data.adv_name.is_empty()) else card_data.card_name
	_title_label.visible = true
	_hint_label.visible = true
	_title_label.text = tr("Bid for %s") % card_name
	_hint_label.text = tr("Minimum bid: %d %s") % [min_cost, color_name]
	_status_label.visible = false
	_cancel_btn.show()
	_pass_btn.visible = false
	_confirm_btn.text = tr("Confirm Bid")
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
	# Card name/current-bid/leader as text is redundant here — the card art
	# is already shown above, and the Players column on the right (see the
	# ~58%-width anchor note at the top of _ready) already shows live
	# per-player auction status, including who's leading.
	_title_label.visible = false
	_hint_label.visible = false
	_cancel_btn.hide()
	_confirm_btn.text = tr("Raise")
	_set_auction_active(is_active, can_pass)
	_update()
	show()

func update_auction(current_bid: int, leader_name: String, is_active: bool, can_pass: bool) -> void:
	_min_cost = current_bid
	if _bid_amount <= current_bid:
		_bid_amount = current_bid + 1
	_set_auction_active(is_active, can_pass)
	_update()
	if not visible:
		show()

func _set_auction_active(is_active: bool, can_pass: bool) -> void:
	_is_active_turn = is_active
	_status_label.visible = true
	if is_active:
		_status_label.text = tr("Your turn — raise to win!")
		_status_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	else:
		_status_label.text = tr("Waiting for other players…")
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
