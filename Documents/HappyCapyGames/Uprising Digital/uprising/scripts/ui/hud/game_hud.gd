extends Control

## The in-game HUD over the 3D table.
## - Left rail: the seven main Actions in player-board order, each with its
##   cost and, when it can't be taken, why (tooltip and a dimmed button).
## - Right tray: options that only exist now and then - building in the Build
##   Phase (or when a card opens it), keeping 1 of 2 Feats, turning a hex you
##   just explored, cards with an ability to use. Hidden otherwise.
## - Top: the Chapter's seven phases, the score against The Empire and
##   Chaos, the selected hex, the latest happening.
## - Bottom: your faction's AP, resources, VP and cards, and the button that
##   ends your turn or moves the game on.
## play_board.gd feeds it the state through refresh() and submits what it
## emits through action_requested. No class_name - preload it.

signal action_requested(action: Dictionary)

const Style := preload("res://scripts/ui/hud/hud_style.gd")
const Rules := preload("res://scripts/ui/hud/action_rules.gd")
const PhaseTrack := preload("res://scripts/ui/hud/phase_track.gd")
const HexArt := preload("res://scripts/ui/lobby/hex_art.gd")
const FactionCatalog := preload("res://scripts/data/tables/faction_catalog.gd")
const MENU_SCENE := "res://scenes/MainMenu.tscn"
const PHASE_BANNER := "res://assets/art/ui/phases/phase_%d.png"
const LOG_SECONDS := 7.0
const CAMERA_HINT := "Right-drag turns the table, the wheel zooms, middle-drag or WASD pans, F reframes."

## action -> [name, what it does]
const ACTION_INFO: Dictionary = {
	"command": ["Command", "Units and Hero into the hex"],
	"move": ["Move", "Hero to the selected hex"],
	"explore": ["Explore", "Flip your Hero's hex"],
	"haven": ["Haven", "On your Hero's hex"],
	"trade": ["Trade", "Gain 1 Salt, your turn goes on"],
	"market": ["Market", "Buy 1 of 3 Items"],
	"quest": ["Quest", "Roll your Hero Dice"],
}

## True Solo Mode: the allied Hero takes the Hero actions while this is on.
var ally_acting: bool = false
var status_label: Label
var turn_label: Label

var _state: GameState = null
var _me: PlayerFactionState = null
var _my_faction: String = ""
var _selected: Vector2i = Vector2i.ZERO
var _has_selected: bool = false
var _card_db: Node
var _images: Node

var _phase_track: Control
var _chapter_label: Label
var _score: Dictionary = {}          # "you" / "empire" / "chaos" -> Label
var _hex_panel: PanelContainer
var _hex_title: Label
var _hex_sub: Label
var _hex_lines: Label
var _log_panel: PanelContainer
var _log_label: Label
var _log_time: float = -100.0
var _clock: float = 0.0
var _rail_hint: Label
var _hero_switch: HBoxContainer
var _action_buttons: Dictionary = {}  # action -> {"button", "content", "sub", "cost"}
var _bar_style: StyleBoxFlat
var _bar_token: Control
var _bar_faction: Label
var _bar_heroes: Label
var _ap_pips: HBoxContainer
var _ap_count: Label
var _res_labels: Dictionary = {}     # "Salt" / "Plunder" / "Food" / "VP" -> Label
var _cards_button: Button
var _exchange_button: Button
var _flow_primary: Button
var _flow_secondary: Button
var _flow_note: Label
var _tray: VBoxContainer
var _prompt: VBoxContainer
var _popup: Control = null
var _popup_kind: String = ""
var _banner: TextureRect
var _banner_tween: Tween
var _last_phase: int = -1
var _last_log: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_card_db = get_node_or_null("/root/CardDatabase")
	_images = get_node_or_null("/root/ImageManifest")
	_build_top()
	_build_rail()
	_build_bar()
	_build_tray()
	_build_banner()
	_show_log(CAMERA_HINT)


func _process(delta: float) -> void:
	_clock += delta
	if _log_panel.visible and _clock - _log_time > LOG_SECONDS:
		_log_panel.modulate.a = maxf(0.0, _log_panel.modulate.a - delta * 2.0)
		if _log_panel.modulate.a <= 0.0:
			_log_panel.visible = false


# ============================================================== building

func _panel(style: StyleBoxFlat = null) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style if style != null else Style.panel_style())
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


