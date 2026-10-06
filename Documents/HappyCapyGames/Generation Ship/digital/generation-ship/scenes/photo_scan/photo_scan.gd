extends Control
const PopupAnim = preload("res://scripts/popup_anim.gd")

# Photo-scan VP calculator. One photo covers the whole ship: DialReader reads the
# scan-code dial printed around every card's colour orb (the one part of a card
# that stays visible in a real tableau), TableauReader works out each sector's
# archive and stored supply, and the result goes straight into the ship overview
# with its VP total — sectors in table order, each anchored at the bottom with its
# tech stack above it like the in-game ship, an Edit button under each to correct
# it in the review screen. Capture uses the real CameraIntentPlugin (our own CameraX camera screen, torch on)
# on Android (falls back to a plain file picker elsewhere, since the plugin
# only exists in Android builds). Follows the same code-built-UI convention
# as collection_popup.gd / manual_popup.gd (no companion .tscn).

const DialReaderScript := preload("res://scripts/photo_scan/dial_reader.gd")
const CardPickerScript := preload("res://scenes/photo_scan/card_picker.gd")

# A sector always shows exactly 6 slots: 1 sector card + 5 tech/expedition
# (its physical maximum), never fewer or more — unused slots just stay
# blank rather than being added/removed. Review columns are sized to fit
# all 6 across one phone-width screen without horizontal scrolling.
const SECTOR_SLOT_COUNT: int = 6
# Hibernators (a dust sector) stands in for a sector whose dial couldn't be read
const PLACEHOLDER_SECTOR_CODE: int = 450
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

# A SpinBox's own built-in up/down arrows are tiny and don't scale with its
# height — nowhere near big enough to hit reliably on a phone — so every
# counter here pairs one with big dedicated -/+ buttons instead
# (_make_stepper_row) and only relies on the SpinBox itself to hold/display
# the value. The whole row scrolls horizontally (see _build_review_view)
# since 6 supply counters plus 3 tucked ones, each now with 2 extra big
# buttons, no longer fit one phone-width screen at a readable size.
const _SUPPLY_ICON_SIZE: Vector2 = Vector2(36, 36)
const SUPPLY_CONTROL_HEIGHT: float = 72.0
const SUPPLY_FONT_SIZE: int = 22
const SUPPLY_SPIN_WIDTH: float = 56.0
# Half of SUPPLY_SPIN_WIDTH — the tucked counters sit beside the 6 cards in
# their own scrollable row now, and were juuust wide enough to force a
# scrollbar there; the number field itself doesn't need to be as wide as
# the supply row's (it's flanked by big +/- buttons either way).
const TUCKED_SPIN_WIDTH: float = 28.0
const STEPPER_BUTTON_SIZE: float = 72.0
const STEPPER_BUTTON_FONT_SIZE: int = 30
# The archive counters' little card outline ([▲] Archived / [▲] Stars ★ / [▼] Archived).
const TUCKED_ARCHIVE_CARD_SIZE: Vector2 = Vector2(28, 40)
const TUCKED_ARCHIVE_ARROW_SIZE: int = 20

# The ship overview's cards are sized to fit the space there is (all sectors side
# by side, the tallest stack without scrolling), within these limits; SHIP_CARD_*
# is a card's long edge in px. Sector 67x44 mm landscape, tech 44x67 mm portrait.
const SHIP_CARD_MAX: float = 220.0
const SHIP_FIT_SHARE: float = 0.85        # of what would just fit: room to spare, so no scrollbar
const SHIP_CARD_MIN: float = 96.0
# Like a real tableau: each tech covers the top of the one below it, which keeps its
# name strip and orb in view (TECH_SHOWN of its height), and the tech nearest the
# sector covers the sector's top (SECTOR_COVERED of the sector's height).
const SHIP_TECH_SHOWN: float = 0.36
const SHIP_SECTOR_COVERED: float = 0.4
const SHIP_INFO_HEIGHT: float = 136.0     # supply/archive line + Edit button under a sector
const SHIP_ADD_COLUMN: float = 150.0      # the "+ Sector" column
const MAX_SECTORS: int = 6                # a ship never has more
const SHIP_EDIT_HEIGHT: float = 64.0
const SCORE_COMPACT_FONT_SIZE: int = 56
const SUMMARY_SUPPLY_ICON_SIZE: Vector2 = Vector2(44, 44)
const SUMMARY_FONT_SIZE: int = 24
const SUMMARY_ARCHIVE_CARD_SIZE: Vector2 = Vector2(24, 34)   # a little portrait card round the ▲/▼
const SUMMARY_ARCHIVE_ARROW_SIZE: int = 16
const SUMMARY_HOVER_SCALE: Vector2 = Vector2(1.08, 1.08)
const SUMMARY_HOVER_IN_SEC: float = 0.12
const SUMMARY_HOVER_OUT_SEC: float = 0.18
const SCORE_STAR_COLOR: Color = Color(1.0, 0.85, 0.2)
const SCORE_COLOR: Color = Color(0.9, 0.85, 0.7)
# The photo guide shown before the first scan — badge colours as drawn on the picture.
const GUIDE_IMAGE_PATH: String = "res://assets/scan/guide.jpg"
const GUIDE_BADGE_BG: Color = Color8(18, 26, 46)
const GUIDE_BADGE_RIM: Color = Color8(236, 200, 104)
const GUIDE_BADGE_SIZE: float = 52.0
const GUIDE_TIPS: Array[String] = [
	"Hold your phone sideways, straight above the table, and fit your whole ship in the photo.",
	"Keep the ring of lights around each card's orb uncovered.",
	"Give supply tokens a little room and keep them fully visible.",
	"Archived cards go below their sector, face up or face down.",
	"The scan can make mistakes: compare it with Show Photo and fix any sector with Edit.",
]
# badge per tip: the numbers on the picture; the last tip isn't about the picture
const GUIDE_MARKS: Array[String] = ["1", "2", "3", "4", "!"]
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

