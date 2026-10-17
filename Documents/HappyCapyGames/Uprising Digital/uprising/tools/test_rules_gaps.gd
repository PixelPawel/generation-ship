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

	# --- Save/load keeps typed Units ---
	var round_trip: GameState = GameState.from_dict(state.to_dict())
	_check(round_trip.get_hex(c1).unit_stack("Duerkhar") == t1.unit_stack("Duerkhar"), "typed Unit stacks survive to_dict/from_dict")
	var legacy := HexTileState.from_dict({"units": {"Krowh": 2}})
	_check(legacy.unit_stack("Krowh") == {"Tribesmen": 2}, "old count-only saves load as Basic Warriors")

	_report()


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
