class_name BotTurn
extends RefCounted
const FleetRules = preload("res://scripts/game/fleet_rules.gd")
const FleetFlow = preload("res://scenes/main/fleet_flow.gd")

# Server-side orchestration for AI-controlled players: owns bot hand/supply/
# board state on the Main node and executes the plays BotAI decides on.
# Holds no state of its own.
#
# Bot board entries mirror the fields a real SectorSlot tracks (minus the
# Node3D/visual bits) so BotAI/BotScoring/OptimizeLogic can reuse the exact
# same rules a human player's board resolves against:
#   {sector, is_advanced, techs, stored_supply, tucked_cards,
#    optimize_count, max_optimizations, triggered_levels,
#    last_placed_tech_cost, is_optimized}
# "techs" holds both Tech cards (placed from hand) and Expedition cards (won
# via auction) — the real game attaches both to the same 5-card slot stack.

static func init_bot_state(main: Main) -> void:
	for bot_id: int in GameNetwork.bot_ids:
		var supply: Dictionary = {
			int(CardData.SupplyColor.DUST):     4,
			int(CardData.SupplyColor.METALS):   2,
			int(CardData.SupplyColor.LIQUIDS):  2,
			int(CardData.SupplyColor.ORGANIX):  1,
			int(CardData.SupplyColor.ELECTRIX): 1,
			int(CardData.SupplyColor.THRUST):   0,
		}
		main.bot_supplies[bot_id] = supply
		main.bot_hands[bot_id] = main.get_node("Board").draw_card_data(6)
		main.bot_boards[bot_id] = []

static func update_bots_for_new_round(main: Main) -> void:
	for bot_id: int in GameNetwork.bot_ids:
		# draw 6 more and keep the hand: there is no hand maximum (rule book p4; the bots threw
		# their whole hand away every Generation)
		var hand: Array[CardData] = bot_hand(main, bot_id)
		hand.append_array(main.get_node("Board").draw_card_data(6))
		bot_set_hand(main, bot_id, hand)
		# the last Generation's income, as for the humans (Main._apply_supply_generation): 1 supply
		# per card on the ship in its colour (the sector by its visible side), not +1 of every colour
		var supply: Dictionary = main.bot_supplies.get(bot_id, {})
		for slot_v: Variant in (main.bot_boards.get(bot_id, []) as Array):
			for color: int in BotScoring.slot_effective_placed_colors(slot_v as Dictionary):
				if FleetRules.blocks_income(color):   # Fleet Dangers
					continue
				supply[color] = int(supply.get(color, 0)) + 1
		main.bot_supplies[bot_id] = supply

static func get_bot_snapshot(main: Main, bot_id: int) -> Dictionary:
	var hand_arr: Array = main.bot_hands.get(bot_id, []) as Array
	var board: Array = main.bot_boards.get(bot_id, []) as Array
	var slot_snaps: Array = []
	for entry_v: Variant in board:
		var entry: Dictionary = entry_v as Dictionary
		var sector: CardData = entry.get("sector") as CardData
		if sector == null:
			continue
		var is_adv: bool = bool(entry.get("is_advanced", false))
		var techs: Array = entry.get("techs", []) as Array
		var tech_names: Array[String] = []
		for t: Variant in techs:
			if t is CardData:   # (a Fleet-destroyed card is a marker: no name, no expedition)
				tech_names.append((t as CardData).card_name)
		var stored_supply: Dictionary = entry.get("stored_supply", {}) as Dictionary
		var stored_snap: Dictionary = {}
		for color: int in stored_supply:
			stored_snap[int(color)] = stored_supply[color]
		var tucked_cards: Array = entry.get("tucked_cards", []) as Array
		var tucked_snap: Array = []
		for tuck_v: Variant in tucked_cards:
			var tuck: Dictionary = tuck_v as Dictionary
			var face_up: bool = bool(tuck.get("face_up", false))
			var tuck_cd: CardData = tuck.get("data") as CardData
			tucked_snap.append({
				"face_up": face_up,
				"name": tuck_cd.card_name if (face_up and tuck_cd) else "",
			})
		slot_snaps.append({
			"occupied": true,
			"optimize_count": int(entry.get("optimize_count", 0)),
			"max_optimizations": int(entry.get("max_optimizations", 0)),
			"is_optimized": bool(entry.get("is_optimized", false)),
			"tech_count": techs.size(),
			"sector_name": sector.adv_name if (is_adv and not sector.adv_name.is_empty()) else sector.card_name,
			"sector_advanced": is_adv,
			"tech_names": tech_names,
			"stored_supply": stored_snap,
			"tucked_cards": tucked_snap,
			"position": {"x": 0.0, "z": 0.0},
		})
	Scoring.other_players_expeditions = main._alliance_count_for(bot_id)
	return {
		"peer_id": bot_id,
		"supply": main.bot_supplies.get(bot_id, {}),
		"hand_size": hand_arr.size(),
		"vp": BotScoring.board_vp(board),
		"vp_lines": BotScoring.board_vp_lines(board),
		"slots": slot_snaps,
		"fleet": FleetFlow.bot_stats(main, bot_id) if GameNetwork.fleet_mode else {},
	}

