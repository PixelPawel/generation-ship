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
const DESTINATION_FILL: float = 0.85   # enlarged Destination: share of the view
const C := CardData.SupplyColor
const NL: String = "\n"

# ── Setup ─────────────────────────────────────────────────────────────────────

static func setup(main: Main) -> void:
	if not GameNetwork.fleet_mode:
		FleetRules.current = null
		return
	var rules: RefCounted = FleetRules.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if GameNetwork.is_multiplayer and GameNetwork.fleet_seed != 0:
		rng.seed = GameNetwork.fleet_seed   # every peer shuffles the same Danger deck
	else:
		rng.randomize()
	rules.setup(GameNetwork.fleet_destination, rng)
	FleetRules.current = rules
	main._fleet = rules
	var panel: Control = main._fleet_panel
	panel.danger_solve_pressed.connect(func(no: int) -> void: try_solve(main, no))
	# right-click / long press enlarges like the market's cards; right-clicking
	# another Danger while one is big swaps (Main._on_market_inspect_right_dismissed)
	panel.danger_inspect_requested.connect(func(no: int) -> void: inspect_danger(main, no))
	panel.danger_hover_started.connect(func(no: int) -> void:
		main._hovered_market_slot = ["danger", no]
		main._show_tooltip(danger_tooltip_title(main, no), danger_tooltip_text(main, no)))
	panel.danger_hover_ended.connect(func() -> void:
		main._hovered_market_slot = ["", -1]
		main._hide_tooltip())
	main._fleet_dest_view.destination_hover_started.connect(func() -> void:
		main._show_tooltip(FleetData.card_text("destination", GameNetwork.fleet_destination, "name"), destination_tooltip_text(main)))
	main._fleet_dest_view.destination_hover_ended.connect(main._hide_tooltip)
	main._fleet_dest_view.destination_inspect_requested.connect(func() -> void: inspect_destination(main))
	main.get_node("Board").fleet_rule_blocked.connect(func(msg: String) -> void:
		main._log_action(msg, DANGER_COLOR)
		main._show_tooltip(main.tr("Danger"), msg)
		main.get_tree().create_timer(2.5).timeout.connect(main._hide_tooltip))
	# Solve buttons and mission progress follow the game while the screen shows
	var timer: Timer = Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		auto_solve(main)
		if panel.visible or main._fleet_dest_view.visible:
			refresh_panel(main))
	main.add_child(timer)
	# Shuttle (online): drop a hand card on a teammate's row in the Players column
	if GameNetwork.is_multiplayer:
		var board: Node = main.get_node("Board")
		board.shuttle_target_provider = main.fleet_shuttle_target_at_mouse
		board.shuttle_requested.connect(main._fleet_on_shuttle_requested)
		var last_hl: Array = [0]
		var tree: SceneTree = main.get_tree()
		var highlight: Callable = func() -> void:
			if main._market_panel == null:
				return
			var dragging: bool = board._dragged_card != null and board._drag_origin == board.DragOrigin.HAND
			var pid: int = main.fleet_shuttle_target_at_mouse() if dragging else 0
			if pid != int(last_hl[0]):
				last_hl[0] = pid
				main._market_panel.set_shuttle_highlight(pid)
		tree.process_frame.connect(highlight)
		main.tree_exiting.connect(func() -> void: tree.process_frame.disconnect(highlight))
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
	auto_solve(main)

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
	if GameNetwork.is_multiplayer and main.multiplayer.is_server():
		for bot_id: int in GameNetwork.bot_ids:
			BotTurn.bot_fleet_place(main, bot_id, no)
		BotTurn.broadcast_bot_states(main)
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
			# done on every peer in lockstep: the deck positions come from the
			# shared Fleet RNG, not the market's own (unsynced) shuffle-back
			var em: Node = board.get_expedition_market()
			var deck: Node = em._expedition_deck
			var count: int = 0
			for i: int in em._stacks.size():
				var stack: Array = em._stacks[i]
				while not stack.is_empty():
					var card: Node3D = stack.pop_back() as Node3D
					if card and card.card_data:
						deck.insert_at(card.card_data, main._fleet.rng.randi() % (deck.remaining() + 1))
						count += 1
					if card:
						card.queue_free()
				em._update_slot_visuals(i)
			em.market_changed.emit()
			main._log_action(main.tr("%s: %d expedition(s) shuffled back into the deck.") % [_name(no), count], DANGER_COLOR)
		"pass_left":
			if GameNetwork.is_multiplayer and GameNetwork.player_order.size() > 1:
				main._log_action(main.tr("%s: everyone passes their hand to the left.") % _name(no), DANGER_COLOR)
				await main.fleet_pass_hand_left()
			else:
				main._log_action(main.tr("%s: nobody to pass cards to — nothing happens.") % _name(no), DANGER_COLOR)
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
			var target: SectorSlot = await _pick_sector(main, main.tr("%s: which sector is removed?") % _name(no), cands, false)
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
# ask (solving): always show the picker, with Cancel. Returns false if cancelled.
static func _destroy(main: Main, no: int, n: int, where: String, pref: int, ask: bool = false) -> bool:
	for i: int in n:
		var target: SectorSlot = null
		if where == "rightmost" or where == "leftmost":
			var slots: Array[SectorSlot] = _occupied_slots(main)
			if slots.is_empty():
				return true
			target = slots[slots.size() - 1] if where == "rightmost" else slots[0]
			if target.fleet_top_card() == null:
				main._log_action(main.tr("%s: no card left to destroy there.") % _name(no), DANGER_COLOR)
				return true
		else:
			var cands: Array[SectorSlot] = _destroyable_slots(main, pref)
			if cands.is_empty():
				return true
			target = await _pick_sector(main, main.tr("%s: destroy the top card of which sector?") % _name(no), cands, ask)
			if target == null:
				return false
		var card: Node3D = target.fleet_top_card()
		target.fleet_destroy_card(card, _back_path(card))
		main._log_action(main.tr("%s: %s destroyed (flipped face down).") % [_name(no), card.card_data.card_name], DANGER_COLOR)
	return true

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
# ask (solving): always show the picker, with Cancel. Returns false if cancelled.
static func _lose_items(main: Main, no: int, n: int, stored: bool, archived: bool, ask: bool = false) -> bool:
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
			return true
		var pick: Dictionary = items[0]
		var prompt: String = main.tr("%s: lose which? (%d of %d)") % [_name(no), i + 1, n]
		if not stored:   # archived cards only: show the cards
			var cards: Array[CardData] = []
			for it: Dictionary in items:
				cards.append((it["tuck"] as Dictionary)["data"])
			var ci: int = await _pick_card(main, prompt, cards, ask)
			if ci < 0:
				return false
			pick = items[ci]
		elif items.size() > 1 or ask:
			var labels: Array = []
			for it: Dictionary in items:
				labels.append(it["label"])
			if ask:
				labels.append(main.tr("Cancel"))
			var idx: int = await _pick_option(main, prompt, labels)
			if idx >= items.size():
				return false
			pick = items[idx]
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
	return true

