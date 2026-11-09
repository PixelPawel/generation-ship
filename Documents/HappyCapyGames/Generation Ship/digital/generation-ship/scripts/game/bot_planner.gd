extends RefCounted
## Hard and Very Hard bots (2026-11-09): they try their plays out before choosing. Every candidate play —
## a tech on a sector, a sector, an auction — is run through the game's own rules in BotTurn's sandbox
## (sim_apply: the real effect resolver on a copy of the bot's ship, supplies and hand; draws come up as
## unknown cards), several plays deep (a beam search: the best few lines are followed), and each resulting
## position is scored by evaluate():
##   * in the last Generation, simply the score the ship would end with;
##   * earlier, the score the ship is heading for: an economy forecast (supply in hand + what the ship
##     earns each Generation + cards to play) says how many more cards the bot will get onto the ship,
##     the ship is filled up with that many stand-ins, and the result is scored by the game's own scoring.
## So supply, income, cards, completing and optimizing sectors and what the expeditions pay for all count,
## at what they are really worth on this ship — the old bots chased printed stars and ended near 20.
## Preloaded by BotTurn (no class_name). Tuned with tools/bot_league.py.

const ROUNDS: int = 4
const CAP: int = 5            # cards a sector takes (BotAI.TECH_CAPACITY)
const MAX_SECTORS: int = 6
# a supply's worth by colour, Dust = 1 (it fuses 2:1 up a chain, and pays 1:1 for anything below it)
const U: Array[float] = [1.0, 1.4, 1.4, 2.0, 2.0, 2.8]
const COST_U: float = 3.0     # what an average card costs to place, in those units
const REC_U: float = 1.6      # what an average card gives recycled
const INC_U: float = 1.6      # what an average placed card earns per Generation
const CARD_VP: float = 0.7    # points an average later card brings by itself (its stars, stores, archives):
                              # what an average REAL card brings, or the bot hoards supply for imaginary ones
const EXP_VP: float = 8.0     # points an expedition bought in a later Generation brings
const EXP_COST_U: float = 5.0 # and what it costs, in units
const PLAYABLE: float = 0.8   # share of the cards in hand that are worth placing
const MIN_GAIN: float = 0.05  # a play must improve the outlook by this much, else research/pass
const PREMIUM: int = 1        # supply above the printed cost an auction is planned to cost
const SLICE_MSEC: int = 5     # planning work per frame, so the game never stutters

static func kf(name: String, fallback: float) -> float:
	return BotAI.BotValue.k(name, fallback)   # --bv-<name>=<value> overrides (tools/bot_league.py)

## How hard a bot of this difficulty thinks: lines followed (width), plays ahead (depth).
static func config(difficulty: int, gen: int = 1) -> Dictionary:
	var cfg: Dictionary = {width = int(kf("hw", 3.0)), depth = int(kf("hd", 4.0))}
	if difficulty >= BotAI.Difficulty.VERY_HARD:
		cfg = {width = int(kf("vw", 5.0)), depth = int(kf("vd", 6.0))}
	if gen >= ROUNDS:   # the last Generation is scored exactly: looking further only helps
		cfg["width"] = int(cfg["width"]) + int(kf("lastw", 3.0))
		cfg["depth"] = int(cfg["depth"]) + int(kf("lastd", 4.0))
	return cfg

static func state_of(main: Main, bot_id: int) -> Dictionary:
	return {
		"board": main.bot_boards.get(bot_id, []) as Array,
		"supplies": main.bot_supplies.get(bot_id, {}) as Dictionary,
		"hand": BotTurn.bot_hand(main, bot_id),
		"unknown_i": 0,
	}

# ── What a position is worth ────────────────────────────────────────────────────

static func units_of(supplies: Dictionary) -> float:
	var u: float = 0.0
	for c: Variant in supplies:
		u += float(int(supplies[c])) * U[clampi(int(c), 0, 5)]
	return u

