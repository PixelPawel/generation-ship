extends Control

## The HUD's pull-out drawers - what lay on the printed board's tracks and
## sideboards. Tabs in the top-left corner open and close them; a drawer
## slides out right of the action rail, so the rail stays usable.
## - Druids: the four in play, their Aether, when they gain it.
## - Nemesis: Legions and Hordes on the map in Initiative order (Threat,
##   Activation Tokens, Target), both decks, both Graveyards.
## - Market / Quests: the three face-up cards, to buy or attempt.
## - Events: this Chapter's Event, face down until the Events phase.
## - Score (the score plaque): VP so far and what this Chapter's Scoring adds.
## - Cards (the faction bar): your Feats and Items.
## No class_name - preload it.

signal action_requested(action: Dictionary)

const Style := preload("res://scripts/ui/hud/hud_style.gd")
const Rules := preload("res://scripts/ui/hud/action_rules.gd")
const FactionCatalog := preload("res://scripts/data/tables/faction_catalog.gd")
const TABS: Array = [["druids", "Druids"], ["nemesis", "Nemesis"], ["market", "Market"], ["quests", "Quests"], ["events", "Events"]]
const TITLES: Dictionary = {
	"druids": "Druids", "nemesis": "The Nemesis", "market": "Market", "quests": "Quests",
	"events": "Events", "score": "Victory Points", "cards": "Your cards",
}
const BODY_MAX_HEIGHT: float = 420.0
const AETHER := Color(0.96, 0.66, 0.24)

var open_kind: String = ""
var _state: GameState = null
var _me: PlayerFactionState = null
var _my_faction: String = ""
var _selected: Vector2i = Vector2i.ZERO
var _has_selected: bool = false
var _ally_acting: bool = false
var _card_db: Node
var _images: Node
var _tabs: Dictionary = {}           # kind -> Button
var _drawer: PanelContainer
var _drawer_title: Label
var _scroll: ScrollContainer
var _body: VBoxContainer
var _tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_db = get_node_or_null("/root/CardDatabase")
	_images = get_node_or_null("/root/ImageManifest")
	_build_tabs()
	_build_drawer()


func _build_tabs() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	row.set_anchors_preset(Control.PRESET_TOP_LEFT)
	row.offset_left = 14
	row.offset_top = 18
	for tab: Array in TABS:
		var b := Button.new()
		b.text = str(tab[1])
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 30)
		_style_tab(b, false)
		var kind: String = str(tab[0])
		b.pressed.connect(func() -> void: toggle(kind))
		row.add_child(b)
		_tabs[kind] = b


func _build_drawer() -> void:
	_drawer = PanelContainer.new()
	_drawer.add_theme_stylebox_override("panel", Style.panel_style())
	_drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_drawer)
	_drawer.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_drawer.offset_left = 238
	_drawer.offset_top = 76
	_drawer.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	_drawer_title = Style.heading("", 22)
	_drawer_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_drawer_title)
	var close := Button.new()
	close.text = "Hide"
	close.custom_minimum_size = Vector2(0, 28)
	Style.style_button(close)
	close.add_theme_font_size_override("font_size", 15)
	close.pressed.connect(close_drawer)
	head.add_child(close)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)


# ============================================================== open / close

func toggle(kind: String) -> void:
	if open_kind == kind:
		close_drawer()
	else:
		open(kind)


func open(kind: String) -> void:
	var was_open: bool = not open_kind.is_empty()
	open_kind = kind
	_rebuild()
	_sync_tabs()
	if was_open:
		return
	_drawer.visible = true
	_drawer.modulate.a = 0.0
	_drawer.offset_left = 210
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_drawer, "modulate:a", 1.0, 0.16)
	_tween.tween_property(_drawer, "offset_left", 238.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func close_drawer() -> void:
	if open_kind.is_empty():
		return
	open_kind = ""
	_sync_tabs()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_drawer, "modulate:a", 0.0, 0.12)
	_tween.tween_property(_drawer, "offset_left", 210.0, 0.14)
	_tween.chain().tween_callback(func() -> void: _drawer.visible = false)


func _sync_tabs() -> void:
	for kind: Variant in _tabs.keys():
		var b: Button = _tabs[kind]
		b.set_pressed_no_signal(open_kind == str(kind))
		_style_tab(b, open_kind == str(kind))