# ── Solving ───────────────────────────────────────────────────────────────────

static func can_solve(main: Main, no: int) -> bool:
	if GameNetwork.is_multiplayer and not FleetRules.is_condition_solve(no):
		return main._fleet_session_no == 0   # the crew may cover it together
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
	if GameNetwork.is_multiplayer:
		_try_solve_online(main, no)
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
			done = await _discard_each_color(main, no)
		"destroy":
			done = await _destroy(main, no, n, "any", -1, true)
		"lose_archived":
			done = await _lose_items(main, no, n, false, true, true)
		"flip_archived":
			var items: Array[Dictionary] = _archived(main, true, int(sv.get("stars", 0)))
			var cards: Array[CardData] = []
			for it: Dictionary in items:
				cards.append((it["tuck"] as Dictionary)["data"])
			var pick: int = await _pick_card(main, main.tr("Solve %s: flip which archived card face down?") % _name(no), cards)
			done = pick >= 0
			if done:
				(items[pick]["tuck"] as Dictionary)["face_up"] = false
				(items[pick]["slot"] as SectorSlot).refresh_display()
		"destroy_expedition":
			var exps: Array[Dictionary] = _placed_expeditions(main)
			var cards: Array[CardData] = []
			for it: Dictionary in exps:
				cards.append((it["card"] as Node3D).card_data)
			var pick: int = await _pick_card(main, main.tr("Solve %s: destroy which expedition?") % _name(no), cards)
			done = pick >= 0
			if done:
				var card: Node3D = exps[pick]["card"]
				(exps[pick]["slot"] as SectorSlot).fleet_destroy_card(card, CardDatabase.expedition_back_path())
	main._fleet_busy = false
	if not done:
		return
	main._fleet.solve(no)
	_announce_solved(main, no, "")
	_after_change(main)

