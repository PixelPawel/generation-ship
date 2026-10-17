extends RefCounted

## Feats and Items as rules (Feats.csv / Items.csv, Core box). Loaded with
## preload/load, no class_name.
##
## Feat decks: the card art is filed per Hero (FEATS_EN/<Faction>/
## <Hero>_<Feat>.jpg), and each faction's first Hero - the one GameSetup
## plays - owns exactly the cards filed under their name: 8 or 10 Feats
## plus the two attribute Feats every deck has ("Every Feat deck contains
## two Feats that give an attribute and 3 resources"). START markers read
## off the art: 2 per first-Hero deck (rulebook Setup: "place the Feats
## marked START next to your Hero card"). The second Heroes' decks are only
## partly identifiable from the art (their own few cards), so they borrow
## the rest of their faction's cards - flagged as a guess.
##
## A card is "active" while it's in play and not flipped; flipped cards come
## back in the Refresh Phase. Feats and Items share a 10-card limit; the
## least useful card goes when it's exceeded.
##
## This file covers ownership, the Build Phase draw, passive ("Always")
## effects GameActions asks about, Actions-phase cards (the "use_card"
## action) and modifiers to rolls outside of combat. Combat abilities
## live in CombatResolver.

const START_FEATS: Array[String] = [
	"Intuition", "Swordsisters", "Teleport", "Elder", "Phalanx", "Younglings",
	"Dark Ritual", "Trolls", "Pillage", "Slavers", "Treachery", "Wiles",
]
const ATTRIBUTE_FEATS: Dictionary = {"Guile Leadership": ["lead", "guile"], "Might Magic": ["might", "magic"]}
const CARD_LIMIT: int = 10
## True Solo Mode: 14 Feats and Items across both Heroes, attribute Feats
## (under the Hero card) not counted (rulebook p76).
const SOLO_CARD_LIMIT: int = 14
## Unit Feats - the ones naming a specific Unit or showing one in their art -
## leave the allied Hero's deck in True Solo Mode (rulebook p74). Read off
## the Core cards; removing them leaves every Hero exactly 1 START Feat,
## which is what the rule expects of an allied Hero.
const UNIT_FEATS: Array[String] = [
	"Beastmasters", "Swordsisters", "Koloth", "Warsong", "Younglings", "Trolls", "Vargs",
	"Berserkers", "Crossfire", "Rebel Marksmen", "Slavers",
]

const FEAT_DECKS: Dictionary = {
	"Fhayanor": ["Ambush", "Assasins", "Beastmasters", "Caravans", "Hit and Run", "Informants", "Intuition", "Swordsisters"],
	"Syndra": ["Illusionist", "Teleport", "Swordsisters", "Ambush", "Assasins", "Beastmasters", "Caravans", "Hit and Run"],
	"Baranth": ["Astute", "Asheforge", "Call to Arms", "Glory", "Koloth", "Phalanx", "Warsong", "Younglings"],
	"Yanny": ["Elder", "Traps", "Younglings", "Astute", "Call to Arms", "Glory", "Koloth", "Warsong"],
	"Dugpa": ["Dark Ritual", "Deathsworn", "Trolls", "Frenzy", "Gravedigger", "Necromancy", "Vargs"],
	"Kha'al": ["Bloodlust", "Bonefires", "Pillage", "Trolls", "Deathsworn", "Frenzy", "Gravedigger"],
	"Hanzo": ["Berserkers", "Crossfire", "Imperial Connections", "Rebel Marksmen", "Slavers", "Spoils of War", "Tomb Raiders", "Treachery"],
	"Ronja": ["Tricky", "Wiles", "Slavers", "Berserkers", "Crossfire", "Rebel Marksmen", "Spoils of War", "Tomb Raiders"],
}

