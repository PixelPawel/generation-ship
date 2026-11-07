extends Control
const PopupAnim = preload("res://scripts/popup_anim.gd")

# Photo-scan VP calculator. One photo covers the whole ship: DialReader reads the
# scan-code dial printed around every card's colour orb (the one part of a card
# that stays visible in a real tableau), TableauReader works out each sector's
# archive and stored supply, and the result goes straight into the ship overview
# with its VP total — sectors in table order, each anchored at the bottom with its
# tech stack above it like the in-game ship.
#
# 2026-11-06 redesign (mockups in Docs/Scan Tableau/ui_mockup): one screen, no separate editing
# screen. The ship is edited by touching it: a tapped card lifts with a gold edge and the strip at
# the bottom offers Change / Remove; "+" slots on top of every stack and at the end of the row add
# cards and sectors; a sector's tokens and its archive open small trays right there (tap a token to
# add one; face-up archived cards are picked as the real cards, so their stars count by themselves).
# The rail on the left holds the score (tap: the breakdown), the photo (tap: compare) and the
# capture buttons. Names, captions and the status line are set in Myriad (the theme's Ethnocentric
# stays for the title, score and buttons: it reads badly at small sizes).
# Capture uses the real CameraIntentPlugin on Android (our camera screen, the phone's camera app,
# the gallery); elsewhere a plain file picker. Code-built UI like collection_popup.gd (no .tscn).

const DialReaderScript := preload("res://scripts/photo_scan/dial_reader.gd")
const SETTINGS_PATH: String = "user://settings.cfg"
const CardPickerScript := preload("res://scenes/photo_scan/card_picker.gd")

const MAX_TECHS: int = 5                  # a sector holds its sector card + 5 tech/expedition cards
const MAX_SECTORS: int = 6                # a ship never has more
# Hibernators (a dust sector) stands in for a sector whose dial couldn't be read
const PLACEHOLDER_SECTOR_CODE: int = 450

# Sized for touch on a phone (this popup is Android-first, see main_menu.gd); the canvas is 1920x1080.
const TITLE_FONT_SIZE: int = 32
const BUTTON_FONT_SIZE: int = 22
const BUTTON_MIN_HEIGHT: float = 84.0
const BODY_FONT_SIZE: int = 26            # Myriad: status line, names
const SMALL_FONT_SIZE: int = 22
const NAME_FONT_SIZE: int = 32
const SCORE_FONT_SIZE: int = 88
const STEPPER_BUTTON_SIZE: float = 72.0
const STEPPER_BUTTON_FONT_SIZE: int = 30
const RAIL_WIDTH: float = 500.0
const PHOTO_THUMB_HEIGHT: float = 376.0      # a 4:3 photo across the rail
const CAPTURE_BUTTON_HEIGHT: float = 150.0
const CAPTURE_FONT_SIZE: int = 26
const LEADERBOARD_HEIGHT: float = 100.0
const CAPTURE_GLYPH: float = 66.0
const BAR_HEIGHT: float = 104.0           # the strip under the ship (edit actions / hint)

# The ship's cards are sized to fit the space there is (all sectors side by side, the tallest
# stack without scrolling), within these limits; SHIP_CARD_* is a card's long edge in px.
# Sector 67x44 mm landscape, tech 44x67 mm portrait.
const SHIP_CARD_MAX: float = 236.0
const SHIP_FIT_SHARE: float = 0.94        # of what would just fit: room to spare, so no scrollbar
const SHIP_CARD_MIN: float = 96.0
const SHIP_GAP: float = 40.0              # between sector columns
const SHIP_ADD_WIDTH: float = 0.8         # the "+ Sector" slot, x the card's long edge
# Like a real tableau: each tech covers the top of the one below it, which keeps its name strip
# and orb in view (TECH_SHOWN of its height), and the tech nearest the sector covers the sector's
# top (SECTOR_COVERED of the sector's height).
const SHIP_TECH_SHOWN: float = 0.36
const SHIP_SECTOR_COVERED: float = 0.4
const GHOST_SLOT_H: float = 0.24          # the "+" slot on top of a stack, x the long edge
const GHOST_GAP: float = 0.04
const SELECT_LIFT: float = 12.0           # a tapped card rises this far
const SHIP_INFO_HEIGHT: float = 150.0     # tokens + archive under a sector (measured later)
const TOKEN_ICON: float = 50.0
const ARCHIVE_CARD: Vector2 = Vector2(60, 91)
const TRAY_TOKEN: float = 76.0
const TRAY_CARD: Vector2 = Vector2(64, 97)
# a card as the photo shows it: the part a stack leaves in view (a tech's lower CROP_TECH_SHOWN with its
# name strip and orb, a sector's lower part under the techs), upright, at CROP_PPM px per mm
const CROP_PPM: float = 6.0
const CROP_TECH_SHOWN: float = 0.4
const CROP_SECTOR_SHOWN: float = 0.62
const TAP_SLOP: float = 20.0              # a press that moves further is a scroll, not a tap
const SUMMARY_HOVER_SCALE: Vector2 = Vector2(1.06, 1.06)
const SUMMARY_HOVER_IN_SEC: float = 0.12
const SUMMARY_HOVER_OUT_SEC: float = 0.18

# Colours: the game's navy and steel; gold = needs you (a tapped card, a card to check); violet =
# the scan's own (the dial diamond's colour), on the photo.
const CREAM: Color = Color(0.9, 0.85, 0.7)
const MUTED: Color = Color(0.56, 0.6, 0.69)
const GOLD: Color = Color8(236, 200, 104)
const STAR_COLOR: Color = Color(1.0, 0.85, 0.2)
const VIOLET: Color = Color8(150, 80, 175)
const STEEL: Color = Color(0.22, 0.40, 0.65, 0.75)
const STEEL_DIM: Color = Color(0.22, 0.35, 0.55, 0.45)
const GHOST: Color = Color(0.45, 0.55, 0.75, 0.65)
const PANEL_BG: Color = Color(0.055, 0.08, 0.15, 0.97)
const BADGE_DARK: Color = Color(0.1, 0.08, 0.02)

# The photo guide shown before the first scan — badge colours as drawn on the picture.
const GUIDE_IMAGE_PATH: String = "res://assets/scan/guide.jpg"
const GUIDE_BADGE_BG: Color = Color8(18, 26, 46)
const GUIDE_BADGE_RIM: Color = Color8(236, 200, 104)
const GUIDE_BADGE_SIZE: float = 64.0
const GUIDE_TIP_FONT_SIZE: int = 30
const GUIDE_PICTURE_RATIO: float = 1.4
const GUIDE_TIPS: Array[String] = [
	"Hold your phone sideways, straight above the table, and fit your whole ship in the photo.",
	"Keep the ring of lights around each card's orb uncovered.",
	"Give supply tokens a little room and keep them fully visible.",
	"Archived cards go below their sector, face up or face down.",
	"SCAN_TIP_FIX",
]
# badge per tip: the numbers on the picture; the last tip isn't about the picture
const GUIDE_MARKS: Array[String] = ["1", "2", "3", "4", "!"]
# Same res://assets/ui/supply/<Name>.png set supply_ui.gd uses elsewhere — the real token art.
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
const TECH_BACK_PATH: String = "res://assets/cards/Tech/%s/GS Techs Back 44x67mm.png"
const MYRIAD_PATH: String = "res://assets/fonts/Myriad Variable Concept.ttf"

var _scan_thread: Thread = null           # DialReader running on the current photo
var _scan_job: Object = null              # the reader on that thread (DialReader / TableauReader), to cancel it
var _scan_progress: ProgressBar = null      # shown while the photo is being read
var _sectors: Array[Dictionary] = []          # the ship, BotScoring-shaped (+ unsure/unknown flags)
var _source_image: Image = null               # the one whole-ship photo

var _body_font: FontVariation = null          # Myriad semibold, normal width
var _file_dialog: FileDialog = null
var _card_picker: Control = null
var _picker_callback: Callable = Callable()   # armed while a pick is awaited

# the stage: the guide, the ship, the photo or the breakdown, one at a time
var _view: String = "ship"
var _guide_box: Control = null
var _sector_scroll: ScrollContainer = null
var _sector_list_box: HBoxContainer = null    # sector columns side by side
var _photo_view: TextureRect = null
var _results_box: VBoxContainer = null
var _status_badge: Control = null             # the gold "?" before "N cards to check"
var _status_label: Label = null
var _scan_summary: String = ""                # what the last scan found (shown when nothing needs checking)
var _bar: PanelContainer = null               # the strip under the stage
var _bar_style: StyleBoxFlat = null
# the rail
var _score_box: Control = null
var _score_total_label: Label = null
var _photo_box: Control = null
var _photo_thumb: TextureRect = null
var _photo_caption: Label = null
var _leaderboard_btn: Button = null
# Alliance scores the expeditions of an ally the photo can't show: entered here when the ship has it
var _alliance_row: HBoxContainer = null
var _alliance_count_lbl: Label = null
var _alliance_ally_exp: int = 0
const ALLIANCE_MAX_EXPEDITIONS: int = 9

var _ship_card: float = SHIP_CARD_MAX         # long edge of the ship's cards, see _fit_ship_card()
var _ship_info_boxes: Array[Control] = []     # each sector's token line, evened out in height
var _ship_archive_boxes: Array[Control] = []  # each sector's archive line, likewise
var _ship_info_height: float = SHIP_INFO_HEIGHT
# the tapped card: sector index, and -1 for the sector card itself or the tech's index in its stack
var _sel_sector: int = -1
var _sel_tech: int = -1
var _tray: Control = null                     # a sector's token or archive tray while open
var _tray_kind: String = ""
var _tray_sector: int = -1
var _tray_anchor: Rect2 = Rect2()
var _crops: Dictionary = {}                  # photo cut-outs by card position (cleared with each photo)


# The reading thread must always be joined, also when the screen is freed mid-scan.
func _exit_tree() -> void:
	_finish_scan_thread()

# Stops the reading of an earlier photo: tells its reader to give up (it checks between steps),
# then waits for that — waiting for a full read instead froze the game for a minute on a phone
# when a second photo came in right after the first.
func _finish_scan_thread() -> void:
	if _scan_job:
		_scan_job.set("cancelled", true)
	if _scan_thread and _scan_thread.is_started():
		_scan_thread.wait_to_finish()
	_scan_thread = null
	_scan_job = null