# ── Free solves: conditions solve themselves the moment they're met ───────────
# (e.g. optimizing a Dust sector solves Mining Incident before that optimize's
# own Dust gain resolves). Checked when a card is placed, before every effect
# step and every half second; not while the generation's Dangers resolve.
static func auto_solve(main: Main) -> void:
	if main._fleet == null or main._fleet_busy:
		return
	for e: Dictionary in main._fleet.active.duplicate():
		var no: int = int(e["no"])
		if not FleetRules.is_condition_solve(no) or not can_solve(main, no):
			continue
		# solved here at once (so the rest of this move already plays without
		# it), then the crew is told
		main._fleet.solve(no)
		_announce_solved(main, no, "")
		_after_change(main)
		if GameNetwork.is_multiplayer:
			main.fleet_request_solved(no)

## An effect step a Danger forbids outright: archiving under Neural Gear
## Malfunction, storing under it (and Liquids under Anti-Fusion Field).
static func step_blocked(step: Dictionary) -> bool:
	match str(step.get("type", "")):
		"tuck", "tuck_optional", "tuck_any_sector_optional", "recycle_tuck", "recycle_tuck_store_choice":
			return FleetRules.blocks_archive()
		"store_on_slot", "store_on_any_sector":
			return FleetRules.blocks_store(int(step.get("color", -1)))
		"store_per_card_here", "seedbanks", "caldera_colony":
			return FleetRules.blocks_store(-1)
	return false

# The solved Danger shown big with a green SOLVED banner (everyone sees it).
static func _announce_solved(main: Main, no: int, who: String) -> void:
	if who.is_empty():
		main._log_action(main.tr("Danger solved: %s") % _name(no), SOLVED_COLOR)
	else:
		main._log_action(main.tr("Danger solved by %s: %s") % [who, _name(no)], SOLVED_COLOR)
	UIAudio.play_fuse_sfx()
	show_card(main, FleetData.danger_art(no), false, CARD_SHOW_SEC)
	var banner: Node = TurnBanner.new()
	main.get_node("UILayer").add_child(banner)
	banner.play(main.tr("SOLVED"), SOLVED_COLOR, _name(no), 1.0)

# Dimension Pocket: the player picks 1 card of each of the 6 colours (none = cancel).
# ── Solving online ────────────────────────────────────────────────────────────
# Conditions: the player meeting it says so, the host tells everyone. Costs:
# the host opens a session, every human gets one prompt to pledge part of the
# (per-player-scaled) cost; when everyone has answered, the host checks the
# total — enough: each peer pays its pledge and the Danger is solved for all;
# short: nothing is paid. (Bots pledge on the host, see BotTurn.)

static func _try_solve_online(main: Main, no: int) -> void:
	if FleetRules.is_condition_solve(no):
		if not can_solve(main, no):
			main._log_action(main.tr("Can't solve %s yet.") % _name(no), DANGER_COLOR)
			return
		main.fleet_request_solved(no)
		return
	main.fleet_request_session(no)

static func on_solved(main: Main, no: int, who: String) -> void:
	if main._fleet == null or main._fleet.entry(no).is_empty():
		return   # (already solved here — the one who solved it)
	main._fleet.solve(no)
	_announce_solved(main, no, who)
	_after_change(main)

static func _item_data(it: Dictionary) -> CardData:
	if it.has("card"):
		return (it["card"] as Node3D).card_data
	return (it["tuck"] as Dictionary)["data"]