## The final score this position is heading for (see the top of the file).
static func evaluate(st: Dictionary, gen: int) -> float:
	var board: Array = st["board"] as Array
	var units: float = units_of(st["supplies"] as Dictionary)
	if gen >= ROUNDS:
		return float(BotScoring.board_vp(board)) + 0.02 * units
	if W.has(gen + 1) and kf("model", 1.0) > 0.5:
		# what the ship scores now + what a position like the one the next Generation will start from
		# went on to add in the bots' own games (W: fitted by tools/bot_league_fit.py)
		var f: PackedFloat32Array = features(st, gen + 1, true)
		var w: Array = W[gen + 1] as Array
		var v2: float = float(BotScoring.board_vp(board))
		for i: int in mini(f.size(), w.size()):
			v2 += f[i] * float(w[i])
		return v2
	return forecast(st, gen)

## Fitted weights per Generation start (2, 3, 4), one per feature (FEATURES). Empty: forecast() is used.
const W: Dictionary = {
	2: [3.1, 1.16, 1.33, 1.0, 0.1, 0.0, 0.3, 0.1, 1.0, 0.0],
	3: [-2.0, 0.76, 0.57, 0.96, 0.1, 0.0, 0.3, 0.05, 1.0, 0.0],
	4: [-6.7, 0.57, 0.0, 0.86, 0.0, 0.0, 0.3, 0.05, 0.6, 0.0],
}
const FEATURES: Array[String] = ["one", "units", "income", "hand", "capacity", "open_sectors", "synergy", "hand_stars", "opt_value", "ship"]

## A position as the start of Generation gen_start sees it. advance: st is the END of the Generation
## before (the ship's income and the 6 new cards are added); else st is already that start.
static func features(st: Dictionary, gen_start: int, advance: bool) -> PackedFloat32Array:
	var board: Array = st["board"] as Array
	var hand: Array = st["hand"] as Array
	var units: float = units_of(st["supplies"] as Dictionary)
	var income: float = 0.0
	var capacity: int = 0
	var ship: int = 0
	var opt_value: float = 0.0
	var wu: float = unit_vp(gen_start)
	var wh: float = card_vp(gen_start)
	for e_v: Variant in board:
		var e: Dictionary = e_v as Dictionary
		var n_techs: int = (e.get("techs", []) as Array).size()
		for c: int in BotScoring.slot_effective_placed_colors(e):
			income += U[clampi(c, 0, 5)]
		ship += 1 + n_techs
		capacity += maxi(0, CAP - n_techs)
		opt_value += opt_potential(e, board.size(), wu, wh)
	var open_sectors: int = MAX_SECTORS - board.size()
	var n_hand: float = float(hand.size())
	if advance:
		units += income
		n_hand += 6.0
	var hand_stars: float = 0.0
	for cd_v: Variant in hand:
		var cd: CardData = cd_v as CardData
		if cd.trigger_type == CardData.TriggerType.SCORE:
			hand_stars += float(cd.stars)
	# what the cards still to come would add through the ship's own multipliers (expeditions, the
	# "6 complete sectors" techs): the ship filled up as far as the game still allows, scored
	var gens_left: int = ROUNDS + 1 - gen_start
	var fill: int = mini(capacity + CAP * open_sectors, 6 * gens_left)
	var synergy: float = float(BotScoring.board_vp(project(board, fill, open_sectors)) - BotScoring.board_vp(board))
	return PackedFloat32Array([1.0, units, income, n_hand, float(capacity), float(open_sectors), synergy, hand_stars, opt_value, float(ship)])

## What a unit of supply / a card in hand is worth at the start of Generation gen_start (the fitted
## weights; past the last Generation, nothing).
static func unit_vp(gen_start: int) -> float:
	return float((W[gen_start] as Array)[1]) if W.has(gen_start) else 0.0

static func card_vp(gen_start: int) -> float:
	return float((W[gen_start] as Array)[3]) if W.has(gen_start) else 0.0