func _ready() -> void:
	var myriad: FontFile = load(MYRIAD_PATH) as FontFile
	# Myriad Variable Concept has no Polish ą ć ę ń ś ź ż (nor · … ★): in Polish the theme's
	# Ethnocentric stays, rather than letters patched in from a system font
	if myriad and not TranslationServer.get_locale().begins_with("pl"):
		_body_font = FontVariation.new()
		_body_font.base_font = myriad
		_body_font.variation_opentype = {"wght": 600, "wdth": 100}
	_build_ui()
	visible = false

func open() -> void:
	_close_tray()
	_sel_sector = -1
	_sel_tech = -1
	_sectors.clear()
	_source_image = null
	_scan_summary = ""
	_photo_view.texture = null
	_photo_thumb.texture = null
	_photo_box.visible = false
	_guide_box.visible = true
	_alliance_ally_exp = 0
	_set_view("ship")
	_refresh_sector_list()
	PopupAnim.open(self)

func _input(event: InputEvent) -> void:
	if not visible or _card_picker.visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _tray:
			_close_tray()
		elif _sel_sector >= 0:
			_select(-1, -1)
		else:
			PopupAnim.close(self)
		get_viewport().set_input_as_handled()
		return
	# a press outside an open tray closes it and still does what it was meant for (nothing is
	# rebuilt under it); a press on the tray's own line only closes it
	if _tray and event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var at: Vector2 = get_global_mouse_position()
		if not _tray.get_global_rect().has_point(at):
			var own_line: bool = _tray_line_rect().has_point(at)
			_close_tray()
			if own_line:
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
	vbox.add_theme_constant_override("separation", 14)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(vbox)

	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 18)
	vbox.add_child(title_row)
	var title: Label = Label.new()
	title.text = tr("Scan Tableau").to_upper()
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", CREAM)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(title)
	# what the scan found / the cards to check, beside the title: the ship gets the height
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(24, 0)
	title_row.add_child(gap)
	_build_status(title_row)
	# Android: also put each scan photo in the gallery (off by default; for checking a scan later or
	# sending it in — the photos themselves stay in the app's private files)
	# (no has_method() on a plugin singleton: Godot's Java bridge object doesn't report its
	# methods that way; the plugin ships in the same build, so it has them)
	if Engine.has_singleton("CameraIntentPlugin"):
		var gallery: CheckButton = CheckButton.new()
		gallery.text = "Save photos to gallery"
		gallery.focus_mode = Control.FOCUS_NONE
		_body(gallery, SMALL_FONT_SIZE)
		gallery.add_theme_color_override("font_color", MUTED)
		gallery.button_pressed = _save_to_gallery()
		gallery.toggled.connect(_set_save_to_gallery)
		title_row.add_child(gallery)
	var close_btn: Button = _make_button("✕")
	close_btn.custom_minimum_size = Vector2(BUTTON_MIN_HEIGHT, BUTTON_MIN_HEIGHT)
	close_btn.pressed.connect(func() -> void: PopupAnim.close(self))
	title_row.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	var main_row: HBoxContainer = HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 32)
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(main_row)
	main_row.add_child(_build_rail())
	main_row.add_child(_build_stage())

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = false
	_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg ; Photos"])
	_file_dialog.size = Vector2i(800, 600)
	_file_dialog.file_selected.connect(_on_photo_selected)
	add_child(_file_dialog)

	_card_picker = CardPickerScript.new()
	_card_picker.z_index = 200        # above an open tray
	add_child(_card_picker)

## The rail: the score (tap: the breakdown), the photo (tap: compare), the capture buttons and
## Add to leaderboard at its foot.
func _build_rail() -> Control:
	var rail: VBoxContainer = VBoxContainer.new()
	rail.custom_minimum_size = Vector2(RAIL_WIDTH, 0)
	rail.add_theme_constant_override("separation", 18)

	# score: a big ★ and the total
	var score: VBoxContainer = VBoxContainer.new()
	score.add_theme_constant_override("separation", 0)
	score.mouse_filter = Control.MOUSE_FILTER_STOP
	score.tooltip_text = "Tap for the breakdown"
	score.gui_input.connect(_tap_handler(func() -> void: _set_view("ship" if _view == "breakdown" else "breakdown")))
	var score_row: HBoxContainer = HBoxContainer.new()
	score_row.add_theme_constant_override("separation", 12)
	score_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score.add_child(score_row)
	var star_lbl: Label = Label.new()
	star_lbl.text = "★"
	star_lbl.add_theme_font_size_override("font_size", SCORE_FONT_SIZE)
	star_lbl.add_theme_color_override("font_color", STAR_COLOR)
	star_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	star_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_row.add_child(star_lbl)
	_score_total_label = Label.new()
	_score_total_label.add_theme_font_size_override("font_size", SCORE_FONT_SIZE)
	_score_total_label.add_theme_color_override("font_color", CREAM)
	_score_total_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_score_total_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_row.add_child(_score_total_label)
	var score_hint: Label = _make_label("Tap for the breakdown", SMALL_FONT_SIZE, MUTED)
	score_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score.add_child(score_hint)
	_score_box = score
	rail.add_child(score)

	# the photo, small: tap to compare it with the ship
	var frame: PanelContainer = PanelContainer.new()
	frame.custom_minimum_size = Vector2(0, PHOTO_THUMB_HEIGHT)
	frame.add_theme_stylebox_override("panel", _rounded(Color(0, 0, 0, 0.3), VIOLET, 3, 12, 3))
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.gui_input.connect(_tap_handler(func() -> void: _set_view("ship" if _view == "photo" else "photo")))
	_photo_thumb = TextureRect.new()
	_photo_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_photo_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_photo_thumb)
	var caption_wrap: MarginContainer = MarginContainer.new()
	caption_wrap.add_theme_constant_override("margin_left", 10)
	caption_wrap.add_theme_constant_override("margin_bottom", 10)
	caption_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(caption_wrap)
	var pill: PanelContainer = PanelContainer.new()
	pill.add_theme_stylebox_override("panel", _rounded(Color(0.04, 0.05, 0.1, 0.86), Color(0, 0, 0, 0), 0, 16, 12))
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pill.size_flags_vertical = Control.SIZE_SHRINK_END
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_wrap.add_child(pill)
	_photo_caption = _make_label("SCAN_PHOTO_CAPTION", SMALL_FONT_SIZE, CREAM)
	_photo_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(_photo_caption)
	_photo_box = frame
	rail.add_child(frame)

	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(spacer)

	# capture: picture buttons (Android: our camera, the camera app's Night mode, the gallery)
	var capture: HBoxContainer = HBoxContainer.new()
	capture.add_theme_constant_override("separation", 12)
	rail.add_child(capture)
	if Engine.has_singleton("CameraIntentPlugin"):
		capture.add_child(_make_capture_button("camera", "Camera", _on_scan_ship_pressed))
		capture.add_child(_make_capture_button("night", "Night shot", _on_camera_app_pressed))
		capture.add_child(_make_capture_button("gallery", "Gallery", _on_gallery_pressed))
	else:
		capture.add_child(_make_capture_button("gallery", "Load Image", _on_scan_ship_pressed))

	_leaderboard_btn = _make_button("Add to Leaderboard")
	_leaderboard_btn.custom_minimum_size = Vector2(0, LEADERBOARD_HEIGHT)
	# (a long translation is cut short rather than widening the rail)
	_leaderboard_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_style_gold(_leaderboard_btn)
	_leaderboard_btn.pressed.connect(_on_leaderboard_pressed)
	rail.add_child(_leaderboard_btn)
	return rail

## The stage: the status line, the ship (or the guide, the photo, the breakdown) and the strip.
func _build_stage() -> Control:
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)

	_scan_progress = ProgressBar.new()
	_scan_progress.custom_minimum_size = Vector2(0, 18)
	_scan_progress.min_value = 0.0
	_scan_progress.max_value = 100.0
	_scan_progress.show_percentage = false
	_scan_progress.visible = false
	col.add_child(_scan_progress)

	_guide_box = _build_photo_guide()
	col.add_child(_guide_box)
	# The ship: sectors side by side in table order, anchored at the bottom like the in-game ship —
	# every sector card on one baseline with its tech stack growing upward. The holder fills the
	# scroll area and pushes the row to its bottom while everything fits.
	_sector_scroll = ScrollContainer.new()
	_sector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sector_scroll.resized.connect(_on_ship_area_resized)
	col.add_child(_sector_scroll)
	var holder: VBoxContainer = VBoxContainer.new()
	holder.alignment = BoxContainer.ALIGNMENT_END
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sector_scroll.add_child(holder)
	_sector_list_box = HBoxContainer.new()
	_sector_list_box.add_theme_constant_override("separation", int(SHIP_GAP))
	_sector_list_box.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.add_child(_sector_list_box)
	# the photo, whole, in the ship's place while comparing
	_photo_view = TextureRect.new()
	_photo_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_photo_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_photo_view.visible = false
	col.add_child(_photo_view)
	# the VP breakdown, also in the ship's place (tap the score)
	_results_box = VBoxContainer.new()
	_results_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_results_box.add_theme_constant_override("separation", 6)
	_results_box.visible = false
	col.add_child(_results_box)

	# the strip: what can be done with the tapped card, or a hint
	_bar = PanelContainer.new()
	_bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	_bar_style = _rounded(Color(0.06, 0.09, 0.16, 0.92), STEEL_DIM, 2, 14, 14)
	_bar.add_theme_stylebox_override("panel", _bar_style)
	col.add_child(_bar)
	return col

## The status line: the gold "?" and "N cards to check" (else what the scan found), and the Alliance
## question when the ship has Alliance. In the title row, above the line.
func _build_status(row: HBoxContainer) -> void:
	_status_badge = _make_round_badge("?", 36.0, GOLD, BADGE_DARK)
	_status_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_badge.visible = false
	row.add_child(_status_badge)
	_status_label = _make_label("", BODY_FONT_SIZE, CREAM)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.max_lines_visible = 2          # (see _make_bar_hint)
	row.add_child(_status_label)
	_build_alliance_row(row)