static func pledge_prompt(main: Main, no: int, who: String, need: int) -> void:
	var sv: Dictionary = FleetRules.SOLVES.get(no, {})
	var kind: String = str(sv.get("kind", ""))
	main._fleet_pledge_apply = Callable()
	main._log_action(main.tr("%s wants to solve %s — the crew needs %d.") % [who, _name(no), need], DANGER_COLOR)
	if main._fleet_choice_active or main._effect_mode != Main.EffectMode.NONE or main._fleet_busy:
		main._log_action(main.tr("(You're busy — you pledge nothing this time.)"), DANGER_COLOR)
		main.fleet_send_pledge(no, 0, [])
		return
	main._fleet_busy = true
	var units: int = 0
	var colors: Array = []
	var board: Node = main.get_node("Board")
	var title: String = main.tr("Solve %s (crew needs %d): your share?") % [_name(no), need]
	match kind:
		"pay":
			var col: int = int(sv["color"])
			var labels: Array = [main.tr("Nothing")]
			var plans: Array = [{}]
			for k: int in range(1, need + 1):
				var plan: Dictionary = board._compute_payment(col, k)
				if plan.is_empty():
					break
				labels.append(main.tr("%d %s") % [k, CardData.color_name(col)])
				plans.append(plan)
			var pick: int = await _pick_option(main, title, labels)
			units = pick
			if pick > 0:
				var plan: Dictionary = plans[pick]
				main._fleet_pledge_apply = func() -> void:
					for c: int in plan:
						main._cs_display.spend_supply(c, int(plan[c]))
		"discard_color", "discard_stars", "discard_each_color":
			var cands: Array[Node3D] = []
			for c: Node3D in _hand_cards(main):
				if kind == "discard_color" and not (sv["colors"] as Array).has(int(c.card_data.color)):
					continue
				if kind == "discard_stars" and c.card_data.stars <= 0:
					continue
				cands.append(c)
			if not cands.is_empty():
				var max_pick: int = need if kind != "discard_stars" else 0
				var idx: Array[int] = await _pick_cards(main, title + main.tr(" (none = nothing)"), cands, max_pick)
				var picks: Array[Node3D] = []
				for i: int in idx:
					picks.append(cands[i])
					if kind == "discard_stars":
						units += cands[i].card_data.stars
					elif kind == "discard_each_color":
						if not colors.has(int(cands[i].card_data.color)):
							colors.append(int(cands[i].card_data.color))
					else:
						units += 1
				if not picks.is_empty():
					main._fleet_pledge_apply = func() -> void:
						var still: Array[Node3D] = []
						for c: Node3D in picks:
							if is_instance_valid(c) and _hand_cards(main).has(c):
								still.append(c)
						_discard_nodes(main, still)
		"destroy":
			var slots: Array[SectorSlot] = []
			var cands: Array[SectorSlot] = _destroyable_slots(main, -1)
			while units < need and not cands.is_empty():
				var t: SectorSlot = await _pick_sector(main, title + main.tr(" — Skip when done"), cands, true)
				if t == null:
					break
				slots.append(t)
				cands.erase(t)
				units += 1
			if not slots.is_empty():
				main._fleet_pledge_apply = func() -> void:
					for t: SectorSlot in slots:
						var card: Node3D = t.fleet_top_card()
						if card:
							t.fleet_destroy_card(card, _back_path(card))
		"lose_archived", "flip_archived", "destroy_expedition":
			var pool: Array[Dictionary] = []
			if kind == "destroy_expedition":
				pool = _placed_expeditions(main)
			else:
				pool = _archived(main, kind == "flip_archived", int(sv.get("stars", 0)))
			var chosen: Array[Dictionary] = []
			while units < need and not pool.is_empty():
				var pd: Array[CardData] = []
				for it: Dictionary in pool:
					pd.append(_item_data(it))
				var pi: int = await _pick_card(main, title + main.tr(" — Skip when done"), pd, true)
				if pi < 0:
					break
				chosen.append(pool[pi])
				pool.remove_at(pi)
				units += 1
			if not chosen.is_empty():
				main._fleet_pledge_apply = func() -> void:
					for it: Dictionary in chosen:
						var slot: SectorSlot = it["slot"]
						if kind == "destroy_expedition":
							slot.fleet_destroy_card(it["card"], CardDatabase.expedition_back_path())
						elif kind == "flip_archived":
							(it["tuck"] as Dictionary)["face_up"] = false
						else:
							slot.tucked_cards.erase(it["tuck"])
							board.add_to_discard((it["tuck"] as Dictionary)["data"])
						slot.refresh_display()
	main._fleet_busy = false
	main.fleet_send_pledge(no, units, colors)

