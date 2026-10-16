extends RefCounted
# Card effects, step by step: the effect queue (process_next / execute one step)
# and the handlers for the more involved steps (choices, bids offered by
# effects, Seedbanks, Caldera Colony, Ice 9, promo techs...). Moved out of
# main.gd; static functions on Main, like BotTurn / CockpitRig / FleetFlow.
# The effect state itself (_effect_queue, _effect_mode, ...) stays on Main.

# True when every step only gains or stores a fixed supply: nothing to decide,
# and resolving it first never takes an option away.
static func _is_automatic_batch(steps: Array) -> bool:
	for step: Dictionary in steps:
		var t: String = str(step.get("type", ""))
		if not (t == "gain_supply" or t == "store_on_slot") or not step.has("color"):
			return false
	return true

static func _expedition_count_of(main: Main, pid: int) -> int:
	if pid == main.multiplayer.get_unique_id():
		return main.get_node("Board").get_all_placed_expeditions().size()
	var count: int = 0
	if main.bot_boards.has(pid):
		for entry: Variant in (main.bot_boards[pid] as Array):
			for t: Variant in ((entry as Dictionary).get("techs", []) as Array):
				if t is CardData and (t as CardData).card_type == CardData.CardType.EXPEDITION:
					count += 1
		return count
	var snap: Dictionary = main._opp_snapshots.get(pid, {}) as Dictionary
	for slot_v: Variant in (snap.get("slots", []) as Array):
		for n: Variant in ((slot_v as Dictionary).get("tech_names", []) as Array):
			if _expedition_names(main).has(str(n)):
				count += 1
	return count

static func _expedition_names(main: Main) -> Dictionary:
	if main._expedition_name_set.is_empty():
		for cd: CardData in CardDatabase.expeditions:
			main._expedition_name_set[cd.card_name] = true
	return main._expedition_name_set

# Always-effect source cards (Insects, Crops, 1-G Thrust, Einstein-Rosen
# Portal, etc.) are always techs or expeditions, never sectors.
static func _find_card_data_by_name(main: Main, card_name: String) -> CardData:
	if card_name.is_empty():
		return null
	for cd: CardData in CardDatabase.techs:
		if cd.card_name == card_name:
			return cd
	for cd: CardData in CardDatabase.expeditions:
		if cd.card_name == card_name:
			return cd
	return null

static func _process_next_effect(main: Main) -> void:
	if main._effect_queue.is_empty():
		main._effect_slot = null
		main._refresh_vp()
		main._refresh_card_counts()
		main.get_node("Board").set_cards_can_elevate(true)
		main._try_auto_end_turn()
		return
	main.get_node("Board").set_cards_can_elevate(false)
	var step: Dictionary = main._effect_queue.pop_front()
	_execute_effect_step(main, step)

