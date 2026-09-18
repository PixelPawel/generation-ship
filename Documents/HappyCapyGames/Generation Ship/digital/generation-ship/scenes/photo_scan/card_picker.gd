class_name CardPicker
extends Control

# Full-screen card picker used by Scan Tableau's review rows — lets the user
# choose a real card by tapping its art instead of typing its name by hand
# (a typo there just silently failed the CardDatabase lookup at confirm
# time). Modeled on collection_popup.gd's tabbed thumbnail grid, but a
# single tap picks and closes instead of enlarging, and cards are sourced
# directly from CardDatabase's own lists rather than scanning art files, so
# the exact card_name/adv_name is always known (no name<->art guessing).

signal picked(card_name: String, is_advanced: bool)

const _TAB_LABELS: Array[String] = ["Sector (Dust)", "Sector (Advanced)", "Tech", "Expedition"]
const _PORTRAIT_SIZE: Vector2 = Vector2(140, 196)
const _PORTRAIT_COLUMNS: int = 5
const _LANDSCAPE_SIZE: Vector2 = Vector2(200, 132)
const _LANDSCAPE_COLUMNS: int = 4

const TITLE_FONT_SIZE: int = 28
const TAB_FONT_SIZE: int = 20
const TAB_MIN_HEIGHT: float = 72.0

var _active_tab: int = 0
var _tab_buttons: Array[Button] = []
var _grid: GridContainer = null

func _ready() -> void:
	_build_ui()
	visible = false

func open() -> void:
	_select_tab(0)
	visible = true

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var panel: Control = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(24)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(vbox)

	var title_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(title_row)
	var title: Label = Label.new()
	title.text = "PICK A CARD"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close_btn: Button = _make_tab_button("✕")
	close_btn.custom_minimum_size = Vector2(TAB_MIN_HEIGHT, TAB_MIN_HEIGHT)
	close_btn.pressed.connect(func(): visible = false)
	title_row.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	var tab_row: HBoxContainer = HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 10)
	vbox.add_child(tab_row)
	var group: ButtonGroup = ButtonGroup.new()
	for i: int in _TAB_LABELS.size():
		var btn: Button = _make_tab_button(_TAB_LABELS[i])
		btn.custom_minimum_size = Vector2(0, TAB_MIN_HEIGHT)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.toggle_mode = true
		btn.button_group = group
		btn.pressed.connect(_select_tab.bind(i))
		tab_row.add_child(btn)
		_tab_buttons.append(btn)

	vbox.add_child(HSeparator.new())

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var center: CenterContainer = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	center.add_child(_grid)

func _make_tab_button(label: String) -> Button:
	var btn: Button = Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", TAB_FONT_SIZE)
	GameTheme.apply_to_button(btn)
	return btn

func _select_tab(idx: int) -> void:
	_active_tab = idx
	for i: int in _tab_buttons.size():
		_tab_buttons[i].set_pressed_no_signal(i == idx)
	_populate_grid()

func _populate_grid() -> void:
	for child: Node in _grid.get_children():
		child.queue_free()
	var landscape: bool = _active_tab <= 1
	_grid.columns = _LANDSCAPE_COLUMNS if landscape else _PORTRAIT_COLUMNS
	var box_size: Vector2 = _LANDSCAPE_SIZE if landscape else _PORTRAIT_SIZE
	for entry: Dictionary in _entries_for_tab(_active_tab):
		var tex: Texture2D = load(entry["art"] as String) as Texture2D
		if not tex:
			continue
		var rect: TextureRect = TextureRect.new()
		rect.texture = tex
		rect.custom_minimum_size = box_size
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.mouse_filter = Control.MOUSE_FILTER_STOP
		rect.tooltip_text = entry["name"]
		var card_name: String = entry["name"]
		var is_adv: bool = entry["is_advanced"]
		rect.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
				picked.emit(card_name, is_adv)
				visible = false)
		_grid.add_child(rect)

func _entries_for_tab(idx: int) -> Array[Dictionary]:
	match idx:
		0: return _dedupe(CardDatabase.sectors, func(cd: CardData) -> String: return cd.card_name, func(cd: CardData) -> String: return cd.local_art_path, false)
		1: return _dedupe(CardDatabase.sectors, func(cd: CardData) -> String: return cd.adv_name, func(cd: CardData) -> String: return cd.adv_local_art_path, true)
		2: return _dedupe(CardDatabase.techs, func(cd: CardData) -> String: return cd.card_name, func(cd: CardData) -> String: return cd.local_art_path, false)
		3: return _dedupe(CardDatabase.expeditions, func(cd: CardData) -> String: return cd.card_name, func(cd: CardData) -> String: return cd.local_art_path, false)
	return []

## Sectors carry both a dust and an advanced identity on the same CardData
## (and advanced names repeat across the 2 physical copies of each unique
## card), so tab-building dedupes by whichever name is relevant to that tab
## rather than listing one tile per CardData.
static func _dedupe(cards: Array[CardData], name_fn: Callable, art_fn: Callable, is_advanced: bool) -> Array[Dictionary]:
	var seen: Dictionary = {}
	var out: Array[Dictionary] = []
	for cd: CardData in cards:
		var name: String = name_fn.call(cd)
		if name.is_empty() or seen.has(name):
			continue
		var art: String = art_fn.call(cd)
		if art.is_empty():
			continue
		seen[name] = true
		out.append({"name": name, "art": art, "is_advanced": is_advanced})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["name"] as String) < (b["name"] as String))
	return out

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()
