extends Node
# Offline check of Scan Tableau on real photos (no UI): the same DialReader ->
# TableauReader chain as scenes/photo_scan, printed per sector. Run as a scene so
# the autoloads (CardDatabase) exist:
#   godot --headless --path . res://tools/scan_debug/scan_debug.tscn -- photo1.jpg photo2.jpg
# Photos are read as stored (no EXIF rotation), like the app does.

const DialReaderScript := preload("res://scripts/photo_scan/dial_reader.gd")
const TableauReaderScript := preload("res://scripts/photo_scan/tableau_reader.gd")

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
	reader.debug_strips = OS.get_environment("SCAN_STRIPS") != ""
	# SCAN_NO_VIOLET=1: read photos of the violet cards by their lights only (the lights pass), light 0
	# (their diamond) not required to be lit
	if OS.get_environment("SCAN_NO_VIOLET") != "":
		reader.ignore_violet = true
		reader.light0_lit = false
		reader.lights_pass = true
	# SCAN_LIGHTS_ONLY=1: photos of the diamond-less test cards (light 0 lit): the lights pass only
	if OS.get_environment("SCAN_LIGHTS_ONLY") != "":
		reader.ignore_violet = true
		reader.lights_pass = true
	# SCAN_SPOTS=<folder>: the lights pass's spots and rings per photo as <photo>.spots.json there
	if OS.get_environment("SCAN_SPOTS") != "":
		reader.debug_spots_path = OS.get_environment("SCAN_SPOTS").path_join(path.get_file().get_basename() + ".spots.json")
	# SCAN_PROBES="x,y;x,y": photo spots near dial markers to search exhaustively
	for pp: String in OS.get_environment("SCAN_PROBES").split(";", false):
		var xy: PackedStringArray = pp.split(",")
		reader.debug_probes.append(Vector2(float(xy[0]), float(xy[1])))
	var dials: Array[Dictionary] = reader.run(img)
	# SCAN_ALTS=1: the camera's other burst shots next to the photo (<photo>_alt1.jpg, _alt2.jpg)
	# get the app's second look
	if OS.get_environment("SCAN_ALTS") != "":
		for k: int in range(1, 3):   # as the app: the third shot only if the second added something
			var alt_path: String = "%s_alt%d.jpg" % [path.get_basename(), k]
			var alt: Image = Image.new()
			if FileAccess.file_exists(alt_path) and alt.load(alt_path) == OK and not dials.is_empty():
				var more: Array[Dictionary] = reader.second_look(alt, dials)
				print("  second look %s: +%d" % [alt_path.get_file(), more.size()])
				dials.append_array(more)
				if more.is_empty():
					break
	var t1: int = Time.get_ticks_msec()
	var tableau: TableauReader = TableauReaderScript.create(dials)
	tableau.debug = OS.get_environment("SCAN_DEBUG") != ""
	# SCAN_TOKENS=<folder>: each sector's token zone and pixel classes as <photo>_sector<i>_<code>.png there
	if OS.get_environment("SCAN_TOKENS") != "":
		tableau.debug_dump = OS.get_environment("SCAN_TOKENS").path_join(path.get_file().get_basename())
	# as in the app: a column whose sector dial is unread gets a placeholder sector (printed "[placeholder]")
	tableau.placeholder_card = CardDatabase.find_by_scan_code(450).get("card") as CardData
	var groups: Array = tableau.analyze(reader.photo, dials, reader.markers)
	print("=== %s  (%d dials, %.1f s)  cards %.1f s, tokens/archive %.1f s" % [path.get_file(), dials.size(), (Time.get_ticks_msec() - t0) / 1000.0, (t1 - t0) / 1000.0, (Time.get_ticks_msec() - t1) / 1000.0])
	for d: Dictionary in dials:
		var c: Vector2 = d["center"]
		var a: PackedFloat32Array = d.get("shape", PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
		print("  dial %4d %-24s at (%4d, %4d) r %.1f gap %.2f dot %.2f th %.4f shape %.3f,%.3f,%.3f,%.3f" % [int(d.get("code", 0)), _card_name(d), int(c.x), int(c.y), float(d["radius"]), float(d.get("gap", 0.0)), float(d.get("dot", 0.0)), float(d.get("th", 0.0)), a[0], a[1], a[2], a[3]])
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
	if d.has("placeholder"):
		return "[placeholder]"
	return cd.adv_name if bool(d.get("is_advanced", false)) and cd.adv_name != "" else cd.card_name
