extends RefCounted

## Quests (rulebook p25-26, Quests.csv - 25 Core cards). The Quest Action
## rolls the Hero Dice plus the card's bonus die when its printed condition
## holds (and any extra dice, e.g. Kyushi's Tavern's +1 blue), compares the
## symbols with each goal, and resolves the solve effect plus the reward of
## every goal met - or only the failure effect. Loaded with preload/load,
## no class_name.
##
## Card text decides what happens to the Quest afterwards: "Discard this
## Quest" discards it (no refill until the next Refresh Phase), "Gain this
## card" moves it in front of the player (PlayerFactionState.quests_in_play),
## anything else leaves it in the row. Cleanse the Wastes and Imperial
## Inquisition stay in the row across Refreshes until solved.
##
## Choices: the Guile dice colour and which Quest Kyushi's Tavern attempts
## come from a quick simulation of the odds; "You may draw a new Quest" /
## "You may discard any Items from the Market" are declined (the rulebook
## warns that new Quests can bite), targets follow NemesisAI.pick_hex.
## Feats aren't tracked as cards, so Feat rewards are only logged.

const NemesisCards := preload("res://scripts/game/nemesis_cards.gd")

const STAY_UNTIL_SOLVED: Array[String] = ["Cleanse the Wastes", "Imperial Inquisition"]
## No dice goals: a persistent effect, or a board condition.
const NO_ROLL: Array[String] = ["Break the Shackles", "Cleanse the Wastes"]
const SYMBOLS: Array[String] = ["Skull", "Shield", "Bolt"]


static func card(card_db: Node, quest_name: String) -> QuestCard:
	if card_db == null:
		return null
	for q: QuestCard in card_db.quests:
		if q.card_name == quest_name:
			return q
	return null


static func _num(s: String) -> int:
	var t: String = s.strip_edges()
	return t.to_int() if t.is_valid_int() else -1


## {"successes": n, "Skull": n, "Shield": n, "Bolt": n}; -1 = no such goal.
static func goals(q: QuestCard) -> Dictionary:
	return {"successes": maxi(1, _num(q.successes)), "Skull": _num(q.skulls), "Shield": _num(q.shields), "Bolt": _num(q.bolts)}


static func _reward_text(q: QuestCard, symbol: String) -> String:
	match symbol:
		"Skull":
			return q.skull_bonus
		"Shield":
			return q.shield_bonus
	return q.bolt_bonus


## The bonus die printed at the bottom of the card ("If your Hero is on a
## Woods hex +1 YELLOW"), when the Hero meets the condition.
static func bonus_dice(state: GameState, card_db: Node, p: PlayerFactionState, q: QuestCard) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile("\\+1\\s+(WHITE|YELLOW|BLUE|RED|PURPLE|BLACK)")
	var m: RegExMatch = re.search(q.terrain_bonus)
	if m == null:
		return out
	var cond: String = q.terrain_bonus.to_lower()
	var coord: Vector2i = p.hero_coord
	var tile: HexTileState = state.get_hex(coord)
	if tile == null:
		return out
	var terrain: String = EffectUtil.combat_terrain(tile, card_db)
	var nemesis: Array = EffectUtil.nemesis_at(state, coord)
	var has_horde: bool = false
	for n: Variant in nemesis:
		if n is HordeInstance:
			has_horde = true
	var ok: bool = false
	if cond.find("legion or horde") != -1:
		ok = not nemesis.is_empty()
	elif cond.find("horde") != -1:
		ok = has_horde
	elif cond.find("curse") != -1:
		ok = tile.curse
	elif cond.find("highland") != -1:
		ok = terrain == "Highlands"
	elif cond.find("woods") != -1:
		ok = terrain == "Woods"
	elif cond.find("marsh") != -1:
		ok = terrain == "Marshes"
	elif cond.find("badlands") != -1:
		ok = terrain == "Badlands"
	elif cond.find("ice waste") != -1:
		ok = terrain == "Ice Waste"
	elif cond.find("sea tower") != -1:
		ok = tile.role == "sea_tower"
	elif cond.find("capital") != -1:
		ok = tile.role == "capital"
	elif cond.find("garrison") != -1:
		ok = tile.garrison_level > 0
	elif cond.find("enemy units") != -1:
		ok = tile.garrison_level > 0 or tile.skeleton_count > 0 or not nemesis.is_empty()
	elif cond.find("2+ heros") != -1:
		var heroes: int = 0
		for other: PlayerFactionState in state.players:
			if other.hero_coord == coord:
				heroes += 1
		ok = heroes >= 2
	if ok:
		out.append(m.get_string(1).to_lower())
	return out