var _scan_thread: Thread = null           # DialReader running on the current photo
var _scan_progress: ProgressBar = null      # shown while the photo is being read
var _sectors: Array[Dictionary] = []          # board entries confirmed so far, BotScoring-shaped
var _pending: Array[Dictionary] = []          # current in-review cluster's candidates
var _source_image: Image = null               # the one whole-ship photo, kept for supply detection per cluster

var _file_dialog: FileDialog = null
var _list_view: Control = null
var _review_view: Control = null
var _sector_list_box: HBoxContainer = null    # sector columns side by side (see _build_list_view)
var _sector_scroll: ScrollContainer = null
var _results_box: VBoxContainer = null        # VP breakdown, shown in the ship's place
var _guide_box: Control = null                # how to take the photo, until the first scan
var _status_label: Label = null               # scan progress / outcome
# Alliance scores the expeditions of an ally the photo can't show: when the ship
# has it, the player enters that ally's expedition count here.
var _alliance_row: HBoxContainer = null
var _alliance_count_lbl: Label = null
var _alliance_ally_exp: int = 0
const ALLIANCE_MAX_EXPEDITIONS: int = 9
var _leaderboard_btn: Button = null
var _photo_view: TextureRect = null           # the scanned photo, shown in the ship's place to compare
var _photo_btn: Button = null                 # "Show Photo" / "Show Ship"
var _rotate_btn: Button = null                # turns the shown photo, only while it's shown
var _ship_card: float = SHIP_CARD_MAX         # long edge of the overview's cards, see _fit_ship_card()
var _ship_info_boxes: Array[Control] = []     # each sector's supply line, evened out in height
var _ship_archive_boxes: Array[Control] = []  # each sector's archive line, likewise
var _ship_info_height: float = SHIP_INFO_HEIGHT   # what sits under a sector card, as last measured
var _review_cards_box: HBoxContainer = null
var _confirm_btn: Button = null
var _supply_spinboxes: Dictionary = {}        # SupplyColor(int) -> SpinBox
var _tucked_up_spinbox: SpinBox = null       # count of face-up tucked cards
var _tucked_up_stars_spinbox: SpinBox = null # total printed stars across those cards
var _tucked_down_spinbox: SpinBox = null     # count of face-down tucked cards (identity/stars n/a)
var _card_picker: Control = null
var _picker_callback: Callable = Callable()   # armed while a row's Edit flow is waiting on a pick
var _skip_btn: Button = null                  # relabeled "Cancel" while editing an already-confirmed sector


# Replaces the photo preview once Calculate Score is pressed — a big ★
# and the total VP, in the same spot the photo occupied. Reverts back to
# the photo (see _refresh_sector_list) as soon as the board changes, so it
# never sits there showing a stale number after an edit.
var _score_display: Control = null
var _score_total_label: Label = null

# Set while re-opening an already-confirmed sector for editing (via the
# list view's "Edit Sector" button) — the sector is pulled back out of
# _sectors into _pending for the same review screen a fresh scan uses.
# _editing_original_sector is kept aside so Cancel can restore it unchanged.
var _editing_sector_index: int = -1
var _editing_original_sector: Dictionary = {}
var _delete_btn: Button


# The reading thread must always be joined, also when the screen is freed mid-scan.
func _exit_tree() -> void:
	_finish_scan_thread()

func _finish_scan_thread() -> void:
	if _scan_thread and _scan_thread.is_started():
		_scan_thread.wait_to_finish()
	_scan_thread = null

func _ready() -> void:
	_build_ui()
	visible = false

func open() -> void:
	_sectors.clear()
	_source_image = null
	_photo_view.texture = null
	_photo_btn.disabled = true
	_set_view("ship")
	_guide_box.visible = true
	_sector_scroll.visible = false   # the guide takes the ship's place until a photo is in
	_status_label.visible = false
	_alliance_ally_exp = 0
	_editing_sector_index = -1
	_editing_original_sector = {}
	_refresh_sector_list()
	_show_list_view()
	PopupAnim.open(self)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		PopupAnim.close(self)
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
	close_btn.pressed.connect(func() -> void: PopupAnim.close(self))
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

	_guide_box = _build_photo_guide()
	box.add_child(_guide_box)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.visible = false
	box.add_child(_status_label)
	_build_alliance_row(box)
	_scan_progress = ProgressBar.new()
	_scan_progress.custom_minimum_size = Vector2(0, BUTTON_MIN_HEIGHT * 0.5)
	_scan_progress.min_value = 0.0
	_scan_progress.max_value = 100.0
	_scan_progress.show_percentage = false
	_scan_progress.visible = false
	box.add_child(_scan_progress)

	# The ship: sectors side by side in table order, anchored at the bottom like
	# the in-game ship — every sector card on one baseline with its tech stack
	# growing upward, and the view resting at the bottom when the stacks are
	# taller than the screen. The holder fills the scroll area and pushes the row
	# to its bottom while everything fits.
	_sector_scroll = ScrollContainer.new()
	_sector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sector_scroll.resized.connect(_on_ship_area_resized)
	box.add_child(_sector_scroll)
	# The scanned photo takes the ship's place while comparing (Show Photo), whole
	# and scaled to fit — screen space is too tight to show both.
	_photo_view = TextureRect.new()
	_photo_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_photo_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_photo_view.visible = false
	box.add_child(_photo_view)
	# The VP breakdown, also in the ship's place (tap the score) — so opening it never
	# squeezes the ship.
	_results_box = VBoxContainer.new()
	_results_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_results_box.add_theme_constant_override("separation", 6)
	_results_box.visible = false
	box.add_child(_results_box)
	var holder: VBoxContainer = VBoxContainer.new()
	holder.alignment = BoxContainer.ALIGNMENT_END
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sector_scroll.add_child(holder)
	_sector_list_box = HBoxContainer.new()
	_sector_list_box.add_theme_constant_override("separation", 14)
	_sector_list_box.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.add_child(_sector_list_box)

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	box.add_child(btn_row)
	# The ship's VP total ("★ 87"), recalculated whenever the ship changes; tap it
	# for the breakdown.
	_score_display = HBoxContainer.new()
	_score_display.add_theme_constant_override("separation", 8)
	_score_display.mouse_filter = Control.MOUSE_FILTER_STOP
	_score_display.tooltip_text = "Tap for the breakdown"
	_score_display.visible = false
	_score_display.gui_input.connect(func(event: InputEvent) -> void:
		if _is_tap(event):
			_set_view("ship" if _results_box.visible else "breakdown"))
	var star_lbl: Label = Label.new()
	star_lbl.text = "★"
	star_lbl.add_theme_font_size_override("font_size", SCORE_COMPACT_FONT_SIZE)
	star_lbl.add_theme_color_override("font_color", SCORE_STAR_COLOR)
	star_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	star_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_display.add_child(star_lbl)
	_score_total_label = Label.new()
	_score_total_label.add_theme_font_size_override("font_size", SCORE_COMPACT_FONT_SIZE)
	_score_total_label.add_theme_color_override("font_color", SCORE_COLOR)
	_score_total_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_score_total_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_display.add_child(_score_total_label)
	btn_row.add_child(_score_display)
	# The camera plugin only exists in Android builds; elsewhere it's a file picker.
	var scan_btn: Button = _make_button("Take Image" if Engine.has_singleton("CameraIntentPlugin") else "Load Image")
	scan_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scan_btn.pressed.connect(_on_scan_ship_pressed)
	btn_row.add_child(scan_btn)
	_photo_btn = _make_button("Show Photo")
	_photo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_photo_btn.disabled = true
	_photo_btn.pressed.connect(func() -> void: _set_view("ship" if _photo_view.visible else "photo"))
	btn_row.add_child(_photo_btn)
	# Godot ignores the orientation phones store in a JPEG, so a photo can show up
	# sideways; reading it doesn't care, this only turns what's shown.
	_rotate_btn = _make_button("⟳ Rotate")
	_rotate_btn.visible = false
	_rotate_btn.pressed.connect(_rotate_photo)
	btn_row.add_child(_rotate_btn)
	_leaderboard_btn = _make_button("Add to Leaderboard")
	_leaderboard_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_leaderboard_btn.pressed.connect(_on_leaderboard_pressed)
	btn_row.add_child(_leaderboard_btn)

	return box

