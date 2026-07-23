class_name OpponentBoardView
extends RefCounted

# Builds the "Players" sidebar widget and the full-screen opponent board
# view (sector grid + card detail overlay) from the local _opp_snapshots
# cache main.gd already owns and keeps updated via state-broadcast RPCs.
# Holds no state of its own — operates on the Main node passed in.

const CARD_ASPECT: float = 183.0 / 130.0  # height / width, matches the physical card proportions
const CARD_MAX_W: float = 200.0
const CARD_MIN_W: float = 50.0
# Tucked cards render at their own, smaller cap (40% below the sector/tech
# row's cards) — they're a "what's stashed here" detail, not the headline
# content of the row.
const TUCKED_CARD_MAX_W: float = CARD_MAX_W * 0.6
const TUCKED_CARD_MIN_W: float = CARD_MIN_W * 0.6
const CARD_ROW_SPACING: int = 16
# Rough allowance for ScifiPanel's content margin + the outer list's vertical
# scrollbar — used to estimate how much width a card row actually has to work
# with, so cards can be sized to always fit without ever needing their own
# horizontal scrollbar.
const ROW_MARGIN: float = 60.0

# Shrinks cards to fit `count` of them side by side within the estimated
# available row width, instead of a fixed size that overflows into a
# horizontal scrollbar once enough cards are present.
static func _dynamic_card_size(avail_w: float, count: int, max_w: float = CARD_MAX_W, min_w: float = CARD_MIN_W) -> Vector2:
	var n: int = maxi(count, 1)
	var card_w: float = (avail_w - CARD_ROW_SPACING * float(n - 1)) / float(n)
	card_w = clampf(card_w, min_w, max_w)
	return Vector2(card_w, card_w * CARD_ASPECT)

static func setup_enemy_screen_display(main: Main) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.visible = false
	main.get_node("UILayer").add_child(panel)
	main.es_viewport = panel

