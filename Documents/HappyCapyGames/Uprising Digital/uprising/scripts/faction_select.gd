extends Control

## Faction screen. Everyone at the table comes here together once the host
## closes the table (NetworkManager.lobby_phase "factions") and goes back to
## the table screen if the host reopens it or the table breaks up.
##
## All ten peoples are shown as a cluster of their Home hexes' face-down art:
## the Core box down the middle, the Arch-Nemesis and Titans factions either
## side. Only FactionCatalog.PLAYABLE factions can be claimed - the others
## can be browsed until their rules exist. A faction can be held by one seat
## only (NetworkManager.validate_pick, enforced by the host). Selecting a
## faction shows its player board (click to turn it over), its Home hex,
## both Heroes and the cards each starts with.

const FactionCatalog := preload("res://scripts/data/tables/faction_catalog.gd")
const HexArt := preload("res://scripts/ui/lobby/hex_art.gd")
const PLAY_SCENE := "res://scenes/PlayBoard.tscn"
const TABLE_SCENE := "res://scenes/Lobby.tscn"

## Cell of each faction in the cluster: Vector2i(column, row). The middle
## column holds four hexes, the outer two hold three, set half a hex lower.
const CLUSTER: Dictionary = {
	"Ytuma": Vector2i(0, 0), "Renegade": Vector2i(0, 1), "Tua Than": Vector2i(0, 2),
	"Druwhn": Vector2i(1, 0), "Duerkhar": Vector2i(1, 1), "Krowh": Vector2i(1, 2), "Mohyar": Vector2i(1, 3),
	"Hokqan": Vector2i(2, 0), "Pirates": Vector2i(2, 1), "Titans": Vector2i(2, 2),
}
const GOLD := Color(0.875, 0.745, 0.424)
const TEAL := Color(0.055, 0.592, 0.635)
const BONE := Color(0.949, 0.91, 0.769)
const PANEL_BG := Color(0.024, 0.102, 0.114, 0.86)
const MESSAGE_SECONDS := 6.0

@onready var status_label: Label = $Margin/Rows/Header/Status
@onready var back_button: Button = $Margin/Rows/Header/BackButton
@onready var cluster: Control = $Margin/Rows/Body/Picker/Cluster
@onready var legend: VBoxContainer = $Margin/Rows/Body/Picker/Legend
@onready var board_frame: Control = $Margin/Rows/Body/Dossier/TopRow/BoardFrame
@onready var board_image: TextureRect = $Margin/Rows/Body/Dossier/TopRow/BoardFrame/BoardImage
@onready var board_hint: Label = $Margin/Rows/Body/Dossier/TopRow/BoardFrame/BoardHint
@onready var faction_name: Label = $Margin/Rows/Body/Dossier/TopRow/Info/FactionName
@onready var origin_label: Label = $Margin/Rows/Body/Dossier/TopRow/Info/Origin
@onready var faction_facts: Label = $Margin/Rows/Body/Dossier/TopRow/Info/FactionFacts
@onready var holder_label: Label = $Margin/Rows/Body/Dossier/TopRow/Info/Holder
@onready var claim_button: Button = $Margin/Rows/Body/Dossier/TopRow/Info/ClaimButton
@onready var heroes_box: HBoxContainer = $Margin/Rows/Body/Dossier/Heroes
@onready var seats_box: HBoxContainer = $Margin/Rows/Footer/Seats
@onready var ready_button: Button = $Margin/Rows/Footer/ReadyButton
@onready var start_button: Button = $Margin/Rows/Footer/StartButton

var net: Node
var card_db: Node
var images: Node
var _viewing: String = "Druwhn"
var _hero_choice: Dictionary = {}   # faction -> Hero name the player is looking at
var _board_back: bool = false
var _tokens: Dictionary = {}        # faction -> HexArt
var _message: String = ""
var _message_time: float = -100.0
var _clock: float = 0.0
var _flipping: bool = false
var _leaving: bool = false


func _ready() -> void:
	net = get_node("/root/NetworkManager")
	card_db = get_node("/root/CardDatabase")
	images = get_node("/root/ImageManifest")
	if not net.in_lobby() or net.lobby_phase != "factions":
		_go_to_table.call_deferred()
		return

	back_button.pressed.connect(_on_back_pressed)
	claim_button.pressed.connect(_on_claim_pressed)
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)
	board_frame.gui_input.connect(_on_board_input)
	cluster.resized.connect(_layout_cluster)

	net.roster_changed.connect(_on_roster_changed)
	net.lobby_phase_changed.connect(_on_phase_changed)
	net.lobby_status.connect(_show_message)
	net.game_starting.connect(_on_game_starting)

	for f: String in FactionCatalog.FACTIONS:
		var heroes: Array[HeroCard] = FactionCatalog.heroes_of(card_db, f)
		_hero_choice[f] = heroes[0].card_name if not heroes.is_empty() else ""
	_build_cluster()
	_build_legend()
	var mine: String = _my_pick()
	_viewing = mine if not mine.is_empty() else _first_open_faction()
	var carried: String = net.recent_status()
	if not carried.is_empty():
		_show_message(carried)
	_refresh()


