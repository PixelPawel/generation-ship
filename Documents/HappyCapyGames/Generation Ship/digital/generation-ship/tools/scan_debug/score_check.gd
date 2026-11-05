extends Node
# Offline check of Scan Tableau's VP against the game's own scoring (2026-11-05). For every mockup
# photo (Layout/InDesign/_automation/scan_code/mockups3.py; <name>.truth.json holds the real ship) it
# prints three totals:
#   game   the true ship built on real SectorSlots (sector, then its techs in order, the optimize state
#          re-checked after every card as Board._update_optimize_state does) and scored by
#          Scoring.calculate: what the game itself shows for that ship
#   truth  the same ship as the app's ship entries (photo_scan._sector_entry_from_group) scored like the
#          app does (BotScoring.board_vp_lines): must equal "game"
#   photo  what the app makes of the photo (DialReader -> TableauReader -> entries -> BotScoring)
# and every line that differs. Run as a scene so the autoloads (CardDatabase) exist:
#   godot --headless --path . res://tools/scan_debug/score_check.tscn -- a.jpg b.jpg [--no-photo]

const DialReaderScript := preload("res://scripts/photo_scan/dial_reader.gd")
const TableauReaderScript := preload("res://scripts/photo_scan/tableau_reader.gd")
const SectorSlotScene := preload("res://scenes/board/sector_slot.tscn")
const CardScene := preload("res://scenes/card/card.tscn")
const PhotoScanScript := preload("res://scenes/photo_scan/photo_scan.gd")
const TOKEN_COLORS: Dictionary = {
	"Dust": CardData.SupplyColor.DUST, "Metals": CardData.SupplyColor.METALS,
	"Liquids": CardData.SupplyColor.LIQUIDS, "Organix": CardData.SupplyColor.ORGANIX,
	"Electrix": CardData.SupplyColor.ELECTRIX, "Thrust": CardData.SupplyColor.THRUST,
}

var _app: Control = null        # a bare photo_scan instance (never in the tree), for its entry builder
var _n: int = 0
var _truth_ok: int = 0
var _photo_ok: int = 0
var _photos: int = 0

func _ready() -> void:
	while CardDatabase.sectors.is_empty():
		await get_tree().process_frame
	_app = PhotoScanScript.new() as Control
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var with_photo: bool = not args.has("--no-photo")
	for path: String in args:
		if path.begins_with("--random="):
			_random_ships(int(path.get_slice("=", 1)))
		elif not path.begins_with("--"):
			_check(path, with_photo)
	print("TOTAL %d ships: scan scorer = game on %d/%d%s" % [_n, _truth_ok, _n,
		("" if _photos == 0 else ", photo read = game on %d/%d" % [_photo_ok, _photos])])
	_app.free()
	get_tree().quit()

func _check(path: String, with_photo: bool) -> void:
	var truth_path: String = path.get_basename() + ".truth.json"
	if not FileAccess.file_exists(truth_path):
		print("no truth for ", path)
		return
	var truth: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(truth_path)) as Dictionary
	var groups: Array = []
	for s: Variant in (truth["sectors"] as Array):
		var sec: Dictionary = s as Dictionary
		var sd: Dictionary = _ref(int(sec["code"]))
		var ups: Array = []
		for c: Variant in (sec.get("archived_up", []) as Array):
			ups.append(_ref(int(c)))
		sd["archived_up"] = ups
		sd["archived_down"] = int(sec.get("archived_down", 0))
		var supply: Dictionary = {}
		for t: Variant in (sec.get("tokens", []) as Array):
			var col: int = int(TOKEN_COLORS[str(t)])
			supply[col] = int(supply.get(col, 0)) + 1
		sd["supply"] = supply
		var g: Array = [sd]
		for c: Variant in (sec.get("techs", []) as Array):
			g.append(_ref(int(c)))
		groups.append(g)
	Scoring.other_players_expeditions = 0
	var game: Array[Dictionary] = _game_lines(groups)
	var scan_truth: Array[Dictionary] = BotScoring.board_vp_lines(_entries(groups))
	_n += 1
	var g_total: int = _total(game)
	var t_total: int = _total(scan_truth)
	if g_total == t_total:
		_truth_ok += 1
	var line: String = "=== %-34s game %3d | scan scorer on the true ship %3d" % [path.get_file(), g_total, t_total]
	var photo: Array[Dictionary] = []
	if with_photo:
		photo = _photo_lines(path)
		_photos += 1
		if _total(photo) == g_total:
			_photo_ok += 1
		line += " | scan from the photo %3d" % _total(photo)
	print(line)
	_diff("scan scorer", game, scan_truth)
	if with_photo:
		_diff("photo", game, photo)

