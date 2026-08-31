extends Node
## Autoload singleton. Loads every card CSV under res://assets/data/ plus the
## image manifest, and exposes typed arrays of card Resources.
##
## Source CSVs are exported from "UPRISING _ FULL CARD DETAILS.xlsx" (one
## sheet per category, EN and DE rows interleaved). The image manifest
## (_image_manifest.csv) maps each (sheet, lang, name[, column]) to the
## downloaded card art under res://assets/images/, since hyperlinks don't
## survive a CSV export on their own.

const DATA_DIR := "res://assets/data/"
const IMAGE_MANIFEST_PATH := DATA_DIR + "_image_manifest.csv"

const CSV_FILES := {
	"druids": "UPRISING _ FULL CARD DETAILS - Druids.csv",
	"events": "UPRISING _ FULL CARD DETAILS - Events.csv",
	"feats": "UPRISING _ FULL CARD DETAILS - Feats.csv",
	"heros": "UPRISING _ FULL CARD DETAILS - Heros .csv",
	"hexes": "UPRISING _ FULL CARD DETAILS - Hexes.csv",
	"hordes": "UPRISING _ FULL CARD DETAILS - Hordes.csv",
	"items": "UPRISING _ FULL CARD DETAILS - Items.csv",
	"legions": "UPRISING _ FULL CARD DETAILS - Legions.csv",
	"mercs": "UPRISING _ FULL CARD DETAILS - Mercs.csv",
	"playerboards": "UPRISING _ FULL CARD DETAILS - Playerboards.csv",
	"quests": "UPRISING _ FULL CARD DETAILS - Quests.csv",
}

var heroes: Array[HeroCard] = []
var legions: Array[LegionCard] = []
var hordes: Array[HordeCard] = []
var quests: Array[QuestCard] = []
var items: Array[ItemCard] = []
var feats: Array[FeatCard] = []
var events: Array[EventCard] = []
var druids: Array[DruidCard] = []
var hexes: Array[HexCard] = []
var mercs: Array[MercCard] = []
var playerboards: Array[PlayerboardData] = []

## (sheet_lower, lang, name) -> Dictionary{ link_col: String -> res_path: String }
var _image_lookup: Dictionary = {}


func _ready() -> void:
	_load_image_manifest()
	_load_heroes()
	_load_legions()
	_load_hordes()
	_load_quests()
	_load_items()
	_load_feats()
	_load_events()
	_load_druids()
	_load_hexes()
	_load_mercs()
	_load_playerboards()
	print("CardDatabase: loaded %d heroes, %d legions, %d hordes, %d quests, %d items, %d feats, %d events, %d druids, %d hexes, %d mercs, %d playerboards" % [
		heroes.size(), legions.size(), hordes.size(), quests.size(), items.size(),
		feats.size(), events.size(), druids.size(), hexes.size(), mercs.size(), playerboards.size(),
	])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _to_int(raw: String) -> int:
	var s := raw.strip_edges()
	if s == "" or s == "-":
		return 0
	return int(s.to_float())


static func _rows(key: String) -> Array[Dictionary]:
	return CsvParser.parse_file_as_dicts(DATA_DIR + CSV_FILES[key])


func _image_key(sheet: String, lang: String, name: String) -> String:
	return "%s|%s|%s" % [sheet.to_lower(), lang, name]


func _load_image_manifest() -> void:
	var rows := CsvParser.parse_file_as_dicts(IMAGE_MANIFEST_PATH)
	for row in rows:
		if row.get("downloaded", "") != "True":
			continue
		var key := _image_key(row.get("sheet", ""), row.get("lang", ""), row.get("name", ""))
		if not _image_lookup.has(key):
			_image_lookup[key] = {}
		var by_col: Dictionary = _image_lookup[key]
		by_col[row.get("link_col", "")] = row.get("res_path", "")


## Returns the res:// path for a card's art, or "" if none was found.
## `column` lets Playerboards pick "Front" or "Back"; other sheets only ever
## have one image, filed under their Name column header.
func find_texture_path(sheet: String, lang: String, name: String, column: String = "") -> String:
	var key := _image_key(sheet, lang, name)
	if not _image_lookup.has(key):
		return ""
	var by_col: Dictionary = _image_lookup[key]
	if column != "" and by_col.has(column):
		return by_col[column]
	# Fall back to whichever single image is filed for this row.
	for v in by_col.values():
		return v
	return ""


# ---------------------------------------------------------------------------
# Per-category loaders
# ---------------------------------------------------------------------------

func _load_heroes() -> void:
	for row in _rows("heros"):
		var card := HeroCard.new()
		card.lang = row.get("Lang", "")
		card.box = row.get("Box", "")
		card.card_name = row.get("Name", "")
		card.faction = row.get("Faction", "")
		card.flavor = row.get("Flavor", "")
		card.might = _to_int(row.get("Might", ""))
		card.magic = _to_int(row.get("Magic", ""))
		card.lead = _to_int(row.get("Lead", ""))
		card.guile = _to_int(row.get("Guile", ""))
		card.texture_path = find_texture_path("Heros", card.lang, card.card_name)
		heroes.append(card)


func _load_legions() -> void:
	for row in _rows("legions"):
		var card := LegionCard.new()
		card.lang = row.get("Lang", "")
		card.box = row.get("Box", "")
		card.card_name = row.get("Name", "")
		card.flavor = row.get("Flavor", "")
		card.immediate = row.get("Immediate", "")
		card.combat = row.get("Combat", "")
		card.bolt = row.get("Bolt", "")
		card.on_destroy = row.get("On destroy", "")
		card.texture_path = find_texture_path("Legions", card.lang, card.card_name)
		legions.append(card)


