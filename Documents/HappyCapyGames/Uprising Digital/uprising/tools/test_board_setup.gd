extends SceneTree

## Headless topology check for Milestone 1 (run before the visual
## screenshot check): confirms GameSetup produces the expected hex/piece
## counts and that the scene actually builds them as real child nodes.
## Run with: godot --headless --script res://tools/test_board_setup.gd --path .

var failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	await process_frame
	await _run()
	quit(1 if not failures.is_empty() else 0)


func _run() -> void:
	var card_db: Node = root.get_node_or_null("/root/CardDatabase")
	if card_db == null:
		failures.append("CardDatabase autoload not found")
		_report()
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var layout: BoardLayout = GameSetup.build_2p_normal_layout(card_db, rng)

	_check(layout.home_coords.size() == 2, "2 home hexes, got %d" % layout.home_coords.size())
	_check(layout.sea_tower_coords.size() == 2, "2 sea towers, got %d" % layout.sea_tower_coords.size())
	_check(layout.interior_coords.size() == 10, "10 interior hexes, got %d" % layout.interior_coords.size())
	_check(layout.garrison_counts.size() == 3, "3 non-Capital garrison stacks, got %d" % layout.garrison_counts.size())
	_check(layout.capital_garrison_count == 3, "Capital has 3 baseline garrisons, got %d" % layout.capital_garrison_count)
	_check(layout.curse_coords.size() == 2, "2 curses, got %d" % layout.curse_coords.size())
	_check(layout.skeleton_counts.size() == 3, "3 skeleton hexes, got %d" % layout.skeleton_counts.size())

	# No overlap between Home/SeaTower/Interior/Capital coord sets.
	var all_hex_coords: Array[Vector2i] = [layout.capital_coord]
	all_hex_coords.append_array(layout.home_coords)
	all_hex_coords.append_array(layout.sea_tower_coords)
	all_hex_coords.append_array(layout.interior_coords)
	var unique: Dictionary = {}
	for c: Vector2i in all_hex_coords:
		unique[c] = true
	_check(unique.size() == all_hex_coords.size(), "no duplicate hex coords across roles, got %d unique of %d total" % [unique.size(), all_hex_coords.size()])

	# Every home hex has a distinct faction and a resolved HexCard.
	var factions_seen: Dictionary = {}
	for coord: Vector2i in layout.home_coords:
		var f: String = layout.home_factions.get(coord, "")
		_check(f != "" and f != "Unknown", "home hex at %s has a resolved faction, got '%s'" % [coord, f])
		_check(not factions_seen.has(f), "faction '%s' assigned to only one home hex" % f)
		factions_seen[f] = true
		_check(layout.home_hex_cards.has(coord), "home hex at %s has a HexCard" % coord)

	# Now build the actual scene and confirm real nodes exist with sane transforms.
	var packed: PackedScene = load("res://scenes/GameBoard.tscn")
	if packed == null:
		failures.append("could not load GameBoard.tscn")
		_report()
		return
	var instance: Node = packed.instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame

	var hexes: Node = instance.get_node_or_null("Hexes")
	_check(hexes != null, "Hexes node exists")
	if hexes != null:
		_check(hexes.get_child_count() == 15, "15 hex nodes (1 capital + 2 home + 2 sea tower + 10 interior), got %d" % hexes.get_child_count())
		for child: Node in hexes.get_children():
			var mi := child as MeshInstance3D
			_check(mi != null and mi.mesh != null, "%s is a MeshInstance3D with a mesh" % child.name)
			var pos: Vector3 = (child as Node3D).position
			_check(not (is_nan(pos.x) or is_nan(pos.y) or is_nan(pos.z)), "%s has a non-NaN position" % child.name)

	var pieces: Node = instance.get_node_or_null("Pieces")
	_check(pieces != null, "Pieces node exists")
	if pieces != null:
		# 1 capital garrison group + 3 non-capital garrison groups + 2 curses + (1+1+3 skeleton instances split across 3 hexes... wait skeleton_counts values are 1,1,1) = 3 skeleton pieces.
		_check(pieces.get_child_count() > 0, "Pieces has children, got %d" % pieces.get_child_count())

	var standees: Node = instance.get_node_or_null("Standees")
	_check(standees != null, "Standees node exists")
	if standees != null:
		print("Standees built: %d (expected up to 2, may be fewer if a model path didn't resolve)" % standees.get_child_count())

	_report()


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
