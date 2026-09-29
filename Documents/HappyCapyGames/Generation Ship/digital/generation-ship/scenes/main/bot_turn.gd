class_name BotTurn
extends RefCounted

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
		var old_hand: Array = main.bot_hands.get(bot_id, [])
		for cd: Variant in old_hand:
			main.get_node("Board").add_to_discard(cd as CardData)
		main.bot_hands[bot_id] = main.get_node("Board").draw_card_data(6)
		var supply: Dictionary = main.bot_supplies.get(bot_id, {})
		for color: CardData.SupplyColor in CardData.SupplyColor.values():
			supply[int(color)] = supply.get(int(color), 0) + 1
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
			var tc: CardData = t as CardData
			if tc:
				tech_names.append(tc.card_name)
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
	return {
		"peer_id": bot_id,
		"supply": main.bot_supplies.get(bot_id, {}),
		"hand_size": hand_arr.size(),
		"vp": BotScoring.board_vp(board),
		"vp_lines": BotScoring.board_vp_lines(board),
		"slots": slot_snaps,
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
	var board: Array = main.bot_boards.get(bot_id, []) as Array
	var supplies: Dictionary = main.bot_supplies.get(bot_id, {}) as Dictionary
	var hand: Array[CardData] = bot_hand(main, bot_id)

	# Free actions first: fuse toward the best play, then (Hard only) recycle
	# a dead hand card if that's what's actually blocking a play.
	for f: Dictionary in BotAI.suggest_fuses(difficulty, hand, supplies, board, market_sectors):
		bot_fuse(main, bot_id, int(f["source"]), int(f["target"]))

	var action: Dictionary = BotAI.decide_action(difficulty, hand, supplies, board, main._round, market_sectors, market_expeditions)
	if String(action.get("type", "pass")) in ["pass", "research"]:
		var recycle_card: CardData = BotAI.suggest_recycle(difficulty, hand, supplies, board, market_sectors)
		if recycle_card:
			bot_recycle(main, bot_id, recycle_card)
			hand = bot_hand(main, bot_id)
			action = BotAI.decide_action(difficulty, hand, supplies, board, main._round, market_sectors, market_expeditions)

	match String(action.get("type", "pass")):
		"buy_sector":
			bot_buy_sector(main, bot_id, action["card"] as CardData)
			broadcast_bot_states(main)
			await main.get_tree().create_timer(0.5).timeout
			main._server_handle_end_turn()
		"place_tech":
			bot_place_tech(main, bot_id, action["card"] as CardData, action["slot_idx"] as int)
			broadcast_bot_states(main)
			await main.get_tree().create_timer(0.5).timeout
			main._server_handle_end_turn()
		"start_auction":
			bot_start_auction(main, bot_id, action["card"] as CardData)
			broadcast_bot_states(main)
			# No end_turn call here — the auction (and whoever wins it) still
			# has to resolve, which can take real time and other players'
			# input. Main._rpc_sync_auction_placement_pending ends this bot's
			# turn once that fully settles, mirroring how a human initiator's
			# turn stays open until their auction is done.
		"research":
			bot_do_research(main, bot_id)
			broadcast_bot_states(main)
			var _rname: String = GameNetwork.player_names.get(bot_id, main.tr("Bot"))
			main._broadcast_log(main.tr("%s: researching…") % _rname, Color(0.50, 0.78, 1.0))
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
	var color: int = int(card_data.color)
	main.bot_supplies[bot_id][color] = max(0, main.bot_supplies[bot_id].get(color, 0) - max(0, card_data.cost))
	main.get_node("Board").get_market().remove_card(card_data)
	main.bot_boards[bot_id].append(_new_slot_entry(card_data, false))
	var _bname: String = GameNetwork.player_names.get(bot_id, main.tr("Bot"))
	main._broadcast_log(main.tr("%s: bought %s") % [_bname, card_data.card_name], CardData.color_tint(card_data.color))


static func bot_place_tech(main: Main, bot_id: int, card_data: CardData, slot_idx: int) -> void:
	var hand: Array[CardData] = bot_hand(main, bot_id)
	hand.erase(card_data)
	bot_set_hand(main, bot_id, hand)
	var color: int = int(card_data.color)
	main.bot_supplies[bot_id][color] = max(0, main.bot_supplies[bot_id].get(color, 0) - max(0, card_data.cost))
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

	var place_steps: Array[Dictionary] = PlaceEffects.get_steps_for_state(
		card_data, BotScoring.is_slot_new(slot), BotScoring.is_slot_complete(slot),
		BotScoring.is_slot_optimized(slot), BotScoring.slot_effective_placed_colors(slot))
	apply_bot_effect_steps(main, bot_id, place_steps, slot_idx)

	var sector: CardData = slot.get("sector") as CardData
	if sector == null:
		return
	var is_adv: bool = bool(slot.get("is_advanced", false))
	var effective_colors: Array[int] = BotScoring.slot_effective_placed_colors(slot)
	var result: Dictionary = OptimizeLogic.update_optimize_state(
		sector, is_adv, effective_colors,
		int(slot.get("optimize_count", 0)), int(slot.get("max_optimizations", 0)),
		slot.get("triggered_levels", []) as Array[bool])
	slot["optimize_count"] = result["optimize_count"]
	slot["is_optimized"] = result["is_optimized"]
	slot["triggered_levels"] = result["triggered_levels"]
	var triggered: Array = result["triggered"] as Array
	if triggered.is_empty():
		return
	var opt_steps: Array[Dictionary] = SectorEffects.get_optimize_steps_for_state(
		sector, is_adv, effective_colors, int(slot.get("last_placed_tech_cost", 0)))
	# Mirrors main.gd:_on_optimize_triggered firing once per triggered level.
	for _lvl: int in triggered.size():
		apply_bot_effect_steps(main, bot_id, opt_steps, slot_idx)


static func bot_do_research(main: Main, bot_id: int) -> void:
	var hand: Array[CardData] = bot_hand(main, bot_id)
	if hand.is_empty():
		return
	hand.sort_custom(func(a: CardData, b: CardData) -> bool: return a.cost < b.cost)
	main.get_node("Board").add_to_discard(hand.pop_front())
	hand.append_array(main.get_node("Board").draw_card_data(1))
	bot_set_hand(main, bot_id, hand)


static func bot_pass(main: Main, bot_id: int) -> void:
	main._bots_passed_this_round.append(bot_id)
	main._server_handle_pass()


static func bot_fuse(main: Main, bot_id: int, source: int, target: int) -> void:
	main.bot_supplies[bot_id][source] = max(0, (main.bot_supplies[bot_id].get(source, 0) as int) - 2)
	main.bot_supplies[bot_id][target] = (main.bot_supplies[bot_id].get(target, 0) as int) + 1
	var _bname: String = GameNetwork.player_names.get(bot_id, main.tr("Bot"))
	main._broadcast_log(
		main.tr("%s: fused %s → %s") % [_bname, CardData.color_name(source as CardData.SupplyColor), CardData.color_name(target as CardData.SupplyColor)],
		Color(0.7, 0.85, 1.0))


static func bot_recycle(main: Main, bot_id: int, card: CardData) -> void:
	var hand: Array[CardData] = bot_hand(main, bot_id)
	hand.erase(card)
	bot_set_hand(main, bot_id, hand)
	var color: int = int(card.color)
	main.bot_supplies[bot_id][color] = (main.bot_supplies[bot_id].get(color, 0) as int) + CardData.recycle_amount(card)
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
static func apply_bot_effect_steps(main: Main, bot_id: int, steps: Array[Dictionary], slot_idx: int = -1) -> void:
	for step: Dictionary in steps:
		match String(step.get("type", "")):
			"draw", "draw_recycle_top":
				var hand: Array[CardData] = bot_hand(main, bot_id)
				hand.append_array(main.get_node("Board").draw_card_data(int(step.get("count", 1))))
				bot_set_hand(main, bot_id, hand)
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
				var c: int = int(step.get("color", 0))
				main.bot_supplies[bot_id][c] = (main.bot_supplies[bot_id].get(c, 0) as int) + int(step.get("amount", 1))
			"gain_supply_per_stored":
				if slot_idx >= 0 and slot_idx < main.bot_boards[bot_id].size():
					var slot: Dictionary = main.bot_boards[bot_id][slot_idx] as Dictionary
					var amt: int = BotScoring.slot_total_stored(slot) * int(step.get("multiplier", 1))
					if amt > 0:
						var c2: int = int(step.get("color", 0))
						main.bot_supplies[bot_id][c2] = (main.bot_supplies[bot_id].get(c2, 0) as int) + amt
			"gain_supply_per_sector_count":
				var c3: int = int(step.get("color", 0))
				var board: Array = main.bot_boards.get(bot_id, []) as Array
				main.bot_supplies[bot_id][c3] = (main.bot_supplies[bot_id].get(c3, 0) as int) + board.size()
			"store_on_slot":
				_bot_store(main, bot_id, slot_idx, int(step.get("color", 0)), int(step.get("amount", 1)))
			"store_on_any_sector":
				_bot_store(main, bot_id, _bot_any_slot(main, bot_id), int(step.get("color", 0)), int(step.get("amount", 1)))
			"store_per_card_here":
				if slot_idx >= 0 and slot_idx < main.bot_boards[bot_id].size():
					for color: int in BotScoring.slot_effective_placed_colors(main.bot_boards[bot_id][slot_idx] as Dictionary):
						_bot_store(main, bot_id, slot_idx, color, 1)
			"tuck":
				_bot_tuck(main, bot_id, slot_idx, int(step.get("count", 1)), bool(step.get("face_up", false)))
			"tuck_optional":
				_bot_tuck(main, bot_id, slot_idx, int(step.get("max", 1)), bool(step.get("face_up", false)))
			"tuck_any_sector_optional":
				_bot_tuck(main, bot_id, _bot_any_slot(main, bot_id), int(step.get("max", 1)), bool(step.get("face_up", false)))
			"recycle":
				_bot_recycle_n(main, bot_id, int(step.get("count", 1)))
			"recycle_optional":
				_bot_recycle_n(main, bot_id, int(step.get("max", 1)))
			"choice":
				var opts: Array = step.get("options", []) as Array
				if not opts.is_empty():
					apply_bot_effect_steps(main, bot_id, BotScoring.to_dict_array((opts[0] as Dictionary).get("steps", []) as Array), slot_idx)
			_:
				pass


static func _bot_store(main: Main, bot_id: int, slot_idx: int, color: int, amount: int) -> void:
	if slot_idx < 0 or slot_idx >= main.bot_boards[bot_id].size():
		return
	var slot: Dictionary = main.bot_boards[bot_id][slot_idx] as Dictionary
	var stored: Dictionary = slot.get("stored_supply", {}) as Dictionary
	stored[color] = (stored.get(color, 0) as int) + amount
	slot["stored_supply"] = stored

static func _bot_any_slot(main: Main, bot_id: int) -> int:
	var board: Array = main.bot_boards.get(bot_id, []) as Array
	return 0 if not board.is_empty() else -1

static func _bot_tuck(main: Main, bot_id: int, slot_idx: int, count: int, face_up: bool) -> void:
	if slot_idx < 0 or slot_idx >= main.bot_boards[bot_id].size():
		return
	var hand: Array[CardData] = bot_hand(main, bot_id)
	hand.sort_custom(func(a: CardData, b: CardData) -> bool: return BotScoring.card_value(a) < BotScoring.card_value(b))
	var slot: Dictionary = main.bot_boards[bot_id][slot_idx] as Dictionary
	var tucked: Array = slot.get("tucked_cards", []) as Array
	var n: int = mini(count, hand.size())
	for _i: int in n:
		tucked.append({"data": hand.pop_front(), "face_up": face_up})
	slot["tucked_cards"] = tucked
	bot_set_hand(main, bot_id, hand)

static func _bot_recycle_n(main: Main, bot_id: int, count: int) -> void:
	var hand: Array[CardData] = bot_hand(main, bot_id)
	hand.sort_custom(func(a: CardData, b: CardData) -> bool: return BotScoring.card_value(a) < BotScoring.card_value(b))
	var n: int = mini(count, hand.size())
	for _i: int in n:
		var card: CardData = hand.pop_front()
		main.bot_supplies[bot_id][int(card.color)] = (main.bot_supplies[bot_id].get(int(card.color), 0) as int) + CardData.recycle_amount(card)
		main.get_node("Board").add_to_discard(card)
	bot_set_hand(main, bot_id, hand)


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
	main._server_start_auction(card_ref, -1, true, false, card_data.cost, int(card_data.color), bot_id)
	var _bname: String = GameNetwork.player_names.get(bot_id, main.tr("Bot"))
	main._broadcast_log(main.tr("%s: started an auction for %s") % [_bname, card_data.card_name], CardData.color_tint(card_data.color))


static func bot_decide_bid(main: Main, bot_id: int) -> void:
	var cd: CardData = CardRef.from_ref(main._auction_card_ref)
	if cd == null:
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
# effect like Cargo Bays/Transformable Hull).
static func bot_resolve_auction_win(
	main: Main, bot_id: int, card_ref: Dictionary, final_bid: int,
	cost_color: CardData.SupplyColor, is_tech: bool, is_adv: bool
) -> void:
	var cd: CardData = CardRef.from_ref(card_ref)
	if cd == null:
		return
	var color: int = int(cost_color)
	main.bot_supplies[bot_id][color] = max(0, (main.bot_supplies[bot_id].get(color, 0) as int) - max(0, final_bid))
	var board: Array = main.bot_boards.get(bot_id, []) as Array
	if is_tech:
		var difficulty: int = GameNetwork.bot_difficulty.get(bot_id, BotAI.Difficulty.EASY)
		var slot_idx: int = BotAI.pick_stack_slot(board, cd, difficulty)
		if slot_idx == -1:
			# No room anywhere — shouldn't normally happen since bots only bid
			# when they have somewhere to put the card. Recycle it for supply
			# rather than lose it silently.
			main.bot_supplies[bot_id][int(cd.color)] = (main.bot_supplies[bot_id].get(int(cd.color), 0) as int) + CardData.recycle_amount(cd)
			main.get_node("Board").add_to_discard(cd)
		else:
			_attach_stack_card(main, bot_id, slot_idx, cd)
	elif board.size() < BotAI.MAX_SECTORS:
		main.bot_boards[bot_id].append(_new_slot_entry(cd, is_adv))
	else:
		main.get_node("Board").add_to_discard(cd)
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
