class_name ContextHints
extends Control
# First-time tips: the first time a mechanic actually comes up in a game
# (an Archive effect, a Store effect, an optimize, a complete sector, a bid…)
# a small tip explains it, worded after the rule book. Each tip shows once
# per player ever (settings.cfg [hints]); the pause menu's "show the tutorial
# again" brings them back too (see pause_menu.gd). Never blocks: it sits near
# the top, lets clicks through, and goes away after a while or on a tap.

const SETTINGS_PATH: String = "user://settings.cfg"
const SECTION: String = "hints"
const SHOW_SEC: float = 7.0
const WIDTH: float = 560.0

# key -> English text (translated with tr when shown)
const TEXTS: Dictionary = {
	"archive": "Archive: put the card under this sector. Face down it's worth 1★ at the end, face up it's worth its printed stars.",
	"store": "Stored supply sits on your sector and is always worth 1★ at the end.",
	"optimize": "Optimize: a matching group of cards on a sector activates its optimize effect — once, twice or three times per sector.",
	"fully_optimized": "Fully optimized: the sector's last matching card is placed. Cards that say \"if fully optimized\" now resolve.",
	"complete": "Complete: this sector has 5 cards. Its 5th card activates \"if complete\" effects.",
	"bid": "Bidding: in turn order, raise or pass. Once you pass you're out. The winner pays their bid and places the card on their ship.",
	"order": "Several effects at once: you choose which one resolves first.",
}

var _seen: Dictionary = {}
var _queue: Array[String] = []
var _panel: PanelContainer = null
var _label: Label = null
var _timer: SceneTreeTimer = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK and cfg.has_section(SECTION):
		for key: String in cfg.get_section_keys(SECTION):
			_seen[key] = bool(cfg.get_value(SECTION, key, false))
	_panel = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.14, 0.92)
	style.border_color = Color(0.4, 0.85, 1.0, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	_panel.add_theme_stylebox_override("panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			_close())
	_panel.visible = false
	add_child(_panel)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_label.add_theme_font_size_override("font_size", 20 if GameTheme.is_touch() else 17)
	_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)

## Shows the tip for `key` if this player has never seen it.
func hint(key: String) -> void:
	if _seen.get(key, false) or _queue.has(key) or not TEXTS.has(key):
		return
	_seen[key] = true
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SECTION, key, true)
	cfg.save(SETTINGS_PATH)
	_queue.append(key)
	if not _panel.visible:
		_show_next()

func _show_next() -> void:
	if _queue.is_empty():
		return
	var key: String = _queue.pop_front()
	_label.text = tr("Tip") + ": " + tr(str(TEXTS[key]))
	var w: float = minf(WIDTH * (1.4 if GameTheme.is_touch() else 1.0), size.x * 0.9)
	_label.custom_minimum_size = Vector2(w - 36.0, 0.0)
	_panel.size = Vector2.ZERO
	_panel.visible = true
	_panel.modulate.a = 0.0
	await get_tree().process_frame
	_panel.position = Vector2((size.x - _panel.size.x) / 2.0, size.y * 0.16)
	create_tween().tween_property(_panel, "modulate:a", 1.0, 0.2)
	var t: SceneTreeTimer = get_tree().create_timer(SHOW_SEC)
	_timer = t
	t.timeout.connect(func() -> void:
		if _timer == t:
			_close())

func _close() -> void:
	_timer = null
	if not _panel.visible:
		return
	var t: Tween = create_tween()
	t.tween_property(_panel, "modulate:a", 0.0, 0.2)
	t.tween_callback(func() -> void:
		_panel.visible = false
		_show_next())

## Forgets every tip (the pause menu's "show the tutorial again").
static func reset_all() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK and cfg.has_section(SECTION):
		cfg.erase_section(SECTION)
		cfg.save(SETTINGS_PATH)
