extends Control

## Cards the game turns up, shown big for a moment, one after another: the
## Refresh (the new Quests, the Market's Items, the Druids with their
## Aether), the Chapter's Event, and every Legion and Horde entering play -
## the card first, then its Immediate effect. A click moves on; the table
## stays visible (no dimming). The HUD feeds it from state changes.
## No class_name - preload it.

const Style := preload("res://scripts/ui/hud/hud_style.gd")
const AETHER := Color(0.96, 0.66, 0.24)
const DURATION: Dictionary = {"refresh": 6.0, "event": 6.5, "nemesis": 5.0}

var _queue: Array = []
var _panel: PanelContainer = null
var _timer: float = 0.0
var _closing: bool = false
var _images: Node
var _card_db: Node


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_images = get_node_or_null("/root/ImageManifest")
	_card_db = get_node_or_null("/root/CardDatabase")


func _process(delta: float) -> void:
	if _panel == null:
		if not _queue.is_empty():
			_show(_queue.pop_front())
		return
	if _closing:
		return
	_timer -= delta
	if _timer <= 0.0:
		_dismiss()


func is_busy() -> bool:
	return _panel != null or not _queue.is_empty()


## The Refresh phase dealt `quests` and `items`; `druids` = [{name, aether, gained}].
func reveal_refresh(chapter: int, quests: Array, items: Array, druids: Array) -> void:
	_queue.append({"kind": "refresh", "chapter": chapter, "quests": quests.duplicate(), "items": items.duplicate(), "druids": druids.duplicate(true)})


func reveal_event(chapter: int, event_name: String) -> void:
	_queue.append({"kind": "event", "chapter": chapter, "name": event_name})


## A Legion or Horde entered play: `kind` "legion" / "horde".
func reveal_nemesis(kind: String, card_name: String, threat: int, where: String) -> void:
	_queue.append({"kind": "nemesis", "side": kind, "name": card_name, "threat": threat, "where": where})


# ============================================================== showing

func _show(entry: Dictionary) -> void:
	_closing = false
	_timer = float(DURATION.get(str(entry["kind"]), 5.0))
	_panel = PanelContainer.new()
	var accent: Color = Style.GOLD
	if str(entry["kind"]) == "nemesis":
		accent = Style.EMPIRE if str(entry["side"]) == "legion" else Style.CHAOS
	_panel.add_theme_stylebox_override("panel", Style.accent_panel_style(accent, Color(0.02, 0.08, 0.09, 0.94)))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_panel.tooltip_text = "Click to move on."
	_panel.gui_input.connect(func(event: InputEvent) -> void:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_dismiss())
	add_child(_panel)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.offset_left = 0
	_panel.offset_right = 0
	_panel.offset_top = -30
	_panel.offset_bottom = -30
	var v := _vbox(10)
	_panel.add_child(v)
	match str(entry["kind"]):
		"refresh":
			_build_refresh(v, entry)
		"event":
			_build_event(v, entry)
		"nemesis":
			_build_nemesis(v, entry)
	_panel.modulate.a = 0.0
	var t: Tween = create_tween()
	t.tween_property(_panel, "modulate:a", 1.0, 0.22)


func _dismiss() -> void:
	if _panel == null or _closing:
		return
	_closing = true
	var p: PanelContainer = _panel
	var t: Tween = create_tween()
	t.tween_property(p, "modulate:a", 0.0, 0.18)
	t.tween_callback(func() -> void:
		p.queue_free()
		if _panel == p:
			_panel = null
		_closing = false)


func _build_refresh(v: VBoxContainer, e: Dictionary) -> void:
	v.add_child(Style.heading("Chapter %d: the Refresh phase" % int(e["chapter"]), 24))
	var row := _hbox(26)
	v.add_child(row)
	row.add_child(_group("New Quests", "Quests", e["quests"], Vector2(96, 159), {}))
	row.add_child(_group("The Market", "Items", e["items"], Vector2(94, 138), {}))
	var badges: Dictionary = {}
	var names: Array = []
	for d: Variant in (e["druids"] as Array):
		var dd: Dictionary = d
		names.append(str(dd["name"]))
		var text: String = "%d Aether" % int(dd["aether"])
		if int(dd.get("gained", 0)) > 0:
			text = "+%d, %d Aether" % [int(dd["gained"]), int(dd["aether"])]
		badges[str(dd["name"])] = text
	if not names.is_empty():
		v.add_child(_group("The Druids", "Druids", names, Vector2(84, 123), badges))


