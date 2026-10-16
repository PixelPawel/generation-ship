extends RefCounted
# Generation Fleet (co-op, solo for now): the Danger flow and the mission.
# Static helpers on Main, like BotTurn / CockpitRig. FleetRules holds the state
# and the rule queries; this does the revealing, resolving, solving and the
# Dangers screen. Player choices use Main's ChoicePopup directly (awaited) with
# Main._fleet_choice_active set, so Main's own popup handlers stay out of it.
const FleetData = preload("res://scripts/game/fleet_data.gd")
const FleetRules = preload("res://scripts/game/fleet_rules.gd")
const TurnBanner = preload("res://scenes/ui/turn_banner.gd")

const DANGER_COLOR: Color = Color(1.0, 0.5, 0.4)
const SOLVED_COLOR: Color = Color(0.5, 1.0, 0.6)
const CARD_SHOW_SEC: float = 1.6
const C := CardData.SupplyColor

# ── Setup ─────────────────────────────────────────────────────────────────────

static func setup(main: Main) -> void:
	if not GameNetwork.fleet_mode:
		FleetRules.current = null
		return
	var rules: RefCounted = FleetRules.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	rules.setup(GameNetwork.fleet_destination, rng)
	FleetRules.current = rules
	main._fleet = rules
	var panel: Control = main._fleet_panel
	panel.danger_solve_pressed.connect(func(no: int) -> void: try_solve(main, no))
	panel.danger_inspect_requested.connect(func(no: int) -> void:
		show_card(main, FleetData.danger_art(no), false, 0.0))
	main._fleet_dest_view.destination_inspect_requested.connect(func() -> void:
		show_card(main, FleetData.destination_art(GameNetwork.fleet_destination), true, 0.0))
	main.get_node("Board").fleet_rule_blocked.connect(func(msg: String) -> void:
		main._log_action(msg, DANGER_COLOR))
	# Solve buttons and mission progress follow the game while the screen shows
	var timer: Timer = Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		if panel.visible or main._fleet_dest_view.visible:
			refresh_panel(main))
	main.add_child(timer)
	refresh_panel(main)

# ── Generation start ──────────────────────────────────────────────────────────

## After the draw: Place Dangers still in play strike again (oldest first),
## then 3 new Dangers are revealed and resolve one at a time.
static func start_generation(main: Main) -> void:
	var rules: RefCounted = main._fleet
	if rules == null:
		return
	main._fleet_busy = true
	main._set_action_buttons_disabled(true)
	for no: int in rules.active_place_dangers():
		main._log_action(main.tr("Danger strikes again: %s") % _name(no), DANGER_COLOR)
		await resolve_place(main, no)
	var revealed: Array[int] = rules.reveal(FleetData.DANGERS_PER_GENERATION)
	if revealed.is_empty():
		main._log_action(main.tr("The Danger deck is empty."), DANGER_COLOR)
	await _resolve_revealed(main, revealed)
	_after_change(main)
	main._set_action_buttons_disabled(false)
	main._fleet_busy = false

static func _resolve_revealed(main: Main, nos: Array[int]) -> void:
	for no: int in nos:
		await _announce(main, no)
		if FleetRules.is_place(no):
			await resolve_place(main, no)
		else:
			main._log_action(main.tr("Danger: %s — in effect until solved.") % _name(no), DANGER_COLOR)
		_after_change(main)

static func _announce(main: Main, no: int) -> void:
	main._log_action(main.tr("Danger revealed: %s") % _name(no), DANGER_COLOR)
	show_card(main, FleetData.danger_art(no), false, CARD_SHOW_SEC)
	var banner: Node = TurnBanner.new()
	main.get_node("UILayer").add_child(banner)
	banner.play(main.tr("DANGER"), DANGER_COLOR, _name(no), 1.2)
	await banner.finished

# ── Place effects ─────────────────────────────────────────────────────────────

