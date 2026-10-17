extends Control

## Faction lobby. Each seat claims one of the four Core peoples - a faction
## can be held by one seat only (NetworkManager.validate_pick, enforced by
## the host) - and picks one of its two Heroes. Selecting a faction shows its
## player board (click to turn it over to the lore side), its Home hex's
## face-down art, both Heroes and the START Feats each begins with.
##
## Networking: Steam (host for friends / join a friend's lobby, App ID 480
## until Uprising has its own - see steam_manager.gd) or LAN by address.
## Factions can be browsed before connecting; claiming needs a lobby.

const HexArt := preload("res://scripts/ui/lobby/hex_art.gd")
const PLAY_SCENE := "res://scenes/PlayBoard.tscn"
const MENU_SCENE := "res://scenes/MainMenu.tscn"

const FACTIONS: Array[String] = ["Druwhn", "Duerkhar", "Krowh", "Mohyar"]
## Accent per faction, taken from the frame of its own player board.
const ACCENT: Dictionary = {
	"Druwhn": Color(0.86, 0.80, 0.55), "Duerkhar": Color(0.27, 0.68, 0.76),
	"Krowh": Color(0.80, 0.24, 0.32), "Mohyar": Color(0.90, 0.63, 0.25),
}
## The face-down hex on each TTS Home hex atlas (hex.obj's top-face UVs).
const HEX_BACK_REGION := Rect2(408, 63, 1032, 893)
const GOLD := Color(0.875, 0.745, 0.424)
const CRIMSON := Color(0.70, 0.15, 0.23)
const TEAL := Color(0.055, 0.592, 0.635)
const BONE := Color(0.949, 0.91, 0.769)
const MIST := Color(0.58, 0.76, 0.78)
const PANEL_BG := Color(0.024, 0.102, 0.114, 0.86)
const MESSAGE_SECONDS := 6.0

@onready var status_label: Label = $Margin/Rows/Header/Status
@onready var invite_button: Button = $Margin/Rows/Header/InviteButton
@onready var leave_button: Button = $Margin/Rows/Header/LeaveButton
@onready var factions_box: VBoxContainer = $Margin/Rows/Body/Factions
@onready var board_frame: Control = $Margin/Rows/Body/Dossier/TopRow/BoardFrame
@onready var board_image: TextureRect = $Margin/Rows/Body/Dossier/TopRow/BoardFrame/BoardImage
@onready var board_hint: Label = $Margin/Rows/Body/Dossier/TopRow/BoardFrame/BoardHint
@onready var faction_name: Label = $Margin/Rows/Body/Dossier/TopRow/Info/FactionName
@onready var faction_facts: Label = $Margin/Rows/Body/Dossier/TopRow/Info/FactionFacts
@onready var holder_label: Label = $Margin/Rows/Body/Dossier/TopRow/Info/Holder
@onready var claim_button: Button = $Margin/Rows/Body/Dossier/TopRow/Info/ClaimButton
@onready var heroes_box: HBoxContainer = $Margin/Rows/Body/Dossier/Heroes
@onready var seats_box: HBoxContainer = $Margin/Rows/Footer/Seats
@onready var ready_button: Button = $Margin/Rows/Footer/ReadyButton
@onready var start_button: Button = $Margin/Rows/Footer/StartButton
@onready var connect_panel: PanelContainer = $ConnectPanel
@onready var host_steam_button: Button = $ConnectPanel/VBox/SteamRow/HostSteamButton
@onready var join_steam_button: Button = $ConnectPanel/VBox/SteamRow/JoinSteamButton
@onready var host_lan_button: Button = $ConnectPanel/VBox/LanRow/HostLanButton
@onready var address_edit: LineEdit = $ConnectPanel/VBox/LanRow/AddressEdit
@onready var join_lan_button: Button = $ConnectPanel/VBox/LanRow/JoinLanButton
@onready var connect_note: Label = $ConnectPanel/VBox/Note
@onready var lobby_list: PanelContainer = $LobbyList
@onready var lobby_rows: VBoxContainer = $LobbyList/VBox/Scroll/Rows
@onready var refresh_button: Button = $LobbyList/VBox/Buttons/RefreshButton
@onready var close_list_button: Button = $LobbyList/VBox/Buttons/CloseButton

