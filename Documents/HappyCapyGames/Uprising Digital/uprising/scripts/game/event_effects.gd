extends RefCounted

## The 28 Core Event cards (Events.csv, EN, Box=Core), both halves resolved
## top to bottom by the first player (rulebook p16). Loaded with
## preload/load, no class_name.
##
## Sources: card text from Events.csv; "Vision from the Old Gods" has an
## empty Effect 2 there, so its second half is transcribed from the card art
## (Events_Core_04_Visions+from+the+Old+Gods.jpg). PRINTED_THREAT is the
## Threat number in each card's lower-left corner (read off the art - the
## CSV has no column for it): the default Threat of any Legion/Horde that
## enters while this Event is the latest one.
##
## Choices the cards leave to players: "may" offers that cost AP or
## resources are taken when affordable (an Item for 1 AP, 2 Basic Units for
## 2 resources, an Elite for 2 AP); the Druid swap and Feat offers are
## declined (Feats aren't tracked as cards yet - those lines are logged);
## "Legion OR Horde" alternates starting with a Legion; hexes follow
## NemesisAI.pick_hex (away from player Havens); the roller of "Choose a
## Hero to roll" is the Hero with the most dice.

const PRINTED_THREAT: Dictionary = {
	"Aezhers Essence": 4, "Exiles from the South": 4, "Starving Mobs": 4, "The Last Harvest": 4,
	"Three Bloody Comets": 4, "Turmoil grips the Lands": 4, "Uprising": 4,
	"Long live the Emperor": 5, "Madness sweeps the Land": 5, "Prolonged Eclipse": 5, "Slave Revolts": 5,
	"The Frozen Fleet": 5, "The God Touched": 5, "Unholy Omens": 5,
	"A new Dawn": 6, "Guidance from the Druids": 6, "Imperial Inspection": 5, "Imperial Spy Network": 5,
	"Ravening Hunger": 5, "The Empire strikes": 6, "Corruption of the Witches": 5,
	"Designs of the Empress": 7, "Endless Snowfall": 7, "Famine": 6, "Mass Executions": 6,
	"Rain of Ashe and Fire": 6, "The Invasion begins": 7, "Vision from the Old Gods": 7,
}
const CHAPTER_NUMBERS: Array[String] = ["One", "Two", "Three", "Four"]
const QUEST_FLOW_PATH := "res://scripts/game/quest_flow.gd"


## One random Event per Chapter from that Chapter's deck (rulebook Setup:
## "place 1 Chapter I Event on Chapter 1, 1 Chapter II Event on Chapter 2...").
static func pick_chapter_events(state: GameState, card_db: Node, rng: RandomNumberGenerator) -> void:
	for chapter: int in range(1, state.max_chapters + 1):
		var names: Array[String] = []
		for e: EventCard in card_db.events:
			if e.nr == CHAPTER_NUMBERS[mini(chapter, 4) - 1]:
				names.append(e.card_name)
		if names.is_empty():
			continue
		names.sort()
		state.chapter_events[chapter] = names[rng.randi_range(0, names.size() - 1)]


static func resolve(state: GameState, card_db: Node, event_name: String) -> void:
	var ctx := EffectContext.new()
	ctx.state = state
	ctx.card_db = card_db
	ctx.rng = state.rng()
	ctx.acting_faction = state.players[state.first_player_index % state.players.size()].faction if not state.players.is_empty() else ""
	state.latest_event = event_name
	ctx.log("Event '%s'" % event_name)
	_first_half(ctx, event_name)
	_second_half(ctx, event_name)
	NemesisAI.log_line(state, "; ".join(ctx.log_lines))


static func _players(ctx: EffectContext) -> int:
	return ctx.state.players.size()


# --- Top halves ---------------------------------------------------------------