static func on_session_result(main: Main, no: int, ok: bool, total: int, need: int) -> void:
	if not ok:
		main._fleet_pledge_apply = Callable()
		main._log_action(main.tr("Not enough for %s — the crew pledged %d of %d. Nothing was paid.") % [_name(no), total, need], DANGER_COLOR)
		return
	if main._fleet_pledge_apply.is_valid():
		main._fleet_pledge_apply.call()
	main._fleet_pledge_apply = Callable()
	on_solved(main, no, main.tr("the crew"))

static func _discard_each_color(main: Main, no: int) -> bool:
	var cands: Array[Node3D] = []
	for c: Node3D in _hand_cards(main):
		cands.append(c)
	while true:
		var idx: Array[int] = await _pick_cards(main, main.tr("Solve %s: pick 1 card of each colour (none = cancel)") % _name(no), cands, 6)
		if idx.is_empty():
			return false
		var colors: Dictionary = {}
		var picks: Array[Node3D] = []
		for i: int in idx:
			picks.append(cands[i])
			colors[int(cands[i].card_data.color)] = true
		if picks.size() == 6 and colors.size() == 6:
			_discard_nodes(main, picks)
			return true
		main._log_action(main.tr("Pick exactly one card of each of the 6 colours."), DANGER_COLOR)
	return false

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
	while true:   # always the player's pick, even when every card has to go
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

## A bot's ship (BotTurn's board entries), host only.
static func bot_stats(main: Main, bot_id: int) -> Dictionary:
	var st: Dictionary = {"stars": 0, "stored": 0, "stored_by": {}, "optimized": 0, "complete": 0,
			"cards_by": {}, "archived": 0, "archived_stars": 0, "faceup_stars": 0}
	var board: Array = main.bot_boards.get(bot_id, []) as Array
	st["stars"] = BotScoring.board_vp(board)
	for entry_v: Variant in board:
		var e: Dictionary = entry_v as Dictionary
		var sector: CardData = e.get("sector") as CardData
		if sector == null:
			continue
		var techs: Array = e.get("techs", []) as Array
		if bool(e.get("is_optimized", false)):
			st["optimized"] = int(st["optimized"]) + 1
		if techs.size() + int(e.get("fleet_destroyed", 0)) >= 5:
			st["complete"] = int(st["complete"]) + 1
		var cards: Array = [{"cd": sector, "adv": bool(e.get("is_advanced", false))}]
		for t: Variant in techs:
			cards.append({"cd": t, "adv": false})
		for c: Dictionary in cards:
			var cd: CardData = c["cd"] as CardData
			if cd == null:
				continue
			var col: int = int(CardData.effective_color(cd, bool(c["adv"])))
			st["cards_by"][col] = int(st["cards_by"].get(col, 0)) + 1
			st["faceup_stars"] = int(st["faceup_stars"]) + cd.stars
		var stored: Dictionary = e.get("stored_supply", {}) as Dictionary
		for col: Variant in stored:
			st["stored"] = int(st["stored"]) + int(stored[col])
			st["stored_by"][int(col)] = int(st["stored_by"].get(int(col), 0)) + int(stored[col])
		for t_v: Variant in e.get("tucked_cards", []) as Array:
			var t: Dictionary = t_v as Dictionary
			st["archived"] = int(st["archived"]) + 1
			var tcd: CardData = t.get("data") as CardData
			if bool(t.get("face_up", false)) and tcd:
				st["archived_stars"] = int(st["archived_stars"]) + tcd.stars
				st["faceup_stars"] = int(st["faceup_stars"]) + tcd.stars
			else:
				st["archived_stars"] = int(st["archived_stars"]) + 1
	return st