## What a sector's optimize effects still to come are worth: each level's effect, by how far along its
## colours are (a quarter for the bare level, the rest as its colours arrive), as long as the sector has
## room for the missing ones. This is what makes a bot work toward Habitation Ring's 8 Dust or an
## advanced sector's three levels instead of spreading cards anywhere.
static func opt_potential(e: Dictionary, n_sectors: int, wu: float, wh: float) -> float:
	var sector: CardData = e.get("sector") as CardData
	var max_opt: int = int(e.get("max_optimizations", 0))
	if sector == null or int(e.get("optimize_count", 0)) >= max_opt:
		return 0.0
	var room: int = CAP - (e.get("techs", []) as Array).size()
	if room <= 0:
		return 0.0
	var is_adv: bool = bool(e.get("is_advanced", false))
	var reqs: Array = [sector.adv_opt1_req, sector.adv_opt2_req, sector.adv_opt3_req] if is_adv else [sector.opt1_req]
	var triggered: Array = e.get("triggered_levels", []) as Array
	var pool: Array[int] = BotScoring.slot_tech_colors(e)
	var steps: Array[Dictionary] = SectorEffects.get_optimize_steps_for_state(sector, is_adv, BotScoring.slot_effective_placed_colors(e), 2)
	var val: float = steps_vp(steps, n_sectors, wu, wh)
	var total: float = 0.0
	for i: int in reqs.size():
		var req: Array[int] = []
		req.assign(reqs[i] as Array)
		if req.is_empty():
			break
		if i < triggered.size() and bool(triggered[i]):
			OptimizeLogic.consume_from_pool(pool, req)
			continue
		var matched: int = 0
		for m: bool in OptimizeLogic.matched_indices(pool, req):
			if m:
				matched += 1
		var missing: int = req.size() - matched
		if missing > room:
			break
		room -= missing
		total += val * (0.25 + 0.75 * float(matched) / float(req.size()))
		OptimizeLogic.consume_from_pool(pool, req)
	return total

## Effect steps in points: supply at wu a unit, cards at wh each, stores and archives at what they score.
static func steps_vp(steps: Array[Dictionary], n_sectors: int, wu: float, wh: float) -> float:
	var v: float = 0.0
	for step: Dictionary in steps:
		match str(step.get("type", "")):
			"draw":
				v += float(step.get("count", 1)) * wh
			"draw_all_players", "interfleet_comms":
				v += float(step.get("count", 1)) * wh * 0.6
			"draw_recycle_top":
				v += 1.5 * wu
			"gain_supply":
				v += float(step.get("amount", 1)) * U[clampi(int(step.get("color", 0)), 0, 5)] * wu
			"gain_supply_per_sector_count":
				v += float(n_sectors) * U[clampi(int(step.get("color", 0)), 0, 5)] * wu
			"gain_supply_per_stored":
				v += 1.5 * wu
			"store_on_slot", "store_on_any_sector":
				v += float(step.get("amount", 1))
			"store_per_card_here":
				v += 3.0
			"tuck":
				v += float(step.get("count", 1)) * ((2.0 if bool(step.get("face_up", false)) else 1.0) - 0.5 * wh)
			"tuck_optional", "tuck_any_sector_optional":
				v += float(step.get("max", 1)) * 0.5
			"recycle", "recycle_optional", "recycle_double":
				v += 0.4
			"fuse_notice":
				v += float(step.get("count", 1)) * 0.5 * wu
			"fuse_dust_1to1":
				v += 1.5 * wu
			"choice":
				var best: float = 0.0
				for o_v: Variant in (step.get("options", []) as Array):
					best = maxf(best, steps_vp(BotScoring.to_dict_array((o_v as Dictionary).get("steps", []) as Array), n_sectors, wu, wh))
				v += best
			_:
				v += 0.6   # reveals and offers: a look at more of the market
	return v

