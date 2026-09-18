extends Control

# Photo-scan VP calculator (see the plan for the full design). One photo
# covers the whole ship; CardDetector.cluster_candidates() groups the
# detected cards into per-sector clusters by spatial proximity, and each
# cluster is reviewed/corrected one at a time through the same screen a
# per-sector capture would have used. Capture uses the real CameraIntentPlugin
# on Android (falls back to a plain file picker elsewhere, since the plugin
# only exists in Android builds). Follows the same code-built-UI convention
# as collection_popup.gd / manual_popup.gd (no companion .tscn).

const CardDetectorScript := preload("res://scripts/photo_scan/card_detector.gd")
const CardMatcherScript := preload("res://scripts/photo_scan/card_matcher.gd")
const SupplyDetectorScript := preload("res://scripts/photo_scan/supply_detector.gd")
const CLUSTER_PADDING_PX: int = 24

# Sized for touch on a phone screen, not desktop-popup scale — this whole
# popup is Android-only in practice (see main_menu.gd), unlike the other
# code-built popups it otherwise mirrors the style of.
const TITLE_FONT_SIZE: int = 32
const HINT_FONT_SIZE: int = 22
const LABEL_FONT_SIZE: int = 22
const BUTTON_FONT_SIZE: int = 26
const BUTTON_MIN_HEIGHT: float = 88.0
const CONTROL_FONT_SIZE: int = 22
const CONTROL_MIN_HEIGHT: float = 72.0

const _SUPPLY_ICON_SIZE: Vector2 = Vector2(48, 48)
# Same res://assets/ui/supply/<Name>.png set supply_ui.gd uses elsewhere —
# the real resource-token graphics, not the card-frame icon set.
const _SUPPLY_ICON_PATHS: Dictionary = {
	CardData.SupplyColor.DUST:     "res://assets/ui/supply/Dust.png",
	CardData.SupplyColor.METALS:   "res://assets/ui/supply/Metals.png",
	CardData.SupplyColor.LIQUIDS:  "res://assets/ui/supply/Liquids.png",
	CardData.SupplyColor.ORGANIX:  "res://assets/ui/supply/Organix.png",
	CardData.SupplyColor.ELECTRIX: "res://assets/ui/supply/Electrix.png",
	CardData.SupplyColor.THRUST:   "res://assets/ui/supply/Thrust.png",
}

const _SUPPLY_COLORS: Array[CardData.SupplyColor] = [
	CardData.SupplyColor.DUST, CardData.SupplyColor.METALS, CardData.SupplyColor.LIQUIDS,
	CardData.SupplyColor.ORGANIX, CardData.SupplyColor.ELECTRIX, CardData.SupplyColor.THRUST,
]
const _ROLES: Array[String] = ["sector", "tech", "tucked_up", "tucked_down"]
const _ROLE_LABELS: Array[String] = ["Sector", "Tech", "Tucked (face up)", "Tucked (face down)"]

var _matcher: RefCounted = null
var _sectors: Array[Dictionary] = []          # board entries confirmed so far, BotScoring-shaped
var _pending: Array[Dictionary] = []          # current in-review cluster's candidates
var _source_image: Image = null               # the one whole-ship photo, kept for supply detection per cluster
var _cluster_queue: Array = []                 # remaining clusters (Array[Dictionary]) still to review

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
	_cluster_queue.clear()
	_source_image = null
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
	panel.set_content_margin(28)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(vbox)

	var title_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(title_row)
	var title: Label = Label.new()
	title.text = "SCAN TABLEAU"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close_btn: Button = _make_button("✕")
	close_btn.custom_minimum_size = Vector2(BUTTON_MIN_HEIGHT, BUTTON_MIN_HEIGHT)
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
	box.add_theme_constant_override("separation", 14)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var hint: Label = _make_hint_label("Photograph your whole ship in one shot — fan out each sector's cards (sector, tech stack, tucked cards) so each is at least partly visible, with a gap between sectors. You'll review one sector at a time next.")
	box.add_child(hint)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_sector_list_box = VBoxContainer.new()
	_sector_list_box.add_theme_constant_override("separation", 10)
	_sector_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_sector_list_box)

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	box.add_child(btn_row)
	var add_btn: Button = _make_button("Scan Ship")
	add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_btn.pressed.connect(_on_scan_ship_pressed)
	btn_row.add_child(add_btn)
	_calculate_btn = _make_button("Calculate Score")
	_calculate_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_calculate_btn.pressed.connect(_on_calculate_pressed)
	btn_row.add_child(_calculate_btn)

	box.add_child(HSeparator.new())
	_results_box = VBoxContainer.new()
	_results_box.add_theme_constant_override("separation", 6)
	box.add_child(_results_box)

	return box