static func build_opponent_widget(main: Main) -> void:
	if main.opp_widget:
		main.opp_widget.queue_free()
	main._opp_panels.clear()
	main.es_back_btn = null

	var supply_paths: Array = [
		"res://assets/ui/supply/Dust.png",
		"res://assets/ui/supply/Metals.png",
		"res://assets/ui/supply/Liquids.png",
		"res://assets/ui/supply/Organix.png",
		"res://assets/ui/supply/Electrix.png",
		"res://assets/ui/supply/Thrust.png",
	]

	var widget: ScifiPanel = ScifiPanel.new()
	widget.set_content_margin(14)
	widget.theme = GameTheme.get_theme()
	main.opp_widget = widget
	widget.mouse_filter = Control.MOUSE_FILTER_STOP
	main.es_viewport.add_child(widget)
	widget.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	widget.grow_horizontal = Control.GROW_DIRECTION_BOTH
	widget.grow_vertical = Control.GROW_DIRECTION_BOTH

	var outer_vbox: VBoxContainer = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 6)
	widget.add_child(outer_vbox)

	var title_lbl: Label = Label.new()
	title_lbl.text = "Players"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer_vbox.add_child(title_lbl)

	var title_sep: HSeparator = HSeparator.new()
	title_sep.modulate = Color(0.4, 0.4, 0.5, 0.5)
	outer_vbox.add_child(title_sep)

	for peer_id: int in GameNetwork.player_order:
		if peer_id == main.multiplayer.get_unique_id():
			continue

		if main._market_panel:
			main._market_panel.add_opponent(peer_id, GameNetwork.player_names.get(peer_id, "Player"))

		var entry_sep: HSeparator = HSeparator.new()
		entry_sep.modulate = Color(0.4, 0.4, 0.5, 0.3)
		outer_vbox.add_child(entry_sep)

		var pid: int = peer_id

		var entry: PanelContainer = PanelContainer.new()
		entry.mouse_filter = Control.MOUSE_FILTER_STOP
		var entry_style: StyleBoxFlat = StyleBoxFlat.new()
		entry_style.bg_color = Color(0.05, 0.07, 0.15, 0.80)
		entry_style.border_color = Color(0.22, 0.44, 0.70, 0.38)
		entry_style.set_border_width_all(1)
		entry_style.set_corner_radius_all(4)
		entry_style.content_margin_left = 8.0
		entry_style.content_margin_right = 8.0
		entry_style.content_margin_top = 7.0
		entry_style.content_margin_bottom = 7.0
		entry.add_theme_stylebox_override("panel", entry_style)
		entry.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				show_opponent_board(main, pid)
			entry.accept_event()
		)
		var opp_name: String = GameNetwork.player_names.get(pid, "Player")
		entry.mouse_entered.connect(func() -> void: main._show_tooltip("", "Click to view %s's board." % opp_name))
		entry.mouse_exited.connect(func() -> void: main._hide_tooltip())
		outer_vbox.add_child(entry)

		var entry_vbox: VBoxContainer = VBoxContainer.new()
		entry_vbox.add_theme_constant_override("separation", 4)
		entry_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.add_child(entry_vbox)

		# Row 1: name (expand) + ♠ N + ⭐ N
		var row1: HBoxContainer = HBoxContainer.new()
		row1.add_theme_constant_override("separation", 4)
		row1.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry_vbox.add_child(row1)

		var name_lbl: Label = Label.new()
		name_lbl.text = GameNetwork.player_names.get(peer_id, "Player")
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.clip_text = true
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row1.add_child(name_lbl)

		var hand_lbl: Label = Label.new()
		hand_lbl.text = "♠ 0"
		hand_lbl.add_theme_font_size_override("font_size", 13)
		hand_lbl.add_theme_color_override("font_color", Color(0.70, 0.82, 1.0))
		hand_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row1.add_child(hand_lbl)

		var vp_lbl: Label = Label.new()
		vp_lbl.text = "⭐ 0"
		vp_lbl.add_theme_font_size_override("font_size", 12)
		vp_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
		vp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row1.add_child(vp_lbl)

		# Row 2: 6 supply columns (icon above count)
		var row2: HBoxContainer = HBoxContainer.new()
		row2.add_theme_constant_override("separation", 2)
		row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry_vbox.add_child(row2)

		var supply_lbls: Array = []
		for si: int in 6:
			var col: VBoxContainer = VBoxContainer.new()
			col.add_theme_constant_override("separation", 0)
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row2.add_child(col)

			var icon: TextureRect = TextureRect.new()
			icon.texture = load(supply_paths[si]) as Texture2D
			icon.custom_minimum_size = Vector2(20.0, 20.0)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(icon)

			var s_lbl: Label = Label.new()
			s_lbl.text = "0"
			s_lbl.add_theme_font_size_override("font_size", 11)
			s_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.90))
			s_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			s_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(s_lbl)
			supply_lbls.append(s_lbl)

		# Row 3: status, centered
		var row3: HBoxContainer = HBoxContainer.new()
		row3.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry_vbox.add_child(row3)

		var status_lbl: Label = Label.new()
		status_lbl.add_theme_font_size_override("font_size", 11)
		status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row3.add_child(status_lbl)

		main._opp_panels[peer_id] = {
			"hand_lbl": hand_lbl,
			"supply_lbls": supply_lbls,
			"vp_lbl": vp_lbl,
			"status_lbl": status_lbl,
		}

	var bottom_sep: HSeparator = HSeparator.new()
	bottom_sep.modulate = Color(0.4, 0.4, 0.5, 0.5)
	outer_vbox.add_child(bottom_sep)

	main.es_back_btn = Button.new()
	main.es_back_btn.text = "← Back to my board"
	main.es_back_btn.visible = false
	main.es_back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.es_back_btn.add_theme_font_size_override("font_size", 15)
	GameTheme.apply_to_button(main.es_back_btn)
	main.es_back_btn.pressed.connect(func() -> void: close_opponent_board_view(main))
	outer_vbox.add_child(main.es_back_btn)

static func show_opponent_board(main: Main, peer_id: int) -> void:
	if not main._opp_snapshots.has(peer_id):
		return
	if main.opp_info_panel:
		close_opponent_board_view(main)
	if main._market_panel:
		main._market_panel.visible = false
	build_opp_info_panel(main, peer_id)