func _make_button(label: String) -> Button:
	var btn: Button = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, BUTTON_MIN_HEIGHT)
	btn.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	GameTheme.apply_to_button(btn)
	return btn

## A label in Myriad (the body face): names, captions, the status line.
func _make_label(text: String, font_size: int, color: Color) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	_body(lbl, font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl

func _body(c: Control, font_size: int) -> void:
	if _body_font:
		c.add_theme_font_override("font", _body_font)
	c.add_theme_font_size_override("font_size", font_size)

static func _rounded(bg: Color, border: Color, border_w: int, radius: int, margin: int = 0) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s

## A gold-edged button (the screen's one call to action).
func _style_gold(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", _rounded(Color(0.06, 0.09, 0.15, 0.9), Color(GOLD, 0.75), 2, 10))
	btn.add_theme_stylebox_override("hover", _rounded(Color(0.12, 0.11, 0.06, 0.95), GOLD, 3, 10))
	btn.add_theme_stylebox_override("pressed", _rounded(Color(0.04, 0.04, 0.03, 1.0), Color(GOLD, 0.8), 2, 10))
	btn.add_theme_stylebox_override("disabled", _rounded(Color(0.04, 0.05, 0.08, 0.5), Color(GOLD, 0.25), 1, 10))
	btn.add_theme_color_override("font_color", GOLD)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.7))
	btn.add_theme_color_override("font_pressed_color", GOLD.darkened(0.15))
	btn.add_theme_color_override("font_disabled_color", Color(GOLD, 0.35))

## A round badge with a glyph ("?" on a card the scan wasn't sure of, the status line's marker).
func _make_round_badge(glyph: String, d: float, bg: Color, fg: Color) -> PanelContainer:
	var badge: PanelContainer = PanelContainer.new()
	badge.add_theme_stylebox_override("panel", _rounded(bg, BADGE_DARK, maxi(1, roundi(d * 0.06)), roundi(d / 2.0)))
	badge.custom_minimum_size = Vector2(d, d)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl: Label = _make_label(glyph, roundi(d * 0.72), fg)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(lbl)
	return badge

## A capture button: a drawn glyph over a short caption.
func _make_capture_button(kind: String, caption: String, on_press: Callable) -> Button:
	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(0, CAPTURE_BUTTON_HEIGHT)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameTheme.apply_to_button(btn)
	btn.pressed.connect(on_press)
	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)
	var glyph: Glyph = Glyph.new()
	glyph.kind = kind
	glyph.custom_minimum_size = Vector2(CAPTURE_GLYPH, CAPTURE_GLYPH)
	glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(glyph)
	var lbl: Label = _make_label(caption, CAPTURE_FONT_SIZE, Color(0.78, 0.88, 1.0))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lbl)
	return btn

## The capture buttons' pictures, drawn (no icon files): a camera, a moon for the Night shot,
## a picture for the gallery.
class Glyph extends Control:
	var kind: String = ""

	func _draw() -> void:
		var c: Color = Color(0.78, 0.88, 1.0)
		var s: Vector2 = size
		var m: Vector2 = s / 2.0
		var u: float = minf(s.x, s.y) / 50.0
		match kind:
			"camera":
				draw_rect(Rect2(m.x - 22 * u, m.y - 13 * u, 44 * u, 31 * u), c, false, 3.0 * u)
				draw_rect(Rect2(m.x - 9 * u, m.y - 19 * u, 18 * u, 6 * u), c, true)
				draw_arc(m + Vector2(0, 2.5 * u), 9 * u, 0.0, TAU, 32, c, 3.0 * u)
			"night":
				draw_circle(m, 19 * u, c)
				draw_circle(m + Vector2(9 * u, -8 * u), 17 * u, Color(0.06, 0.09, 0.15))
			_:
				draw_rect(Rect2(m.x - 22 * u, m.y - 17 * u, 44 * u, 34 * u), c, false, 3.0 * u)
				draw_colored_polygon(PackedVector2Array([m + Vector2(-17, 12) * u, m + Vector2(-4, -4) * u,
					m + Vector2(5, 5) * u, m + Vector2(10, 0) * u, m + Vector2(17, 12) * u]), c)

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
	pic.size_flags_stretch_ratio = GUIDE_PICTURE_RATIO
	row.add_child(pic)
	var tips: VBoxContainer = VBoxContainer.new()
	tips.alignment = BoxContainer.ALIGNMENT_CENTER
	tips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tips.add_theme_constant_override("separation", 20)
	row.add_child(tips)
	var tips_text: Array[String] = []
	tips_text.append_array(GUIDE_TIPS)
	var marks: Array[String] = []
	marks.append_array(GUIDE_MARKS)
	if Engine.has_singleton("CameraIntentPlugin"):
		tips_text.append("SCAN_TIP_NIGHT")      # dim room: the phone's Night mode
		marks.append("!")
	for i: int in tips_text.size():
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
		num.text = marks[i]
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		num.add_theme_font_size_override("font_size", GUIDE_TIP_FONT_SIZE)
		badge.add_child(num)
		tip.add_child(badge)
		var text: Label = _make_label(tips_text[i], GUIDE_TIP_FONT_SIZE, CREAM)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tip.add_child(text)
		tips.add_child(tip)
	return row

## True for an actual click/tap (left or right press) — NOT for a mouse wheel scroll, which
## Godot also delivers as an InputEventMouseButton with pressed=true.
func _is_tap(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false
	var mb: InputEventMouseButton = event as InputEventMouseButton
	return mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT)

## A gui_input handler that calls on_tap for a tap: a left press and release that didn't move
## (a drag that scrolls the ship isn't a tap).
func _tap_handler(on_tap: Callable) -> Callable:
	var down: Array = [Vector2.INF]      # (closures copy plain values: a one-element array as a cell)
	return func(event: InputEvent) -> void:
		if not (event is InputEventMouseButton):
			return
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			down[0] = mb.global_position
			return
		var start: Vector2 = down[0]
		down[0] = Vector2.INF
		if start != Vector2.INF and mb.global_position.distance_to(start) <= TAP_SLOP:
			on_tap.call()

func _build_alliance_row(parent: HBoxContainer) -> void:
	_alliance_row = HBoxContainer.new()
	_alliance_row.add_theme_constant_override("separation", 10)
	_alliance_row.visible = false
	parent.add_child(_alliance_row)
	var lbl: Label = _make_label(tr("Alliance detected! Choose an ally — how many expeditions do they have?"), SMALL_FONT_SIZE, STAR_COLOR)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(360, 0)
	_alliance_row.add_child(lbl)
	var dec: Button = _make_stepper_button("−")
	dec.pressed.connect(func() -> void: _set_alliance_ally(_alliance_ally_exp - 1))
	_alliance_row.add_child(dec)
	_alliance_count_lbl = _make_label("0", STEPPER_BUTTON_FONT_SIZE, CREAM)
	_alliance_count_lbl.custom_minimum_size = Vector2(48, 0)
	_alliance_count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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

# ── Capture -> detect ───────────────────────────────────────────────────────

# The real camera-intent plugin only exists in Android builds (it's Kotlin
# source added directly to android/build/, not a GDExtension, so there's
# nothing to check for on other platforms) — fall back to the file-picker
# stub elsewhere so the rest of the flow stays testable on desktop.
func _on_scan_ship_pressed() -> void:
	if Engine.has_singleton("CameraIntentPlugin"):
		var plugin: Object = _camera_plugin()
		# shown on our own camera screen: the hint on top, the live guidance below, and the tip
		# that replaces the hint where it's dim
		plugin.set_hint(tr("SCAN_CAMERA_HINT"))
		plugin.set_guide("\n".join([tr("SCAN_GUIDE_NONE"), tr("SCAN_GUIDE_CLOSER"), tr("SCAN_GUIDE_STEADY"), tr("SCAN_GUIDE_SHOOTING"), tr("SCAN_TIP_DIM")]))
		plugin.capture_photo()
	else:
		_file_dialog.popup_centered()

## Android: a photo from the gallery (the maker's gallery or the system photo picker), read like a camera shot.
func _on_gallery_pressed() -> void:
	_camera_plugin().pick_photo()

## Android: the phone's camera app (its Night mode); the plugin opens the picker once the
## game is back, and the pick arrives like From Gallery's.
func _on_camera_app_pressed() -> void:
	_camera_plugin().open_camera_app()

func _camera_plugin() -> Object:
	var plugin: Object = Engine.get_singleton("CameraIntentPlugin")
	if not plugin.photo_captured.is_connected(_on_photo_selected):
		plugin.photo_captured.connect(_on_photo_selected)
	if not plugin.photo_canceled.is_connected(_on_photo_canceled):
		plugin.photo_canceled.connect(_on_photo_canceled)
	return plugin

func _on_photo_canceled() -> void:
	pass  # user backed out of the camera — the ship stays as it was

## The camera's own folder keeps only the scan being read: every earlier photo, its burst shots
## and anything half-written stayed there for good (5-10 MB a scan), and a nearly full phone is
## exactly when the camera needs the room. Never touches a photo loaded from anywhere else.
func _clean_capture_folder(path: String) -> void:
	if not _is_camera_photo(path):
		return
	var dir: DirAccess = DirAccess.open(path.get_base_dir())
	if dir == null:
		return
	var keep: String = path.get_file().get_basename()
	for f: String in dir.get_files():
		if not f.begins_with(keep):
			dir.remove(f)

## A photo our camera screen took (the app's private captured_photos folder, Android only) — the
## only kind whose folder and burst shots the scan may delete: on a computer, Load Image could
## pick a photo from any folder, even one that happens to be called captured_photos.
static func _is_camera_photo(path: String) -> bool:
	return Engine.has_singleton("CameraIntentPlugin") and path.contains("/captured_photos/")

func _save_to_gallery() -> bool:
	var cfg: ConfigFile = ConfigFile.new()
	return cfg.load(SETTINGS_PATH) == OK and bool(cfg.get_value("scan", "save_to_gallery", false))

func _set_save_to_gallery(on: bool) -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("scan", "save_to_gallery", on)
	cfg.save(SETTINGS_PATH)