static func _first_half(ctx: EffectContext, event_name: String) -> void:
	var state: GameState = ctx.state
	match event_name:
		"Aezhers Essence":
			# Place 1 SALT on each unexplored hex that shows SALT. If you flip that hex, gain it.
			for t: HexTileState in state.hexes.values():
				var c: HexCard = EffectUtil.hex_card(ctx.card_db, t.hex_card_name)
				if not t.explored and c != null and c.salt.strip_edges().is_valid_int():
					t.bonus_salt += 1
		"Exiles from the South":
			# Every player may place 1 AP on the Trade Action to gain 1 Item they can Use (or 2 AP for one they can't).
			for p: PlayerFactionState in state.players:
				if p.action_points < 1:
					continue
				var pick: String = _best_market_item(ctx, p)
				if pick.is_empty():
					continue
				p.action_points -= 1
				state.item_market.erase(pick)
				ChapterFlow.refill_row(state.item_market, state.item_deck, state.item_discard, 3, state)
				p.items_in_hand.append(pick)
				ctx.log("%s spends 1 AP for '%s'" % [p.faction, pick])
		"Starving Mobs":
			# Every player places 1 Wall and 1 Tower on their Haven.
			for p2: PlayerFactionState in state.players:
				var haven: Vector2i = _least_defended_haven(state, p2.faction)
				if haven != Vector2i.MIN:
					state.hexes[haven].wall = true
					state.hexes[haven].tower = true
		"The Last Harvest":
			EachPlayerOp.new([GainResourceOp.new("Food", 2)], false).execute(ctx)
		"Three Bloody Comets":
			# Roll; with 2 SHIELD or 2 BOLT you may swap a Druid - declined.
			var r: Dictionary = HexEffectPrograms.roll_best_hero(ctx, "white")
			ctx.log("Druid swap %s (declined)" % ("earned" if int(r["Shield"]) >= 2 or int(r["Bolt"]) >= 2 else "not earned"))
		"Turmoil grips the Lands":
			_skeletons_on(ctx, 2, _unexplored_empty(state))
		"Uprising":
			# Every player may place 2 AP on the Market Action to place their cheapest Elite on their home hex.
			for p3: PlayerFactionState in state.players:
				if p3.action_points < 2:
					continue
				var home: Vector2i = _home_of(state, p3.faction)
				var elite: String = _cheapest_reserve_elite(state, p3)
				if home == Vector2i.MIN or elite.is_empty() or not _can_place_units(state, home, p3.faction):
					continue
				p3.action_points -= 2
				state.hexes[home].add_units(p3.faction, elite, 1)
				ctx.log("%s spends 2 AP to place 1 %s at home" % [p3.faction, elite])
		"Long live the Emperor", "The Empire strikes":
			NemesisAI.add_garrisons(state, state.capital_coord, _players(ctx))
		"Madness sweeps the Land":
			HexEffectPrograms.draw_then_discard_feat(state, ctx.card_db)
		"Prolonged Eclipse":
			_garrison_on_every_garrison(state)
			_flip_one(ctx)
			NemesisAI.place_skeleton_with_others(state, ctx.card_db, 1)
		"Slave Revolts":
			# Every player may pay 2 resources to place 2 Basic Units on a Haven or explored empty hex.
			var quest_flow: GDScript = load(QUEST_FLOW_PATH)
			var original: String = ctx.acting_faction
			for p4: PlayerFactionState in state.players:
				if quest_flow._total_resources(p4) < 2:
					continue
				quest_flow._pay_any(p4, 2)
				ctx.acting_faction = p4.faction
				PlaceUnitOp.new(2, "haven_or_empty_explored").execute(ctx)
			ctx.acting_faction = original
		"The Frozen Fleet":
			EachPlayerOp.new([GainResourceOp.new("Any", 4)], false).execute(ctx)
		"The God Touched":
			ctx.log("Feat-for-Bolts-on-Curses offer declined")
		"Unholy Omens":
			_skeletons_on(ctx, 2, _unexplored_empty(state))
			_garrisons_on_one_hex(ctx, 3)
		"A new Dawn":
			_clear_worst(ctx, "Garrison")
			_clear_worst(ctx, "Skeleton")
			state.legion_deck_tokens += 1
			state.horde_deck_tokens += 1
		"Guidance from the Druids":
			var r2: Dictionary = HexEffectPrograms.roll_best_hero(ctx, "white")
			var symbols: int = int(r2["Skull"]) + int(r2["Shield"]) + int(r2["Bolt"])
			if symbols >= 6:
				for fp: PlayerFactionState in state.players:
					GameActions.CardAbilities.draw_feat(state, ctx.card_db, fp)
				ctx.log("Every player draws 1 Feat")
		"Imperial Inspection":
			var r3: Dictionary = HexEffectPrograms.roll_best_hero(ctx, "white")
			if int(r3["Skull"]) + int(r3["Shield"]) + int(r3["Bolt"]) < 6:
				_discard_quests(ctx, 2)
		"Imperial Spy Network":
			var r4: Dictionary = HexEffectPrograms.roll_best_hero(ctx, "white")
			if int(r4["Skull"]) + int(r4["Shield"]) + int(r4["Bolt"]) < 5:
				for fp2: PlayerFactionState in state.players:
					if not fp2.feats_in_play.is_empty():
						GameActions.CardAbilities.discard(state, fp2, GameActions.CardAbilities._worst_feat(fp2.feats_in_play))
		"Ravening Hunger":
			for p5: PlayerFactionState in state.players:
				var home2: Vector2i = _home_of(state, p5.faction)
				if home2 != Vector2i.MIN:
					NemesisAI.add_skeletons(state, ctx.card_db, home2, 2)
					NemesisAI.resolve_combat_at(state, ctx.card_db, home2)
		"Corruption of the Witches":
			for p6: PlayerFactionState in state.players:
				NemesisAI.NemesisCards.send_unit_to_graveyard(state, p6, "Chaos", true)
		"Designs of the Empress":
			var top_vp: int = -999
			for p7: PlayerFactionState in state.players:
				top_vp = maxi(top_vp, p7.vp)
			if state.empire_vp < top_vp:
				state.empire_vp += 5
			if state.chaos_vp < top_vp:
				state.chaos_vp += 5
		"Endless Snowfall":
			var r5: Dictionary = HexEffectPrograms.roll_best_hero(ctx, "white")
			if int(r5["Shield"]) < 2 and int(r5["Bolt"]) < 3:
				_discard_quests(ctx, 99)
		"Famine":
			# Every player destroys 1 of their Units (Chaos Graveyard) and places 1 Skeleton on that hex.
			for p8: PlayerFactionState in state.players:
				var spot: Vector2i = _biggest_stack(state, p8.faction)
				if spot == Vector2i.MIN:
					continue
				var tile: HexTileState = state.hexes[spot]
				var unit: String = CombatResolver._cheapest_unit(tile, p8.faction)
				tile.remove_unit(p8.faction, unit)
				_to_graveyard(state, p8, unit, "Chaos")
				NemesisAI.add_skeletons(state, ctx.card_db, spot, 1)
				NemesisAI.resolve_combat_at(state, ctx.card_db, spot)
		"Mass Executions":
			# Every player: 3 Basic Units or 2 Elites (play or reserve) to the Imperial Graveyard.
			for p9: PlayerFactionState in state.players:
				var sent: int = 0
				for _i: int in range(3):
					if NemesisAI.NemesisCards.send_unit_to_graveyard(state, p9, "Empire", false):
						sent += 1
				if sent < 3:
					for _j: int in range(2):
						NemesisAI.NemesisCards.send_unit_to_graveyard(state, p9, "Empire", true)
		"Rain of Ashe and Fire":
			var r6: Dictionary = HexEffectPrograms.roll_best_hero(ctx, "yellow")
			if int(r6["Skull"]) < 5:
				for coord: Vector2i in state.hexes.keys():
					var t2: HexTileState = state.hexes[coord]
					var faction: String = t2.player_faction_here()
					if faction.is_empty():
						continue
					var unit2: String = CombatResolver._cheapest_unit(t2, faction)
					t2.remove_unit(faction, unit2)
					var owner: PlayerFactionState = state.find_player(faction)
					if owner != null:
						_to_graveyard(state, owner, unit2, "Chaos")
		"The Invasion begins":
			for coord2: Vector2i in state.hexes.keys():
				if (state.hexes[coord2] as HexTileState).role == "sea_tower":
					NemesisAI.add_skeletons(state, ctx.card_db, coord2, 2)
					NemesisAI.resolve_combat_at(state, ctx.card_db, coord2)
		"Vision from the Old Gods":
			# Every player may place 1 AP on the Trade Action to draw 1 Feat - taken.
			for fp3: PlayerFactionState in state.players:
				if fp3.action_points >= 1 and not fp3.feat_deck.is_empty():
					fp3.action_points -= 1
					GameActions.CardAbilities.draw_feat(state, ctx.card_db, fp3)