## Estimated chance of solving with a given dice pool (quick simulation).
static func success_chance(q: QuestCard, pool: Array[String], rng: RandomNumberGenerator, trials: int = 120) -> float:
	var g: Dictionary = goals(q)
	var wins: int = 0
	for _t: int in range(trials):
		var rolled: Dictionary = DiceModel.roll_pool(pool, rng)
		var met: int = 0
		for sym: String in SYMBOLS:
			if int(g[sym]) > 0 and int(rolled[sym]) >= int(g[sym]):
				met += 1
		if met >= int(g["successes"]):
			wins += 1
	return float(wins) / float(trials)


static func _pool(state: GameState, card_db: Node, p: PlayerFactionState, q: QuestCard, guile: String, extra: Array) -> Array[String]:
	var pool: Array[String] = DiceModel.hero_pool(EffectUtil.hero_card(card_db, p.hero_name), guile)
	pool.append_array(bonus_dice(state, card_db, p, q))
	for e: Variant in extra:
		pool.append(str(e))
	return pool


## The Guile colour (white or yellow) with the better odds for this Quest.
static func best_guile(state: GameState, card_db: Node, p: PlayerFactionState, q: QuestCard, extra: Array, rng: RandomNumberGenerator) -> String:
	var hero: HeroCard = EffectUtil.hero_card(card_db, p.hero_name)
	if hero == null or hero.guile == 0:
		return "yellow"
	var y: float = success_chance(q, _pool(state, card_db, p, q, "yellow", extra), rng)
	var w: float = success_chance(q, _pool(state, card_db, p, q, "white", extra), rng)
	return "white" if w > y else "yellow"


## The face-up Quest this player is likeliest to solve, "" if none can be rolled for.
static func best_quest_for(state: GameState, card_db: Node, faction: String, extra: Array = []) -> String:
	var p: PlayerFactionState = state.find_player(faction)
	if p == null:
		return ""
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var best: String = ""
	var best_odds: float = -1.0
	for name: String in state.quest_row:
		var q: QuestCard = card(card_db, name)
		if q == null or NO_ROLL.has(name):
			continue
		var odds: float = success_chance(q, _pool(state, card_db, p, q, best_guile(state, card_db, p, q, extra, rng), extra), rng)
		if odds > best_odds:
			best_odds = odds
			best = name
	return best


## The Quest Action's resolution. opts: "extra_dice" (Array of colours),
## "ignore_failure" (bool), "guile" (force a colour), "rng", "fixed_roll"
## ({Skull, Shield, Bolt} - tests). Returns {ok, solved, rolled, met, log}.
static func attempt(state: GameState, card_db: Node, faction: String, quest_name: String, opts: Dictionary = {}) -> Dictionary:
	var p: PlayerFactionState = state.find_player(faction)
	var q: QuestCard = card(card_db, quest_name)
	if p == null or q == null or not state.quest_row.has(quest_name):
		return {"ok": false, "reason": "that Quest is not face-up"}
	var ctx: EffectContext = _ctx(state, card_db, faction, opts)
	if quest_name == "Cleanse the Wastes":
		return _cleanse_the_wastes(ctx, q)
	if NO_ROLL.has(quest_name):
		return {"ok": false, "reason": "'%s' isn't solved with a roll" % quest_name}

	var extra: Array = opts.get("extra_dice", [])
	var guile: String = str(opts.get("guile", best_guile(state, card_db, p, q, extra, ctx.rng)))
	var pool: Array[String] = _pool(state, card_db, p, q, guile, extra)
	var rolled: Dictionary = opts.get("fixed_roll", DiceModel.roll_pool(pool, ctx.rng))
	var g: Dictionary = goals(q)
	var met: Array[String] = []
	for sym: String in SYMBOLS:
		if int(g[sym]) > 0 and int(rolled.get(sym, 0)) >= int(g[sym]):
			met.append(sym)
	var solved: bool = met.size() >= int(g["successes"])
	ctx.log("%s attempts '%s' with %s: %d Skull, %d Shield, %d Bolt - %s" % [
		faction, quest_name, pool, int(rolled.get("Skull", 0)), int(rolled.get("Shield", 0)), int(rolled.get("Bolt", 0)),
		"SOLVED" if solved else "failed"])

	if solved:
		_solve(ctx, q, rolled, met)
		for sym: String in met:
			_reward(ctx, q, _reward_text(q, sym), rolled)
	elif not bool(opts.get("ignore_failure", false)):
		_fail(ctx, q, rolled)
	_after(ctx, q, solved, bool(opts.get("ignore_failure", false)))
	return {"ok": true, "solved": solved, "rolled": rolled, "met": met, "log": "; ".join(ctx.log_lines)}


