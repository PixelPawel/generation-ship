extends Control

# Guided per-sector photo-scan VP calculator (see the plan for the full
# design). Capture is stubbed with a plain file picker for now — the real
# camera-intent Android plugin doesn't exist yet, and this lets the rest of
# the pipeline (detect -> review/correct -> score) be built and tested today
# without it. Follows the same code-built-UI convention as collection_popup.gd
# / manual_popup.gd (no companion .tscn).

const CardDetectorScript := preload("res://scripts/photo_scan/card_detector.gd")
const CardMatcherScript := preload("res://scripts/photo_scan/card_matcher.gd")

const _SUPPLY_COLORS: Array[CardData.SupplyColor] = [
	CardData.SupplyColor.DUST, CardData.SupplyColor.METALS, CardData.SupplyColor.LIQUIDS,
	CardData.SupplyColor.ORGANIX, CardData.SupplyColor.ELECTRIX, CardData.SupplyColor.THRUST,
]
const _ROLES: Array[String] = ["sector", "tech", "tucked_up", "tucked_down"]
const _ROLE_LABELS: Array[String] = ["Sector", "Tech", "Tucked (face up)", "Tucked (face down)"]

var _matcher: RefCounted = null
var _sectors: Array[Dictionary] = []          # board entries confirmed so far, BotScoring-shaped
var _pending: Array[Dictionary] = []          # current in-review capture's candidates

var _file_dialog: FileDialog = null
var _list_view: Control = null
var _review_view: Control = null
var _sector_list_box: VBoxContainer = null
var _results_box: VBoxContainer = null
var _calculate_btn: Button = null
var _review_cards_box: HBoxContainer = null
var _confirm_btn: Button = null
var _supply_spinboxes: Dictionary = {}        # SupplyColor(int) -> SpinBox

func _ready() -> void:
	_build_ui()
	visible = false

func open() -> void:
	_sectors.clear()
	if _matcher == null:
		_matcher = CardMatcherScript.new()
	_refresh_sector_list()
	_show_list_view()
	visible = true

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()

# ── UI construction ────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var panel: Control = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(20)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(1000, 760)
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.custom_minimum_size = Vector2(960, 0)
	panel.add_child(vbox)

	var title_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(title_row)
	var title: Label = Label.new()
	title.text = "SCAN TABLEAU"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close_btn: Button = _make_button("✕")
	close_btn.custom_minimum_size = Vector2(36, 0)
	close_btn.pressed.connect(func(): visible = false)
	title_row.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	_list_view = _build_list_view()
	vbox.add_child(_list_view)
	_review_view = _build_review_view()
	vbox.add_child(_review_view)

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = false
	_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg ; Photos"])
	_file_dialog.size = Vector2i(800, 600)
	_file_dialog.file_selected.connect(_on_photo_selected)
	add_child(_file_dialog)

func _build_list_view() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)

	var hint: Label = Label.new()
	hint.text = "Photograph one sector's cards at a time — sector card, its tech stack, and any tucked cards, fanned out so each is at least partly visible. Add sectors one by one, then calculate."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(hint)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_sector_list_box = VBoxContainer.new()
	_sector_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_sector_list_box)

	var btn_row: HBoxContainer = HBoxContainer.new()
	box.add_child(btn_row)
	var add_btn: Button = _make_button("Add Sector Photo")
	add_btn.pressed.connect(func(): _file_dialog.popup_centered())
	btn_row.add_child(add_btn)
	_calculate_btn = _make_button("Calculate Score")
	_calculate_btn.pressed.connect(_on_calculate_pressed)
	btn_row.add_child(_calculate_btn)

	box.add_child(HSeparator.new())
	_results_box = VBoxContainer.new()
	box.add_child(_results_box)

	return box

func _build_review_view() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)

	var hint: Label = Label.new()
	hint.text = "Check each card's role and name (auto-detected — correct anything wrong), then enter this sector's stored supply."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(hint)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 340)
	box.add_child(scroll)
	_review_cards_box = HBoxContainer.new()
	_review_cards_box.add_theme_constant_override("separation", 14)
	scroll.add_child(_review_cards_box)

	box.add_child(HSeparator.new())

	var supply_label: Label = Label.new()
	supply_label.text = "Stored supply on this sector:"
	box.add_child(supply_label)
	var supply_row: HBoxContainer = HBoxContainer.new()
	supply_row.add_theme_constant_override("separation", 12)
	box.add_child(supply_row)
	_supply_spinboxes.clear()
	for color: CardData.SupplyColor in _SUPPLY_COLORS:
		var col_box: VBoxContainer = VBoxContainer.new()
		var lbl: Label = Label.new()
		lbl.text = CardData.color_name(color)
		lbl.add_theme_font_size_override("font_size", 13)
		col_box.add_child(lbl)
		var spin: SpinBox = SpinBox.new()
		spin.min_value = 0
		spin.max_value = 99
		spin.custom_minimum_size = Vector2(70, 0)
		col_box.add_child(spin)
		supply_row.add_child(col_box)
		_supply_spinboxes[int(color)] = spin

	var btn_row: HBoxContainer = HBoxContainer.new()
	box.add_child(btn_row)
	var cancel_btn: Button = _make_button("Cancel")
	cancel_btn.pressed.connect(_show_list_view)
	btn_row.add_child(cancel_btn)
	_confirm_btn = _make_button("Confirm Sector")
	_confirm_btn.pressed.connect(_on_confirm_sector_pressed)
	btn_row.add_child(_confirm_btn)

	return box

func _make_button(label: String) -> Button:
	var btn: Button = Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 14)
	GameTheme.apply_to_button(btn)
	return btn

# ── View switching ───────────────────────────────────────────────────────────

