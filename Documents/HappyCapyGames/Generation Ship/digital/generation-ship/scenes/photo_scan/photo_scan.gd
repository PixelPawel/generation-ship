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
const CardPickerScript := preload("res://scenes/photo_scan/card_picker.gd")
const CLUSTER_PADDING_PX: int = 24

# A sector always shows exactly 6 slots: 1 sector card + 5 tech/expedition
# (its physical maximum), never fewer or more — unused slots just stay
# blank rather than being added/removed. Review columns are sized to fit
# all 6 across one phone-width screen without horizontal scrolling.
const SECTOR_SLOT_COUNT: int = 6
const REVIEW_COL_WIDTH: float = 210.0
const REVIEW_THUMB_SIZE: Vector2 = Vector2(180, 252)

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

# Shrunk from a first pass at 48px icons / 72px-tall spinboxes — this row
# also now carries the tucked-card counters (see the note further down
# about how face-up tucked cards are tallied), so each entry needs to be
# more compact to keep the whole row on one phone-width screen.
const _SUPPLY_ICON_SIZE: Vector2 = Vector2(36, 36)
const SUPPLY_CONTROL_HEIGHT: float = 56.0
const SUPPLY_FONT_SIZE: int = 18
# Fixed narrow width for the 6 supply number fields (shrink-to-content
# instead of sharing the row equally with the tucked counters) — just wide
# enough for a 2-digit value plus the SpinBox's own up/down arrows.
const SUPPLY_SPIN_WIDTH: float = 64.0
# Same res://assets/ui/supply/<Name>.png set supply_ui.gd uses elsewhere —
# the real resource-token graphics, not the card-frame icon set.
const _SUPPLY_ICON_PATHS: Dictionary = {
	CardData.SupplyColor.DUST:     "res://assets/ui/supply/Dust.png",
	CardData.SupplyColor.METALS:   "res://assets/ui/supply/Metals.png",
	CardData.SupplyColor.LIQUIDS:  "res://assets/ui/supply/Liquids.png",
	CardData.SupplyColor.ORGANIX: "res://assets/ui/supply/Organix.png",
	CardData.SupplyColor.ELECTRIX: "res://assets/ui/supply/Electrix.png",
	CardData.SupplyColor.THRUST:   "res://assets/ui/supply/Thrust.png",
}

const _SUPPLY_COLORS: Array[CardData.SupplyColor] = [
	CardData.SupplyColor.DUST, CardData.SupplyColor.METALS, CardData.SupplyColor.LIQUIDS,
	CardData.SupplyColor.ORGANIX, CardData.SupplyColor.ELECTRIX, CardData.SupplyColor.THRUST,
]

# Every picked card's identity is known (CardPicker only ever hands back a
# real name), so there's no more "sector/tech/tucked" role dropdown per card
# — the first reviewed card is always the sector, the rest are always its
# exposed tech stack. Tucked cards (which don't get their own slot/art
# anymore) are tracked as plain counts instead: face-down ones score as pure
# counts anyway (BotScoring never needs their identity), and face-up ones
# split into a card count plus a separately entered total-stars value (the
# printed star icons are visible on a face-up tucked card even without
# identifying exactly which card it is), rather than guessing at an assumed
# average.

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
var _tucked_up_spinbox: SpinBox = null       # count of face-up tucked cards
var _tucked_up_stars_spinbox: SpinBox = null # total printed stars across those cards
var _tucked_down_spinbox: SpinBox = null     # count of face-down tucked cards (identity/stars n/a)
var _card_picker: Control = null
var _picker_callback: Callable = Callable()   # armed while a row's Edit flow is waiting on a pick

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

	_card_picker = CardPickerScript.new()
	add_child(_card_picker)