static func _execute_effect_step(main: Main, step: Dictionary) -> void:
	if main._fleet:   # a free solve met by an earlier step counts before this one
		Main.FleetFlow.auto_solve(main)
	main._effect_source_name = str(step.get("_source_name", "Effect"))
	# Fleet: a Danger forbids what this step does (archive / store) — the
	# player just doesn't pick anything for it
	if main._fleet and Main.FleetFlow.step_blocked(step):
		main._log_effect(main.tr("a Danger stops this — skipped"))
		_process_next_effect(main)
		return
	match step.get("type", ""):

		"draw":
			var _before: Array[Node3D] = main.get_node("Hand").get_cards()
			main.get_node("Board").draw_cards(int(step.get("count", 0)))
			var _after: Array[Node3D] = main.get_node("Hand").get_cards()
			main._last_drawn_cards = _after.filter(func(c: Node3D) -> bool: return not _before.has(c))
			main._log_effect(main.tr("drew %d card(s)") % main._last_drawn_cards.size())
			_process_next_effect(main)

		"draw_recycle_top":
			# Lambdas capture locals by value, so plain reassignment inside one
			# never reaches the outer variable — box it in an Array (captured by
			# reference) so the connected callback can actually report back.
			var recycled_color_box: Array = [null, 1]
			var capture_color: Callable = func(c: CardData.SupplyColor, amt: int) -> void:
				recycled_color_box[0] = c
				recycled_color_box[1] = amt
			main.get_node("Board").card_recycled.connect(capture_color, CONNECT_ONE_SHOT)
			main.get_node("Board").draw_and_recycle_top()
			if main.get_node("Board").card_recycled.is_connected(capture_color):
				main.get_node("Board").card_recycled.disconnect(capture_color)
			if recycled_color_box[0] != null:
				main._log_effect(main.tr("drew and recycled the top card, gained %d %s") % [int(recycled_color_box[1]), CardData.color_name(recycled_color_box[0] as CardData.SupplyColor)])
			else:
				main._log_effect(main.tr("drew and recycled the top card"))
			_process_next_effect(main)

		"gain_supply":
			var gs_color: CardData.SupplyColor = step["color"] as CardData.SupplyColor
			var gs_amount: int = int(step.get("amount", 0))
			main._cs_display.add_supply(gs_color, gs_amount)
			main._log_effect(main.tr("gained %d %s") % [gs_amount, CardData.color_name(gs_color)])
			_process_next_effect(main)

		"store_on_slot":
			if main._effect_slot:
				var ss_color: CardData.SupplyColor = step["color"] as CardData.SupplyColor
				var ss_amount: int = int(step.get("amount", 0))
				main._effect_slot.add_stored_supply(ss_color, ss_amount)
				main._log_effect(main.tr("stored %d %s on the sector") % [ss_amount, CardData.color_name(ss_color)])
			_process_next_effect(main)

		"store_on_any_sector":
			main._pending_store_color = step["color"] as CardData.SupplyColor
			main._pending_store_amount = int(step.get("amount", 1))
			main._pending_store_from_supply = bool(step.get("from_supply", false))
			main._pending_store_spread = bool(step.get("spread", false)) and main._pending_store_amount > 1
			main._effect_mode = Main.EffectMode.EFFECT_STORE_ON_SECTOR
			main.get_node("Board").set_cargo_click_mode(true)
			main._open_store_picker()

		"store_per_card_here":
			if main._effect_slot:
				for c: Node3D in main._effect_slot.get_all_placed_cards():
					var cd: CardData = c.get("card_data")
					if cd:
						main._effect_slot.add_stored_supply(CardData.effective_color(cd, bool(c.get("is_advanced"))), 1)
			_process_next_effect(main)

		"gain_supply_per_stored":
			if main._effect_slot:
				var color: CardData.SupplyColor = step["color"] as CardData.SupplyColor
				var mult: int = int(step.get("multiplier", 1))
				var stored: int = main._effect_slot.get_stored_supply(color)
				main._cs_display.add_supply(color, stored * mult)
			_process_next_effect(main)

		"gain_supply_per_sector_count":
			var color: CardData.SupplyColor = step["color"] as CardData.SupplyColor
			var count: int
			if step.has("sector_color_filter"):
				count = main.get_node("Board").get_sector_count_by_color(step["sector_color_filter"] as CardData.SupplyColor)
			else:
				count = main.get_node("Board").get_sector_count()
			main._cs_display.add_supply(color, count)
			main._log_effect(main.tr("gained %d %s") % [count, CardData.color_name(color)])
			_process_next_effect(main)

		"fuse_notice":
			var count: int = int(step.get("count", 0))
			main._cs_display.add_fuse_1to1(count)
			main._log_effect(main.tr("granted %d fuse action(s)") % count)
			_process_next_effect(main)

		"fuse_dust_1to1":
			main._cs_display.set_dust_fuse_1to1(true)
			main._log_effect(main.tr("granted a Dust fuse action"))
			_process_next_effect(main)

		"recycle":
			main._effect_mode = Main.EffectMode.EFFECT_RECYCLE
			main._effect_remaining = int(step.get("count", 1))
			main._restrict_picks_to_drawn = bool(step.get("restrict_to_drawn", false))
			main._show_hand_popup(main.tr("Recycle %d card(s) from your hand") % main._effect_remaining, false)

		"recycle_optional":
			main._effect_mode = Main.EffectMode.EFFECT_RECYCLE_OPTIONAL
			main._effect_remaining = int(step.get("max", 1))
			main._restrict_picks_to_drawn = bool(step.get("restrict_to_drawn", false))
			main._show_hand_multiselect(main.tr("Recycle up to %d card(s) — draw 1 per recycled") % main._effect_remaining)

		"recycle_double":
			main._effect_mode = Main.EffectMode.EFFECT_RECYCLE_DOUBLE
			main._effect_remaining = int(step.get("count", 1))
			main._restrict_picks_to_drawn = bool(step.get("restrict_to_drawn", false))
			main._show_hand_popup(main.tr("Recycle %d card(s) — gain double supply") % main._effect_remaining, false)

		"tuck":
			main._effect_mode = Main.EffectMode.EFFECT_TUCK
			main._effect_remaining = int(step.get("count", 1))
			main._effect_face_up = bool(step.get("face_up", false))
			main._restrict_picks_to_drawn = bool(step.get("restrict_to_drawn", false))
			var face_str_t: String = main.tr("faceup") if main._effect_face_up else main.tr("facedown")
			main._show_hand_popup(main.tr("Tuck %d card(s) %s under this sector") % [main._effect_remaining, face_str_t], false)

		"tuck_optional":
			_effect_step_tuck_optional(main, step)

		"tuck_any_sector_optional":
			main._effect_mode = Main.EffectMode.EFFECT_TUCK_ANY_SECTOR
			main._effect_remaining = int(step.get("max", 1))
			main._effect_face_up = bool(step.get("face_up", false))
			main._effect_label = step.get("label", main.tr("Tuck"))
			var face_str_any: String = main.tr("faceup") if main._effect_face_up else main.tr("facedown")
			main._show_hand_popup(main.tr("%s — tuck a card %s? (%d remaining)") % [main._effect_label, face_str_any, main._effect_remaining], true)

		"recycle_tuck":
			main._effect_mode = Main.EffectMode.EFFECT_RECYCLE_TUCK
			main._effect_remaining = int(step.get("count", 2))
			main._show_hand_multiselect(main.tr("Recycle & tuck up to %d card(s) facedown — draw equal") % main._effect_remaining)

		"recycle_tuck_store_choice":
			main._effect_mode = Main.EffectMode.EFFECT_RECYCLE_TUCK_STORE
			main._effect_remaining = int(step.get("max", 4))
			main._show_hand_multiselect(main.tr("Recycle & tuck up to %d card(s) facedown — choose store or gain") % main._effect_remaining)

		"reveal_sector":
			main._pending_reveal_gain_supply = bool(step.get("gain_supply", false))
			main._pending_reveal_may_bid = bool(step.get("may_bid", false))
			main._pending_reveal_may_free_gain = bool(step.get("may_free_gain", false))
			main._effect_mode = Main.EffectMode.EFFECT_REVEAL_SECTOR
			main._show_effect_hint(main.hint("Click a free sector slot in the Market panel to reveal it", "Tap a free sector slot in the Market panel to reveal it"))
			main.get_node("Board").set_sector_reveal_mode(true)

		"reveal_expedition":
			main._pending_expedition_reveal_gain_supply = bool(step.get("gain_supply", false))
			main._pending_expedition_reveal_may_bid = bool(step.get("may_bid", false))
			main._effect_mode = Main.EffectMode.EFFECT_REVEAL_EXPEDITION
			main._show_effect_hint(main.hint("Click an expedition slot in the Market panel to reveal it", "Tap an expedition slot in the Market panel to reveal it"))
			main.get_node("Board").set_expedition_reveal_mode(true)

		"reveal_expedition_slot":
			_effect_step_reveal_expedition_slot(main, step)

		"choice":
			_effect_step_choice(main, step)

		"reflectors_choice":
			_effect_step_reflectors_choice(main)

		"offer_bid_pool":
			_effect_step_offer_bid_pool(main)

		"offer_free_sector_gain":
			_effect_step_offer_free_sector_gain(main)

		"free_sector_gain":
			var cd: CardData = step.get("card_data") as CardData
			if not cd:
				_process_next_effect(main)
				return
			var card_node: Node3D = main.get_node("Board").find_market_card(cd)
			if not card_node:
				_process_next_effect(main)
				return
			main.get_node("Board").market_origin_3d = CockpitRig.effect_card_origin(main, card_node, cd)
			main.get_node("Board").begin_free_sector_gain(card_node)

		"initiate_market_bid":
			var cd: CardData = step.get("card_data") as CardData
			if not cd:
				_process_next_effect(main)
				return
			var card_node: Node3D = main.get_node("Board").find_market_card(cd)
			if not card_node:
				_process_next_effect(main)
				return
			main._bid_is_from_effect = true
			if step.has("bid_color"):
				main.get_node("Board").bid_color_override = int(step["bid_color"])
				main._log_effect(main.tr("started a bid on %s, paid in %s") % [
					cd.adv_name if cd.card_type == CardData.CardType.SECTOR else cd.card_name,
					CardData.color_name(step["bid_color"] as CardData.SupplyColor)])
			main.get_node("Board").market_origin_3d = CockpitRig.effect_card_origin(main, card_node, cd)
			main.get_node("Board").begin_revealed_card_bid(card_node)

		"seedbanks":
			_effect_step_seedbanks(main)

		"caldera_colony":
			_effect_step_caldera_colony(main)

		"cargo_drones":
			main._effect_mode = Main.EffectMode.EFFECT_CARGO_DRONES
			main._cargo_drones_panel.start(main.get_node("Board").get_all_sector_slots())

		"interfleet_comms":
			_effect_step_interfleet_comms(main)

		"draw_all_players":
			_effect_step_draw_all_players(main, int(step.get("count", 1)))

		"offer_bid_any_expedition":
			_effect_step_offer_bid_any_expedition(main)

		"black_hole_encounter":
			_effect_step_black_hole_encounter(main)

		"placing_color":
			_effect_step_placing_color(main, step["color"] as CardData.SupplyColor)

		"recycle_from_own_sector":
			_effect_step_recycle_from_own_sector(main)

		"recycle_sector_card":
			_effect_step_recycle_sector_card(main, step.get("card_node") as Node3D, step.get("slot") as SectorSlot)

		"earth_support":
			_effect_step_earth_support(main, step["color"] as CardData.SupplyColor)

		"wormhole_surfing":
			_effect_step_wormhole_surfing(main)

		_:
			_process_next_effect(main)