func _on_photo_selected(path: String) -> void:
	# (a gallery pick, the plugin's pick_<time>.jpg copy, is in the gallery already)
	if _save_to_gallery() and Engine.has_singleton("CameraIntentPlugin") and not path.get_file().begins_with("pick_"):
		Engine.get_singleton("CameraIntentPlugin").save_to_gallery(path)
	_clean_capture_folder(path)
	var img := Image.new()
	if img.load(path) != OK:
		push_warning("Scan Tableau: could not load %s" % path)
		return
	_source_image = img
	_crops.clear()
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_photo_view.texture = tex
	_photo_thumb.texture = tex
	_photo_box.visible = true
	_close_tray()
	_sel_sector = -1
	_sel_tech = -1
	# Cards are identified by the scan-code dial printed around each card's
	# colour orb (DialReader) — the only part of a card that stays visible in
	# a real tableau. Read on a thread: a full photo takes a few seconds.
	_guide_box.visible = false
	_set_view("ship")
	_status_badge.visible = false
	_status_label.text = tr("SCAN_READING") % 0
	var t_start: int = Time.get_ticks_msec()
	var reader: DialReader = DialReaderScript.create()
	_finish_scan_thread()            # a previous photo still being read
	var thread: Thread = Thread.new()
	_scan_thread = thread
	_scan_job = reader
	thread.start(reader.run.bind(img))
	_scan_progress.value = 0.0
	_scan_progress.visible = true
	while thread.is_alive():
		await get_tree().process_frame
		if not is_inside_tree():
			return                       # _exit_tree() joined the thread
		_scan_progress.value = reader.progress * 100.0
		var pct: int = roundi(reader.progress * 100.0)
		_status_label.text = (tr("SCAN_READING") % pct) if reader.attempt == 1 else (tr("SCAN_LOOKING") % pct)
	_scan_progress.visible = false
	if _scan_thread != thread:
		return
	_scan_thread = null
	_scan_job = null
	var dials: Array[Dictionary] = thread.wait_to_finish()
	if _source_image != img:
		return   # another photo was picked meanwhile
	# The camera's other burst shots (<photo>_alt1.jpg, _alt2.jpg, Android): a second look at the
	# cards this one couldn't read — a moment later, glare and blur sit elsewhere. The third shot
	# only if the second added something (each look costs seconds on a phone).
	var look_more: bool = true
	for k: int in range(1, 3):
		var alt_path: String = "%s_alt%d.jpg" % [path.get_basename(), k]
		if not FileAccess.file_exists(alt_path):
			continue
		if _save_to_gallery() and Engine.has_singleton("CameraIntentPlugin"):
			Engine.get_singleton("CameraIntentPlugin").save_to_gallery(alt_path)
		var alt: Image = Image.new()
		var loaded: bool = look_more and not dials.is_empty() and alt.load(alt_path) == OK
		if _is_camera_photo(path):
			DirAccess.remove_absolute(alt_path)   # the camera's own leftovers only, never a loaded photo's neighbours
		if not loaded:
			continue
		var thread_a: Thread = Thread.new()
		_scan_thread = thread_a
		_scan_job = reader
		thread_a.start(reader.second_look.bind(alt, dials))
		_scan_progress.value = 0.0
		_scan_progress.visible = true
		while thread_a.is_alive():
			await get_tree().process_frame
			if not is_inside_tree():
				return
			_scan_progress.value = reader.progress * 100.0
			_status_label.text = tr("SCAN_SECOND_LOOK") % roundi(reader.progress * 100.0)
		_scan_progress.visible = false
		if _scan_thread != thread_a:
			return
		_scan_thread = null
		_scan_job = null
		var more: Array[Dictionary] = thread_a.wait_to_finish()
		if _source_image != img:
			return
		dials.append_array(more)
		look_more = not more.is_empty()
	# Second step: what belongs to each sector — archived cards (face-up ones by their
	# dial, face-down ones by their backs) and stored-supply tokens. Card art is
	# loaded here on the main thread, the counting runs on a thread.
	var tableau: TableauReader = TableauReader.create(dials)
	# a column whose sector dial is covered gets this placeholder sector (shown as "?")
	tableau.placeholder_card = CardDatabase.find_by_scan_code(PLACEHOLDER_SECTOR_CODE).get("card") as CardData
	var thread2: Thread = Thread.new()
	_scan_thread = thread2
	_scan_job = tableau
	thread2.start(tableau.analyze.bind(reader.photo, dials, reader.markers))
	_scan_progress.value = 0.0
	_scan_progress.visible = true
	while thread2.is_alive():
		await get_tree().process_frame
		if not is_inside_tree():
			return                       # _exit_tree() joined the thread
		_scan_progress.value = tableau.progress * 100.0
		_status_label.text = tr("SCAN_COUNTING") % roundi(tableau.progress * 100.0)
	_scan_progress.visible = false
	if _scan_thread != thread2:
		return
	_scan_thread = null
	_scan_job = null
	var groups: Array = thread2.wait_to_finish()
	if _source_image != img:
		return
	# Everything recognised goes straight into the ship (a new photo is a new ship). A tray or a
	# tapped card from the old ship would now point into the new one (both go by sector index): gone.
	_close_tray()
	_sel_sector = -1
	_sel_tech = -1
	_sectors.clear()
	var loose: int = 0
	for g: Array in groups:
		var entry: Dictionary = _sector_entry_from_group(g)
		if entry.is_empty():
			loose += g.size() - 1
		else:
			_sectors.append(entry)
	var secs: int = roundi((Time.get_ticks_msec() - t_start) / 1000.0)
	if _sectors.is_empty():
		push_warning("Scan Tableau: no sector cards found in that photo")
		_scan_summary = tr("SCAN_NONE_FOUND")
	else:
		UIAudio.play_sfx("scan_success")
		_scan_summary = (tr("SCAN_FOUND_ONE") if _sectors.size() == 1 else tr("SCAN_FOUND_MANY") % _sectors.size())
		if loose > 0:
			_scan_summary += ", " + (tr("SCAN_LOOSE_ONE") if loose == 1 else tr("SCAN_LOOSE_MANY") % loose)
		# how long the reading took on this phone (for tuning the reader's speed)
		_scan_summary += " (%d s)" % secs
	_refresh_sector_list()

## A recognised group ([sector, techs…] from TableauReader, sector {} if none was
## read) as a ship entry, BotScoring-shaped. {} for a group without a sector.
func _sector_entry_from_group(g: Array) -> Dictionary:
	var sd: Dictionary = g[0]
	if sd.is_empty():
		return {}
	var techs: Array[CardData] = []
	var tech_dials: Array[Dictionary] = []   # where each lies in the photo (for its cut-out)
	var unsure: Array[int] = []      # techs the reader wasn't sure of (marked "?")
	for i: int in range(1, g.size()):
		if techs.size() >= MAX_TECHS:
			push_warning("Scan Tableau: more cards than a sector can hold — dropping the extras")
			break
		techs.append((g[i] as Dictionary)["card"])
		tech_dials.append(g[i])
		if _is_unsure(g[i]):
			unsure.append(techs.size() - 1)
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
		"unsure_techs": unsure,
		"unsure_sector": _is_unsure(sd),
		# a column whose sector dial wasn't read: drawn as a "?" card (the placeholder card
		# underneath only keeps the scoring going until the player picks the real one)
		"unknown_sector": bool(sd.get("placeholder", false)),
		"sector_dial": sd,
		"tech_dials": tech_dials,
	}

## A reading DialReader only took on its strip's word (a weak dial) or swapped for a
## neighbouring code: worth a look before trusting the score.
static func _is_unsure(d: Dictionary) -> bool:
	return bool(d.get("weak", false)) or bool(d.get("corrected", false))

## A sector made by hand ("+ Sector"): nothing on it yet.
static func _new_entry(sector_cd: CardData, is_advanced: bool) -> Dictionary:
	var techs: Array[CardData] = []
	var tucked: Array[Dictionary] = []
	var unsure: Array[int] = []
	var tech_dials: Array[Dictionary] = []
	return {
		"sector": sector_cd, "is_advanced": is_advanced, "techs": techs, "tucked_cards": tucked,
		"stored_supply": {}, "unsure_techs": unsure, "unsure_sector": false, "unknown_sector": false,
		"sector_dial": {}, "tech_dials": tech_dials,
	}

# ── The stage ──────────────────────────────────────────────────────────────

# What fills the stage: "ship" (the guide before the first photo), "photo" (the scanned photo, to
# compare) or "breakdown" (the VP lines). One at a time, so none squeezes another.
func _set_view(view: String) -> void:
	if view != "ship":
		_close_tray()
		_sel_sector = -1
		_sel_tech = -1
	_view = view
	_sector_scroll.visible = view == "ship" and _source_image != null
	_guide_box.visible = view == "ship" and _source_image == null
	_photo_view.visible = view == "photo"
	_results_box.visible = view == "breakdown"
	_photo_caption.text = "SCAN_PHOTO_BACK" if view == "photo" else "SCAN_PHOTO_CAPTION"
	if view == "ship":
		_refresh_sector_list()
	else:
		_refresh_bar()

# Turns the shown photo 90 degrees clockwise (display only: the reading doesn't care).
func _rotate_photo() -> void:
	var tex: Texture2D = _photo_view.texture
	if tex == null:
		return
	var img: Image = tex.get_image()
	img.rotate_90(CLOCKWISE)
	var turned: ImageTexture = ImageTexture.create_from_image(img)
	_photo_view.texture = turned
	_photo_thumb.texture = turned

## The status line: the cards the scan wasn't sure of (gold "?"), else what the scan found.
func _update_status() -> void:
	var check: int = 0
	for e: Dictionary in _sectors:
		check += (e.get("unsure_techs", []) as Array).size()
		if bool(e.get("unsure_sector", false)) or bool(e.get("unknown_sector", false)):
			check += 1
	_status_badge.visible = check > 0
	if check > 0:
		_status_label.text = tr("SCAN_CHECK_ONE") if check == 1 else tr("SCAN_CHECK_MANY") % check
	else:
		_status_label.text = _scan_summary