var net: Node
var card_db: Node
var images: Node
var _viewing: String = "Druwhn"
var _hero_choice: Dictionary = {}   # faction -> Hero name the player is looking at
var _board_back: bool = false
var _banners: Dictionary = {}       # faction -> {button, hex, name, state}
var _message: String = ""
var _message_time: float = -100.0
var _clock: float = 0.0
var _flipping: bool = false


func _ready() -> void:
	net = get_node("/root/NetworkManager")
	card_db = get_node("/root/CardDatabase")
	images = get_node("/root/ImageManifest")

	invite_button.pressed.connect(func() -> void: net.invite_friends())
	leave_button.pressed.connect(_on_leave_pressed)
	claim_button.pressed.connect(_on_claim_pressed)
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)
	host_steam_button.pressed.connect(func() -> void: net.host_steam(true))
	join_steam_button.pressed.connect(_on_join_steam_pressed)
	host_lan_button.pressed.connect(_on_host_lan_pressed)
	join_lan_button.pressed.connect(_on_join_lan_pressed)
	address_edit.text_submitted.connect(func(_t: String) -> void: _on_join_lan_pressed())
	refresh_button.pressed.connect(func() -> void: net.request_steam_lobbies())
	close_list_button.pressed.connect(func() -> void: lobby_list.visible = false)
	board_frame.gui_input.connect(_on_board_input)

	net.roster_changed.connect(func(_r: Dictionary) -> void: _refresh())
	net.lobby_status.connect(_show_message)
	net.lobby_joined.connect(func() -> void:
		lobby_list.visible = false
		_refresh())
	net.game_starting.connect(_on_game_starting)
	net.steam.lobby_list_received.connect(_on_lobby_list)

	for f: String in FACTIONS:
		var heroes: Array[HeroCard] = _heroes_of(f)
		_hero_choice[f] = heroes[0].card_name if not heroes.is_empty() else ""
	_build_banners()
	var mine: String = _my_pick()
	if not mine.is_empty():
		_viewing = mine
	_refresh()


func _process(delta: float) -> void:
	_clock += delta
	if not _message.is_empty() and _clock - _message_time > MESSAGE_SECONDS:
		_message = ""
		_update_status()


# --- Data helpers ----------------------------------------------------------------

func _heroes_of(faction: String) -> Array[HeroCard]:
	var out: Array[HeroCard] = []
	for h: HeroCard in card_db.heroes:
		if h.faction == faction:
			out.append(h)
	return out


func _hero(name: String) -> HeroCard:
	for h: HeroCard in card_db.heroes:
		if h.card_name == name:
			return h
	return null


func _start_feats(hero_name: String) -> Array[String]:
	var abilities: GDScript = GameActions.CardAbilities
	var out: Array[String] = []
	for f: String in abilities.feat_deck_for(hero_name):
		if abilities.START_FEATS.has(f):
			out.append(f)
	return out


func _feat_card(name: String) -> FeatCard:
	for f: FeatCard in card_db.feats:
		if f.card_name == name:
			return f
	return null


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


func _show_message(text: String) -> void:
	_message = text
	_message_time = _clock
	_update_status()


# --- Faction banners ----------------------------------------------------------------