static func resolve_place(main: Main, no: int) -> void:
	var eff: Dictionary = FleetRules.PLACE_EFFECTS.get(no, {"kind": "none"})
	main._effect_source_name = _name(no)
	await _apply(main, no, eff)
	_after_change(main)

static func _apply(main: Main, no: int, eff: Dictionary) -> void:
	var board: Node = main.get_node("Board")
	var n: int = int(eff.get("n", 1))
	match str(eff.get("kind", "none")):
		"to_dust":
			for i: int in n:
				var colors: Array[int] = []
				for col: int in [C.METALS, C.LIQUIDS, C.ORGANIX, C.ELECTRIX, C.THRUST]:
					if main._cs_display.get_supply(col) > 0:
						colors.append(col)
				if colors.is_empty():
					break
				var pick: int = 0
				if colors.size() > 1:
					pick = await _pick_color(main, main.tr("%s: turn a supply into Dust (%d of %d)") % [_name(no), i + 1, n], colors)
				main._cs_display.spend_supply(colors[pick], 1)
				main._cs_display.add_supply(C.DUST, 1)
		"destroy":
			await _destroy(main, no, n, str(eff.get("where", "any")), int(eff.get("pref", -1)))
		"choose":
			var options: Array = eff.get("options", [])
			var possible: Array[Dictionary] = []
			for o: Dictionary in options:
				if _option_possible(main, o):
					possible.append(o)
			if possible.is_empty():
				main._log_action(main.tr("%s: nothing you can pay — nothing happens.") % _name(no), DANGER_COLOR)
				return
			var chosen: Dictionary = possible[0]
			if possible.size() > 1:
				var labels: Array = []
				for o: Dictionary in possible:
					labels.append(_option_text(main, o))
				chosen = possible[await _pick_option(main, main.tr("%s — choose one:") % _name(no), labels)]
			await _apply(main, no, chosen)
		"pay":
			var pay: Dictionary = board._compute_payment(int(eff["color"]), n)
			if pay.is_empty():
				main._log_action(main.tr("%s: you can't pay — nothing happens.") % _name(no), DANGER_COLOR)
				return
			for col: int in pay:
				main._cs_display.spend_supply(col, int(pay[col]))
			main._log_action(main.tr("%s: paid %d %s.") % [_name(no), n, CardData.color_name(int(eff["color"]))], DANGER_COLOR)
		"lose_stored":
			await _lose_items(main, no, n, true, false)
		"lose_stored_or_archived":
			await _lose_items(main, no, n, true, true)
		"discard":
			await _discard_from_hand(main, main.tr("%s: discard %d card(s)") % [_name(no), n], _hand_cards(main), n, true)
		"market_adv":
			var market: Node = board.get_market()
			var gone: PackedStringArray = []
			for i: int in 3:
				if gone.size() >= n:
					break
				var top: Node3D = market.get_advanced_top_node(i)
				if top and top.card_data:
					gone.append(top.card_data.adv_name)
					board.remove_market_card(top.card_data)
			main._log_action(main.tr("%s: discarded from the market: %s") % [_name(no), ", ".join(gone) if not gone.is_empty() else "—"], DANGER_COLOR)
		"system_failure":
			var e: Dictionary = main._fleet.entry(no)
			e["electrix"] = int(e.get("electrix", 0)) + 1
			var extra: int = int(e["electrix"])
			main._log_action(main.tr("%s: 1 Electrix stored on it — revealing %d more Danger(s).") % [_name(no), extra], DANGER_COLOR)
			var more: Array[int] = main._fleet.reveal(extra)
			await _resolve_revealed(main, more)
		"shuffle_expeditions":
			var em: Node = board.get_expedition_market()
			var count: int = 0
			for stack: Array in em._stacks:
				while not stack.is_empty():
					var before: int = stack.size()
					em._on_shuffle_card_clicked(stack.back() as Node3D)
					if stack.size() >= before:   # card without its slot meta: stop
						break
					count += 1
			main._log_action(main.tr("%s: %d expedition(s) shuffled back into the deck.") % [_name(no), count], DANGER_COLOR)
		"remove_fewest_sector":
			var slots: Array[SectorSlot] = _occupied_slots(main)
			if slots.is_empty():
				return
			var fewest: int = 99
			for s: SectorSlot in slots:
				fewest = mini(fewest, s.get_all_placed_cards().size())
			var cands: Array[SectorSlot] = []
			for s: SectorSlot in slots:
				if s.get_all_placed_cards().size() == fewest:
					cands.append(s)
			var target: SectorSlot = cands[0]
			if cands.size() > 1:
				var labels: Array = []
				for s: SectorSlot in cands:
					labels.append(_sector_label(s))
				target = cands[await _pick_option(main, main.tr("%s: which sector is removed?") % _name(no), labels)]
			var label: String = _sector_label(target)
			for cd: CardData in target.fleet_remove_sector():
				board.add_to_discard(cd)
			main._log_action(main.tr("%s: sector removed — %s") % [_name(no), label], DANGER_COLOR)
		_:
			main._log_action(main.tr("%s: nothing happens.") % _name(no), DANGER_COLOR)