## The strip under the stage: the tapped card and what can be done with it; else a hint.
func _refresh_bar() -> void:
	for child: Node in _bar.get_children():
		_bar.remove_child(child)
		child.queue_free()
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_bar.add_child(row)
	_bar_style.border_color = STEEL_DIM
	if _view == "photo":
		row.add_child(_make_bar_hint("SCAN_PHOTO_HINT"))
		var rot: Button = _make_button("⟳ " + tr("Rotate"))
		rot.custom_minimum_size = Vector2(220, 0)
		rot.pressed.connect(_rotate_photo)
		row.add_child(rot)
		row.add_child(_make_back_button())
		return
	if _view == "breakdown":
		row.add_child(_make_bar_hint("SCAN_BREAKDOWN_HINT"))
		row.add_child(_make_back_button())
		return
	var entry: Dictionary = _sectors[_sel_sector] if _sel_sector >= 0 and _sel_sector < _sectors.size() else {}
	if entry.is_empty():
		if not _sectors.is_empty():
			row.add_child(_make_bar_hint("SCAN_IDLE_HINT"))
		return
	_bar_style.border_color = GOLD
	var is_sector: bool = _sel_tech < 0
	var cd: CardData = entry["sector"] if is_sector else (entry["techs"] as Array)[_sel_tech]
	var unknown: bool = is_sector and bool(entry.get("unknown_sector", false))
	var crop: Texture2D = _selected_crop()
	if crop:
		var frame: PanelContainer = PanelContainer.new()
		frame.add_theme_stylebox_override("panel", _rounded(Color(0, 0, 0, 0.3), VIOLET, 3, 8, 3))
		frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		frame.tooltip_text = tr("SCAN_PHOTO_CAPTION")
		var pic: TextureRect = TextureRect.new()
		pic.texture = crop
		pic.custom_minimum_size = Vector2(150, 72)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		frame.add_child(pic)
		row.add_child(frame)
	var mini_size: Vector2 = Vector2(98, 64) if is_sector else Vector2(54, 82)
	var mini: TextureRect = TextureRect.new()
	mini.custom_minimum_size = mini_size
	mini.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mini.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mini.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not unknown:
		mini.texture = load(_art_path(cd, is_sector and bool(entry["is_advanced"]))) as Texture2D
	row.add_child(mini)
	var names: VBoxContainer = VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(names)
	var title: String = _bar_title()
	var name_lbl: Label = _make_label(title, NAME_FONT_SIZE, CREAM)
	name_lbl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	names.add_child(name_lbl)
	var place: String = _bar_place()
	var place_lbl: Label = _make_label(place, SMALL_FONT_SIZE, MUTED)
	place_lbl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	place_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	names.add_child(place_lbl)
	var change: Button = _make_button("Change sector" if is_sector else "Change card")
	change.custom_minimum_size = Vector2(260, 0)
	change.pressed.connect(_on_change_pressed)
	row.add_child(change)
	var remove: Button = _make_button("Delete sector" if is_sector else "Remove")
	remove.custom_minimum_size = Vector2(220, 0)
	GameTheme.style_negative(remove)
	remove.pressed.connect(_on_remove_pressed)
	row.add_child(remove)
	var done: Button = _make_button("Done")
	done.custom_minimum_size = Vector2(180, 0)
	done.pressed.connect(func() -> void: _select(-1, -1))
	row.add_child(done)

func _make_bar_hint(key: String) -> Label:
	var lbl: Label = _make_label(key, BODY_FONT_SIZE, MUTED)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# at most 2 lines: a wrapping label is born 0 px wide and for a frame wants a line per word
	# (2700 px here), which pushed the whole screen down and it stayed there until the next tap
	lbl.max_lines_visible = 2
	return lbl

func _make_back_button() -> Button:
	var back: Button = _make_button("Show Ship")
	back.custom_minimum_size = Vector2(240, 0)
	back.pressed.connect(func() -> void: _set_view("ship"))
	return back

# ── The ship ───────────────────────────────────────────────────────────────

func _refresh_sector_list() -> void:
	_fit_ship_card()
	for child: Node in _sector_list_box.get_children():
		_sector_list_box.remove_child(child)
		child.queue_free()
	_ship_info_boxes.clear()
	_ship_archive_boxes.clear()
	if _sel_sector >= _sectors.size():
		_sel_sector = -1
		_sel_tech = -1
	for i: int in _sectors.size():
		_sector_list_box.add_child(_build_sector_column(_sectors[i], i))
	# a sector the scan missed (dial covered, say) can still be added by hand — until the ship is full
	if _sectors.size() < MAX_SECTORS and _source_image != null:
		_sector_list_box.add_child(_make_add_sector_slot())
	_update_score()
	_update_status()
	_refresh_bar()
	_even_out_info_lines()
	_scroll_ship_to_bottom()

# Card size: as big as fits — every sector side by side across the width (plus the "+ Sector"
# slot), the tallest stack (plus its "+" slot, tokens and archive) within the height.
func _fit_ship_card() -> void:
	var area: Vector2 = _sector_scroll.size if is_instance_valid(_sector_scroll) else Vector2.ZERO
	if area.x <= 0.0 or area.y <= 0.0:
		_ship_card = SHIP_CARD_MAX
		return
	var n: int = maxi(1, _sectors.size())
	var add: float = 1.0 if _sectors.size() < MAX_SECTORS else 0.0
	var by_width: float = (area.x - 8.0 - SHIP_GAP * (n - 1 + add)) / (n + SHIP_ADD_WIDTH * add)
	var most_techs: int = 0
	for e: Dictionary in _sectors:
		most_techs = maxi(most_techs, (e["techs"] as Array).size())
	var by_height: float = (area.y - _ship_info_height - SELECT_LIFT - 8.0) / _ship_stack_factor(most_techs)
	_ship_card = clampf(minf(by_width, by_height) * SHIP_FIT_SHARE, SHIP_CARD_MIN, SHIP_CARD_MAX)

# Height of a sector with `techs` cards stacked on it (and the "+" slot while there's room),
# per px of card long edge.
static func _ship_stack_factor(techs: int) -> float:
	var sector_h: float = 44.0 / 67.0
	var f: float = sector_h
	if techs > 0:
		f += (1.0 - SHIP_SECTOR_COVERED * sector_h) + (techs - 1) * SHIP_TECH_SHOWN
	if techs < MAX_TECHS:
		f += GHOST_SLOT_H + GHOST_GAP
	return f

# Re-fit when the space changes (window resized, rotation) — only on a real change.
func _on_ship_area_resized() -> void:
	if _sectors.is_empty() or not visible or not _sector_scroll.visible:
		return
	var old: float = _ship_card
	_fit_ship_card()
	if absf(_ship_card - old) > 4.0:
		_refresh_sector_list()

# Every sector's token/archive line gets the height of the tallest one, so the sector cards above
# them all sit on one line. Needs a layout pass first: a wrapping line's height depends on width.
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
	# fit with what's really under a sector, so the ship never needs a scrollbar: refit once if off
	var measured: float = total + 24.0
	if not _sectors.is_empty() and measured > _ship_info_height + 4.0:
		_ship_info_height = measured
		_refresh_sector_list()

# Rests the ship view at the bottom (the sectors' baseline), like the in-game ship.
func _scroll_ship_to_bottom() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(_sector_scroll):
		_sector_scroll.scroll_vertical = int(_sector_scroll.get_v_scroll_bar().max_value)

## One sector's column, laid out like the real tableau: the sector at the bottom, the tech nearest
## it covering its top, each further tech covering the top of the one below it (name strip and orb
## in view), a "+" slot above; under the sector its tokens, then its archive. Every card is tapped
## to change it; the token and archive lines open their trays.
func _build_sector_column(entry: Dictionary, index: int) -> Control:
	var long_px: float = _ship_card
	var short_px: float = roundf(long_px * 44.0 / 67.0)
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	outer.custom_minimum_size = Vector2(long_px, 0)
	outer.size_flags_vertical = Control.SIZE_SHRINK_END   # sector cards on one baseline

	var techs: Array = entry["techs"]
	var sector_h: float = short_px
	var tech_size: Vector2 = Vector2(short_px, long_px)
	var stack_h: float = roundf(long_px * _ship_stack_factor(techs.size()) + SELECT_LIFT)
	var stack: Control = Control.new()
	stack.custom_minimum_size = Vector2(long_px, stack_h)
	stack.mouse_filter = Control.MOUSE_FILTER_PASS
	outer.add_child(stack)

	var sector_cd: CardData = entry["sector"]
	var is_advanced: bool = entry["is_advanced"]
	var unknown: bool = bool(entry.get("unknown_sector", false))
	var sector_art: String = "" if unknown else _art_path(sector_cd, is_advanced)
	var sector_tip: String = tr("SCAN_NOT_FOUND") if unknown else _card_name(sector_cd, is_advanced)
	var sector_sel: bool = _sel_sector == index and _sel_tech < 0
	var sector_thumb: TextureRect = _make_ship_thumb(sector_art, sector_tip, Vector2(long_px, sector_h), 0, _select.bind(index, -1))
	stack.add_child(sector_thumb)
	sector_thumb.position = Vector2(0.0, stack_h - sector_h - (SELECT_LIFT if sector_sel else 0.0))   # after add_child
	sector_thumb.size = Vector2(long_px, sector_h)
	if unknown:
		_add_unknown_card(sector_thumb, Vector2(long_px, sector_h))
	elif bool(entry.get("unsure_sector", false)):
		_add_unsure_badge(sector_thumb, Vector2(long_px, sector_h), TableauReader.DIAL_MM["sector"] / TableauReader.SIZE_MM["sector"])
	var lifted: Control = null
	if sector_sel:
		_mark_selected(sector_thumb, Vector2(long_px, sector_h))
		lifted = sector_thumb

	var unsure: Array = entry.get("unsure_techs", [])
	var tech_x: float = roundf((long_px - short_px) * 0.3)
	var y: float = stack_h - sector_h - long_px + SHIP_SECTOR_COVERED * sector_h
	var top_y: float = stack_h - sector_h
	for k: int in techs.size():
		var cd: CardData = techs[k]
		var sel: bool = _sel_sector == index and _sel_tech == k
		var thumb: TextureRect = _make_ship_thumb(cd.local_art_path, cd.card_name, tech_size, k + 1, _select.bind(index, k))
		stack.add_child(thumb)
		thumb.position = Vector2(tech_x, roundf(y) - (SELECT_LIFT if sel else 0.0))
		thumb.size = tech_size
		if unsure.has(k):
			var deck: String = "expedition" if cd.card_type == CardData.CardType.EXPEDITION else "tech"
			_add_unsure_badge(thumb, tech_size, TableauReader.DIAL_MM[deck] / TableauReader.SIZE_MM[deck])
		if sel:
			_mark_selected(thumb, tech_size)
			lifted = thumb
		top_y = y
		y -= SHIP_TECH_SHOWN * long_px
	if lifted:
		stack.move_child(lifted, -1)     # (it is drawn in front, so it takes the taps there too)
	# room for another card: a "+" slot on top of the stack
	if techs.size() < MAX_TECHS:
		var ghost_h: float = roundf(GHOST_SLOT_H * long_px)
		var ghost: Control = _make_ghost_slot(Vector2(short_px, ghost_h), "+", _on_add_tech.bind(index))
		stack.add_child(ghost)
		ghost.position = Vector2(tech_x, roundf(top_y - GHOST_GAP * long_px - ghost_h))
		ghost.size = Vector2(short_px, ghost_h)

	# under the sector: its tokens, then its archive (each line opens its tray)
	var tokens: PanelContainer = _make_tap_area(_open_tray.bind("supply", index))
	outer.add_child(tokens)
	var token_flow: HFlowContainer = HFlowContainer.new()
	token_flow.add_theme_constant_override("h_separation", 8)
	token_flow.add_theme_constant_override("v_separation", 6)
	token_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tokens.add_child(token_flow)
	_ship_info_boxes.append(tokens)
	var stored: Dictionary = entry["stored_supply"]
	for color: CardData.SupplyColor in _SUPPLY_COLORS:
		var n: int = int(stored.get(int(color), 0))
		if n > 0:
			token_flow.add_child(_make_token(int(color), n, TOKEN_ICON))
	token_flow.add_child(_make_round_badge("+", 40.0, Color(0.08, 0.11, 0.19, 0.9), GHOST))

	var archive: PanelContainer = _make_tap_area(_open_tray.bind("archive", index))
	outer.add_child(archive)
	_ship_archive_boxes.append(archive)
	archive.add_child(_make_archive_line(entry, long_px))
	return outer