func _process(delta: float) -> void:
	_clock += delta
	if not _message.is_empty() and _clock - _message_time > MESSAGE_SECONDS:
		_message = ""
		_update_status()


# --- Data helpers ----------------------------------------------------------------

func _tex(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _my_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1


func _my_pick() -> String:
	var me: int = _my_id()
	return str(net.roster[me]["faction"]) if net.roster.has(me) else ""


## Roster id holding `faction`, or 0.
func _holder(faction: String) -> int:
	for id: Variant in net.roster.keys():
		if str(net.roster[id]["faction"]) == faction:
			return int(id)
	return 0


func _first_open_faction() -> String:
	for f: String in FactionCatalog.PLAYABLE:
		if _holder(f) == 0:
			return f
	return FactionCatalog.PLAYABLE[0]


func _host_name() -> String:
	return str(net.roster[1]["name"]) if net.roster.has(1) else "The host"


func _show_message(text: String) -> void:
	_message = text
	_message_time = _clock
	_update_status()


# --- Faction cluster ---------------------------------------------------------------

func _build_cluster() -> void:
	for child: Node in cluster.get_children():
		child.queue_free()
	_tokens.clear()
	for f: String in FactionCatalog.FACTIONS:
		var token: HexArt = HexArt.new()
		token.texture = _tex(str(FactionCatalog.HOME_ATLAS.get(f, "")))
		token.region = FactionCatalog.home_region(f)
		token.label = f
		token.accent = FactionCatalog.accent(f)
		token.locked = not FactionCatalog.is_playable(f)
		token.inset = 1.5
		token.focus_mode = Control.FOCUS_ALL
		token.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		token.pressed.connect(_select_faction.bind(f))
		cluster.add_child(token)
		_tokens[f] = token
	_layout_cluster()


## Fits the 3-4-3 cluster (2.5 hexes wide, 4 tall) into the Cluster control.
func _layout_cluster() -> void:
	var avail: Vector2 = cluster.size
	if avail.x <= 0.0 or avail.y <= 0.0 or _tokens.is_empty():
		return
	var hex_ratio: float = sqrt(3.0) * 0.5
	var w: float = minf(avail.x / 2.5, avail.y / (4.0 * hex_ratio))
	var h: float = w * hex_ratio
	var origin: Vector2 = (avail - Vector2(w * 2.5, h * 4.0)) * 0.5
	for f: String in _tokens.keys():
		var cell: Vector2i = CLUSTER[f]
		var token: HexArt = _tokens[f]
		var drop: float = 0.0 if cell.x == 1 else h * 0.5
		token.position = origin + Vector2(float(cell.x) * w * 0.75, float(cell.y) * h + drop)
		token.size = Vector2(w, h)


func _build_legend() -> void:
	for child: Node in legend.get_children():
		child.queue_free()
	var entries: Array = [["gold", false, "Your faction"], ["crimson", false, "Led by another player"], ["", true, "Not playable yet"]]
	for e: Variant in entries:
		var entry: Array = e
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var glyph: HexArt = HexArt.new()
		glyph.custom_minimum_size = Vector2(26, 22)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.seal = str(entry[0])
		glyph.locked = bool(entry[1])
		glyph.border_color = Color(TEAL, 0.4)
		glyph.border_width = 1.0
		row.add_child(glyph)
		var text := Label.new()
		text.theme_type_variation = &"MutedLabel"
		text.add_theme_font_size_override("font_size", 14)
		text.text = str(entry[2])
		row.add_child(text)
		legend.add_child(row)


func _refresh_tokens() -> void:
	var me: int = _my_id()
	for f: String in FactionCatalog.FACTIONS:
		var token: HexArt = _tokens[f]
		var holder: int = _holder(f)
		var mine: bool = holder != 0 and holder == me
		var taken: bool = holder != 0 and not mine
		token.selected = f == _viewing
		token.seal = "gold" if mine else ("crimson" if taken else "")
		token.dimmed = taken
		var state: String = "Open"
		if not FactionCatalog.is_playable(f):
			state = "%s, not playable yet" % FactionCatalog.box_title(f)
		elif mine:
			state = "Yours, as %s" % str(net.roster[me]["hero"])
		elif taken:
			state = "Led by %s" % str(net.roster[holder]["name"])
		token.tooltip_text = "%s\n%s" % [f, state]
	# The selected token draws its glow over its neighbours.
	if _tokens.has(_viewing):
		cluster.move_child(_tokens[_viewing], -1)


func _select_faction(f: String) -> void:
	if _viewing == f:
		return
	_viewing = f
	_board_back = false
	_refresh()


# --- Dossier ---------------------------------------------------------------------

func _refresh_dossier() -> void:
	var f: String = _viewing
	var playable: bool = FactionCatalog.is_playable(f)
	var side: String = "Back" if _board_back else "Front"
	board_image.texture = _tex(images.get_image_path("Playerboards", "EN", FactionCatalog.board_key(f), side))
	board_hint.text = "Click the board to see its Units" if _board_back else "Click the board to read the %s lore" % f
	faction_name.text = f
	faction_name.add_theme_color_override("font_color", FactionCatalog.accent(f))
	var origin: String = FactionCatalog.box_title(f)
	if FactionCatalog.FULL_NAME.has(f):
		origin = "%s, %s" % [str(FactionCatalog.FULL_NAME[f]), origin]
	origin_label.text = origin

	var lines: Array[String] = []
	lines.append("Home hex: %s (%s)" % [str(FactionCatalog.HOME_HEX.get(f, "")), str(FactionCatalog.HOME_TERRAIN.get(f, ""))])
	if playable:
		var board: PlayerboardTable.FactionBoard = PlayerboardTable.get_board(f)
		if board != null:
			lines.append("A Haven costs %d Plunder" % board.haven_plunder_cost)
			var unit_names: Array[String] = []
			for u: PlayerboardTable.UnitEntry in board.units:
				unit_names.append(u.name)
			lines.append("Units: %s" % ", ".join(unit_names))
	faction_facts.text = "\n".join(lines)

	var holder: int = _holder(f)
	var me: int = _my_id()
	var mine: bool = holder != 0 and holder == me
	var hero_name: String = str(_hero_choice.get(f, ""))
	if mine:
		hero_name = str(net.roster[me]["hero"])
		_hero_choice[f] = hero_name
	if not playable:
		holder_label.text = "Their rules aren't in the game yet. Browse their board and Heroes for now."
		claim_button.text = "Not playable yet"
		claim_button.disabled = true
	elif mine:
		holder_label.text = "You lead the %s as %s." % [f, hero_name]
		claim_button.text = "Give up the %s" % f
		claim_button.disabled = false
	elif holder != 0:
		holder_label.text = "%s leads the %s." % [str(net.roster[holder]["name"]), f]
		claim_button.text = "Led by %s" % str(net.roster[holder]["name"])
		claim_button.disabled = true
	else:
		holder_label.text = "No one leads the %s yet." % f
		claim_button.text = "Lead the %s as %s" % [f, hero_name]
		claim_button.disabled = false
	_build_hero_panels(f, hero_name, mine)


func _build_hero_panels(f: String, chosen: String, mine: bool) -> void:
	for child: Node in heroes_box.get_children():
		child.queue_free()
	for h: HeroCard in FactionCatalog.heroes_of(card_db, f):
		heroes_box.add_child(_hero_panel(f, h, h.card_name == chosen, mine))


func _hero_panel(f: String, h: HeroCard, selected: bool, mine: bool) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.tooltip_text = "%s leads the %s" % [h.card_name, f] if selected else "Choose %s" % h.card_name
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.15, 0.17, 0.92) if selected else PANEL_BG
	sb.set_border_width_all(2 if selected else 1)
	sb.border_color = GOLD if selected else Color(TEAL, 0.3)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	panel.gui_input.connect(_on_hero_input.bind(f, h.card_name))

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	var card := TextureRect.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size = Vector2(128, 212)
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.texture = _tex(images.get_image_path("Heros", "EN", h.card_name, "Name"))
	row.add_child(card)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)

	var me: Dictionary = net.roster.get(_my_id(), {})
	var solo: bool = net.is_solo()
	var is_ally: bool = solo and str(me.get("ally", "")) == h.card_name
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	col.add_child(name_row)
	var name_label := Label.new()
	name_label.theme_type_variation = &"HeadingLabel"
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", GOLD if selected or is_ally else BONE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text = h.card_name
	name_row.add_child(name_label)
	if selected and mine:
		name_row.add_child(_badge("Your Hero", GOLD))
	elif is_ally:
		name_row.add_child(_badge("Allied Hero", GOLD))
	elif solo and FactionCatalog.is_playable(f) and h.card_name != str(me.get("hero", "")):
		# True Solo: any Hero of any faction (even your own) can be the ally.
		var ally_button := Button.new()
		ally_button.text = "Make ally"
		ally_button.add_theme_font_size_override("font_size", 15)
		ally_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var ally_starts: Array[String] = FactionCatalog.ally_start_cards(f, h.card_name)
		ally_button.tooltip_text = "As your allied Hero, %s starts with %s." % [h.card_name, " and ".join(ally_starts)] if not ally_starts.is_empty() else "Take %s as your allied Hero." % h.card_name
		ally_button.pressed.connect(func() -> void: net.request_ally(h.card_name))
		name_row.add_child(ally_button)
	# The first flavor line is the Hero's role ("Krowh Necromancer"); the
	# Titans' rows hold a rules sentence there instead, which is skipped.
	var role_text: String = h.flavor.split("\n")[0].strip_edges() if not h.flavor.is_empty() else ""
	if not role_text.is_empty() and role_text.length() <= 32:
		var role := Label.new()
		role.theme_type_variation = &"MutedLabel"
		role.text = role_text
		col.add_child(role)
	var attrs := Label.new()
	attrs.text = "Might %d, Magic %d, Leadership %d, Guile %d" % [h.might, h.magic, h.lead, h.guile]
	attrs.add_theme_font_size_override("font_size", 16)
	attrs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(attrs)

	var starts := Label.new()
	starts.theme_type_variation = &"MutedLabel"
	starts.add_theme_font_size_override("font_size", 14)
	starts.text = "Starts with, as your allied Hero" if is_ally else "Starts with"
	col.add_child(starts)
	var cards_row := HBoxContainer.new()
	cards_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cards_row.add_theme_constant_override("separation", 8)
	col.add_child(cards_row)
	var start_list: Array[String] = FactionCatalog.ally_start_cards(f, h.card_name) if is_ally else FactionCatalog.start_cards(f, h.card_name)
	for card_name: String in start_list:
		var fc := TextureRect.new()
		fc.custom_minimum_size = Vector2(76, 112)
		fc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fc.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fc.texture = _tex(images.get_image_path("Feats", "EN", card_name, "Name"))
		var info: FeatCard = FactionCatalog.feat_card(card_db, card_name)
		fc.tooltip_text = "%s (%s)\n%s" % [card_name, info.phase, info.text] if info != null and not info.text.is_empty() else card_name
		fc.mouse_filter = Control.MOUSE_FILTER_PASS
		cards_row.add_child(fc)
	return panel