static func build_opp_info_panel(main: Main, peer_id: int) -> void:
	if main.opp_info_panel:
		main.opp_info_panel.queue_free()
	var snap: Dictionary = main._opp_snapshots.get(peer_id, {})
	var player_name: String = GameNetwork.player_names.get(peer_id, "Opponent")

	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main._info_viewport.add_child(root)
	main.opp_info_panel = root

	var scifi: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	scifi.set_content_margin(20)
	scifi.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(scifi)

	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	scifi.add_child(outer)

	# ── Header ──────────────────────────────────────────────────────────────────
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	outer.add_child(header)

	var name_lbl: Label = Label.new()
	name_lbl.text = player_name
	name_lbl.add_theme_font_size_override("font_size", 30)
	name_lbl.add_theme_color_override("font_color", Color(0.80, 0.90, 1.0))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(name_lbl)

	var return_btn: Button = Button.new()
	return_btn.text = "← Return"
	return_btn.add_theme_font_size_override("font_size", 20)
	return_btn.custom_minimum_size = Vector2(160, 48)
	return_btn.pressed.connect(func() -> void: close_opponent_board_view(main))
	header.add_child(return_btn)

	# The in-world screen's bezel crops a bit more than ScifiPanel's own
	# content margin accounts for, so the return button was sitting almost
	# off the visible edge — pull it in with a fixed spacer.
	var header_right_pad: Control = Control.new()
	header_right_pad.custom_minimum_size = Vector2(40, 0)
	header.add_child(header_right_pad)

	# Opponent-switch tabs — lets you hop directly to another opponent's
	# board without backing out to the market panel and clicking again.
	var opponent_ids: Array = []
	for pid: int in GameNetwork.player_order:
		if pid != main.multiplayer.get_unique_id():
			opponent_ids.append(pid)
	if opponent_ids.size() > 1:
		var tabs_row: HBoxContainer = HBoxContainer.new()
		tabs_row.add_theme_constant_override("separation", 8)
		outer.add_child(tabs_row)
		for opid_v: Variant in opponent_ids:
			var opid: int = opid_v
			var tab_btn: Button = Button.new()
			tab_btn.text = GameNetwork.player_names.get(opid, "Player")
			tab_btn.custom_minimum_size = Vector2(0, 36)
			tab_btn.add_theme_font_size_override("font_size", 15)
			tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if opid == peer_id:
				tab_btn.disabled = true
				tab_btn.add_theme_color_override("font_disabled_color", Color(1.0, 0.88, 0.35))
			else:
				tab_btn.pressed.connect(func() -> void: build_opp_info_panel(main, opid))
			tabs_row.add_child(tab_btn)

	var hsep: HSeparator = HSeparator.new()
	hsep.modulate = Color(0.4, 0.4, 0.5, 0.5)
	outer.add_child(hsep)

	# ── Stats bar ───────────────────────────────────────────────────────────────
	var stats_bar: HBoxContainer = HBoxContainer.new()
	stats_bar.add_theme_constant_override("separation", 16)
	outer.add_child(stats_bar)

	var supply_dict: Dictionary = snap.get("supply", {})
	var supply_paths: Array[String] = [
		"res://assets/ui/supply/Dust.png",
		"res://assets/ui/supply/Metals.png",
		"res://assets/ui/supply/Liquids.png",
		"res://assets/ui/supply/Organix.png",
		"res://assets/ui/supply/Electrix.png",
		"res://assets/ui/supply/Thrust.png",
	]
	for si: int in 6:
		var cell: HBoxContainer = HBoxContainer.new()
		cell.add_theme_constant_override("separation", 5)
		stats_bar.add_child(cell)
		var icon: TextureRect = TextureRect.new()
		icon.texture = load(supply_paths[si]) as Texture2D
		icon.custom_minimum_size = Vector2(22, 22)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(icon)
		var amt_lbl: Label = Label.new()
		amt_lbl.text = str(supply_dict.get(si, 0))
		amt_lbl.add_theme_font_size_override("font_size", 18)
		amt_lbl.add_theme_color_override("font_color", Color(0.75, 0.82, 1.0))
		amt_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(amt_lbl)

	var sv1: VSeparator = VSeparator.new()
	sv1.modulate = Color(0.4, 0.4, 0.5, 0.5)
	stats_bar.add_child(sv1)

	var hand_lbl: Label = Label.new()
	hand_lbl.text = "♠  %d cards" % snap.get("hand_size", 0)
	hand_lbl.add_theme_font_size_override("font_size", 18)
	hand_lbl.add_theme_color_override("font_color", Color(0.70, 0.82, 1.0))
	hand_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stats_bar.add_child(hand_lbl)

	var sv2: VSeparator = VSeparator.new()
	sv2.modulate = Color(0.4, 0.4, 0.5, 0.5)
	stats_bar.add_child(sv2)

	var vp_lbl: Label = Label.new()
	vp_lbl.text = "⭐  VP: %d" % snap.get("vp", 0)
	vp_lbl.add_theme_font_size_override("font_size", 20)
	vp_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	vp_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stats_bar.add_child(vp_lbl)

	var hsep2: HSeparator = HSeparator.new()
	hsep2.modulate = Color(0.4, 0.4, 0.5, 0.5)
	outer.add_child(hsep2)

	# ── Sectors ─────────────────────────────────────────────────────────────────
	# One continuous scrollable list instead of a 6-slot grid you had to click
	# into one sector at a time — that modal's tech-card row also had no
	# scrollbar and silently clipped past 3 cards. Everything (sector art,
	# attached techs, stored supply, tucked cards) is visible at a glance now;
	# you just scroll down through the board instead of clicking in and out.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	var sectors_list: VBoxContainer = VBoxContainer.new()
	sectors_list.add_theme_constant_override("separation", 16)
	sectors_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(sectors_list)

	var slots: Array = snap.get("slots", []) as Array
	var occupied_slots: Array = []
	for sv: Variant in slots:
		if bool((sv as Dictionary).get("occupied", false)):
			occupied_slots.append(sv as Dictionary)

	if occupied_slots.is_empty():
		var empty_lbl: Label = Label.new()
		empty_lbl.text = main.tr("No sectors placed yet")
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 18)
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
		sectors_list.add_child(empty_lbl)
	else:
		for i: int in occupied_slots.size():
			sectors_list.add_child(build_opp_sector_block(main, occupied_slots[i] as Dictionary))
			if i < occupied_slots.size() - 1:
				var sep: HSeparator = HSeparator.new()
				sep.modulate = Color(0.4, 0.4, 0.5, 0.4)
				sectors_list.add_child(sep)