# --- Bottom halves --------------------------------------------------------------

static func _second_half(ctx: EffectContext, event_name: String) -> void:
	var state: GameState = ctx.state
	match event_name:
		"Aezhers Essence":
			# 1 Legion at Threat 4 and its Target on a Sea Tower (it stays); 1 Horde at
			# Threat 4 on an empty hex next to a different Sea Tower; 1 Curse, no X, empty if possible.
			var tower: Vector2i = NemesisAI.NemesisCards.choose_sea_tower(state, true, NemesisAI.legion_prompt(state, 4, "with its Target on a Sea Tower"))
			if tower != Vector2i.MIN:
				NemesisAI.spawn_legion(state, ctx.card_db, tower, 4, {"target": "here"})
			var near_other: Array[Vector2i] = NemesisAI.empty_hexes(state, func(c: Vector2i, _t: HexTileState) -> bool:
				for n: Vector2i in HexMath.neighbors(c):
					var nt: HexTileState = state.get_hex(n)
					if nt != null and nt.role == "sea_tower" and n != tower:
						return true
				return false)
			_horde_at(ctx, NemesisAI.choose_spawn_hex(state, near_other, NemesisAI.horde_prompt(state, 4, "on an empty hex next to another Sea Tower")), 4)
			_curse_no_x(ctx)
		"Exiles from the South":
			_horde_in_region(ctx, "Screaming Sea", 4)
			_horde_in_region(ctx, "Fog Grave", 4)
		"Starving Mobs":
			_horde_in_region(ctx, "Howling White", 4)
			_horde_in_region(ctx, "Screaming Sea", 4)
		"The Last Harvest":
			_horde_in_region(ctx, "Fog Grave", 4)
			_horde_in_region(ctx, "Screaming Sea", 4)
		"Three Bloody Comets":
			_horde_in_region(ctx, "Fog Grave", 4)
			_horde_at(ctx, NemesisAI.NemesisCards.choose_sea_tower(state, true, NemesisAI.horde_prompt(state, 4, "on a Sea Tower")), 4)
		"Turmoil grips the Lands":
			_horde_in_region(ctx, "Howling White", 4)
			_horde_at(ctx, NemesisAI.NemesisCards.choose_sea_tower(state, true, NemesisAI.horde_prompt(state, 4, "on a Sea Tower")), 4)
		"Uprising":
			_horde_in_region(ctx, "Howling White", 4)
			_horde_in_region(ctx, "Fog Grave", 4)
		"Long live the Emperor":
			_legions(ctx, 2, 4)
			if state.hordes.is_empty():
				_horde_on_empty(ctx, 5, [])
			_token_on_horde(ctx)
		"Madness sweeps the Land":
			_legions(ctx, 2, 5)
			_skeleton_next_to_haven(ctx, 1, true)
			activate_all_skeletons(state, ctx.card_db)
		"Prolonged Eclipse":
			_legions(ctx, 2, 5)
		"Slave Revolts":
			_legions(ctx, 2, 5)
			NemesisAI.place_skeleton_with_others(state, ctx.card_db, 1)
			if state.hordes.is_empty():
				_horde_on_empty(ctx, 5, [])
		"The Frozen Fleet":
			_legions(ctx, 2, 5)
			_skeletons_on(ctx, 1, _empty_next_to_haven_first(state))
			activate_all_skeletons(state, ctx.card_db)
		"The God Touched":
			_garrisons_on_one_hex(ctx, 3)
			var tower2: Vector2i = NemesisAI.NemesisCards.choose_sea_tower(state, true, NemesisAI.legion_prompt(state, 5, "on a Sea Tower"))
			if tower2 != Vector2i.MIN:
				NemesisAI.spawn_legion(state, ctx.card_db, tower2, 5, {"target": "capital"})
			var no_x: Array[Vector2i] = NemesisAI.empty_hexes(state, func(_c: Vector2i, t: HexTileState) -> bool:
				return NemesisAI.no_x(t))
			if no_x.is_empty():
				_horde_on_empty(ctx, 5, [])
			else:
				_horde_at(ctx, NemesisAI.choose_spawn_hex(state, no_x, NemesisAI.horde_prompt(state, 5, "on an empty hex without an X")), 5)
		"Unholy Omens":
			_legions(ctx, 1, 5)
			_horde_on_empty(ctx, 5, [])
			_flip_one(ctx)
		"A new Dawn":
			_legions(ctx, 1, 6)
			var tower3: Vector2i = NemesisAI.NemesisCards.choose_sea_tower(state, true, "Place the Hordes at Threat 6 on a Sea Tower")
			for _i: int in range(1 if _players(ctx) == 2 else 2):
				_horde_at(ctx, tower3, 6)
		"Guidance from the Druids":
			_legions(ctx, 1, 6)
			_hordes_same_region(ctx, 1 if _players(ctx) == 2 else 2, 6)
			_skeleton_next_to_haven(ctx, 1, true)
			activate_all_skeletons(state, ctx.card_db)
		"Imperial Inspection":
			_legions(ctx, 2 if _players(ctx) == 2 else 3, 5)
			_activate_extreme(ctx, "Legion", true)
		"Imperial Spy Network":
			_legions(ctx, 2, 5)
			if _players(ctx) >= 3:
				_horde_on_empty(ctx, 5, [])
			NemesisAI.add_garrisons(state, state.capital_coord, _players(ctx))
		"Ravening Hunger":
			_horde_in_region(ctx, "Fog Grave", 5, false)
			_horde_in_region(ctx, "Screaming Sea", 5, false)
			if _players(ctx) >= 3:
				_legions(ctx, 1, 5)
			_activate_extreme(ctx, "Horde", false)
		"The Empire strikes":
			_legions(ctx, 2 if _players(ctx) == 2 else 3, 6)
			_activate_extreme(ctx, "Legion", true)
		"Corruption of the Witches":
			_hordes_same_region(ctx, 2, 5)
			if _players(ctx) >= 3:
				_legions(ctx, 1, 5)
			_skeleton_next_to_haven(ctx, 1, true)
			activate_all_skeletons(state, ctx.card_db)
		"Designs of the Empress":
			_legion_or_horde_each(ctx, 7, "alternate")
			_activate_extreme(ctx, "Legion", true)
			_activate_extreme(ctx, "Horde", false)
		"Endless Snowfall":
			_legion_or_horde_each(ctx, 7, "alternate")
			_activate_extreme(ctx, "Any", true)
		"Famine":
			_legion_or_horde_each(ctx, 6, "alternate")
			_activate_extreme(ctx, "Any", true)
		"Mass Executions":
			_legion_or_horde_each(ctx, 6, "legion_first")
			_activate_extreme(ctx, "Legion", true)
		"Rain of Ashe and Fire":
			_legion_or_horde_each(ctx, 6, "horde_first")
			_activate_extreme(ctx, "Any", false)
		"The Invasion begins":
			_legion_or_horde_each(ctx, 7, "horde_first")
			_activate_extreme(ctx, "Horde", false)
		"Vision from the Old Gods":
			# From the card art: Legion at 7 on The Capital OR Horde at 7 on an empty hex per
			# player, Hordes in different regions; 2 Skeletons on an empty hex next to a Haven
			# if possible; activate all Skeletons.
			_legion_or_horde_each(ctx, 7, "alternate")
			_skeletons_on(ctx, 2, _empty_next_to_haven_first(state))
			activate_all_skeletons(state, ctx.card_db)


