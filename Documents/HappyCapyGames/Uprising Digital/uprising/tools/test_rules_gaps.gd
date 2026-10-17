extends SceneTree

## Verifies the 2026-10-17 rules-gap pass: real dice faces, Garrison/
## Skeleton dice tables, per-Unit die colors, terrain modifiers,
## graveyards, Skeletons merging into Hordes, Empire-vs-Chaos combat, hex
## production bonus, and the face-up Item/Quest rows.
## Run with: godot --headless --script res://tools/test_rules_gaps.gd --path .

var failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	await process_frame
	_run()
	quit(1 if not failures.is_empty() else 0)


func _run() -> void:
	var card_db: Node = root.get_node("/root/CardDatabase")

	# --- Dice faces re-read from the Dice Distribution card ---
	_check(DiceModel.FACES["purple"][0] == ["Bolt", "Bolt"], "purple top face is Bolt-Bolt")
	_check(DiceModel.FACES["black"][0] == ["Skull", "Skull", "Skull"], "black top face is a triple Skull")

	# --- Per-Unit die colors from the player boards ---
	_check(PlayerboardTable.get_unit("Duerkhar", "Younglings").die == "blue", "Younglings roll blue")
	_check(PlayerboardTable.get_unit("Krowh", "Trolls").die == "black", "Trolls roll black")
	_check(PlayerboardTable.get_unit("Druwhn", "Rangers").die == "purple", "Rangers roll purple")
	_check(PlayerboardTable.get_unit("Mohyar", "Hunters").is_archer(), "Hunters are Archers")

	var state := GameState.new()
	state.horde_deck = ["Oda the Fallen", "Counter of Omens"]  # Oda first: his entry effect adds no Skeletons
	var p := PlayerFactionState.new()
	p.faction = "Duerkhar"
	state.players.append(p)

	# --- Player dice: Archers in Archery+Clash, Riders in Archery only on Badlands ---
	var c1 := Vector2i(1, 0)
	var t1: HexTileState = _hex(state, c1, "Black Ice")  # Ice Waste
	t1.add_units("Duerkhar", "Younglings", 2)
	t1.add_units("Duerkhar", "Spearsingers", 1)
	t1.add_units("Duerkhar", "Koloth", 1)
	var me := CombatResolver.Combatant.new()
	me.kind = "player"
	me.faction = "Duerkhar"
	var arch: Array[String] = CombatResolver._dice(state, t1, me, "archery", "Ice Waste")
	var clash: Array[String] = CombatResolver._dice(state, t1, me, "clash", "Ice Waste")
	_check(_sorted(arch) == ["white"], "Ice Waste Archery: only the Spearsinger's white die, got %s" % [arch])
	_check(_sorted(clash) == ["black", "blue", "blue", "white"], "Clash: every Unit's own die, got %s" % [clash])
	var arch_bad: Array[String] = CombatResolver._dice(state, t1, me, "archery", "Badlands")
	_check(_sorted(arch_bad) == ["black", "white"], "Badlands: the Koloth (Rider) adds its die to Archery, got %s" % [arch_bad])
	t1.haven_faction = "Duerkhar"
	t1.tower = true
	t1.wall = true
	_check(_sorted(CombatResolver._dice(state, t1, me, "archery", "")) == ["white", "white"], "Tower adds a white Archery die")
	_check(CombatResolver._dice(state, t1, me, "clash", "").size() == 6, "Tower + Wall add white + blue in Clash")
	t1.add_units("Duerkhar", "Oathsworn", 1)
	_check(t1.unit_count("Duerkhar") == 5, "5 Units on the hex")
	_check(t1.add_units("Duerkhar", "Oathsworn", 1) == 0, "a 6th Unit is refused (5 per hex)")
	_check(not CombatResolver._dice(state, t1, me, "clash", "Marshes").has("red"), "Marshes turn the Oathsworn's red die white")

	# --- Garrison dice table (rulebook p46) and Highlands ---
	var c2 := Vector2i(2, 0)
	var t2: HexTileState = _hex(state, c2, "Frosthold Pass")
	t2.garrison_level = 2
	var g := CombatResolver.Combatant.new()
	g.kind = "garrison"
	g.faction = "Empire"
	_check(CombatResolver._dice(state, t2, g, "archery", "") == ["white", "white"], "Garrison level 2 Archery: 2 white")
	_check(CombatResolver._dice(state, t2, g, "clash", "") == ["blue", "yellow", "yellow", "white"], "Garrison level 2 Clash: blue, yellow, yellow, white")
	_check(CombatResolver._dice(state, t2, g, "archery", "Highlands").size() == 1, "Highlands: only 1 Archery die")
	_check(EffectUtil.combat_terrain(t2, card_db) == "Highlands", "explored Frosthold Pass fights as Highlands")
	t2.explored = false
	_check(EffectUtil.combat_terrain(t2, card_db) == "", "an unexplored hex has no terrain")
	t2.curse = true
	_check(EffectUtil.combat_terrain(t2, card_db) == "Curse", "a Curse replaces the terrain")

	# --- Skeleton dice + 3 Skeletons become a Horde ---
	var c3 := Vector2i(3, 0)
	var t3: HexTileState = _hex(state, c3, "Grim Fangs")
	var log: Array[String] = []
	CombatResolver.add_skeletons(state, c3, 2, log, card_db)
	var sk := CombatResolver.Combatant.new()
	sk.kind = "skeleton"
	sk.faction = "Chaos"
	_check(CombatResolver._dice(state, t3, sk, "clash", "") == ["red", "red"], "2 Skeletons roll 2 red in Clash")
	_check(CombatResolver._dice(state, t3, sk, "archery", "").is_empty(), "Skeletons have no Archery dice")
	CombatResolver.add_skeletons(state, c3, 1, log, card_db)
	_check(t3.skeleton_count == 0 and state.hordes.size() == 1 and state.hordes[0].coord == c3, "a 3rd Skeleton turns the stack into a Horde (%s)" % [log])

	# --- Graveyards: player Units killed by a Legion go to the Imperial Graveyard ---
	var c4 := Vector2i(4, 0)
	var t4: HexTileState = _hex(state, c4, "Black Ice")
	t4.add_units("Duerkhar", "Younglings", 1)
	t4.haven_faction = "Duerkhar"
	var legion := LegionInstance.new()
	legion.card_name = "The Warlock"
	legion.threat = 7
	legion.coord = c4
	state.legions.append(legion)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var r: CombatResolver.Result = CombatResolver.resolve_hex(state, c4, card_db, rng)
	if t4.unit_count("Duerkhar") == 0:
		_check(int(state.imperial_graveyard.get("Duerkhar", 0)) == 1, "the lost Youngling is in the Imperial Graveyard")
		_check(t4.haven_faction.is_empty(), "Haven removed after losing every Unit to the Legion")
	else:
		_check(not state.legions.has(legion), "if the Youngling survived, the Legion must be gone (%s)" % [r.log])

	# --- Empire vs Chaos: a Garrison and Skeletons on one hex fight each other ---
	var c5 := Vector2i(5, 0)
	var t5: HexTileState = _hex(state, c5, "Black Ice")
	t5.garrison_level = 1
	t5.skeleton_count = 1
	_check(CombatResolver.hex_needs_combat(state, c5), "Garrison + Skeleton on one hex need a combat")
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 8
	CombatResolver.resolve_hex(state, c5, card_db, rng2)
	_check(t5.garrison_level == 0 or t5.skeleton_count == 0 or state.hordes.size() > 1, "Empire-vs-Chaos fought to a finish")
	var graves: int = int(state.chaos_graveyard.get("Empire", 0)) + int(state.imperial_graveyard.get("Chaos", 0))
	_check(graves >= 1, "the loser went to the other side's Graveyard")

	# --- Production: Haven hex resources come from the Hexes CSV ---
	var pstate := GameState.new()
	var kp := PlayerFactionState.new()
	kp.faction = "Krowh"
	pstate.players.append(kp)
	var rigga: HexTileState = _hex(pstate, Vector2i(0, 1), "Rigga")  # Marshes, 2 Food
	rigga.haven_faction = "Krowh"
	_check(EffectUtil.hex_production(rigga, card_db)["Food"] == 2, "Rigga produces 2 Food")
	pstate.phase = GameState.Phase.NEMESIS
	ChapterFlow.advance_phase(pstate, card_db)
	# Krowh board with 1 Haven: 1 Salt, 0 Plunder, 3 Food; plus Rigga's 2 Food.
	_check(kp.food == 5 and kp.salt == 1, "Production = board (1 Haven) + Rigga bonus, got S%d P%d F%d" % [kp.salt, kp.plunder, kp.food])

	# --- Refresh deals 3 Items and 3 Quests, discarding the old ones ---
	var rs: GameState = GameSetup.build_2p_normal_game_state(card_db, rng)
	var deck_before: int = rs.item_deck.size()
	ChapterFlow.advance_phase(rs, card_db)  # REFRESH -> EVENTS
	_check(rs.item_market.size() == 3 and rs.quest_row.size() == 3, "Refresh deals 3 Items + 3 Quests")
	_check(rs.item_deck.size() == deck_before - 3, "the Items came off the deck")
	var first_items: Array[String] = rs.item_market.duplicate()
	ChapterFlow._refresh_phase(rs, card_db)
	_check(rs.item_discard == first_items, "the next Refresh discards the old Items")

	# --- Market: buy a face-up Item at its CSV Salt cost ---
	rs.phase = GameState.Phase.ACTIONS
	rs.current_player_index = 0
	var buyer: PlayerFactionState = rs.players[0]
	buyer.salt = 20
	buyer.has_acted_this_turn = false
	var item: String = rs.item_market[0]
	var cost: int = GameActions.item_cost(card_db, item)
	var mr: Dictionary = GameActions.apply(rs, {"type": "market", "item": item}, buyer.faction, card_db)
	_check(mr.get("ok", false), "Market buy succeeds: %s" % mr.get("reason", ""))
	_check(buyer.salt == 20 - cost and buyer.items_in_hand.has(item) and not rs.item_market.has(item), "paid %d Salt and the Item left the Market" % cost)

	_impassable_checks(card_db)
	_region_and_hero_checks(card_db)
	_quest_checks(card_db)
	_nemesis_entry_checks(card_db)
	_event_checks(card_db)
	_card_power_checks(card_db)
	_economy_checks(card_db)

	# --- Save/load keeps typed Units ---
	var round_trip: GameState = GameState.from_dict(state.to_dict())
	_check(round_trip.get_hex(c1).unit_stack("Duerkhar") == t1.unit_stack("Duerkhar"), "typed Unit stacks survive to_dict/from_dict")
	var legacy := HexTileState.from_dict({"units": {"Krowh": 2}})
	_check(legacy.unit_stack("Krowh") == {"Tribesmen": 2}, "old count-only saves load as Basic Warriors")

	_report()