## The Banished's "Choose 1 Quest and resolve its failure effect": the
## face-up Quest whose failure hurts least.
static func resolve_failure(state: GameState, card_db: Node, _quest_hint: String, faction: String) -> void:
	var pick: String = ""
	var best_harm: int = 999
	for name: String in state.quest_row:
		var q: QuestCard = card(card_db, name)
		if q == null:
			continue
		var harm: int = _harm(q.failure)
		if harm < best_harm:
			best_harm = harm
			pick = name
	if pick.is_empty():
		return
	var q2: QuestCard = card(card_db, pick)
	var ctx: EffectContext = _ctx(state, card_db, faction, {})
	ctx.log("Banished: failure effect of '%s'" % pick)
	_fail(ctx, q2, {"Skull": 0, "Shield": 0, "Bolt": 0})
	_after(ctx, q2, false, false)
	NemesisAI.log_line(state, "; ".join(ctx.log_lines))


static func _harm(failure: String) -> int:
	var f: String = failure.to_lower()
	if f.strip_edges().is_empty() or f.strip_edges() == "discard this quest." or f.begins_with("discard this quest and draw"):
		return 0
	if f.find("lose 1 vp") != -1 or f.find("chaos gains 1") != -1 or f.find("empire gains 1") != -1:
		return 1
	if f.find("skeleton") != -1 or f.find("garrison") != -1:
		return 2
	if f.find("gains 2 vp") != -1:
		return 3
	return 4


## Immediate effect of a Quest entering the row (rulebook p25).
static func on_dealt(state: GameState, card_db: Node, quest_name: String, faction: String) -> void:
	var ctx: EffectContext = _ctx(state, card_db, faction, {})
	match quest_name:
		"Break the Shackles":
			# Iron Reprisals: 1 Legion at Threat 3 on The Capital.
			NemesisAI.spawn_legion(state, card_db, state.capital_coord, 3)
		"Cleanse the Wastes":
			# Legions of Undead: 2 Skeletons on 1 empty hex in each region with no Skeletons.
			for region: String in RegionMath.REGIONS:
				var spaces: Array[Vector2i] = RegionMath.region_hexes(state, region)
				var has_skeletons: bool = false
				for c: Vector2i in spaces:
					if state.hexes[c].skeleton_count > 0:
						has_skeletons = true
				if has_skeletons:
					continue
				var empties: Array[Vector2i] = []
				for c2: Vector2i in spaces:
					if EffectUtil.hex_is_empty(state, c2):
						empties.append(c2)
				var spot: Vector2i = NemesisAI.pick_hex(state, empties)
				if spot != Vector2i.MIN:
					NemesisAI.add_skeletons(state, card_db, spot, 2)
		"Corrupted Druid":
			# Beacon of Despair: 1 Activation Token on the Horde deck; 1 Curse on any empty hex.
			state.horde_deck_tokens += 1
			var spot2: Vector2i = NemesisAI.pick_hex(state, NemesisAI.empty_hexes(state))
			if spot2 != Vector2i.MIN:
				NemesisAI.place_curse_on(state, card_db, spot2)
			else:
				state.chaos_vp += 1
		"Imperial Inquisition":
			# No God But Aezher: flip 2 face-up Druids face-down.
			_flip_druids(state, 2, true)
		"Imperial Spy":
			# Dark Wings Above: per player 1 Garrison on a hex with a Garrison; 1 token on the Legion deck.
			for _p: PlayerFactionState in state.players:
				var stacks: Array[Vector2i] = []
				for c3: Vector2i in state.hexes.keys():
					var t: HexTileState = state.hexes[c3]
					if t.garrison_level > 0 and t.garrison_level < 3:
						stacks.append(c3)
				var spot3: Vector2i = NemesisAI.pick_hex(state, stacks)
				if spot3 != Vector2i.MIN:
					NemesisAI.add_garrisons(state, spot3, 1)
				else:
					state.empire_vp += 1
			state.legion_deck_tokens += 1
		"Thieves Guild":
			# Cloak and Dagger: every player's most expensive Item onto this card,
			# or the top Item of the deck for a player without one.
			var pile: Array = []
			for p: PlayerFactionState in state.players:
				var top: String = _most_expensive(card_db, p.items_in_hand)
				if not top.is_empty():
					p.items_in_hand.erase(top)
					pile.append(top)
				elif not state.item_deck.is_empty():
					pile.append(state.item_deck.pop_front())
			state.quest_items["Thieves Guild"] = pile
	NemesisAI.log_line(state, "; ".join(ctx.log_lines))


# --- Solve / failure / rewards ------------------------------------------------