func _build_review_view() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var hint: Label = _make_hint_label("Check each card's role and name (auto-detected — correct anything wrong). Stored supply below is also auto-detected and much less reliable than card identity — check it carefully.")
	box.add_child(hint)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_review_cards_box = HBoxContainer.new()
	_review_cards_box.add_theme_constant_override("separation", 20)
	scroll.add_child(_review_cards_box)

	box.add_child(HSeparator.new())

	var supply_label: Label = _make_hint_label("Stored supply on this sector:")
	box.add_child(supply_label)
	var supply_row: HBoxContainer = HBoxContainer.new()
	supply_row.add_theme_constant_override("separation", 16)
	box.add_child(supply_row)
	_supply_spinboxes.clear()
	for color: CardData.SupplyColor in _SUPPLY_COLORS:
		var col_box: VBoxContainer = VBoxContainer.new()
		col_box.add_theme_constant_override("separation", 8)
		col_box.alignment = BoxContainer.ALIGNMENT_CENTER
		col_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var icon: TextureRect = TextureRect.new()
		icon.texture = load(_SUPPLY_ICON_PATHS[color]) as Texture2D
		icon.custom_minimum_size = _SUPPLY_ICON_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# custom_minimum_size alone doesn't shrink a TextureRect below its
		# texture's own native pixel size — EXPAND_IGNORE_SIZE is needed too
		# (same fix as supply_ui.gd/collection_popup.gd/market_panel.gd).
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.tooltip_text = CardData.color_name(color)
		col_box.add_child(icon)
		var spin: SpinBox = SpinBox.new()
		spin.min_value = 0
		spin.max_value = 99
		spin.custom_minimum_size = Vector2(0, CONTROL_MIN_HEIGHT)
		spin.get_line_edit().add_theme_font_size_override("font_size", CONTROL_FONT_SIZE)
		col_box.add_child(spin)
		supply_row.add_child(col_box)
		_supply_spinboxes[int(color)] = spin

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	box.add_child(btn_row)
	var cancel_btn: Button = _make_button("Skip Sector")
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(_on_skip_sector_pressed)
	btn_row.add_child(cancel_btn)
	_confirm_btn = _make_button("Confirm Sector")
	_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_btn.pressed.connect(_on_confirm_sector_pressed)
	btn_row.add_child(_confirm_btn)

	return box

func _make_button(label: String) -> Button:
	var btn: Button = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, BUTTON_MIN_HEIGHT)
	btn.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	GameTheme.apply_to_button(btn)
	return btn