static func run_bot_turn(main: Main, bot_id: int) -> void:
	await main.get_tree().create_timer(1.0 + randf() * 0.5).timeout
	if GameNetwork.active_peer_id != bot_id:
		return
	if main._bots_passed_this_round.has(bot_id):
		main._server_handle_end_turn()
		return
	var difficulty: int = GameNetwork.bot_difficulty.get(bot_id, BotAI.Difficulty.EASY)
	var market_sectors: Array[CardData] = main.get_node("Board").get_available_dust_sectors()
	var market_expeditions: Array[CardData] = main.get_node("Board").get_available_expeditions()
	# Generation Fleet: advanced sectors are bought at their printed cost, like expeditions
	var market_adv: Array[CardData] = []
	if GameNetwork.fleet_mode:
		market_adv = main.get_node("Board").get_available_advanced_sectors()
	var board: Array = main.bot_boards.get(bot_id, []) as Array
	var supplies: Dictionary = main.bot_supplies.get(bot_id, {}) as Dictionary
	var hand: Array[CardData] = bot_hand(main, bot_id)

	# Free actions first: fuse toward the best play, then (Hard only) recycle
	# a dead hand card if that's what's actually blocking a play.
	for f: Dictionary in BotAI.suggest_fuses(difficulty, hand, supplies, board, market_sectors):
		bot_fuse(main, bot_id, int(f["source"]), int(f["target"]))

	var action: Dictionary = BotAI.decide_action(difficulty, hand, supplies, board, main._round, market_sectors, market_expeditions, market_adv)
	if String(action.get("type", "pass")) in ["pass", "research"]:
		var recycle_card: CardData = BotAI.suggest_recycle(difficulty, hand, supplies, board, market_sectors)
		if recycle_card:
			bot_recycle(main, bot_id, recycle_card)
			hand = bot_hand(main, bot_id)
			action = BotAI.decide_action(difficulty, hand, supplies, board, main._round, market_sectors, market_expeditions, market_adv)

	match String(action.get("type", "pass")):
		"buy_sector":
			bot_buy_sector(main, bot_id, action["card"] as CardData)
			broadcast_bot_states(main)
			await main.get_tree().create_timer(0.5).timeout
			main._server_handle_end_turn()
		"buy_adv_sector":
			bot_buy_adv_sector_fleet(main, bot_id, action["card"] as CardData)
			broadcast_bot_states(main)
			await main.get_tree().create_timer(0.5).timeout
			main._server_handle_end_turn()
		"place_tech":
			bot_place_tech(main, bot_id, action["card"] as CardData, action["slot_idx"] as int)
			broadcast_bot_states(main)
			await main.get_tree().create_timer(0.5).timeout
			main._server_handle_end_turn()
		"start_auction":
			if GameNetwork.fleet_mode:   # Fleet: expeditions at printed cost, no auction
				bot_buy_expedition_fleet(main, bot_id, action["card"] as CardData)
				broadcast_bot_states(main)
				await main.get_tree().create_timer(0.5).timeout
				main._server_handle_end_turn()
				return
			bot_start_auction(main, bot_id, action["card"] as CardData)
			broadcast_bot_states(main)
			# No end_turn call here — the auction (and whoever wins it) still
			# has to resolve, which can take real time and other players'
			# input. Main._rpc_sync_auction_placement_pending ends this bot's
			# turn once that fully settles, mirroring how a human initiator's
			# turn stays open until their auction is done.
		"research":
			bot_do_research(main, bot_id, action.get("card") as CardData)   # Hard: its smart pick
			broadcast_bot_states(main)
			# like a human's research: everyone logs it and sees the "is researching" banner
			main._rpc_sync_opp_status.rpc(bot_id, "researching")
			await main.get_tree().create_timer(0.3).timeout
			bot_pass(main, bot_id)
		_:
			bot_pass(main, bot_id)


static func bot_hand(main: Main, bot_id: int) -> Array[CardData]:
	var result: Array[CardData] = []
	for item: Variant in (main.bot_hands.get(bot_id, []) as Array):
		if item is CardData:
			result.append(item as CardData)
	return result

static func bot_set_hand(main: Main, bot_id: int, hand: Array[CardData]) -> void:
	main.bot_hands[bot_id] = hand


static func _new_slot_entry(cd: CardData, is_advanced: bool) -> Dictionary:
	var max_opt: int = OptimizeLogic.max_optimizations(cd, is_advanced)
	var triggered: Array[bool] = []
	triggered.resize(max_opt)
	triggered.fill(false)
	return {
		"sector": cd, "is_advanced": is_advanced, "techs": [],
		"stored_supply": {}, "tucked_cards": [],
		"optimize_count": 0, "max_optimizations": max_opt,
		"triggered_levels": triggered, "last_placed_tech_cost": 0,
		"is_optimized": false,
	}

static func bot_buy_sector(main: Main, bot_id: int, card_data: CardData) -> void:
	var cost: int = max(0, card_data.cost) + FleetRules.cost_increase(card_data)
	BotAI.pay_supplies(main.bot_supplies[bot_id] as Dictionary, int(card_data.color), cost)
	# off every market, not only the host's (online players could buy the same card)
	if GameNetwork.is_multiplayer:
		main._rpc_sync_market_removal.rpc(CardRef.to_ref(card_data))
	else:
		main.get_node("Board").get_market().remove_card(card_data)
	main.bot_boards[bot_id].append(_new_slot_entry(card_data, false))
	_bot_sector_placed(main, bot_id, card_data, false)
	var _bname: String = GameNetwork.player_names.get(bot_id, main.tr("Bot"))
	main._broadcast_log(main.tr("%s: bought %s") % [_bname, card_data.card_name], CardData.color_tint(card_data.color))

## Generation Fleet: an advanced sector from the market at its printed cost (no auction), as the humans.
static func bot_buy_adv_sector_fleet(main: Main, bot_id: int, card_data: CardData) -> void:
	var cost: int = maxi(0, card_data.adv_cost) + FleetRules.cost_increase(card_data, true)
	BotAI.pay_supplies(main.bot_supplies[bot_id] as Dictionary, int(card_data.adv_color), cost)
	if GameNetwork.is_multiplayer:
		main._rpc_sync_market_removal.rpc(CardRef.to_ref(card_data))
	else:
		main.get_node("Board").remove_market_card(card_data)
	main.bot_boards[bot_id].append(_new_slot_entry(card_data, true))
	_bot_sector_placed(main, bot_id, card_data, true)
	var _bname: String = GameNetwork.player_names.get(bot_id, main.tr("Bot"))
	main._broadcast_log(main.tr("%s: bought %s") % [_bname, card_data.adv_name], CardData.color_tint(card_data.adv_color))

# A new sector on a bot's ship (the last entry): the Always effects that react to it (Biodomes for
# a Liquids side, Einstein-Rosen Portal for a starred side), as Main._on_card_placed for a sector.
static func _bot_sector_placed(main: Main, bot_id: int, card_data: CardData, is_adv: bool) -> void:
	if FleetRules.always_effects_off():   # Fleet: Totalitarianism
		return
	var idx: int = (main.bot_boards[bot_id] as Array).size() - 1
	apply_bot_effect_steps(main, bot_id, AlwaysEffects.get_bot_steps(main.bot_boards[bot_id] as Array, idx, card_data, is_adv), idx)


static func bot_place_tech(main: Main, bot_id: int, card_data: CardData, slot_idx: int) -> void:
	var hand: Array[CardData] = bot_hand(main, bot_id)
	hand.erase(card_data)
	bot_set_hand(main, bot_id, hand)
	# the bot's own discounts (Academies, Skyhook, Seasons on top of this sector…), before the card goes on top
	var cost: int = BotAI.tech_cost(card_data, main.bot_boards.get(bot_id, []) as Array, slot_idx)
	BotAI.pay_supplies(main.bot_supplies[bot_id] as Dictionary, int(card_data.color), cost)
	_attach_stack_card(main, bot_id, slot_idx, card_data)
	var _bname: String = GameNetwork.player_names.get(bot_id, main.tr("Bot"))
	main._broadcast_log(main.tr("%s: placed %s") % [_bname, card_data.card_name], CardData.color_tint(card_data.color))