func _vbox(gap: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


func _hbox(gap: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _place(c: Control, preset: Control.LayoutPreset, left: float, top: float, right: float, bottom: float) -> void:
	add_child(c)
	c.set_anchors_preset(preset)
	c.offset_left = left
	c.offset_top = top
	c.offset_right = right
	c.offset_bottom = bottom


func _build_top() -> void:
	# Phase plaque, top centre.
	var phase := _panel()
	_place(phase, Control.PRESET_CENTER_TOP, -234, 10, 234, 64)
	phase.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var row := _hbox(14)
	phase.add_child(row)
	_phase_track = PhaseTrack.new()
	_phase_track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_phase_track)
	var col := _vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	status_label = Style.heading("Refresh phase", 22)
	status_label.name = "StatusLabel"
	col.add_child(status_label)
	var line := _hbox(8)
	col.add_child(line)
	_chapter_label = Style.label("Chapter 1 of 2", 14, Style.MUTED)
	line.add_child(_chapter_label)
	line.add_child(_spacer())
	turn_label = Style.label("", 15, Style.GOLD, Style.FONT_BOLD)
	turn_label.name = "TurnLabel"
	line.add_child(turn_label)

	# Score, top right: your VP against The Empire's and Chaos'.
	var score := _panel()
	_place(score, Control.PRESET_TOP_RIGHT, -260, 10, -14, 64)
	score.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	score.tooltip_text = "Beat both The Empire and Chaos on VP at the end of the last Chapter."
	var cols := _hbox(10)
	score.add_child(cols)
	for spec: Array in [["you", "You", Style.GOLD], ["empire", "Empire", Style.EMPIRE], ["chaos", "Chaos", Style.CHAOS]]:
		var c := _vbox(1)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(c)
		var bar := ColorRect.new()
		bar.color = spec[2]
		bar.custom_minimum_size = Vector2(0, 3)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(bar)
		c.add_child(Style.label(str(spec[1]), 13, Style.MUTED))
		var n := _hbox(4)
		c.add_child(n)
		n.add_child(Style.icon_rect("vp", 15))
		var num: Label = Style.label("0", 20, Style.BONE, Style.FONT_BOLD)
		n.add_child(num)
		_score[spec[0]] = num

	# The selected hex, under the score.
	_hex_panel = _panel(Style.accent_panel_style(Style.TEAL))
	_place(_hex_panel, Control.PRESET_TOP_RIGHT, -260, 72, -14, 72)
	_hex_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hex_panel.visible = false
	var hv := _vbox(2)
	_hex_panel.add_child(hv)
	_hex_title = Style.heading("", 20)
	hv.add_child(_hex_title)
	_hex_sub = Style.label("", 14, Style.MUTED)
	hv.add_child(_hex_sub)
	_hex_lines = Style.label("", 15)
	_hex_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hex_lines.custom_minimum_size = Vector2(210, 0)
	hv.add_child(_hex_lines)

	# The latest happening, a toast under the phase plaque.
	_log_panel = _panel(Style.panel_style(Color(0.016, 0.07, 0.082, 0.86)))
	(_log_panel.get_theme_stylebox("panel") as StyleBoxFlat).set_corner_radius_all(12)
	(_log_panel.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_top = 4
	(_log_panel.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_bottom = 5
	_place(_log_panel, Control.PRESET_CENTER_TOP, -230, 70, 230, 70)
	_log_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_label = Style.label("", 14, Style.MUTED)
	_log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_panel.add_child(_log_label)


func _build_rail() -> void:
	var rail := _panel()
	_place(rail, Control.PRESET_TOP_LEFT, 14, 76, 228, 76)
	var v := _vbox(4)
	rail.add_child(v)
	v.add_child(Style.heading("Actions", 20))
	_rail_hint = Style.label("", 12, Style.MUTED)
	_rail_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rail_hint.custom_minimum_size = Vector2(186, 0)
	v.add_child(_rail_hint)
	_hero_switch = _hbox(6)
	_hero_switch.visible = false
	v.add_child(_hero_switch)
	for action: String in Rules.MAIN_ACTIONS:
		v.add_child(_action_button(action))


func _action_button(action: String) -> Button:
	var b := Button.new()
	b.name = "%sButton" % str(ACTION_INFO[action][0])
	b.custom_minimum_size = Vector2(186, 42)
	Style.style_button(b)
	b.pressed.connect(_on_main_action.bind(action))
	var content := MarginContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("margin_left", 10)
	content.add_theme_constant_override("margin_right", 10)
	content.add_theme_constant_override("margin_top", 3)
	content.add_theme_constant_override("margin_bottom", 3)
	var row := _hbox(6)
	content.add_child(row)
	var col := _vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	var name_label: Label = Style.label(str(ACTION_INFO[action][0]), 18, Style.BONE, Style.FONT_BOLD)
	col.add_child(name_label)
	var sub: Label = Style.label(str(ACTION_INFO[action][1]), 12, Style.MUTED)
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(sub)
	var cost_holder := _hbox(0)
	cost_holder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(cost_holder)
	_action_buttons[action] = {"button": b, "content": content, "name": name_label, "sub": sub, "cost": cost_holder}
	return b


func _build_bar() -> void:
	_bar_style = Style.panel_style()
	var bar := _panel(_bar_style)
	_place(bar, Control.PRESET_BOTTOM_WIDE, 14, -72, -14, -14)
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var row := _hbox(14)
	bar.add_child(row)

	var who := _hbox(10)
	row.add_child(who)
	var token: HexArt = HexArt.new()
	token.custom_minimum_size = Vector2(46, 40)
	token.mouse_filter = Control.MOUSE_FILTER_IGNORE
	token.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar_token = token
	who.add_child(token)
	var names := _vbox(0)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_child(names)
	_bar_faction = Style.heading("", 20)
	names.add_child(_bar_faction)
	_bar_heroes = Style.label("", 13, Style.MUTED)
	names.add_child(_bar_heroes)

	var ap := _vbox(2)
	ap.alignment = BoxContainer.ALIGNMENT_CENTER
	ap.tooltip_text = "Action Points left this Chapter. Every Action costs 1."
	ap.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(ap)
	var ap_head := _hbox(6)
	ap.add_child(ap_head)
	ap_head.add_child(Style.label("AP", 13, Style.MUTED, Style.FONT_BOLD))
	_ap_count = Style.label("", 13, Style.BONE, Style.FONT_BOLD)
	ap_head.add_child(_ap_count)
	_ap_pips = _hbox(1)
	ap.add_child(_ap_pips)

	for spec: Array in [["Salt", "salt"], ["Plunder", "plunder"], ["Food", "food"], ["VP", "vp"]]:
		var cell := _hbox(6)
		cell.tooltip_text = str(spec[0])
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(cell)
		var ic: TextureRect = Style.icon_rect(str(spec[1]), 26)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(ic)
		var nums := _vbox(-4)
		nums.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_child(nums)
		var n: Label = Style.label("0", 22, Style.BONE, Style.FONT_BOLD)
		nums.add_child(n)
		nums.add_child(Style.label(str(spec[0]), 11, Style.MUTED))
		_res_labels[spec[0]] = n

	_exchange_button = Button.new()
	_exchange_button.text = "Exchange"
	_exchange_button.tooltip_text = "Exchange 3 of one resource for 1 of another, any time, for no AP."
	_exchange_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_exchange_button.custom_minimum_size = Vector2(0, 32)
	Style.style_button(_exchange_button)
	_exchange_button.pressed.connect(func() -> void: _open_popup("exchange"))
	row.add_child(_exchange_button)
	_cards_button = Button.new()
	_cards_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cards_button.custom_minimum_size = Vector2(0, 32)
	_cards_button.tooltip_text = "Your Feats and Items."
	Style.style_button(_cards_button)
	_cards_button.pressed.connect(func() -> void: _open_popup("cards"))
	row.add_child(_cards_button)

	row.add_child(_spacer())
	_flow_note = Style.label("", 15, Style.MUTED)
	_flow_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_flow_note)
	_flow_secondary = Button.new()
	_flow_secondary.custom_minimum_size = Vector2(84, 38)
	_flow_secondary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Style.style_button(_flow_secondary)
	_flow_secondary.add_theme_font_size_override("font_size", 17)
	_flow_secondary.pressed.connect(func() -> void: _on_flow(_flow_secondary))
	row.add_child(_flow_secondary)
	_flow_primary = Button.new()
	_flow_primary.custom_minimum_size = Vector2(124, 38)
	_flow_primary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Style.style_button(_flow_primary, true)
	_flow_primary.add_theme_font_size_override("font_size", 18)
	_flow_primary.pressed.connect(func() -> void: _on_flow(_flow_primary))
	row.add_child(_flow_primary)


func _build_tray() -> void:
	_tray = _vbox(8)
	_tray.alignment = BoxContainer.ALIGNMENT_END
	_place(_tray, Control.PRESET_BOTTOM_RIGHT, -260, -82, -14, -82)
	_tray.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tray.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Decisions the game waits on sit centre-bottom, above the faction bar.
	_prompt = _vbox(8)
	_place(_prompt, Control.PRESET_CENTER_BOTTOM, 0, -82, 0, -82)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _build_banner() -> void:
	_banner = TextureRect.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_place(_banner, Control.PRESET_CENTER_TOP, -215, 40, 215, 237)
	_banner.visible = false


# ============================================================== refresh

## Shows `state` as `my_faction` sees it, with `selected` as the chosen hex.
func refresh(state: GameState, my_faction: String, selected: Vector2i, has_selected: bool) -> void:
	_state = state
	_my_faction = my_faction
	_me = state.find_player(my_faction) if state != null else null
	_selected = selected
	_has_selected = has_selected
	if state == null:
		return
	if _me == null or not _me.has_ally():
		ally_acting = false
	_refresh_top()
	_refresh_rail()
	_refresh_bar()
	_refresh_tray()
	if int(state.phase) != _last_phase:
		if _last_phase != -1:
			_show_banner(int(state.phase))
		_last_phase = int(state.phase)
	if state.phase_log != _last_log and not state.phase_log.is_empty():
		_last_log = state.phase_log
		_show_log(state.phase_log)
	if _popup != null:
		_open_popup(_popup_kind)  # rebuild with the new state


## A rejected action, in the log toast in crimson.
func show_rejection(reason: String) -> void:
	_show_log("Not allowed: %s" % reason, Color(0.9, 0.45, 0.5))


func _refresh_top() -> void:
	var phase_i: int = int(_state.phase)
	_phase_track.set("current", phase_i)
	status_label.text = "%s phase" % Rules.PHASE_NAMES[phase_i]
	_chapter_label.text = "Chapter %d of %d" % [_state.chapter, _state.max_chapters]
	turn_label.text = ""
	if _state.phase == GameState.Phase.ACTIONS and not _state.players.is_empty():
		var current: PlayerFactionState = _state.players[_state.current_player_index % _state.players.size()]
		if current.faction == _my_faction:
			turn_label.text = "Your turn"
			turn_label.add_theme_color_override("font_color", Style.GOLD)
		else:
			turn_label.text = "%s's turn" % current.faction
			turn_label.add_theme_color_override("font_color", Style.MUTED)
	(_score["you"] as Label).text = str(_me.vp) if _me != null else "-"
	(_score["empire"] as Label).text = str(_state.empire_vp)
	(_score["chaos"] as Label).text = str(_state.chaos_vp)
	_refresh_hex_card()


func _refresh_hex_card() -> void:
	var tile: HexTileState = _state.get_hex(_selected) if _has_selected else null
	_hex_panel.visible = tile != null
	if tile == null:
		return
	var accent: Color = Style.TEAL
	var title: String = tile.hex_card_name if tile.explored and not tile.hex_card_name.is_empty() else "Unexplored hex"
	var sub: String = ""
	match tile.role:
		"outer":
			title = RegionMath.region_at(_state, _selected)
			sub = "Ice Waste, no Havens here"
		"capital":
			title = "The Capital"
			sub = "Uprising in the Capital" if _state.capital_flipped else "Seat of The Empire"
			accent = Style.EMPIRE
		"home":
			sub = "%s Home hex" % tile.owning_faction
			accent = FactionCatalog.accent(tile.owning_faction)
		"sea_tower":
			sub = "Sea Tower" if tile.explored else "Sea Tower, unexplored"
		_:
			sub = _terrain_of(tile.hex_card_name) if tile.explored else "Explore it to see what's there"
	if tile.curse:
		sub += ", Cursed"
		accent = Style.CHAOS
	_hex_title.text = title
	_hex_sub.text = sub
	var lines: Array[String] = []
	if not tile.haven_faction.is_empty():
		var defenses: Array[String] = []
		if tile.tower:
			defenses.append("Tower")
		if tile.wall:
			defenses.append("Wall")
		lines.append("%s Haven%s" % [tile.haven_faction, " with " + " and ".join(defenses) if not defenses.is_empty() else ""])
	var faction: String = tile.player_faction_here()
	if not faction.is_empty():
		var stack: Dictionary = tile.unit_stack(faction)
		var bits: Array[String] = []
		for unit_name: Variant in stack.keys():
			bits.append("%d %s" % [int(stack[unit_name]), unit_name])
		lines.append(", ".join(bits))
	if tile.garrison_level > 0:
		lines.append("Garrison, level %d" % tile.garrison_level)
	if tile.skeleton_count > 0:
		lines.append("%d Skeleton%s" % [tile.skeleton_count, "" if tile.skeleton_count == 1 else "s"])
	for n: Variant in EffectUtil.nemesis_at(_state, _selected):
		lines.append("%s, Threat %d" % [n.card_name, n.threat])
	for p: PlayerFactionState in _state.players:
		if p.hero_coord == _selected:
			lines.append("Hero %s" % p.hero_name)
		if p.has_ally() and p.ally_coord == _selected:
			lines.append("Allied Hero %s" % p.ally_hero_name)
	_hex_lines.text = "\n".join(lines)
	_hex_lines.visible = not lines.is_empty()
	(_hex_panel.get_theme_stylebox("panel") as StyleBoxFlat).border_color = accent


func _terrain_of(card_name: String) -> String:
	if _card_db == null:
		return ""
	for h: HexCard in _card_db.hexes_all:
		if h.card_name == card_name and h.lang == "EN":
			return h.terrain
	return ""


func _refresh_rail() -> void:
	var hint: String = "One Action a turn. Move and Trade don't end it."
	if _me == null:
		hint = "You're watching this game."
	elif _state.phase != GameState.Phase.ACTIONS:
		hint = "Actions open in the Actions phase. Trade works any time."
	elif not Rules.my_turn(_state, _me):
		hint = "Wait for your turn. Trade works any time."
	elif _me.has_acted_this_turn:
		hint = "Action taken. Move, Trade or end your turn."
	_rail_hint.text = hint
	_refresh_hero_switch()
	for action: String in Rules.MAIN_ACTIONS:
		var parts: Dictionary = _action_buttons[action]
		var reason: String = Rules.main_reason(_state, _card_db, _me, action, _selected, _has_selected, ally_acting)
		var b: Button = parts["button"]
		b.disabled = not reason.is_empty()
		b.tooltip_text = reason if not reason.is_empty() else _action_tooltip(action)
		(parts["content"] as Control).modulate.a = 1.0 if reason.is_empty() else 0.42
		var holder: HBoxContainer = parts["cost"]
		for child: Node in holder.get_children():
			child.queue_free()
		holder.add_child(Style.cost_row(_action_cost(action), 14))


func _action_cost(action: String) -> Array:
	var parts: Array = [["ap", "1"]]
	if _me == null:
		return parts
	if _me.wiles_ready and (action == "command" or action == "haven" or action == "move"):
		return [["ap", "0"]]
	match action:
		"command":
			var food: int = GameActions.CardAbilities.command_food_cost(_me)
			if food > 0:
				parts.append(["food", str(food)])
		"haven":
			parts.append(["plunder", str(Rules.haven_cost(_me))])
		"market":
			parts.append(["salt", ""])
	return parts


func _action_tooltip(action: String) -> String:
	match action:
		"command":
			return "Move your adjacent Units (up to 5) into the selected hex. Enemies there means combat. Ends your turn."
		"move":
			return "Move your Hero to the selected hex next to it. Doesn't end your turn."
		"explore":
			return "Flip the hex under your Hero and resolve it. Ends your turn."
		"haven":
			return "Build a Haven on your Hero's explored hex. Ends your turn."
		"trade":
			return "Gain 1 Salt. Heroes on one hex may also swap resources and Items. Doesn't end your turn."
		"market":
			return "Buy one of the 3 face-up Items your Hero can use. Ends your turn."
		"quest":
			return "Roll your Hero Dice against a face-up Quest. Ends your turn."
	return ""


func _refresh_hero_switch() -> void:
	var solo: bool = _me != null and _me.has_ally()
	_hero_switch.visible = solo
	if not solo:
		return
	for child: Node in _hero_switch.get_children():
		child.queue_free()
	for slot: Array in [[false, _me.hero_name], [true, _me.ally_hero_name]]:
		var b := Button.new()
		b.text = str(slot[1])
		b.toggle_mode = true
		b.button_pressed = ally_acting == bool(slot[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "Your allied Hero takes Move, Explore, Haven, Market, Quest and Trade." if bool(slot[0]) else "Your main Hero takes the Hero actions."
		Style.style_button(b, ally_acting == bool(slot[0]))
		var is_ally: bool = bool(slot[0])
		b.pressed.connect(func() -> void:
			ally_acting = is_ally
			if _state != null:
				refresh(_state, _my_faction, _selected, _has_selected))
		_hero_switch.add_child(b)


func _refresh_bar() -> void:
	var visible_me: bool = _me != null
	_ap_pips.get_parent().visible = visible_me
	if not visible_me:
		_bar_faction.text = "Watching"
		_bar_heroes.text = ""
		return
	var accent: Color = FactionCatalog.accent(_me.faction)
	(_bar_token as HexArt).texture = _tex(str(FactionCatalog.HOME_ATLAS.get(_me.faction, "")))
	(_bar_token as HexArt).region = FactionCatalog.home_region(_me.faction)
	(_bar_token as HexArt).border_color = accent
	_bar_faction.text = _me.faction
	_bar_faction.add_theme_color_override("font_color", accent.lerp(Style.BONE, 0.35))
	_bar_heroes.text = "%s and %s" % [_me.hero_name, _me.ally_hero_name] if _me.has_ally() else _me.hero_name
	for child: Node in _ap_pips.get_children():
		child.queue_free()
	for i: int in range(_me.max_action_points):
		var pip: TextureRect = Style.icon_rect("ap", 13)
		if i >= _me.action_points:
			pip.modulate = Color(1, 1, 1, 0.2)
		_ap_pips.add_child(pip)
	_ap_count.text = "%d of %d" % [_me.action_points, _me.max_action_points]
	(_res_labels["Salt"] as Label).text = str(_me.salt)
	(_res_labels["Plunder"] as Label).text = str(_me.plunder)
	(_res_labels["Food"] as Label).text = str(_me.food)
	(_res_labels["VP"] as Label).text = str(_me.vp)
	var limit: int = GameActions.CardAbilities.SOLO_CARD_LIMIT if _me.has_ally() else GameActions.CardAbilities.CARD_LIMIT
	_cards_button.text = "Cards %d of %d" % [_me.feats_in_play.size() + _me.items_in_hand.size(), limit]
	_exchange_button.disabled = maxi(_me.salt, maxi(_me.plunder, _me.food)) < 3
	_refresh_flow()


func _refresh_flow() -> void:
	var flow: Dictionary = Rules.flow(_state, _me)
	var primary: Array = flow["primary"]
	var secondary: Array = flow["secondary"]
	_flow_primary.visible = not primary.is_empty()
	if not primary.is_empty():
		_flow_primary.text = str(primary[0])
		_flow_primary.set_meta("action", str(primary[1]))
	_flow_secondary.visible = not secondary.is_empty()
	if not secondary.is_empty():
		_flow_secondary.text = str(secondary[0])
		_flow_secondary.set_meta("action", str(secondary[1]))
		_flow_secondary.tooltip_text = "Stop taking turns for the rest of this Chapter." if str(secondary[1]) == "pass" else ""
	_flow_primary.tooltip_text = "Finish building for this Chapter." if not primary.is_empty() and str(primary[1]) == "pass" else ""
	_flow_note.text = str(flow["note"])
	_flow_note.visible = not str(flow["note"]).is_empty()


# ============================================================== tray

func _refresh_tray() -> void:
	for child: Node in _tray.get_children():
		child.queue_free()
	for child2: Node in _prompt.get_children():
		child2.queue_free()
	if _me == null:
		return
	var panels: int = 0
	var orient: Array[Vector2i] = Rules.orientable(_state, _me)
	if not orient.is_empty():
		_tray.add_child(_turn_hex_panel(orient[0]))
		panels += 1
	if Rules.build_open(_state, _me, _selected):
		_tray.add_child(_build_panel())
		panels += 2  # tall
	if _state.phase == GameState.Phase.ACTIONS and Rules.my_turn(_state, _me):
		var cards: Array[String] = Rules.usable_cards(_state, _me)
		if not cards.is_empty():
			_tray.add_child(_cards_panel(cards))
			panels += 1
	if not _me.pending_feats.is_empty() or not _me.ally_pending_feats.is_empty():
		_prompt.add_child(_feat_panel())
	# A crowded tray would run into the hex card - the tray wins.
	if panels >= 3:
		_hex_panel.visible = false


func _tray_panel(title: String, hint: String, accent: Color) -> Array:
	var panel := _panel(Style.accent_panel_style(accent))
	panel.custom_minimum_size = Vector2(246, 0)
	var v := _vbox(5)
	panel.add_child(v)
	v.add_child(Style.label(title, 17, Style.BONE, Style.FONT_BOLD))
	if not hint.is_empty():
		var h: Label = Style.label(hint, 13, Style.MUTED)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.custom_minimum_size = Vector2(210, 0)
		v.add_child(h)
	return [panel, v]


func _small_button(text: String, reason: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not reason.is_empty()
	b.tooltip_text = reason
	b.custom_minimum_size = Vector2(0, 28)
	Style.style_button(b, primary)
	b.add_theme_font_size_override("font_size", 15)
	return b


func _turn_hex_panel(coord: Vector2i) -> Control:
	var tile: HexTileState = _state.get_hex(coord)
	var parts: Array = _tray_panel("Turn the hex you explored", "%s has impassable edges. Units can't cross them." % tile.hex_card_name, Style.GOLD)
	var row := _hbox(8)
	(parts[1] as VBoxContainer).add_child(row)
	for spec: Array in [["Turn left", -1], ["Turn right", 1]]:
		var b: Button = _small_button(str(spec[0]), "")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var step: int = int(spec[1])
		b.pressed.connect(func() -> void:
			action_requested.emit({"type": "orient", "at": _coord_dict(coord), "rotation": posmod(tile.rotation + step, 6)}))
		row.add_child(b)
	return parts[0]


func _feat_panel() -> Control:
	var parts: Array = _tray_panel("Keep one Feat", "Click the Feat to keep. The other goes under your Feat deck.", Style.GOLD)
	var panel: PanelContainer = parts[0]
	panel.custom_minimum_size = Vector2(0, 0)
	var v: VBoxContainer = parts[1]
	var groups := _hbox(22)
	v.add_child(groups)
	for slot: Array in [[false, _me.pending_feats, _me.hero_name], [true, _me.ally_pending_feats, _me.ally_hero_name]]:
		var pending: Array = slot[1]
		if pending.is_empty():
			continue
		var group := _vbox(4)
		groups.add_child(group)
		if _me.has_ally():
			group.add_child(Style.label(str(slot[2]), 13, Style.MUTED, Style.FONT_BOLD))
		var row := _hbox(8)
		group.add_child(row)
		for feat: Variant in pending:
			var card: Control = _card_image("Feats", str(feat), Vector2(76, 112))
			card.mouse_filter = Control.MOUSE_FILTER_STOP
			card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			card.tooltip_text = "Keep %s\n%s" % [feat, _card_text("Feats", str(feat))]
			var action: Dictionary = {"type": "pick_feat", "feat": str(feat)}
			if bool(slot[0]):
				action["hero_slot"] = "ally"
			card.gui_input.connect(func(event: InputEvent) -> void:
				var mb: InputEventMouseButton = event as InputEventMouseButton
				if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					action_requested.emit(action))
			row.add_child(card)
	return parts[0]


func _build_panel() -> Control:
	var site: String = Rules.build_site_reason(_state, _me, _selected, _has_selected)
	var hint: String = site
	if site.is_empty():
		var tile: HexTileState = _state.get_hex(_selected)
		hint = "On your Haven here." if tile.haven_faction == _me.faction else "No Havens yet: your Hero brings the Units here."
	var parts: Array = _tray_panel("Build", hint, Style.TEAL)
	var v: VBoxContainer = parts[1]
	var board: PlayerboardTable.FactionBoard = PlayerboardTable.get_board(_me.faction)
	if board == null:
		return parts[0]
	for unit: PlayerboardTable.UnitEntry in board.units:
		var row := _hbox(6)
		v.add_child(row)
		var name_label: Label = Style.label(unit.name, 15, Style.BONE, Style.FONT_BOLD)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(Style.cost_row(Style.board_cost_parts(unit.cost), 13))
		var reason: String = site if not site.is_empty() else Rules.unit_reason(_state, _me, _selected, unit)
		var b: Button = _small_button("Build", reason)
		b.tooltip_text = reason if not reason.is_empty() else "%s, %d left in your reserve" % [unit.name, NemesisAI.NemesisCards.reserve_left(_state, _me, unit.name)]
		var unit_name: String = unit.name
		var cost: Dictionary = unit.cost
		b.pressed.connect(func() -> void:
			var action: Dictionary = {"type": "build_unit", "unit": unit_name, "at": _coord_dict(_selected)}
			action.merge(Rules.payment_for(_me, cost))
			action_requested.emit(action))
		row.add_child(b)
	var defenses := _hbox(8)
	v.add_child(defenses)
	for kind: String in ["Tower", "Wall"]:
		var reason2: String = Rules.defense_reason(_state, _me, _selected, kind) if _has_selected else "Select one of your Havens."
		var b2: Button = _small_button("%s, 1 Plunder" % kind, reason2)
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var k: String = kind
		b2.pressed.connect(func() -> void:
			action_requested.emit({"type": "build_defense", "kind": k, "at": _coord_dict(_selected)}))
		defenses.add_child(b2)
	return parts[0]


func _cards_panel(cards: Array[String]) -> Control:
	var parts: Array = _tray_panel("Use a card", "", Style.GOLD)
	var v: VBoxContainer = parts[1]
	for card: String in cards:
		var row := _hbox(6)
		v.add_child(row)
		var name_label: Label = Style.label(card, 15, Style.BONE, Style.FONT_BOLD)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		name_label.tooltip_text = _card_text("Feats", card) if _is_feat(card) else _card_text("Items", card)
		row.add_child(name_label)
		var needs_hex: String = str(Rules.TARGETED_CARDS.get(card, ""))
		var reason: String = "Select a hex first." if not needs_hex.is_empty() and not _has_selected else ""
		var use: Button = _small_button("Use", reason)
		var c: String = card
		use.pressed.connect(func() -> void: action_requested.emit(_card_action(c, needs_hex, false)))
		row.add_child(use)
		if Rules.DISCARD_OPTION.has(card):
			var more: Button = _small_button("Discard", reason)
			more.tooltip_text = "Discard it for the stronger effect."
			more.pressed.connect(func() -> void: action_requested.emit(_card_action(c, needs_hex, true)))
			row.add_child(more)
	return parts[0]


func _card_action(card: String, needs_hex: String, discard: bool) -> Dictionary:
	var action: Dictionary = {"type": "use_card", "card": card}
	if not needs_hex.is_empty():
		action[needs_hex] = _coord_dict(_selected)
	if discard:
		action["discard"] = true
	return action


# ============================================================== popups

func _close_popup() -> void:
	if _popup != null:
		_popup.queue_free()
	_popup = null
	_popup_kind = ""


func _open_popup(kind: String) -> void:
	if _popup != null:
		_popup.queue_free()
		_popup = null
	_popup_kind = kind
	var panel := _panel()
	add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := _vbox(10)
	panel.add_child(v)
	var head := _hbox(10)
	v.add_child(head)
	var title: Label = Style.heading("", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close: Button = _small_button("Close", "")
	close.pressed.connect(_close_popup)
	head.add_child(close)
	match kind:
		"market":
			title.text = "Market"
			_fill_market(v)
		"quest":
			title.text = "Quests"
			_fill_quests(v)
		"exchange":
			title.text = "Exchange"
			_fill_exchange(v)
		"cards":
			title.text = "Your cards"
			_fill_cards(v)
		"result":
			head.remove_child(close)
			close.queue_free()
			_fill_result(v, title)
	_popup = panel
	# Zero-size rect on the screen centre that grows both ways to fit.
	panel.offset_left = 0
	panel.offset_right = 0
	panel.offset_top = 0
	panel.offset_bottom = 0


func _fill_market(v: VBoxContainer) -> void:
	var note: Label = Style.label("1 AP plus the Item's Salt. Your Hero must be able to use it. The Market refills at once.", 14, Style.MUTED)
	v.add_child(note)
	var row := _hbox(16)
	v.add_child(row)
	# Turn, phase, AP or an Action already taken block every Item; otherwise
	# each Item says for itself what's missing.
	var gate: String = Rules.main_reason(_state, _card_db, _me, "market", _selected, _has_selected, ally_acting)
	if gate == "You can't afford or use any Item.":
		gate = ""
	for item: String in _state.item_market:
		var col := _vbox(6)
		row.add_child(col)
		col.add_child(_card_image("Items", item, Vector2(150, 220)))
		var price := _hbox(6)
		col.add_child(price)
		var cost: int = Rules.market_cost(_state, _card_db, _me, item) if _me != null else GameActions.item_cost(_card_db, item)
		price.add_child(Style.cost_row([["salt", str(cost)]], 16))
		price.add_child(_spacer())
		var reason: String = gate
		if reason.is_empty() and _me != null:
			if ally_acting and _me.has_ally():
				_me.swap_heroes()
				reason = Rules.market_reason(_state, _card_db, _me, item)
				_me.swap_heroes()
			else:
				reason = Rules.market_reason(_state, _card_db, _me, item)
		var buy: Button = _small_button("Buy", reason, true)
		var it: String = item
		buy.pressed.connect(func() -> void:
			_close_popup()
			action_requested.emit({"type": "market", "item": it}))
		price.add_child(buy)


func _fill_quests(v: VBoxContainer) -> void:
	v.add_child(Style.label("1 AP. Roll your Hero Dice: solve the Quest for its reward, fail and its fail effect strikes.", 14, Style.MUTED))
	var row := _hbox(16)
	v.add_child(row)
	var reason: String = Rules.main_reason(_state, _card_db, _me, "quest", _selected, _has_selected, ally_acting)
	for quest: String in _state.quest_row:
		var col := _vbox(6)
		row.add_child(col)
		col.add_child(_card_image("Quests", quest, Vector2(160, 262)))
		var go: Button = _small_button("Attempt", reason, true)
		var q: String = quest
		go.pressed.connect(func() -> void:
			_close_popup()
			action_requested.emit({"type": "quest", "quest": q}))
		col.add_child(go)


func _fill_exchange(v: VBoxContainer) -> void:
	v.add_child(Style.label("3 of one resource for 1 of another. Any time, no AP.", 14, Style.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	for give: String in ["Salt", "Plunder", "Food"]:
		for get_res: String in ["Salt", "Plunder", "Food"]:
			if give == get_res:
				continue
			var have: int = GameActions._res(_me, give) if _me != null else 0
			var b: Button = _small_button("", "Needs 3 %s." % give if have < 3 else "")
			b.custom_minimum_size = Vector2(150, 34)
			var row := _hbox(4)
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			b.add_child(row)
			row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			row.add_child(Style.cost_row([[Style.RESOURCE_ICON[give], "3"]], 16))
			row.add_child(Style.label("for", 14, Style.MUTED))
			row.add_child(Style.cost_row([[Style.RESOURCE_ICON[get_res], "1"]], 16))
			row.modulate.a = 1.0 if have >= 3 else 0.4
			var g: String = give
			var r: String = get_res
			b.pressed.connect(func() -> void: action_requested.emit({"type": "exchange", "give": g, "get": r}))
			grid.add_child(b)


func _fill_cards(v: VBoxContainer) -> void:
	if _me == null:
		return
	var groups: Array = [[_me.hero_name, false]]
	if _me.has_ally():
		groups.append([_me.ally_hero_name, true])
	for group: Variant in groups:
		var g: Array = group
		var ally: bool = bool(g[1])
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		flow.custom_minimum_size = Vector2(620, 0)
		var count: int = 0
		for f: String in _me.feats_in_play:
			if _me.ally_cards.has(f) == ally:
				flow.add_child(_hand_card("Feats", f, _me.flipped_feats.has(f)))
				count += 1
		for it: String in _me.items_in_hand:
			if _me.ally_cards.has(it) == ally:
				flow.add_child(_hand_card("Items", it, _me.flipped_items.has(it)))
				count += 1
		if _me.has_ally():
			v.add_child(Style.label("%s, %s" % [str(g[0]), "allied Hero" if ally else "main Hero"], 15, Style.MUTED, Style.FONT_BOLD))
		if count == 0:
			v.add_child(Style.label("No cards yet.", 14, Style.MUTED))
		else:
			v.add_child(flow)


func _hand_card(sheet: String, card: String, flipped: bool) -> Control:
	var c: Control = _card_image(sheet, card, Vector2(96, 141))
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.tooltip_text = "%s%s\n%s" % [card, " (flipped until the next Refresh)" if flipped else "", _card_text(sheet, card)]
	if flipped:
		c.modulate = Color(0.5, 0.5, 0.55)
	return c


func _fill_result(v: VBoxContainer, title: Label) -> void:
	var verdict: String = ChapterFlow.check_win_loss(_state)
	title.text = "The Uprising succeeds" if verdict == "win" else "The Uprising fails"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Style.GOLD if verdict == "win" else Color(0.92, 0.5, 0.55))
	var lines: Array[String] = []
	for p: PlayerFactionState in _state.players:
		lines.append("%s: %d VP" % [p.faction, p.vp])
	lines.append("The Empire: %d VP" % _state.empire_vp)
	lines.append("Chaos: %d VP" % _state.chaos_vp)
	var l: Label = Style.label("\n".join(lines), 18)
	v.add_child(l)
	v.add_child(Style.label("Every faction had to beat both The Empire and Chaos.", 14, Style.MUTED))
	var back: Button = _small_button("Back to the menu", "", true)
	back.custom_minimum_size = Vector2(0, 38)
	back.pressed.connect(func() -> void:
		var net: Node = get_node("/root/NetworkManager")
		net.leave_lobby()
		get_tree().change_scene_to_file(MENU_SCENE))
	v.add_child(back)


func _card_image(sheet: String, card: String, size: Vector2) -> Control:
	var r := TextureRect.new()
	r.custom_minimum_size = size
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path: String = _images.get_image_path(sheet, "EN", card, "Name") if _images != null else ""
	r.texture = _tex(path)
	if r.texture == null:
		var fallback := PanelContainer.new()
		fallback.custom_minimum_size = size
		fallback.add_theme_stylebox_override("panel", Style.panel_style(Color(0.08, 0.12, 0.13, 0.95)))
		var l: Label = Style.label(card, 14)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.add_child(l)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.queue_free()
		return fallback
	return r


func _card_text(sheet: String, card: String) -> String:
	if _card_db == null:
		return ""
	if sheet == "Feats":
		for f: FeatCard in _card_db.feats_all:
			if f.card_name == card and f.lang == "EN":
				return "%s: %s" % [f.phase, f.text] if not f.phase.is_empty() else f.text
	elif sheet == "Items":
		for it: ItemCard in _card_db.items_all:
			if it.card_name == card and it.lang == "EN":
				return "%s: %s" % [it.phases, it.text] if not it.phases.is_empty() else it.text
	return ""


func _is_feat(card: String) -> bool:
	return _me != null and _me.feats_in_play.has(card)


# ============================================================== events

func _on_main_action(action: String) -> void:
	match action:
		"market":
			_open_popup("market")
		"quest":
			_open_popup("quest")
		"move", "command":
			action_requested.emit({"type": action, "to": _coord_dict(_selected)})
		_:
			action_requested.emit({"type": action})


func _on_flow(b: Button) -> void:
	var action: String = str(b.get_meta("action", ""))
	if action.is_empty():
		_open_popup("result")
	else:
		action_requested.emit({"type": action})


func _show_log(text: String, color: Color = Style.MUTED) -> void:
	_log_label.text = text
	_log_label.add_theme_color_override("font_color", color)
	_log_panel.visible = true
	_log_panel.modulate.a = 1.0
	_log_time = _clock


func _show_banner(phase_i: int) -> void:
	var tex: Texture2D = _tex(PHASE_BANNER % (phase_i + 1))
	if tex == null:
		return
	_banner.texture = tex
	_banner.visible = true
	_banner.modulate.a = 0.0
	_banner.offset_top = 10.0
	_banner.offset_bottom = 207.0
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.22)
	_banner_tween.tween_property(_banner, "offset_top", 52.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_property(_banner, "offset_bottom", 249.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.chain().tween_interval(1.1)
	_banner_tween.chain().tween_property(_banner, "modulate:a", 0.0, 0.35)
	_banner_tween.chain().tween_callback(func() -> void: _banner.visible = false)


func _tex(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _coord_dict(c: Vector2i) -> Dictionary:
	return {"x": c.x, "y": c.y}