static func _option_possible(main: Main, o: Dictionary) -> bool:
	match str(o.get("kind", "")):
		"pay":
			return not main.get_node("Board")._compute_payment(int(o["color"]), int(o["n"])).is_empty()
		"destroy":
			return not _destroyable_slots(main, -1).is_empty()
		"lose_stored":
			return _stored_total(main) > 0
		"discard":
			return not _hand_cards(main).is_empty()
	return true

static func _option_text(main: Main, o: Dictionary) -> String:
	var n: int = int(o.get("n", 1))
	match str(o.get("kind", "")):
		"pay":
			return main.tr("Pay %d %s") % [n, CardData.color_name(int(o["color"]))]
		"destroy":
			return main.tr("Destroy %d card(s)") % n
		"lose_stored":
			return main.tr("Lose %d stored supplies") % n
		"discard":
			return main.tr("Discard %d card(s)") % n
	return str(o.get("kind", ""))

# Flip the top card of sectors face down. where: "rightmost"/"leftmost" (all n
# from that sector) or "any" (the player picks a sector each time; pref = a
# colour that must be picked if any top card has it).
static func _destroy(main: Main, no: int, n: int, where: String, pref: int) -> void:
	for i: int in n:
		var target: SectorSlot = null
		if where == "rightmost" or where == "leftmost":
			var slots: Array[SectorSlot] = _occupied_slots(main)
			if slots.is_empty():
				return
			target = slots[slots.size() - 1] if where == "rightmost" else slots[0]
			if target.fleet_top_card() == null:
				main._log_action(main.tr("%s: no card left to destroy there.") % _name(no), DANGER_COLOR)
				return
		else:
			var cands: Array[SectorSlot] = _destroyable_slots(main, pref)
			if cands.is_empty():
				return
			target = cands[0]
			if cands.size() > 1:
				var labels: Array = []
				for s: SectorSlot in cands:
					labels.append(_sector_label(s))
				target = cands[await _pick_option(main, main.tr("%s: destroy the top card of which sector?") % _name(no), labels)]
		var card: Node3D = target.fleet_top_card()
		target.fleet_destroy_card(card, _back_path(card))
		main._log_action(main.tr("%s: %s destroyed (flipped face down).") % [_name(no), card.card_data.card_name], DANGER_COLOR)

static func _destroyable_slots(main: Main, pref: int) -> Array[SectorSlot]:
	var all: Array[SectorSlot] = []
	var preferred: Array[SectorSlot] = []
	for s: SectorSlot in _occupied_slots(main):
		var top: Node3D = s.fleet_top_card()
		if top == null:
			continue
		all.append(s)
		if pref >= 0 and top.card_data and int(top.card_data.color) == pref:
			preferred.append(s)
	return preferred if not preferred.is_empty() else all

static func _back_path(card: Node3D) -> String:
	if card.card_data and card.card_data.card_type == CardData.CardType.EXPEDITION:
		return CardDatabase.expedition_back_path()
	return CardDatabase.tech_back_path()

