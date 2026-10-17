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
	state.horde_deck = ["Counter of Omens", "Oda the Fallen"]
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
	ChapterFlow._refresh_phase(rs)
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
