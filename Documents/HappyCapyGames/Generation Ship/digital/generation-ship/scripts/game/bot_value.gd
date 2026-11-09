extends RefCounted
## How much a play is worth to a Hard (and, with less foresight, a Normal) bot, in final victory points
## (2026-11-09). The old valuation was printed stars x2: bots chased stars, the smallest source of points,
## and ended near 20 while good players score 65-100 - a 97-point game: 67 from seven expeditions, 25 from
## archived cards, 5 from stars and stored supply. Expeditions and Atmosphere Processor & co. pay for the ship
## they end up on, so a play is valued by what it adds to the bot's PROJECTED FINAL score: the board as it
## will likely look after Generation 4 (stacks filled toward five cards in the colours their optimize still
## needs, the remaining sector slots filled at the pace the bots play), scored by the game's own rules
## (BotScoring.board_vp). Plus the supply the card earns each Generation left, plus its effects, minus the
## supply it costs, which is worth less and less as the game nears its end. Tuned with tools/bot_league.py.
## Preloaded by BotAI (no class_name).

const ROUNDS: int = 4
const CARDS_PER_GEN: float = 6.0     # cards a bot places per Generation, roughly (projection pace)
const SECTORS_PER_GEN: float = 1.5   # sectors it adds per Generation, up to six
# one supply's worth in VP during Generation n: it buys cards early, it buys nothing after the game
const SUPPLY_VP: Array[float] = [0.0, 0.55, 0.45, 0.35, 0.2]
const EFFECT_W: float = 1.0          # steps_value of a placed card's own Place effect
const SECTOR_W: float = 1.5          # a sector's room for five more cards and its optimize effects
const ADV_LEVEL_W: float = 1.0       # each optimize level of an advanced sector
# a supply's worth by colour (Metals = 1): fusing is 2:1 up each chain, Dust -> Metals/Liquids ->
# Electrix/Organix -> Thrust (CardData.SupplyColor order: Dust, Metals, Liquids, Organix, Electrix, Thrust)
const COLOR_W: Array[float] = [0.5, 1.0, 1.0, 2.0, 2.0, 4.0]

static func color_w(color: int) -> float:
	return COLOR_W[clampi(color, 0, COLOR_W.size() - 1)]

static func supply_vp(gen: int) -> float:
	return SUPPLY_VP[clampi(gen, 0, ROUNDS)] * k("sv", 1.0)

# tuning overrides for tools/bot_league.py: --bv-<name>=<value> on the command line (cached)
static var _k: Dictionary = {}
static var _k_read: bool = false

static func k(name: String, fallback: float) -> float:
	if not _k_read:
		_k_read = true
		for a: String in OS.get_cmdline_user_args():
			if a.begins_with("--bv-") and a.contains("="):
				_k[a.trim_prefix("--bv-").get_slice("=", 0)] = float(a.get_slice("=", 1))
	return float(_k.get(name, fallback))

## VP of the supply one card on the ship still earns: one of its colour at the end of this Generation and
## every later one, each spent in the Generation after (the last one's buys nothing).
static func income_vp(gen: int) -> float:
	var v: float = 0.0
	for g: int in range(gen + 1, ROUNDS + 1):
		v += supply_vp(g)
	return v * k("inc", 1.0)

## The bot's projected final score for this board in Generation gen. foresight 1 (Hard) projects the full
## remaining game, less looks at the board more as it is.
static func projected_vp(board: Array, gen: int, foresight: float = 1.0) -> float:
	return float(BotScoring.board_vp(project(board, gen, foresight)))

static func project(board: Array, gen: int, foresight: float = 1.0) -> Array:
	var left: float = maxf(0.0, (float(ROUNDS - gen) + 0.5) * foresight)   # Generations of play left
	var out: Array = copy_board(board)
	var new_sectors: int = mini(6 - out.size(), int(round(SECTORS_PER_GEN * left)))
	for _i: int in maxi(0, new_sectors):
		out.append(_virtual_sector())
	var cards: int = int(round(k("cpg", CARDS_PER_GEN) * left))
	# the fullest stacks first: complete sectors are what Atmosphere Processor, Millions of Colonists and
	# Asteroid Colonies pay for
	var order: Array[int] = []
	for i: int in out.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return ((out[a] as Dictionary)["techs"] as Array).size() > ((out[b] as Dictionary)["techs"] as Array).size())
	for i: int in order:
		if cards <= 0:
			break
		var slot: Dictionary = out[i] as Dictionary
		var techs: Array = slot["techs"] as Array
		while techs.size() < BotAI.TECH_CAPACITY and cards > 0:
			techs.append(_virtual_card(_needed_color(slot)))
			cards -= 1
		BotTurn._bot_update_optimize(slot, BotScoring.slot_tech_colors(slot))
	return out