static func _solve(ctx: EffectContext, q: QuestCard, rolled: Dictionary, met: Array[String]) -> void:
	var state: GameState = ctx.state
	var p: PlayerFactionState = state.find_player(ctx.acting_faction)
	match q.card_name:
		"A Deal with Demons":
			# Place any Horde in play on any hex - moved as far from the Havens as possible.
			if not state.hordes.is_empty():
				var h: HordeInstance = state.hordes[0]
				var spot: Vector2i = NemesisAI.pick_hex(state, NemesisAI.empty_hexes(state))
				if spot != Vector2i.MIN:
					h.coord = spot
					ctx.log("%s moves to %s" % [h.card_name, spot])
		"Corrupted Druid":
			_strip_tokens(ctx, "Horde")
		"Deepling Allies", "Druidic Prophetess", "Ramparts", "Tua Than Allies":
			ctx.log("%s takes '%s' into play" % [p.faction, q.card_name])
		"Druid Sacrifice":
			_remove_curse(ctx)
		"Expedition to the Mainland":
			GainResourceOp.new("Any", int(rolled.get("Skull", 0))).execute(ctx)
		"Forest Spirit":
			if state.find_player(ctx.acting_faction) != null and _total_resources(p) >= 5:
				_pay_any(p, 5)
				if _remove_curse(ctx):
					p.vp += 1
		"Hokqhan Scout":
			var unexplored: Array[Vector2i] = []
			for c: Vector2i in state.hexes.keys():
				var t: HexTileState = state.hexes[c]
				if not t.explored and not t.curse and t.role != "outer":
					unexplored.append(c)
			unexplored.sort()
			if not unexplored.is_empty():
				_flip_hex(ctx, unexplored[0], true)
		"Hungry Giant":
			_hungry_giant(ctx, met.has("Shield"), false)
		"Imperial Inquisition":
			_flip_druids(state, 2, false)
		"Imperial Spy":
			_strip_tokens(ctx, "Legion")
		"Instruction of the Druids":
			ctx.log("%s gains any 1 of their Feats (Feats are not tracked as cards yet)" % p.faction)
		"Intercept the Empress":
			_gain_market_item(ctx, false)
		"Koloth Migration":
			GainResourceOp.new("Food", int(rolled.get("Skull", 0))).execute(ctx)
		"Mad Krowh Shaman":
			_clear_hex(ctx, false)
		"Nethersea Navigators":
			var n: int = mini(5, int(rolled.get("Shield", 0)) + int(rolled.get("Bolt", 0)))
			EachPlayerOp.new([GainResourceOp.new("Any", n)], false).execute(ctx)
		"Rebel Council":
			for other: PlayerFactionState in state.players:
				if other.hero_coord == p.hero_coord:
					_lowest_vp_player(state).vp += 5
					ctx.log("a player gains 5 VP")
		"Release the Kraken":
			_move_curse(ctx)
		"Strike at Dawn":
			var foe: Variant = _strongest_nemesis(state)
			if foe != null:
				NemesisAI.add_threat(state, foe, -2)
				ctx.log("%s loses 2 Threat" % foe.card_name)
				if foe.threat <= 0:
					_destroy_by_effect(ctx, foe)
		"Thieves Guild":
			var pile: Array = state.quest_items.get("Thieves Guild", [])
			if not pile.is_empty():
				var item: String = _most_expensive(ctx.card_db, pile)
				pile.erase(item)
				p.items_in_hand.append(item)
				ctx.log("%s takes '%s' from the Thieves Guild" % [p.faction, item])
		"Willing to Fight":
			for c2: Vector2i in state.hexes.keys():
				if state.hexes[c2].haven_faction == p.faction:
					state.hexes[c2].add_units(p.faction, PlayerboardTable.default_unit(p.faction), 1)
			EachPlayerOp.new([PlaceUnitOp.new(1, "haven_or_empty_explored")], true).execute(ctx)