# --- Placement helpers ----------------------------------------------------------

static func _legions(ctx: EffectContext, count: int, threat: int) -> void:
	for _i: int in range(count):
		NemesisAI.spawn_legion(ctx.state, ctx.card_db, ctx.state.capital_coord, threat)


static func _horde_at(ctx: EffectContext, coord: Vector2i, threat: int) -> void:
	if coord == Vector2i.MIN:
		_horde_on_empty(ctx, threat, [])
		return
	NemesisAI.spawn_horde(ctx.state, coord, ctx.card_db, threat)


## "Place 1 Horde at Threat N in the <Region>[, not adjacent to a Haven]":
## an empty space of that Region, else one with a Skeleton or Curse (p53),
## else any empty hex.
static func _horde_in_region(ctx: EffectContext, region: String, threat: int, away_from_havens: bool = true) -> void:
	var spaces: Array[Vector2i] = RegionMath.region_hexes(ctx.state, region)
	var ideal: Array[Vector2i] = []
	var empty: Array[Vector2i] = []
	var crowded: Array[Vector2i] = []
	for c: Vector2i in spaces:
		var t: HexTileState = ctx.state.hexes[c]
		if EffectUtil.hex_is_empty(ctx.state, c):
			empty.append(c)
			if not away_from_havens or not NemesisAI.near_haven(ctx.state, c):
				ideal.append(c)
		elif t.skeleton_count > 0 or t.curse:
			crowded.append(c)
	var options: Array[Vector2i] = ideal
	if options.is_empty():
		options = empty
	if options.is_empty():
		options = crowded
	if not options.is_empty():
		NemesisAI.spawn_horde(ctx.state, NemesisAI.choose_spawn_hex(ctx.state, options, NemesisAI.horde_prompt(ctx.state, threat, "in the %s" % region)), ctx.card_db, threat)
		return
	_horde_on_empty(ctx, threat, [])


