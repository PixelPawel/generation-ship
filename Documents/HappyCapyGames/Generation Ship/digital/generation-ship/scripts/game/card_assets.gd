extends Node

# Maps normalized filenames to res:// paths for fast art lookup.
var _sector_index: Dictionary = {}
var _tech_index: Dictionary = {}
var _exp_index: Dictionary = {}

const _FRAME_SECTOR := "res://assets/frames/Sectors/"
const _FRAME_TECH   := "res://assets/frames/Techs/"
const _FRAME_EXP    := "res://assets/frames/Expeditions/"

func _ready() -> void:
	_build_index(_sector_index, "res://assets/art/sectors/")
	_build_index(_tech_index,   "res://assets/art/tech/")
	_build_index(_exp_index,    "res://assets/art/expeditions/")

# ── Frame paths ───────────────────────────────────────────────────────────────

func frame_path(cd: CardData, is_advanced: bool) -> String:
	var color := CardData.effective_color(cd, is_advanced)
	var cn    := _frame_color(color)
	match cd.card_type:
		CardData.CardType.SECTOR:
			var cost := CardData.effective_cost(cd, is_advanced)
			var tier := "1x" if cost <= 1 else ("2x" if cost == 2 else "3x")
			return _FRAME_SECTOR + "Deck-%s_%s.png" % [cn, tier]
		CardData.CardType.TECH:
			return _FRAME_TECH + "Tech-%s_%s.png" % [cn, cd.frame_trigger()]
		CardData.CardType.EXPEDITION:
			return _FRAME_EXP + "Trek-%s_%s.png" % [cn, cd.frame_trigger_exp()]
	return ""

# ── Art paths ─────────────────────────────────────────────────────────────────

func art_path(cd: CardData, is_advanced: bool) -> String:
	match cd.card_type:
		CardData.CardType.SECTOR:
			var card_name := cd.adv_name if is_advanced else cd.card_name
			return _find_art(_sector_index, card_name, cd.id)
		CardData.CardType.TECH:
			return _find_art(_tech_index, cd.card_name, cd.id)
		CardData.CardType.EXPEDITION:
			return _find_art(_exp_index, cd.card_name, cd.id)
	return ""

# ── Helpers ───────────────────────────────────────────────────────────────────

func _frame_color(color: CardData.SupplyColor) -> String:
	match color:
		CardData.SupplyColor.DUST:    return "Dust"
		CardData.SupplyColor.METALS:  return "Metal"
		CardData.SupplyColor.LIQUIDS: return "Water"
		CardData.SupplyColor.ORGANIX: return "DNA"
		CardData.SupplyColor.ELECTRIX: return "Tech"
		CardData.SupplyColor.THRUST:  return "Thrust"
	return "Dust"

func _build_index(dict: Dictionary, dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".png") and file != "ExpeditionBack.png":
			dict[_normalize(file.get_basename())] = dir_path + file
		file = dir.get_next()
	dir.list_dir_end()

func _normalize(s: String) -> String:
	return s.to_lower().replace(" ", "").replace("_", "").replace("-", "")

func _find_art(index: Dictionary, card_name: String, id: int) -> String:
	var key := _normalize(card_name)
	# Exact match
	if index.has(key):
		return index[key]
	# Suffix match handles "tch04fungi" → card name "fungi"
	for file_key: String in index.keys():
		if file_key.ends_with(key):
			return index[file_key]
	# Contains match for non-standard names
	if key.length() >= 4:
		for file_key: String in index.keys():
			if file_key.contains(key):
				return index[file_key]
	return ""