## The hand-made forecast (before there were fitted weights; --bv-model=0).
static func forecast(st: Dictionary, gen: int) -> float:
	var board: Array = st["board"] as Array
	var units: float = units_of(st["supplies"] as Dictionary)
	var hand: Array = st["hand"] as Array
	var income: float = 0.0
	var capacity: float = 0.0
	for e_v: Variant in board:
		var e: Dictionary = e_v as Dictionary
		for c: int in BotScoring.slot_effective_placed_colors(e):
			income += U[clampi(c, 0, 5)]
		capacity += float(maxi(0, CAP - (e.get("techs", []) as Array).size()))
	var open_sectors: int = MAX_SECTORS - board.size()
	var cards: float = float(hand.size())
	var placed: float = 0.0
	var new_sectors: int = 0
	var expeditions: float = 0.0
	var cost_u: float = kf("cost", COST_U)
	var rec_u: float = kf("rec", REC_U)
	var exp_cost: float = kf("expcost", EXP_COST_U)
	for _g: int in range(gen + 1, ROUNDS + 1):
		units += income
		cards += 6.0
		# sectors first (room for five cards each, and they earn too), keeping supply for cards
		var buy: int = mini(open_sectors, mini(2, int(units / 4.0)))
		open_sectors -= buy
		new_sectors += buy
		units -= 2.0 * float(buy)
		capacity += float(CAP * buy)
		# an expedition a Generation, if there is supply and room for it: the best points for supply there are
		var exp_n: float = minf(1.0, minf(units / exp_cost, capacity))
		expeditions += exp_n
		units -= exp_cost * exp_n
		capacity -= exp_n
		# every card is placed (cost_u) or recycled (rec_u): placements = what supply and cards allow
		var n: float = minf(kf("playable", PLAYABLE) * cards, (units + rec_u * cards) / (cost_u + rec_u))
		n = clampf(n, 0.0, capacity)
		placed += n
		capacity -= n
		units = maxf(0.0, units + rec_u * (cards - n) - cost_u * n)
		cards = 0.0
		income += kf("inc", INC_U) * (n + exp_n) + float(buy)
	var v: float = float(BotScoring.board_vp(project(board, int(round(placed + expeditions)), new_sectors)))
	v += kf("cardvp", CARD_VP) * placed + kf("expvp", EXP_VP) * expeditions + 0.05 * units
	# starred cards in hand are worth more than the average card the forecast assumes
	for cd_v: Variant in hand:
		var cd: CardData = cd_v as CardData
		if cd.stars > 0 and cd.trigger_type == CardData.TriggerType.SCORE:
			v += maxf(0.0, float(cd.stars) - CARD_VP) * kf("handstar", 0.7)
	return v

## The ship with n_sectors more sectors and n_cards more cards on it: the fullest stacks first
## (complete sectors are what the big cards pay for), each card in the colour its sector's optimize
## still needs.
static func project(board: Array, n_cards: int, n_sectors: int) -> Array:
	var out: Array = BotAI.BotValue.copy_board(board)
	for _i: int in mini(n_sectors, MAX_SECTORS - out.size()):
		out.append(BotAI.BotValue._virtual_sector())
	var order: Array[int] = []
	for i: int in out.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return ((out[a] as Dictionary)["techs"] as Array).size() > ((out[b] as Dictionary)["techs"] as Array).size())
	var left: int = n_cards
	for i: int in order:
		if left <= 0:
			break
		var slot: Dictionary = out[i] as Dictionary
		var techs: Array = slot["techs"] as Array
		var added: bool = false
		while techs.size() < CAP and left > 0:
			techs.append(BotAI.BotValue._virtual_card(BotAI.BotValue._needed_color(slot)))
			left -= 1
			added = true
		if added:
			BotTurn._bot_update_optimize(slot, BotScoring.slot_tech_colors(slot))
	return out

# ── Candidate plays ─────────────────────────────────────────────────────────────

## What a hand card is worth keeping (the cheapest are recycled first to pay for others).
static func keep_value(cd: CardData) -> float:
	if BotTurn.is_unknown(cd):
		return 0.9
	var v: float = 0.0
	if cd.trigger_type == CardData.TriggerType.SCORE:
		v += float(cd.stars)
	else:
		v += 1.0 + float(cd.stars)
	return v - 0.2 * float(cd.cost)

## The fuses and recycles that let supplies pay cost of color: {ok, steps}. spare: the card being
## played (never recycled for itself).
static func pay_plan(st: Dictionary, color: int, cost: int, spare: CardData) -> Dictionary:
	var work: Dictionary = (st["supplies"] as Dictionary).duplicate()
	if BotAI.can_pay(work, color, cost):
		return {ok = true, steps = []}
	var steps: Array = []
	var pool: Array[CardData] = []
	pool.assign(st["hand"] as Array)
	if spare != null:
		pool.erase(spare)
	pool.sort_custom(func(a: CardData, b: CardData) -> bool: return keep_value(a) < keep_value(b))
	var recycled: int = 0
	for _i: int in 14:
		if BotAI.can_pay(work, color, cost):
			return {ok = true, steps = steps}
		var f: Dictionary = BotAI._fuse_step_toward(color, work, 3)
		if not f.is_empty():
			work[int(f["source"])] = int(work.get(int(f["source"]), 0)) - 2
			work[int(f["target"])] = int(work.get(int(f["target"]), 0)) + 1
			steps.append({fuse = f})
			continue
		var pick: CardData = null
		for c: CardData in pool:
			if BotAI._feeds(int(c.color), color):
				pick = c
				break
		if pick == null or recycled >= int(kf("maxrec", 4.0)):
			return {ok = false}
		work[int(pick.color)] = int(work.get(int(pick.color), 0)) + CardData.recycle_amount(pick)
		pool.erase(pick)
		recycled += 1
		steps.append({recycle = pick})
	return {ok = false}