## Every ship's stats: this player's own plus the crew's (from their board
## snapshots; online the host passes fresher ones at the end).
static func crew_stats(main: Main) -> Array[Dictionary]:
	var out: Array[Dictionary] = [stats(main)]
	if GameNetwork.is_multiplayer:
		var me: int = main.multiplayer.get_unique_id()
		for pid: int in GameNetwork.player_order:
			if pid != me:
				out.append(main._opp_snapshots.get(pid, {}).get("fleet", {}))
	return out

static func _stat(st: Dictionary, part: Dictionary) -> int:
	var col: int = int(part.get("color", 0))
	match str(part["kind"]):
		"stars": return int(st.get("stars", 0))
		"stored": return int(st.get("stored", 0))
		"stored_color": return int((st.get("stored_by", {}) as Dictionary).get(col, 0))
		"stored_set":
			var sets: int = 99
			for c: int in 6:
				sets = mini(sets, int((st.get("stored_by", {}) as Dictionary).get(c, 0)))
			return sets
		"optimized": return int(st.get("optimized", 0))
		"complete": return int(st.get("complete", 0))
		"cards_color": return int((st.get("cards_by", {}) as Dictionary).get(col, 0))
		"archived": return int(st.get("archived", 0))
		"archived_stars": return int(st.get("archived_stars", 0))
		"faceup_stars": return int(st.get("faceup_stars", 0))
	return 0

static func _part_label(main: Main, part: Dictionary) -> String:
	var col: int = int(part.get("color", 0))
	match str(part["kind"]):
		"stars": return main.tr("Stars")
		"stored": return main.tr("Stored supplies")
		"stored_color": return main.tr("Stored %s") % CardData.color_name(col)
		"stored_set": return main.tr("Stored sets (1 of each colour)")
		"optimized": return main.tr("Fully optimized sectors")
		"complete": return main.tr("Complete sectors")
		"cards_color": return main.tr("%s cards") % CardData.color_name(col)
		"archived": return main.tr("Archived cards")
		"archived_stars": return main.tr("⭐ on archived cards")
		"faceup_stars": return main.tr("Face-up ⭐ (archived or placed)")
	return "?"

## [{text, done}] per mission part. "per player": the crew's total must reach
## value x players; "each": every ship on its own (shown: the lowest ship).
static func mission_lines(main: Main, all_stats: Array = []) -> Array[Dictionary]:
	if all_stats.is_empty():
		all_stats = crew_stats(main)
	var players: int = maxi(1, all_stats.size())
	var out: Array[Dictionary] = []
	for part: Dictionary in FleetData.destination(GameNetwork.fleet_destination).get("mission", []):
		var value: int = int(part["value"])
		if str(part["scope"]) == "per_player":
			var total: int = 0
			for st: Dictionary in all_stats:
				total += _stat(st, part)
			var need: int = value * players
			out.append({"text": "%s: %d / %d" % [_part_label(main, part), mini(total, 999), need], "done": total >= need})
		else:
			var lowest: int = 999
			for st: Dictionary in all_stats:
				lowest = mini(lowest, _stat(st, part))
			var each: String = main.tr(" (each ship)") if players > 1 else ""
			out.append({"text": "%s%s: %d / %d" % [_part_label(main, part), each, lowest, value], "done": lowest >= value})
	return out

static func mission_met(main: Main, all_stats: Array = []) -> bool:
	for l: Dictionary in mission_lines(main, all_stats):
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

# ── Tooltips ──────────────────────────────────────────────────────────────────

static func danger_tooltip_title(main: Main, no: int) -> String:
	var always: bool = str(FleetData.danger(no).get("type", "")) == "always"
	return "%s — %s" % [FleetData.card_text("danger", no, "name"), main.tr("ALWAYS") if always else main.tr("PLACE")]

static func danger_tooltip_text(main: Main, no: int) -> String:
	var parts: PackedStringArray = []
	var eff: String = FleetData.card_text("danger", no, "effect")
	var sol: String = FleetData.card_text("danger", no, "solve")
	if not eff.is_empty():
		parts.append(main.tr("Effect: %s") % eff.replace(NL, " "))
	if not sol.is_empty():
		parts.append(main.tr("Solve: %s") % sol.replace(NL, " "))
	if FleetRules.is_condition_solve(no):
		parts.append(main.tr("(Solves itself as soon as this is met.)"))
	return NL.join(parts)