func _badge(text: String, color: Color) -> Label:
	var badge := Label.new()
	badge.add_theme_color_override("font_color", color)
	badge.add_theme_font_size_override("font_size", 15)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.text = text
	return badge


func _on_hero_input(event: InputEvent, f: String, hero_name: String) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	_hero_choice[f] = hero_name
	if _holder(f) == _my_id():
		net.request_pick(f, hero_name)  # switch Hero, keep the faction
	_refresh()


func _on_board_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _flipping:
		return
	_flipping = true
	board_image.pivot_offset = board_image.size * 0.5
	var tween: Tween = create_tween()
	tween.tween_property(board_image, "scale:x", 0.0, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		_board_back = not _board_back
		_refresh_dossier())
	tween.tween_property(board_image, "scale:x", 1.0, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void: _flipping = false)


# --- Seats, buttons, status -----------------------------------------------------

func _refresh_seats() -> void:
	for child: Node in seats_box.get_children():
		child.queue_free()
	if net.is_solo():
		seats_box.add_child(_solo_summary())
		return
	var ids: Array = net.seats()
	for i: int in range(int(net.MAX_PLAYERS)):
		var chip := PanelContainer.new()
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := StyleBoxFlat.new()
		sb.bg_color = PANEL_BG
		sb.border_width_left = 4
		sb.set_corner_radius_all(2)
		sb.content_margin_left = 10
		sb.content_margin_right = 8
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 15)
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if i < ids.size():
			var id: int = int(ids[i])
			var m: Dictionary = net.roster[ids[i]]
			var f: String = str(m["faction"])
			sb.border_color = FactionCatalog.accent(f) if not f.is_empty() else Color(TEAL, 0.5)
			var who: String = str(m["name"]) + (" (you)" if id == _my_id() else "") + (", host" if id == 1 else "")
			var what: String = "%s, %s" % [f, str(m["hero"])] if not f.is_empty() else "choosing"
			var rdy: String = "" if id == 1 or f.is_empty() else (", ready" if bool(m["ready"]) else ", not ready")
			label.text = "%s\n%s%s" % [who, what, rdy]
		else:
			sb.border_color = Color(TEAL, 0.18)
			label.theme_type_variation = &"MutedLabel"
			label.text = "Empty seat"
		chip.add_theme_stylebox_override("panel", sb)
		chip.add_child(label)
		seats_box.add_child(chip)