# Lose n stored supplies (and/or archived cards), the player picking each one.
static func _lose_items(main: Main, no: int, n: int, stored: bool, archived: bool) -> void:
	for i: int in n:
		var items: Array[Dictionary] = []
		for s: SectorSlot in _occupied_slots(main):
			if stored:
				for col: int in s.stored_supply:
					if int(s.stored_supply[col]) > 0:
						items.append({"slot": s, "color": col, "label": main.tr("Stored %s on %s") % [CardData.color_name(col), _sector_name(s)]})
			if archived:
				for t: Dictionary in s.tucked_cards:
					var cd: CardData = t["data"]
					items.append({"slot": s, "tuck": t, "label": main.tr("Archived %s under %s") % [cd.card_name if bool(t["face_up"]) else main.tr("face-down card"), _sector_name(s)]})
		if items.is_empty():
			return
		var pick: Dictionary = items[0]
		if items.size() > 1:
			var labels: Array = []
			for it: Dictionary in items:
				labels.append(it["label"])
			pick = items[await _pick_option(main, main.tr("%s: lose which? (%d of %d)") % [_name(no), i + 1, n], labels)]
		var slot: SectorSlot = pick["slot"]
		if pick.has("color"):
			var col: int = int(pick["color"])
			slot.stored_supply[col] = int(slot.stored_supply[col]) - 1
			if int(slot.stored_supply[col]) <= 0:
				slot.stored_supply.erase(col)
		else:
			slot.tucked_cards.erase(pick["tuck"])
			main.get_node("Board").add_to_discard((pick["tuck"] as Dictionary)["data"])
		slot.refresh_display()
		main._log_action(main.tr("%s: lost %s.") % [_name(no), pick["label"]], DANGER_COLOR)

# ── Solving ───────────────────────────────────────────────────────────────────

static func can_solve(main: Main, no: int) -> bool:
	var sv: Dictionary = FleetRules.SOLVES.get(no, {})
	var n: int = int(sv.get("n", 1))
	var hand: Array[Node3D] = _hand_cards(main)
	match str(sv.get("kind", "")):
		"pay":
			return not main.get_node("Board")._compute_payment(int(sv["color"]), n).is_empty()
		"discard_color":
			return _cards_of_colors(hand, sv["colors"]).size() >= n
		"discard_stars":
			var total: int = 0
			for c: Node3D in hand:
				total += c.card_data.stars
			return total >= n
		"discard_each_color":
			for col: int in 6:
				if _cards_of_colors(hand, [col]).is_empty():
					return false
			return true
		"destroy":
			return not _destroyable_slots(main, -1).is_empty()
		"lose_archived":
			return _archived(main, false, 0).size() >= n
		"flip_archived":
			return not _archived(main, true, int(sv.get("stars", 0))).is_empty()
		"destroy_expedition":
			return not _placed_expeditions(main).is_empty()
		"complete_rightmost":
			var slots: Array[SectorSlot] = _occupied_slots(main)
			return not slots.is_empty() and slots[slots.size() - 1].is_complete()
		"optimized_color":
			for s: SectorSlot in _occupied_slots(main):
				if s.is_optimized and _sector_color(s) == int(sv["color"]):
					return true
			return false
		"cards_in_sector":
			for s: SectorSlot in _occupied_slots(main):
				var count: int = 0
				for c: Node3D in s.get_all_placed_cards():
					if c.card_data and not c.has_meta(FleetRules.DESTROYED_META) \
							and int(CardData.effective_color(c.card_data, bool(c.get("is_advanced")))) == int(sv["color"]):
						count += 1
				if count >= n:
					return true
			return false
		"dust_deck_empty":
			var market: Node = main.get_node("Board").get_market()
			for i: int in 3:
				if market.get_dust_card_data(i) == null:
					return true
			return false
		"complete_optimized":
			for s: SectorSlot in _occupied_slots(main):
				if s.is_complete() and s.is_optimized:
					return true
			return false
		"complete_color":
			for s: SectorSlot in _occupied_slots(main):
				if s.is_complete() and (sv["colors"] as Array).has(_sector_color(s)):
					return true
			return false
		"hand_empty":
			return hand.is_empty()
		"expedition_bought":
			return bool(main._fleet.entry(no).get("expedition_bought", false))
	return false