## A card in the ship: its art (or nothing, for a sector the scan didn't find), a tap selects it.
func _make_ship_thumb(art_path: String, tooltip: String, thumb_size: Vector2, base_z: int, on_tap: Callable) -> TextureRect:
	var thumb: TextureRect = TextureRect.new()
	if not art_path.is_empty():
		thumb.texture = load(art_path) as Texture2D
	thumb.custom_minimum_size = thumb_size
	thumb.z_index = base_z
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# PASS: the tap reaches the card and a drag still scrolls the ship
	thumb.mouse_filter = Control.MOUSE_FILTER_PASS
	thumb.tooltip_text = tooltip
	thumb.pivot_offset = thumb_size / 2.0
	thumb.gui_input.connect(_tap_handler(on_tap))
	# (mouse only) the card under the pointer comes to the front, a little bigger
	var hover_tween_cell: Array = [null]
	thumb.mouse_entered.connect(func() -> void:
		thumb.z_index = maxi(base_z, 40)
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
		tw.tween_callback(func() -> void: thumb.z_index = base_z if thumb.get_meta("selected", false) == false else 60)
		hover_tween_cell[0] = tw)
	return thumb

## The tapped card: in front, a gold edge round it (it's also lifted, see _build_sector_column).
func _mark_selected(thumb: TextureRect, thumb_size: Vector2) -> void:
	thumb.z_index = 60
	thumb.set_meta("selected", true)
	var rim: Panel = Panel.new()
	var w: int = maxi(3, roundi(minf(thumb_size.x, thumb_size.y) * 0.035))
	var style: StyleBoxFlat = _rounded(Color(0, 0, 0, 0), GOLD, w, roundi(minf(thumb_size.x, thumb_size.y) * 0.08))
	style.expand_margin_left = w
	style.expand_margin_right = w
	style.expand_margin_top = w
	style.expand_margin_bottom = w
	rim.add_theme_stylebox_override("panel", style)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.add_child(rim)
	rim.position = Vector2.ZERO                     # after add_child, so layout can't override it
	rim.size = thumb_size

## A dashed-looking empty slot with a "+" (a card or a sector to add).
func _make_ghost_slot(slot_size: Vector2, text: String, on_tap: Callable) -> Control:
	var slot: PanelContainer = PanelContainer.new()
	slot.add_theme_stylebox_override("panel", _rounded(Color(0.06, 0.09, 0.16, 0.55), GHOST, 2, 10))
	slot.custom_minimum_size = slot_size
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	slot.gui_input.connect(_tap_handler(on_tap))
	var lbl: Label = _make_label(text, roundi(clampf(slot_size.y * 0.55, 24.0, 40.0)), GHOST)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(lbl)
	return slot

func _make_add_sector_slot() -> Control:
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_vertical = Control.SIZE_SHRINK_END
	var w: float = roundf(_ship_card * SHIP_ADD_WIDTH)
	var slot: Control = _make_ghost_slot(Vector2(w, roundf(_ship_card * 44.0 / 67.0)), "+ Sector", _on_add_sector)
	(slot.get_child(0) as Label).add_theme_font_size_override("font_size", 26)
	col.add_child(slot)
	# in line with the sector cards (their token and archive lines below)
	var under: Control = Control.new()
	under.custom_minimum_size = Vector2(w, _ship_info_height)
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(under)
	return col

## A line under a sector that opens its tray when tapped (no frame until it's open).
func _make_tap_area(on_tap: Callable) -> PanelContainer:
	var area: PanelContainer = PanelContainer.new()
	area.add_theme_stylebox_override("panel", _rounded(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 10, 4))
	area.mouse_filter = Control.MOUSE_FILTER_PASS
	area.gui_input.connect(_tap_handler(on_tap))
	return area

## A supply token with its count (×2 and up).
func _make_token(color_int: int, n: int, icon_size: float) -> Control:
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon: TextureRect = TextureRect.new()
	icon.texture = load(_SUPPLY_ICON_PATHS[color_int]) as Texture2D
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	if n > 1:
		var lbl: Label = _make_label("×%d" % n, SMALL_FONT_SIZE, CREAM)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(lbl)
	return box

## The archive under a sector: face-up cards as small cards, face-down ones as backs with their count;
## an empty outline when there's nothing.
func _make_archive_line(entry: Dictionary, width: float) -> Control:
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var up: Array[CardData] = []
	var down: int = 0
	for t: Dictionary in (entry["tucked_cards"] as Array):
		if bool(t["face_up"]):
			var tcd: CardData = t.get("data")
			if tcd:
				up.append(tcd)
		else:
			down += 1
	if not up.is_empty():
		# fanned; with many they overlap more, so the line stays within the sector's width
		var room: float = width - ((ARCHIVE_CARD.x + 4.0 + 40.0 + 14.0) if down > 0 else 0.0)
		var step: float = ARCHIVE_CARD.x - 14.0
		if up.size() > 1:
			step = clampf((room - ARCHIVE_CARD.x) / (up.size() - 1), 12.0, step)
		var fan: HBoxContainer = HBoxContainer.new()
		fan.add_theme_constant_override("separation", roundi(step - ARCHIVE_CARD.x))
		fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for tcd: CardData in up:
			fan.add_child(_make_mini_card(tcd.local_art_path, ARCHIVE_CARD))
		line.add_child(fan)
	if down > 0:
		var backs: HBoxContainer = HBoxContainer.new()
		backs.add_theme_constant_override("separation", 4)
		backs.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backs.add_child(_make_mini_card(_back_path(), ARCHIVE_CARD))
		var lbl: Label = _make_label("×%d" % down, BODY_FONT_SIZE, CREAM)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backs.add_child(lbl)
		line.add_child(backs)
	if up.is_empty() and down == 0:
		var empty: Panel = Panel.new()
		empty.add_theme_stylebox_override("panel", _rounded(Color(0, 0, 0, 0), Color(GHOST, 0.5), 2, 5))
		empty.custom_minimum_size = ARCHIVE_CARD
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(empty)
	return line

func _make_mini_card(art_path: String, card_size: Vector2) -> TextureRect:
	var r: TextureRect = TextureRect.new()
	if not art_path.is_empty():
		r.texture = load(art_path) as Texture2D
	r.custom_minimum_size = card_size
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## The tech back of the game's language (EN where there's none).
static func _back_path() -> String:
	var lang: String = TranslationServer.get_locale().substr(0, 2).to_upper()
	var p: String = TECH_BACK_PATH % lang
	return p if ResourceLoader.exists(p) else TECH_BACK_PATH % "EN"

## A card the scan couldn't find (a sector whose light ring wasn't read): a dark card with a
## giant yellow "?", so it can't be mistaken for a real one.
func _add_unknown_card(thumb: TextureRect, thumb_size: Vector2) -> void:
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _rounded(Color(0.1, 0.12, 0.17), STAR_COLOR,
		maxi(2, roundi(minf(thumb_size.x, thumb_size.y) * 0.04)), roundi(minf(thumb_size.x, thumb_size.y) * 0.07)))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl: Label = _make_label("?", roundi(minf(thumb_size.x, thumb_size.y) * 0.8), STAR_COLOR)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(lbl)
	thumb.add_child(card)
	card.position = Vector2.ZERO                     # after add_child, so layout can't override it
	card.size = thumb_size

## A gold "?" over a card's light ring: the scan wasn't sure of this card (tap it to check).
func _add_unsure_badge(thumb: TextureRect, thumb_size: Vector2, at: Vector2) -> void:
	var d: float = maxf(16.0, roundf(minf(thumb_size.x, thumb_size.y) * 0.24))
	var badge: PanelContainer = _make_round_badge("?", d, GOLD, BADGE_DARK)
	thumb.add_child(badge)
	badge.size = Vector2(d, d)                       # after add_child, so layout can't override it
	badge.position = thumb_size * at - badge.size / 2.0
	thumb.tooltip_text += "  (?)"