## True Solo Mode footer: your party instead of the seats.
func _solo_summary() -> Control:
	var me: Dictionary = net.roster.get(_my_id(), {})
	var f: String = str(me.get("faction", ""))
	var ally: String = str(me.get("ally", ""))
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_width_left = 4
	sb.border_color = FactionCatalog.accent(f) if not f.is_empty() else Color(TEAL, 0.5)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 12
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", sb)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 15)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var lead: String = "%s, led by %s" % [f, str(me.get("hero", ""))] if not f.is_empty() else "No faction yet"
	var with_ally: String = "allied Hero: %s (%s)" % [ally, _faction_of_hero(ally)] if not ally.is_empty() else "no allied Hero yet (Make ally on any Hero)"
	label.text = "True Solo Mode\n%s, %s" % [lead, with_ally]
	chip.add_child(label)
	return chip


func _faction_of_hero(hero_name: String) -> String:
	for f: String in FactionCatalog.FACTIONS:
		for h: HeroCard in FactionCatalog.heroes_of(card_db, f):
			if h.card_name == hero_name:
				return f
	return ""


func _refresh_buttons() -> void:
	var host: bool = net.is_host()
	if net.is_solo():
		back_button.text = "Back"
		back_button.tooltip_text = ""
	else:
		back_button.text = "Back to the table" if host else "Leave the table"
		back_button.tooltip_text = "Wait for more players. Everyone keeps their choice." if host else ""
	var me: int = _my_id()
	ready_button.visible = not host
	if ready_button.visible and net.roster.has(me):
		ready_button.disabled = str(net.roster[me]["faction"]).is_empty()
		ready_button.text = "Not ready yet" if bool(net.roster[me]["ready"]) else "I'm ready"
	start_button.visible = host
	if host:
		var blocker: String = net.start_blocker()
		start_button.disabled = not blocker.is_empty()
		start_button.tooltip_text = blocker