## A copy deep enough to add cards, archives and stored supply to without touching the real board.
static func copy_board(board: Array) -> Array:
	var out: Array = []
	for e_v: Variant in board:
		out.append(copy_slot(e_v as Dictionary))
	return out

static func copy_slot(e: Dictionary) -> Dictionary:
	var c: Dictionary = e.duplicate()
	c["techs"] = (e.get("techs", []) as Array).duplicate()
	c["tucked_cards"] = (e.get("tucked_cards", []) as Array).duplicate()
	c["stored_supply"] = (e.get("stored_supply", {}) as Dictionary).duplicate()
	var tl: Array[bool] = []
	for b: Variant in (e.get("triggered_levels", []) as Array):
		tl.append(bool(b))
	c["triggered_levels"] = tl
	return c

## board with card placed on slot slot_idx (optimize state updated, effects not resolved).
static func with_card(board: Array, slot_idx: int, card: CardData) -> Array:
	var out: Array = copy_board(board)
	if slot_idx < 0 or slot_idx >= out.size():
		return out
	var slot: Dictionary = out[slot_idx] as Dictionary
	(slot["techs"] as Array).append(card)
	BotTurn._bot_update_optimize(slot, BotScoring.slot_tech_colors(slot))
	return out

static func with_sector(board: Array, card: CardData, is_adv: bool) -> Array:
	var out: Array = copy_board(board)
	out.append(BotTurn._new_slot_entry(card, is_adv))
	return out

## The slot where card adds the most to the projected final score (-1: no room anywhere).
static func best_slot(board: Array, card: CardData, gen: int, foresight: float = 1.0) -> int:
	var best: int = -1
	var best_v: float = -INF
	for i: int in board.size():
		if ((board[i] as Dictionary).get("techs", []) as Array).size() >= BotAI.TECH_CAPACITY:
			continue
		var v: float = projected_vp(with_card(board, i, card), gen, foresight)
		v += optimize_payoff(board[i] as Dictionary, card, gen)
		if v > best_v:
			best_v = v
			best = i
	return best

## What a play is worth, in final VP, before paying for it (base: projected_vp(board), computed once).
static func gain(play: Dictionary, board: Array, gen: int, foresight: float, base: float) -> float:
	var card: CardData = play["card"] as CardData
	match str(play.get("type", "")):
		"place_tech":
			var slot_idx: int = int(play.get("slot_idx", -1))
			if slot_idx < 0 or slot_idx >= board.size():
				return -INF
			var slot: Dictionary = board[slot_idx] as Dictionary
			var v: float = projected_vp(with_card(board, slot_idx, card), gen, foresight) - base
			v += income_vp(gen) * color_w(int(card.color)) + EFFECT_W * place_payoff(slot, card, gen)
			v += optimize_payoff(slot, card, gen)
			return v
		"buy_sector":
			return projected_vp(with_sector(board, card, false), gen, foresight) - base \
					+ income_vp(gen) * color_w(int(card.color)) + k("sec", SECTOR_W)
		"buy_adv_sector", "start_auction_adv":
			return projected_vp(with_sector(board, card, true), gen, foresight) - base \
					+ income_vp(gen) * color_w(int(card.adv_color)) + k("sec", SECTOR_W) \
					+ k("adv", ADV_LEVEL_W) * float(OptimizeLogic.max_optimizations(card, true))
		"start_auction":
			var s: int = best_slot(board, card, gen, foresight)
			if s < 0:
				return -INF
			return projected_vp(with_card(board, s, card), gen, foresight) - base + income_vp(gen) * color_w(int(card.color))
	return 0.0

## A play's net worth: its gain minus the supply it costs now (by the colour it is paid in).
static func value(play: Dictionary, board: Array, gen: int, foresight: float, base: float) -> float:
	var card: CardData = play["card"] as CardData
	var cost: int = int(play.get("cost", maxi(0, card.cost)))
	var color: int = int(play.get("color", int(card.color)))
	return gain(play, board, gen, foresight, base) - float(cost) * supply_vp(gen) * color_w(color)

## What card's own Place effect is worth, placed on slot (BotAI._tech_effect_payoff, by steps_value).
static func place_payoff(slot: Dictionary, card: CardData, gen: int) -> float:
	var sim: Dictionary = copy_slot(slot)
	(sim["techs"] as Array).append(card)
	var steps: Array[Dictionary] = PlaceEffects.get_steps_for_state(
		card, BotScoring.is_slot_new(sim), BotScoring.is_slot_complete(sim),
		BotScoring.is_slot_optimized(sim), BotScoring.slot_effective_placed_colors(sim))
	return steps_value(steps, gen)