# Sectors that would treat a new card alike (same sector, same cards in the same order) need trying once.
static func _slot_signature(slot: Dictionary) -> String:
	var sector: CardData = slot.get("sector") as CardData
	var sig: String = (sector.card_name if sector else "") + ("A" if bool(slot.get("is_advanced", false)) else "D")
	for t: Variant in (slot.get("techs", []) as Array):
		sig += "|" + ((t as CardData).card_name if t is CardData else "x")
	sig += "#%d#%d" % [BotScoring.slot_total_stored(slot), (slot.get("tucked_cards", []) as Array).size()]
	return sig

## Every play worth trying from st. market: {dust, adv, exp} (Array[CardData] each), taken: cards of it
## this line of play already bought.
static func candidates(st: Dictionary, market: Dictionary, taken: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var board: Array = st["board"] as Array
	var hand: Array = st["hand"] as Array
	var open_slots: Array[int] = []
	var sigs: Dictionary = {}
	for i: int in board.size():
		var slot: Dictionary = board[i] as Dictionary
		if (slot.get("techs", []) as Array).size() >= CAP:
			continue
		var sig: String = _slot_signature(slot)
		if sigs.has(sig):
			continue
		sigs[sig] = true
		open_slots.append(i)
	var seen: Dictionary = {}
	for cd_v: Variant in hand:
		var cd: CardData = cd_v as CardData
		if BotTurn.is_unknown(cd) or cd.card_type != CardData.CardType.TECH or seen.has(cd.card_name):
			continue
		seen[cd.card_name] = true
		for i: int in open_slots:
			var pay: Dictionary = pay_plan(st, int(cd.color), BotAI.tech_cost(cd, board, i), cd)
			if bool(pay["ok"]):
				out.append({type = "place_tech", card = cd, slot_idx = i, free = pay["steps"]})
	if board.size() < MAX_SECTORS:
		var names: Dictionary = {}
		for cd: CardData in (market["dust"] as Array[CardData]):
			if names.has(cd.card_name) or taken.has(cd):
				continue
			names[cd.card_name] = true
			var pay: Dictionary = pay_plan(st, int(cd.color), maxi(0, cd.cost), null)
			if bool(pay["ok"]):
				out.append({type = "buy_sector", card = cd, free = pay["steps"]})
		for cd: CardData in (market["adv"] as Array[CardData]):
			if taken.has(cd):
				continue
			var price: int = maxi(0, cd.adv_cost) + PREMIUM
			var pay: Dictionary = pay_plan(st, int(cd.adv_color), price, null)
			if bool(pay["ok"]):
				out.append({type = "win_adv_sector", card = cd, price = price, color = int(cd.adv_color), free = pay["steps"]})
	for cd: CardData in (market["exp"] as Array[CardData]):
		if taken.has(cd):
			continue
		var price: int = maxi(0, cd.cost) + PREMIUM
		var pay: Dictionary = pay_plan(st, int(cd.color), price, null)
		if not bool(pay["ok"]):
			continue
		for i: int in open_slots:
			out.append({type = "win_expedition", card = cd, slot_idx = i, price = price, color = int(cd.color), free = pay["steps"]})
	return out

# ── The search ──────────────────────────────────────────────────────────────────

static var _feat_logged: Dictionary = {}

## The best outlook reachable from root within depth plays, and the first play of that line:
## {v, first, tried, base}. A beam search: every candidate play of the `width` best positions so far is
## tried in the sandbox. A coroutine: the work is spread over frames (SLICE_MSEC each), so the caller
## must check afterwards that the game has not moved on.
static func search(main: Main, bot_id: int, root: Dictionary, gen: int, market: Dictionary, width: int, depth: int) -> Dictionary:
	var base: float = evaluate(root, gen)
	var best_v: float = base
	var best_first: Dictionary = {}
	var beam: Array = [{"st": root, "first": {}, "taken": [], "v": base}]
	var t0: int = Time.get_ticks_msec()
	var tried: int = 0
	for _d: int in depth:
		var next: Array = []
		for node_v: Variant in beam:
			var node: Dictionary = node_v as Dictionary
			for a: Dictionary in candidates(node["st"] as Dictionary, market, node["taken"] as Array):
				var st2: Dictionary = BotTurn.sim_apply(main, bot_id, node["st"] as Dictionary, a)
				var v: float = evaluate(st2, gen)
				tried += 1
				var first: Dictionary = node["first"] as Dictionary
				if first.is_empty():
					first = a
				var taken: Array = node["taken"] as Array
				if str(a["type"]) != "place_tech":
					taken = taken.duplicate()
					taken.append(a["card"])
				next.append({"st": st2, "first": first, "taken": taken, "v": v})
				if v > best_v:
					best_v = v
					best_first = first
				if Time.get_ticks_msec() - t0 >= SLICE_MSEC:
					await main.get_tree().process_frame
					t0 = Time.get_ticks_msec()
		if next.is_empty():
			break
		next.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["v"]) > float(q["v"]))
		beam = next.slice(0, width)
	return {v = best_v, first = best_first, tried = tried, base = base}