func _build_review_view() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var hint: Label = _make_hint_label("Every sector always shows 6 slots: the first is the sector, the other 5 are its tech/expedition stack (leave any unused ones blank). Tap Edit to pick a card's real identity from the collection (auto-detected as a starting guess where possible). Stored supply and archived-card counts below are also auto-detected and much less reliable than card identity — check them carefully.")
	box.add_child(hint)

	# The 6 cards never fill the whole screen width, so the tucked-card
	# counters live in that leftover space instead of crowding the supply
	# row below into needing a scrollbar — see _make_tucked_counter.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var cards_row: HBoxContainer = HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 20)
	scroll.add_child(cards_row)
	_review_cards_box = HBoxContainer.new()
	_review_cards_box.add_theme_constant_override("separation", 14)
	cards_row.add_child(_review_cards_box)
	cards_row.add_child(VSeparator.new())
	# label | stepper grid: the label column is as wide as its longest label, so the
	# steppers line up and the block sits right by the separator
	var tucked_col: GridContainer = GridContainer.new()
	tucked_col.columns = 2
	tucked_col.add_theme_constant_override("h_separation", 8)
	tucked_col.add_theme_constant_override("v_separation", 12)
	tucked_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cards_row.add_child(tucked_col)
	_tucked_up_spinbox = _make_tucked_counter(tucked_col, "▲", "Archived")
	_tucked_up_stars_spinbox = _make_tucked_counter(tucked_col, "▲", "Stars ★")
	_tucked_down_spinbox = _make_tucked_counter(tucked_col, "▼", "Archived")

	box.add_child(HSeparator.new())

	var supply_label: Label = _make_hint_label("Stored supply on this sector (auto-detected and much less reliable than card identity — check it carefully):")
	box.add_child(supply_label)
	var supply_row: HBoxContainer = HBoxContainer.new()
	supply_row.add_theme_constant_override("separation", 12)
	box.add_child(supply_row)
	_supply_spinboxes.clear()
	for color: CardData.SupplyColor in _SUPPLY_COLORS:
		var col_box: VBoxContainer = VBoxContainer.new()
		col_box.add_theme_constant_override("separation", 4)
		col_box.alignment = BoxContainer.ALIGNMENT_CENTER
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
		spin.alignment = HORIZONTAL_ALIGNMENT_CENTER
		col_box.add_child(_make_stepper_row(spin))
		supply_row.add_child(col_box)
		_supply_spinboxes[int(color)] = spin

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	box.add_child(btn_row)
	_skip_btn = _make_button("Cancel")
	_skip_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skip_btn.pressed.connect(_on_skip_sector_pressed)
	btn_row.add_child(_skip_btn)
	# only while editing a sector that's already in the ship (e.g. a misread extra one)
	_delete_btn = _make_button("Delete Sector")
	_delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_delete_btn.visible = false
	_delete_btn.pressed.connect(_on_delete_sector_pressed)
	btn_row.add_child(_delete_btn)
	_confirm_btn = _make_button("Add Sector")
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

## Before the first photo: an example shot (assets/scan/guide.jpg, made by
## InDesign_Shop/_automation/scan_code/guide.py) with numbered badges, and the
## numbered tips beside it — the picture has no words, so it needs no translating.
func _build_photo_guide() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 28)
	var pic: TextureRect = TextureRect.new()
	pic.texture = load(GUIDE_IMAGE_PATH) as Texture2D
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.size_flags_stretch_ratio = 2.6
	row.add_child(pic)
	var tips: VBoxContainer = VBoxContainer.new()
	tips.alignment = BoxContainer.ALIGNMENT_CENTER
	tips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tips.add_theme_constant_override("separation", 22)
	row.add_child(tips)
	for i: int in GUIDE_TIPS.size():
		var tip: HBoxContainer = HBoxContainer.new()
		tip.add_theme_constant_override("separation", 16)
		var badge: PanelContainer = PanelContainer.new()
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = GUIDE_BADGE_BG
		style.border_color = GUIDE_BADGE_RIM
		style.set_border_width_all(3)
		style.set_corner_radius_all(int(GUIDE_BADGE_SIZE / 2.0))
		badge.add_theme_stylebox_override("panel", style)
		badge.custom_minimum_size = Vector2(GUIDE_BADGE_SIZE, GUIDE_BADGE_SIZE)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var num: Label = Label.new()
		num.text = GUIDE_MARKS[i]
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		num.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
		badge.add_child(num)
		tip.add_child(badge)
		var text: Label = _make_hint_label(GUIDE_TIPS[i])
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tip.add_child(text)
		tips.add_child(tip)
	return row