## "Place 1 Horde on any empty hex" - preferring a Region not in
## `used_regions` ("place each Horde in a different region, if possible").
static func _horde_on_empty(ctx: EffectContext, threat: int, used_regions: Array) -> String:
	var all: Array[Vector2i] = NemesisAI.empty_hexes(ctx.state)
	var fresh: Array[Vector2i] = []
	for c: Vector2i in all:
		if not used_regions.has(RegionMath.region_at(ctx.state, c)):
			fresh.append(c)
	var spot: Vector2i = NemesisAI.choose_spawn_hex(ctx.state, fresh if not fresh.is_empty() else all, NemesisAI.horde_prompt(ctx.state, threat, "on an empty hex"))
	if spot == Vector2i.MIN:
		var fallback: Array[Vector2i] = []
		for c2: Vector2i in ctx.state.hexes.keys():
			var t: HexTileState = ctx.state.hexes[c2]
			if t.skeleton_count > 0 or t.curse:
				fallback.append(c2)
		spot = NemesisAI.choose_spawn_hex(ctx.state, fallback, NemesisAI.horde_prompt(ctx.state, threat, "on a hex with a Skeleton or Curse"))
	if spot == Vector2i.MIN:
		ctx.state.chaos_vp += 1
		return ""
	NemesisAI.spawn_horde(ctx.state, spot, ctx.card_db, threat)
	return RegionMath.region_at(ctx.state, spot)