## Impassable terrain: Rigga's art has mountains on its NE and NW edges.
func _impassable_checks(card_db: Node) -> void:
	_check(HexMath.clockwise_index(Vector2i.ZERO, Vector2i(0, -1)) == 0 and HexMath.clockwise_index(Vector2i.ZERO, Vector2i(1, 0)) == 2, "clockwise directions start at N")
	var s := GameState.new()
	for c: Vector2i in HexMath.spiral(Vector2i.ZERO, 2):
		_hex(s, c, "")
	var rigga: HexTileState = _hex(s, Vector2i.ZERO, "Rigga")
	_check(s.edge_blocked(Vector2i.ZERO, Vector2i(1, -1)) and s.edge_blocked(Vector2i(1, -1), Vector2i.ZERO), "Rigga blocks its NE edge, from both sides")
	_check(s.edge_blocked(Vector2i.ZERO, Vector2i(-1, 0)), "Rigga blocks its NW edge")
	_check(not s.edge_blocked(Vector2i.ZERO, Vector2i(0, -1)), "Rigga's N edge is open")
	rigga.rotation = 1
	_check(s.edge_blocked(Vector2i.ZERO, Vector2i(1, 0)) and s.edge_blocked(Vector2i.ZERO, Vector2i(0, -1)) and not s.edge_blocked(Vector2i.ZERO, Vector2i(1, -1)), "rotating 1 step clockwise moves the blocks to SE and N")
	rigga.rotation = 0
	rigga.explored = false
	_check(not s.edge_blocked(Vector2i.ZERO, Vector2i(1, -1)), "an unexplored hex shows no impassable terrain")
	rigga.explored = true

	var routes: Dictionary = s.route_distances(Vector2i.ZERO)
	_check(int(routes.get(Vector2i(1, -1), -1)) == 2, "route from the NE neighbor goes around the mountains (2 steps), got %s" % routes.get(Vector2i(1, -1)))
	var step: Vector2i = NemesisAI._best_step(s, Vector2i(1, -1), Vector2i.ZERO, true, "Empire")
	_check(step == Vector2i(0, -1) or step == Vector2i(1, 0), "a Legion walks around impassable terrain instead of across, stepped to %s" % step)

	# Command: blocked across the mountains, allowed from an explored Sea Tower.
	var p := PlayerFactionState.new()
	p.faction = "Krowh"
	p.action_points = 8
	p.food = 5
	s.players.append(p)
	s.phase = GameState.Phase.ACTIONS
	s.ensure_hex(Vector2i(1, -1)).add_units("Krowh", "Tribesmen", 1)
	var blocked: Dictionary = GameActions.apply(s, {"type": "command", "to": {"x": 0, "y": 0},
		"units": [{"from": {"x": 1, "y": -1}, "unit": "Tribesmen", "count": 1}]}, "Krowh", card_db)
	_check(not blocked.get("ok", false), "Command across impassable terrain is refused")
	var tower: HexTileState = _hex(s, Vector2i(0, 2), "Guragi Tower")
	tower.role = "sea_tower"
	tower.add_units("Krowh", "Deadeyes", 1)
	var via_tower: Dictionary = GameActions.apply(s, {"type": "command", "to": {"x": 1, "y": -1},
		"units": [{"from": {"x": 0, "y": 2}, "unit": "Deadeyes", "count": 1}]}, "Krowh", card_db)
	_check(via_tower.get("ok", false) and s.get_hex(Vector2i(1, -1)).unit_count("Krowh") == 2, "Units on an explored Sea Tower reach a hex 3 steps away: %s" % via_tower.get("reason", ""))
	GameActions.apply(s, {"type": "end_turn"}, "Krowh", card_db)

	# Explore -> the explorer may orient the hex until their turn ends.
	var fh: HexTileState = _hex(s, Vector2i(-1, 2), "Frosthold Pass")
	fh.explored = false
	p.hero_coord = Vector2i(-1, 2)
	var ex: Dictionary = GameActions.apply(s, {"type": "explore", "at": {"x": -1, "y": 2}}, "Krowh", card_db)
	_check(ex.get("ok", false) and fh.orientable_by == "Krowh", "Explore lets the explorer orient Frosthold Pass")
	_check(not GameActions.apply(s, {"type": "orient", "at": {"x": -1, "y": 2}, "rotation": 2}, "Druwhn", card_db).get("ok", false), "another faction can't orient it")
	_check(GameActions.apply(s, {"type": "orient", "at": {"x": -1, "y": 2}, "rotation": 3}, "Krowh", card_db).get("ok", false) and fh.rotation == 3, "the explorer turns it to rotation 3")
	GameActions.apply(s, {"type": "end_turn"}, "Krowh", card_db)
	_check(fh.orientable_by.is_empty(), "orientation locks when the turn ends")
	_check(HexTileState.from_dict(fh.to_dict()).rotation == 3, "rotation survives save/load")


