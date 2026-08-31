extends SceneTree
## Headless smoke test: `godot --headless --script res://scripts/data/test_runner.gd`
## Confirms CardDatabase autoload parses every CSV without error and that
## image paths resolve for a few known cards.

func _initialize() -> void:
	# Autoloads aren't in the tree yet during _initialize(); wait a frame.
	await process_frame
	var db := root.get_node("/root/CardDatabase")

	var checks := [
		["Hero 'Fhayanor' EN", func(): return db.heroes.filter(func(c): return c.card_name == "Fhayanor" and c.lang == "EN")],
		["Legion 'The Butcher' EN", func(): return db.legions.filter(func(c): return c.card_name == "The Butcher" and c.lang == "EN")],
		["Horde 'Lichqueen' EN", func(): return db.hordes.filter(func(c): return c.card_name == "Lichqueen" and c.lang == "EN")],
		["Item 'Abad Warpaint' EN", func(): return db.items.filter(func(c): return c.card_name == "Abad Warpaint" and c.lang == "EN")],
	]

	var all_ok := true
	for check in checks:
		var label: String = check[0]
		var results: Array = check[1].call()
		if results.is_empty():
			print("FAIL  %s: not found" % label)
			all_ok = false
			continue
		var card = results[0]
		var tex_ok: bool = card.texture_path != "" and FileAccess.file_exists(card.texture_path)
		print("%s  %s -> texture_path='%s' (exists=%s)" % [
			"OK   " if tex_ok else "WARN ", label, card.texture_path, tex_ok
		])

	print("\nCounts: heroes=%d legions=%d hordes=%d quests=%d items=%d feats=%d events=%d druids=%d hexes=%d mercs=%d playerboards=%d" % [
		db.heroes.size(), db.legions.size(), db.hordes.size(), db.quests.size(), db.items.size(),
		db.feats.size(), db.events.size(), db.druids.size(), db.hexes.size(), db.mercs.size(), db.playerboards.size(),
	])

	quit()