func _update_status() -> void:
	if not _message.is_empty():
		status_label.text = _message
		return
	var me: int = _my_id()
	if net.is_solo():
		var solo_blocker: String = net.start_blocker()
		status_label.text = solo_blocker if not solo_blocker.is_empty() else "Your party is set. Start when you like."
	elif net.is_host():
		var blocker: String = net.start_blocker()
		status_label.text = blocker if not blocker.is_empty() else "Everyone is ready. Start when you like."
	elif not net.roster.has(me) or str(net.roster[me]["faction"]).is_empty():
		status_label.text = "Pick a faction and a Hero."
	elif not bool(net.roster[me]["ready"]):
		status_label.text = "Press I'm ready when you're set."
	else:
		status_label.text = "Waiting for %s to start the game." % _host_name()


func _refresh() -> void:
	_refresh_tokens()
	_refresh_dossier()
	_refresh_seats()
	_refresh_buttons()
	_update_status()


# --- Actions and scene flow --------------------------------------------------------

func _on_claim_pressed() -> void:
	var f: String = _viewing
	if _holder(f) == _my_id():
		net.request_pick("", "")
	else:
		net.request_pick(f, str(_hero_choice.get(f, "")))


func _on_ready_pressed() -> void:
	var me: int = _my_id()
	if net.roster.has(me):
		net.set_ready_state(not bool(net.roster[me]["ready"]))


func _on_start_pressed() -> void:
	if net.start_game() != OK:
		_show_message(net.start_blocker())


func _on_back_pressed() -> void:
	if net.is_host() and not net.is_solo():
		net.reopen_table()  # everyone follows through lobby_phase_changed
	else:
		net.leave_lobby()


func _on_roster_changed(_roster: Dictionary) -> void:
	if _leaving:
		return
	if not net.in_lobby():
		_go_to_table()
		return
	_refresh()


func _on_phase_changed(phase: String) -> void:
	if phase != "factions":
		_go_to_table()


func _go_to_table() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file(TABLE_SCENE)


func _on_game_starting() -> void:
	_leaving = true
	LobbyConfig.is_host = net.is_host()
	get_tree().change_scene_to_file(PLAY_SCENE)