func _build_event(v: VBoxContainer, e: Dictionary) -> void:
	var event_name: String = str(e["name"])
	v.add_child(Style.heading("Chapter %d's Event" % int(e["chapter"]), 24))
	v.add_child(_card("Events", event_name, Vector2(420, 254), 0.0))
	var text: String = _event_text(event_name)
	if not text.is_empty():
		var l: Label = Style.label(text, 15, Style.BONE)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(420, 0)
		v.add_child(l)


func _build_nemesis(v: VBoxContainer, e: Dictionary) -> void:
	var legion: bool = str(e["side"]) == "legion"
	var card_name: String = str(e["name"])
	v.add_child(Style.heading("%s enters play" % ("A Legion of The Empire" if legion else "A Horde of Chaos"), 24))
	var row := _hbox(16)
	v.add_child(row)
	row.add_child(_card("Legions" if legion else "Hordes", card_name, Vector2(150, 248), 0.0))
	var col := _vbox(6)
	col.custom_minimum_size = Vector2(300, 0)
	row.add_child(col)
	col.add_child(Style.label(card_name, 22, Style.BONE, Style.FONT_BOLD))
	col.add_child(Style.label("Threat %d, on %s" % [int(e["threat"]), str(e["where"])], 15, Style.MUTED))
	# The Immediate effect follows the card a moment later.
	var effect := _vbox(4)
	effect.modulate.a = 0.0
	col.add_child(effect)
	effect.add_child(Style.label("Immediate effect", 15, Style.GOLD, Style.FONT_BOLD))
	var text: Label = Style.label(_immediate_text(card_name, legion), 15, Style.BONE)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(300, 0)
	effect.add_child(text)
	var t: Tween = create_tween()
	t.tween_interval(0.9)
	t.tween_property(effect, "modulate:a", 1.0, 0.35)


func _group(title: String, sheet: String, cards: Array, size: Vector2, badges: Dictionary) -> Control:
	var col := _vbox(6)
	col.add_child(Style.label(title, 15, Style.MUTED, Style.FONT_BOLD))
	var row := _hbox(8)
	col.add_child(row)
	var i: int = 0
	for c: Variant in cards:
		var cell := _vbox(3)
		row.add_child(cell)
		cell.add_child(_card(sheet, str(c), size, 0.08 * float(i)))
		if badges.has(str(c)):
			var b: Label = Style.label(str(badges[str(c)]), 13, AETHER, Style.FONT_BOLD)
			b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.add_child(b)
		i += 1
	if cards.is_empty():
		col.add_child(Style.label("None left", 14, Style.MUTED))
	return col


## A card image that fades in after `delay`.
func _card(sheet: String, card: String, size: Vector2, delay: float) -> Control:
	var path: String = _images.get_image_path(sheet, "EN", card, "Name") if _images != null else ""
	var c: Control = null
	if not path.is_empty() and ResourceLoader.exists(path):
		var r := TextureRect.new()
		r.texture = load(path) as Texture2D
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		c = r
	else:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", Style.panel_style(Color(0.08, 0.12, 0.13, 0.95)))
		var l: Label = Style.label(card, 14)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p.add_child(l)
		c = p
	c.custom_minimum_size = size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if delay > 0.0:
		c.modulate.a = 0.0
		var t: Tween = create_tween()
		t.tween_interval(delay)
		t.tween_property(c, "modulate:a", 1.0, 0.25)
	return c


func _immediate_text(card_name: String, legion: bool) -> String:
	if _card_db == null:
		return ""
	if legion:
		for l: LegionCard in _card_db.legions_all:
			if l.card_name == card_name and l.lang == "EN":
				return l.immediate
	else:
		for h: HordeCard in _card_db.hordes_all:
			if h.card_name == card_name and h.lang == "EN":
				return h.immediate
	return ""


func _event_text(event_name: String) -> String:
	if _card_db == null:
		return ""
	for e: EventCard in _card_db.events_all:
		if e.card_name == event_name and e.lang == "EN":
			return "%s\n%s" % [e.effect_1, e.effect_2] if not e.effect_2.is_empty() else e.effect_1
	return ""


func _hbox(gap: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


func _vbox(gap: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v