## Tabs are compact: they share the top-left corner with nothing else, but
## must stop short of the phase plaque at the base 1152 px width.
func _style_tab(b: Button, active: bool) -> void:
	Style.style_button(b, active)
	b.add_theme_font_size_override("font_size", 14)
	for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb: StyleBoxFlat = b.get_theme_stylebox(st) as StyleBoxFlat
		if sb != null:
			sb.content_margin_left = 7
			sb.content_margin_right = 7


## The HUD hands over the state on every update.
func refresh(state: GameState, me: PlayerFactionState, my_faction: String, selected: Vector2i, has_selected: bool, ally_acting: bool) -> void:
	_state = state
	_me = me
	_my_faction = my_faction
	_selected = selected
	_has_selected = has_selected
	_ally_acting = ally_acting
	if state == null:
		return
	var on_map: int = state.legions.size() + state.hordes.size()
	(_tabs["nemesis"] as Button).text = "Nemesis %d" % on_map if on_map > 0 else "Nemesis"
	if not open_kind.is_empty():
		_rebuild()


func _rebuild() -> void:
	if _state == null:
		return
	for child: Node in _body.get_children():
		child.queue_free()
	_drawer_title.text = str(TITLES.get(open_kind, ""))
	match open_kind:
		"druids":
			_fill_druids()
		"nemesis":
			_fill_nemesis()
		"market":
			_fill_market()
		"quests":
			_fill_quests()
		"events":
			_fill_events()
		"score":
			_fill_score()
		"cards":
			_fill_cards()
	_fit.call_deferred()


## The scroll area takes the content's height, up to BODY_MAX_HEIGHT.
func _fit() -> void:
	var h: float = _body.get_combined_minimum_size().y
	_scroll.custom_minimum_size = Vector2(_body.get_combined_minimum_size().x, minf(h, BODY_MAX_HEIGHT))


# ============================================================== helpers

func _label(text: String, size: int, color: Color = Style.BONE, bold: bool = false) -> Label:
	var l: Label = Style.label(text, size, color, Style.FONT_BOLD if bold else Style.FONT_TEXT)
	return l