# Attaches a Tech or Expedition card to a slot's 5-card stack, resolves its
# PlaceEffects "on placed" effect, then recomputes optimize state and
# resolves SectorEffects for any newly-triggered level — mirrors
# board.gd's accept_tech_card + _update_optimize_state + main.gd's
# _on_optimize_triggered, against the bot's lightweight board dict instead
# of a live SectorSlot.
static func _attach_stack_card(main: Main, bot_id: int, slot_idx: int, card_data: CardData) -> void:
	var slot: Dictionary = main.bot_boards[bot_id][slot_idx] as Dictionary
	(slot["techs"] as Array).append(card_data)
	if card_data.card_type == CardData.CardType.TECH:
		slot["last_placed_tech_cost"] = card_data.cost

	# the optimize state first, as Board._finalize_placement does for humans: "if fully
	# optimized" includes the card that fully optimizes the sector (rule book p15)
	var sector: CardData = slot.get("sector") as CardData
	var triggered: Array = []
	var is_adv: bool = bool(slot.get("is_advanced", false))
	var effective_colors: Array[int] = BotScoring.slot_effective_placed_colors(slot)
	if sector != null:
		# tanks are filled by the cards placed ON the sector only, never by the sector card itself;
		# Karma Chameleon sits its own placement's check out (its Place effect picks its colour)
		var tanks: Array[int] = _bot_tanks_without_karma(slot) if card_data.card_name == KARMA else BotScoring.slot_tech_colors(slot)
		triggered = _bot_update_optimize(slot, tanks)

	# what Main._on_card_placed queues, in its order: the Always effects reacting to this card, its own
	# Place effect, then the optimize effect it triggered — each list built from this moment's state
	var always_steps: Array[Dictionary] = []
	if not FleetRules.always_effects_off():   # Fleet: Totalitarianism
		always_steps = AlwaysEffects.get_bot_steps(main.bot_boards[bot_id] as Array, slot_idx, card_data, false)
	var place_steps: Array[Dictionary] = PlaceEffects.get_steps_for_state(
		card_data, BotScoring.is_slot_new(slot), BotScoring.is_slot_complete(slot),
		BotScoring.is_slot_optimized(slot), effective_colors)
	var opt_steps: Array[Dictionary] = []
	if sector != null and not triggered.is_empty():
		opt_steps = SectorEffects.get_optimize_steps_for_state(
			sector, is_adv, effective_colors, int(slot.get("last_placed_tech_cost", 0)))
	# Fleet: free solves met by this placement go before its effects (as for the humans)
	FleetFlow.bot_auto_solve(main)
	apply_bot_effect_steps(main, bot_id, always_steps, slot_idx)
	apply_bot_effect_steps(main, bot_id, place_steps, slot_idx)
	# Mirrors main.gd:_on_optimize_triggered firing once per triggered level.
	for _lvl: int in triggered.size():
		apply_bot_effect_steps(main, bot_id, opt_steps, slot_idx)

const KARMA: String = "Karma Chameleon"

# The new optimize state of a bot's sector for these tank colours, as Board._update_optimize_state
# (Fleet Infestation: nothing changes on a sector with an Organix card). Returns the levels it triggered.
static func _bot_update_optimize(slot: Dictionary, tanks: Array[int]) -> Array:
	var sector: CardData = slot.get("sector") as CardData
	if sector == null or BotAI.infested(sector, bool(slot.get("is_advanced", false)), tanks):
		return []
	var levels: Array[bool] = []
	levels.assign(slot.get("triggered_levels", []) as Array)
	var result: Dictionary = OptimizeLogic.update_optimize_state(
		sector, bool(slot.get("is_advanced", false)), tanks,
		int(slot.get("optimize_count", 0)), int(slot.get("max_optimizations", 0)), levels)
	slot["optimize_count"] = result["optimize_count"]
	slot["is_optimized"] = result["is_optimized"]
	slot["triggered_levels"] = result["triggered_levels"]
	return result["triggered"] as Array

# After a card left a bot's sector or lost its colour (Fleet destroy, Ice 9, Karma Chameleon): re-check
# its levels (one whose colours are gone can be earned again) and fire any level that newly triggers,
# as Board.revalidate_optimize_after_removal.
static func _bot_revalidate_optimize(main: Main, bot_id: int, slot_idx: int) -> void:
	var board: Array = main.bot_boards.get(bot_id, []) as Array
	if slot_idx < 0 or slot_idx >= board.size():
		return
	var slot: Dictionary = board[slot_idx] as Dictionary
	var triggered: Array = _bot_update_optimize(slot, BotScoring.slot_tech_colors(slot))
	if triggered.is_empty():
		return
	var opt_steps: Array[Dictionary] = SectorEffects.get_optimize_steps_for_state(
		slot.get("sector") as CardData, bool(slot.get("is_advanced", false)),
		BotScoring.slot_effective_placed_colors(slot), int(slot.get("last_placed_tech_cost", 0)))
	for _lvl: int in triggered.size():
		apply_bot_effect_steps(main, bot_id, opt_steps, slot_idx)

# Tank colours of a bot's sector without its (topmost) Karma Chameleon.
static func _bot_tanks_without_karma(slot: Dictionary) -> Array[int]:
	var techs: Array = slot.get("techs", []) as Array
	var skip: int = _karma_index(techs)
	var result: Array[int] = []
	for i: int in techs.size():
		if i != skip and techs[i] is CardData:
			result.append(int((techs[i] as CardData).color))
	return result

static func _karma_index(techs: Array) -> int:
	for i: int in range(techs.size() - 1, -1, -1):
		if techs[i] is CardData and (techs[i] as CardData).card_name == KARMA:
			return i
	return -1


# pick: the card BotAI chose to research away (Hard's smart pick); else the cheapest one
static func bot_do_research(main: Main, bot_id: int, pick: CardData = null) -> void:
	var hand: Array[CardData] = bot_hand(main, bot_id)
	if hand.is_empty():
		return
	if pick != null and hand.has(pick):
		hand.erase(pick)
		main.get_node("Board").add_to_discard(pick)
	else:
		hand.sort_custom(func(a: CardData, b: CardData) -> bool: return a.cost < b.cost)
		main.get_node("Board").add_to_discard(hand.pop_front())
	hand.append_array(main.get_node("Board").draw_card_data(1))
	bot_set_hand(main, bot_id, hand)


static func bot_pass(main: Main, bot_id: int) -> void:
	main._bots_passed_this_round.append(bot_id)
	main._server_handle_pass()


static func bot_fuse(main: Main, bot_id: int, source: int, target: int) -> void:
	if FleetRules.blocks_fuse(source) or FleetRules.blocks_fuse(target):   # Fleet Dangers (as SupplyUI._fuse)
		return
	main.bot_supplies[bot_id][source] = max(0, (main.bot_supplies[bot_id].get(source, 0) as int) - 2)
	main.bot_supplies[bot_id][target] = (main.bot_supplies[bot_id].get(target, 0) as int) + 1
	var _bname: String = GameNetwork.player_names.get(bot_id, main.tr("Bot"))
	main._broadcast_log(
		main.tr("%s: fused %s → %s") % [_bname, CardData.color_name(source as CardData.SupplyColor), CardData.color_name(target as CardData.SupplyColor)],
		Color(0.7, 0.85, 1.0))


static func bot_recycle(main: Main, bot_id: int, card: CardData) -> void:
	if FleetRules.blocks_recycle(int(card.color)):   # Fleet: Pandemic / Barbarism
		return
	var hand: Array[CardData] = bot_hand(main, bot_id)
	hand.erase(card)
	bot_set_hand(main, bot_id, hand)
	_bot_gain_recycle(main, bot_id, card)
	main.get_node("Board").add_to_discard(card)
	var _bname: String = GameNetwork.player_names.get(bot_id, main.tr("Bot"))
	main._broadcast_log(main.tr("%s: recycled %s") % [_bname, card.card_name], CardData.color_tint(card.color))