## Build Phase pick order when no player choice is available: economy and
## attribute cards early, then reliable combat help.
const FEAT_PRIORITY: Array[String] = [
	"Might Magic", "Guile Leadership", "Caravans", "Intuition", "Tomb Raiders", "Astute", "Asheforge",
	"Phalanx", "Ambush", "Traps", "Treachery", "Dark Ritual", "Necromancy", "Assasins", "Illusionist",
	"Hit and Run", "Crossfire", "Warsong", "Vargs", "Berserkers", "Pillage", "Spoils of War", "Slavers",
	"Call to Arms", "Bonefires", "Swordsisters", "Imperial Connections", "Teleport", "Wiles", "Elder",
	"Tricky", "Rebel Marksmen", "Glory", "Frenzy", "Beastmasters", "Trolls", "Younglings", "Koloth",
	"Bloodlust", "Deathsworn", "Gravedigger", "Informants",
]


# --- Ownership -----------------------------------------------------------------

static func owns(p: PlayerFactionState, card: String) -> bool:
	return p != null and (p.feats_in_play.has(card) or p.items_in_hand.has(card))


static func active(p: PlayerFactionState, card: String) -> bool:
	if p == null:
		return false
	if p.feats_in_play.has(card):
		return not p.flipped_feats.has(card)
	if p.items_in_hand.has(card):
		return not p.flipped_items.has(card)
	return false


static func flip(p: PlayerFactionState, card: String) -> void:
	if p.feats_in_play.has(card) and not p.flipped_feats.has(card):
		p.flipped_feats.append(card)
	elif p.items_in_hand.has(card) and not p.flipped_items.has(card):
		p.flipped_items.append(card)


## Discards a Feat (to the bottom of its deck - "It might come back") or an
## Item (to the discard pile; Caravans pays 1 Salt for it).
static func discard(state: GameState, p: PlayerFactionState, card: String) -> void:
	if p.feats_in_play.has(card):
		var own_deck: bool = p.card_is_acting_heros(card)  # True Solo: back to its own Hero's deck
		p.feats_in_play.erase(card)
		p.flipped_feats.erase(card)
		if own_deck:
			p.feat_deck.append(card)
		else:
			p.ally_feat_deck.append(card)
		if not p.feats_in_play.has(card):
			p.ally_cards.erase(card)
	elif p.items_in_hand.has(card):
		p.ally_cards.erase(card)
		p.items_in_hand.erase(card)
		p.flipped_items.erase(card)
		state.item_discard.append(card)
		if active(p, "Caravans"):
			p.salt += 1


static func feat_deck_for(hero_name: String) -> Array[String]:
	var deck: Array[String] = []
	for f: Variant in (FEAT_DECKS.get(hero_name, []) as Array):
		deck.append(str(f))
	deck.append("Guile Leadership")
	deck.append("Might Magic")
	return deck


## Setup: START Feats into play, the rest shuffled into the Feat deck. With
## an allied Hero (True Solo) its own deck follows: no Unit Feats, no card
## the main Hero's deck already holds (both Heroes may be one faction's).
static func setup_player(state: GameState, card_db: Node, p: PlayerFactionState, rng: RandomNumberGenerator) -> void:
	p.feats_in_play.clear()
	p.feat_deck.clear()
	p.ally_cards.clear()
	_setup_deck(state, card_db, p, rng, [])
	if p.has_ally():
		var taken: Array[String] = p.feats_in_play.duplicate()
		taken.append_array(p.feat_deck)
		for a: String in ATTRIBUTE_FEATS.keys():
			taken.erase(a)  # each Hero has their own attribute Feats
		taken.append_array(UNIT_FEATS)
		p.swap_heroes()
		_setup_deck(state, card_db, p, rng, taken)
		p.swap_heroes()