func _build_banners() -> void:
	for child: Node in factions_box.get_children():
		child.queue_free()
	_banners.clear()
	for f: String in FACTIONS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(240, 126)
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.toggle_mode = false
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(_select_faction.bind(f))
		factions_box.add_child(button)

		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 10
		row.offset_right = -8
		row.add_theme_constant_override("separation", 12)
		button.add_child(row)

		var hex: HexArt = HexArt.new()
		hex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hex.custom_minimum_size = Vector2(118, 104)
		hex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hex.texture = _tex(str(HexTextureLibrary.HOME.get(f, "")))
		hex.region = HEX_BACK_REGION
		row.add_child(hex)

		var text_col := VBoxContainer.new()
		text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_col.alignment = BoxContainer.ALIGNMENT_CENTER
		text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text_col)
		var name_label := Label.new()
		name_label.theme_type_variation = &"HeadingLabel"
		name_label.add_theme_font_size_override("font_size", 26)
		name_label.text = f
		text_col.add_child(name_label)
		var state_label := Label.new()
		state_label.theme_type_variation = &"MutedLabel"
		state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_col.add_child(state_label)

		_banners[f] = {"button": button, "hex": hex, "name": name_label, "state": state_label}


func _banner_style(accent: Color, viewing: bool, bar: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.15, 0.17, 0.92) if viewing else PANEL_BG
	sb.border_width_left = 4
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(accent, 0.85) if viewing else Color(TEAL, 0.28)
	if bar != Color.TRANSPARENT:
		sb.border_color = bar if viewing else Color(bar, 0.75)
	sb.corner_radius_top_left = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_right = 2
	sb.shadow_color = Color(0, 0.02, 0.03, 0.45)
	sb.shadow_size = 8 if viewing else 0
	return sb


func _refresh_banners() -> void:
	var me: int = _my_id()
	for f: String in FACTIONS:
		var b: Dictionary = _banners[f]
		var holder: int = _holder(f)
		var mine: bool = holder != 0 and holder == me and net.in_lobby()
		var taken: bool = holder != 0 and not mine
		var hex: HexArt = b["hex"]
		hex.seal = "gold" if mine else ("crimson" if taken else "")
		hex.dimmed = taken
		hex.border_color = Color(ACCENT[f], 0.9) if f == _viewing else Color(TEAL, 0.55)
		var state: String = "Open"
		if mine:
			state = "Yours, as %s%s" % [str(net.roster[me]["hero"]), " - ready" if bool(net.roster[me]["ready"]) else ""]
		elif taken:
			state = "Led by %s" % str(net.roster[holder]["name"])
		(b["state"] as Label).text = state
		(b["name"] as Label).add_theme_color_override("font_color", BONE.lerp(Color(0.5, 0.55, 0.57), 0.5) if taken else BONE)
		var bar: Color = GOLD if mine else (CRIMSON if taken else Color.TRANSPARENT)
		var button: Button = b["button"]
		var viewing: bool = f == _viewing
		button.add_theme_stylebox_override("normal", _banner_style(ACCENT[f], viewing, bar))
		button.add_theme_stylebox_override("hover", _banner_style(ACCENT[f], true, bar))
		button.add_theme_stylebox_override("pressed", _banner_style(ACCENT[f], true, bar))
		button.add_theme_stylebox_override("focus", _banner_style(ACCENT[f], true, GOLD))


func _select_faction(f: String) -> void:
	if _viewing == f:
		return
	_viewing = f
	_board_back = false
	_refresh()


# --- Dossier ---------------------------------------------------------------------