## Regions as printed on the board, the full 37-space board, Hero movement.
func _region_and_hero_checks(card_db: Node) -> void:
	_check(RegionMath.region_for(Vector2i(0, -3)) == "Screaming Sea", "north tip is Screaming Sea")
	_check(RegionMath.region_for(Vector2i(0, 3)) == "Howling White", "south tip is Howling White")
	_check(RegionMath.region_for(Vector2i(3, -1)) == "Fog Grave", "east edge is Fog Grave")
	_check(RegionMath.region_for(Vector2i.ZERO) == "Screaming Sea", "the center space is printed Screaming Sea")
	_check(RegionMath.region_for(Vector2i(4, 0)).is_empty(), "off the 37-hex board there is no Region")
	var counts: Dictionary = {}
	for c: Vector2i in HexMath.spiral(Vector2i.ZERO, 3):
		var reg: String = RegionMath.region_for(c)
		counts[reg] = int(counts.get(reg, 0)) + 1
	_check(counts == {"Screaming Sea": 13, "Howling White": 12, "Fog Grave": 12}, "wedges are 13/12/12, got %s" % counts)

	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var s: GameState = GameSetup.build_2p_normal_game_state(card_db, rng)
	_check(s.hexes.size() == 37, "the whole 37-space board exists, got %d" % s.hexes.size())
	var covered: int = 0
	for t: HexTileState in s.hexes.values():
		if t.role != "outer":
			covered += 1
	var uncovered: int = 0
	for reg: String in RegionMath.REGIONS:
		uncovered += RegionMath.region_hexes(s, reg).size()
	_check(uncovered == 37 - covered, "only uncovered spaces count as Region hexes (%d)" % uncovered)

	var p: PlayerFactionState = s.players[0]
	_check(s.get_hex(p.hero_coord).role == "home", "the Hero starts on the home hex")
	s.phase = GameState.Phase.ACTIONS
	s.current_player_index = 0
	var start: Vector2i = p.hero_coord
	var far: Vector2i = start + Vector2i(0, 2) if s.hexes.has(start + Vector2i(0, 2)) else start + Vector2i(0, -2)
	_check(not GameActions.apply(s, {"type": "move", "to": {"x": far.x, "y": far.y}}, p.faction, card_db).get("ok", false), "Move 2 hexes away is refused")
	var next: Vector2i = Vector2i.MIN
	for n: Vector2i in HexMath.neighbors(start):
		if s.hexes.has(n):
			next = n
			break
	var mv: Dictionary = GameActions.apply(s, {"type": "move", "to": {"x": next.x, "y": next.y}}, p.faction, card_db)
	_check(mv.get("ok", false) and p.hero_coord == next and p.action_points == 7, "Move steps the Hero to a neighbor for 1 AP")
	_check(not GameActions.apply(s, {"type": "explore", "at": {"x": start.x, "y": start.y}}, p.faction, card_db).get("ok", false), "Explore elsewhere than the Hero's hex is refused")
	var pool: Array[String] = DiceModel.hero_pool(EffectUtil.hero_card(card_db, "Hanzo"), "white")
	pool.sort()
	_check(pool == ["purple", "white", "white", "white"], "Hanzo's Hero Dice: 1 purple + 3 Guile dice, got %s" % [pool])