## --random=N: N random ships from the whole card pool (1-6 sectors, 0-5 cards each, archives and
## supply), half of the sectors given techs in the colours they need to optimize, scored by the game
## and by the app's scorer. Prints the first ships that differ.
func _random_ships(count: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261105
	var by_color: Dictionary = {}
	for cd: CardData in CardDatabase.techs:
		if not by_color.has(int(cd.color)):
			by_color[int(cd.color)] = []
		(by_color[int(cd.color)] as Array).append(cd)
	var pool: Array[CardData] = []
	pool.append_array(CardDatabase.techs)
	pool.append_array(CardDatabase.expeditions)
	var shown: int = 0
	var same: int = 0
	var seen: Dictionary = {}        # scoring line -> ships where the game scored it
	for k: int in count:
		var groups: Array = []
		for _s: int in rng.randi_range(1, 6):
			var sector: CardData = CardDatabase.sectors[rng.randi_range(0, CardDatabase.sectors.size() - 1)]
			var is_adv: bool = rng.randf() < 0.7
			var ups: Array = []
			for _u: int in rng.randi_range(0, 2):
				ups.append({card = pool[rng.randi_range(0, pool.size() - 1)], is_advanced = false})
			var supply: Dictionary = {}
			for _t: int in rng.randi_range(0, 5):
				var col: int = rng.randi_range(0, 5)
				supply[col] = int(supply.get(col, 0)) + 1
			var g: Array = [{card = sector, is_advanced = is_adv, archived_up = ups,
				archived_down = rng.randi_range(0, 4), supply = supply}]
			var want: Array[int] = []
			if rng.randf() < 0.5:
				for req: Variant in ([sector.adv_opt1_req, sector.adv_opt2_req, sector.adv_opt3_req] if is_adv else [sector.opt1_req]):
					for c: Variant in (req as Array):
						want.append(int(c))
			for t: int in rng.randi_range(0, 5):
				var cd: CardData = pool[rng.randi_range(0, pool.size() - 1)]
				if t < want.size() and want[t] >= 0 and by_color.has(want[t]):
					var same_color: Array = by_color[want[t]]
					cd = same_color[rng.randi_range(0, same_color.size() - 1)] as CardData
				g.append({card = cd, is_advanced = false})
			groups.append(g)
		var game: Array[Dictionary] = _game_lines(groups)
		var scan: Array[Dictionary] = BotScoring.board_vp_lines(_entries(groups))
		for label: String in _normalised(game):
			seen[label] = int(seen.get(label, 0)) + 1
		if _total(game) == _total(scan) and _normalised(game) == _normalised(scan):
			same += 1
		elif shown < 12:
			shown += 1
			print("random ship %d: game %d, scan scorer %d" % [k, _total(game), _total(scan)])
			_diff("scan scorer", game, scan)
	print("RANDOM %d ships: scan scorer = game (every line) on %d" % [count, same])
	var parts: Array[String] = []
	for label: String in seen:
		parts.append("%s %d" % [label, int(seen[label])])
	print("  lines scored (ships): ", ", ".join(parts))

## The ship on real SectorSlots, scored by the game's own Scoring.
func _game_lines(groups: Array) -> Array[Dictionary]:
	var row: Node3D = Node3D.new()
	add_child(row)
	for g: Array in groups:
		var slot: SectorSlot = SectorSlotScene.instantiate() as SectorSlot
		row.add_child(slot)
		slot.accept_card(_card_node(row, g[0] as Dictionary))
		_optimize(slot)
		for i: int in range(1, g.size()):
			slot.accept_tech_card(_card_node(row, g[i] as Dictionary))
			_optimize(slot)
		var sd: Dictionary = g[0]
		for d: Variant in (sd["archived_up"] as Array):
			slot.add_tucked_card((d as Dictionary)["card"] as CardData, true)
		for _k: int in int(sd["archived_down"]):
			slot.add_tucked_card(null, false)
		var supply: Dictionary = sd["supply"]
		for col: Variant in supply:
			slot.add_stored_supply(int(col) as CardData.SupplyColor, int(supply[col]))
	var lines: Array[Dictionary] = Scoring.calculate(row)
	row.free()
	return lines

# as Board._update_optimize_state (outside Fleet)
func _optimize(slot: SectorSlot) -> void:
	var cd: CardData = slot.placed_card.card_data
	var result: Dictionary = OptimizeLogic.update_optimize_state(cd, bool(slot.placed_card.get("is_advanced")),
		slot.get_placed_tech_colors(), slot.optimize_count, slot.max_optimizations, slot.triggered_levels)
	slot.optimize_count = int(result["optimize_count"])
	slot.is_optimized = bool(result["is_optimized"])
	slot.triggered_levels = result["triggered_levels"] as Array[bool]

func _card_node(parent: Node3D, d: Dictionary) -> Node3D:
	var n: Node3D = CardScene.instantiate() as Node3D
	n.set("is_advanced", bool(d.get("is_advanced", false)))
	n.set("card_data", d["card"] as CardData)
	parent.add_child(n)
	return n

func _entries(groups: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g: Array in groups:
		var e: Dictionary = _app.call("_sector_entry_from_group", g) as Dictionary
		if not e.is_empty():
			out.append(e)
	return out

## What the app scores for the photo itself.
func _photo_lines(path: String) -> Array[Dictionary]:
	var img: Image = Image.new()
	if img.load(path) != OK:
		return []
	var reader: DialReader = DialReaderScript.create()
	var dials: Array[Dictionary] = reader.run(img)
	var tableau: TableauReader = TableauReaderScript.create(dials)
	tableau.placeholder_card = CardDatabase.find_by_scan_code(450).get("card") as CardData
	var groups: Array = tableau.analyze(reader.photo, dials, reader.markers)
	return BotScoring.board_vp_lines(_entries(groups))

func _ref(code: int) -> Dictionary:
	var r: Dictionary = CardDatabase.find_by_scan_code(code)
	if r.is_empty():
		push_error("score_check: no card with scan code %d" % code)
	return r.duplicate()

static func _total(lines: Array[Dictionary]) -> int:
	var t: int = 0
	for l: Dictionary in lines:
		t += int(l["vp"])
	return t

# Lines by name as the app shows them: the game's labels carry a hint ("Stars (⭐)", "Stored supply
# (1 VP each)") and list the Greenhouse / Astra Cultura bonus apart, the app adds it to Stored supply.
static func _normalised(lines: Array[Dictionary]) -> Dictionary:
	var out: Dictionary = {}
	for l: Dictionary in lines:
		var label: String = str(l["label"]).get_slice(" (", 0)
		if label in ["Greenhouses", "Greenhouse", "Astra Cultura"] and str(l["label"]).contains("bonus"):
			label = "Stored supply"
		out[label] = int(out.get(label, 0)) + int(l["vp"])
	return out

static func _diff(what: String, game: Array[Dictionary], other: Array[Dictionary]) -> void:
	var a: Dictionary = _normalised(game)
	var b: Dictionary = _normalised(other)
	var parts: Array[String] = []
	for k: String in a:
		if int(b.get(k, 0)) != int(a[k]):
			parts.append("%s %d -> %d" % [k, int(a[k]), int(b.get(k, 0))])
	for k: String in b:
		if not a.has(k):
			parts.append("%s 0 -> %d" % [k, int(b[k])])
	if not parts.is_empty():
		print("    %s differs: %s" % [what, ", ".join(parts)])