func _refresh_dossier() -> void:
	var f: String = _viewing
	var side: String = "Back" if _board_back else "Front"
	board_image.texture = _tex(images.get_image_path("Playerboards", "EN", f, side))
	board_hint.text = "Click the board to see its Units" if _board_back else "Click the board to read the %s lore" % f
	faction_name.text = f
	faction_name.add_theme_color_override("font_color", ACCENT[f])

	var board: PlayerboardTable.FactionBoard = PlayerboardTable.get_board(f)
	var home_name: String = str(GameSetup.HOME_HEX_BY_FACTION.get(f, ""))
	var home: HexCard = EffectUtil.hex_card(card_db, home_name)
	var lines: Array[String] = []
	if home != null:
		lines.append("Home hex: %s (%s)" % [home_name, home.terrain])
	if board != null:
		lines.append("A Haven costs %d Plunder" % board.haven_plunder_cost)
		var unit_names: Array[String] = []
		for u: PlayerboardTable.UnitEntry in board.units:
			unit_names.append(u.name)
		lines.append("Units: %s" % ", ".join(unit_names))
	faction_facts.text = "\n".join(lines)

	var holder: int = _holder(f)
	var me: int = _my_id()
	var mine: bool = holder != 0 and holder == me and net.in_lobby()
	var hero_name: String = str(_hero_choice.get(f, ""))
	if mine:
		hero_name = str(net.roster[me]["hero"])
		_hero_choice[f] = hero_name
	if not net.in_lobby():
		holder_label.text = "Host or join a game below to lead a faction."
		claim_button.text = "Lead the %s" % f
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
	for h: HeroCard in _heroes_of(f):
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

	var name_label := Label.new()
	name_label.theme_type_variation = &"HeadingLabel"
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", GOLD if selected else BONE)
	name_label.text = h.card_name
	col.add_child(name_label)
	var role := Label.new()
	role.theme_type_variation = &"MutedLabel"
	role.text = h.flavor.split("\n")[0].strip_edges() if not h.flavor.is_empty() else ""
	col.add_child(role)
	var attrs := Label.new()
	attrs.text = "Might %d, Magic %d, Leadership %d, Guile %d" % [h.might, h.magic, h.lead, h.guile]
	attrs.add_theme_font_size_override("font_size", 16)
	col.add_child(attrs)

	var starts := Label.new()
	starts.theme_type_variation = &"MutedLabel"
	starts.add_theme_font_size_override("font_size", 14)
	starts.text = "Starts with"
	col.add_child(starts)
	var feats_row := HBoxContainer.new()
	feats_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feats_row.add_theme_constant_override("separation", 8)
	col.add_child(feats_row)
	for feat: String in _start_feats(h.card_name):
		var fc := TextureRect.new()
		fc.custom_minimum_size = Vector2(80, 118)
		fc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fc.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fc.texture = _tex(images.get_image_path("Feats", "EN", feat, "Name"))
		var info: FeatCard = _feat_card(feat)
		fc.tooltip_text = "%s (%s)\n%s" % [feat, info.phase, info.text] if info != null else feat
		fc.mouse_filter = Control.MOUSE_FILTER_PASS
		feats_row.add_child(fc)
	if selected and mine:
		var lead := Label.new()
		lead.add_theme_color_override("font_color", GOLD)
		lead.add_theme_font_size_override("font_size", 15)
		lead.text = "Your Hero"
		col.add_child(lead)
	return panel


func _on_hero_input(event: InputEvent, f: String, hero_name: String) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	_hero_choice[f] = hero_name
	if _holder(f) == _my_id() and net.in_lobby():
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
	var ids: Array = net.seats() if net.in_lobby() else []
	for i: int in range(_max_seats()):
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
			var m: Dictionary = net.roster[ids[i]]
			var f: String = str(m["faction"])
			sb.border_color = ACCENT.get(f, Color(TEAL, 0.5)) if not f.is_empty() else Color(TEAL, 0.5)
			var who: String = str(m["name"]) + (" (you)" if int(ids[i]) == _my_id() else "") + (", host" if int(ids[i]) == 1 else "")
			var what: String = "%s, %s" % [f, str(m["hero"])] if not f.is_empty() else "choosing"
			var rdy: String = "" if int(ids[i]) == 1 or f.is_empty() else (", ready" if bool(m["ready"]) else ", not ready")
			label.text = "%s\n%s%s" % [who, what, rdy]
		else:
			sb.border_color = Color(TEAL, 0.18)
			label.theme_type_variation = &"MutedLabel"
			label.text = "Open seat"
		chip.add_theme_stylebox_override("panel", sb)
		chip.add_child(label)
		seats_box.add_child(chip)


func _max_seats() -> int:
	return int(net.MAX_PLAYERS)