func _make_hint_label(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	return lbl

## True for an actual click/tap (left or right press) — NOT for a mouse
## wheel scroll, which Godot also delivers as an InputEventMouseButton with
## pressed=true (button_index MOUSE_BUTTON_WHEEL_UP/DOWN), so a plain
## "is InputEventMouseButton and pressed" check would wrongly fire on
## scrolling over the control too (this is exactly how the photo preview's
## tap-to-enlarge used to trigger just from scrolling past it).
func _is_tap(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false
	var mb: InputEventMouseButton = event as InputEventMouseButton
	return mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT)

## Built as label-then-stepper, stacked vertically 3-high in the leftover
## space beside the 6 review cards (rather than side by side in the supply
## row, which would need the full extra width all over again).
func _make_tucked_counter(parent: GridContainer, arrow: String, label_text: String) -> SpinBox:
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(_make_archive_card(arrow, TUCKED_ARCHIVE_CARD_SIZE, TUCKED_ARCHIVE_ARROW_SIZE))
	var lbl: Label = Label.new()
	lbl.text = label_text
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", SUPPLY_FONT_SIZE)
	head.add_child(lbl)
	parent.add_child(head)
	var spin: SpinBox = SpinBox.new()
	spin.min_value = 0
	spin.max_value = 99
	spin.custom_minimum_size = Vector2(TUCKED_SPIN_WIDTH, SUPPLY_CONTROL_HEIGHT)
	spin.get_line_edit().add_theme_font_size_override("font_size", SUPPLY_FONT_SIZE)
	spin.alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(_make_stepper_row(spin))
	return spin

## A SpinBox's own up/down arrows are too small to hit reliably on a phone
## (see the const block above), so every counter on this screen pairs one
## with a big dedicated -/+ button instead — the SpinBox itself just holds
## and displays the value, clamped the same way tapping its own arrows would.
func _make_stepper_row(spin: SpinBox) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var minus_btn: Button = _make_stepper_button("−")
	minus_btn.pressed.connect(func(): spin.value = maxf(spin.min_value, spin.value - 1.0))
	row.add_child(minus_btn)
	row.add_child(spin)
	var plus_btn: Button = _make_stepper_button("+")
	plus_btn.pressed.connect(func(): spin.value = minf(spin.max_value, spin.value + 1.0))
	row.add_child(plus_btn)
	return row

func _build_alliance_row(box: VBoxContainer) -> void:
	_alliance_row = HBoxContainer.new()
	_alliance_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_alliance_row.add_theme_constant_override("separation", 12)
	_alliance_row.visible = false
	box.add_child(_alliance_row)
	var lbl: Label = Label.new()
	lbl.text = tr("Alliance detected! Choose an ally — how many expeditions do they have?")
	lbl.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	lbl.add_theme_color_override("font_color", SCORE_STAR_COLOR)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_alliance_row.add_child(lbl)
	var dec: Button = _make_stepper_button("−")
	dec.pressed.connect(func() -> void: _set_alliance_ally(_alliance_ally_exp - 1))
	_alliance_row.add_child(dec)
	_alliance_count_lbl = Label.new()
	_alliance_count_lbl.custom_minimum_size = Vector2(STEPPER_BUTTON_SIZE, 0)
	_alliance_count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alliance_count_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_alliance_count_lbl.add_theme_font_size_override("font_size", STEPPER_BUTTON_FONT_SIZE)
	_alliance_row.add_child(_alliance_count_lbl)
	var inc: Button = _make_stepper_button("+")
	inc.pressed.connect(func() -> void: _set_alliance_ally(_alliance_ally_exp + 1))
	_alliance_row.add_child(inc)

func _set_alliance_ally(n: int) -> void:
	_alliance_ally_exp = clampi(n, 0, ALLIANCE_MAX_EXPEDITIONS)
	_update_score()

# Shows the Alliance row only when the ship has Alliance, and scores it with the
# ally's count entered there (0 otherwise).
func _apply_alliance() -> void:
	var has_alliance: bool = false
	for e: Dictionary in _sectors:
		for cd: CardData in (e["techs"] as Array):
			if cd and cd.card_name == "Alliance":
				has_alliance = true
	_alliance_row.visible = has_alliance
	_alliance_count_lbl.text = str(_alliance_ally_exp)
	Scoring.other_players_expeditions = _alliance_ally_exp if has_alliance else 0

func _make_stepper_button(label: String) -> Button:
	var btn: Button = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(STEPPER_BUTTON_SIZE, STEPPER_BUTTON_SIZE)
	btn.add_theme_font_size_override("font_size", STEPPER_BUTTON_FONT_SIZE)
	GameTheme.apply_to_button(btn)
	return btn

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

# ── Calibration logging ──────────────────────────────────────────────────────

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
		# shown on our own camera screen (builds before it have no set_hint)
		if plugin.has_method("set_hint"):
			plugin.set_hint(tr("SCAN_CAMERA_HINT"))
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
	_photo_view.texture = ImageTexture.create_from_image(img)
	_photo_btn.disabled = false
	_set_view("ship")
	# Cards are identified by the scan-code dial printed around each card's
	# colour orb (DialReader) — the only part of a card that stays visible in
	# a real tableau. Read on a thread: a full photo takes a few seconds.
	_guide_box.visible = false
	_sector_scroll.visible = true
	_status_label.visible = true
	_status_label.text = "Reading cards…"
	var reader: DialReader = DialReaderScript.create()
	_finish_scan_thread()            # a previous photo still being read
	var thread: Thread = Thread.new()
	_scan_thread = thread
	thread.start(reader.run.bind(img))
	_scan_progress.value = 0.0
	_scan_progress.visible = true
	while thread.is_alive():
		await get_tree().process_frame
		if not is_inside_tree():
			return                       # _exit_tree() joined the thread
		_scan_progress.value = reader.progress * 100.0
		var pct: int = roundi(reader.progress * 100.0)
		_status_label.text = ("Reading cards… %d%%" % pct) if reader.attempt == 1 else ("Looking closer… %d%%" % pct)
	_scan_progress.visible = false
	if _scan_thread != thread:
		return
	_scan_thread = null
	var dials: Array[Dictionary] = thread.wait_to_finish()
	if _source_image != img:
		return   # another photo was picked meanwhile
	# Second step: what belongs to each sector — archived cards (face-up ones by their
	# dial, face-down ones by their backs) and stored-supply tokens. Card art is
	# loaded here on the main thread, the counting runs on a thread.
	var tableau: TableauReader = TableauReader.create(dials)
	# a column whose sector dial is covered gets this placeholder sector (fix it with Edit)
	tableau.placeholder_card = CardDatabase.find_by_scan_code(PLACEHOLDER_SECTOR_CODE).get("card") as CardData
	var thread2: Thread = Thread.new()
	_scan_thread = thread2
	thread2.start(tableau.analyze.bind(reader.photo, dials, reader.markers))
	_scan_progress.value = 0.0
	_scan_progress.visible = true
	while thread2.is_alive():
		await get_tree().process_frame
		if not is_inside_tree():
			return                       # _exit_tree() joined the thread
		_scan_progress.value = tableau.progress * 100.0
		_status_label.text = "Counting archive & supply… %d%%" % roundi(tableau.progress * 100.0)
	_scan_progress.visible = false
	if _scan_thread != thread2:
		return
	_scan_thread = null
	var groups: Array = thread2.wait_to_finish()
	if _source_image != img:
		return
	# Everything recognised goes straight into the ship (a new photo is a new ship);
	# Edit under a sector corrects it.
	_sectors.clear()
	var loose: int = 0
	var placeholders: int = 0
	for g: Array in groups:
		if not (g[0] as Dictionary).is_empty() and bool((g[0] as Dictionary).get("placeholder", false)):
			placeholders += 1
		var entry: Dictionary = _sector_entry_from_group(g)
		if entry.is_empty():
			loose += g.size() - 1
		else:
			_sectors.append(entry)
	if _sectors.is_empty():
		push_warning("Scan Tableau: no sector cards found in that photo")
		_status_label.text = "No sectors found — move closer so the ship fills the photo"
	else:
		var read: int = _sectors.size() - placeholders
		_status_label.text = "%d sector%s found" % [read, "" if read == 1 else "s"]
		if loose > 0:
			_status_label.text += " · %d card%s not next to a sector left out" % [loose, "" if loose == 1 else "s"]
		if placeholders > 0:
			_status_label.text += " · %d more with the light ring covered, added as Hibernators — fix with Edit" % placeholders
	_refresh_sector_list()

## A recognised group ([sector, techs…] from TableauReader, sector {} if none was
## read) as a ship entry, BotScoring-shaped. {} for a group without a sector.
func _sector_entry_from_group(g: Array) -> Dictionary:
	var sd: Dictionary = g[0]
	if sd.is_empty():
		return {}
	var techs: Array[CardData] = []
	for i: int in range(1, g.size()):
		if techs.size() >= SECTOR_SLOT_COUNT - 1:
			push_warning("Scan Tableau: more cards than a sector can hold — dropping the extras")
			break
		techs.append((g[i] as Dictionary)["card"])
	var tucked: Array[Dictionary] = []
	for d: Dictionary in (sd.get("archived_up", []) as Array):
		tucked.append({"data": d["card"], "face_up": true})
	for i: int in int(sd.get("archived_down", 0)):
		tucked.append({"data": null, "face_up": false})
	var stored: Dictionary = {}
	var supply: Dictionary = sd.get("supply", {})
	for color_int: int in supply:
		if int(supply[color_int]) > 0:
			stored[color_int] = int(supply[color_int])
	return {
		"sector": sd["card"],
		"is_advanced": bool(sd.get("is_advanced", false)),
		"techs": techs,
		"tucked_cards": tucked,
		"stored_supply": stored,
	}

## The edited sector was already taken out of _sectors by Edit, so deleting just
## drops it instead of putting it back.
func _on_delete_sector_pressed() -> void:
	_editing_sector_index = -1
	_editing_original_sector = {}
	_confirm_btn.text = "Add Sector"
	_delete_btn.visible = false
	_refresh_sector_list()
	_show_list_view()

func _on_skip_sector_pressed() -> void:
	if _editing_sector_index >= 0:
		_sectors.insert(_editing_sector_index, _editing_original_sector)
		_editing_sector_index = -1
		_editing_original_sector = {}
		_confirm_btn.text = "Add Sector"
		_delete_btn.visible = false
		_skip_btn.text = "Cancel"
		_refresh_sector_list()
		_show_list_view()
		return
	_show_list_view()

## Lets the user build a sector entirely by hand ("+ Sector") — always the full
## 6 blank slots (1 sector + 5 tech/expedition).
func _on_add_sector_pressed() -> void:
	_pending = []
	for i: int in range(SECTOR_SLOT_COUNT):
		_pending.append(_blank_entry())
	for color_int: int in _supply_spinboxes:
		(_supply_spinboxes[color_int] as SpinBox).value = 0
	_tucked_up_spinbox.value = 0
	_tucked_up_stars_spinbox.value = 0
	_tucked_down_spinbox.value = 0
	_delete_btn.visible = false
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

	# Just "Sector" / "Tech / Exp." — no Dust/Advanced suffix. That distinction
	# is still fully tracked (via entry["is_advanced"], set by which CardPicker
	# tab the sector was picked from) and visible in the card art itself; the
	# longer "Sector (Advanced)" text used to widen this one column past
	# REVIEW_COL_WIDTH whenever an advanced sector was picked, which pushed
	# the whole row wide enough to need a horizontal scrollbar.
	var role_label: Label = Label.new()
	role_label.text = "Sector" if is_sector else "Tech / Exp."
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
		var card_name: String = (_pending[i]["name"] as String).strip_edges()
		if card_name.is_empty():
			continue
		var cd: CardData = CardDatabase.find_any_by_name(card_name)
		if cd:
			techs.append(cd)
		else:
			push_warning("Scan Tableau: unknown card name '%s', skipped" % card_name)

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

	var new_sector: Dictionary = {
		"sector": sector_cd,
		"is_advanced": is_advanced,
		"techs": techs,
		"tucked_cards": tucked,
		"stored_supply": stored,
	}
	if _editing_sector_index >= 0:
		_sectors.insert(_editing_sector_index, new_sector)
		_editing_sector_index = -1
		_editing_original_sector = {}
		_confirm_btn.text = "Add Sector"
		_delete_btn.visible = false
		_skip_btn.text = "Cancel"
		_refresh_sector_list()
		# Never auto-chain into a pending cluster queue after finishing an
		# edit — editing an already-confirmed sector is a separate action
		# from scanning, and should always land back on the list view
		# regardless of what's still queued there.
		_show_list_view()
		return
	_sectors.append(new_sector)
	_refresh_sector_list()
	_show_list_view()

func _refresh_sector_list() -> void:
	_fit_ship_card()
	for child: Node in _sector_list_box.get_children():
		_sector_list_box.remove_child(child)
		child.queue_free()
	_ship_info_boxes.clear()
	_ship_archive_boxes.clear()
	for i: int in _sectors.size():
		_sector_list_box.add_child(_build_sector_summary_row(_sectors[i], i))
	# a sector the scan missed (dial covered, say) can still be added by hand — until
	# the ship is full
	if _sectors.size() < MAX_SECTORS:
		_add_sector_column()
	_update_score()
	_even_out_info_lines()
	_scroll_ship_to_bottom()

func _add_sector_column() -> void:
	var add_col: VBoxContainer = VBoxContainer.new()
	add_col.size_flags_vertical = Control.SIZE_SHRINK_END
	add_col.custom_minimum_size = Vector2(SHIP_ADD_COLUMN - 14.0, 0)
	var add_btn: Button = _make_button("+ Sector")
	add_btn.custom_minimum_size = Vector2(0, SHIP_EDIT_HEIGHT)   # in line with the Edit buttons
	add_btn.pressed.connect(_on_add_sector_pressed)
	add_col.add_child(add_btn)
	_sector_list_box.add_child(add_col)

# Card size for the overview: as big as fits — every sector side by side across the
# width, the tallest stack (plus its info + Edit) within the height.
func _fit_ship_card() -> void:
	var area: Vector2 = _sector_scroll.size if is_instance_valid(_sector_scroll) else Vector2.ZERO
	if area.x <= 0.0 or area.y <= 0.0:
		_ship_card = SHIP_CARD_MAX
		return
	var n: int = maxi(1, _sectors.size())
	var add_w: float = SHIP_ADD_COLUMN if _sectors.size() < MAX_SECTORS else 0.0
	var by_width: float = (area.x - add_w - 14.0 * n - 8.0) / n
	var most_techs: int = 0
	for e: Dictionary in _sectors:
		most_techs = maxi(most_techs, (e["techs"] as Array).size())
	var by_height: float = (area.y - _ship_info_height - 8.0) / _ship_stack_factor(most_techs)
	_ship_card = clampf(minf(by_width, by_height) * SHIP_FIT_SHARE, SHIP_CARD_MIN, SHIP_CARD_MAX)

# Height of a sector with `techs` cards stacked on it, per px of card long edge.
static func _ship_stack_factor(techs: int) -> float:
	var sector_h: float = 44.0 / 67.0
	if techs == 0:
		return sector_h
	return sector_h + (1.0 - SHIP_SECTOR_COVERED * sector_h) + (techs - 1) * SHIP_TECH_SHOWN

# Re-fit when the space changes (window resized, rotation) — only on a real width
# or height change, since rebuilding the columns resizes nothing outside them.
func _on_ship_area_resized() -> void:
	if _sectors.is_empty() or not visible or not _sector_scroll.visible:
		return
	var old: float = _ship_card
	_fit_ship_card()
	if absf(_ship_card - old) > 4.0:
		_refresh_sector_list()

# Every sector's supply/archive line gets the height of the tallest one, so the
# sector cards above them all sit on one line (more badges would otherwise lift
# a sector). Needs a layout pass first: a wrapping line's height depends on width.
func _even_out_info_lines() -> void:
	var lines: Array = [_ship_info_boxes, _ship_archive_boxes]
	for group: Array in lines:
		for box: Control in group:
			box.custom_minimum_size.y = 0.0
	await get_tree().process_frame
	var total: float = 0.0
	for group: Array in lines:
		var tallest: float = 0.0
		for box: Control in group:
			if is_instance_valid(box):
				tallest = maxf(tallest, box.size.y)
		for box: Control in group:
			if is_instance_valid(box):
				box.custom_minimum_size.y = tallest
		total += tallest
	# Fit with what's really under a sector (supply + archive lines, Edit, gaps) rather
	# than the estimate, so the ship never needs a scrollbar: refit once if it's off.
	var measured: float = total + SHIP_EDIT_HEIGHT + 12.0   # + the gaps between them
	if not _sectors.is_empty() and measured > _ship_info_height + 4.0:
		_ship_info_height = measured
		_refresh_sector_list()

# What fills the main area: "ship" (the overview), "photo" (the scanned photo, to
# compare) or "breakdown" (the VP lines). One at a time, so none squeezes another.
func _set_view(view: String) -> void:
	_sector_scroll.visible = view == "ship"
	_photo_view.visible = view == "photo"
	_results_box.visible = view == "breakdown"
	_rotate_btn.visible = view == "photo"
	_photo_btn.text = "Show Ship" if view == "photo" else "Show Photo"

# Turns the shown photo 90 degrees clockwise (display only).
func _rotate_photo() -> void:
	var tex: Texture2D = _photo_view.texture
	if tex == null:
		return
	var img: Image = tex.get_image()
	img.rotate_90(CLOCKWISE)
	_photo_view.texture = ImageTexture.create_from_image(img)

# Rests the ship view at the bottom (the sectors' baseline), like the in-game
# ship — once the new columns have been laid out.
func _scroll_ship_to_bottom() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(_sector_scroll):
		_sector_scroll.scroll_vertical = int(_sector_scroll.get_v_scroll_bar().max_value)

## A confirmed sector's column on the list view — sectors run left to right
## (up to 6, a ship's physical max), each one's own card stack running
## vertically underneath it (sector card, then its tech/expedition stack),
## matching the real board's layout instead of a flat text summary. Real
## art throughout (same source images the review screen and CardPicker
## use), plus supply icons and tuck counts, with an Edit button to reopen
## it in the review screen.
func _build_sector_summary_row(entry: Dictionary, index: int) -> Control:
	var long_px: float = _ship_card
	var short_px: float = roundf(long_px * 44.0 / 67.0)
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	outer.custom_minimum_size = Vector2(long_px, 0)
	outer.size_flags_vertical = Control.SIZE_SHRINK_END   # sector cards on one baseline

	var sector_cd: CardData = entry["sector"]
	var is_advanced: bool = entry["is_advanced"]
	# No header label (wrapping names broke the row alignment); the name is the
	# sector card's tooltip.
	var sector_name: String = sector_cd.adv_name if (is_advanced and not sector_cd.adv_name.is_empty()) else sector_cd.card_name

	# Laid out like the real tableau: the sector at the bottom, the tech nearest it
	# covering its top, each further tech covering the top of the one below it, so
	# every tech keeps its name strip and orb in view and the outermost one is
	# whole. Placed by hand (a box container can't overlap by different amounts);
	# z_index puts further techs on top.
	var techs: Array = entry["techs"]
	var sector_h: float = short_px
	var tech_size: Vector2 = Vector2(short_px, long_px)
	var stack_h: float = roundf(long_px * _ship_stack_factor(techs.size()))
	var stack: Control = Control.new()
	stack.custom_minimum_size = Vector2(long_px, stack_h)
	stack.mouse_filter = Control.MOUSE_FILTER_PASS
	outer.add_child(stack)
	var sector_art: String = sector_cd.adv_local_art_path if is_advanced else sector_cd.local_art_path
	var sector_thumb: TextureRect = _make_summary_thumb(sector_art, "%d. %s" % [index + 1, sector_name], Vector2(long_px, sector_h))
	stack.add_child(sector_thumb)
	sector_thumb.position = Vector2(0.0, stack_h - sector_h)   # after add_child, so layout can't override it
	sector_thumb.size = Vector2(long_px, sector_h)
	var tech_x: float = roundf((long_px - short_px) * 0.3)
	var y: float = stack_h - sector_h - long_px + SHIP_SECTOR_COVERED * sector_h
	for k: int in techs.size():
		var cd: CardData = techs[k]
		var thumb: TextureRect = _make_summary_thumb(cd.local_art_path, cd.card_name, tech_size, k + 1)
		stack.add_child(thumb)
		thumb.position = Vector2(tech_x, roundf(y))
		thumb.size = tech_size
		y -= SHIP_TECH_SHOWN * long_px

	# stored supply, then archived cards on a line of their own, then Edit
	var info: HFlowContainer = HFlowContainer.new()
	info.alignment = FlowContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("h_separation", 10)
	outer.add_child(info)
	_ship_info_boxes.append(info)
	var archive: HFlowContainer = HFlowContainer.new()
	archive.alignment = FlowContainer.ALIGNMENT_CENTER
	archive.add_theme_constant_override("h_separation", 10)
	outer.add_child(archive)
	_ship_archive_boxes.append(archive)
	var stored: Dictionary = entry["stored_supply"]
	for color_int: int in stored:
		if int(stored[color_int]) > 0:
			info.add_child(_make_summary_supply_badge(color_int, int(stored[color_int])))
	var up_count: int = 0
	var up_stars: int = 0
	var down_count: int = 0
	for t: Dictionary in (entry["tucked_cards"] as Array):
		if t["face_up"]:
			up_count += 1
			var tcd: CardData = t.get("data")
			if tcd:
				up_stars += tcd.stars
		else:
			down_count += 1
	if up_count > 0:
		archive.add_child(_make_summary_archive_badge("▲", "%d ★%d" % [up_count, up_stars]))
	if down_count > 0:
		archive.add_child(_make_summary_archive_badge("▼", str(down_count)))

	var edit_btn: Button = _make_button("Edit")
	edit_btn.custom_minimum_size = Vector2(0, SHIP_EDIT_HEIGHT)
	edit_btn.pressed.connect(_on_edit_sector_pressed.bind(index))
	outer.add_child(edit_btn)
	return outer

func _make_summary_thumb(art_path: String, tooltip: String, thumb_size: Vector2, base_z: int = 0) -> TextureRect:
	var thumb: TextureRect = TextureRect.new()
	if not art_path.is_empty():
		thumb.texture = load(art_path) as Texture2D
	thumb.custom_minimum_size = thumb_size
	thumb.z_index = base_z
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.mouse_filter = Control.MOUSE_FILTER_PASS
	thumb.tooltip_text = tooltip
	thumb.pivot_offset = thumb_size / 2.0

	# Cards overlap in their stack (see _build_sector_summary_row), so whichever one
	# was added last always draws on top regardless of which one you're
	# actually looking at — z_index (not just sibling order) is what
	# actually controls draw order, so hovering bumps it above every
	# neighbor, plus a small scale-up so it's obvious which card responded.
	# Stays elevated through the shrink-back tween on exit (reset via
	# tween_callback once it's actually done) so it doesn't visually duck
	# back behind a neighbor mid-animation.
	var hover_tween_cell: Array = [null]
	thumb.mouse_entered.connect(func() -> void:
		thumb.z_index = 50
		if hover_tween_cell[0] and (hover_tween_cell[0] as Tween).is_valid():
			(hover_tween_cell[0] as Tween).kill()
		var tw: Tween = thumb.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(thumb, "scale", SUMMARY_HOVER_SCALE, SUMMARY_HOVER_IN_SEC)
		hover_tween_cell[0] = tw)
	thumb.mouse_exited.connect(func() -> void:
		if hover_tween_cell[0] and (hover_tween_cell[0] as Tween).is_valid():
			(hover_tween_cell[0] as Tween).kill()
		var tw: Tween = thumb.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(thumb, "scale", Vector2.ONE, SUMMARY_HOVER_OUT_SEC)
		tw.tween_callback(func(): thumb.z_index = base_z)
		hover_tween_cell[0] = tw)
	return thumb

func _make_summary_supply_badge(color_int: int, amount: int) -> Control:
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon: TextureRect = TextureRect.new()
	icon.texture = load(_SUPPLY_ICON_PATHS[color_int]) as Texture2D
	icon.custom_minimum_size = SUMMARY_SUPPLY_ICON_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	box.add_child(icon)
	var lbl: Label = _make_summary_text_badge(str(amount))
	box.add_child(lbl)
	return box

## Archived cards: the face-up/face-down arrow inside a little card outline, then the count.
func _make_summary_archive_badge(arrow: String, text: String) -> Control:
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_make_archive_card(arrow, SUMMARY_ARCHIVE_CARD_SIZE, SUMMARY_ARCHIVE_ARROW_SIZE))
	box.add_child(_make_summary_text_badge(text))
	return box