static func _art_path(cd: CardData, is_advanced: bool) -> String:
	return cd.adv_local_art_path if is_advanced and not cd.adv_local_art_path.is_empty() else cd.local_art_path

static func _card_name(cd: CardData, is_advanced: bool) -> String:
	return cd.adv_name if is_advanced and not cd.adv_name.is_empty() else cd.card_name

func _sector_label(entry: Dictionary) -> String:
	if bool(entry.get("unknown_sector", false)):
		return tr("SCAN_NOT_FOUND")
	return _card_name(entry["sector"], bool(entry["is_advanced"]))

## The tapped card's name ("Sector not found" for a "?" sector) and where it sits.
func _bar_title() -> String:
	if _sel_sector < 0 or _sel_sector >= _sectors.size():
		return ""
	var entry: Dictionary = _sectors[_sel_sector]
	if _sel_tech < 0:
		return _sector_label(entry)
	return _card_name((entry["techs"] as Array)[_sel_tech], false)

func _bar_place() -> String:
	if _sel_sector < 0 or _sel_sector >= _sectors.size():
		return ""
	if _sel_tech < 0:
		return tr("SCAN_PLACE_SECTOR") % (_sel_sector + 1)
	return tr("SCAN_PLACE_CARD") % [_sector_label(_sectors[_sel_sector]), _sel_tech + 1]

## The tapped card as the photo shows it (null for a card added by hand, or without a photo).
func _selected_crop() -> Texture2D:
	if _sel_sector < 0 or _sel_sector >= _sectors.size():
		return null
	var entry: Dictionary = _sectors[_sel_sector]
	var d: Dictionary = {}
	if _sel_tech < 0:
		d = entry.get("sector_dial", {})
	else:
		var dials: Array = entry.get("tech_dials", [])
		if _sel_tech < dials.size():
			d = dials[_sel_tech]
	return _photo_crop(d)

## The part of the photo where a read card lies, turned upright and squared up (the reader knows
## each card's frame: TableauReader.card_frame). A tech: its lower part with the name strip and orb
## (what a stack leaves in view); a sector: its lower part under the techs; a "?" sector: where it
## must be. Cached per position.
func _photo_crop(d: Dictionary) -> Texture2D:
	if d.is_empty() or _source_image == null or not d.has("shape") or not d.has("card"):
		return null
	var key: String = "%s|%s" % [str(d["center"]), str(d["radius"])]
	if _crops.has(key):
		return _crops[key]
	var deck: String = TableauReader.deck_of(d)
	var size_mm: Vector2 = TableauReader.SIZE_MM[deck]
	var shown: float = CROP_SECTOR_SHOWN if deck == "sector" else CROP_TECH_SHOWN
	var from_v: float = size_mm.y * (1.0 - shown)
	var frame: Transform2D = TableauReader.card_frame(d)
	var w: int = int(size_mm.x * CROP_PPM)
	var h: int = int(size_mm.y * shown * CROP_PPM)
	var iw: int = _source_image.get_width()
	var ih: int = _source_image.get_height()
	var out: Image = Image.create(w, h, false, Image.FORMAT_RGB8)
	for j: int in h:
		for i: int in w:
			var at: Vector2 = frame * Vector2((i + 0.5) / CROP_PPM, from_v + (j + 0.5) / CROP_PPM)
			out.set_pixel(i, j, _source_image.get_pixel(clampi(int(at.x), 0, iw - 1), clampi(int(at.y), 0, ih - 1)))
	var tex: ImageTexture = ImageTexture.create_from_image(out)
	_crops[key] = tex
	return tex

# ── Editing: a tapped card ─────────────────────────────────────────────────

## Taps a card (tech -1: the sector card); the same card again, or (-1, -1), lets go.
func _select(sector: int, tech: int) -> void:
	_close_tray()
	if sector == _sel_sector and tech == _sel_tech:
		sector = -1
		tech = -1
	_sel_sector = sector
	_sel_tech = tech
	_refresh_sector_list()

func _on_change_pressed() -> void:
	if _sel_sector < 0 or _sel_sector >= _sectors.size():
		return
	var index: int = _sel_sector
	var crop: Texture2D = _selected_crop()
	var line: String = "%s (%s)" % [_bar_title(), _bar_place()]
	if _sel_tech < 0:
		var entry: Dictionary = _sectors[index]
		var tab: int = CardPickerScript.TAB_SECTOR_ADVANCED if bool(entry["is_advanced"]) else CardPickerScript.TAB_SECTOR_DUST
		_pick(tab, [CardPickerScript.TAB_SECTOR_DUST, CardPickerScript.TAB_SECTOR_ADVANCED], func(card_name: String, adv: bool) -> void:
			var cd: CardData = CardDatabase.find_sector_by_name(card_name, adv)
			if cd == null or index >= _sectors.size():
				return
			var e: Dictionary = _sectors[index]
			e["sector"] = cd
			e["is_advanced"] = adv
			e["unsure_sector"] = false
			e["unknown_sector"] = false
			_refresh_sector_list(), crop, line)
	else:
		var k: int = _sel_tech
		_pick(CardPickerScript.TAB_TECH, [CardPickerScript.TAB_TECH, CardPickerScript.TAB_EXPEDITION], func(card_name: String, _adv: bool) -> void:
			var cd: CardData = CardDatabase.find_any_by_name(card_name)
			if cd == null or index >= _sectors.size():
				return
			var techs: Array = _sectors[index]["techs"]
			if k >= techs.size():
				return
			techs[k] = cd
			(_sectors[index]["unsure_techs"] as Array).erase(k)
			_refresh_sector_list(), crop, line)

func _on_remove_pressed() -> void:
	if _sel_sector < 0 or _sel_sector >= _sectors.size():
		return
	if _sel_tech < 0:
		_sectors.remove_at(_sel_sector)
	else:
		var e: Dictionary = _sectors[_sel_sector]
		(e["techs"] as Array).remove_at(_sel_tech)
		var dials: Array = e.get("tech_dials", [])
		if _sel_tech < dials.size():
			dials.remove_at(_sel_tech)
		# the "?" marks follow their cards
		var marks: Array[int] = []
		for m: int in (e.get("unsure_techs", []) as Array):
			if m < _sel_tech:
				marks.append(m)
			elif m > _sel_tech:
				marks.append(m - 1)
		e["unsure_techs"] = marks
	_sel_sector = -1
	_sel_tech = -1
	_refresh_sector_list()

## The "+" on top of a stack: a tech or expedition picked from the collection goes on top.
func _on_add_tech(index: int) -> void:
	_close_tray()
	_pick(CardPickerScript.TAB_TECH, [CardPickerScript.TAB_TECH, CardPickerScript.TAB_EXPEDITION], func(card_name: String, _adv: bool) -> void:
		var cd: CardData = CardDatabase.find_any_by_name(card_name)
		if cd == null or index >= _sectors.size():
			return
		var techs: Array = _sectors[index]["techs"]
		if techs.size() < MAX_TECHS:
			techs.append(cd)
			var dials: Array = _sectors[index].get("tech_dials", [])
			dials.append({})          # added by hand: no place in the photo
		_refresh_sector_list())

## "+ Sector": a sector the scan missed, picked from the collection, at the end of the row.
func _on_add_sector() -> void:
	_close_tray()
	_pick(CardPickerScript.TAB_SECTOR_DUST, [CardPickerScript.TAB_SECTOR_DUST, CardPickerScript.TAB_SECTOR_ADVANCED], func(card_name: String, adv: bool) -> void:
		var cd: CardData = CardDatabase.find_sector_by_name(card_name, adv)
		if cd == null or _sectors.size() >= MAX_SECTORS:
			return
		_sectors.append(_new_entry(cd, adv))
		_refresh_sector_list())

## Opens the card picker on the tabs a slot can hold (a sector slot only ever shows sectors).
func _pick(default_tab: int, allowed: Array[int], on_pick: Callable, context: Texture2D = null, context_text: String = "",
		stars_first: bool = false) -> void:
	if _picker_callback.is_valid() and _card_picker.picked.is_connected(_picker_callback):
		_card_picker.picked.disconnect(_picker_callback)
	_picker_callback = on_pick
	_card_picker.picked.connect(_picker_callback, CONNECT_ONE_SHOT)
	if _tray:
		_tray.visible = false
		if not _card_picker.visibility_changed.is_connected(_on_picker_visibility):
			_card_picker.visibility_changed.connect(_on_picker_visibility)
	_card_picker.open(default_tab, allowed, context, context_text, stars_first)

func _on_picker_visibility() -> void:
	if not _card_picker.visible and _tray and is_instance_valid(_tray):
		_tray.visible = true
		_place_tray()

# ── Editing: a sector's trays ──────────────────────────────────────────────

## A sector's token tray ("supply") or archive tray ("archive"), floating over its line (no dimming:
## the ship stays in view). A tap anywhere else closes it and shows the new counts.
func _open_tray(kind: String, index: int) -> void:
	var same: bool = _tray != null and _tray_kind == kind and _tray_sector == index
	var boxes: Array[Control] = _ship_info_boxes if kind == "supply" else _ship_archive_boxes
	var anchor: Rect2 = boxes[index].get_global_rect() if index >= 0 and index < boxes.size() and is_instance_valid(boxes[index]) else Rect2()
	_close_tray()
	_sel_sector = -1
	_sel_tech = -1
	_refresh_sector_list()                  # the new counts, no card lifted
	if same or index < 0 or index >= _sectors.size() or anchor.size == Vector2.ZERO:
		return
	_tray_kind = kind
	_tray_sector = index
	_tray_anchor = anchor
	var tray: PanelContainer = PanelContainer.new()
	tray.add_theme_stylebox_override("panel", _tray_style())
	tray.mouse_filter = Control.MOUSE_FILTER_STOP
	tray.z_index = 100
	add_child(tray)
	_tray = tray
	_fill_tray()

func _tray_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = _rounded(PANEL_BG, GOLD, 2, 16, 18)
	s.shadow_color = Color(0, 0, 0, 0.6)
	s.shadow_size = 18
	s.shadow_offset = Vector2(0, 10)
	return s

