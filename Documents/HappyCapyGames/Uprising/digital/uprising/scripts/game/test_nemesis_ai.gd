extends SceneTree
## Headless smoke test: `godot --headless --script res://scripts/game/test_nemesis_ai.gd`
## Exercises NemesisAI directly against hand-built GameStates -- precise hex
## geometry, not GameSetup output, so the movement-priority logic is tested
## deterministically rather than against whatever a random board happens to
## contain.

var checks: Array = []


func _check(label: String, ok: bool) -> void:
	checks.append([label, ok])


func _blank_state() -> GameState:
	var state := GameState.new()
	var capital := HexTile.new()
	capital.coord = GameState.CAPITAL_COORD
	capital.card_name = "The Capital"
	capital.explored = true
	capital.no_haven = true
	state.set_hex(capital)
	return state


func _tile(coord: Vector2i) -> HexTile:
	var t := HexTile.new()
	t.coord = coord
	t.explored = true
	return t


func _initialize() -> void:
	await process_frame

	# --- Movement priority: Haven beats an enemy-occupied candidate ---
	# From (0,0) toward (2,-1), the two equally-closer neighbors are
	# (1,0) and (1,-1) (verified by hand: hex distance math, not guessed).
	var state_a := _blank_state()
	var enemy_tile := _tile(Vector2i(1, 0))
	enemy_tile.units["Krowh"] = ["Tribesmen"]
	state_a.set_hex(enemy_tile)
	var haven_tile := _tile(Vector2i(1, -1))
	haven_tile.haven_faction = "Druwhn"
	state_a.set_hex(haven_tile)
	var choice_a := NemesisAI._choose_legion_move(state_a, Vector2i.ZERO, Vector2i(2, -1))
	_check("Legion prefers a Haven over an enemy-occupied hex", choice_a == Vector2i(1, -1))

	# --- Movement priority: enemy beats an empty candidate ---
	var state_b := _blank_state()
	state_b.set_hex(_tile(Vector2i(1, 0)))  # empty
	var enemy_tile_b := _tile(Vector2i(1, -1))
	enemy_tile_b.skeleton_count = 1
	state_b.set_hex(enemy_tile_b)
	var choice_b := NemesisAI._choose_legion_move(state_b, Vector2i.ZERO, Vector2i(2, -1))
	_check("Legion prefers an enemy-occupied hex over an empty one", choice_b == Vector2i(1, -1))

	# --- Full Legion activation: Garrison placement + movement + token spend ---
	var state := _blank_state()
	state.set_hex(_tile(Vector2i(1, 0)))
	state.set_hex(_tile(Vector2i(2, 0)))
	var legion := LegionInstance.new()
	legion.id = state.next_nemesis_id()
	legion.card_name = "The Butcher"
	legion.threat = 5
	legion.coord = Vector2i(1, 0)
	legion.target_hex = Vector2i(2, 0)
	legion.activation_tokens = 2
	state.legions.append(legion)

	var r := NemesisAI.activate_legion(state, legion.id)
	_check("legion activation ok", r.get("ok", false))
	_check("legion left a Garrison on its old hex", state.get_hex(Vector2i(1, 0)).garrison_level == 1)
	_check("legion moved one hex closer to target", legion.coord == Vector2i(2, 0))
	_check("legion consumed one Activation Token", legion.activation_tokens == 1)
	_check("legion at target now (no further move pending)", legion.coord == legion.target_hex)

	# --- Legion with no Activation Tokens is rejected ---
	legion.activation_tokens = 0
	r = NemesisAI.activate_legion(state, legion.id)
	_check("legion with 0 tokens rejected", not r.get("ok", true))

	# --- Garrison cap: a 4th Garrison on a hex gives Empire VP instead ---
	var capped_tile := _tile(Vector2i(3, 0))
	capped_tile.garrison_level = 3
	state.set_hex(capped_tile)
	var legion2 := LegionInstance.new()
	legion2.id = state.next_nemesis_id()
	legion2.coord = Vector2i(3, 0)
	legion2.target_hex = Vector2i(3, 0)  # already there -- only tests the Garrison step
	legion2.activation_tokens = 1
	state.legions.append(legion2)
	var vp_before := state.empire_vp
	NemesisAI.activate_legion(state, legion2.id)
	_check("Garrison-capped hex gives Empire VP instead of a 4th Garrison", state.empire_vp == vp_before + 1)
	_check("capped hex garrison level unchanged", state.get_hex(Vector2i(3, 0)).garrison_level == 3)

	# --- Legion moving into a player-occupied hex flags pending combat ---
	var state_c := _blank_state()
	state_c.set_hex(_tile(Vector2i(1, 0)))
	var occupied := _tile(Vector2i(2, 0))
	occupied.units["Duerkhar"] = ["Spearsingers"]
	state_c.set_hex(occupied)
	var legion3 := LegionInstance.new()
	legion3.id = state_c.next_nemesis_id()
	legion3.coord = Vector2i(1, 0)
	legion3.target_hex = Vector2i(2, 0)
	legion3.activation_tokens = 1
	state_c.legions.append(legion3)
	NemesisAI.activate_legion(state_c, legion3.id)
	_check("moving into enemy Units queues a pending combat", state_c.pending_combats == [Vector2i(2, 0)])

	# --- Full Horde activation: Curse placement + movement toward not-farther-from-Capital ---
	var state_h := _blank_state()
	state_h.set_hex(_tile(Vector2i(1, 0)))
	state_h.set_hex(_tile(Vector2i(2, 0)))
	var horde := HordeInstance.new()
	horde.id = state_h.next_nemesis_id()
	horde.card_name = "Lichqueen"
	horde.threat = 4
	horde.coord = Vector2i(2, 0)  # farther from Capital than (1,0)
	horde.activation_tokens = 1
	state_h.hordes.append(horde)
	r = NemesisAI.activate_horde(state_h, horde.id)
	_check("horde activation ok", r.get("ok", false))
	_check("horde left a Curse on its old hex", state_h.get_hex(Vector2i(2, 0)).has_curse)
	_check("horde moved toward the Capital", horde.coord == Vector2i(1, 0))
	_check("horde consumed one Activation Token", horde.activation_tokens == 0)

	# --- Horde re-activating a hex it already cursed gives Chaos VP instead ---
	var state_h2 := _blank_state()
	var precursed := _tile(Vector2i(1, 0))
	precursed.has_curse = true
	state_h2.set_hex(precursed)
	var horde2 := HordeInstance.new()
	horde2.id = state_h2.next_nemesis_id()
	horde2.coord = Vector2i(1, 0)
	horde2.activation_tokens = 1
	state_h2.hordes.append(horde2)
	var chaos_vp_before := state_h2.chaos_vp
	NemesisAI.activate_horde(state_h2, horde2.id)
	_check("re-cursing gives Chaos VP instead", state_h2.chaos_vp == chaos_vp_before + 1)

	# --- Round-trip pending_combats through to_dict/from_dict ---
	var restored := GameState.from_dict(state_c.to_dict())
	_check("pending_combats survives serialization", restored.pending_combats == [Vector2i(2, 0)])
	var restored_none := GameState.from_dict(state.to_dict())
	_check("no-combat state round-trips to an empty queue", restored_none.pending_combats.is_empty())

	# --- Multiple activations in one pass queue up multiple combats, not overwrite ---
	var state_multi := _blank_state()
	state_multi.set_hex(_tile(Vector2i(1, 0)))
	var occupied_a := _tile(Vector2i(2, 0))
	occupied_a.units["Duerkhar"] = ["Spearsingers"]
	state_multi.set_hex(occupied_a)
	state_multi.set_hex(_tile(Vector2i(-1, 0)))
	var occupied_b := _tile(Vector2i(-2, 0))
	occupied_b.units["Krowh"] = ["Tribesmen"]
	state_multi.set_hex(occupied_b)

	var legion_multi := LegionInstance.new()
	legion_multi.id = state_multi.next_nemesis_id()
	legion_multi.coord = Vector2i(1, 0)
	legion_multi.target_hex = Vector2i(2, 0)
	legion_multi.activation_tokens = 1
	state_multi.legions.append(legion_multi)

	var legion_multi_b := LegionInstance.new()
	legion_multi_b.id = state_multi.next_nemesis_id()
	legion_multi_b.coord = Vector2i(-1, 0)
	legion_multi_b.target_hex = Vector2i(-2, 0)
	legion_multi_b.activation_tokens = 1
	state_multi.legions.append(legion_multi_b)

	NemesisAI.activate_legion(state_multi, legion_multi.id)
	NemesisAI.activate_legion(state_multi, legion_multi_b.id)
	_check("two activations in one pass queue both combats, not just the last",
		state_multi.pending_combats.size() == 2
		and state_multi.pending_combats.has(Vector2i(2, 0))
		and state_multi.pending_combats.has(Vector2i(-2, 0)))

	var all_ok := true
	for c in checks:
		var label: String = c[0]
		var ok: bool = c[1]
		print(("OK   " if ok else "FAIL "), label)
		if not ok:
			all_ok = false

	print("\nALL CHECKS %s" % ("PASSED" if all_ok else "FAILED"))
	quit(0 if all_ok else 1)