## A little portrait card outline with ▲ (face up) or ▼ (face down) in it.
func _make_archive_card(arrow: String, card_size: Vector2, arrow_size: int) -> Control:
	var card: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = Color(1, 1, 1, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = card_size
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var lbl: Label = Label.new()
	lbl.text = arrow
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", arrow_size)
	card.add_child(lbl)
	return card

func _make_summary_text_badge(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", SUMMARY_FONT_SIZE)
	return lbl

## Pulls a confirmed sector back out for editing: removed from _sectors (so
## the list doesn't show it twice while it's being edited) and reconstructed
## into the same 6-slot _pending shape a fresh scan/add would build, with
## supply/tucked fields pre-filled from what it was confirmed as. Cancel
## restores _editing_original_sector unchanged; Confirm re-inserts whatever
## it's edited to at the same index.
func _on_edit_sector_pressed(index: int) -> void:
	_set_view("ship")
	_editing_sector_index = index
	_editing_original_sector = _sectors[index]
	_sectors.remove_at(index)
	_pending = _rebuild_pending_from_sector(_editing_original_sector)

	var stored: Dictionary = _editing_original_sector.get("stored_supply", {})
	for color_int: int in _supply_spinboxes:
		(_supply_spinboxes[color_int] as SpinBox).value = int(stored.get(color_int, 0))
	var up_count: int = 0
	var up_stars: int = 0
	var down_count: int = 0
	for t: Dictionary in (_editing_original_sector.get("tucked_cards", []) as Array):
		if t["face_up"]:
			up_count += 1
			var tcd: CardData = t.get("data")
			if tcd:
				up_stars += tcd.stars
		else:
			down_count += 1
	_tucked_up_spinbox.value = up_count
	_tucked_up_stars_spinbox.value = up_stars
	_tucked_down_spinbox.value = down_count

	_confirm_btn.text = "Save Changes"
	_skip_btn.text = "Cancel"
	_delete_btn.visible = true
	_populate_review_cards()
	_show_review_view()

func _rebuild_pending_from_sector(sector_entry: Dictionary) -> Array[Dictionary]:
	var pending: Array[Dictionary] = []
	var sector_cd: CardData = sector_entry["sector"]
	var is_advanced: bool = sector_entry["is_advanced"]
	var sector_name: String = sector_cd.adv_name if is_advanced else sector_cd.card_name
	pending.append({"thumbnail": null, "name": sector_name, "is_advanced": is_advanced})
	for cd: CardData in (sector_entry["techs"] as Array):
		pending.append({"thumbnail": null, "name": cd.card_name, "is_advanced": false})
	while pending.size() < SECTOR_SLOT_COUNT:
		pending.append(_blank_entry())
	return pending

# The ship's VP total and breakdown, shown whenever there's a ship; any change
# to the ship makes it submittable again.
func _update_score() -> void:
	for child: Node in _results_box.get_children():
		_results_box.remove_child(child)
		child.queue_free()
	_score_display.visible = not _sectors.is_empty()
	if _sectors.is_empty() and _results_box.visible:
		_set_view("ship")
	_leaderboard_btn.disabled = _sectors.is_empty()
	_leaderboard_btn.text = "Add to Leaderboard"
	if _sectors.is_empty():
		_alliance_row.visible = false
		return
	_apply_alliance()
	for line: Dictionary in BotScoring.board_vp_lines(_sectors):
		var lbl: Label = Label.new()
		lbl.text = "%s: %d" % [line["label"], line["vp"]]
		lbl.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_results_box.add_child(lbl)
	_score_total_label.text = str(BotScoring.board_vp(_sectors))

# Same submission as the end of a real game (main.gd _game_over): total plus the
# packed breakdown. The server keeps each player's best.
func _on_leaderboard_pressed() -> void:
	if _sectors.is_empty():
		return
	_apply_alliance()
	var lines: Array[Dictionary] = BotScoring.board_vp_lines(_sectors)
	_leaderboard_btn.disabled = true
	_leaderboard_btn.text = "Adding…"
	if not LeaderboardManager.score_uploaded.is_connected(_on_score_uploaded):
		LeaderboardManager.score_uploaded.connect(_on_score_uploaded, CONNECT_ONE_SHOT)
	LeaderboardManager.submit_score(BotScoring.board_vp(_sectors), ScoringSnapshotCodec.encode_lines(lines),
		LeaderboardManager.SOURCE_SCAN)

func _on_score_uploaded(success: bool) -> void:
	if success:
		_leaderboard_btn.text = "Added to Leaderboard ✓"
	else:
		_leaderboard_btn.text = "Upload failed — try again"
		_leaderboard_btn.disabled = false