## (Re)builds the open tray's content and keeps it by its line, on screen.
func _fill_tray() -> void:
	if _tray == null or _tray_sector >= _sectors.size():
		return
	for child: Node in _tray.get_children():
		_tray.remove_child(child)
		child.queue_free()
	var entry: Dictionary = _sectors[_tray_sector]
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_tray.add_child(box)
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	box.add_child(head)
	var title_key: String = "SCAN_SUPPLY_ON" if _tray_kind == "supply" else "SCAN_ARCHIVE_UNDER"
	var title: Label = _make_label(tr(title_key) % _sector_label(entry), BODY_FONT_SIZE, CREAM)
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if _tray_kind == "supply":
		head.add_child(_make_label("SCAN_TOKEN_HINT", SMALL_FONT_SIZE, MUTED))
		box.add_child(_build_supply_tray(entry))
	else:
		box.add_child(_build_archive_tray(entry))
	_place_tray()

## Where the open tray's line is now (the ship may have been redrawn since it opened).
func _tray_line_rect() -> Rect2:
	var boxes: Array[Control] = _ship_info_boxes if _tray_kind == "supply" else _ship_archive_boxes
	if _tray_sector >= 0 and _tray_sector < boxes.size() and is_instance_valid(boxes[_tray_sector]):
		return boxes[_tray_sector].get_global_rect()
	return _tray_anchor

func _place_tray() -> void:
	if _tray == null:
		return
	_tray.reset_size()
	var screen: Rect2 = get_global_rect()
	var sz: Vector2 = _tray.get_combined_minimum_size()
	var pos: Vector2 = Vector2(_tray_anchor.get_center().x - sz.x / 2.0, _tray_anchor.position.y - sz.y - 14.0)
	if pos.y < screen.position.y + 8.0:
		pos.y = _tray_anchor.end.y + 14.0           # no room above: below the line
	pos.x = clampf(pos.x, screen.position.x + 8.0, screen.end.x - sz.x - 8.0)
	pos.y = clampf(pos.y, screen.position.y + 8.0, screen.end.y - sz.y - 8.0)
	_tray.global_position = pos

## The six tokens: tap one to add it, its "−" takes one off; the score follows every tap.
func _build_supply_tray(entry: Dictionary) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var stored: Dictionary = entry["stored_supply"]
	for color: CardData.SupplyColor in _SUPPLY_COLORS:
		var c: int = int(color)
		var n: int = int(stored.get(c, 0))
		var col: VBoxContainer = VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(col)
		var icon: TextureRect = TextureRect.new()
		icon.texture = load(_SUPPLY_ICON_PATHS[c]) as Texture2D
		icon.custom_minimum_size = Vector2(TRAY_TOKEN, TRAY_TOKEN)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.tooltip_text = CardData.color_name(color)
		icon.modulate = Color(1, 1, 1, 1.0 if n > 0 else 0.45)
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		icon.gui_input.connect(_tap_handler(_step_supply.bind(c, 1)))
		col.add_child(icon)
		var count: Label = _make_label(str(n), STEPPER_BUTTON_FONT_SIZE, CREAM if n > 0 else MUTED)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(count)
		var minus: Button = _make_stepper_button("−")
		minus.custom_minimum_size = Vector2(TRAY_TOKEN, 56)
		minus.disabled = n == 0
		minus.pressed.connect(_step_supply.bind(c, -1))
		col.add_child(minus)
	return row

func _step_supply(color_int: int, by: int) -> void:
	if _tray_sector < 0 or _tray_sector >= _sectors.size():
		return
	var stored: Dictionary = _sectors[_tray_sector]["stored_supply"]
	var n: int = clampi(int(stored.get(color_int, 0)) + by, 0, 99)
	if n > 0:
		stored[color_int] = n
	else:
		stored.erase(color_int)
	_refresh_sector_list()
	_fill_tray()

## Face-up archived cards (the real cards: tap "+" to pick one, ✕ takes one off) and the
## face-down count (− n +).
func _build_archive_tray(entry: Dictionary) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	var tucked: Array = entry["tucked_cards"]
	# face up
	var up_col: VBoxContainer = VBoxContainer.new()
	up_col.add_theme_constant_override("separation", 8)
	row.add_child(up_col)
	up_col.add_child(_make_label("Face up", SMALL_FONT_SIZE, MUTED))
	var up_row: HBoxContainer = HBoxContainer.new()
	up_row.add_theme_constant_override("separation", 10)
	up_col.add_child(up_row)
	for i: int in tucked.size():
		var t: Dictionary = tucked[i]
		if not bool(t["face_up"]) or t.get("data") == null:
			continue
		var tcd: CardData = t["data"]
		var card_col: VBoxContainer = VBoxContainer.new()
		card_col.add_theme_constant_override("separation", 4)
		up_row.add_child(card_col)
		var mini: TextureRect = _make_mini_card(tcd.local_art_path, TRAY_CARD)
		mini.tooltip_text = tcd.card_name
		mini.mouse_filter = Control.MOUSE_FILTER_PASS
		card_col.add_child(mini)
		var off: Button = _make_stepper_button("✕")
		off.custom_minimum_size = Vector2(TRAY_CARD.x, 48)
		off.add_theme_font_size_override("font_size", 22)
		off.pressed.connect(_remove_tucked.bind(i))
		card_col.add_child(off)
	var add_up: Control = _make_ghost_slot(TRAY_CARD, "+", _add_face_up)
	add_up.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	up_row.add_child(add_up)
	row.add_child(VSeparator.new())
	# face down
	var down: int = 0
	for t: Dictionary in tucked:
		if not bool(t["face_up"]):
			down += 1
	var down_col: VBoxContainer = VBoxContainer.new()
	down_col.add_theme_constant_override("separation", 8)
	row.add_child(down_col)
	down_col.add_child(_make_label("Face down", SMALL_FONT_SIZE, MUTED))
	var down_row: HBoxContainer = HBoxContainer.new()
	down_row.add_theme_constant_override("separation", 12)
	down_col.add_child(down_row)
	down_row.add_child(_make_mini_card(_back_path(), TRAY_CARD))
	var minus: Button = _make_stepper_button("−")
	minus.disabled = down == 0
	minus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	minus.pressed.connect(_step_face_down.bind(-1))
	down_row.add_child(minus)
	var count: Label = _make_label(str(down), STEPPER_BUTTON_FONT_SIZE + 6, CREAM)
	count.custom_minimum_size = Vector2(44, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	down_row.add_child(count)
	var plus: Button = _make_stepper_button("+")
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plus.pressed.connect(_step_face_down.bind(1))
	down_row.add_child(plus)
	return row

## A face-up archived card scores its printed stars: the picker lists the cards with a star first.
func _add_face_up() -> void:
	var index: int = _tray_sector
	if index < 0 or index >= _sectors.size():
		return
	var line: String = tr("SCAN_ARCHIVE_UNDER") % _sector_label(_sectors[index])
	_pick(CardPickerScript.TAB_TECH, [CardPickerScript.TAB_TECH, CardPickerScript.TAB_EXPEDITION], func(card_name: String, _adv: bool) -> void:
		var cd: CardData = CardDatabase.find_any_by_name(card_name)
		if cd == null or index >= _sectors.size():
			return
		(_sectors[index]["tucked_cards"] as Array).append({"data": cd, "face_up": true})
		_refresh_sector_list()
		_fill_tray(), null, line, true)

func _remove_tucked(i: int) -> void:
	if _tray_sector < 0 or _tray_sector >= _sectors.size():
		return
	var tucked: Array = _sectors[_tray_sector]["tucked_cards"]
	if i < tucked.size():
		tucked.remove_at(i)
	_refresh_sector_list()
	_fill_tray()

func _step_face_down(by: int) -> void:
	if _tray_sector < 0 or _tray_sector >= _sectors.size():
		return
	var tucked: Array = _sectors[_tray_sector]["tucked_cards"]
	if by > 0:
		tucked.append({"data": null, "face_up": false})
	else:
		for i: int in range(tucked.size() - 1, -1, -1):
			if not bool((tucked[i] as Dictionary)["face_up"]):
				tucked.remove_at(i)
				break
	_refresh_sector_list()
	_fill_tray()

## Closes the open tray (the ship under it already shows its counts: every tray tap redraws it).
func _close_tray() -> void:
	if _tray == null:
		return
	if is_instance_valid(_tray):
		_tray.queue_free()
	_tray = null
	_tray_kind = ""
	_tray_sector = -1

# ── Score ──────────────────────────────────────────────────────────────────

# The ship's VP total and breakdown, shown whenever there's a ship; any change makes it
# submittable again.
func _update_score() -> void:
	for child: Node in _results_box.get_children():
		_results_box.remove_child(child)
		child.queue_free()
	_score_box.visible = not _sectors.is_empty()
	_leaderboard_btn.disabled = _sectors.is_empty()
	_leaderboard_btn.text = "Add to Leaderboard"
	if _sectors.is_empty():
		_alliance_row.visible = false
		return
	_apply_alliance()
	for line: Dictionary in BotScoring.board_vp_lines(_sectors):
		var lbl: Label = _make_label("%s: %d" % [line["label"], line["vp"]], BODY_FONT_SIZE, CREAM)
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
	# the first time (or with posting switched off) the player is asked first and may say no
	if not LeaderboardManager.score_not_shared.is_connected(_on_score_not_shared):
		LeaderboardManager.score_not_shared.connect(_on_score_not_shared, CONNECT_ONE_SHOT)
	LeaderboardManager.submit_score(BotScoring.board_vp(_sectors), ScoringSnapshotCodec.encode_lines(lines),
		LeaderboardManager.SOURCE_SCAN)

func _on_score_not_shared() -> void:
	if LeaderboardManager.score_uploaded.is_connected(_on_score_uploaded):
		LeaderboardManager.score_uploaded.disconnect(_on_score_uploaded)
	_leaderboard_btn.text = "Add to Leaderboard"
	_leaderboard_btn.disabled = false

func _on_score_uploaded(success: bool) -> void:
	if LeaderboardManager.score_not_shared.is_connected(_on_score_not_shared):
		LeaderboardManager.score_not_shared.disconnect(_on_score_not_shared)
	if success:
		_leaderboard_btn.text = "Added to Leaderboard ✓"
	else:
		_leaderboard_btn.text = "Upload failed — try again"
		_leaderboard_btn.disabled = false