static func _setup_deck(state: GameState, card_db: Node, p: PlayerFactionState, rng: RandomNumberGenerator, skip: Array[String]) -> void:
	var rest: Array[String] = []
	for f: String in feat_deck_for(p.hero_name):
		if skip.has(f):
			continue
		if START_FEATS.has(f):
			gain_feat(state, card_db, p, f)
		else:
			rest.append(f)
	for i: int in range(rest.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: String = rest[i]
		rest[i] = rest[j]
		rest[j] = tmp
	p.feat_deck = rest
	p.feats_deck_remaining = rest.size()


## A Feat comes into play ("draw" or "gain"): the attribute Feats give 3
## resources and +1 to one of their two attributes (the Hero's stronger one).
static func gain_feat(state: GameState, card_db: Node, p: PlayerFactionState, feat: String) -> void:
	p.feat_deck.erase(feat)
	# Both Heroes of a True Solo game have their own attribute Feats.
	if not p.feats_in_play.has(feat) or (p.has_ally() and ATTRIBUTE_FEATS.has(feat)):
		p.feats_in_play.append(feat)
	p.claim_card(feat)
	if ATTRIBUTE_FEATS.has(feat):
		var pair: Array = ATTRIBUTE_FEATS[feat]
		var a: String = str(pair[0])
		var b: String = str(pair[1])
		var pick: String = a if EffectUtil.hero_attr(card_db, p, a) >= EffectUtil.hero_attr(card_db, p, b) else b
		p.attr_bonus[pick] = int(p.attr_bonus.get(pick, 0)) + 1
		var ctx := EffectContext.new()
		ctx.state = state
		ctx.card_db = card_db
		ctx.acting_faction = p.faction
		GainResourceOp.new("Any", 3).execute(ctx)
	p.feats_deck_remaining = p.feat_deck.size()
	enforce_limit(state, p, card_db)


## "Draw a Feat": the top card of the deck comes into play.
static func draw_feat(state: GameState, card_db: Node, p: PlayerFactionState) -> String:
	if p.feat_deck.is_empty():
		return ""
	var feat: String = p.feat_deck[0]
	gain_feat(state, card_db, p, feat)
	return feat


## Feats + Items over 10: the least useful card goes (the cheapest Item,
## else the lowest-priority Feat). True Solo: 14 across both Heroes, with
## the attribute Feats under the Hero cards left out.
static func enforce_limit(state: GameState, p: PlayerFactionState, card_db: Node = null) -> void:
	while _limited_cards(p) > (SOLO_CARD_LIMIT if p.has_ally() else CARD_LIMIT):
		if not p.items_in_hand.is_empty():
			var cheapest: String = p.items_in_hand[0]
			for it: String in p.items_in_hand:
				if GameActions.item_cost(card_db, it) < GameActions.item_cost(card_db, cheapest):
					cheapest = it
			discard(state, p, cheapest)
		else:
			var counted: Array[String] = []
			for f: String in p.feats_in_play:
				if not (p.has_ally() and ATTRIBUTE_FEATS.has(f)):
					counted.append(f)
			if counted.is_empty():
				return
			discard(state, p, _worst_feat(counted))


static func _limited_cards(p: PlayerFactionState) -> int:
	var n: int = p.feats_in_play.size() + p.items_in_hand.size()
	if p.has_ally():
		for f: String in p.feats_in_play:
			if ATTRIBUTE_FEATS.has(f):
				n -= 1
	return n


static func _rank(feat: String) -> int:
	var i: int = FEAT_PRIORITY.find(feat)
	return i if i >= 0 else 999


static func _worst_feat(feats: Array[String]) -> String:
	var worst: String = feats[0]
	for f: String in feats:
		if _rank(f) > _rank(worst):
			worst = f
	return worst


## Build Phase start (rulebook p17): draw 2 Feats, keep 1, the other goes
## under the deck. The pair waits in pending_feats for a "pick_feat". True
## Solo: the allied Hero does the same from their own deck (p78).
static func draw_for_build(p: PlayerFactionState) -> void:
	_draw_two(p)
	if p.has_ally():
		p.swap_heroes()
		_draw_two(p)
		p.swap_heroes()


static func _draw_two(p: PlayerFactionState) -> void:
	p.pending_feats.clear()
	for _i: int in range(mini(2, p.feat_deck.size())):
		p.pending_feats.append(p.feat_deck.pop_front())


static func pick_feat(state: GameState, card_db: Node, p: PlayerFactionState, feat: String) -> bool:
	if not p.pending_feats.has(feat):
		return false
	for other: String in p.pending_feats:
		if other != feat:
			p.feat_deck.append(other)
	p.pending_feats.clear()
	gain_feat(state, card_db, p, feat)
	return true


static func auto_pick(state: GameState, card_db: Node, p: PlayerFactionState) -> void:
	_auto_pick_one(state, card_db, p)
	if p.has_ally():
		p.swap_heroes()
		_auto_pick_one(state, card_db, p)
		p.swap_heroes()


static func _auto_pick_one(state: GameState, card_db: Node, p: PlayerFactionState) -> void:
	if p.pending_feats.is_empty():
		return
	var best: String = p.pending_feats[0]
	for f: String in p.pending_feats:
		if _rank(f) < _rank(best):
			best = f
	pick_feat(state, card_db, p, best)


# --- Passive effects GameActions asks about --------------------------------

static func item_discount(p: PlayerFactionState) -> int:
	return 1 if active(p, "Caravans") else 0


static func ignores_item_requirements(p: PlayerFactionState) -> bool:
	return active(p, "Intuition")


static func command_food_cost(p: PlayerFactionState) -> int:
	return 0 if active(p, "Horn of Yor") else 1


static func hero_adjacent_everywhere(p: PlayerFactionState) -> bool:
	return active(p, "Nethersea Map")


static func trade_bonus(p: PlayerFactionState) -> int:
	return 1 if active(p, "Tomb Raiders") else 0


static func trades_adjacent(p: PlayerFactionState) -> bool:
	return active(p, "Tomb Raiders")


# --- Rolls outside of combat ------------------------------------------------

## The dice for a roll outside combat: Hero Dice, plus Wyten's Eyepatch
## ("Add 1 RED") and Elder ("Add any 1 die" - black, the most symbols).
static func outside_roll_pool(card_db: Node, p: PlayerFactionState, guile_color: String) -> Array[String]:
	var pool: Array[String] = EffectUtil.hero_dice(card_db, p, guile_color)
	if active(p, "Wytens Eyepatch"):
		pool.append("red")
	if active(p, "Elder"):
		pool.append("black")
	return pool


## After a roll outside combat came up short: Icewaterpipe ("reroll ALL
## your dice ... once") rerolls everything, Tricky (flip) rerolls the blanks.
## Returns the new symbol counts (unchanged if nothing helped).
static func second_chance(p: PlayerFactionState, pool: Array[String], rolled: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	if active(p, "Icewaterpipe"):
		return DiceModel.roll_pool(pool, rng)
	if active(p, "Tricky"):
		flip(p, "Tricky")
		var faces: Array = []
		for c: String in pool:
			faces.append(DiceModel.roll(c, rng))
		var counts: Dictionary = {"Skull": 0, "Shield": 0, "Bolt": 0}
		for i: int in range(faces.size()):
			var face: Array = faces[i]
			if face.is_empty():
				face = DiceModel.roll(pool[i], rng)
			for s: Variant in face:
				counts[str(s)] = int(counts.get(str(s), 0)) + 1
		return counts
	return rolled


## Takes 1 Aether off the Druid holding the most and returns it to the bag
## (rulebook p40: "remove 1 Aether from any Druid ... put it back into the
## bag"). False when no Druid has any.
static func spend_aether(state: GameState) -> bool:
	var best: DruidInstance = null
	for d: DruidInstance in state.druids_in_play:
		if d.aether > 0 and (best == null or d.aether > best.aether):
			best = d
	if best == null:
		return false
	best.aether -= 1
	state.aether_pool += 1
	return true


## Last-ditch fixes for a roll outside combat that still misses its goals
## (`needs` = symbol -> how many are needed): 1 Aether rerolls ALL the dice
## (once per roll); Mask of Jein (discard) turns up to 2 dice; Runestones
## (2 resources) adds 1 symbol, once per roll. Returns the new counts.
static func last_ditch(state: GameState, p: PlayerFactionState, pool: Array[String], rolled: Dictionary, needs: Dictionary, successes: int, rng: RandomNumberGenerator) -> Dictionary:
	var counts: Dictionary = rolled.duplicate()
	if _goals_met(counts, needs) < successes and spend_aether(state):
		counts = DiceModel.roll_pool(pool, rng)
	if _goals_met(counts, needs) < successes and active(p, "Mask of Jein"):
		var gap: String = _closest_gap(counts, needs)
		if not gap.is_empty() and int(needs[gap]) - int(counts.get(gap, 0)) <= 2:
			discard(state, p, "Mask of Jein")
			counts[gap] = int(needs[gap])
	if _goals_met(counts, needs) < successes and active(p, "Runestones") and p.salt + p.plunder + p.food >= 2:
		var gap2: String = _closest_gap(counts, needs)
		if not gap2.is_empty() and int(needs[gap2]) - int(counts.get(gap2, 0)) == 1:
			var quest_flow: GDScript = load("res://scripts/game/quest_flow.gd")
			quest_flow._pay_any(p, 2)
			counts[gap2] = int(counts.get(gap2, 0)) + 1
	return counts


static func _goals_met(counts: Dictionary, needs: Dictionary) -> int:
	var met: int = 0
	for sym: Variant in needs.keys():
		if int(needs[sym]) > 0 and int(counts.get(sym, 0)) >= int(needs[sym]):
			met += 1
	return met


static func _closest_gap(counts: Dictionary, needs: Dictionary) -> String:
	var best: String = ""
	var best_gap: int = 99
	for sym: Variant in needs.keys():
		var need: int = int(needs[sym])
		if need <= 0:
			continue
		var gap: int = need - int(counts.get(sym, 0))
		if gap > 0 and gap < best_gap:
			best_gap = gap
			best = str(sym)
	return best


# --- Actions-phase cards ("use_card") ------------------------------------------

## Uses an Actions-phase card (or an "Always" one that does something on
## demand). action keys depend on the card ("to", "target", "unit"...);
## sensible defaults when they're missing. Returns {ok, reason}.
static func use_card(state: GameState, card_db: Node, p: PlayerFactionState, card: String, action: Dictionary) -> Dictionary:
	if not active(p, card):
		return {"ok": false, "reason": "'%s' is not ready to use" % card}
	var ctx := EffectContext.new()
	ctx.state = state
	ctx.card_db = card_db
	ctx.acting_faction = p.faction
	ctx.rng = state.rng()
	match card:
		# --- Items ---
		"Darkstrider Boots":
			if p.action_points >= p.max_action_points:
				return {"ok": false, "reason": "no used AP to regain"}
			p.action_points += 1
			flip(p, card)
		"Dragonfruits":
			p.food += 5
			for other: PlayerFactionState in state.players:
				if other != p:
					other.food += 2
			discard(state, p, card)
		"Drakh Architect":
			var haven: Vector2i = _haven_missing_defense(state, p.faction)
			if haven == Vector2i.MIN:
				return {"ok": false, "reason": "no Haven lacks a Tower or Wall"}
			state.hexes[haven].tower = true
			state.hexes[haven].wall = true
			flip(p, card)
		"Druid's Ale":
			draw_feat(state, card_db, p)
			discard(state, p, card)
		"Imperial Defectors":
			for other2: PlayerFactionState in state.players:
				var h: Vector2i = NemesisAI.weakest_haven(state, other2.faction)
				if h != Vector2i.MIN:
					state.hexes[h].add_units(other2.faction, PlayerboardTable.default_unit(other2.faction), 1)
			discard(state, p, card)
		"Leeching Orb":
			if not _remove_a_curse(state, p):
				return {"ok": false, "reason": "no Curse on the map"}
			p.vp += 1
			discard(state, p, card)
		"Mohyar Pirate":
			p.vp -= 1
			GainResourceOp.new("Any", 5).execute(ctx)
			discard(state, p, card)
		"Orb of Storms":
			var foe: Variant = _nearest_nemesis(state, p)
			if foe == null:
				return {"ok": false, "reason": "no Legion or Horde to move"}
			var away: Array[Vector2i] = []
			for n: Vector2i in HexMath.neighbors(foe.coord):
				if state.hexes.has(n) and not state.edge_blocked(foe.coord, n):
					away.append(n)
			var to: Vector2i = NemesisAI.choose_spawn_hex(state, away, "Orb of Storms: push %s onto a hex next to it" % foe.card_name)
			if to == Vector2i.MIN:
				return {"ok": false, "reason": "it has nowhere to go"}
			foe.coord = to
			NemesisAI.resolve_combat_at(state, card_db, to)
			discard(state, p, card)
		"Ptetee":
			var dest: Vector2i = GameActions._coord(action, "to")
			if not state.hexes.has(dest) or HexMath.distance(p.hero_coord, dest) > 3:
				return {"ok": false, "reason": "Ptetee moves your Hero up to 3 hexes"}
			p.hero_coord = dest
			flip(p, card)
		"Twilight Bow":
			var killed: int = _destroy_skeletons(state, p, 2 if bool(action.get("discard", false)) else 1, bool(action.get("discard", false)))
			if killed == 0:
				return {"ok": false, "reason": "no Skeletons in reach"}
			p.vp += killed
			if bool(action.get("discard", false)):
				discard(state, p, card)
			else:
				flip(p, card)
		"Druwhn Witcher":
			var pool: Array = []
			pool.append_array(state.legions)
			pool.append_array(state.hordes)
			var busiest: Variant = null
			for n2: Variant in pool:
				if busiest == null or n2.activation_tokens > busiest.activation_tokens:
					busiest = n2
			if busiest == null or busiest.activation_tokens <= 0:
				return {"ok": false, "reason": "no Activation Tokens to remove"}
			busiest.activation_tokens -= 1
			discard(state, p, card)
		"Dawngaard Lantern":
			var quest_flow: GDScript = load("res://scripts/game/quest_flow.gd")
			var best: String = ""
			var best_odds: float = -1.0
			for q: String in state.quest_deck:
				var qc: QuestCard = quest_flow.card(card_db, q)
				if qc == null or quest_flow.NO_ROLL.has(q):
					continue
				var odds: float = quest_flow.success_chance(qc, outside_roll_pool(card_db, p, "yellow"), ctx.rng, 60)
				if odds > best_odds:
					best_odds = odds
					best = q
			if best.is_empty():
				return {"ok": false, "reason": "no Quest to choose"}
			state.quest_deck.erase(best)
			state.shuffle(state.quest_deck)
			state.quest_deck.push_front(best)
			discard(state, p, card)
		"Assassins Dagger":
			var mark: Variant = _nearest_nemesis(state, p)
			if mark == null:
				return {"ok": false, "reason": "no Legion or Horde to mark"}
			state.daggers[str(mark.id)] = p.faction
			discard(state, p, card)
		"Survivors":
			state.open_build_until_turn_end = true
			flip(p, card)
		# --- Feats ---
		"Swordsisters":
			var n3: int = 0
			for t: HexTileState in state.hexes.values():
				n3 += int(t.unit_stack(p.faction).get("Swordsisters", 0))
			p.salt += n3
			flip(p, card)
		"Teleport":
			var dest2: Vector2i = GameActions._coord(action, "to")
			if not state.hexes.has(dest2) or p.salt < 1:
				return {"ok": false, "reason": "Teleport costs 1 Salt and needs a hex"}
			p.salt -= 1
			p.hero_coord = dest2
		"Call to Arms":
			var discard_it: bool = bool(action.get("discard", false))
			var unit: String = str(action.get("unit", PlayerboardTable.default_unit(p.faction)))
			if not discard_it:
				unit = PlayerboardTable.default_unit(p.faction)
			var h3: Vector2i = NemesisAI.weakest_haven(state, p.faction)
			if h3 == Vector2i.MIN or NemesisAI.NemesisCards.reserve_left(state, p, unit) <= 0:
				return {"ok": false, "reason": "no Haven or no %s in reserve" % unit}
			state.hexes[h3].add_units(p.faction, unit, 1)
			if discard_it:
				discard(state, p, card)
			else:
				flip(p, card)
		"Bonefires":
			var n4: int = state.legions.size() + state.hordes.size()
			for _i: int in range(n4):
				var h4: Vector2i = NemesisAI.weakest_haven(state, p.faction)
				if h4 != Vector2i.MIN:
					state.hexes[h4].add_units(p.faction, PlayerboardTable.default_unit(p.faction), 1)
			discard(state, p, card)
		"Gravedigger":
			if state.item_discard.is_empty():
				return {"ok": false, "reason": "the Market discard is empty"}
			var best_item: String = state.item_discard[0]
			for it: String in state.item_discard:
				if GameActions.item_cost(card_db, it) > GameActions.item_cost(card_db, best_item):
					best_item = it
			state.item_discard.erase(best_item)
			p.items_in_hand.append(best_item)
			discard(state, p, card)
		"Imperial Connections":
			var n5: int = 0
			for it2: String in state.item_market.duplicate():
				if n5 >= 3 or state.flipped_market.has(it2):
					continue
				if GameActions.hero_can_use_item(card_db, p, it2):
					continue  # keep what the Hero could buy
				state.item_market.erase(it2)
				state.item_discard.append(it2)
				n5 += 1
			ChapterFlow.refill_row(state.item_market, state.item_deck, state.item_discard, 3, state)
			p.salt += n5
			flip(p, card)
		"Wiles":
			p.wiles_ready = true
			flip(p, card)
		"Deathsworn":
			var from: Vector2i = GameActions._coord(action, "at") if action.has("at") else p.hero_coord
			var tile: HexTileState = state.get_hex(from)
			if tile == null or tile.unit_count(p.faction) == 0:
				return {"ok": false, "reason": "pick a hex with your Units"}
			var removed: int = 0
			for unit2: Variant in tile.unit_stack(p.faction).keys():
				var k: int = int(tile.unit_stack(p.faction)[unit2])
				tile.remove_unit(p.faction, str(unit2), k)
				p.removed_units[str(unit2)] = int(p.removed_units.get(str(unit2), 0)) + k
				removed += k
			var target_hex: Vector2i = Vector2i.MIN
			for n6: Vector2i in HexMath.neighbors(from):
				var nt: HexTileState = state.get_hex(n6)
				if nt != null and (nt.skeleton_count > 0 or nt.garrison_level > 0):
					target_hex = n6
					break
			if target_hex != Vector2i.MIN:
				var tt: HexTileState = state.hexes[target_hex]
				for _j: int in range(removed):
					if tt.skeleton_count > 0:
						tt.skeleton_count -= 1
						p.vp += 1
					elif tt.garrison_level > 0:
						tt.garrison_level -= 1
						p.vp += 1
			discard(state, p, card)
		_:
			return {"ok": false, "reason": "'%s' isn't used from the Actions Phase" % card}
	enforce_limit(state, p, card_db)
	state.phase_log = "%s uses '%s'" % [p.faction, card]
	return {"ok": true}


static func _haven_missing_defense(state: GameState, faction: String) -> Vector2i:
	var coords: Array = state.hexes.keys()
	coords.sort()
	for c: Vector2i in coords:
		var t: HexTileState = state.hexes[c]
		if t.haven_faction == faction and (not t.tower or not t.wall):
			return c
	return Vector2i.MIN


static func _remove_a_curse(state: GameState, p: PlayerFactionState) -> bool:
	var best: Vector2i = Vector2i.MIN
	var best_d: int = 999
	for c: Vector2i in state.hexes.keys():
		if (state.hexes[c] as HexTileState).curse and HexMath.distance(c, p.hero_coord) < best_d:
			best_d = HexMath.distance(c, p.hero_coord)
			best = c
	if best == Vector2i.MIN:
		return false
	state.hexes[best].curse = false
	return true


static func _nearest_nemesis(state: GameState, p: PlayerFactionState) -> Variant:
	var best: Variant = null
	var best_d: int = 999
	var all: Array = []
	all.append_array(state.legions)
	all.append_array(state.hordes)
	for n: Variant in all:
		var home: Vector2i = NemesisAI.weakest_haven(state, p.faction)
		var d: int = HexMath.distance(n.coord, home if home != Vector2i.MIN else p.hero_coord)
		if d < best_d:
			best_d = d
			best = n
	return best


## Twilight Bow: Skeletons on the Hero's hex or next to it.
static func _destroy_skeletons(state: GameState, p: PlayerFactionState, count: int, anywhere: bool) -> int:
	var killed: int = 0
	var spots: Array[Vector2i] = [p.hero_coord]
	spots.append_array(HexMath.neighbors(p.hero_coord))
	if anywhere:
		spots = []
		for c: Vector2i in state.hexes.keys():
			spots.append(c)
	for c2: Vector2i in spots:
		var t: HexTileState = state.get_hex(c2)
		while t != null and t.skeleton_count > 0 and killed < count:
			t.skeleton_count -= 1
			killed += 1
	return killed