static func _effect_step_tuck_optional(main: Main, step: Dictionary) -> void:
	main._effect_mode = Main.EffectMode.EFFECT_TUCK_OPTIONAL
	main._effect_remaining = int(step.get("max", 1))
	main._effect_face_up = bool(step.get("face_up", false))
	main._restrict_picks_to_drawn = bool(step.get("restrict_to_drawn", false))
	main._tuck_optional_no_bonus_draw = bool(step.get("no_bonus_draw", false))
	var face_str_to: String = main.tr("faceup") if main._effect_face_up else main.tr("facedown")
	var prompt_to: String
	if main._restrict_picks_to_drawn:
		prompt_to = main.tr("Archive up to %d of the drawn cards %s") % [main._effect_remaining, face_str_to]
	elif main._tuck_optional_no_bonus_draw:
		prompt_to = main.tr("Tuck up to %d card(s) %s") % [main._effect_remaining, face_str_to]
	else:
		prompt_to = main.tr("Archive up to %d card(s) %s — draw 1 per archived card") % [main._effect_remaining, face_str_to]
	main._show_hand_multiselect(prompt_to)

static func _effect_step_reveal_expedition_slot(main: Main, step: Dictionary) -> void:
	var exp_slot: int = int(step.get("slot", 0))
	var revealed: CardData = main.get_node("Board").reveal_expedition_to_slot(exp_slot)
	if bool(step.get("gain_supply", false)) and revealed:
		main._cs_display.add_supply(revealed.color, 1)
	if bool(step.get("may_bid", false)) and revealed:
		main._reveal_bid_pool.append(revealed)
	if GameNetwork.is_multiplayer:
		if GameNetwork.is_host:
			main._rpc_sync_expedition_reveal.rpc(exp_slot)
		else:
			main._rpc_notify_expedition_reveal.rpc_id(1, exp_slot)
	_process_next_effect(main)