func _note(text: String) -> Label:
	var l: Label = _label(text, 14, Style.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(360, 0)
	return l


func _section(text: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := ColorRect.new()
	bar.color = color
	bar.custom_minimum_size = Vector2(3, 18)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	row.add_child(_label(text, 17, Style.BONE, true))
	return row


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


func _card(sheet: String, card: String, size: Vector2, tip: String = "") -> Control:
	var path: String = _images.get_image_path(sheet, "EN", card, "Name") if _images != null else ""
	var tex: Texture2D = load(path) as Texture2D if not path.is_empty() and ResourceLoader.exists(path) else null
	var c: Control = null
	if tex != null:
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		c = r
	else:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", Style.panel_style(Color(0.08, 0.12, 0.13, 0.95)))
		var l: Label = _label(card, 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p.add_child(l)
		c = p
	c.custom_minimum_size = size
	c.mouse_filter = Control.MOUSE_FILTER_PASS if not tip.is_empty() else Control.MOUSE_FILTER_IGNORE
	c.tooltip_text = tip
	return c


func _button(text: String, reason: String, primary: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not reason.is_empty()
	b.tooltip_text = reason
	b.custom_minimum_size = Vector2(0, 28)
	Style.style_button(b, primary)
	b.add_theme_font_size_override("font_size", 15)
	return b


## A small coloured counter chip: "3" on a tinted pill.
func _chip(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color, 0.22)
	sb.border_color = Color(color, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(_label(text, 13, Style.BONE, true))
	return p


func _hex_name(c: Vector2i) -> String:
	var t: HexTileState = _state.get_hex(c)
	if t == null:
		return "%s" % c
	if t.role == "capital":
		return "The Capital"
	if t.role == "outer":
		return RegionMath.region_at(_state, c)
	if t.explored and not t.hex_card_name.is_empty():
		return t.hex_card_name
	return "an unexplored hex"


# ============================================================== drawers

func _fill_druids() -> void:
	_body.add_child(_note("Each Refresh phase, a Druid whose condition holds gains Aether. Aether pays for rerolls and Godpowers. Aether left in the bag: %d." % _state.aether_pool))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	_body.add_child(grid)
	for d: DruidInstance in _state.druids_in_play:
		var col := _vbox(4)
		grid.add_child(col)
		var info: DruidCard = _druid_card(d.card_name)
		var tip: String = d.card_name
		if info != null:
			tip = "%s\nGains Aether: %s\nGodpower: %s" % [d.card_name, info.refresh_phase, info.archery_and_clash]
		var card: Control = _card("Druids", d.card_name, Vector2(150, 220), tip)
		if d.face_down:
			card.modulate = Color(0.45, 0.45, 0.5)
		col.add_child(card)
		var row := _hbox(6)
		col.add_child(row)
		row.add_child(_label(d.card_name, 15, Style.BONE, true))
		row.add_child(_chip("%d Aether" % d.aether, AETHER))
		if d.face_down:
			row.add_child(_label("face down", 13, Style.MUTED))


func _druid_card(card_name: String) -> DruidCard:
	if _card_db == null:
		return null
	for d: DruidCard in _card_db.druids_all:
		if d.card_name == card_name and d.lang == "EN":
			return d
	return null


func _fill_nemesis() -> void:
	var legions: Array = _state.legions.duplicate()
	legions.sort_custom(func(a: Variant, b: Variant) -> bool: return _initiative(a.card_name) < _initiative(b.card_name))
	var hordes: Array = _state.hordes.duplicate()
	hordes.sort_custom(func(a: Variant, b: Variant) -> bool: return _initiative(a.card_name) < _initiative(b.card_name))
	_body.add_child(_section("The Empire's Legions", Style.EMPIRE))
	if legions.is_empty():
		_body.add_child(_note("No Legions on the map."))
	for l: Variant in legions:
		var target: String = ""
		if (l as LegionInstance).has_target:
			var li: LegionInstance = l
			target = "Target: The Capital" if li.target_faction == "Capital" else "Target: %s Haven on %s" % [li.target_faction, _hex_name(li.target_coord)]
		_body.add_child(_nemesis_row("Legions", l, target))
	_body.add_child(_note("Legion deck: %d card%s%s." % [_state.legion_deck.size(), "" if _state.legion_deck.size() == 1 else "s",
		", %d Activation Token%s waiting" % [_state.legion_deck_tokens, "" if _state.legion_deck_tokens == 1 else "s"] if _state.legion_deck_tokens > 0 else ""]))
	_body.add_child(_section("Chaos' Hordes", Style.CHAOS))
	if hordes.is_empty():
		_body.add_child(_note("No Hordes on the map."))
	for h: Variant in hordes:
		_body.add_child(_nemesis_row("Hordes", h, ""))
	_body.add_child(_note("Horde deck: %d card%s%s." % [_state.horde_deck.size(), "" if _state.horde_deck.size() == 1 else "s",
		", %d Activation Token%s waiting" % [_state.horde_deck_tokens, "" if _state.horde_deck_tokens == 1 else "s"] if _state.horde_deck_tokens > 0 else ""]))
	_body.add_child(_section("Graveyards", Style.MUTED))
	_body.add_child(_note("The Empire's: %s\nChaos': %s\nEmptied at Scoring, %s" % [_yard_text(_state.imperial_graveyard), _yard_text(_state.chaos_graveyard),
		"1 VP per Unit in it (2 on Nightmare and Apocalypse)." if _state.solo else "2 VP for every faction in it."]))


func _nemesis_row(sheet: String, n: Variant, target: String) -> Control:
	var row := _hbox(10)
	row.add_child(_card(sheet, str(n.card_name), Vector2(64, 106), str(n.card_name)))
	var col := _vbox(2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	col.add_child(_label(str(n.card_name), 16, Style.BONE, true))
	var chips := _hbox(6)
	col.add_child(chips)
	chips.add_child(_chip("Threat %d" % int(n.threat), Style.CRIMSON.lightened(0.3)))
	chips.add_child(_chip("%d Activation" % int(n.activation_tokens), Style.TEAL.lightened(0.3)))
	chips.add_child(_chip("Initiative %d" % _initiative(str(n.card_name)), Style.MUTED))
	col.add_child(_label("On %s" % _hex_name(n.coord), 13, Style.MUTED))
	if not target.is_empty():
		col.add_child(_label(target, 13, Style.MUTED))
	return row


func _initiative(card_name: String) -> int:
	var card: LegionHordeCombatTable.CombatCard = LegionHordeCombatTable.get_card(card_name)
	return card.initiative if card != null else 99


func _yard_text(yard: Dictionary) -> String:
	var bits: Array[String] = []
	for f: Variant in yard.keys():
		if int(yard[f]) > 0:
			bits.append("%s %d" % [str(f), int(yard[f])])
	return ", ".join(bits) if not bits.is_empty() else "empty"


func _fill_market() -> void:
	_body.add_child(_note("1 AP plus the Item's Salt. Your Hero must be able to use it. The Market refills at once."))
	var gate: String = Rules.main_reason(_state, _card_db, _me, "market", _selected, _has_selected, _ally_acting)
	if gate == "You can't afford or use any Item.":
		gate = ""
	var row := _hbox(12)
	_body.add_child(row)
	for item: String in _state.item_market:
		var col := _vbox(6)
		row.add_child(col)
		col.add_child(_card("Items", item, Vector2(118, 174), item))
		var price := _hbox(6)
		col.add_child(price)
		var cost: int = Rules.market_cost(_state, _card_db, _me, item) if _me != null else GameActions.item_cost(_card_db, item)
		price.add_child(Style.cost_row([["salt", str(cost)]], 16))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		price.add_child(spacer)
		var reason: String = gate
		if reason.is_empty() and _me != null:
			if _ally_acting and _me.has_ally():
				_me.swap_heroes()
				reason = Rules.market_reason(_state, _card_db, _me, item)
				_me.swap_heroes()
			else:
				reason = Rules.market_reason(_state, _card_db, _me, item)
		var buy: Button = _button("Buy", reason)
		var it: String = item
		buy.pressed.connect(func() -> void:
			close_drawer()
			action_requested.emit({"type": "market", "item": it}))
		price.add_child(buy)
	_body.add_child(_note("Item deck: %d. Discarded: %d." % [_state.item_deck.size(), _state.item_discard.size()]))


func _fill_quests() -> void:
	_body.add_child(_note("1 AP. Roll your Hero Dice: solve the Quest for its reward, or its fail effect strikes."))
	var reason: String = Rules.main_reason(_state, _card_db, _me, "quest", _selected, _has_selected, _ally_acting)
	var row := _hbox(12)
	_body.add_child(row)
	for quest: String in _state.quest_row:
		var col := _vbox(6)
		row.add_child(col)
		col.add_child(_card("Quests", quest, Vector2(118, 194), quest))
		var go: Button = _button("Attempt", reason)
		var q: String = quest
		go.pressed.connect(func() -> void:
			close_drawer()
			action_requested.emit({"type": "quest", "quest": q}))
		col.add_child(go)
	if _state.quest_row.is_empty():
		_body.add_child(_note("No Quests are face up. New ones come in the Refresh phase."))
	_body.add_child(_note("Quest deck: %d." % _state.quest_deck.size()))


func _fill_events() -> void:
	var event_name: String = str(_state.chapter_events.get(_state.chapter, ""))
	var revealed: bool = int(_state.phase) >= int(GameState.Phase.EVENTS)
	if event_name.is_empty():
		_body.add_child(_note("No Event this Chapter."))
	elif revealed:
		_body.add_child(_label("Chapter %d's Event" % _state.chapter, 15, Style.MUTED, true))
		_body.add_child(_card("Events", event_name, Vector2(360, 217), _event_text(event_name)))
		_body.add_child(_label(event_name, 18, Style.BONE, true))
	else:
		_body.add_child(_note("Chapter %d's Event lies face down until the Events phase." % _state.chapter))
		if not _state.latest_event.is_empty():
			_body.add_child(_label("Last Chapter's Event", 15, Style.MUTED, true))
			_body.add_child(_card("Events", _state.latest_event, Vector2(300, 181), _event_text(_state.latest_event)))
	_body.add_child(_note("Every Event raises Legions and Hordes by 2 Threat first, then its card resolves top to bottom, then everyone gets their Activation Tokens."))


func _event_text(event_name: String) -> String:
	if _card_db == null:
		return event_name
	for e: EventCard in _card_db.events_all:
		if e.card_name == event_name and e.lang == "EN":
			return "%s\n%s\n%s" % [event_name, e.effect_1, e.effect_2]
	return event_name


func _fill_score() -> void:
	var rows: Array = []
	for p: PlayerFactionState in _state.players:
		rows.append([p.faction + (" (you)" if p.faction == _my_faction else ""), p.vp, FactionCatalog.accent(p.faction)])
	rows.append(["The Empire", _state.empire_vp, Style.EMPIRE])
	rows.append(["Chaos", _state.chaos_vp, Style.CHAOS])
	for r: Variant in rows:
		var row := _hbox(8)
		_body.add_child(row)
		var bar := ColorRect.new()
		bar.color = (r as Array)[2]
		bar.custom_minimum_size = Vector2(3, 22)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bar)
		var who: Label = _label(str((r as Array)[0]), 17, Style.BONE, true)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(who)
		row.add_child(Style.icon_rect("vp", 16))
		row.add_child(_label(str((r as Array)[1]), 18, Style.BONE, true))
	_body.add_child(_section("This Chapter's Scoring would add", Style.GOLD))
	var garrison_hexes: int = 0
	var curses: int = 0
	for t: HexTileState in _state.hexes.values():
		if t.garrison_level > 0:
			garrison_hexes += 1
		if t.curse:
			curses += 1
	var empire_yard: int = Scoring._graveyard_vp(_state, _state.imperial_graveyard)
	var chaos_yard: int = Scoring._graveyard_vp(_state, _state.chaos_graveyard)
	_body.add_child(_note("The Empire +%d: %d hex%s with Garrisons, %d Legion%s, %d from its Graveyard." % [
		garrison_hexes + _state.legions.size() + empire_yard, garrison_hexes, "" if garrison_hexes == 1 else "es",
		_state.legions.size(), "" if _state.legions.size() == 1 else "s", empire_yard]))
	_body.add_child(_note("Chaos +%d: %d Curse%s, %d Horde%s, %d from its Graveyard." % [
		curses + _state.hordes.size() + chaos_yard, curses, "" if curses == 1 else "s",
		_state.hordes.size(), "" if _state.hordes.size() == 1 else "s", chaos_yard]))
	for p2: PlayerFactionState in _state.players:
		var havens: int = 0
		var bonus: int = 0
		for t2: HexTileState in _state.hexes.values():
			if t2.haven_faction == p2.faction:
				havens += 1
				if Scoring._hex_has_bonus_vp(t2, _card_db):
					bonus += 1
		_body.add_child(_note("%s +%d: %d Haven%s at 2 VP%s." % [p2.faction, 2 * havens + bonus, havens, "" if havens == 1 else "s",
			", %d from hexes with a VP bonus" % bonus if bonus > 0 else ""]))
	_body.add_child(_note("To win, have more VP than The Empire and than Chaos at the end of Chapter %d." % _state.max_chapters))


func _fill_cards() -> void:
	if _me == null:
		_body.add_child(_note("You're watching this game."))
		return
	var limit: int = GameActions.CardAbilities.SOLO_CARD_LIMIT if _me.has_ally() else GameActions.CardAbilities.CARD_LIMIT
	_body.add_child(_note("%d of %d cards. Flipped cards come back in the Refresh phase." % [_me.feats_in_play.size() + _me.items_in_hand.size(), limit]))
	var groups: Array = [[_me.hero_name, false]]
	if _me.has_ally():
		groups.append([_me.ally_hero_name, true])
	for g: Variant in groups:
		var ally: bool = bool((g as Array)[1])
		if _me.has_ally():
			_body.add_child(_label("%s, %s" % [str((g as Array)[0]), "allied Hero" if ally else "main Hero"], 15, Style.MUTED, true))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		flow.custom_minimum_size = Vector2(380, 0)
		flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var count: int = 0
		for f: String in _me.feats_in_play:
			if _me.ally_cards.has(f) == ally:
				flow.add_child(_hand_card("Feats", f, _me.flipped_feats.has(f)))
				count += 1
		for it: String in _me.items_in_hand:
			if _me.ally_cards.has(it) == ally:
				flow.add_child(_hand_card("Items", it, _me.flipped_items.has(it)))
				count += 1
		if count == 0:
			_body.add_child(_note("No cards yet."))
		else:
			_body.add_child(flow)


func _hand_card(sheet: String, card: String, flipped: bool) -> Control:
	var text: String = ""
	if _card_db != null:
		if sheet == "Feats":
			for f: FeatCard in _card_db.feats_all:
				if f.card_name == card and f.lang == "EN":
					text = "%s: %s" % [f.phase, f.text] if not f.phase.is_empty() else f.text
		else:
			for it: ItemCard in _card_db.items_all:
				if it.card_name == card and it.lang == "EN":
					text = "%s: %s" % [it.phases, it.text] if not it.phases.is_empty() else it.text
	var c: Control = _card(sheet, card, Vector2(86, 126), "%s%s\n%s" % [card, " (flipped until the next Refresh)" if flipped else "", text])
	if flipped:
		c.modulate = Color(0.5, 0.5, 0.55)
	return c