func _make_hint_label(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	return lbl

# ── View switching ───────────────────────────────────────────────────────────

func _show_list_view() -> void:
	_list_view.visible = true
	_review_view.visible = false

func _show_review_view() -> void:
	_list_view.visible = false
	_review_view.visible = true

# ── Capture -> detect -> review ─────────────────────────────────────────────

# The real camera-intent plugin only exists in Android builds (it's Kotlin
# source added directly to android/build/, not a GDExtension, so there's
# nothing to check for on other platforms) — fall back to the file-picker
# stub elsewhere so the rest of the flow stays testable on desktop.
func _on_scan_ship_pressed() -> void:
	if Engine.has_singleton("CameraIntentPlugin"):
		var plugin: Object = Engine.get_singleton("CameraIntentPlugin")
		if not plugin.photo_captured.is_connected(_on_photo_selected):
			plugin.photo_captured.connect(_on_photo_selected)
		if not plugin.photo_canceled.is_connected(_on_photo_canceled):
			plugin.photo_canceled.connect(_on_photo_canceled)
		plugin.capture_photo()
	else:
		_file_dialog.popup_centered()

func _on_photo_canceled() -> void:
	pass  # user backed out of the camera app — stay on the sector list

func _on_photo_selected(path: String) -> void:
	var img := Image.new()
	if img.load(path) != OK:
		push_warning("Scan Tableau: could not load %s" % path)
		return
	_source_image = img
	var candidates: Array[Dictionary] = CardDetectorScript.detect(img)
	_cluster_queue = CardDetectorScript.cluster_candidates(candidates)
	if _cluster_queue.is_empty():
		push_warning("Scan Tableau: no cards detected in that photo")
		return
	_start_reviewing_next_cluster()

## Pops the next queued cluster and populates the review screen for it —
## one whole-ship photo yields several clusters (one per sector), reviewed
## one at a time through the same screen a per-sector capture would have used.
func _start_reviewing_next_cluster() -> void:
	if _cluster_queue.is_empty():
		_show_list_view()
		return
	var cluster: Array = _cluster_queue.pop_front()

	_pending = []
	for c: Dictionary in cluster:
		var crop: Image = CardDetectorScript.extract_card(_source_image, c)
		var result: Dictionary = _matcher.match_card(crop)
		_pending.append({
			"thumbnail": crop,
			"role": "tech",
			"name": String(result.get("name", "")),
			"is_advanced": false,
		})
	if not _pending.is_empty():
		_pending[0]["role"] = "sector"

	var detected_supply: Dictionary = SupplyDetectorScript.detect(_source_image, _cluster_region(cluster))
	for color_int: int in _supply_spinboxes:
		(_supply_spinboxes[color_int] as SpinBox).value = int(detected_supply.get(color_int, 0))

	_populate_review_cards()
	_show_review_view()

## The cluster's own card candidates only cover the cards themselves —
## stored-supply tokens usually sit on or beside them, so search a padded
## region around the whole cluster rather than just the cards' own boxes.
func _cluster_region(cluster: Array) -> Rect2i:
	var union: Rect2i = (cluster[0]["rect"] as Rect2i)
	for c: Dictionary in cluster:
		union = union.merge(c["rect"] as Rect2i)
	return union.grow(CLUSTER_PADDING_PX)

func _on_skip_sector_pressed() -> void:
	_start_reviewing_next_cluster()

func _populate_review_cards() -> void:
	for child: Node in _review_cards_box.get_children():
		child.queue_free()
	for entry: Dictionary in _pending:
		_review_cards_box.add_child(_build_card_review_row(entry))

func _build_card_review_row(entry: Dictionary) -> Control:
	var col: VBoxContainer = VBoxContainer.new()
	col.custom_minimum_size = Vector2(260, 0)
	col.add_theme_constant_override("separation", 10)

	var thumb: TextureRect = TextureRect.new()
	thumb.texture = ImageTexture.create_from_image(entry["thumbnail"] as Image)
	thumb.custom_minimum_size = Vector2(200, 280)
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	col.add_child(thumb)

	var role_btn: OptionButton = OptionButton.new()
	role_btn.custom_minimum_size = Vector2(0, CONTROL_MIN_HEIGHT)
	role_btn.add_theme_font_size_override("font_size", CONTROL_FONT_SIZE)
	for label: String in _ROLE_LABELS:
		role_btn.add_item(label)
	role_btn.select(_ROLES.find(entry["role"]))
	col.add_child(role_btn)

	var name_edit: LineEdit = LineEdit.new()
	name_edit.text = entry["name"]
	name_edit.custom_minimum_size = Vector2(0, CONTROL_MIN_HEIGHT)
	name_edit.add_theme_font_size_override("font_size", CONTROL_FONT_SIZE)
	col.add_child(name_edit)
	name_edit.text_changed.connect(func(t: String): entry["name"] = t)

	var adv_check: CheckBox = CheckBox.new()
	adv_check.text = "Advanced side"
	adv_check.custom_minimum_size = Vector2(0, CONTROL_MIN_HEIGHT)
	adv_check.add_theme_font_size_override("font_size", CONTROL_FONT_SIZE)
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
	_start_reviewing_next_cluster()

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
		lbl.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
		_sector_list_box.add_child(lbl)
	_calculate_btn.disabled = _sectors.is_empty()

func _on_calculate_pressed() -> void:
	for child: Node in _results_box.get_children():
		child.queue_free()
	var lines: Array[Dictionary] = BotScoring.board_vp_lines(_sectors)
	for line: Dictionary in lines:
		var lbl: Label = Label.new()
		lbl.text = "%s: %d" % [line["label"], line["vp"]]
		lbl.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
		_results_box.add_child(lbl)
	var total_lbl: Label = Label.new()
	total_lbl.text = "TOTAL: %d" % BotScoring.board_vp(_sectors)
	total_lbl.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	total_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	_results_box.add_child(total_lbl)