static func broadcast_bot_states(main: Main) -> void:
	for bot_id: int in GameNetwork.bot_ids:
		var bot_state: Dictionary = get_bot_snapshot(main, bot_id)
		main._apply_opponent_state(bot_state)
		for peer_id: int in GameNetwork.player_order:
			if peer_id != 1 and not GameNetwork.is_bot(peer_id):
				main._rpc_recv_board_state.rpc_id(peer_id, bot_state)


# Resolves the subset of effect steps that are pure resource/hand/slot
# mutations (draw, gain/store supply, tuck, recycle). Auction/market- and
# UI-flow-integrated step types (reveal_*, offer_bid_*, cargo_drones,
# black_hole_encounter, seedbanks, reflectors_choice, recycle_tuck*,
# caldera_colony, fuse_dust_1to1, fuse_notice's 1:1 token, ...) are
# intentionally left as a no-op for bots — wiring those into the live
# auction/UI flow is a separate, much larger effort. slot_idx is the board
# slot the triggering card belongs to (-1 if none), used by the slot-scoped
# step types.
#
# interfleet_comms is a deliberate simplification, not the real card: a
# human's Interfleet Comms draws 1/player then runs a synced pass-left pick
# among the pool. Wiring bots into that live draft is scoped out along with
# the rest of the UI-flow types above, so a bot placing it just resolves as
# draw_all_players(1) — everyone (including the bot) draws 1 straight from
# their own deck, no passing.
static var _bot_last_drawn: Array[CardData] = []   # the last "draw" (for "…1 of them" steps)

static func apply_bot_effect_steps(main: Main, bot_id: int, steps: Array[Dictionary], slot_idx: int = -1) -> void:
	for step: Dictionary in steps:
		FleetFlow.bot_auto_solve(main)   # a free solve met by an earlier step counts before this one
		if FleetFlow.step_blocked(step):   # Fleet: archiving/storing forbidden by a Danger
			continue
		match String(step.get("type", "")):
			"draw":
				var hand: Array[CardData] = bot_hand(main, bot_id)
				var drawn: Array[CardData] = main.get_node("Board").draw_card_data(int(step.get("count", 1)))
				_bot_last_drawn = drawn.duplicate()
				hand.append_array(drawn)
				bot_set_hand(main, bot_id, hand)
			"draw_recycle_top":
				# Passing Comet "Draw 1, then recycle it": the supply, not a hand card (Board.draw_and_recycle_top)
				for cd: CardData in main.get_node("Board").draw_card_data(1):
					if FleetRules.blocks_recycle(int(cd.color)):   # Fleet: it stays in hand then
						var keep: Array[CardData] = bot_hand(main, bot_id)
						keep.append(cd)
						bot_set_hand(main, bot_id, keep)
					else:
						main.get_node("Board").add_to_discard(cd)
						_bot_gain_recycle(main, bot_id, cd)
			"draw_all_players", "interfleet_comms":
				# Unlike a plain "draw", this must also reach every real peer
				# and every other bot (see main.gd:_effect_step_draw_all_players
				# for the human-initiated counterpart) — a bare local draw here
				# would silently skip everyone but the bot that placed the card.
				# interfleet_comms collapses to a 1-card draw_all_players here;
				# see the comment on this function for why.
				var count: int = 1 if step.get("type") == "interfleet_comms" else int(step.get("count", 1))
				var source: String = str(step.get("_source_name", "Effect"))
				main._server_handle_draw_all_players(count, bot_id, source)
			"gain_supply":
				_bot_gain(main, bot_id, int(step.get("color", 0)), int(step.get("amount", 1)))
			"gain_supply_per_stored":
				if slot_idx >= 0 and slot_idx < main.bot_boards[bot_id].size():
					var slot: Dictionary = main.bot_boards[bot_id][slot_idx] as Dictionary
					var amt: int = BotScoring.slot_total_stored(slot) * int(step.get("multiplier", 1))
					_bot_gain(main, bot_id, int(step.get("color", 0)), amt)
			"gain_supply_per_sector_count":
				var board: Array = main.bot_boards.get(bot_id, []) as Array
				_bot_gain(main, bot_id, int(step.get("color", 0)), board.size())
			"store_on_slot":
				_bot_store(main, bot_id, slot_idx, int(step.get("color", 0)), int(step.get("amount", 1)))
			"store_on_any_sector":
				_bot_store(main, bot_id, _bot_any_slot(main, bot_id), int(step.get("color", 0)), int(step.get("amount", 1)))
			"store_per_card_here":
				if slot_idx >= 0 and slot_idx < main.bot_boards[bot_id].size():
					for color: int in BotScoring.slot_effective_placed_colors(main.bot_boards[bot_id][slot_idx] as Dictionary):
						_bot_store(main, bot_id, slot_idx, color, 1)
			"tuck":
				_bot_tuck(main, bot_id, slot_idx, int(step.get("count", 1)), bool(step.get("face_up", false)),
						false, bool(step.get("restrict_to_drawn", false)))
			"tuck_optional":
				# "Archive up to N …, then draw that many" (unless the step already drew: no_bonus_draw / "of them")
				var restrict_t: bool = bool(step.get("restrict_to_drawn", false))
				var tucked_n: int = _bot_tuck(main, bot_id, slot_idx, int(step.get("max", 1)), bool(step.get("face_up", false)),
						true, restrict_t)
				if tucked_n > 0 and not restrict_t and not bool(step.get("no_bonus_draw", false)):
					_bot_draw(main, bot_id, tucked_n)
			"tuck_any_sector_optional":
				_bot_tuck(main, bot_id, _bot_any_slot(main, bot_id), int(step.get("max", 1)), bool(step.get("face_up", false)), true)
			"recycle":
				_bot_recycle_n(main, bot_id, int(step.get("count", 1)), 1, bool(step.get("restrict_to_drawn", false)))
			"recycle_optional":
				# "Recycle up to N, then draw that many"
				var recycled_n: int = _bot_recycle_n(main, bot_id, int(step.get("max", 1)), 1, bool(step.get("restrict_to_drawn", false)))
				_bot_draw(main, bot_id, recycled_n)
			"recycle_double":   # Cleaning Robot: "Recycle 1 but gain the supply twice."
				_bot_recycle_n(main, bot_id, int(step.get("count", 1)), 2, bool(step.get("restrict_to_drawn", false)))
			"recycle_from_own_sector":   # Ice 9
				_bot_ice9(main, bot_id)
			"earth_support":
				_bot_earth_support(main, bot_id, int(step.get("color", 0)))
			"placing_color":   # Karma Chameleon's chosen colour
				_bot_karma_resolve(main, bot_id, slot_idx, int(step.get("color", 0)))
			"choice":
				var opts: Array = step.get("options", []) as Array
				if not opts.is_empty():
					var pick: int = _bot_pick_option(main, bot_id, slot_idx, opts)
					apply_bot_effect_steps(main, bot_id, BotScoring.to_dict_array((opts[pick] as Dictionary).get("steps", []) as Array), slot_idx)
			_:
				pass