static func build_opp_sector_block(main: Main, slot: Dictionary) -> Control:
	var sector_name: String = str(slot.get("sector_name", ""))
	var is_adv: bool = bool(slot.get("sector_advanced", false))
	var tech_names: Array = slot.get("tech_names", []) as Array
	var sector_cd: CardData = CardDatabase.find_sector_by_name(sector_name, is_adv)
	var avail_w: float = main.opp_info_panel.get_viewport_rect().size.x - ROW_MARGIN

	var block: VBoxContainer = VBoxContainer.new()
	block.add_theme_constant_override("separation", 10)

	var hdr: Label = Label.new()
	hdr.text = ("▲ " if is_adv else "") + sector_name
	hdr.add_theme_font_size_override("font_size", 20)
	hdr.add_theme_color_override("font_color",
		Color(1.0, 0.90, 0.50) if is_adv else Color(0.80, 0.90, 1.0))
	block.add_child(hdr)

	var cards_row: HBoxContainer = HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", CARD_ROW_SPACING)
	block.add_child(cards_row)

	var card_size: Vector2 = _dynamic_card_size(avail_w, 1 + tech_names.size())
	cards_row.add_child(build_detail_card(sector_cd, is_adv, sector_name, card_size))

	if not tech_names.is_empty():
		var vsep: VSeparator = VSeparator.new()
		vsep.modulate = Color(0.4, 0.4, 0.5, 0.4)
		cards_row.add_child(vsep)
		for t: Variant in tech_names:
			var t_name: String = str(t)
			var tech_cd: CardData = CardDatabase.find_tech_by_name(t_name)
			cards_row.add_child(build_detail_card(tech_cd, false, t_name, card_size))

	var stored_supply: Dictionary = slot.get("stored_supply", {}) as Dictionary
	var tucked_resolved: Array = []
	for tuck_v: Variant in (slot.get("tucked_cards", []) as Array):
		var tuck: Dictionary = tuck_v as Dictionary
		var face_up: bool = bool(tuck.get("face_up", false))
		var tuck_name: String = str(tuck.get("name", ""))
		var resolved_cd: CardData = CardDatabase.find_any_by_name(tuck_name) if face_up else null
		tucked_resolved.append({"data": resolved_cd, "face_up": face_up, "name": tuck_name})

	if SectorInfoPopup.has_stored_supply(stored_supply):
		block.add_child(SectorInfoPopup.make_section_label(main.tr("Stored Supplies")))
		block.add_child(SectorInfoPopup.make_supply_row(stored_supply))

	var faceup: Array = tucked_resolved.filter(func(t: Dictionary) -> bool: return t.get("face_up", false))
	if not faceup.is_empty():
		block.add_child(SectorInfoPopup.make_section_label(main.tr("Faceup Tucked")))
		block.add_child(build_tucked_row(faceup, true, avail_w))

	var facedown: Array = tucked_resolved.filter(func(t: Dictionary) -> bool: return not t.get("face_up", false))
	if not facedown.is_empty():
		block.add_child(SectorInfoPopup.make_section_label(main.tr("Facedown Tucked")))
		block.add_child(build_tucked_row(facedown, false, avail_w))

	return block