func _load_hordes() -> void:
	for row in _rows("hordes"):
		var card := HordeCard.new()
		card.lang = row.get("Lang", "")
		card.box = row.get("Box", "")
		card.card_name = row.get("Name", "")
		card.flavor = row.get("Flavor", "")
		card.immediate = row.get("Immediate", "")
		card.combat = row.get("Combat", "")
		card.bolt = row.get("Bolt", "")
		card.on_destroy = row.get("On destroy", "")
		card.texture_path = find_texture_path("Hordes", card.lang, card.card_name)
		hordes.append(card)


func _load_quests() -> void:
	for row in _rows("quests"):
		var card := QuestCard.new()
		card.lang = row.get("a", "")
		card.box = row.get("Box", "")
		card.card_name = row.get("Name", "")
		card.flavor = row.get("Flavour", "")
		card.immediate_effect = row.get("Immediate Effect", "")
		card.solve = row.get("Solve", "")
		card.failure = row.get("Failure", "")
		card.successes_needed = _to_int(row.get("Succeses", ""))
		card.skulls_threshold = _to_int(row.get("Skulls", ""))
		card.skulls_reward = row.get("Skull Bonus", "")
		card.shields_threshold = _to_int(row.get("Shields", ""))
		card.shields_reward = row.get("Shield Bonus", "")
		card.bolts_threshold = _to_int(row.get("Bolts", ""))
		card.bolts_reward = row.get("Bolt Bonus", "")
		card.terrain_bonus = row.get("Terrain Bonus", "")
		card.texture_path = find_texture_path("Quests", card.lang, card.card_name)
		quests.append(card)


func _load_items() -> void:
	for row in _rows("items"):
		var card := ItemCard.new()
		card.lang = row.get("Lang", "")
		card.box = row.get("Box", "")
		card.card_name = row.get("Name", "")
		card.text = row.get("Text", "")
		card.restrictions = row.get("Restrictions", "")
		card.phases = row.get("Phases", "")
		card.cost = _to_int(row.get("Cost", ""))
		card.might = _to_int(row.get("Might", ""))
		card.magic = _to_int(row.get("Magic", ""))
		card.lead = _to_int(row.get("Lead", ""))
		card.guile = _to_int(row.get("Guile", ""))
		card.texture_path = find_texture_path("Items", card.lang, card.card_name)
		items.append(card)


func _load_feats() -> void:
	for row in _rows("feats"):
		var card := FeatCard.new()
		card.lang = row.get("Lang", "")
		card.box = row.get("Box", "")
		card.card_name = row.get("Name", "")
		card.faction = row.get("Faction", "")
		card.phase = row.get("Phase", "")
		card.text = row.get("Text", "")
		card.restrictions = row.get("Restrictions", "")
		card.texture_path = find_texture_path("Feats", card.lang, card.card_name)
		feats.append(card)


func _load_events() -> void:
	for row in _rows("events"):
		var card := EventCard.new()
		card.lang = row.get("Lang", "")
		card.box = row.get("Box", "")
		card.card_name = row.get("Name", "")
		card.chapter = row.get("Nr.", "")
		card.flavor_1 = row.get("Flavor 1", "")
		card.effect_1 = row.get("Effect 1", "")
		card.flavor_2 = row.get("Flavor 2", "")
		card.effect_2 = row.get("Effect 2", "")
		card.texture_path = find_texture_path("Events", card.lang, card.card_name)
		events.append(card)


func _load_druids() -> void:
	for row in _rows("druids"):
		var card := DruidCard.new()
		# The "Box" header actually holds Lang for this sheet; see DruidCard docs.
		card.lang = row.get("Box", "")
		card.card_name = row.get("Name", "")
		card.godpower = row.get("Archery & Clash", "")
		card.restrictions = row.get("Restrictions", "")
		card.refresh_phase = row.get("Refresh Phase", "")
		card.texture_path = find_texture_path("Druids", card.lang, card.card_name)
		druids.append(card)


func _load_hexes() -> void:
	for row in _rows("hexes"):
		var card := HexCard.new()
		card.lang = row.get("Lang", "")
		card.box = row.get("Box", "")
		card.card_name = row.get("Name", "")
		card.hex_type = row.get("Type", "")
		card.flavor = row.get("Flavor", "")
		card.ongoing_effect = row.get("Ongoing Effect", "")
		card.effect = row.get("Effect", "")
		card.terrain = row.get("Terrain", "")
		card.resources = _to_int(row.get("Resources", ""))
		card.salt = _to_int(row.get("Salt", ""))
		card.plunder = _to_int(row.get("Plunder", ""))
		card.food = _to_int(row.get("Food", ""))
		card.special = row.get("Special", "")
		card.side = row.get("Side", "")
		card.no_haven = row.get("X", "").strip_edges() == "X"
		card.texture_path = find_texture_path("Hexes", card.lang, card.card_name)
		hexes.append(card)


func _load_mercs() -> void:
	for row in _rows("mercs"):
		var card := MercCard.new()
		card.lang = row.get("Lang", "")
		card.card_name = row.get("Name", "")
		card.cost_text = row.get("Cost", "")
		card.phases = row.get("Phases", "")
		card.text = row.get("Text", "")
		card.restrictions = row.get("Restrictions", "")
		card.texture_path = find_texture_path("Mercs", card.lang, card.card_name)
		mercs.append(card)


func _load_playerboards() -> void:
	for row in _rows("playerboards"):
		var card := PlayerboardData.new()
		card.lang = row.get("Lang", "")
		card.box = row.get("Box", "")
		card.front = row.get("Front", "")
		card.back = row.get("Back", "")
		card.front_texture_path = find_texture_path("Playerboards", card.lang, card.front, "Front")
		card.back_texture_path = find_texture_path("Playerboards", card.lang, card.front, "Back")
		playerboards.append(card)
