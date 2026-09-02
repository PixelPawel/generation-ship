extends SceneTree

## Headless verification for Milestone 0: run with
##   godot --headless --script res://tools/test_data_load.gd --path .
## Loads CardDatabase/ImageManifest/ModelManifest via their autoloads and
## sanity-checks row counts + a few known embedded-newline / positional-
## column parsing cases, then prints PASS/FAIL and quits.

var failures: Array[String] = []


func _initialize() -> void:
	# Autoloads aren't in the tree yet inside _initialize() - wait a frame.
	await process_frame
	await process_frame
	_run()
	quit(1 if not failures.is_empty() else 0)


func _run() -> void:
	var cdb: Node = root.get_node_or_null("/root/CardDatabase")
	var img: Node = root.get_node_or_null("/root/ImageManifest")
	var mdl: Node = root.get_node_or_null("/root/ModelManifest")

	if cdb == null or img == null or mdl == null:
		failures.append("One or more autoloads not found (CardDatabase=%s ImageManifest=%s ModelManifest=%s)" % [cdb, img, mdl])
		_report()
		return

	_check_gt("heroes_all count", cdb.heroes_all.size(), 0)
	_check_gt("legions_all count", cdb.legions_all.size(), 0)
	_check_gt("hordes_all count", cdb.hordes_all.size(), 0)
	_check_gt("items_all count", cdb.items_all.size(), 0)
	_check_gt("feats_all count", cdb.feats_all.size(), 0)
	_check_gt("events_all count", cdb.events_all.size(), 0)
	_check_gt("druids_all count", cdb.druids_all.size(), 0)
	_check_gt("hexes_all count", cdb.hexes_all.size(), 0)
	_check_gt("mercs_all count", cdb.mercs_all.size(), 0)
	_check_gt("playerboards_all count", cdb.playerboards_all.size(), 0)
	_check_gt("quests_all count", cdb.quests_all.size(), 0)

	print("Core EN filtered counts: heroes=%d legions=%d hordes=%d items=%d feats=%d events=%d druids=%d hexes=%d playerboards=%d quests=%d" % [
		cdb.heroes.size(), cdb.legions.size(), cdb.hordes.size(), cdb.items.size(),
		cdb.feats.size(), cdb.events.size(), cdb.druids.size(), cdb.hexes.size(),
		cdb.playerboards.size(), cdb.quests.size(),
	])

	# Known-good spot checks.
	_check_true("8 Core Legions", cdb.legions.size() == 8, "got %d" % cdb.legions.size())
	_check_true("8 Core Hordes", cdb.hordes.size() == 8, "got %d" % cdb.hordes.size())
	_check_true("4 Core factions (8 heroes)", cdb.heroes.size() == 8, "got %d" % cdb.heroes.size())
	_check_true("9 Core Druids", cdb.druids.size() == 9, "got %d" % cdb.druids.size())

	var legion_names: Array = cdb.legions.map(func(l: LegionCard) -> String: return l.card_name)
	for expected: String in ["The Courtesan", "The Warlock", "The Spymaster", "The Assassin", "The Imperial Guard", "The Mage Breaker", "The Executioner", "The New Emperor"]:
		_check_true("Legion roster has '%s'" % expected, legion_names.has(expected), "roster=%s" % [legion_names])

	var horde_names: Array = cdb.hordes.map(func(h: HordeCard) -> String: return h.card_name)
	for expected: String in ["Lichqueen", "Coven of Yssat", "Counter of Omens", "Bloodwyrm", "Siren", "Banished", "False Messiah", "Oda the Fallen"]:
		_check_true("Horde roster has '%s'" % expected, horde_names.has(expected), "roster=%s" % [horde_names])

	# Embedded-newline field parsing: find "Yfelskog" (a known Core Home hex
	# with a long multi-sentence Flavor field) and confirm the row wasn't
	# split/truncated by an unescaped newline.
	var yfelskog: HexCard = null
	for h: HexCard in cdb.hexes_all:
		if h.card_name == "Yfelskog" and h.lang == "EN":
			yfelskog = h
			break
	_check_true("Yfelskog hex found (embedded-newline parse survived)", yfelskog != null, "not found")
	if yfelskog != null:
		_check_true("Yfelskog is Core/Home/Woods", yfelskog.box == "Core" and yfelskog.hex_type == "Home" and yfelskog.terrain == "Woods",
			"box=%s type=%s terrain=%s" % [yfelskog.box, yfelskog.hex_type, yfelskog.terrain])

	# Quest CSV's mis-named first column ("a" instead of "Lang") read positionally.
	_check_gt("quests filtered to EN/Core", cdb.quests.size(), 0)
	if not cdb.quests.is_empty():
		var q0: QuestCard = cdb.quests[0]
		_check_true("first Core quest has non-empty lang from column 'a'", q0.lang == "EN", "lang='%s'" % q0.lang)

	# HexMath geometry sanity (flat-top, R=2.0).
	var origin_world: Vector3 = HexMath.to_world(Vector2i(0, 0))
	_check_true("HexMath origin at world origin", origin_world.is_equal_approx(Vector3.ZERO), "%s" % origin_world)
	# Center-to-center distance between ANY two adjacent hexes (any axial
	# neighbor direction) is R*sqrt(3) for a flat-top grid - not 1.5*R, which
	# is only the pure-horizontal component of the (1,0) step.
	var neighbor_world: Vector3 = HexMath.to_world(Vector2i(1, 0))
	var expected_dist: float = HexMath.TILE_HEX_SIZE * sqrt(3.0)
	_check_true("HexMath neighbor(1,0) distance ~= R*sqrt(3)", is_equal_approx(origin_world.distance_to(neighbor_world), expected_dist),
		"dist=%f expected=%f" % [origin_world.distance_to(neighbor_world), expected_dist])
	_check_true("HexMath.from_world round-trips", HexMath.from_world(neighbor_world) == Vector2i(1, 0),
		"got %s" % HexMath.from_world(neighbor_world))
	_check_true("HexMath.distance((0,0),(1,0)) == 1", HexMath.distance(Vector2i.ZERO, Vector2i(1, 0)) == 1, "")
	_check_true("HexMath.ring radius0 == [center]", HexMath.ring(Vector2i.ZERO, 0) == [Vector2i.ZERO], "")
	_check_true("HexMath.ring radius1 has 6 hexes", HexMath.ring(Vector2i.ZERO, 1).size() == 6, "got %d" % HexMath.ring(Vector2i.ZERO, 1).size())
	_check_true("HexMath.spiral radius2 has 19 hexes (1+6+12)", HexMath.spiral(Vector2i.ZERO, 2).size() == 19, "got %d" % HexMath.spiral(Vector2i.ZERO, 2).size())

	# Manifests loaded.
	_check_gt("image manifest rows", img.rows.size(), 0)
	_check_true("6 known-missing Arch Nemesis Event images flagged", img.missing_downloads().size() == 6, "got %d" % img.missing_downloads().size())
	_check_gt("model manifest folders", mdl.folder_to_obj.size(), 0)
	_check_true("Mohyar folder alias resolves to Moyhar", mdl.resolve_faction_folder("Mohyar") == "Moyhar", "")

	var asset_problems: Array[String] = cdb.self_check_assets()
	if not asset_problems.is_empty():
		print("Asset self-check found %d issue(s) (not necessarily failures - see list):" % asset_problems.size())
		for p: String in asset_problems:
			print("  - " + p)

	_report()


func _check_true(label: String, condition: bool, detail: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures.append("%s (%s)" % [label, detail])
		print("FAIL: %s (%s)" % [label, detail])


func _check_gt(label: String, value: int, minimum: int) -> void:
	_check_true(label, value > minimum, "value=%d" % value)


func _report() -> void:
	print("\n---")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED:" % failures.size())
		for f: String in failures:
			print("  - " + f)