static func _effect_step_choice(main: Main, step: Dictionary) -> void:
	main._effect_mode = Main.EffectMode.EFFECT_CHOICE
	main._pending_choice_options = step.get("options", [])
	if not bool(step.get("skippable", false)) and main._auto_pick_single_option():
		return
	var labels: Array[String] = []
	var tints: Array[Color] = []
	for opt: Dictionary in main._pending_choice_options:
		labels.append(str(opt.get("label", main.tr("?"))))
		if opt.has("tint"):
			tints.append(opt["tint"] as Color)
	var choice_cd: CardData = null
	var choice_is_adv: bool = false
	if main._effect_slot and is_instance_valid(main._effect_slot) and main._effect_slot.placed_card:
		choice_cd = main._effect_slot.placed_card.card_data
		choice_is_adv = bool(main._effect_slot.placed_card.get("is_advanced"))
	# Pure supply-color choices (every option tagged with a `color`) use the
	# supply diamond; anything mixed stays a row of text buttons.
	var colors: Array[int] = []
	for opt: Dictionary in main._pending_choice_options:
		if not opt.has("color"):
			colors.clear()
			break
		colors.append(int(opt["color"]))
	if not colors.is_empty():
		main._choice_popup.show_color_choices(main.tr(str(step.get("prompt", "Choose:"))), colors,
			bool(step.get("skippable", false)), choice_cd, choice_is_adv)
		return
	main._choice_popup.show_choices(
		main.tr(str(step.get("prompt", "Choose:"))),
		labels,
		bool(step.get("skippable", false)),
		tints,
		choice_cd,
		choice_is_adv
	)

