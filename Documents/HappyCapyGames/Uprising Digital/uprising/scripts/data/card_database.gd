extends Node

## Autoload. Loads every card-data CSV under assets/data/ into typed Resource
## arrays. Each category exposes:
##   <name>_all   - every row, any language/box (kept for future i18n/expansion work)
##   <name>       - EN + Core only (the V1 scope filter)
## Call reload() to force a re-read (handy for iterating on data by hand
## without restarting the editor).

const DATA_DIR := "res://assets/data/"

const PATHS := {
	"heroes": DATA_DIR + "UPRISING _ FULL CARD DETAILS - Heros .csv",
	"legions": DATA_DIR + "UPRISING _ FULL CARD DETAILS - Legions.csv",
	"hordes": DATA_DIR + "UPRISING _ FULL CARD DETAILS - Hordes.csv",
	"items": DATA_DIR + "UPRISING _ FULL CARD DETAILS - Items.csv",
	"feats": DATA_DIR + "UPRISING _ FULL CARD DETAILS - Feats.csv",
	"events": DATA_DIR + "UPRISING _ FULL CARD DETAILS - Events.csv",
	"druids": DATA_DIR + "UPRISING _ FULL CARD DETAILS - Druids.csv",
	"hexes": DATA_DIR + "UPRISING _ FULL CARD DETAILS - Hexes.csv",
	"mercs": DATA_DIR + "UPRISING _ FULL CARD DETAILS - Mercs.csv",
	"playerboards": DATA_DIR + "UPRISING _ FULL CARD DETAILS - Playerboards.csv",
	"quests": DATA_DIR + "UPRISING _ FULL CARD DETAILS - Quests.csv",
}

var heroes_all: Array[HeroCard] = []
var legions_all: Array[LegionCard] = []
var hordes_all: Array[HordeCard] = []
var items_all: Array[ItemCard] = []
var feats_all: Array[FeatCard] = []
var events_all: Array[EventCard] = []
var druids_all: Array[DruidCard] = []
var hexes_all: Array[HexCard] = []
var mercs_all: Array[MercCard] = []
var playerboards_all: Array[PlayerboardData] = []
var quests_all: Array[QuestCard] = []

var heroes: Array[HeroCard] = []
var legions: Array[LegionCard] = []
var hordes: Array[HordeCard] = []
var items: Array[ItemCard] = []
var feats: Array[FeatCard] = []
var events: Array[EventCard] = []
var druids: Array[DruidCard] = []
var hexes: Array[HexCard] = []
var mercs: Array[MercCard] = []
var playerboards: Array[PlayerboardData] = []
var quests: Array[QuestCard] = []


func _ready() -> void:
	reload()


func reload() -> void:
	heroes_all = _load_heroes()
	legions_all = _load_legions()
	hordes_all = _load_hordes()
	items_all = _load_items()
	feats_all = _load_feats()
	events_all = _load_events()
	druids_all = _load_druids()
	hexes_all = _load_hexes()
	mercs_all = _load_mercs()
	playerboards_all = _load_playerboards()
	quests_all = _load_quests()

	heroes = heroes_all.filter(_is_en_core)
	legions = legions_all.filter(_is_en_core)
	hordes = hordes_all.filter(_is_en_core)
	items = items_all.filter(_is_en_core)
	feats = feats_all.filter(_is_en_core)
	events = events_all.filter(_is_en_core)
	# Druids have no real Box column (see DruidCard's doc comment) - every
	# row is already Core-scope, so Lang == "EN" is the only V1 filter.
	druids = druids_all.filter(func(d: DruidCard) -> bool: return d.lang == "EN")
	hexes = hexes_all.filter(_is_en_core)
	# Mercs have no Box column - out of V1 scope entirely (Mercenaries are an
	# expansion module) but loaded/exposed anyway for later use.
	mercs = mercs_all.filter(func(m: MercCard) -> bool: return m.lang == "EN")
	playerboards = playerboards_all.filter(_is_en_core)
	quests = quests_all.filter(_is_en_core)


func _is_en_core(card: Resource) -> bool:
	return card.lang == "EN" and card.box == "Core"


func _rows(path: String) -> Array:
	var split: Dictionary = CsvParser.parse_file_split(path)
	return split["rows"]


