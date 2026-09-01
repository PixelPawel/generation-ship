extends SceneTree
## Headless smoke test: `godot --headless --script res://scripts/game/test_scoring.gd`
## Verifies Scoring against a hand-built GameState so every number is known
## up front, plus one check against real CardDatabase hex text (Yfelskog,
## Druwhn's Core-box home hex, whose "Special" column is "1 VP").

var checks: Array = []


func _check(label: String, ok: bool) -> void:
	checks.append([label, ok])


func _initialize() -> void:
	await process_frame
	var card_db := root.get_node("/root/CardDatabase")

	var state := GameState.new()

	# 2 Garrisoned hexes (Empire: +2), 1 Legion (+1) = 3 Empire VP.
	var g1 := HexTile.new()
	g1.coord = Vector2i(1, 0)
	g1.garrison_level = 2
	state.set_hex(g1)
	var g2 := HexTile.new()
	g2.coord = Vector2i(2, 0)
	g2.garrison_level = 1
	state.set_hex(g2)
	var legion := LegionInstance.new()
	legion.id = state.next_nemesis_id()
	state.legions.append(legion)
	state.imperial_graveyard["Druwhn"] = 2
	state.imperial_graveyard["Krowh"] = 1  # two factions represented -> +4

	# 1 Cursed hex (Chaos: +1), 2 Hordes (+2) = 3 Chaos VP, no graveyard factions.
	var c1 := HexTile.new()
	c1.coord = Vector2i(3, 0)
	c1.has_curse = true
	state.set_hex(c1)
	var horde1 := HordeInstance.new()
	horde1.id = state.next_nemesis_id()
	var horde2 := HordeInstance.new()
	horde2.id = state.next_nemesis_id()
	state.hordes.append(horde1)
	state.hordes.append(horde2)

	# Druwhn: 1 Haven on the real "Yfelskog" hex (Special == "1 VP" in the CSV)
	# -> 2 (Haven) + 1 (hex bonus) = 3 VP.
	var home := HexTile.new()
	home.coord = Vector2i(4, 0)
	home.card_name = "Yfelskog"
	state.set_hex(home)
	var druwhn := PlayerFactionState.new()
	druwhn.faction = "Druwhn"
	druwhn.havens = [Vector2i(4, 0)]
	druwhn.victory_points = 10
	state.players.append(druwhn)

	# Krowh: 2 plain Havens (no VP-bonus hexes) -> 2*2 = 4 VP.
	var k1 := HexTile.new()
	k1.coord = Vector2i(5, 0)
	state.set_hex(k1)
	var k2 := HexTile.new()
	k2.coord = Vector2i(6, 0)
	state.set_hex(k2)
	var krowh := PlayerFactionState.new()
	krowh.faction = "Krowh"
	krowh.havens = [Vector2i(5, 0), Vector2i(6, 0)]
	krowh.victory_points = 0
	state.players.append(krowh)

	var empire_vp_before := state.empire_vp
	var chaos_vp_before := state.chaos_vp
	var deltas := Scoring.score_chapter(state, card_db)

	_check("empire delta == 3 (2 garrisoned hexes + 1 legion) + 4 (2 graveyard factions)",
		deltas["empire"] == 7)
	_check("empire_vp increased by the delta", state.empire_vp == empire_vp_before + 7)
	_check("chaos delta == 3 (1 curse + 2 hordes)", deltas["chaos"] == 3)
	_check("chaos_vp increased by the delta", state.chaos_vp == chaos_vp_before + 3)

	_check("Druwhn delta == 3 (Haven + real 1-VP hex bonus)", int(deltas["players"]["Druwhn"]) == 3)
	_check("Druwhn total VP updated", druwhn.victory_points == 13)
	_check("Krowh delta == 4 (2 plain Havens)", int(deltas["players"]["Krowh"]) == 4)
	_check("Krowh total VP updated", krowh.victory_points == 4)

	_check("imperial graveyard cleared after scoring", state.imperial_graveyard.is_empty())
	_check("chaos graveyard cleared after scoring", state.chaos_graveyard.is_empty())

	# --- Scoring again immediately (empty graveyards, same board) should be stable ---
	var deltas2 := Scoring.score_chapter(state, card_db)
	_check("re-scoring with cleared graveyards drops the +4 Empire graveyard bonus",
		deltas2["empire"] == 3)

	var all_ok := true
	for c in checks:
		var label: String = c[0]
		var ok: bool = c[1]
		print(("OK   " if ok else "FAIL "), label)
		if not ok:
			all_ok = false

	print("\nALL CHECKS %s" % ("PASSED" if all_ok else "FAILED"))
	quit(0 if all_ok else 1)