static func try_solve(main: Main, no: int) -> void:
	if main._fleet == null or main._fleet_busy or main._effect_mode != Main.EffectMode.NONE:
		return
	if not can_solve(main, no):
		main._log_action(main.tr("Can't solve %s yet.") % _name(no), DANGER_COLOR)
		return
	var sv: Dictionary = FleetRules.SOLVES.get(no, {})
	var n: int = int(sv.get("n", 1))
	var board: Node = main.get_node("Board")
	main._fleet_busy = true
	var done: bool = true
	match str(sv.get("kind", "")):
		"pay":
			var pay: Dictionary = board._compute_payment(int(sv["color"]), n)
			var ok: int = await _pick_option(main, main.tr("Solve %s: pay %d %s?") % [_name(no), n, CardData.color_name(int(sv["color"]))],
					[main.tr("Pay"), main.tr("Cancel")])
			done = ok == 0
			if done:
				for col: int in pay:
					main._cs_display.spend_supply(col, int(pay[col]))
		"discard_color":
			var cands: Array[Node3D] = _cards_of_colors(_hand_cards(main), sv["colors"])
			done = await _discard_from_hand(main, main.tr("Solve %s: discard %d card(s)") % [_name(no), n], cands, n, false)
		"discard_stars":
			var cands: Array[Node3D] = []
			for c: Node3D in _hand_cards(main):
				if c.card_data.stars > 0:
					cands.append(c)
			done = await _discard_for_stars(main, no, cands, n)
		"discard_each_color":
			var picks: Array[Node3D] = []
			var hand: Array[Node3D] = _hand_cards(main)
			for col: int in 6:
				var of_col: Array[Node3D] = _cards_of_colors(hand, [col])
				of_col.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.card_data.stars < b.card_data.stars)
				picks.append(of_col[0])
			var names: PackedStringArray = []
			for c: Node3D in picks:
				names.append(c.card_data.card_name)
			var ok: int = await _pick_option(main, main.tr("Solve %s: discard %s?") % [_name(no), ", ".join(names)], [main.tr("Discard"), main.tr("Cancel")])
			done = ok == 0
			if done:
				_discard_nodes(main, picks)
		"destroy":
			await _destroy(main, no, n, "any", -1)
		"lose_archived":
			await _lose_items(main, no, n, false, true)
		"flip_archived":
			var items: Array[Dictionary] = _archived(main, true, int(sv.get("stars", 0)))
			var labels: Array = []
			for it: Dictionary in items:
				labels.append(it["label"])
			labels.append(main.tr("Cancel"))
			var pick: int = await _pick_option(main, main.tr("Solve %s: flip which archived card face down?") % _name(no), labels)
			done = pick < items.size()
			if done:
				(items[pick]["tuck"] as Dictionary)["face_up"] = false
				(items[pick]["slot"] as SectorSlot).refresh_display()
		"destroy_expedition":
			var exps: Array[Dictionary] = _placed_expeditions(main)
			var labels: Array = []
			for it: Dictionary in exps:
				labels.append(it["label"])
			labels.append(main.tr("Cancel"))
			var pick: int = await _pick_option(main, main.tr("Solve %s: destroy which expedition?") % _name(no), labels)
			done = pick < exps.size()
			if done:
				var card: Node3D = exps[pick]["card"]
				(exps[pick]["slot"] as SectorSlot).fleet_destroy_card(card, CardDatabase.expedition_back_path())
	main._fleet_busy = false
	if not done:
		return
	main._fleet.solve(no)
	main._log_action(main.tr("Danger solved: %s") % _name(no), SOLVED_COLOR)
	UIAudio.play_fuse_sfx()
	_after_change(main)