func _refresh_buttons() -> void:
	var in_lobby: bool = net.in_lobby()
	var host: bool = in_lobby and net.is_host()
	connect_panel.visible = not in_lobby
	invite_button.visible = in_lobby and net.transport == "steam"
	leave_button.text = "Leave lobby" if in_lobby else "Back to menu"
	var me: int = _my_id()
	ready_button.visible = in_lobby and not host
	if ready_button.visible and net.roster.has(me):
		var has_pick: bool = not str(net.roster[me]["faction"]).is_empty()
		ready_button.disabled = not has_pick
		ready_button.text = "Not ready yet" if bool(net.roster[me]["ready"]) else "I'm ready"
	start_button.visible = host
	if host:
		var blocker: String = net.start_blocker()
		start_button.disabled = not blocker.is_empty()
		start_button.tooltip_text = blocker
	var steam_ok: bool = net.steam_available()
	host_steam_button.disabled = not steam_ok
	join_steam_button.disabled = not steam_ok
	connect_note.text = "Steam: friends see your lobby and can join from their friends list." if steam_ok else "%s You can still play on this network." % str(net.steam.init_message)


func _update_status() -> void:
	if not _message.is_empty():
		status_label.text = _message
		return
	if not net.in_lobby():
		status_label.text = "Not connected yet. Browse the factions, then host or join a game."
		return
	var seats: String = "%d of %d seats taken" % [net.roster.size(), int(net.MAX_PLAYERS)]
	if net.is_host():
		var where: String = "Hosting on Steam" if net.transport == "steam" else "Hosting on this network at %s" % _local_ip()
		var blocker: String = net.start_blocker()
		status_label.text = "%s, %s. %s" % [where, seats, blocker if not blocker.is_empty() else "Everyone is ready."]
	else:
		var host_name: String = str(net.roster[1]["name"]) if net.roster.has(1) else "the host"
		status_label.text = "In %s's game, %s." % [host_name, seats]


func _local_ip() -> String:
	for a: String in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			return a
	return "this computer"


func _refresh() -> void:
	_refresh_banners()
	_refresh_dossier()
	_refresh_seats()
	_refresh_buttons()
	_update_status()


# --- Actions ------------------------------------------------------------------------

func _on_claim_pressed() -> void:
	if not net.in_lobby():
		return
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


func _on_join_steam_pressed() -> void:
	for child: Node in lobby_rows.get_children():
		child.queue_free()
	var waiting := Label.new()
	waiting.theme_type_variation = &"MutedLabel"
	waiting.text = "Looking for open lobbies..."
	lobby_rows.add_child(waiting)
	lobby_list.visible = true
	net.request_steam_lobbies()


func _on_lobby_list(lobbies: Array) -> void:
	for child: Node in lobby_rows.get_children():
		child.queue_free()
	if lobbies.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = &"MutedLabel"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.text = "No open lobbies yet. Ask a friend to host, or host one yourself. A friend's Steam invite also brings you straight in."
		lobby_rows.add_child(empty)
		return
	for l: Variant in lobbies:
		var entry: Dictionary = l
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s's game, %d of %d seats" % [str(entry.get("host", "Someone")), int(entry.get("members", 1)), int(net.MAX_PLAYERS)]
		row.add_child(label)
		var join := Button.new()
		join.text = "Join"
		join.disabled = int(entry.get("members", 1)) >= int(net.MAX_PLAYERS)
		join.pressed.connect(func() -> void: net.join_steam(int(entry["id"])))
		row.add_child(join)
		lobby_rows.add_child(row)


func _on_host_lan_pressed() -> void:
	var err: Error = net.host_lan()
	if err != OK:
		_show_message("Couldn't open a game on port %d (error %d)." % [int(net.LAN_PORT), err])


func _on_join_lan_pressed() -> void:
	var address: String = address_edit.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var err: Error = net.join_lan(address)
	if err != OK:
		_show_message("Couldn't connect to %s (error %d)." % [address, err])


func _on_leave_pressed() -> void:
	if net.in_lobby():
		net.leave_lobby()
		_refresh()
	else:
		get_tree().change_scene_to_file(MENU_SCENE)


func _on_game_starting() -> void:
	LobbyConfig.is_host = net.is_host()
	get_tree().change_scene_to_file(PLAY_SCENE)