static func market_of(main: Main, without: CardData = null) -> Dictionary:
	var board_node: Node = main.get_node("Board")
	var market: Dictionary = {
		"dust": board_node.get_available_dust_sectors(),
		"adv": board_node.get_available_advanced_sectors(),
		"exp": board_node.get_available_expeditions(),
	}
	if without != null:
		(market["adv"] as Array).erase(without)
		(market["exp"] as Array).erase(without)
	return market

## The bot's turn: {action: {type, card?, slot_idx?}, free: [fuses/recycles]} as BotAI.plan_turn.
## A coroutine (see search).
static func plan(main: Main, bot_id: int, difficulty: int) -> Dictionary:
	var gen: int = main._round
	var cfg: Dictionary = config(difficulty, gen)
	Scoring.other_players_expeditions = main._alliance_count_for(bot_id)
	var root: Dictionary = state_of(main, bot_id)
	if OS.get_cmdline_user_args().has("--botsim-trace") and not _feat_logged.has("%d/%d" % [bot_id, gen]):
		_feat_logged["%d/%d" % [bot_id, gen]] = true
		var fs: PackedStringArray = []
		for x: float in features(root, gen, false):
			fs.append("%.2f" % x)
		print("FEAT g%d %s vp %d | %s" % [gen, GameNetwork.player_names.get(bot_id, "?"), BotScoring.board_vp(root["board"] as Array), " ".join(fs)])
	var found: Dictionary = await search(main, bot_id, root, gen, market_of(main), int(cfg["width"]), int(cfg["depth"]))
	if GameNetwork.active_peer_id != bot_id or bool(main.get("_game_finished")):
		return {action = {type = "pass"}, free = []}
	var best_first: Dictionary = found["first"] as Dictionary
	if OS.get_cmdline_user_args().has("--botsim-trace"):
		print("PLAN g%d %s base %.1f best %.1f (%d tried) -> %s %s" % [gen, GameNetwork.player_names.get(bot_id, "?"),
				float(found["base"]), float(found["v"]), int(found["tried"]), str(best_first.get("type", "-")),
				(best_first["card"] as CardData).card_name if best_first.has("card") else ""])
	if best_first.is_empty() or float(found["v"]) < float(found["base"]) + kf("mingain", MIN_GAIN):
		return {action = _idle_action(root, gen), free = []}
	var action: Dictionary = best_first.duplicate()
	match str(action["type"]):
		"win_expedition":
			action["type"] = "start_auction"
		"win_adv_sector":
			action["type"] = "start_auction_adv"
	return {action = action, free = best_first.get("free", [])}