static func _bot_draw(main: Main, bot_id: int, count: int) -> void:
	if count <= 0:
		return
	var hand: Array[CardData] = bot_hand(main, bot_id)
	hand.append_array(main.get_node("Board").draw_card_data(count))
	bot_set_hand(main, bot_id, hand)

## A supply a bot gains: none under a Danger that blocks that colour's gains (as SupplyUI.add_supply).
static func _bot_gain(main: Main, bot_id: int, color: int, amount: int) -> void:
	if amount <= 0 or FleetRules.blocks_gain(color):
		return
	main.bot_supplies[bot_id][color] = int(main.bot_supplies[bot_id].get(color, 0)) + amount

## A recycled card's supply (x mult: Cleaning Robot) plus Trash Compactor's +1 Dust per copy on the
## bot's ship (Main._apply_recycle_bonus).
static func _bot_gain_recycle(main: Main, bot_id: int, cd: CardData, mult: int = 1) -> void:
	var color: int = int(cd.color)
	_bot_gain(main, bot_id, color, mult * CardData.recycle_amount(cd))
	if color == CardData.SupplyColor.DUST and not FleetRules.always_effects_off():
		_bot_gain(main, bot_id, color, _bot_count_card(main, bot_id, "Trash Compactor"))

# Live copies of a card on a bot's ship (a destroyed one has no effect).
static func _bot_count_card(main: Main, bot_id: int, card_name: String) -> int:
	var n: int = 0
	for entry: Variant in (main.bot_boards.get(bot_id, []) as Array):
		for t: Variant in ((entry as Dictionary).get("techs", []) as Array):
			if t is CardData and (t as CardData).card_name == card_name:
				n += 1
	return n

# The option a bot takes in a "choice" step: Karma Chameleon the colour that optimizes, Earth Support
# the most common tech colour, an archive's face up only for a card worth 2+ ⭐ (face down is 1);
# anything else the first option.
static func _bot_pick_option(main: Main, bot_id: int, slot_idx: int, opts: Array) -> int:
	var first: Array = (opts[0] as Dictionary).get("steps", []) as Array
	var kind: String = str((first[0] as Dictionary).get("type", "")) if not first.is_empty() else ""
	match kind:
		"placing_color":
			return _bot_karma_pick(main, bot_id, slot_idx, opts)
		"earth_support":
			var counts: Dictionary = {}
			for cd: CardData in CardDatabase.techs:
				counts[int(cd.color)] = int(counts.get(int(cd.color), 0)) + 1
			var best: int = 0
			for i: int in opts.size():
				var col: int = int((opts[i] as Dictionary).get("color", -1))
				if int(counts.get(col, 0)) > int(counts.get(int((opts[best] as Dictionary).get("color", -1)), 0)):
					best = i
			return best
		"tuck", "tuck_optional", "tuck_any_sector_optional":
			# the archive worth the most: face down 1 ⭐ a card, face up the cards' printed stars
			var stars: Array[int] = []
			for cd: CardData in bot_hand(main, bot_id):
				stars.append(cd.stars)
			stars.sort()
			stars.reverse()
			var best: int = 0
			var best_vp: int = -1
			for i: int in opts.size():
				var st: Array = (opts[i] as Dictionary).get("steps", []) as Array
				if st.is_empty():
					continue
				var s: Dictionary = st[0] as Dictionary
				var n: int = mini(int(s.get("count", s.get("max", 1))), stars.size())
				var vp: int = n
				if bool(s.get("face_up", false)):
					vp = 0
					for k: int in n:
						vp += stars[k]
				if vp > best_vp:
					best_vp = vp
					best = i
			return best
	return 0

# Karma Chameleon: the first colour that newly fills an optimize level of its sector, else the first.
static func _bot_karma_pick(main: Main, bot_id: int, slot_idx: int, opts: Array) -> int:
	var board: Array = main.bot_boards.get(bot_id, []) as Array
	if slot_idx < 0 or slot_idx >= board.size():
		return 0
	var slot: Dictionary = board[slot_idx] as Dictionary
	var sector: CardData = slot.get("sector") as CardData
	if sector == null:
		return 0
	var count: int = int(slot.get("optimize_count", 0))
	for i: int in opts.size():
		var col: int = int((opts[i] as Dictionary).get("color", -1))
		if col < 0:
			continue
		var pool: Array[int] = _bot_tanks_without_karma(slot)
		pool.append(col)
		if BotAI.infested(sector, bool(slot.get("is_advanced", false)), pool):
			continue
		var levels: Array[bool] = []
		levels.assign(slot.get("triggered_levels", []) as Array)
		var result: Dictionary = OptimizeLogic.update_optimize_state(sector, bool(slot.get("is_advanced", false)),
				pool, count, int(slot.get("max_optimizations", 0)), levels)
		if int(result["optimize_count"]) > count:
			return i
	return 0

# Karma Chameleon "Counts as any color when placed. Then discard it.": the optimize check with the
# chosen colour, then it leaves the sector (the level it filled can be earned again), as
# EffectSteps._effect_step_placing_color + Board.discard_karma_chameleon.
static func _bot_karma_resolve(main: Main, bot_id: int, slot_idx: int, color: int) -> void:
	var board: Array = main.bot_boards.get(bot_id, []) as Array
	if slot_idx < 0 or slot_idx >= board.size():
		return
	var slot: Dictionary = board[slot_idx] as Dictionary
	var techs: Array = slot.get("techs", []) as Array
	var k: int = _karma_index(techs)
	if k < 0:
		return
	var pool: Array[int] = _bot_tanks_without_karma(slot)
	pool.append(color)
	var triggered: Array = _bot_update_optimize(slot, pool)
	var opt_steps: Array[Dictionary] = []
	if not triggered.is_empty():
		opt_steps = SectorEffects.get_optimize_steps_for_state(slot.get("sector") as CardData,
				bool(slot.get("is_advanced", false)), BotScoring.slot_effective_placed_colors(slot),
				int(slot.get("last_placed_tech_cost", 0)))
	var karma: CardData = techs[k] as CardData
	techs.remove_at(k)
	main.get_node("Board").add_to_discard(karma)
	_bot_revalidate_optimize(main, bot_id, slot_idx)
	for _lvl: int in triggered.size():
		apply_bot_effect_steps(main, bot_id, opt_steps, slot_idx)