static func _effect_step_reflectors_choice(main: Main) -> void:
	if not main._effect_slot:
		_process_next_effect(main)
		return
	var eligible_cards: Array[CardData] = []
	var eligible_steps: Array = []
	for card_node: Node3D in main._effect_slot.get_all_placed_cards():
		var cd: CardData = card_node.get("card_data")
		# get_all_placed_cards() includes the sector itself (placed_card) —
		# exclude that (sectors have no place effect to copy) and Reflectors
		# itself, but allow both Tech AND Expedition place effects, since an
		# Expedition can occupy this same sector slot.
		if not cd or cd.card_type == CardData.CardType.SECTOR or cd.card_name == "Reflectors":
			continue
		var copied: Array[Dictionary] = PlaceEffects.get_steps(cd, main._effect_slot)
		if copied.is_empty():
			continue
		eligible_cards.append(cd)
		eligible_steps.append(copied)
	if eligible_cards.is_empty():
		_process_next_effect(main)
		return
	main._pending_choice_options = []
	for i: int in eligible_cards.size():
		main._pending_choice_options.append({steps = eligible_steps[i]})
	main._effect_mode = Main.EffectMode.EFFECT_CHOICE
	main._choice_popup.show_card_choices(main.tr("Reflectors — copy which effect?"), eligible_cards, true)

static func _effect_step_offer_bid_pool(main: Main) -> void:
	if main._reveal_bid_pool.is_empty():
		_process_next_effect(main)
		return
	var pool: Array[CardData] = main._reveal_bid_pool.duplicate()
	main._reveal_bid_pool.clear()
	main._pending_choice_options = []
	for cd: CardData in pool:
		main._pending_choice_options.append({steps = [{type = "initiate_market_bid", card_data = cd}]})
	main._effect_mode = Main.EffectMode.EFFECT_CHOICE
	main._choice_popup.show_card_choices(main.tr("Bid on a revealed card?"), pool, true)

# Unlike _effect_step_offer_bid_pool (only the card(s) this same effect just
# revealed), Probe Launcher's text is "you may bid on any expedition" — the
# pool is every expedition currently revealed and visible in the market
# (the top card of each of the 3 slots, same pool bots draw from via
# get_available_expeditions()), not every card ever drawn into those slots —
# older cards buried underneath a slot's current top are no longer up for
# auction and shouldn't be biddable here either.
static func _effect_step_offer_bid_any_expedition(main: Main) -> void:
	var pool: Array[CardData] = main.get_node("Board").get_available_expeditions()
	if pool.is_empty():
		_process_next_effect(main)
		return
	main._pending_choice_options = []
	for cd: CardData in pool:
		main._pending_choice_options.append({steps = [{type = "initiate_market_bid", card_data = cd}]})
	main._effect_mode = Main.EffectMode.EFFECT_CHOICE
	main._choice_popup.show_card_choices(main.tr("Probe Launcher — bid on any expedition?"), pool, true)