## "Place N Hordes on any empty hex(es) in the same region."
static func _hordes_same_region(ctx: EffectContext, count: int, threat: int) -> void:
	var best_region: String = ""
	var best_room: int = -1
	for region: String in RegionMath.regions(ctx.state):
		var room: int = 0
		for c: Vector2i in RegionMath.region_hexes(ctx.state, region):
			if EffectUtil.hex_is_empty(ctx.state, c):
				room += 1
		if room > best_room:
			best_room = room
			best_region = region
	for _i: int in range(count):
		_horde_in_region(ctx, best_region, threat, false)


## "For each player, place 1 Legion at Threat N on The Capital or 1 Horde at
## Threat N on any empty hex" (mode "alternate"), or the "...For each you
## cannot, place the other" variants ("legion_first" / "horde_first").
static func _legion_or_horde_each(ctx: EffectContext, threat: int, mode: String) -> void:
	var used: Array = []
	for i: int in range(_players(ctx)):
		var legion: bool = (mode == "legion_first") or (mode == "alternate" and i % 2 == 0)
		if legion and ctx.state.legion_deck.is_empty():
			legion = false
		if not legion and mode == "horde_first" and ctx.state.horde_deck.is_empty():
			legion = true
		if legion:
			_legions(ctx, 1, threat)
		else:
			used.append(_horde_on_empty(ctx, threat, used))


static func _activate_extreme(ctx: EffectContext, kind: String, highest: bool) -> void:
	var pool: Array = []
	if kind != "Horde":
		pool.append_array(ctx.state.legions)
	if kind != "Legion":
		pool.append_array(ctx.state.hordes)
	var pick: Variant = null
	for n: Variant in pool:
		var init: int = NemesisAI.initiative(n.card_name)
		if pick == null or (init > NemesisAI.initiative(pick.card_name) if highest else init < NemesisAI.initiative(pick.card_name)):
			pick = n
	if pick != null:
		ctx.log("%s activates (no token needed)" % pick.card_name)
		NemesisAI.activate_now(ctx.state, ctx.card_db, pick)


static func _token_on_horde(ctx: EffectContext) -> void:
	var pick: HordeInstance = null
	for h: HordeInstance in ctx.state.hordes:
		if pick == null or h.activation_tokens < pick.activation_tokens:
			pick = h
	if pick != null:
		pick.activation_tokens += 1


static func _curse_no_x(ctx: EffectContext) -> void:
	var spots: Array[Vector2i] = []
	var empties: Array[Vector2i] = []
	for c: Vector2i in ctx.state.hexes.keys():
		var t: HexTileState = ctx.state.hexes[c]
		if NemesisAI.no_x(t) and not t.curse:
			spots.append(c)
			if EffectUtil.hex_is_empty(ctx.state, c):
				empties.append(c)
	var spot: Vector2i = NemesisAI.pick_hex(ctx.state, empties if not empties.is_empty() else spots)
	if spot == Vector2i.MIN:
		ctx.state.chaos_vp += 1
	else:
		NemesisAI.place_curse_on(ctx.state, ctx.card_db, spot)


static func _skeletons_on(ctx: EffectContext, count: int, candidates: Array[Vector2i]) -> void:
	var spot: Vector2i = NemesisAI.pick_hex(ctx.state, candidates)
	if spot == Vector2i.MIN:
		ctx.state.chaos_vp += count
		return
	NemesisAI.add_skeletons(ctx.state, ctx.card_db, spot, count)
	NemesisAI.resolve_combat_at(ctx.state, ctx.card_db, spot)