# Ice 9 "Recycle a card on any of your sectors.": the bot's least valuable card on a sector (not
# Ice 9 itself), as EffectSteps._effect_step_recycle_sector_card.
static func _bot_ice9(main: Main, bot_id: int) -> void:
	var board: Array = main.bot_boards.get(bot_id, []) as Array
	var best_slot: int = -1
	var best_idx: int = -1
	var best_value: float = INF
	for i: int in board.size():
		var techs: Array = (board[i] as Dictionary).get("techs", []) as Array
		for j: int in techs.size():
			if not (techs[j] is CardData):
				continue
			var cd: CardData = techs[j] as CardData
			if cd.card_name == "Ice 9" or FleetRules.blocks_recycle(int(cd.color)):
				continue
			if BotScoring.card_value(cd) < best_value:
				best_value = BotScoring.card_value(cd)
				best_slot = i
				best_idx = j
	if best_slot < 0:
		return
	var stack: Array = (board[best_slot] as Dictionary)["techs"] as Array
	var gone: CardData = stack[best_idx] as CardData
	stack.remove_at(best_idx)
	_bot_gain_recycle(main, bot_id, gone)
	main.get_node("Board").add_to_discard(gone)   # (only techs go back; an expedition leaves the game)
	_bot_revalidate_optimize(main, bot_id, best_slot)

# Earth Support "Predict a color, draw 6, keep any of that color, discard the rest."
static func _bot_earth_support(main: Main, bot_id: int, color: int) -> void:
	var hand: Array[CardData] = bot_hand(main, bot_id)
	for cd: CardData in main.get_node("Board").draw_card_data(6):
		if int(cd.color) == color:
			hand.append(cd)
		else:
			main.get_node("Board").add_to_discard(cd)
	bot_set_hand(main, bot_id, hand)


static func _bot_store(main: Main, bot_id: int, slot_idx: int, color: int, amount: int) -> void:
	if slot_idx < 0 or slot_idx >= main.bot_boards[bot_id].size():
		return
	if amount > 0 and FleetRules.blocks_store(color):   # Fleet: Neural Gear / Anti-Fusion Field (as SectorSlot)
		return
	var slot: Dictionary = main.bot_boards[bot_id][slot_idx] as Dictionary
	var stored: Dictionary = slot.get("stored_supply", {}) as Dictionary
	stored[color] = (stored.get(color, 0) as int) + amount
	slot["stored_supply"] = stored

static func _bot_any_slot(main: Main, bot_id: int) -> int:
	var board: Array = main.bot_boards.get(bot_id, []) as Array
	return 0 if not board.is_empty() else -1

# Archives up to count hand cards under bot slot slot_idx; returns how many. Face down: the least
# valuable cards. Face up an archived card scores its printed stars: the most starred ones (an
# optional face-up archive skips 0-star cards). restrict: only cards the last "draw" brought.
static func _bot_tuck(main: Main, bot_id: int, slot_idx: int, count: int, face_up: bool,
		optional: bool = false, restrict: bool = false) -> int:
	if slot_idx < 0 or slot_idx >= main.bot_boards[bot_id].size():
		return 0
	var hand: Array[CardData] = bot_hand(main, bot_id)
	var pool: Array[CardData] = []
	for cd: CardData in hand:
		if restrict and not _bot_last_drawn.has(cd):
			continue
		if face_up and optional and cd.stars <= 0:
			continue
		pool.append(cd)
	if face_up:
		pool.sort_custom(func(a: CardData, b: CardData) -> bool: return a.stars > b.stars)
	else:
		pool.sort_custom(func(a: CardData, b: CardData) -> bool: return BotScoring.card_value(a) < BotScoring.card_value(b))
	var slot: Dictionary = main.bot_boards[bot_id][slot_idx] as Dictionary
	var tucked: Array = slot.get("tucked_cards", []) as Array
	var n: int = mini(count, pool.size())
	for i: int in n:
		hand.erase(pool[i])
		tucked.append({"data": pool[i], "face_up": face_up})
	slot["tucked_cards"] = tucked
	bot_set_hand(main, bot_id, hand)
	return n

# Recycles up to count of the bot's least valuable hand cards (mult x the supply); returns how many.
# Fleet: cards a Danger forbids recycling stay. restrict: only cards the last "draw" brought.
static func _bot_recycle_n(main: Main, bot_id: int, count: int, mult: int = 1, restrict: bool = false) -> int:
	var hand: Array[CardData] = bot_hand(main, bot_id)
	var pool: Array[CardData] = []
	for cd: CardData in hand:
		if FleetRules.blocks_recycle(int(cd.color)) or (restrict and not _bot_last_drawn.has(cd)):
			continue
		pool.append(cd)
	pool.sort_custom(func(a: CardData, b: CardData) -> bool: return BotScoring.card_value(a) < BotScoring.card_value(b))
	var n: int = mini(count, pool.size())
	for i: int in n:
		hand.erase(pool[i])
		_bot_gain_recycle(main, bot_id, pool[i], mult)
		main.get_node("Board").add_to_discard(pool[i])
	bot_set_hand(main, bot_id, hand)
	return n


# Mirrors the human flow (Board._start_bid -> Main._on_bid_required ->
# Main._on_bid_confirmed -> Main._server_start_auction), skipping the bid-
# popup confirmation step entirely since a bot has no UI to confirm through —
# it opens straight at the card's printed cost. slot_idx is passed as -1:
# it's only meaningful for advanced-sector auctions (a new board slot), and
# is unused (an underscore-prefixed parameter) on the expedition/is_tech path
# this is exclusively used for — the winner's own bot_resolve_auction_win /
# human placement picks the destination slot independently.
static func bot_start_auction(main: Main, bot_id: int, card_data: CardData) -> void:
	var board_node: Node = main.get_node("Board")
	board_node.get_expedition_market().remove_card(card_data)
	board_node.set_major_action_taken()
	var card_ref: Dictionary = CardRef.to_ref(card_data)
	# (logged once, for every peer, by _rpc_sync_auction_started as a human's auction)
	main._server_start_auction(card_ref, -1, true, false, card_data.cost, int(card_data.color), bot_id)


static func bot_decide_bid(main: Main, bot_id: int) -> void:
	var cd: CardData = CardRef.from_ref(main._auction_card_ref)
	if cd == null:
		main._server_handle_pass_bid(bot_id)
		return
	# no bid on a card the bot has nowhere to put (it would pay, then recycle or lose it)
	var bot_board: Array = main.bot_boards.get(bot_id, []) as Array
	var placeable: bool = BotAI._any_slot_has_tech_room(bot_board) if main._auction_is_tech else bot_board.size() < BotAI.MAX_SECTORS
	if not placeable:
		main._server_handle_pass_bid(bot_id)
		return
	var new_bid: int = BotAI.decide_bid(
		GameNetwork.bot_difficulty.get(bot_id, BotAI.Difficulty.EASY),
		main._auction_current_bid, main.bot_supplies.get(bot_id, {}), cd, main._auction_is_adv,
		main.bot_boards.get(bot_id, []) as Array, int(main._auction_cost_color))
	if new_bid > 0:
		main._server_handle_raise(bot_id, new_bid)
	else:
		main._server_handle_pass_bid(bot_id)