## Quest goals, rewards, solve/failure effects and what happens to the card.
func _quest_checks(card_db: Node) -> void:
	var quest_flow: GDScript = load("res://scripts/game/quest_flow.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var s: GameState = GameSetup.build_2p_normal_game_state(card_db, rng)
	ChapterFlow.refill_row(s.item_market, s.item_deck, s.item_discard, 3)
	var p: PlayerFactionState = s.players[0]
	s.quest_row = ["Intercept the Empress"]
	var q: QuestCard = quest_flow.card(card_db, "Intercept the Empress")
	_check(quest_flow.goals(q) == {"successes": 2, "Skull": 4, "Shield": 1, "Bolt": 2}, "Intercept the Empress goals parse as 2+ of 4 Skull / 1 Shield / 2 Bolt")
	# Ice Waste bonus die: the Hero on a Region space (explored Ice Waste).
	for c: Vector2i in s.hexes.keys():
		if s.hexes[c].role == "outer":
			p.hero_coord = c
			break
	_check(quest_flow.bonus_dice(s, card_db, p, q) == ["red"], "Hero on Ice Waste earns Intercept's +1 RED")
	var vp0: int = p.vp
	var salt0: int = p.salt
	var items0: int = p.items_in_hand.size()
	var r: Dictionary = quest_flow.attempt(s, card_db, p.faction, "Intercept the Empress", {"fixed_roll": {"Skull": 4, "Shield": 0, "Bolt": 2}})
	_check(r.get("solved", false), "4 Skulls + 2 Bolts meet 2 goals: solved")
	_check(p.vp == vp0 + 2 and p.salt == salt0 + 3, "rewards: Skull goal 2 VP, Bolt goal 3 Salt (VP %d->%d, Salt %d->%d)" % [vp0, p.vp, salt0, p.salt])
	_check(p.items_in_hand.size() == items0 + 1, "solve: gained 1 Item from the Market")
	_check(not s.quest_row.has("Intercept the Empress") and s.quest_discard.has("Intercept the Empress"), "'Discard this Quest' discards it")

	s.quest_row = ["Intercept the Empress"]
	var empire0: int = s.empire_vp
	var r2: Dictionary = quest_flow.attempt(s, card_db, p.faction, "Intercept the Empress", {"fixed_roll": {"Skull": 1, "Shield": 1, "Bolt": 0}})
	_check(not r2.get("solved", true) and s.empire_vp == empire0 + 2, "only 1 goal met: failed, The Empire gains 2 VP")

	s.quest_row = ["Tua Than Allies"]
	quest_flow.attempt(s, card_db, p.faction, "Tua Than Allies", {"fixed_roll": {"Skull": 3, "Shield": 0, "Bolt": 0}})
	_check(p.quests_in_play.has("Tua Than Allies") and not s.quest_row.has("Tua Than Allies"), "'Gain this card' moves the solved Quest in front of the player")

	s.quest_row = ["Instruction of the Druids"]
	var chaos0: int = s.chaos_vp
	quest_flow.attempt(s, card_db, p.faction, "Instruction of the Druids", {"fixed_roll": {"Skull": 0, "Shield": 0, "Bolt": 0}})
	_check(s.quest_row.has("Instruction of the Druids") and s.chaos_vp == chaos0 + 1, "failure 'Chaos gains 1 VP' (no discard) leaves the Quest in the row")


## New Legions get a Target and their immediate effect; Hordes too.
func _nemesis_entry_checks(card_db: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var s: GameState = GameSetup.build_2p_normal_game_state(card_db, rng)
	var p: PlayerFactionState = s.players[0]
	s.legion_deck = ["The Courtesan", "The Imperial Guard"]
	var ap0: int = p.max_action_points
	var courtesan: LegionInstance = NemesisAI.spawn_legion(s, card_db, s.capital_coord, 4)
	_check(courtesan != null and courtesan.has_target and courtesan.target_faction == p.faction, "the first Legion targets the first player's Haven")
	_check(courtesan.target_coord == p.hero_coord, "its Target sits on that faction's (home) Haven")
	_check(p.max_action_points == ap0 - 1, "Dark Lullaby: the targeted player loses 1 AP for the rest of the game")
	var guard_stacks: int = 0
	for t: HexTileState in s.hexes.values():
		if t.garrison_level > 0 and t.role != "capital":
			guard_stacks += t.garrison_level
	var guard: LegionInstance = NemesisAI.spawn_legion(s, card_db, s.capital_coord, 4)
	var after: int = 0
	for t2: HexTileState in s.hexes.values():
		if t2.garrison_level > 0 and t2.role != "capital":
			after += t2.garrison_level
	_check(guard != null and guard.target_faction == s.players[1].faction, "the second Legion targets the other faction")
	_check(after > guard_stacks, "Defensive Stance stacks a Garrison on every Garrison hex (%d -> %d levels)" % [guard_stacks, after])
	_check(NemesisAI.spawn_legion(s, card_db, s.capital_coord, 4) == null, "an empty Legion deck gives The Empire 1 VP instead")

	s.horde_deck = ["Counter of Omens", "Oda the Fallen"]
	var spot: Vector2i = NemesisAI.pick_hex(s, NemesisAI.empty_hexes(s))
	var counter: HordeInstance = NemesisAI.spawn_horde(s, spot, card_db, 4)
	_check(counter != null and s.get_hex(spot).skeleton_count == 2, "Army of Bone: 2 Skeletons on the Counter's hex")
	var oda: HordeInstance = NemesisAI.spawn_horde(s, spot, card_db, 4)
	_check(oda != null and oda.threat == 6 and counter.threat == 5, "Doomsday: Oda +2 Threat, every other Horde +1")

	# A Haven that falls moves its Target to the faction's next Haven, else The Capital.
	NemesisAI.remove_haven(s, card_db, courtesan.target_coord)
	_check(courtesan.target_faction == "Capital" and courtesan.target_coord == s.capital_coord, "losing its only Haven sends the Target to The Capital")


## Chapter Events: picked at setup, resolved in the Events Phase.
func _event_checks(card_db: Node) -> void:
	var event_effects: GDScript = load("res://scripts/game/event_effects.gd")
	_check(event_effects.PRINTED_THREAT.size() == 28, "all 28 Core Events have a printed Threat")
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var s: GameState = GameSetup.build_2p_normal_game_state(card_db, rng)
	_check(s.chapter_events.size() == 2, "a 2-Chapter game gets 2 Events, got %s" % [s.chapter_events])
	var ch1: EventCard = null
	for e: EventCard in card_db.events:
		if e.card_name == str(s.chapter_events.get(1, "")):
			ch1 = e
	_check(ch1 != null and ch1.nr == "One", "Chapter 1's Event comes from the Chapter I deck")

	var food0: Array[int] = []
	for p: PlayerFactionState in s.players:
		food0.append(p.food)
	s.horde_deck = ["Lichqueen", "Oda the Fallen", "Bloodwyrm"]  # none of these relocate on entry
	var deck0: int = s.horde_deck.size()
	event_effects.resolve(s, card_db, "The Last Harvest")
	_check(s.players[0].food == food0[0] + 2 and s.players[1].food == food0[1] + 2, "The Last Harvest: every player gains 2 Food")
	_check(s.horde_deck.size() == deck0 - 2 and s.hordes.size() >= 2, "The Last Harvest: 2 Hordes enter")
	var regions: Array[String] = []
	for h: HordeInstance in s.hordes:
		regions.append(RegionMath.region_for(h.coord, s.capital_coord))
		_check(s.get_hex(h.coord).role == "outer" and not NemesisAI.near_haven(s, h.coord), "%s stands on a Region space away from Havens" % h.card_name)
	_check(regions.has("Fog Grave") and regions.has("Screaming Sea"), "one Horde in the Fog Grave, one in the Screaming Sea, got %s" % [regions])
	_check(s.latest_event == "The Last Harvest" and NemesisAI.event_threat(s, card_db, "Horde") == 4, "the latest Event's printed Threat (4) is the default")

	s.legion_deck = ["The Warlock", "The Spymaster"]  # entry effects that don't move anyone
	var legions0: int = s.legions.size()
	event_effects.resolve(s, card_db, "Long live the Emperor")
	_check(s.legions.size() == legions0 + 2, "Long live the Emperor: 2 Legions enter on The Capital")
	var targeted: Dictionary = {}
	for l: LegionInstance in s.legions:
		if l.has_target:
			targeted[l.target_faction] = true
	_check(targeted.size() == 2, "each faction gets a Target from one of them, got %s" % [targeted])

	# Activate all Skeletons: a lone group steps toward The Capital.
	var t: GameState = GameSetup.build_2p_normal_game_state(card_db, rng)
	var before: Dictionary = {}
	for c: Vector2i in t.hexes.keys():
		if t.hexes[c].skeleton_count > 0:
			before[c] = t.hexes[c].skeleton_count
	event_effects.activate_all_skeletons(t, card_db)
	var moved: int = 0
	for c2: Vector2i in before.keys():
		if t.hexes[c2].skeleton_count == 0:
			moved += 1
	_check(moved > 0, "Activate all Skeletons moves the Skeleton groups (%d of %d moved)" % [moved, before.size()])

	# Events Phase integration: the Chapter's Event resolves on advancing past EVENTS.
	t.phase = GameState.Phase.EVENTS
	ChapterFlow.advance_phase(t, card_db)
	_check(t.latest_event == str(t.chapter_events[1]), "the Events Phase reveals and resolves Chapter 1's Event")


## Legion/Horde combat abilities, bottom effects, The Capital, the Warlock.
func _card_power_checks(card_db: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var s: GameState = GameSetup.build_2p_normal_game_state(card_db, rng)
	var p: PlayerFactionState = s.players[0]
	var spot: Vector2i = Vector2i.MIN
	for c: Vector2i in s.hexes.keys():
		if s.hexes[c].role == "outer" and EffectUtil.hex_is_empty(s, c):
			spot = c
			break
	var tile: HexTileState = s.hexes[spot]

	var assassin := LegionInstance.new()
	assassin.card_name = "The Assassin"
	assassin.threat = 4
	assassin.coord = spot
	s.legions.append(assassin)
	var side := CombatResolver.Combatant.new()
	side.kind = "legion"
	side.faction = "Empire"
	side.legion = assassin
	var base: int = CombatResolver._dice(s, tile, side, "archery", "", spot).size()
	_check(CombatResolver._dice(s, tile, side, "archery", "Badlands", spot).size() == base + 2, "The Assassin gains 2 red in Archery on Badlands")

	var executioner := LegionInstance.new()
	executioner.card_name = "The Executioner"
	executioner.threat = 4
	executioner.coord = spot
	s.legions.append(executioner)
	var ex_side := CombatResolver.Combatant.new()
	ex_side.kind = "legion"
	ex_side.faction = "Empire"
	ex_side.legion = executioner
	var without: int = CombatResolver._dice(s, tile, ex_side, "clash", "", spot).size()
	assassin.has_target = true
	assassin.target_coord = spot
	_check(CombatResolver._dice(s, tile, ex_side, "clash", "", spot).size() == without + 1, "The Executioner gains 1 purple with a Target on the hex")
	s.legions.erase(assassin)
	s.legions.erase(executioner)

	# Bottom effects.
	var spymaster := LegionInstance.new()
	spymaster.card_name = "The Spymaster"
	spymaster.threat = 1
	spymaster.coord = spot
	s.legions.append(spymaster)
	ChapterFlow.refill_row(s.item_market, s.item_deck, s.item_discard, 3)
	s.flipped_market.append(s.item_market[0])
	var vp0: int = p.vp
	CombatResolver.destroy_nemesis(s, card_db, spymaster, p.faction, spot)
	_check(not s.legions.has(spymaster) and p.vp == vp0 + 4, "The Spymaster destroyed: +4 VP to the player")
	_check(s.flipped_market.is_empty() and s.item_market.size() == 3, "his flipped Market Items are discarded and the Market refilled")

	s.horde_deck = ["Coven of Yssat"]
	var coven: HordeInstance = NemesisAI.spawn_horde(s, spot, card_db, 4, {"no_combat": true})
	var max_ap: int = p.max_action_points
	CombatResolver.destroy_nemesis(s, card_db, coven, "Empire", spot)
	_check(p.max_action_points == max_ap + 1 and s.coven_held_ap.is_empty(), "the Coven gone (even by The Empire): every player gets their AP back")

	# The Capital's ongoing effect.
	var cap: HexTileState = s.get_hex(s.capital_coord)
	cap.garrison_level = 0
	for l: LegionInstance in s.legions.duplicate():
		if l.coord == s.capital_coord:
			s.legions.erase(l)
	s.legion_deck = ["The Warlock"]
	cap.add_units(p.faction, PlayerboardTable.default_unit(p.faction), 1)
	NemesisAI.check_capital(s, card_db)
	var legion_here: bool = false
	for l2: LegionInstance in s.legions:
		if l2.card_name == "The Warlock" and l2.coord == s.capital_coord:
			legion_here = true
	_check(legion_here or cap.unit_count(p.faction) == 0, "only rebels on The Capital: a Legion is placed there and fights")
	s.legion_deck.clear()
	cap.garrison_level = 0
	for l3: LegionInstance in s.legions.duplicate():
		if l3.coord == s.capital_coord:
			s.legions.erase(l3)
	cap.units.clear()
	cap.add_units(p.faction, PlayerboardTable.default_unit(p.faction), 1)
	var vp1: int = p.vp
	NemesisAI.check_capital(s, card_db)
	_check(s.capital_flipped and p.vp == vp1 + 5, "no Legion left: The Capital flips and its holder gains 5 VP")

	# The Warlock is always adjacent to any hex: straight to his Target.
	var far_haven: Vector2i = p.hero_coord
	var step: Vector2i = NemesisAI._best_step(s, s.capital_coord + Vector2i(3, -3), far_haven, true, "Empire", "The Warlock")
	_check(step == far_haven, "The Warlock moves straight onto his Target")


## 3:1 exchange, Hero-to-Hero trades, the Haven limit, final VP purchase.
func _economy_checks(card_db: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 52
	var s: GameState = GameSetup.build_2p_normal_game_state(card_db, rng)
	var a: PlayerFactionState = s.players[0]
	var b: PlayerFactionState = s.players[1]
	a.food = 3
	a.salt = 0
	_check(GameActions.apply(s, {"type": "exchange", "give": "Food", "get": "Salt"}, a.faction, card_db).get("ok", false) and a.food == 0 and a.salt == 1, "3 Food become 1 Salt, no AP")
	_check(not GameActions.apply(s, {"type": "exchange", "give": "Food", "get": "Salt"}, a.faction, card_db).get("ok", false), "exchange needs 3 of the resource")

	a.action_points = 3
	_check(not GameActions.apply(s, {"type": "trade", "with": b.faction, "give": {"Salt": 1}}, a.faction, card_db).get("ok", false), "trading needs both Heroes on one hex")
	b.hero_coord = a.hero_coord
	a.plunder = 4
	var b_plunder: int = b.plunder
	var t: Dictionary = GameActions.apply(s, {"type": "trade", "with": b.faction, "give": {"Plunder": 3}}, a.faction, card_db)
	_check(t.get("ok", false) and a.plunder == 1 and b.plunder == b_plunder + 3 and a.salt == 2, "Trade: 1 Salt for the AP and 3 Plunder handed over")

	for c: Vector2i in s.hexes.keys():
		var tile: HexTileState = s.hexes[c]
		if tile.role == "interior":
			tile.haven_faction = a.faction
	var havens: int = 0
	for t2: HexTileState in s.hexes.values():
		if t2.haven_faction == a.faction:
			havens += 1
	_check(havens > GameActions.MAX_HAVENS, "test setup: %s holds %d Havens" % [a.faction, havens])

	s.chapter = s.max_chapters
	a.salt = 10
	a.plunder = 0
	a.food = 0
	b.salt = 0
	b.plunder = 0
	b.food = 0
	a.vp = 20
	b.vp = 0
	Scoring._buy_vp_with_resources(s)
	_check(a.salt == 0 and b.vp == 2, "last Chapter: 10 resources buy 2 VP for the player furthest behind (b VP %d)" % b.vp)


func _hex(state: GameState, coord: Vector2i, card_name: String) -> HexTileState:
	var t: HexTileState = state.ensure_hex(coord, "interior")
	t.hex_card_name = card_name
	t.explored = true
	return t


func _sorted(a: Array[String]) -> Array[String]:
	var out: Array[String] = a.duplicate()
	out.sort()
	return out


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures.append(label)
		print("FAIL: %s" % label)


func _report() -> void:
	print("\n---")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED:" % failures.size())
		for f: String in failures:
			print("  - " + f)