static func _fail(ctx: EffectContext, q: QuestCard, _rolled: Dictionary) -> void:
	var state: GameState = ctx.state
	var p: PlayerFactionState = state.find_player(ctx.acting_faction)
	match q.card_name:
		"A Deal with Demons":
			_activate_lowest(ctx, "Horde")
		"Corrupted Druid", "Mad Krowh Shaman":
			NemesisAI.place_skeleton_with_others(state, ctx.card_db, 1)
		"Deepling Allies", "Imperial Inquisition", "Tua Than Allies":
			if p != null:
				p.vp -= 1
		"Druid Sacrifice", "Druidic Prophetess", "Expedition to the Mainland", "Forest Spirit":
			state.chaos_vp += 2
		"Hungry Giant":
			_hungry_giant(ctx, false, true)
		"Imperial Spy":
			NemesisAI.place_garrison_on_empty_hex(state)
		"Instruction of the Druids":
			state.chaos_vp += 1
		"Intercept the Empress":
			state.empire_vp += 2
		"Koloth Migration":
			if p != null:
				var u: Dictionary = _cheapest_unit_on_map(state, p.faction)
				if not u.is_empty():
					(state.hexes[u["coord"]] as HexTileState).remove_unit(p.faction, u["unit"])
					ctx.log("%s removes 1 %s from play" % [p.faction, u["unit"]])
		"Nethersea Navigators":
			_draw_new_quest(ctx)
		"Ramparts":
			state.empire_vp += 1
		"Rebel Council":
			PlaceActivationTokenOp.new().execute(ctx)
			PlaceActivationTokenOp.new().execute(ctx)
		"Release the Kraken":
			var spots: Array[Vector2i] = []
			for c: Vector2i in state.hexes.keys():
				if NemesisAI.no_x(state.hexes[c]) and not state.hexes[c].curse:
					spots.append(c)
			var spot: Vector2i = NemesisAI.pick_hex(state, spots)
			if spot != Vector2i.MIN:
				NemesisAI.place_curse_on(state, ctx.card_db, spot)
		"Strike at Dawn":
			_activate_lowest(ctx, "Any")
		"Thieves Guild":
			var pile: Array = state.quest_items.get("Thieves Guild", [])
			if not pile.is_empty():
				var item: String = _most_expensive(ctx.card_db, pile)
				pile.erase(item)
				state.item_discard.append(item)
		"Willing to Fight":
			if p != null and _total_resources(p) >= 2:
				_pay_any(p, 2)
			else:
				state.empire_vp += 2
	ctx.log("failure: %s" % q.failure)


## One goal's printed reward.
static func _reward(ctx: EffectContext, q: QuestCard, text: String, rolled: Dictionary) -> void:
	var t: String = text.strip_edges()
	var low: String = t.to_lower()
	var p: PlayerFactionState = ctx.state.find_player(ctx.acting_faction)
	if t.is_empty() or t == "-" or p == null:
		return
	var re_vp := RegEx.new()
	re_vp.compile("^(lose )?(\\d+) vp$")
	var m: RegExMatch = re_vp.search(low.trim_suffix("."))
	if m != null:
		p.vp += (-1 if not m.get_string(1).is_empty() else 1) * m.get_string(2).to_int()
		ctx.log("reward: %s" % t)
		return
	var re_res := RegEx.new()
	re_res.compile("^(\\d+) (salt|plunder|food)$")
	m = re_res.search(low.trim_suffix("."))
	if m != null:
		GainResourceOp.new(m.get_string(2).capitalize(), m.get_string(1).to_int()).execute(ctx)
		return
	if low.begins_with("resolve the solve-effect again"):
		_solve(ctx, q, rolled, [])
	elif low.begins_with("remove 1 curse"):
		_remove_curse(ctx)
	elif low.begins_with("place 1 basic unit on any havens"):
		_place_on_own_haven(ctx, p, PlayerboardTable.default_unit(p.faction))
	elif low.begins_with("place 1 rider unit"):
		var rider: String = ""
		var board: PlayerboardTable.FactionBoard = PlayerboardTable.get_board(p.faction)
		for u: PlayerboardTable.UnitEntry in board.units:
			if u.is_rider() and NemesisCards.reserve_left(ctx.state, p, u.name) > 0:
				rider = u.name
		if not rider.is_empty():
			_place_on_own_haven(ctx, p, rider)
	elif low.begins_with("gain 1 item from the market"):
		_gain_market_item(ctx, true)
	elif low.begins_with("every other player gains 2 food"):
		EachPlayerOp.new([GainResourceOp.new("Food", 2)], true).execute(ctx)
	elif low.begins_with("every hero here gains 2 resources"):
		var original: String = ctx.acting_faction
		for other: PlayerFactionState in ctx.state.players:
			if other.hero_coord == p.hero_coord:
				ctx.acting_faction = other.faction
				GainResourceOp.new("Any", 2).execute(ctx)
		ctx.acting_faction = original
	elif low.begins_with("place 1 wall and tower"):
		_build_defense_anywhere(ctx, p, true, true)
	elif low.begins_with("place 1 wall"):
		_build_defense_anywhere(ctx, p, true, false)
	elif low.begins_with("place 1 tower"):
		_build_defense_anywhere(ctx, p, false, true)
	elif low.begins_with("remove all garrisons from 1 hex"):
		_clear_hex(ctx, true)
	elif low.begins_with("look at the top card of the quest deck"):
		ctx.log("reward: looked at the top Quest and left it")
	elif low.begins_with("gain +1 black"):
		pass  # Hungry Giant: already folded into its solve roll
	else:
		ctx.log("reward not taken: %s" % t)  # the "You may..." options are declined


