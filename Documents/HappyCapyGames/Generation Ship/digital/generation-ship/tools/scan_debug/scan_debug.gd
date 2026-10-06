extends Node
# Offline check of Scan Tableau on real photos (no UI): the same DialReader ->
# TableauReader chain as scenes/photo_scan, printed per sector. Run as a scene so
# the autoloads (CardDatabase) exist:
#   godot --headless --path . res://tools/scan_debug/scan_debug.tscn -- photo1.jpg photo2.jpg
# Photos are read as stored (no EXIF rotation), like the app does.

const DialReaderScript := preload("res://scripts/photo_scan/dial_reader.gd")
const TableauReaderScript := preload("res://scripts/photo_scan/tableau_reader.gd")
const COLOR_NAMES: Array[String] = ["Dust", "Metals", "Liquids", "Organix", "Electrix", "Thrust"]

func _ready() -> void:
	# CardDatabase loads its cards deferred in the game; wait until it has them
	while CardDatabase.sectors.is_empty():
		await get_tree().process_frame
	for path: String in OS.get_cmdline_user_args():
		_scan(path)
	get_tree().quit()

func _scan(path: String) -> void:
	var img: Image = Image.new()
	if img.load(path) != OK:
		print("cannot load ", path)
		return
	var t0: int = Time.get_ticks_msec()
	var reader: DialReader = DialReaderScript.create()
	reader.debug = OS.get_environment("SCAN_DEBUG") != ""
	# SCAN_PROBES="x,y;x,y": photo spots near dial markers to search exhaustively
	for pp: String in OS.get_environment("SCAN_PROBES").split(";", false):
		var xy: PackedStringArray = pp.split(",")
		reader.debug_probes.append(Vector2(float(xy[0]), float(xy[1])))
	var dials: Array[Dictionary] = reader.run(img)
	var tableau: TableauReader = TableauReaderScript.create(dials)
	tableau.debug = OS.get_environment("SCAN_DEBUG") != ""
	var groups: Array = tableau.analyze(reader.photo, dials, reader.markers)
	print("=== %s  (%d dials, %.1f s)" % [path.get_file(), dials.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	for d: Dictionary in dials:
		var c: Vector2 = d["center"]
		print("  dial %4d %-24s at (%4d, %4d) r %.1f gap %.2f dot %.2f" % [int(d.get("code", 0)), _card_name(d), int(c.x), int(c.y), float(d["radius"]), float(d.get("gap", 0.0)), float(d.get("dot", 0.0))])
	for g: Array in groups:
		var sd: Dictionary = g[0]
		var names: Array[String] = []
		for i: int in range(1, g.size()):
			names.append(_card_name(g[i]))
		if sd.is_empty():
			print("  (no sector): ", ", ".join(names))
			continue
		var ups: Array[String] = []
		for d: Dictionary in (sd.get("archived_up", []) as Array):
			ups.append(_card_name(d))
		var supply: Array[String] = []
		var sup: Dictionary = sd.get("supply", {})
		for c: Variant in sup:
			supply.append("%s x%d" % [CardData.color_name(int(c) as CardData.SupplyColor), int(sup[c])])
		print("  SECTOR %s | techs: %s | archived up: %s | down: %d | supply: %s" % [
			_card_name(sd), ", ".join(names), ", ".join(ups), int(sd.get("archived_down", 0)), ", ".join(supply)])

static func _card_name(d: Dictionary) -> String:
	var cd: CardData = d.get("card") as CardData
	if cd == null:
		return "?"
	return cd.adv_name if bool(d.get("is_advanced", false)) and cd.adv_name != "" else cd.card_name