static func _effect_step_offer_free_sector_gain(main: Main) -> void:
	var eligible: Array[CardData] = []
	var eligible_adv: Array[bool] = []
	for cd: CardData in main._reveal_free_pool:
		if cd.adv_color == CardData.SupplyColor.DUST or cd.adv_color == CardData.SupplyColor.LIQUIDS:
			eligible.append(cd)
			eligible_adv.append(true)
	main._reveal_free_pool.clear()
	# "gain Dust sector or Liquids sector": any Liquids sector on display counts,
	# not only the ones this card just revealed
	for cd: CardData in main.get_node("Board").get_available_advanced_sectors():
		if not eligible.has(cd) and (cd.adv_color == CardData.SupplyColor.DUST or cd.adv_color == CardData.SupplyColor.LIQUIDS):
			eligible.append(cd)
			eligible_adv.append(true)
	for cd: CardData in main.get_node("Board").get_available_dust_sectors():
		if not eligible.has(cd):
			eligible.append(cd)
			eligible_adv.append(false)
	if eligible.is_empty():
		_process_next_effect(main)
		return
	main._pending_choice_options = []
	for cd: CardData in eligible:
		main._pending_choice_options.append({steps = [{type = "free_sector_gain", card_data = cd}]})
	main._effect_mode = Main.EffectMode.EFFECT_CHOICE
	if main._auto_pick_single_option():
		return
	main._choice_popup.show_card_choices(main.tr("Inflatable Hull — gain which sector for free?"), eligible, false, eligible_adv)

static func _effect_step_seedbanks(main: Main) -> void:
	main._effect_mode = Main.EffectMode.EFFECT_SEEDBANKS
	var all_cards: Array[Node3D] = main.get_node("Hand").get_cards()
	main._pending_recycle_cards = []
	var card_data: Array[CardData] = []
	for c: Node3D in all_cards:
		var cd: CardData = c.get("card_data") as CardData
		if cd:
			main._pending_recycle_cards.append(c)
			card_data.append(cd)
	if card_data.is_empty():
		main._finish_interactive_step()
	else:
		main._choice_popup.show_multiselect_card_choices(
			main.tr("Seedbanks — select cards to recycle (supplies stored on sector)"), card_data)

static func _effect_step_caldera_colony(main: Main) -> void:
	main._caldera_slots = []
	var caldera_cards: Array[CardData] = []
	var caldera_advanced_flags: Array[bool] = []
	for slot: SectorSlot in main.get_node("Board").get_all_sector_slots():
		if not slot.occupied or not slot.placed_card or not slot.placed_card.card_data:
			continue
		main._caldera_slots.append(slot)
		caldera_cards.append(slot.placed_card.card_data as CardData)
		caldera_advanced_flags.append(bool(slot.placed_card.get("is_advanced")))
	if caldera_cards.is_empty():
		main._finish_interactive_step()
		return
	main._effect_mode = Main.EffectMode.EFFECT_CALDERA_SELECT_SECTOR
	main._choice_popup.show_card_choices(main.tr("Caldera Colony — choose a sector:"), caldera_cards, true, caldera_advanced_flags)

# "Draw 1 per player, keep 1, then pass cards left" — needs real network sync
# since every other player must see and pick from the same shared pool. Async
# like reveal_sector/cargo_drones: does not call _process_next_effect() itself,
# that happens once the whole pass-around sequence resolves (see
# _rpc_sync_interfleet_finished).
static func _effect_step_interfleet_comms(main: Main) -> void:
	if not GameNetwork.is_multiplayer:
		main.get_node("Board").draw_cards(1)
		main._log_effect(main.tr("drew 1 card (Interfleet Comms, solo)"))
		_process_next_effect(main)
		return
	main._effect_mode = Main.EffectMode.EFFECT_INTERFLEET_PICK
	if GameNetwork.is_host:
		main._server_start_interfleet(main.multiplayer.get_unique_id())
	else:
		main._rpc_request_interfleet.rpc_id(1)