## What happens to the card itself after the attempt.
static func _after(ctx: EffectContext, q: QuestCard, solved: bool, failure_ignored: bool) -> void:
	var state: GameState = ctx.state
	var name: String = q.card_name
	if not state.quest_row.has(name):
		return
	var text: String = (q.solve if solved else ("" if failure_ignored else q.failure)).to_lower()
	var p: PlayerFactionState = state.find_player(ctx.acting_faction)
	if solved and text.find("gain this card") != -1 and p != null:
		state.quest_row.erase(name)
		p.quests_in_play.append(name)
		return
	var discard: bool = text.find("discard this quest") != -1
	if name == "Thieves Guild" and (state.quest_items.get(name, []) as Array).is_empty():
		discard = true
	if solved and STAY_UNTIL_SOLVED.has(name):
		discard = true
	if not solved and STAY_UNTIL_SOLVED.has(name):
		discard = false
	if discard:
		state.quest_row.erase(name)
		state.quest_discard.append(name)
		for item: Variant in (state.quest_items.get(name, []) as Array):
			state.item_discard.append(str(item))
		state.quest_items.erase(name)


static func _cleanse_the_wastes(ctx: EffectContext, q: QuestCard) -> Dictionary:
	var any: bool = false
	for t: HexTileState in ctx.state.hexes.values():
		if t.skeleton_count > 0:
			any = true
	if any:
		return {"ok": false, "reason": "Skeletons remain on the map"}
	for p: PlayerFactionState in ctx.state.players:
		p.vp += 3
	ctx.log("Cleanse the Wastes: no Skeletons left - every player gains 3 VP")
	_after(ctx, q, true, false)
	return {"ok": true, "solved": true, "rolled": {}, "met": [], "log": "; ".join(ctx.log_lines)}


# --- Small effect helpers --------------------------------------------------

static func _ctx(state: GameState, card_db: Node, faction: String, opts: Dictionary) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.state = state
	ctx.card_db = card_db
	ctx.acting_faction = faction
	var rng: RandomNumberGenerator = opts.get("rng", null)
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	ctx.rng = rng
	var p: PlayerFactionState = state.find_player(faction)
	if p != null:
		ctx.hex_coord = p.hero_coord
		ctx.has_hex_coord = true
	return ctx


## "You may draw a new Quest" (when taken): one more Quest into the row,
## resolving its immediate effect.
static func _draw_new_quest(ctx: EffectContext) -> void:
	if ctx.state.quest_deck.is_empty():
		return
	var name: String = ctx.state.quest_deck.pop_front()
	ctx.state.quest_row.append(name)
	ctx.log("new Quest: %s" % name)
	on_dealt(ctx.state, ctx.card_db, name, ctx.acting_faction)


static func _remove_curse(ctx: EffectContext) -> bool:
	var p: PlayerFactionState = ctx.state.find_player(ctx.acting_faction)
	var best: Vector2i = Vector2i.MIN
	var best_d: int = 999
	var coords: Array = ctx.state.hexes.keys()
	coords.sort()
	for c: Vector2i in coords:
		if (ctx.state.hexes[c] as HexTileState).curse:
			var d: int = HexMath.distance(c, p.hero_coord) if p != null else 0
			if d < best_d:
				best_d = d
				best = c
	if best == Vector2i.MIN:
		return false
	ctx.state.hexes[best].curse = false
	ctx.log("Curse removed from %s" % best)
	return true


static func _move_curse(ctx: EffectContext) -> void:
	var coords: Array = ctx.state.hexes.keys()
	coords.sort()
	for c: Vector2i in coords:
		var t: HexTileState = ctx.state.hexes[c]
		if not t.curse or not NemesisAI.near_haven(ctx.state, c):
			continue
		var away: Array[Vector2i] = []
		for n: Vector2i in HexMath.neighbors(c):
			var nt: HexTileState = ctx.state.get_hex(n)
			if nt != null and not nt.curse and nt.haven_faction.is_empty():
				away.append(n)
		var to: Vector2i = NemesisAI.pick_hex(ctx.state, away)
		if to != Vector2i.MIN:
			t.curse = false
			NemesisAI.place_curse_on(ctx.state, ctx.card_db, to)
			ctx.log("Curse moved from %s to %s" % [c, to])
			return