func _show_list_view() -> void:
	_list_view.visible = true
	_review_view.visible = false

func _show_review_view() -> void:
	_list_view.visible = false
	_review_view.visible = true

# ── Capture -> detect -> review ─────────────────────────────────────────────

func _on_photo_selected(path: String) -> void:
	var img := Image.new()
	if img.load(path) != OK:
		push_warning("Scan Tableau: could not load %s" % path)
		return
	var candidates: Array[Dictionary] = CardDetectorScript.detect(img)
	_pending = []
	for c: Dictionary in candidates:
		var crop: Image = CardDetectorScript.extract_card(img, c)
		var result: Dictionary = _matcher.match_card(crop)
		_pending.append({
			"thumbnail": crop,
			"role": "tech",
			"name": String(result.get("name", "")),
			"is_advanced": false,
		})
	if not _pending.is_empty():
		_pending[0]["role"] = "sector"
	for spin: SpinBox in _supply_spinboxes.values():
		spin.value = 0
	_populate_review_cards()
	_show_review_view()

func _populate_review_cards() -> void:
	for child: Node in _review_cards_box.get_children():
		child.queue_free()
	for entry: Dictionary in _pending:
		_review_cards_box.add_child(_build_card_review_row(entry))

func _build_card_review_row(entry: Dictionary) -> Control:
	var col: VBoxContainer = VBoxContainer.new()
	col.custom_minimum_size = Vector2(150, 0)
	col.add_theme_constant_override("separation", 4)

	var thumb: TextureRect = TextureRect.new()
	thumb.texture = ImageTexture.create_from_image(entry["thumbnail"] as Image)
	thumb.custom_minimum_size = Vector2(120, 168)
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	col.add_child(thumb)

	var role_btn: OptionButton = OptionButton.new()
	for label: String in _ROLE_LABELS:
		role_btn.add_item(label)
	role_btn.select(_ROLES.find(entry["role"]))
	col.add_child(role_btn)

	var name_edit: LineEdit = LineEdit.new()
	name_edit.text = entry["name"]
	col.add_child(name_edit)
	name_edit.text_changed.connect(func(t: String): entry["name"] = t)

	var adv_check: CheckBox = CheckBox.new()
	adv_check.text = "Advanced side"
	adv_check.button_pressed = entry["is_advanced"]
	adv_check.visible = entry["role"] == "sector"
	col.add_child(adv_check)
	adv_check.toggled.connect(func(pressed: bool): entry["is_advanced"] = pressed)

	role_btn.item_selected.connect(func(idx: int) -> void:
		entry["role"] = _ROLES[idx]
		adv_check.visible = entry["role"] == "sector"
		name_edit.editable = entry["role"] != "tucked_down")

	return col

# ── Confirm sector / calculate ──────────────────────────────────────────────

func _on_confirm_sector_pressed() -> void:
	var sector_cd: CardData = null
	var is_advanced: bool = false
	var techs: Array[CardData] = []
	var tucked: Array[Dictionary] = []
	for entry: Dictionary in _pending:
		var role: String = entry["role"]
		var name: String = (entry["name"] as String).strip_edges()
		if role == "sector":
			is_advanced = entry["is_advanced"]
			sector_cd = CardDatabase.find_sector_by_name(name, is_advanced)
		elif role == "tech":
			var cd: CardData = CardDatabase.find_any_by_name(name)
			if cd:
				techs.append(cd)
			else:
				push_warning("Scan Tableau: unknown tech card name '%s', skipped" % name)
		elif role == "tucked_up":
			var cd: CardData = CardDatabase.find_any_by_name(name)
			if cd:
				tucked.append({"data": cd, "face_up": true})
			else:
				push_warning("Scan Tableau: unknown tucked card name '%s', skipped" % name)
		elif role == "tucked_down":
			tucked.append({"data": null, "face_up": false})

	if sector_cd == null:
		push_warning("Scan Tableau: no valid sector card set for this capture — not adding a sector")
		return

	var stored: Dictionary = {}
	for color_int: int in _supply_spinboxes:
		var amount: int = int((_supply_spinboxes[color_int] as SpinBox).value)
		if amount > 0:
			stored[color_int] = amount

	_sectors.append({
		"sector": sector_cd,
		"is_advanced": is_advanced,
		"techs": techs,
		"tucked_cards": tucked,
		"stored_supply": stored,
	})
	_refresh_sector_list()
	_show_list_view()

func _refresh_sector_list() -> void:
	for child: Node in _sector_list_box.get_children():
		child.queue_free()
	for i: int in _sectors.size():
		var entry: Dictionary = _sectors[i]
		var sector_cd: CardData = entry["sector"]
		var name: String = sector_cd.adv_name if (entry["is_advanced"] and not sector_cd.adv_name.is_empty()) else sector_cd.card_name
		var lbl: Label = Label.new()
		lbl.text = "Sector %d: %s — %d tech, %d tucked" % [
			i + 1, name, (entry["techs"] as Array).size(), (entry["tucked_cards"] as Array).size(),
		]
		_sector_list_box.add_child(lbl)
	_calculate_btn.disabled = _sectors.is_empty()

func _on_calculate_pressed() -> void:
	for child: Node in _results_box.get_children():
		child.queue_free()
	var lines: Array[Dictionary] = BotScoring.board_vp_lines(_sectors)
	for line: Dictionary in lines:
		var lbl: Label = Label.new()
		lbl.text = "%s: %d" % [line["label"], line["vp"]]
		_results_box.add_child(lbl)
	var total_lbl: Label = Label.new()
	total_lbl.text = "TOTAL: %d" % BotScoring.board_vp(_sectors)
	total_lbl.add_theme_font_size_override("font_size", 18)
	total_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	_results_box.add_child(total_lbl)