# Nothing worth its supply: research away the card worth least (a soft pass: it brings a new card and
# the bot is asked again while others play on), or pass with an empty hand.
static func _idle_action(st: Dictionary, gen: int = 1) -> Dictionary:
	var worst: CardData = null
	for cd_v: Variant in (st["hand"] as Array):
		var cd: CardData = cd_v as CardData
		if worst == null or keep_value(cd) < keep_value(worst):
			worst = cd
	# in the last Generation a card the bot can't play is worth nothing: with supply left, any goes
	var last_dig: bool = gen >= ROUNDS and units_of(st["supplies"] as Dictionary) >= 2.0
	if worst == null or (keep_value(worst) > kf("junk", 1.4) and not last_dig):
		return {type = "pass"}   # (a hand of good cards is kept for the next Generation)
	return {type = "research", card = worst}

# ── Auctions ────────────────────────────────────────────────────────────────────

## What winning cd at price (paid in color) would leave the bot with: the best outlook over the sectors
## it could go on ({v, slot_idx}; v = -INF when it can't be placed or paid).
static func win_value(main: Main, bot_id: int, st: Dictionary, cd: CardData, is_adv: bool, price: int, color: int, gen: int) -> Dictionary:
	var board: Array = st["board"] as Array
	if not BotAI.can_pay(st["supplies"] as Dictionary, color, price):
		return {v = -INF, slot_idx = -1}
	if is_adv or cd.card_type == CardData.CardType.SECTOR:
		if board.size() >= MAX_SECTORS:
			return {v = -INF, slot_idx = -1}
		var st2: Dictionary = BotTurn.sim_apply(main, bot_id, st, {type = "win_adv_sector", card = cd, price = price, color = color})
		return {v = evaluate(st2, gen), slot_idx = -1}
	var best: Dictionary = {v = -INF, slot_idx = -1}
	var sigs: Dictionary = {}
	for i: int in board.size():
		var slot: Dictionary = board[i] as Dictionary
		if (slot.get("techs", []) as Array).size() >= CAP:
			continue
		var sig: String = _slot_signature(slot)
		if sigs.has(sig):
			continue
		sigs[sig] = true
		var st2: Dictionary = BotTurn.sim_apply(main, bot_id, st, {type = "win_expedition", card = cd, slot_idx = i, price = price, color = color})
		var v: float = evaluate(st2, gen)
		if v > float(best["v"]):
			best = {v = v, slot_idx = i}
	return best

## Raise to next_bid? Yes while winning at that price still leaves the bot better off than not winning,
## each judged by what the bot could go on to do this Generation (a short search from both positions:
## judged as they stand, supply still in hand counted for nothing in the last Generation, and a bot paid
## 8 Metals for a 3-point card). A coroutine (see search).
static func should_bid(main: Main, bot_id: int, cd: CardData, is_adv: bool, next_bid: int, color: int) -> bool:
	var gen: int = main._round
	Scoring.other_players_expeditions = main._alliance_count_for(bot_id)
	var st: Dictionary = state_of(main, bot_id)
	var win: Dictionary = win_value(main, bot_id, st, cd, is_adv, next_bid, color, gen)
	if float(win["v"]) == -INF:
		return false
	var market: Dictionary = market_of(main, cd)
	var action: Dictionary = {type = "win_adv_sector", card = cd, price = next_bid, color = color}
	if int(win["slot_idx"]) >= 0:
		action = {type = "win_expedition", card = cd, slot_idx = int(win["slot_idx"]), price = next_bid, color = color}
	var st_win: Dictionary = BotTurn.sim_apply(main, bot_id, st, action)
	var w: int = int(kf("bw", 2.0))
	var d: int = int(kf("bd", 3.0))
	var with_card: Dictionary = await search(main, bot_id, st_win, gen, market, w, d)
	var without: Dictionary = await search(main, bot_id, st, gen, market, w, d)
	return float(with_card["v"]) > float(without["v"]) + kf("bidmargin", 0.5)

## The sector a won expedition goes on (-1: none has room).
static func best_slot(main: Main, bot_id: int, cd: CardData) -> int:
	Scoring.other_players_expeditions = main._alliance_count_for(bot_id)
	var win: Dictionary = win_value(main, bot_id, state_of(main, bot_id), cd, false, 0, int(cd.color), main._round)
	return int(win["slot_idx"])