## Mad Krowh Shaman / Imperial Spy: clear Skeletons (or Garrisons) off the
## hex where they press closest to the player.
static func _clear_hex(ctx: EffectContext, garrisons: bool) -> void:
	var p: PlayerFactionState = ctx.state.find_player(ctx.acting_faction)
	var best: Vector2i = Vector2i.MIN
	var best_d: int = 999
	var coords: Array = ctx.state.hexes.keys()
	coords.sort()
	for c: Vector2i in coords:
		var t: HexTileState = ctx.state.hexes[c]
		var has: bool = t.garrison_level > 0 and NemesisAI.no_x(t) if garrisons else t.skeleton_count > 0
		if has:
			var d: int = HexMath.distance(c, p.hero_coord) if p != null else 0
			if d < best_d:
				best_d = d
				best = c
	if best == Vector2i.MIN:
		return
	if garrisons:
		ctx.state.hexes[best].garrison_level = 0
	else:
		ctx.state.hexes[best].skeleton_count = 0
	ctx.log("%s removed from %s" % ["Garrisons" if garrisons else "Skeletons", best])


static func _strip_tokens(ctx: EffectContext, kind: String) -> void:
	var best: Variant = null
	var pool: Array = ctx.state.hordes if kind == "Horde" else ctx.state.legions
	for n: Variant in pool:
		if best == null or n.activation_tokens > best.activation_tokens:
			best = n
	if best != null:
		ctx.log("%s loses its %d Activation Token(s)" % [best.card_name, best.activation_tokens])
		best.activation_tokens = 0


static func _activate_lowest(ctx: EffectContext, kind: String) -> void:
	var best: Variant = null
	var pool: Array = []
	if kind != "Legion":
		pool.append_array(ctx.state.hordes)
	if kind != "Horde":
		pool.append_array(ctx.state.legions)
	for n: Variant in pool:
		if best == null or NemesisAI.initiative(n.card_name) < NemesisAI.initiative(best.card_name):
			best = n
	if best != null:
		ctx.log("%s activates" % best.card_name)
		NemesisAI.activate_now(ctx.state, ctx.card_db, best)


static func _strongest_nemesis(state: GameState) -> Variant:
	var best: Variant = null
	var all: Array = []
	all.append_array(state.legions)
	all.append_array(state.hordes)
	for n: Variant in all:
		if best == null or n.threat > best.threat:
			best = n
	return best


## A Legion/Horde destroyed by a card effect: removed, and the player who
## caused it gains the bottom effect's VP (rulebook p47, p49).
static func _destroy_by_effect(ctx: EffectContext, foe: Variant) -> void:
	ctx.state.legions.erase(foe)
	ctx.state.hordes.erase(foe)
	var c: LegionHordeCombatTable.CombatCard = LegionHordeCombatTable.get_card(foe.card_name)
	var p: PlayerFactionState = ctx.state.find_player(ctx.acting_faction)
	if p != null and c != null:
		p.vp += c.on_destroy_vp
	ctx.log("%s is destroyed" % foe.card_name)


## Hungry Giant: roll 1 black (+1 more with the Shield reward) against the
## strongest Legion/Horde; on failure against the hex with the most player
## Units instead (losses to the Chaos Graveyard).
static func _hungry_giant(ctx: EffectContext, extra_black: bool, failure: bool) -> void:
	var hits: int = 0
	for _i: int in range(2 if extra_black else 1):
		for s: String in DiceModel.roll("black", ctx.rng):
			hits += 2 if s == "Bolt" else (1 if s == "Skull" else 0)
	if not failure:
		var foe: Variant = _strongest_nemesis(ctx.state)
		if foe == null:
			return
		NemesisAI.add_threat(ctx.state, foe, -hits)
		ctx.log("Hungry Giant hits %s for %d" % [foe.card_name, hits])
		if foe.threat <= 0:
			_destroy_by_effect(ctx, foe)
		return
	var best: Vector2i = Vector2i.MIN
	var most: int = 0
	for c: Vector2i in ctx.state.hexes.keys():
		var n: int = (ctx.state.hexes[c] as HexTileState).total_player_units()
		if n > most:
			most = n
			best = c
	if best == Vector2i.MIN:
		return
	var tile: HexTileState = ctx.state.hexes[best]
	var faction: String = tile.player_faction_here()
	var owner: PlayerFactionState = ctx.state.find_player(faction)
	for _j: int in range(hits):
		var unit: String = CombatResolver._cheapest_unit(tile, faction)
		if unit.is_empty():
			break
		tile.remove_unit(faction, unit)
		ctx.state.chaos_graveyard[faction] = int(ctx.state.chaos_graveyard.get(faction, 0)) + 1
		if owner != null:
			owner.graveyard_units[unit] = int(owner.graveyard_units.get(unit, 0)) + 1
	ctx.log("Hungry Giant tramples %s for %d" % [best, hits])


static func _flip_druids(state: GameState, count: int, down: bool) -> void:
	var flipped: int = 0
	for d: DruidInstance in state.druids_in_play:
		if flipped >= count:
			break
		if d.face_down != down:
			d.face_down = down
			flipped += 1