## What placing card on slot is worth through the optimize level(s) it triggers: that level's effect
## (the bots resolve the same SectorEffects steps) plus a little for the optimized state itself.
static func optimize_payoff(slot: Dictionary, card: CardData, gen: int) -> float:
	if not BotAI._would_trigger_optimize(slot, card):
		return 0.0
	var sector: CardData = slot.get("sector") as CardData
	if sector == null:
		return 0.0
	var sim: Dictionary = copy_slot(slot)
	(sim["techs"] as Array).append(card)
	var steps: Array[Dictionary] = SectorEffects.get_optimize_steps_for_state(
		sector, bool(slot.get("is_advanced", false)), BotScoring.slot_effective_placed_colors(sim), card.cost)
	return OPTIMIZE_BASE + steps_value(steps, gen)

const OPTIMIZE_BASE: float = 1.0
# a card in hand, in VP, by Generation: more turns to play it early, little left to do with it at the end
const CARD_VP: Array[float] = [0.0, 1.5, 1.2, 0.8, 0.3]

## Effect steps in final VP (BotScoring.effect_payoff's counts, weighted by colour and Generation).
static func steps_value(steps: Array[Dictionary], gen: int) -> float:
	var v: float = 0.0
	var card_vp: float = CARD_VP[clampi(gen, 0, ROUNDS)] * k("card", 1.0)
	for step: Dictionary in steps:
		match str(step.get("type", "")):
			"draw", "draw_recycle_top", "draw_all_players":
				v += float(step.get("count", 1)) * card_vp
			"gain_supply", "gain_supply_per_stored", "gain_supply_per_sector_count":
				v += float(step.get("amount", 1)) * supply_vp(gen) * color_w(int(step.get("color", 1)))
			"store_on_slot", "store_on_any_sector", "store_per_card_here":
				v += float(step.get("amount", 1))   # 1 VP each at the end (and Polar Planet & co.)
			"tuck":
				v += float(step.get("count", 1)) * (1.5 if bool(step.get("face_up", false)) else 1.0)
			"tuck_optional", "tuck_any_sector_optional":
				v += float(step.get("max", 1)) * 0.8
			"recycle_optional":
				v += float(step.get("max", 1)) * 0.3
			"fuse_notice":
				v += float(step.get("count", 1)) * 0.3
			"choice":
				var best: float = 0.0
				for o_v: Variant in (step.get("options", []) as Array):
					best = maxf(best, steps_value(BotScoring.to_dict_array((o_v as Dictionary).get("steps", []) as Array), gen))
				v += best
	return v

## The highest bid worth paying for an auctioned card (in supply), 0 if none.
static func max_bid(card: CardData, is_adv: bool, board: Array, gen: int, foresight: float) -> int:
	var play: Dictionary = {"type": "start_auction_adv" if is_adv else "start_auction", "card": card}
	var g: float = gain(play, board, gen, foresight, projected_vp(board, gen, foresight))
	if g <= 0.0:
		return 0
	var color: int = int(card.adv_color if is_adv else card.color)
	return int(floor(g / maxf(supply_vp(gen) * color_w(color), 0.05)))

# The colour a sector's optimize still needs most (its next unmet level's first missing colour), else the
# colour the sector shows.
static func _needed_color(slot: Dictionary) -> int:
	var sector: CardData = slot.get("sector") as CardData
	if sector == null:
		return int(CardData.SupplyColor.DUST)
	var adv: bool = bool(slot.get("is_advanced", false))
	var shown: int = int(sector.adv_color if adv else sector.color)
	var reqs: Array = [sector.adv_opt1_req, sector.adv_opt2_req, sector.adv_opt3_req] if adv else [sector.opt1_req]
	var pool: Array[int] = BotScoring.slot_tech_colors(slot)
	for r_v: Variant in reqs:
		var req: Array[int] = r_v as Array[int]
		if req.is_empty():
			break
		if OptimizeLogic.satisfies_optimize(pool, req):
			OptimizeLogic.consume_from_pool(pool, req)
			continue
		var tmp: Array[int] = pool.duplicate()
		for r: int in req:
			if r == CardData.OPTIMIZE_ANY:
				continue
			var k: int = tmp.find(r)
			if k >= 0:
				tmp.remove_at(k)
			else:
				return r
		return shown
	return shown

static var _vsector: CardData = null

static func _virtual_sector() -> Dictionary:
	if _vsector == null:
		_vsector = CardDatabase.sectors[0] if not CardDatabase.sectors.is_empty() else CardData.new()
	return BotTurn._new_slot_entry(_vsector, false)

# a stand-in for a card the bot will place later: its colour only, no stars, no name
static func _virtual_card(color: int) -> CardData:
	var cd: CardData = CardData.new()
	cd.card_type = CardData.CardType.TECH
	cd.color = color as CardData.SupplyColor
	cd.trigger_type = CardData.TriggerType.ALWAYS
	return cd
