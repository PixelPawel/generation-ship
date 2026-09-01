extends SceneTree
## Headless smoke test: `godot --headless --script res://scripts/game/test_setup.gd`
## Builds a fresh 3-player game and sanity-checks the result.

func _initialize() -> void:
	await process_frame
	var card_db := root.get_node("/root/CardDatabase")

	var pairs := [
		["Druwhn", "Fhayanor"],
		["Duerkhar", "Yanny"],
		["Krowh", "Kha'al"],
	]
	var state := GameSetup.build_new_game(card_db, pairs, "Veteran", 3)

	var checks: Array = []

	checks.append(["player count", state.players.size() == 3])

	var p0: PlayerFactionState = state.players[0]
	checks.append(["player0 faction", p0.faction == "Druwhn"])
	checks.append(["player0 hero", p0.hero_name == "Fhayanor"])
	checks.append(["player0 salt", p0.salt == 5])
	checks.append(["player0 AP", p0.action_points == 8])
	checks.append(["player0 has 1 haven", p0.havens.size() == 1])
	checks.append(["player0 might > 0 or magic > 0", (p0.might + p0.magic + p0.leadership + p0.guile) > 0])

	var capital := state.get_hex(GameState.CAPITAL_COORD)
	checks.append(["capital exists", capital != null])
	checks.append(["capital garrison 3", capital != null and capital.garrison_level == 3])
	checks.append(["capital no_haven", capital != null and capital.no_haven])

	var home := state.get_hex(p0.hero_hex)
	checks.append(["home hex explored", home != null and home.explored])
	checks.append(["home hex haven", home != null and home.haven_faction == "Druwhn"])
	checks.append(["home hex name", home != null and home.card_name == "Yfelskog"])

	var capital_garrison_neighbors := 0
	for n in HexMath.neighbors(GameState.CAPITAL_COORD):
		var t := state.get_hex(n)
		if t != null and t.garrison_level == 1:
			capital_garrison_neighbors += 1
	checks.append(["3 garrisoned capital neighbors", capital_garrison_neighbors == 3])

	checks.append(["hex count reasonable", state.hexes.size() > 20])

	var curse_count := 0
	var skeleton_count := 0
	for k in state.hexes:
		var t: HexTile = state.hexes[k]
		if t.has_curse:
			curse_count += 1
		if t.skeleton_count > 0:
			skeleton_count += 1
	checks.append(["curse count == 2 (Veteran)", curse_count == 2])
	checks.append(["skeleton count == 2 (Veteran)", skeleton_count == 2])

	checks.append(["item deck non-empty", state.item_deck.size() > 0])
	checks.append(["market has 3", state.market.size() == 3])
	checks.append(["quest deck non-empty", state.quest_deck.size() > 0])
	checks.append(["quests_available has 3", state.quests_available.size() == 3])
	checks.append(["legion deck non-empty", state.legion_deck.size() > 0])
	checks.append(["horde deck non-empty", state.horde_deck.size() > 0])
	checks.append(["event chapter 1 non-empty", (state.event_deck_by_chapter.get(1, []) as Array).size() > 0])
	checks.append(["druids_in_play == 4", state.druids_in_play.size() == 4])
	checks.append(["druid_deck holds the remaining 5 (9 EN Core Druids total)", state.druid_deck.size() == 5])
	var druids_start_at_zero_aether := true
	var no_druid_overlap := true
	for d in state.druids_in_play:
		if d.aether != 0:
			druids_start_at_zero_aether = false
		if state.druid_deck.has(d.card_name):
			no_druid_overlap = false
	checks.append(["druids_in_play start with 0 AETHER", druids_start_at_zero_aether])
	checks.append(["no overlap between druids_in_play and druid_deck", no_druid_overlap])

	checks.append(["player0 feat_deck has 10 cards (1 Core faction's worth)", p0.feat_deck.size() == 10])
	var unique_feats := {}
	for f in p0.feat_deck:
		unique_feats[f] = true
	checks.append(["player0 feat_deck has no duplicates", unique_feats.size() == 10])
	checks.append(["player0 starts with no pending Feat choice", p0.pending_feat_choice.is_empty()])
	checks.append(["player0 starts with no Feats in play yet", p0.feats_in_play.is_empty()])

	# No duplicate card names should appear across market vs remaining item_deck.
	var item_overlap := false
	for m in state.market:
		if state.item_deck.has(m):
			item_overlap = true
	checks.append(["no market/deck overlap", not item_overlap])

	# Round-trip through JSON too, since this is what actually goes over the wire.
	var json_back: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var restored := GameState.from_dict(json_back)
	checks.append(["JSON round-trip hex count matches", restored.hexes.size() == state.hexes.size()])
	checks.append(["JSON round-trip player count matches", restored.players.size() == state.players.size()])

	var all_ok := true
	for c in checks:
		var label: String = c[0]
		var ok: bool = c[1]
		print(("OK   " if ok else "FAIL "), label)
		if not ok:
			all_ok = false

	print("\nTotal hexes generated: ", state.hexes.size())
	print("ALL CHECKS %s" % ("PASSED" if all_ok else "FAILED"))
	quit(0 if all_ok else 1)