static func _discard_for_stars(main: Main, no: int, cands: Array[Node3D], need: int) -> bool:
	while true:
		var idx: Array[int] = await _pick_cards(main, main.tr("Solve %s: discard cards worth %d ⭐ (none = cancel)") % [_name(no), need], cands, 0)
		if idx.is_empty():
			return false
		var total: int = 0
		var picks: Array[Node3D] = []
		for i: int in idx:
			picks.append(cands[i])
			total += cands[i].card_data.stars
		if total >= need:
			_discard_nodes(main, picks)
			return true
		main._log_action(main.tr("That's only %d ⭐ — %d needed.") % [total, need], DANGER_COLOR)
	return false

# Discard exactly n of cands (fewer if there aren't n). mandatory: keep asking;
# otherwise picking nothing cancels. Returns false if cancelled.
static func _discard_from_hand(main: Main, prompt: String, cands: Array[Node3D], n: int, mandatory: bool) -> bool:
	var need: int = mini(n, cands.size())
	if need <= 0:
		return mandatory
	if cands.size() == need and mandatory:
		_discard_nodes(main, cands)
		return true
	while true:
		var idx: Array[int] = await _pick_cards(main, prompt + (main.tr(" — pick %d") % need), cands, need)
		if idx.size() == need:
			var picks: Array[Node3D] = []
			for i: int in idx:
				picks.append(cands[i])
			_discard_nodes(main, picks)
			return true
		if idx.is_empty() and not mandatory:
			return false
	return false

static func _discard_nodes(main: Main, cards: Array[Node3D]) -> void:
	var board: Node = main.get_node("Board")
	var hand: Node = main.get_node("Hand")
	for c: Node3D in cards:
		main._log_action(main.tr("Discarded %s.") % c.card_data.card_name, DANGER_COLOR)
		board.add_to_discard(c.card_data)
		hand.remove_card_fly_out(c)

# ── Mission ───────────────────────────────────────────────────────────────────

static func stats(main: Main) -> Dictionary:
	var st: Dictionary = {"stars": 0, "stored": 0, "stored_by": {}, "optimized": 0, "complete": 0,
			"cards_by": {}, "archived": 0, "archived_stars": 0, "faceup_stars": 0}
	for line: Dictionary in main.get_node("Board").calculate_score():
		st["stars"] = int(st["stars"]) + int(line.get("vp", 0))
	for s: SectorSlot in _occupied_slots(main):
		if s.is_optimized:
			st["optimized"] = int(st["optimized"]) + 1
		if s.is_complete():
			st["complete"] = int(st["complete"]) + 1
		for col: int in s.stored_supply:
			var k: int = int(s.stored_supply[col])
			st["stored"] = int(st["stored"]) + k
			st["stored_by"][col] = int(st["stored_by"].get(col, 0)) + k
		for c: Node3D in s.get_all_placed_cards():
			if not c.card_data or c.has_meta(FleetRules.DESTROYED_META):
				continue
			var adv: bool = bool(c.get("is_advanced"))
			var col: int = int(CardData.effective_color(c.card_data, adv))
			st["cards_by"][col] = int(st["cards_by"].get(col, 0)) + 1
			st["faceup_stars"] = int(st["faceup_stars"]) + c.card_data.stars
		for t: Dictionary in s.tucked_cards:
			st["archived"] = int(st["archived"]) + 1
			if bool(t["face_up"]):
				var cs: int = (t["data"] as CardData).stars
				st["archived_stars"] = int(st["archived_stars"]) + cs
				st["faceup_stars"] = int(st["faceup_stars"]) + cs
			else:
				st["archived_stars"] = int(st["archived_stars"]) + 1   # face-down cards are 1 ⭐
	return st