## "Place N Skeleton(s) adjacent to a Haven, on a hex with a Curse if possible."
static func _skeleton_next_to_haven(ctx: EffectContext, count: int, prefer_curse: bool) -> void:
	var near: Array[Vector2i] = []
	var cursed: Array[Vector2i] = []
	for c: Vector2i in ctx.state.hexes.keys():
		var t: HexTileState = ctx.state.hexes[c]
		if not t.haven_faction.is_empty() or not NemesisAI.near_haven(ctx.state, c) or t.skeleton_count >= 2:
			continue
		near.append(c)
		if t.curse:
			cursed.append(c)
	_skeletons_on(ctx, count, cursed if prefer_curse and not cursed.is_empty() else near)


static func _empty_next_to_haven_first(state: GameState) -> Array[Vector2i]:
	var near: Array[Vector2i] = NemesisAI.empty_hexes(state, func(c: Vector2i, _t: HexTileState) -> bool:
		return NemesisAI.near_haven(state, c))
	return near if not near.is_empty() else NemesisAI.empty_hexes(state)


static func _unexplored_empty(state: GameState) -> Array[Vector2i]:
	return NemesisAI.empty_hexes(state, func(_c: Vector2i, t: HexTileState) -> bool:
		return not t.explored)


static func _garrison_on_every_garrison(state: GameState) -> void:
	var stacks: Array[Vector2i] = []
	for c: Vector2i in state.hexes.keys():
		var t: HexTileState = state.hexes[c]
		if t.garrison_level > 0 and t.role != "capital":
			stacks.append(c)
	for c2: Vector2i in stacks:
		NemesisAI.add_garrisons(state, c2, 1)


## "Place 3 Garrisons on any hex with no X, empty if possible."
static func _garrisons_on_one_hex(ctx: EffectContext, count: int) -> void:
	var empties: Array[Vector2i] = NemesisAI.empty_hexes(ctx.state, func(_c: Vector2i, t: HexTileState) -> bool:
		return NemesisAI.no_x(t))
	var spot: Vector2i = NemesisAI.pick_hex(ctx.state, empties)
	if spot == Vector2i.MIN:
		var any: Array[Vector2i] = []
		for c: Vector2i in ctx.state.hexes.keys():
			var t: HexTileState = ctx.state.hexes[c]
			if NemesisAI.no_x(t) and not t.curse and t.total_player_units() == 0:
				any.append(c)
		spot = NemesisAI.pick_hex(ctx.state, any)
	if spot == Vector2i.MIN:
		ctx.state.empire_vp += count
		return
	NemesisAI.add_garrisons(ctx.state, spot, count)


## A new Dawn: remove all Garrisons (no X hexes) / all Skeletons from the
## one hex where they press hardest on a Haven.
static func _clear_worst(ctx: EffectContext, kind: String) -> void:
	var best: Vector2i = Vector2i.MIN
	var best_score: int = -1
	var coords: Array = ctx.state.hexes.keys()
	coords.sort()
	for c: Vector2i in coords:
		var t: HexTileState = ctx.state.hexes[c]
		var amount: int = t.garrison_level if kind == "Garrison" and NemesisAI.no_x(t) else (t.skeleton_count if kind == "Skeleton" else 0)
		if amount <= 0:
			continue
		var score: int = amount * 10 + (5 if NemesisAI.near_haven(ctx.state, c) else 0)
		if score > best_score:
			best_score = score
			best = c
	if best == Vector2i.MIN:
		return
	if kind == "Garrison":
		ctx.state.hexes[best].garrison_level = 0
	else:
		ctx.state.hexes[best].skeleton_count = 0
	ctx.log("all %ss removed from %s" % [kind, best])


## "Flip 1 unexplored hex and resolve its effects" - the first player flips
## the unexplored hex nearest one of their Havens and gains its benefits.
static func _flip_one(ctx: EffectContext) -> void:
	var options: Array[Vector2i] = []
	for c: Vector2i in ctx.state.hexes.keys():
		var t: HexTileState = ctx.state.hexes[c]
		if not t.explored and not t.curse and t.role != "outer":
			options.append(c)
	if options.is_empty():
		return
	options.sort()
	var home: Vector2i = _home_of(ctx.state, ctx.acting_faction)
	var best: Vector2i = options[0]
	if home != Vector2i.MIN:
		for c2: Vector2i in options:
			if HexMath.distance(c2, home) < HexMath.distance(best, home):
				best = c2
	var quest_flow: GDScript = load(QUEST_FLOW_PATH)
	quest_flow._flip_hex(ctx, best, false)


