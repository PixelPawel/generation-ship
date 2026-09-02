extends SceneTree

## Milestone 3 verification: exercises the EffectOp/EffectInterpreter engine
## against real transcribed Core Hex effects (HexEffectPrograms), asserting
## actual resource/token/VP deltas - not just "it runs without erroring".
## Run with: godot --headless --script res://tools/test_effects.gd --path .

var failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	await process_frame
	_run()
	quit(1 if not failures.is_empty() else 0)


func _run() -> void:
	var card_db: Node = root.get_node("/root/CardDatabase")

	# --- Structural sanity: every declared builder produces a real program ---
	var expected_cards: Array[String] = [
		"Bruthgaard", "Golgardei", "Plains of Rhun", "Frosthold Pass", "Imperial Slave Mines",
		"Tomb of the Elder Kings", "Black Ice", "Grim Fangs", "Raufrost", "Shadowdawn",
		"Taurel Caravan Passage", "Torment", "Fyrnhalla", "Kyushis Tavern", "Rigga",
		"Dunkelholm", "Fjoelja Stone Circle", "Trollward",
	]
	_check(expected_cards.size() == 18, "18 hex effects transcribed, got %d in the expectation list" % expected_cards.size())
	for name: String in expected_cards:
		_check(HexEffectPrograms.has_program(name), "HexEffectPrograms has a builder for '%s'" % name)
		var prog: EffectProgram = HexEffectPrograms.get_program(name)
		_check(prog != null and prog.ops.size() > 0, "'%s' program has ops" % name)
		_check(prog.source_card == name, "'%s' program source_card matches" % name)
	_check(not HexEffectPrograms.has_program("Capital"), "Capital intentionally excluded (Nemesis-triggered, not Explore)")
	_check(not HexEffectPrograms.has_program("Netherwood"), "Netherwood intentionally excluded (needs multi-threshold dice op)")

	# --- Bruthgaard: Gain 2 Food, place-or-reinforce 2 Skeletons (empty), then +2 more (clamped to cap 2) ---
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var state: GameState = GameSetup.build_2p_normal_game_state(card_db, rng)
	var faction: String = state.players[0].faction
	var test_coord := Vector2i(5, 5)  # an arbitrary hex outside the real board, guaranteed empty/unused
	var starting_food: int = state.find_player(faction).food

	_run_program(state, card_db, "Bruthgaard", faction, test_coord)
	var p: PlayerFactionState = state.find_player(faction)
	_check(p.food == starting_food + 2, "Bruthgaard: food +2, got %d expected %d" % [p.food, starting_food + 2])
	var tile: HexTileState = state.get_hex(test_coord)
	_check(tile.skeleton_count == 2, "Bruthgaard: skeleton_count clamped to cap 2, got %d" % tile.skeleton_count)

	# --- Reinforce branch: run Bruthgaard AGAIN on the same now-occupied hex - should reinforce by 1, not reset to 2 (already at cap so stays 2, but exercises the non-empty branch) ---
	var salt_before: int = p.salt
	_run_program(state, card_db, "Grim Fangs", faction, test_coord)  # different card, same occupied hex - exercises "not empty -> reinforce by 1" branch
	tile = state.get_hex(test_coord)
	_check(tile.skeleton_count == 2, "Grim Fangs on occupied hex: reinforce-by-1 clamps at cap 2, got %d" % tile.skeleton_count)
	_check(p.salt == salt_before + 2, "Grim Fangs: salt +2, got %d expected %d" % [p.salt, salt_before + 2])

	# --- Tomb of the Elder Kings: removes garrison, places 2 skeletons, draws+keeps an Item ---
	var test_coord2 := Vector2i(6, 6)
	var tile2: HexTileState = state.ensure_hex(test_coord2)
	tile2.garrison_level = 3
	var items_before: int = p.items_in_hand.size()
	var deck_before: int = state.item_deck.size()
	var plunder_before: int = p.plunder
	_run_program(state, card_db, "Tomb of the Elder Kings", faction, test_coord2)
	tile2 = state.get_hex(test_coord2)
	_check(tile2.garrison_level == 0, "Tomb of the Elder Kings: garrison removed, got %d" % tile2.garrison_level)
	_check(tile2.skeleton_count == 2, "Tomb of the Elder Kings: 2 skeletons placed, got %d" % tile2.skeleton_count)
	_check(p.items_in_hand.size() == items_before + 1, "Tomb of the Elder Kings: 1 item drawn to hand")
	_check(state.item_deck.size() == deck_before - 1, "Tomb of the Elder Kings: item_deck shrank by 1")
	_check(p.plunder == plunder_before + 1, "Tomb of the Elder Kings: plunder +1")

	# --- Black Ice: places activation token on whichever Legion/Horde has fewest tokens ---
	state.legions.clear()
	state.hordes.clear()
	var l1 := LegionInstance.new()
	l1.id = 0
	l1.card_name = "The Courtesan"
	l1.activation_tokens = 2
	var l2 := LegionInstance.new()
	l2.id = 1
	l2.card_name = "The Warlock"
	l2.activation_tokens = 0  # fewest - should receive the token
	state.legions.append(l1)
	state.legions.append(l2)
	var test_coord3 := Vector2i(7, 7)
	_run_program(state, card_db, "Black Ice", faction, test_coord3)
	_check(l2.activation_tokens == 1, "Black Ice: fewest-tokens Legion received the token, got %d" % l2.activation_tokens)
	_check(l1.activation_tokens == 2, "Black Ice: other Legion untouched, got %d" % l1.activation_tokens)

	# --- Imperial Slave Mines: deterministic dice roll (all Skull) drives the per-symbol reward + each-other-player bonus ---
	var second_faction: String = state.players[1].faction
	var p2: PlayerFactionState = state.find_player(second_faction)
	var test_coord4 := Vector2i(8, 8)
	var tile4: HexTileState = state.ensure_hex(test_coord4)
	tile4.skeleton_count = 2
	var plunder_before_1: int = p.plunder
	var plunder_before_2: int = p2.plunder
	_run_program(state, card_db, "Imperial Slave Mines", faction, test_coord4, func() -> String: return "Skull")
	tile4 = state.get_hex(test_coord4)
	p = state.find_player(faction)
	p2 = state.find_player(second_faction)
	_check(tile4.skeleton_count == 0, "Imperial Slave Mines: skeletons removed")
	_check(tile4.garrison_level == 2, "Imperial Slave Mines: 2 Garrisons placed, got %d" % tile4.garrison_level)
	_check(p.plunder == plunder_before_1 + 2, "Imperial Slave Mines: roller gains 2 (dice, all-Skull; each-other-player bonus is for OTHERS, not self) - got %d expected %d" % [p.plunder, plunder_before_1 + 2])
	_check(p2.plunder == plunder_before_2 + 1, "Imperial Slave Mines: other player gains 1 Plunder, got %d expected %d" % [p2.plunder, plunder_before_2 + 1])

	# --- PlaceOrReinforceOp respects the rulebook's "empty = no Legion/Horde either" rule ---
	var test_coord5 := Vector2i(9, 9)
	var l3 := LegionInstance.new()
	l3.id = 2
	l3.coord = test_coord5
	state.legions.append(l3)
	_check(not EffectUtil.hex_is_empty_of_units(state, test_coord5), "EffectUtil: hex with a Legion on it is not 'empty'")

	_report()


func _run_program(state: GameState, card_db: Node, card_name: String, faction: String, coord: Vector2i, dice_roller: Callable = Callable()) -> void:
	var ctx := EffectContext.new()
	ctx.state = state
	ctx.card_db = card_db
	ctx.rng = RandomNumberGenerator.new()
	ctx.acting_faction = faction
	ctx.hex_coord = coord
	ctx.has_hex_coord = true
	if dice_roller.is_valid():
		ctx.dice_roller = dice_roller
	var program: EffectProgram = HexEffectPrograms.get_program(card_name)
	EffectInterpreter.run(program, ctx)


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