# Tucked cards get their own dynamically-sized row (sized independently from
# the sector/tech row above, since it usually holds a different card count) —
# NOT SectorInfoPopup.make_card_row, which sizes a single card to fill nearly
# the whole popup width; that's correct for that popup's one-section-at-a-time
# use case but wildly oversized dropped into this denser, multi-row layout.
static func build_tucked_row(cards: Array, face_up: bool, avail_w: float) -> Control:
	var card_size: Vector2 = _dynamic_card_size(avail_w, cards.size(), TUCKED_CARD_MAX_W, TUCKED_CARD_MIN_W)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", CARD_ROW_SPACING)
	for tuck_v: Variant in cards:
		var tuck: Dictionary = tuck_v as Dictionary
		if face_up:
			var cd: CardData = tuck.get("data") as CardData
			row.add_child(build_detail_card(cd, false, str(tuck.get("name", "")), card_size))
		else:
			row.add_child(build_facedown_card(card_size))
	return row

static func build_facedown_card(card_size: Vector2) -> Control:
	var outer: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.16)
	style.border_color = Color(0.35, 0.38, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	outer.add_theme_stylebox_override("panel", style)

	var art: TextureRect = TextureRect.new()
	art.texture = ImageCache.get_texture(SectorInfoPopup.TECH_BACK_PATH)
	art.custom_minimum_size = card_size
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	outer.add_child(art)
	return outer

static func build_detail_card(cd: CardData, is_adv: bool, fallback_name: String, card_size: Vector2) -> Control:
	var supply_color: CardData.SupplyColor = CardData.SupplyColor.DUST
	if cd:
		supply_color = cd.adv_color if is_adv else cd.color
	var border_col: Color = CardData.color_tint(supply_color)
	var scale: float = card_size.x / CARD_MAX_W

	var outer: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.16)
	style.border_color = border_col
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	outer.add_theme_stylebox_override("panel", style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	outer.add_child(vbox)

	var img_url: String = ""
	if cd:
		img_url = cd.adv_image_url if is_adv else cd.image_url
	var tex: Texture2D = ImageCache.get_texture(img_url) if not img_url.is_empty() else null

	if tex:
		var art: TextureRect = TextureRect.new()
		art.texture = tex
		art.custom_minimum_size = card_size
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vbox.add_child(art)
	else:
		var placeholder: ColorRect = ColorRect.new()
		placeholder.color = border_col.darkened(0.55)
		placeholder.custom_minimum_size = card_size
		vbox.add_child(placeholder)

	var card_name: String = ((cd.adv_name if is_adv else cd.card_name) if cd else fallback_name)
	if not card_name.is_empty():
		var name_lbl: Label = Label.new()
		name_lbl.text = card_name
		name_lbl.add_theme_font_size_override("font_size", clampi(roundi(14.0 * scale), 9, 14))
		name_lbl.add_theme_color_override("font_color",
			Color(1.0, 0.90, 0.50) if is_adv else Color(0.85, 0.92, 1.0))
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.custom_minimum_size = Vector2(card_size.x, 0)
		vbox.add_child(name_lbl)

	if cd and cd.stars > 0:
		var stars_lbl: Label = Label.new()
		stars_lbl.text = "⭐".repeat(cd.stars)
		stars_lbl.add_theme_font_size_override("font_size", clampi(roundi(13.0 * scale), 8, 13))
		stars_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(stars_lbl)

	return outer


static func close_opponent_board_view(main: Main) -> void:
	if main.opp_info_panel:
		main.opp_info_panel.queue_free()
		main.opp_info_panel = null
	if main._market_panel:
		main._market_panel.visible = true