## Flip a hex as if Explored by the acting player (Hokqhan Scout skips its
## Garrison/Skeleton placements).
static func _flip_hex(ctx: EffectContext, coord: Vector2i, no_nemesis: bool) -> void:
	var tile: HexTileState = ctx.state.hexes[coord]
	tile.explored = true
	var flipper: PlayerFactionState = ctx.state.find_player(ctx.acting_faction)
	if tile.bonus_salt > 0 and flipper != null:
		flipper.salt += tile.bonus_salt
		tile.bonus_salt = 0
	if not HexEffectPrograms.has_program(tile.hex_card_name):
		return
	var sub: EffectContext = _ctx(ctx.state, ctx.card_db, ctx.acting_faction, {"rng": ctx.rng})
	sub.hex_coord = coord
	for op: EffectOp in HexEffectPrograms.get_program(tile.hex_card_name).ops:
		if no_nemesis and (op is PlaceTokenOp or op is PlaceOrReinforceOp):
			continue
		op.execute(sub)
	ctx.log("flipped %s: %s" % [tile.hex_card_name, "; ".join(sub.log_lines)])


static func _gain_market_item(ctx: EffectContext, must_use: bool) -> void:
	var p: PlayerFactionState = ctx.state.find_player(ctx.acting_faction)
	var options: Array = []
	for it: String in ctx.state.item_market:
		if ctx.state.flipped_market.has(it):
			continue
		if must_use and not GameActions.hero_can_use_item(ctx.card_db, p, it):
			continue
		options.append(it)
	var pick: String = _most_expensive(ctx.card_db, options)
	if pick.is_empty():
		return
	ctx.state.item_market.erase(pick)
	ChapterFlow.refill_row(ctx.state.item_market, ctx.state.item_deck, ctx.state.item_discard, 3)
	p.items_in_hand.append(pick)
	ctx.log("%s gains Item '%s'" % [p.faction, pick])


static func _most_expensive(card_db: Node, items: Array) -> String:
	var best: String = ""
	var top: int = -1
	for it: Variant in items:
		var c: int = GameActions.item_cost(card_db, str(it))
		if c > top:
			top = c
			best = str(it)
	return best


static func _place_on_own_haven(ctx: EffectContext, p: PlayerFactionState, unit_name: String) -> void:
	var coords: Array = ctx.state.hexes.keys()
	coords.sort()
	for c: Vector2i in coords:
		var t: HexTileState = ctx.state.hexes[c]
		if t.haven_faction == p.faction and t.add_units(p.faction, unit_name, 1) > 0:
			ctx.log("%s places 1 %s on %s" % [p.faction, unit_name, c])
			return


static func _build_defense_anywhere(ctx: EffectContext, p: PlayerFactionState, wall: bool, tower: bool) -> void:
	var coords: Array = ctx.state.hexes.keys()
	coords.sort()
	for c: Vector2i in coords:
		var t: HexTileState = ctx.state.hexes[c]
		if t.haven_faction != p.faction:
			continue
		if (wall and not t.wall) or (tower and not t.tower):
			t.wall = t.wall or wall
			t.tower = t.tower or tower
			ctx.log("%s Haven on %s gains %s" % [p.faction, c, "Wall and Tower" if wall and tower else ("Wall" if wall else "Tower")])
			return


static func _cheapest_unit_on_map(state: GameState, faction: String) -> Dictionary:
	var best: Dictionary = {}
	var best_cost: int = 999
	for c: Vector2i in state.hexes.keys():
		var t: HexTileState = state.hexes[c]
		for u: Variant in t.unit_stack(faction).keys():
			var e: PlayerboardTable.UnitEntry = PlayerboardTable.get_unit(faction, str(u))
			var cost: int = CombatResolver._cost_total(e.cost) if e != null else 0
			if cost < best_cost:
				best_cost = cost
				best = {"coord": c, "unit": str(u)}
	return best


static func _lowest_vp_player(state: GameState) -> PlayerFactionState:
	var best: PlayerFactionState = state.players[0]
	for p: PlayerFactionState in state.players:
		if p.vp < best.vp:
			best = p
	return best


static func _total_resources(p: PlayerFactionState) -> int:
	return p.salt + p.plunder + p.food


## Pays `n` resources of any kind, from the largest stock first.
static func _pay_any(p: PlayerFactionState, n: int) -> void:
	for _i: int in range(n):
		if p.salt >= p.plunder and p.salt >= p.food and p.salt > 0:
			p.salt -= 1
		elif p.plunder >= p.food and p.plunder > 0:
			p.plunder -= 1
		elif p.food > 0:
			p.food -= 1