## [{text, done}] per mission part, for the Dangers screen and the end.
static func mission_lines(main: Main) -> Array[Dictionary]:
	var st: Dictionary = stats(main)
	var players: int = maxi(1, GameNetwork.player_order.size())
	var out: Array[Dictionary] = []
	for part: Dictionary in FleetData.destination(GameNetwork.fleet_destination).get("mission", []):
		var need: int = int(part["value"]) * (players if str(part["scope"]) == "per_player" else 1)
		var col: int = int(part.get("color", 0))
		var have: int = 0
		var label: String = ""
		match str(part["kind"]):
			"stars":
				have = int(st["stars"]); label = main.tr("Stars")
			"stored":
				have = int(st["stored"]); label = main.tr("Stored supplies")
			"stored_color":
				have = int(st["stored_by"].get(col, 0)); label = main.tr("Stored %s") % CardData.color_name(col)
			"stored_set":
				have = 99
				for c: int in 6:
					have = mini(have, int(st["stored_by"].get(c, 0)))
				label = main.tr("Stored sets (1 of each colour)")
			"optimized":
				have = int(st["optimized"]); label = main.tr("Fully optimized sectors")
			"complete":
				have = int(st["complete"]); label = main.tr("Complete sectors")
			"cards_color":
				have = int(st["cards_by"].get(col, 0)); label = main.tr("%s cards") % CardData.color_name(col)
			"archived":
				have = int(st["archived"]); label = main.tr("Archived cards")
			"archived_stars":
				have = int(st["archived_stars"]); label = main.tr("⭐ on archived cards")
			"faceup_stars":
				have = int(st["faceup_stars"]); label = main.tr("Face-up ⭐ (archived or placed)")
		out.append({"text": "%s: %d / %d" % [label, mini(have, 999), need], "done": have >= need})
	return out

static func mission_met(main: Main) -> bool:
	for l: Dictionary in mission_lines(main):
		if not bool(l["done"]):
			return false
	return true

# ── Dangers screen ────────────────────────────────────────────────────────────

static func refresh_panel(main: Main) -> void:
	if main._fleet == null or main._fleet_panel == null:
		return
	var list: Array = []
	for e: Dictionary in main._fleet.active:
		var no: int = int(e["no"])
		list.append({"no": no, "solvable": not main._fleet_busy and can_solve(main, no)})
	main._fleet_panel.set_dangers(list, main._fleet.deck.size())
	if main._fleet_dest_view:
		main._fleet_dest_view.set_mission_progress(mission_lines(main))
		main._fleet_dest_view.set_generation(main._round, main._max_rounds)

static func _after_change(main: Main) -> void:
	main.get_node("Board").refresh_hand_discounts()
	main._cs_display.set_supply(C.DUST, main._cs_display.get_supply(C.DUST))   # re-check the fuse arrows
	main._refresh_card_counts()
	main._refresh_vp()
	refresh_panel(main)

# A card shown big on screen (no dimming behind it): for duration seconds, or
# until clicked when duration is 0.
static func show_card(main: Main, path: String, landscape: bool, duration: float) -> void:
	if path.is_empty():
		return
	var layer: Node = main.get_node("UILayer")
	var vp: Vector2 = main.get_viewport().get_visible_rect().size
	var h: float = vp.y * (0.42 if landscape else 0.6)
	var w: float = h * (89.0 / 63.5 if landscape else 63.5 / 89.0)
	var rect: TextureRect = TextureRect.new()
	rect.texture = load(path) as Texture2D
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://shaders/card_rounded.gdshader")
	mat.set_shader_parameter("brightness", 1.0)
	rect.material = mat
	layer.add_child(rect)
	rect.size = Vector2(w, h)
	rect.position = (vp - rect.size) / 2.0
	rect.pivot_offset = rect.size / 2.0
	rect.scale = Vector2(0.85, 0.85)
	rect.modulate.a = 0.0
	var tw: Tween = rect.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(rect, "modulate:a", 1.0, 0.2)
	tw.parallel().tween_property(rect, "scale", Vector2.ONE, 0.25)
	var close: Callable = func() -> void:
		if not is_instance_valid(rect):
			return
		var t2: Tween = rect.create_tween()
		t2.tween_property(rect, "modulate:a", 0.0, 0.2)
		t2.tween_callback(rect.queue_free)
	if duration > 0.0:
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		main.get_tree().create_timer(duration).timeout.connect(close)
	else:
		rect.mouse_filter = Control.MOUSE_FILTER_STOP
		rect.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
				close.call())