# Called (host-only) when a bot wins an auction — pays and places the card
# immediately, since bots have no client to drive the normal drag-to-place
# step. is_tech mirrors board.gd's auction/purchase flow: true means the
# card attaches to an existing sector's card stack (Expedition cards — the
# real game attaches them the same way as Tech cards), false means it
# occupies a brand-new sector slot (an advanced Sector card revealed via an
# effect like Cargo Bays/Transforming Hull).
static func bot_resolve_auction_win(
	main: Main, bot_id: int, card_ref: Dictionary, final_bid: int,
	cost_color: CardData.SupplyColor, is_tech: bool, is_adv: bool
) -> void:
	var cd: CardData = CardRef.from_ref(card_ref)
	if cd == null:
		return
	# the bid, paid along the colour's supply chain (as decide_bid budgets it)
	BotAI.pay_supplies(main.bot_supplies[bot_id] as Dictionary, int(cost_color), maxi(0, final_bid))
	var board: Array = main.bot_boards.get(bot_id, []) as Array
	# The card leaves the shared market whether the bot places or recycles it
	# (a human-started auction's card went back to the market when its
	# initiator lost). No-op if it's already gone.
	if GameNetwork.is_multiplayer:
		main._rpc_sync_market_removal.rpc(card_ref)
	else:
		main.get_node("Board").remove_market_card(cd)
	if is_tech:
		var difficulty: int = GameNetwork.bot_difficulty.get(bot_id, BotAI.Difficulty.EASY)
		var slot_idx: int = BotAI.pick_stack_slot(board, cd, difficulty)
		if slot_idx == -1:
			# No room anywhere — shouldn't normally happen since bots only bid
			# when they have somewhere to put the card. Recycle it for supply
			# rather than lose it silently.
			_bot_gain_recycle(main, bot_id, cd)
			main.get_node("Board").add_to_discard(cd)
		else:
			_attach_stack_card(main, bot_id, slot_idx, cd)
	elif board.size() < BotAI.MAX_SECTORS:
		main.bot_boards[bot_id].append(_new_slot_entry(cd, is_adv))
		_bot_sector_placed(main, bot_id, cd, is_adv)
	else:
		# no room for a 7th sector: recycled for its supply, as a human's (Board's unplaceable path)
		_bot_gain(main, bot_id, int(cd.adv_color if is_adv else cd.color), CardData.recycle_amount(cd))
	# main.gd:_rpc_sync_auction_won already logs "X won Y for Z" generically
	# for every winner, bots included — no separate log line needed here.
	broadcast_bot_states(main)


# A random pick is the entire "AI" here — Interfleet Comms is a minor tech
# effect, not worth a BotAI.decide_* heuristic.
static func bot_decide_interfleet_pick(main: Main, bot_id: int) -> void:
	if main._interfleet_pool_refs.is_empty():
		return
	var idx: int = randi() % main._interfleet_pool_refs.size()
	main._server_handle_interfleet_pick(bot_id, idx)


# ── Generation Fleet: bot crewmates pledging toward a solve (host) ────────────
# A bot chips in supplies / hand cards it has, up to need (what the crew still
# needs after the bots before it: FleetFlow._server_fleet_open). The pledge is set
# aside at once (a bot turn during the session can't spend it), paid if the whole
# crew covers the cost, handed back if not. Destroying or archived-card costs are
# left to the humans for now. covered: Dimension Pocket's colours already pledged.
static var _fleet_pledges: Dictionary = {}   # bot id -> {kind, units, colors, cards, paid}

static func bot_fleet_pledge(main: Main, bot_id: int, no: int, need: int, covered: Array = []) -> Dictionary:
	var sv: Dictionary = FleetRules.SOLVES.get(no, {})
	var kind: String = str(sv.get("kind", ""))
	var plan: Dictionary = {"kind": kind, "units": 0, "colors": [], "cards": [], "paid": {}}
	if need <= 0:
		_fleet_pledges[bot_id] = plan
		return plan
	match kind:
		"pay":
			# the colour's supply chain counts, as for the humans' pledges (Board._compute_payment)
			var col: int = int(sv["color"])
			var sup: Dictionary = main.bot_supplies.get(bot_id, {}) as Dictionary
			var have: int = 0
			for c: CardData.SupplyColor in CardData.valid_payment_colors(col as CardData.SupplyColor):
				have += int(sup.get(int(c), 0))
			var units: int = mini(have, need)
			if units > 0:
				var paid: Dictionary = BotAI.bot_payment(sup, col, units)
				for c: Variant in paid:
					sup[int(c)] = int(sup.get(int(c), 0)) - int(paid[c])
				plan["paid"] = paid
				plan["units"] = units
		"discard_color", "discard_stars", "discard_each_color":
			var hand: Array[CardData] = bot_hand(main, bot_id)
			for cd: CardData in hand:
				if kind == "discard_each_color":
					if (plan["colors"] as Array).size() >= need:
						break
				elif int(plan["units"]) >= need:
					break
				if kind == "discard_color" and not (sv["colors"] as Array).has(int(cd.color)):
					continue
				if kind == "discard_stars" and cd.stars <= 0:
					continue
				if kind == "discard_each_color" and ((plan["colors"] as Array).has(int(cd.color)) or covered.has(int(cd.color))):
					continue
				(plan["cards"] as Array).append(cd)
				if kind == "discard_stars":
					plan["units"] = int(plan["units"]) + cd.stars
				elif kind == "discard_each_color":
					(plan["colors"] as Array).append(int(cd.color))
				else:
					plan["units"] = int(plan["units"]) + 1
			for cd: Variant in plan["cards"] as Array:
				hand.erase(cd)
			bot_set_hand(main, bot_id, hand)
	_fleet_pledges[bot_id] = plan
	return plan

# The solve went through: the set-aside supplies are spent, the cards go to the discard pile.
static func bot_fleet_pay_pledges(main: Main) -> void:
	for bot_id: int in _fleet_pledges:
		var plan: Dictionary = _fleet_pledges[bot_id]
		for cd: Variant in plan.get("cards", []) as Array:
			main.get_node("Board").add_to_discard(cd as CardData)
	_fleet_pledges.clear()
	broadcast_bot_states(main)

# The solve fell short: every bot gets its pledge back.
static func bot_fleet_clear_pledges(main: Main) -> void:
	for bot_id: int in _fleet_pledges:
		var plan: Dictionary = _fleet_pledges[bot_id]
		var sup: Dictionary = main.bot_supplies.get(bot_id, {}) as Dictionary
		var paid: Dictionary = plan.get("paid", {}) as Dictionary
		for c: Variant in paid:
			sup[int(c)] = int(sup.get(int(c), 0)) + int(paid[c])
		var cards: Array = plan.get("cards", []) as Array
		if not cards.is_empty():
			var hand: Array[CardData] = bot_hand(main, bot_id)
			for cd: Variant in cards:
				hand.append(cd as CardData)
			bot_set_hand(main, bot_id, hand)
	_fleet_pledges.clear()


# ── Generation Fleet: bot crewmates (host) ───────────────────────────────────

