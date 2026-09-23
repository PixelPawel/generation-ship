extends SceneTree

# Run via: godot --headless --path <project> --script tools/generate_card_hashes.gd
# Rebuilds data/card_hashes.json from the same print-export art CardDatabase
# already resolves onto each CardData (local_art_path / adv_local_art_path).
# Re-run whenever card art changes.

const CardHashScript := preload("res://scripts/photo_scan/card_hash.gd")

func _card_entries() -> Array[Dictionary]:
	# A --script SceneTree entry point is compiled before Godot wires up
	# autoloads, so "CardDatabase" can't be referenced as a static global
	# identifier here the way ordinary scene scripts can — fetch it
	# dynamically instead. Autoload _ready() (which populates these arrays)
	# also doesn't run until after _initialize() returns, so this must be
	# called from _process(), not _initialize().
	var card_db: Node = root.get_node("/root/CardDatabase")
	var entries: Array[Dictionary] = []
	for cd: CardData in (card_db.get("sectors") as Array[CardData]):
		if not cd.local_art_path.is_empty():
			entries.append({"key": cd.card_name, "path": cd.local_art_path})
		if not cd.adv_local_art_path.is_empty():
			entries.append({"key": cd.adv_name, "path": cd.adv_local_art_path})
	for cd: CardData in (card_db.get("techs") as Array[CardData]):
		if not cd.local_art_path.is_empty():
			entries.append({"key": cd.card_name, "path": cd.local_art_path})
	for cd: CardData in (card_db.get("expeditions") as Array[CardData]):
		if not cd.local_art_path.is_empty():
			entries.append({"key": cd.card_name, "path": cd.local_art_path})
	return entries

# Multiple physical copies of the same tech share one name/art (e.g. this
# deck prints "Hibernators" several times) and legitimately hash near-
# identically — only a same-name pair with genuinely different art (an
# actual data problem) should ever get flagged. Scaled proportionally
# (8/96 -> ~55/666) when CardHash grew from a 96-bit to a 666-bit hash.
const SUSPICIOUS_DISTANCE: int = 55

func _process(_delta: float) -> bool:
	var table: Dictionary = {}
	var missing: Array[String] = []
	var suspicious: Array[String] = []
	for entry: Dictionary in _card_entries():
		var key: String = entry["key"]
		var path: String = entry["path"]
		var img := Image.new()
		var err: int = img.load(path)
		if err != OK:
			missing.append("%s (%s)" % [key, path])
			continue
		var new_hash: String = CardHashScript.compute_hash(img)
		if table.has(key):
			var dist: int = CardHashScript.hamming_distance(table[key], new_hash)
			if dist > SUSPICIOUS_DISTANCE:
				suspicious.append("%s (hamming distance %d)" % [key, dist])
		table[key] = new_hash

	var file: FileAccess = FileAccess.open("res://data/card_hashes.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(table, "\t"))
	file.close()

	print("Wrote %d hashes to data/card_hashes.json" % table.size())
	if not missing.is_empty():
		print("Missing art for %d entries:" % missing.size())
		for m: String in missing:
			print(" - %s" % m)
	if not suspicious.is_empty():
		print("WARNING: %d same-name entries hash very differently (possible data problem):" % suspicious.size())
		for s: String in suspicious:
			print(" - %s" % s)
	quit()
	return true