func _load_heroes() -> Array[HeroCard]:
	var out: Array[HeroCard] = []
	for row: PackedStringArray in _rows(PATHS["heroes"]):
		var c := HeroCard.new()
		c.lang = CsvParser.field(row, 0)
		c.box = CsvParser.field(row, 1)
		c.card_name = CsvParser.field(row, 2)
		c.faction = CsvParser.field(row, 3)
		c.flavor = CsvParser.field(row, 4)
		c.might = _to_int(CsvParser.field(row, 5))
		c.magic = _to_int(CsvParser.field(row, 6))
		c.lead = _to_int(CsvParser.field(row, 7))
		c.guile = _to_int(CsvParser.field(row, 8))
		out.append(c)
	return out


func _load_legions() -> Array[LegionCard]:
	var out: Array[LegionCard] = []
	for row: PackedStringArray in _rows(PATHS["legions"]):
		var c := LegionCard.new()
		c.lang = CsvParser.field(row, 0)
		c.box = CsvParser.field(row, 1)
		c.card_name = CsvParser.field(row, 2)
		c.flavor = CsvParser.field(row, 3)
		c.immediate = CsvParser.field(row, 4)
		c.combat = CsvParser.field(row, 5)
		c.bolt = CsvParser.field(row, 6)
		c.on_destroy = CsvParser.field(row, 7)
		out.append(c)
	return out


func _load_hordes() -> Array[HordeCard]:
	var out: Array[HordeCard] = []
	for row: PackedStringArray in _rows(PATHS["hordes"]):
		var c := HordeCard.new()
		c.lang = CsvParser.field(row, 0)
		c.box = CsvParser.field(row, 1)
		c.card_name = CsvParser.field(row, 2)
		c.flavor = CsvParser.field(row, 3)
		c.immediate = CsvParser.field(row, 4)
		c.combat = CsvParser.field(row, 5)
		c.bolt = CsvParser.field(row, 6)
		c.on_destroy = CsvParser.field(row, 7)
		out.append(c)
	return out


func _load_items() -> Array[ItemCard]:
	var out: Array[ItemCard] = []
	for row: PackedStringArray in _rows(PATHS["items"]):
		var c := ItemCard.new()
		c.lang = CsvParser.field(row, 0)
		c.box = CsvParser.field(row, 1)
		c.card_name = CsvParser.field(row, 2)
		c.text = CsvParser.field(row, 3)
		c.restrictions = CsvParser.field(row, 4)
		c.phases = CsvParser.field(row, 5)
		c.cost = CsvParser.field(row, 6)
		c.might = _to_int(CsvParser.field(row, 7))
		c.magic = _to_int(CsvParser.field(row, 8))
		c.lead = _to_int(CsvParser.field(row, 9))
		c.guile = _to_int(CsvParser.field(row, 10))
		out.append(c)
	return out


func _load_feats() -> Array[FeatCard]:
	var out: Array[FeatCard] = []
	for row: PackedStringArray in _rows(PATHS["feats"]):
		var c := FeatCard.new()
		c.lang = CsvParser.field(row, 0)
		c.box = CsvParser.field(row, 1)
		c.card_name = CsvParser.field(row, 2)
		c.faction = CsvParser.field(row, 3)
		c.phase = CsvParser.field(row, 4)
		c.text = CsvParser.field(row, 5)
		c.restrictions = CsvParser.field(row, 6)
		out.append(c)
	return out


func _load_events() -> Array[EventCard]:
	var out: Array[EventCard] = []
	for row: PackedStringArray in _rows(PATHS["events"]):
		var c := EventCard.new()
		c.lang = CsvParser.field(row, 0)
		c.box = CsvParser.field(row, 1)
		c.card_name = CsvParser.field(row, 2)
		c.nr = CsvParser.field(row, 3)
		c.flavor_1 = CsvParser.field(row, 4)
		c.effect_1 = CsvParser.field(row, 5)
		c.flavor_2 = CsvParser.field(row, 6)
		c.effect_2 = CsvParser.field(row, 7)
		out.append(c)
	return out


func _load_druids() -> Array[DruidCard]:
	var out: Array[DruidCard] = []
	for row: PackedStringArray in _rows(PATHS["druids"]):
		var c := DruidCard.new()
		c.lang = CsvParser.field(row, 0)
		c.card_name = CsvParser.field(row, 1)
		c.advanced = CsvParser.field(row, 2)
		c.archery_and_clash = CsvParser.field(row, 3)
		c.restrictions = CsvParser.field(row, 4)
		c.refresh_phase = CsvParser.field(row, 5)
		out.append(c)
	return out