static func _discard_quests(ctx: EffectContext, count: int) -> void:
	for _i: int in range(count):
		if ctx.state.quest_row.is_empty():
			return
		var q: String = ctx.state.quest_row.pop_back()
		ctx.state.quest_discard.append(q)
		for item: Variant in (ctx.state.quest_items.get(q, []) as Array):
			ctx.state.item_discard.append(str(item))
		ctx.state.quest_items.erase(q)
		ctx.log("Quest '%s' discarded" % q)


## "Activate all Skeletons" (rulebook p48): each Skeleton group moves 1 hex
## by the Horde activation rules (no Curse), merges (3 -> a Horde), and
## fights; then the next group.
static func activate_all_skeletons(state: GameState, card_db: Node) -> void:
	var groups: Array[Vector2i] = []
	for c: Vector2i in state.hexes.keys():
		if (state.hexes[c] as HexTileState).skeleton_count > 0:
			groups.append(c)
	groups.sort()
	for c2: Vector2i in groups:
		var tile: HexTileState = state.hexes[c2]
		var n: int = tile.skeleton_count
		if n <= 0:
			continue
		var to: Vector2i = NemesisAI._best_step(state, c2, state.capital_coord, false, "Chaos")
		if to == c2:
			continue
		tile.skeleton_count = 0
		NemesisAI.add_skeletons(state, card_db, to, n)
		NemesisAI.resolve_combat_at(state, card_db, to)


# --- Small lookups ----------------------------------------------------------------

static func _best_market_item(ctx: EffectContext, p: PlayerFactionState) -> String:
	var best: String = ""
	var top: int = -1
	for it: String in ctx.state.item_market:
		if ctx.state.flipped_market.has(it) or not GameActions.hero_can_use_item(ctx.card_db, p, it):
			continue
		var c: int = GameActions.item_cost(ctx.card_db, it)
		if c > top:
			top = c
			best = it
	return best


static func _least_defended_haven(state: GameState, faction: String) -> Vector2i:
	var best: Vector2i = Vector2i.MIN
	var best_score: int = 99
	var coords: Array = state.hexes.keys()
	coords.sort()
	for c: Vector2i in coords:
		var t: HexTileState = state.hexes[c]
		if t.haven_faction != faction:
			continue
		var score: int = (1 if t.wall else 0) + (1 if t.tower else 0)
		if score < best_score:
			best_score = score
			best = c
	return best


static func _home_of(state: GameState, faction: String) -> Vector2i:
	for c: Vector2i in state.hexes.keys():
		var t: HexTileState = state.hexes[c]
		if t.role == "home" and t.owning_faction == faction:
			return c
	return Vector2i.MIN


static func _cheapest_reserve_elite(state: GameState, p: PlayerFactionState) -> String:
	var board: PlayerboardTable.FactionBoard = PlayerboardTable.get_board(p.faction)
	var best: String = ""
	var best_cost: int = 999
	for u: PlayerboardTable.UnitEntry in board.units:
		if u.is_basic() or NemesisAI.NemesisCards.reserve_left(state, p, u.name) <= 0:
			continue
		var c: int = CombatResolver._cost_total(u.cost)
		if c < best_cost:
			best_cost = c
			best = u.name
	return best


## Units of `faction` may be put on `coord`: room left, no other faction's
## Units or Haven, no Nemesis there.
static func _can_place_units(state: GameState, coord: Vector2i, faction: String) -> bool:
	var t: HexTileState = state.get_hex(coord)
	if t == null or t.unit_count(faction) >= HexTileState.MAX_UNITS:
		return false
	if t.total_player_units() > t.unit_count(faction) or (not t.haven_faction.is_empty() and t.haven_faction != faction):
		return false
	return t.garrison_level == 0 and t.skeleton_count == 0 and EffectUtil.nemesis_at(state, coord).is_empty()


static func _biggest_stack(state: GameState, faction: String) -> Vector2i:
	var best: Vector2i = Vector2i.MIN
	var most: int = 0
	var coords: Array = state.hexes.keys()
	coords.sort()
	for c: Vector2i in coords:
		var n: int = (state.hexes[c] as HexTileState).unit_count(faction)
		if n > most:
			most = n
			best = c
	return best


static func _to_graveyard(state: GameState, p: PlayerFactionState, unit_name: String, graveyard: String) -> void:
	var yard: Dictionary = state.imperial_graveyard if graveyard == "Empire" else state.chaos_graveyard
	yard[p.faction] = int(yard.get(p.faction, 0)) + 1
	p.graveyard_units[unit_name] = int(p.graveyard_units.get(unit_name, 0)) + 1