func _build_list_view() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var hint: Label = _make_hint_label("Photograph your whole ship in one shot to auto-detect a starting point, or add sectors by hand — either way you'll review and can add/remove cards before confirming each sector.")
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
	var add_sector_btn: Button = _make_button("+ Add Sector")
	add_sector_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_sector_btn.pressed.connect(_on_add_sector_pressed)
	btn_row.add_child(add_sector_btn)
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

	var hint: Label = _make_hint_label("Every sector always shows 6 slots: the first is the sector, the other 5 are its tech/expedition stack (leave any unused ones blank). Tap Edit to pick a card's real identity from the collection (auto-detected as a starting guess where possible). Stored supply and tucked-card counts below are also auto-detected and much less reliable than card identity — check them carefully.")
	box.add_child(hint)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_review_cards_box = HBoxContainer.new()
	_review_cards_box.add_theme_constant_override("separation", 14)
	scroll.add_child(_review_cards_box)

	box.add_child(HSeparator.new())

	var supply_label: Label = _make_hint_label("Stored supply and tucked cards on this sector (tucked cards' exact identity isn't tracked — for face-up ones, enter how many and the total stars printed on them):")
	box.add_child(supply_label)
	var supply_row: HBoxContainer = HBoxContainer.new()
	supply_row.add_theme_constant_override("separation", 8)
	box.add_child(supply_row)
	_supply_spinboxes.clear()
	for color: CardData.SupplyColor in _SUPPLY_COLORS:
		var col_box: VBoxContainer = VBoxContainer.new()
		col_box.add_theme_constant_override("separation", 4)
		col_box.alignment = BoxContainer.ALIGNMENT_CENTER
		# Shrink-to-content instead of expand-fill: with 6 of these plus the
		# 2 tucked counters all sharing the row, letting the number fields
		# stay narrow (SUPPLY_SPIN_WIDTH) leaves the tucked counters
		# (still expand-fill) the rest of the row's width.
		col_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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
		spin.custom_minimum_size = Vector2(SUPPLY_SPIN_WIDTH, SUPPLY_CONTROL_HEIGHT)
		spin.get_line_edit().add_theme_font_size_override("font_size", SUPPLY_FONT_SIZE)
		col_box.add_child(spin)
		supply_row.add_child(col_box)
		_supply_spinboxes[int(color)] = spin

	supply_row.add_child(VSeparator.new())
	_tucked_up_spinbox = _make_tucked_counter(supply_row, "Tucked ▲")
	_tucked_up_stars_spinbox = _make_tucked_counter(supply_row, "▲ Stars ★")
	supply_row.add_child(VSeparator.new())
	_tucked_down_spinbox = _make_tucked_counter(supply_row, "Tucked ▼")

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

func _make_tucked_counter(parent: HBoxContainer, label_text: String) -> SpinBox:
	var col_box: VBoxContainer = VBoxContainer.new()
	col_box.add_theme_constant_override("separation", 4)
	col_box.alignment = BoxContainer.ALIGNMENT_CENTER
	col_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl: Label = Label.new()
	lbl.text = label_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", SUPPLY_FONT_SIZE)
	col_box.add_child(lbl)
	var spin: SpinBox = SpinBox.new()
	spin.min_value = 0
	spin.max_value = 99
	spin.custom_minimum_size = Vector2(0, SUPPLY_CONTROL_HEIGHT)
	spin.get_line_edit().add_theme_font_size_override("font_size", SUPPLY_FONT_SIZE)
	col_box.add_child(spin)
	parent.add_child(col_box)
	return spin

## Looks up the official art for a card name the same way the review row's
## thumbnail and CardPicker's own tiles do, so a picked (or auto-detected,
## once its guessed name happens to resolve) card shows its real art instead
## of the raw photo crop. Empty string if the name doesn't resolve to
## anything (blank guess, or a still-uncorrected bad detection).
func _resolve_art_path(card_name: String, is_advanced: bool) -> String:
	if card_name.is_empty():
		return ""
	var sector_cd: CardData = CardDatabase.find_sector_by_name(card_name, is_advanced)
	if sector_cd:
		return sector_cd.adv_local_art_path if is_advanced else sector_cd.local_art_path
	var cd: CardData = CardDatabase.find_any_by_name(card_name)
	if cd:
		return cd.local_art_path
	return ""