# "Every player draws 1" (Gas Cloud) — unlike Interfleet Comms there's no
# shared pool or picking, each player just draws from their own independent
# deck, but since a placed card's effect queue only ever runs on the placing
# player's own client, every other client still needs an explicit RPC to
# know to draw at all. Async like _effect_step_interfleet_comms: resumes via
# _rpc_sync_draw_all_finished once the deal completes.
static func _effect_step_draw_all_players(main: Main, count: int) -> void:
	if not GameNetwork.is_multiplayer:
		main.get_node("Board").draw_cards(count)
		main._log_effect(main.tr("everyone draws %d card(s), solo") % count)
		_process_next_effect(main)
		return
	main._effect_mode = Main.EffectMode.EFFECT_AWAITING_ALL_DRAW
	var source: String = main._effect_source_name if not main._effect_source_name.is_empty() else main.tr("Effect")
	if GameNetwork.is_host:
		main._server_handle_draw_all_players(count, 1, source)
	else:
		main._rpc_request_draw_all_players.rpc_id(1, count, source)

static func _effect_step_black_hole_encounter(main: Main) -> void:
	main._effect_mode = Main.EffectMode.EFFECT_EXPEDITION_SHUFFLE
	main._effect_remaining = 3
	main._shuffle_count = 0
	main._show_effect_hint(main.hint("Click up to 3 expeditions to shuffle back — then click Done", "Tap up to 3 expeditions to shuffle back — then tap Done"))
	main._effect_done_btn.show()
	main.get_node("Board").set_expedition_shuffle_mode(true)

# Karma Chameleon: it sat out its own placement's optimize check (see
# Board._mark_color_choice_pending); now re-run it counting as the chosen
# color, queue any newly satisfied optimize level, then discard it — the
# sector can then be optimized again with another card.
static func _effect_step_placing_color(main: Main, color: CardData.SupplyColor) -> void:
	if not main._effect_slot or not is_instance_valid(main._effect_slot):
		_process_next_effect(main)
		return
	var levels: Array[int] = main.get_node("Board").apply_placing_color(main._effect_slot, color)
	main._log_effect(main.tr("counted as %s while being placed, then discarded") % CardData.color_name(color))
	var opt_steps: Array = []
	for _level: int in levels:
		opt_steps.append_array(SectorEffects.get_optimize_steps(main._effect_slot))
	for i: int in opt_steps.size():
		main._effect_queue.insert(i, opt_steps[i])
	main.get_node("Board").discard_karma_chameleon(main._effect_slot)
	main._broadcast_my_state()
	_process_next_effect(main)

# Ice 9: recycle any Tech/Expedition on one of your own sectors (not Ice 9
# itself). Same removal path as Caldera Colony. Two steps: pick the sector
# (sector picker, or click it on the board), then the card on it — skipped
# straight to the cards when only one sector has anything to recycle.
static func _effect_step_recycle_from_own_sector(main: Main) -> void:
	var slots: Array[SectorSlot] = []
	for slot: SectorSlot in main.get_node("Board").get_all_sector_slots():
		if not _ice9_cards_on(main, slot).is_empty():
			slots.append(slot)
	if slots.is_empty():
		main._log_effect(main.tr("no card on your sectors to recycle"))
		_process_next_effect(main)
		return
	if slots.size() == 1:
		_ice9_choose_card(main, slots[0])
		return
	main._effect_mode = Main.EffectMode.EFFECT_ICE9_SECTOR
	main.get_node("Board").set_cargo_click_mode(true)
	main._sector_picker.setup(main.tr("Ice 9 — pick a sector to recycle a card from"), slots)

static func _ice9_cards_on(main: Main, slot: SectorSlot) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if not slot.occupied:
		return out
	for c: Node3D in slot.get_all_placed_cards():
		var cd: CardData = c.get("card_data") as CardData
		if cd and cd.card_type != CardData.CardType.SECTOR and cd.card_name != "Ice 9":
			out.append(c)
	return out