# ── Choices (awaited) ─────────────────────────────────────────────────────────

static func _pick_option(main: Main, prompt: String, labels: Array) -> int:
	main._fleet_choice_active = true
	main._choice_popup.show_choices(prompt, labels, false)
	var idx: int = await main._choice_popup.choice_made
	main._fleet_choice_active = false
	return idx

static func _pick_color(main: Main, prompt: String, colors: Array[int]) -> int:
	main._fleet_choice_active = true
	main._choice_popup.show_color_choices(prompt, colors, false)
	var idx: int = await main._choice_popup.choice_made
	main._fleet_choice_active = false
	return idx

static func _pick_cards(main: Main, prompt: String, cards: Array[Node3D], max_select: int) -> Array[int]:
	var data: Array[CardData] = []
	for c: Node3D in cards:
		data.append(c.card_data)
	main._fleet_choice_active = true
	main._choice_popup.show_multiselect_card_choices(prompt, data, max_select)
	var idx: Array[int] = await main._choice_popup.multiselect_confirmed
	main._fleet_choice_active = false
	return idx

# ── Board helpers ─────────────────────────────────────────────────────────────

static func _occupied_slots(main: Main) -> Array[SectorSlot]:
	var out: Array[SectorSlot] = []
	for s: SectorSlot in main.get_node("Board").get_sector_slots():
		if s.occupied:
			out.append(s)
	return out

static func _sector_color(s: SectorSlot) -> int:
	if not s.placed_card or not s.placed_card.card_data:
		return -1
	return int(CardData.effective_color(s.placed_card.card_data, bool(s.placed_card.get("is_advanced"))))

static func _sector_name(s: SectorSlot) -> String:
	if not s.placed_card or not s.placed_card.card_data:
		return "?"
	var cd: CardData = s.placed_card.card_data
	return cd.adv_name if bool(s.placed_card.get("is_advanced")) and not cd.adv_name.is_empty() else cd.card_name

static func _sector_label(s: SectorSlot) -> String:
	var top: Node3D = s.fleet_top_card()
	var top_name: String = top.card_data.card_name if top and top.card_data else "—"
	return "%s (%d cards, top: %s)" % [_sector_name(s), s.get_all_placed_cards().size(), top_name]

static func _stored_total(main: Main) -> int:
	var t: int = 0
	for s: SectorSlot in _occupied_slots(main):
		t += s.get_total_stored_supply()
	return t

static func _hand_cards(main: Main) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c: Node3D in main.get_node("Hand").get_cards():
		if c.card_data:
			out.append(c)
	return out

static func _cards_of_colors(cards: Array[Node3D], colors: Array) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c: Node3D in cards:
		if colors.has(int(c.card_data.color)):
			out.append(c)
	return out

static func _archived(main: Main, face_up_only: bool, min_stars: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: SectorSlot in _occupied_slots(main):
		for t: Dictionary in s.tucked_cards:
			var cd: CardData = t["data"]
			if face_up_only and (not bool(t["face_up"]) or cd.stars < min_stars):
				continue
			out.append({"slot": s, "tuck": t, "label": "%s (%s)" % [cd.card_name, _sector_name(s)]})
	return out

static func _placed_expeditions(main: Main) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: SectorSlot in _occupied_slots(main):
		for c: Node3D in s.get_all_placed_cards():
			if c.card_data and c.card_data.card_type == CardData.CardType.EXPEDITION and not c.has_meta(FleetRules.DESTROYED_META):
				out.append({"slot": s, "card": c, "label": "%s (%s)" % [c.card_data.card_name, _sector_name(s)]})
	return out

static func _name(no: int) -> String:
	return str(FleetData.danger(no).get("name", "?"))