## Whether a name is a sector's dust or advanced identity (as opposed to a
## tech/expedition) — used to sanity-check CardMatcher's auto-detected
## guesses against which slot they'd land in (slot 0 must be a sector,
## every other slot must not be).
func _match_as_sector(card_name: String) -> Dictionary:
	if card_name.is_empty():
		return {"found": false, "is_advanced": false}
	if CardDatabase.find_sector_by_name(card_name, false):
		return {"found": true, "is_advanced": false}
	if CardDatabase.find_sector_by_name(card_name, true):
		return {"found": true, "is_advanced": true}
	return {"found": false, "is_advanced": false}

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
		var is_sector_slot: bool = _pending.is_empty()
		var guessed_name: String = String(result.get("name", ""))
		var guessed_is_advanced: bool = false
		var sector_match: Dictionary = _match_as_sector(guessed_name)
		if is_sector_slot:
			if sector_match["found"]:
				guessed_is_advanced = sector_match["is_advanced"]
			else:
				# Slot 0 has to be a sector — a guess that resolves to a
				# tech/expedition instead is never trustworthy here, so
				# leave it blank rather than pre-fill something wrong.
				guessed_name = ""
		elif sector_match["found"]:
			# Slots 1-5 have to be tech/expedition — a guess that resolves
			# to a sector card is never trustworthy here either.
			guessed_name = ""
		_pending.append({
			"thumbnail": crop,
			"name": guessed_name,
			"is_advanced": guessed_is_advanced,
		})
	if _pending.size() > SECTOR_SLOT_COUNT:
		push_warning("Scan Tableau: detected %d cards in one sector, a sector can only hold %d — dropping the extras" % [_pending.size(), SECTOR_SLOT_COUNT])
		_pending = _pending.slice(0, SECTOR_SLOT_COUNT)
	while _pending.size() < SECTOR_SLOT_COUNT:
		_pending.append(_blank_entry())

	var detected_supply: Dictionary = SupplyDetectorScript.detect(_source_image, _cluster_region(cluster))
	for color_int: int in _supply_spinboxes:
		(_supply_spinboxes[color_int] as SpinBox).value = int(detected_supply.get(color_int, 0))
	_tucked_up_spinbox.value = 0
	_tucked_up_stars_spinbox.value = 0
	_tucked_down_spinbox.value = 0

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

## Lets the user build a sector entirely by hand, starting fresh from the
## list view — always the full 6 blank slots (1 sector + 5 tech/expedition),
## same shape as a detected cluster.
func _on_add_sector_pressed() -> void:
	_pending = []
	for i: int in range(SECTOR_SLOT_COUNT):
		_pending.append(_blank_entry())
	for color_int: int in _supply_spinboxes:
		(_supply_spinboxes[color_int] as SpinBox).value = 0
	_tucked_up_spinbox.value = 0
	_tucked_up_stars_spinbox.value = 0
	_tucked_down_spinbox.value = 0
	_populate_review_cards()
	_show_review_view()

func _blank_entry() -> Dictionary:
	return {"thumbnail": null, "name": "", "is_advanced": false}

func _populate_review_cards() -> void:
	for child: Node in _review_cards_box.get_children():
		child.queue_free()
	for i: int in range(_pending.size()):
		_review_cards_box.add_child(_build_card_review_row(_pending[i], i))