static func _ice9_choose_card(main: Main, slot: SectorSlot) -> void:
	var choices: Array[CardData] = []
	main._pending_choice_options = []
	for c: Node3D in _ice9_cards_on(main, slot):
		choices.append(c.get("card_data") as CardData)
		main._pending_choice_options.append({steps = [{type = "recycle_sector_card", card_node = c, slot = slot, _source_name = main._effect_source_name}]})
	main._effect_mode = Main.EffectMode.EFFECT_CHOICE
	if main._auto_pick_single_option():
		return
	main._choice_popup.show_card_choices(main.tr("Ice 9 — recycle which card?"), choices, false)

static func _effect_step_recycle_sector_card(main: Main, card: Node3D, slot: SectorSlot) -> void:
	if not is_instance_valid(card) or not is_instance_valid(slot) or not card.card_data:
		_process_next_effect(main)
		return
	var cd: CardData = card.card_data
	var color: CardData.SupplyColor = cd.color
	var amount: int = CardData.recycle_amount(cd)
	UIAudio.play_recycle_sfx()
	main._cs_display.animate_supply_incoming(main.get_node("Camera3D").unproject_position(card.global_position), color)
	main._cs_display.add_supply(color, amount)
	main._apply_recycle_bonus(color)
	main._offer_rich_asteroid_store_for(cd, amount)
	# Only techs go back into the (tech) discard pile; an expedition just
	# leaves the game, same as Caldera Colony's sector recycling.
	if cd.card_type == CardData.CardType.TECH:
		main.get_node("Board").add_to_discard(cd)
	slot.remove_tech_card(card)
	card.queue_free()
	slot.compact_tech_cards()
	main.get_node("Board").revalidate_optimize_after_removal(slot)
	slot.refresh_display()
	main._log_effect(main.tr("recycled %s from a sector, gained %d %s") % [cd.card_name, amount, CardData.color_name(color)])
	main._broadcast_my_state()
	_process_next_effect(main)

# Earth Support: predict a color, draw 6, keep those of that color, discard
# the rest (plain discard — no supply, unlike a recycle).
static func _effect_step_earth_support(main: Main, color: CardData.SupplyColor) -> void:
	var drawn: Array[CardData] = main.get_node("Board").draw_card_data(6)
	var kept: Array[CardData] = []
	for cd: CardData in drawn:
		if cd.color == color:
			kept.append(cd)
		else:
			main.get_node("Board").add_to_discard(cd)
	if not kept.is_empty():
		main.get_node("Board").add_specific_cards_to_hand(kept)
	main._log_effect(main.tr("predicted %s, drew %d, kept %d") % [CardData.color_name(color), drawn.size(), kept.size()])
	main._show_auction_toast(main.tr("Earth Support: kept %d of %d (%s)") % [kept.size(), drawn.size(), CardData.color_name(color)])
	_process_next_effect(main)

# Wormhole Surfing: start a free auction on any biddable market card
# (top expedition or advanced sector) and pick the color it's bid in.
static func _effect_step_wormhole_surfing(main: Main) -> void:
	var pool: Array[CardData] = main.get_node("Board").get_available_expeditions()
	var adv_flags: Array[bool] = []
	for _cd: CardData in pool:
		adv_flags.append(false)
	for cd: CardData in main.get_node("Board").get_available_advanced_sectors():
		pool.append(cd)
		adv_flags.append(true)
	if pool.is_empty():
		_process_next_effect(main)
		return
	main._pending_choice_options = []
	for cd: CardData in pool:
		var shown_name: String = cd.adv_name if cd.card_type == CardData.CardType.SECTOR else cd.card_name
		var options: Array = []
		for sc: int in 6:
			var c: CardData.SupplyColor = sc as CardData.SupplyColor
			options.append({label = CardData.color_name(c), tint = CardData.color_tint(c), color = c,
				steps = [{type = "initiate_market_bid", card_data = cd, bid_color = c, _source_name = main._effect_source_name}]})
		main._pending_choice_options.append({steps = [{type = "choice",
			prompt = main.tr("Wormhole Surfing — bid on %s in which color?") % shown_name,
			options = options, _source_name = main._effect_source_name}]})
	main._effect_mode = Main.EffectMode.EFFECT_CHOICE
	main._choice_popup.show_card_choices(main.tr("Wormhole Surfing — start a bid on which card?"), pool, true, adv_flags)