# Expeditions in Fleet: no auction, the printed cost (plus Danger surcharges).
static func bot_buy_expedition_fleet(main: Main, bot_id: int, cd: CardData) -> void:
	var cost: int = max(0, cd.cost) + FleetRules.cost_increase(cd)
	BotAI.pay_supplies(main.bot_supplies[bot_id] as Dictionary, int(cd.color), cost)
	if GameNetwork.is_multiplayer:
		main._rpc_sync_market_removal.rpc(CardRef.to_ref(cd))
	else:
		main.get_node("Board").remove_market_card(cd)
	var board: Array = main.bot_boards.get(bot_id, []) as Array
	var difficulty: int = GameNetwork.bot_difficulty.get(bot_id, BotAI.Difficulty.EASY)
	var slot_idx: int = BotAI.pick_stack_slot(board, cd, difficulty)
	var _bname: String = GameNetwork.player_names.get(bot_id, main.tr("Bot"))
	# Undetected Wormhole: the purchase counts (even recycled for lack of room), before the card's
	# effects, as Main._on_card_placed
	main.fleet_expedition_bought()
	if slot_idx == -1:
		_bot_gain_recycle(main, bot_id, cd)
		return
	_attach_stack_card(main, bot_id, slot_idx, cd)
	main._broadcast_log(main.tr("%s: bought %s") % [_bname, cd.card_name], CardData.color_tint(cd.color))

# A Place Danger on a bot's ship — the same effect the humans resolve, with
# simple fixed choices. Shared ones (market, System Failure, passing hands)
# happen once for everyone elsewhere.
static func bot_fleet_place(main: Main, bot_id: int, no: int) -> void:
	_bot_fleet_apply(main, bot_id, FleetRules.PLACE_EFFECTS.get(no, {}) as Dictionary)

static func _bot_fleet_apply(main: Main, bot_id: int, eff: Dictionary) -> void:
	var sup: Dictionary = main.bot_supplies.get(bot_id, {}) as Dictionary
	var board: Array = main.bot_boards.get(bot_id, []) as Array
	var n: int = int(eff.get("n", 1))
	match str(eff.get("kind", "")):
		"to_dust":
			for i: int in n:
				var best: int = -1
				for c: int in [CardData.SupplyColor.METALS, CardData.SupplyColor.LIQUIDS, CardData.SupplyColor.ORGANIX,
						CardData.SupplyColor.ELECTRIX, CardData.SupplyColor.THRUST]:
					if int(sup.get(c, 0)) > 0:
						best = c   # the last (most valuable) colour it has
				if best < 0:
					break
				sup[best] = int(sup[best]) - 1
				if not FleetRules.blocks_gain(CardData.SupplyColor.DUST):
					sup[CardData.SupplyColor.DUST] = int(sup.get(CardData.SupplyColor.DUST, 0)) + 1
		"destroy":
			# flipped face down where it lies, as the humans' (SectorSlot.fleet_destroy_card): the sector
			# keeps its card count, the card stays out of the deck and loses colour, stars and effect
			for i: int in n:
				var idx: int = _bot_destroy_target(board, str(eff.get("where", "any")), int(eff.get("pref", -1)))
				if idx < 0:
					break
				var e: Dictionary = board[idx] as Dictionary
				var techs: Array = e.get("techs", []) as Array
				var top: int = BotScoring.top_live_index(e)
				techs[top] = BotScoring.destroyed_marker(techs[top] as CardData)
				_bot_revalidate_optimize(main, bot_id, idx)   # it fills no tank any more
		"choose":
			# only an option the bot can actually do, as the humans' (FleetFlow._option_possible)
			for o: Variant in eff.get("options", []) as Array:
				var opt: Dictionary = o as Dictionary
				if _bot_option_possible(main, bot_id, opt):
					_bot_fleet_apply(main, bot_id, opt)
					return
		"pay":
			var c: int = int(eff["color"])
			if BotAI.can_pay(sup, c, n):   # along the colour's supply chain
				BotAI.pay_supplies(sup, c, n)
		"lose_stored", "lose_stored_or_archived":
			for i: int in n:
				var done: bool = false
				for e_v: Variant in board:
					var stored: Dictionary = (e_v as Dictionary).get("stored_supply", {}) as Dictionary
					for c: Variant in stored.keys():
						if int(stored[c]) > 0:
							stored[c] = int(stored[c]) - 1
							done = true
							break
					if done:
						break
				if not done and str(eff["kind"]) == "lose_stored_or_archived":
					for e_v: Variant in board:
						var tucked: Array = (e_v as Dictionary).get("tucked_cards", []) as Array
						if not tucked.is_empty():
							tucked.pop_back()
							done = true
							break
				if not done:
					break
		"discard":
			var hand: Array[CardData] = bot_hand(main, bot_id)
			for i: int in mini(n, hand.size()):
				main.get_node("Board").add_to_discard(hand.pop_back())
			bot_set_hand(main, bot_id, hand)
		"remove_fewest_sector":
			var fewest: int = -1
			for i: int in board.size():
				var cnt: int = 1 + ((board[i] as Dictionary).get("techs", []) as Array).size()
				if fewest < 0 or cnt < 1 + ((board[fewest] as Dictionary).get("techs", []) as Array).size():
					fewest = i
			if fewest >= 0:
				# every tech on it goes to the discard pile, face-down ones too (SectorSlot.fleet_remove_sector)
				for t: Variant in (board[fewest] as Dictionary).get("techs", []) as Array:
					var tcd: CardData = (t as CardData) if t is CardData else ((t as Dictionary).get("data") as CardData)
					if tcd and tcd.card_type == CardData.CardType.TECH:
						main.get_node("Board").add_to_discard(tcd)
				board.remove_at(fewest)

static func _bot_option_possible(main: Main, bot_id: int, o: Dictionary) -> bool:
	var board: Array = main.bot_boards.get(bot_id, []) as Array
	match str(o.get("kind", "")):
		"pay":
			return BotAI.can_pay(main.bot_supplies.get(bot_id, {}) as Dictionary, int(o["color"]), int(o["n"]))
		"destroy":
			return _bot_destroy_target(board, "any", -1) >= 0
		"lose_stored":
			for e: Variant in board:
				if BotScoring.slot_total_stored(e as Dictionary) > 0:
					return true
			return false
		"discard":
			return not bot_hand(main, bot_id).is_empty()
	return true

# The sector whose top card a Danger destroys: one with a card still face up on it (as
# FleetFlow._destroyable_slots / SectorSlot.fleet_top_card), -1 if none.
static func _bot_destroy_target(board: Array, where: String, pref: int) -> int:
	var with_live: Array[int] = []
	for i: int in board.size():
		if BotScoring.top_live_index(board[i] as Dictionary) >= 0:
			with_live.append(i)
	if with_live.is_empty():
		return -1
	if where == "rightmost":
		return board.size() - 1 if with_live.has(board.size() - 1) else -1
	if where == "leftmost":
		return 0 if with_live.has(0) else -1
	if pref >= 0:
		for i: int in with_live:
			var e: Dictionary = board[i] as Dictionary
			var top: CardData = (e["techs"] as Array)[BotScoring.top_live_index(e)] as CardData
			if top and int(top.color) == pref:
				return i
	return with_live[0]