func _load_hexes() -> Array[HexCard]:
	var out: Array[HexCard] = []
	for row: PackedStringArray in _rows(PATHS["hexes"]):
		var c := HexCard.new()
		c.lang = CsvParser.field(row, 0)
		c.box = CsvParser.field(row, 1)
		c.card_name = CsvParser.field(row, 2)
		c.hex_type = CsvParser.field(row, 3)
		c.flavor = CsvParser.field(row, 4)
		c.ongoing_effect = CsvParser.field(row, 5)
		c.effect = CsvParser.field(row, 6)
		c.terrain = CsvParser.field(row, 7)
		c.resources = CsvParser.field(row, 8)
		c.salt = CsvParser.field(row, 9)
		c.plunder = CsvParser.field(row, 10)
		c.food = CsvParser.field(row, 11)
		c.special = CsvParser.field(row, 12)
		c.side = CsvParser.field(row, 13)
		c.x = CsvParser.field(row, 14)
		out.append(c)
	return out


func _load_mercs() -> Array[MercCard]:
	var out: Array[MercCard] = []
	for row: PackedStringArray in _rows(PATHS["mercs"]):
		var c := MercCard.new()
		c.lang = CsvParser.field(row, 0)
		c.card_name = CsvParser.field(row, 1)
		c.cost = CsvParser.field(row, 2)
		c.phases = CsvParser.field(row, 3)
		c.text = CsvParser.field(row, 4)
		c.restrictions = CsvParser.field(row, 5)
		out.append(c)
	return out


func _load_playerboards() -> Array[PlayerboardData]:
	var out: Array[PlayerboardData] = []
	for row: PackedStringArray in _rows(PATHS["playerboards"]):
		var c := PlayerboardData.new()
		c.lang = CsvParser.field(row, 0)
		c.box = CsvParser.field(row, 1)
		c.front = CsvParser.field(row, 2)
		c.back = CsvParser.field(row, 3)
		out.append(c)
	return out


func _load_quests() -> Array[QuestCard]:
	var out: Array[QuestCard] = []
	for row: PackedStringArray in _rows(PATHS["quests"]):
		var c := QuestCard.new()
		# Column 0's header is a typo ("a" instead of "Lang") - read positionally.
		c.lang = CsvParser.field(row, 0)
		c.box = CsvParser.field(row, 1)
		c.card_name = CsvParser.field(row, 2)
		c.flavour = CsvParser.field(row, 3)
		c.immediate_effect = CsvParser.field(row, 4)
		c.solve = CsvParser.field(row, 5)
		c.failure = CsvParser.field(row, 6)
		c.successes = CsvParser.field(row, 7)
		c.skulls = CsvParser.field(row, 8)
		c.skull_bonus = CsvParser.field(row, 9)
		c.shields = CsvParser.field(row, 10)
		c.shield_bonus = CsvParser.field(row, 11)
		c.bolts = CsvParser.field(row, 12)
		c.bolt_bonus = CsvParser.field(row, 13)
		c.terrain_bonus = CsvParser.field(row, 14)
		out.append(c)
	return out


func _to_int(s: String) -> int:
	var t: String = s.strip_edges()
	if t.is_empty() or not t.is_valid_int():
		return 0
	return t.to_int()


## Reports Core-scope cards (by category) that ImageManifest/ModelManifest
## can't resolve an asset for - run on demand (e.g. from an editor tool
## script), not automatically at _ready(), since it needs both other
## autoloads fully loaded first.
func self_check_assets() -> Array[String]:
	# The manifest's link_col for Heroes/Legions/Hordes is "Name" (the XLSX
	# hyperlink is attached to the Name cell itself), not "Front" -
	# confirmed by inspecting real _image_manifest.csv rows, not assumed.
	var problems: Array[String] = []
	for h: HeroCard in heroes:
		if ImageManifest.get_image_path("Heros", "EN", h.card_name, "Name").is_empty():
			problems.append("Hero '%s' has no resolved image" % h.card_name)
	for l: LegionCard in legions:
		if ImageManifest.get_image_path("Legions", "EN", l.card_name, "Name").is_empty():
			problems.append("Legion '%s' has no resolved image" % l.card_name)
	for hd: HordeCard in hordes:
		if ImageManifest.get_image_path("Hordes", "EN", hd.card_name, "Name").is_empty():
			problems.append("Horde '%s' has no resolved image" % hd.card_name)
	return problems