## index 0 is always the sector; every other reviewed card is always its
## exposed tech stack — there's no longer a per-card role to choose (tucked
## cards are tracked as counts in the supply panel instead, see there).
func _build_card_review_row(entry: Dictionary, index: int) -> Control:
	var is_sector: bool = index == 0
	var col: VBoxContainer = VBoxContainer.new()
	col.custom_minimum_size = Vector2(REVIEW_COL_WIDTH, 0)
	col.add_theme_constant_override("separation", 8)

	# The real card art (once the name resolves to one) always takes priority
	# over the raw detection crop — it's the clean reference image, not a
	# skewed/blurry photo of the physical card.
	var thumb: TextureRect = TextureRect.new()
	var art_path: String = _resolve_art_path(entry["name"], entry["is_advanced"])
	var thumbnail: Image = entry.get("thumbnail")
	if not art_path.is_empty():
		thumb.texture = load(art_path) as Texture2D
	elif thumbnail != null:
		thumb.texture = ImageTexture.create_from_image(thumbnail)
	thumb.custom_minimum_size = REVIEW_THUMB_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	col.add_child(thumb)

	# Dust vs Advanced is decided entirely by which CardPicker tab the sector
	# was picked from (no separate toggle needed anymore) — shown here so
	# that's still visible at a glance.
	var role_label: Label = Label.new()
	if is_sector:
		role_label.text = "Sector (Advanced)" if entry["is_advanced"] else "Sector (Dust)"
	else:
		role_label.text = "Tech / Exp."
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_label.add_theme_font_size_override("font_size", CONTROL_FONT_SIZE)
	col.add_child(role_label)

	# Read-only display of the picked name — typing a name by hand used to
	# silently fail the CardDatabase lookup on any typo, so the only way to
	# set it now is through the "Edit" -> CardPicker flow below, which can
	# only ever hand back a real card name.
	var name_edit: LineEdit = LineEdit.new()
	name_edit.text = entry["name"]
	name_edit.editable = false
	name_edit.custom_minimum_size = Vector2(0, CONTROL_MIN_HEIGHT)
	name_edit.add_theme_font_size_override("font_size", CONTROL_FONT_SIZE)
	col.add_child(name_edit)

	var edit_btn: Button = _make_button("Edit")
	col.add_child(edit_btn)

	# Slot 0 MUST be a sector and 1-5 MUST be a tech/expedition — never the
	# other way round — so the picker only ever shows the tabs that slot can
	# legally hold, not just defaults to one. That makes a wrong-type pick
	# structurally impossible rather than just discouraged.
	var default_tab: int
	var allowed_tabs: Array[int]
	if is_sector:
		default_tab = CardPickerScript.TAB_SECTOR_ADVANCED if entry["is_advanced"] else CardPickerScript.TAB_SECTOR_DUST
		allowed_tabs = [CardPickerScript.TAB_SECTOR_DUST, CardPickerScript.TAB_SECTOR_ADVANCED]
	else:
		default_tab = CardPickerScript.TAB_TECH
		allowed_tabs = [CardPickerScript.TAB_TECH, CardPickerScript.TAB_EXPEDITION]
	edit_btn.pressed.connect(func() -> void:
		if _picker_callback.is_valid() and _card_picker.picked.is_connected(_picker_callback):
			_card_picker.picked.disconnect(_picker_callback)
		_picker_callback = _on_card_picked.bind(entry)
		_card_picker.picked.connect(_picker_callback, CONNECT_ONE_SHOT)
		_card_picker.open(default_tab, allowed_tabs))

	return col

func _on_card_picked(card_name: String, is_advanced: bool, entry: Dictionary) -> void:
	entry["name"] = card_name
	entry["is_advanced"] = is_advanced
	_populate_review_cards()

# ── Confirm sector / calculate ──────────────────────────────────────────────

func _on_confirm_sector_pressed() -> void:
	if _pending.is_empty():
		push_warning("Scan Tableau: no cards to confirm")
		return

	var sector_entry: Dictionary = _pending[0]
	var is_advanced: bool = sector_entry["is_advanced"]
	var sector_name: String = (sector_entry["name"] as String).strip_edges()
	var sector_cd: CardData = CardDatabase.find_sector_by_name(sector_name, is_advanced)
	if sector_cd == null:
		push_warning("Scan Tableau: no valid sector card picked — not adding a sector")
		return

	var techs: Array[CardData] = []
	for i: int in range(1, _pending.size()):
		var name: String = (_pending[i]["name"] as String).strip_edges()
		if name.is_empty():
			continue
		var cd: CardData = CardDatabase.find_any_by_name(name)
		if cd:
			techs.append(cd)
		else:
			push_warning("Scan Tableau: unknown card name '%s', skipped" % name)

	# Tucked cards no longer carry their own identity — face-down ones score
	# as pure counts either way, and face-up ones are entered as a card
	# count plus the total stars printed across them (visible without
	# knowing exactly which cards they are). BotScoring's "Faceup tucked"
	# line just sums every entry's .stars, and other formulas only care
	# about tucked_cards.size(), so it doesn't matter which placeholder
	# entry carries the total as long as the count and the sum are both
	# right — dump it all on the first one.
	var tucked: Array[Dictionary] = []
	var tucked_up_count: int = int(_tucked_up_spinbox.value)
	var tucked_up_stars: int = int(_tucked_up_stars_spinbox.value)
	for i: int in range(tucked_up_count):
		var placeholder := CardData.new()
		placeholder.stars = tucked_up_stars if i == 0 else 0
		tucked.append({"data": placeholder, "face_up": true})
	for i: int in range(int(_tucked_down_spinbox.value)):
		tucked.append({"data": null, "face_up": false})

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
