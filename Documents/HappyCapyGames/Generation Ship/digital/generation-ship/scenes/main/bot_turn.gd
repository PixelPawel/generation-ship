class_name BotTurn
extends RefCounted

# Server-side orchestration for AI-controlled players: owns bot hand/supply/
# board state on the Main node and executes the plays BotAI decides on.
# Holds no state of its own.

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
		slot_snaps.append({
			"occupied": true,
			"optimize_count": 0,
			"max_optimizations": 0,
			"is_optimized": false,
			"tech_count": techs.size(),
			"sector_name": sector.adv_name if (is_adv and not sector.adv_name.is_empty()) else sector.card_name,
			"sector_advanced": is_adv,
			"tech_names": tech_names,
			"position": {"x": 0.0, "z": 0.0},
		})
	return {
		"peer_id": bot_id,
		"supply": main.bot_supplies.get(bot_id, {}),
		"hand_size": hand_arr.size(),
		"vp": 0,
		"vp_lines": [],
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
	var action: Dictionary = BotAI.decide_action(
		difficulty, bot_hand(main, bot_id), main.bot_supplies.get(bot_id, {}) as Dictionary,
		main.bot_boards.get(bot_id, []) as Array, main._round, market_sectors)
	match action.get("type", "pass"):
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
		"research":
			bot_do_research(main, bot_id)
			broadcast_bot_states(main)
			var _rname: String = GameNetwork.player_names.get(bot_id, "Bot")
			main._broadcast_log("%s: researching…" % _rname, Color(0.50, 0.78, 1.0))
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


static func bot_buy_sector(main: Main, bot_id: int, card_data: CardData) -> void:
	var color: int = int(card_data.color)
	main.bot_supplies[bot_id][color] = max(0, main.bot_supplies[bot_id].get(color, 0) - max(0, card_data.cost))
	main.get_node("Board").get_market().remove_card(card_data)
	main.bot_boards[bot_id].append({"sector": card_data, "is_advanced": false, "techs": [], "stored": {}})
	apply_bot_effect_steps(main, bot_id, simple_bot_card_steps(card_data))
	var _bname: String = GameNetwork.player_names.get(bot_id, "Bot")
	main._broadcast_log("%s: bought %s" % [_bname, card_data.card_name], CardData.color_tint(card_data.color))


static func bot_place_tech(main: Main, bot_id: int, card_data: CardData, slot_idx: int) -> void:
	var hand: Array[CardData] = bot_hand(main, bot_id)
	hand.erase(card_data)
	bot_set_hand(main, bot_id, hand)
	var color: int = int(card_data.color)
	main.bot_supplies[bot_id][color] = max(0, main.bot_supplies[bot_id].get(color, 0) - max(0, card_data.cost))
	(main.bot_boards[bot_id][slot_idx]["techs"] as Array).append(card_data)
	apply_bot_effect_steps(main, bot_id, simple_bot_card_steps(card_data))
	var _bname: String = GameNetwork.player_names.get(bot_id, "Bot")
	main._broadcast_log("%s: placed %s" % [_bname, card_data.card_name], CardData.color_tint(card_data.color))


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


static func broadcast_bot_states(main: Main) -> void:
	for bot_id: int in GameNetwork.bot_ids:
		var bot_state: Dictionary = get_bot_snapshot(main, bot_id)
		main._apply_opponent_state(bot_state)
		for peer_id: int in GameNetwork.player_order:
			if peer_id != 1 and not GameNetwork.is_bot(peer_id):
				main._rpc_recv_board_state.rpc_id(peer_id, bot_state)


static func simple_bot_card_steps(_card_data: CardData) -> Array[Dictionary]:
	return []


static func apply_bot_effect_steps(main: Main, bot_id: int, steps: Array[Dictionary]) -> void:
	for step: Dictionary in steps:
		match step.get("type"):
			"draw":
				var hand: Array[CardData] = bot_hand(main, bot_id)
				hand.append_array(main.get_node("Board").draw_card_data(int(step.get("count", 1))))
				bot_set_hand(main, bot_id, hand)
			"gain_supply":
				var c: int = int(step.get("color", 0))
				main.bot_supplies[bot_id][c] = main.bot_supplies[bot_id].get(c, 0) + int(step.get("amount", 1))
			"choice":
				var opts: Array = step.get("options", []) as Array
				if not opts.is_empty():
					apply_bot_effect_steps(main, bot_id, opts[0].get("steps", []) as Array[Dictionary])


static func bot_decide_bid(main: Main, bot_id: int) -> void:
	var cd: CardData = CardRef.from_ref(main._auction_card_ref)
	if cd == null:
		main._server_handle_pass_bid(bot_id)
		return
	var new_bid: int = BotAI.decide_bid(
		GameNetwork.bot_difficulty.get(bot_id, BotAI.Difficulty.EASY),
		main._auction_current_bid, main.bot_supplies.get(bot_id, {}), cd, main._auction_is_adv)
	if new_bid > 0:
		main._server_handle_raise(bot_id, new_bid)
	else:
		main._server_handle_pass_bid(bot_id)


# A random pick is the entire "AI" here — Interfleet Comms is a minor tech
# effect, not worth a BotAI.decide_* heuristic.
static func bot_decide_interfleet_pick(main: Main, bot_id: int) -> void:
	if main._interfleet_pool_refs.is_empty():
		return
	var idx: int = randi() % main._interfleet_pool_refs.size()
	main._server_handle_interfleet_pick(bot_id, idx)