static func destination_tooltip_text(main: Main) -> String:
	var no: int = GameNetwork.fleet_destination
	var parts: PackedStringArray = [FleetData.card_text("destination", no, "effect1"),
			FleetData.card_text("destination", no, "effect2"), "", main.tr("Progress:")]
	for l: Dictionary in mission_lines(main):
		parts.append(("✔ " if bool(l["done"]) else "• ") + str(l["text"]))
	return NL.join(parts)

# ── Enlarging (the market's 3D inspect, with art-only cards) ─────────────────

static var _art_cards: Dictionary = {}   # art path -> CardData

# A CardData that only carries art, for Board.inspect_card_data. Portrait cards
# use the tech card shape, landscape ones the sector shape.
static func _art_card(path: String, card_name: String, landscape: bool) -> CardData:
	if _art_cards.has(path):
		return _art_cards[path]
	var cd: CardData = CardData.new()
	cd.card_name = card_name
	cd.card_type = CardData.CardType.SECTOR if landscape else CardData.CardType.TECH
	cd.local_art_path = path
	_art_cards[path] = cd
	return cd

static func inspect_danger(main: Main, no: int) -> void:
	var path: String = FleetData.danger_art(no)
	if path.is_empty():
		return
	var origin: Vector3 = CockpitRig.viewport_to_world(main, main._fleet_panel.get_danger_center(no))
	var center: Vector3 = CockpitRig.viewport_to_world(main, Vector2(main._info_viewport.size) * 0.5)
	main.get_node("Board").inspect_card_data(_art_card(path, _name(no), false), false, ["danger", no], origin, center)

static func inspect_destination(main: Main) -> void:
	var dest: Dictionary = FleetData.destination(GameNetwork.fleet_destination)
	var path: String = FleetData.destination_art(GameNetwork.fleet_destination)
	if path.is_empty():
		return
	# grows out of the control screen, in front of it, big enough to read
	var screen: MeshInstance3D = main.get_node("UiControl").find_child("gs_ui_control_screen", true, false) as MeshInstance3D
	var origin: Vector3 = screen.to_global(screen.mesh.get_aabb().get_center()) if screen else main.get_node("UiControl").global_position
	main.get_node("Board").inspect_card_data(_art_card(path, str(dest.get("name", "")), true), false, ["destination", 0], origin, origin, DESTINATION_FILL)

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

# The sector picker (sector card art), for cands only. Its Skip cancels when
# cancelable, otherwise the picker comes back. Returns null if cancelled.
static func _pick_sector(main: Main, prompt: String, cands: Array[SectorSlot], cancelable: bool) -> SectorSlot:
	var picker: Control = main._sector_picker
	while true:
		var result: Array = []
		var on_sel: Callable = func(s: SectorSlot) -> void: result.append(s)
		var on_skip: Callable = func() -> void: result.append(null)
		picker.sector_selected.connect(on_sel)
		picker.skipped.connect(on_skip)
		main._fleet_choice_active = true
		picker.setup(prompt, cands)
		while result.is_empty():
			await main.get_tree().process_frame
		picker.sector_selected.disconnect(on_sel)
		picker.skipped.disconnect(on_skip)
		picker.hide()
		main._fleet_choice_active = false
		if result[0] != null or cancelable:
			return result[0] as SectorSlot
	return null

# One card, shown with its art. Returns its index, or -1 if cancelled (only
# offered when cancelable).
static func _pick_card(main: Main, prompt: String, cards: Array[CardData], cancelable: bool = true) -> int:
	var popup: Control = main._choice_popup
	var result: Array = []
	var on_pick: Callable = func(i: int) -> void: result.append(i)
	var on_skip: Callable = func() -> void: result.append(-1)
	popup.choice_made.connect(on_pick)
	popup.skipped.connect(on_skip)
	main._fleet_choice_active = true
	popup.show_card_choices(prompt, cards, cancelable)
	while result.is_empty():
		await main.get_tree().process_frame
	popup.choice_made.disconnect(on_pick)
	popup.skipped.disconnect(on_skip)
	main._fleet_choice_active = false
	return int(result[0])

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
