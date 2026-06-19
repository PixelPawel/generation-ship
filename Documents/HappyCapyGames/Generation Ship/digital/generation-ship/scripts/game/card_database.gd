extends Node

var sectors: Array[CardData] = []
var techs: Array[CardData] = []
var expeditions: Array[CardData] = []

var _local_art: Dictionary = {}  # normalized_name -> res:// path

func _ready() -> void:
	_build_local_art_lookup()
	_load_sector_cards()
	_load_techs()
	_load_expeditions()
	print("CardDatabase loaded: %d sectors, %d techs, %d expeditions" % [sectors.size(), techs.size(), expeditions.size()])

func _build_local_art_lookup() -> void:
	var dirs: Array[String] = [
		"res://assets/art/tech",
		"res://assets/art/expeditions",
		"res://assets/art/sectors",
	]
	for dir_path: String in dirs:
		var dir: DirAccess = DirAccess.open(dir_path)
		if not dir:
			continue
		dir.list_dir_begin()
		var fname: String = dir.get_next()
		while fname != "":
			if fname.ends_with(".png"):
				var key: String = _normalize(fname.get_basename())
				if not _local_art.has(key):
					_local_art[key] = dir_path + "/" + fname
			fname = dir.get_next()
		dir.list_dir_end()

static func _normalize(s: String) -> String:
	var r: RegEx = RegEx.new()
	r.compile("^(?:TCH|GS|EXP|SEC|CBK)_\\d+_")
	s = r.sub(s, "")
	r.compile("^(?:Technologies|Expedition)[-_]\\d+[-_]")
	s = r.sub(s, "")
	r.compile("[_ ]\\d+$")
	s = r.sub(s, "")
	var out: String = ""
	for ch: String in s:
		var code: int = ch.unicode_at(0)
		if (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
			out += ch.to_lower()
		elif code >= 48 and code <= 57:
			out += ch
	return out

func _local_art_url(name: String) -> String:
	return _local_art.get(_normalize(name), "")

func _load_sector_cards() -> void:
	# Build dust side lookup by name
	var dust_rows := _read_csv("res://data/Generation Ship Full Card Details - Dust Sectors.csv")
	var dust_by_name: Dictionary = {}
	for row in dust_rows:
		var card_name: String = row.get("Name", "").strip_edges()
		if not card_name.is_empty():
			dust_by_name[card_name] = row

	# Each row in the advanced CSV is one physical card (30 total)
	var adv_rows := _read_csv("res://data/Generation Ship Full Card Details - Advanced Sectors.csv")
	for row in adv_rows:
		if not _valid_id(row.get("No.", "")):
			continue
		var backside_name: String = row.get("Backside", "").strip_edges()
		var dust: Dictionary = dust_by_name.get(backside_name, {})

		var card := CardData.new()
		card.id = int(row["No."])
		card.card_type = CardData.CardType.SECTOR
		card.stars = row.get("Printed Star", "").count("⭐")
		card.is_star_card = _parse_yes_no(row.get("Star Card", row.get("Star card", "No")))

		# Dust side (shown face-up in the deck / base display)
		card.card_name = dust.get("Name", backside_name).strip_edges()
		card.color = CardData.SupplyColor.DUST
		card.cost = int(dust.get("Cost", "2")) if dust.get("Cost", "").is_valid_int() else 2
		card.effect_text = dust.get("Effect", "").strip_edges()
		card.flavor_text = dust.get("Flavor", "").strip_edges()
		card.image_url = dust.get("Link", "").strip_edges()
		card.local_art_path = _local_art_url(card.card_name)
		card.opt1_req = _parse_color_list(dust.get("Optimize 1", ""))

		# Advanced side
		card.adv_name = row.get("Name", "").strip_edges()
		card.adv_color = _parse_color(row.get("Color", ""))
		card.adv_cost = int(row.get("Cost", "0")) if row.get("Cost", "").is_valid_int() else 0
		card.adv_effect_text = row.get("Effect", "").strip_edges()
		card.adv_flavor_text = row.get("Flavor", "").strip_edges()
		card.adv_image_url = row.get("Link", "").strip_edges()
		card.adv_local_art_path = _local_art_url(card.adv_name)
		card.adv_opt1_req = _parse_color_list(row.get("Optimize 1", ""))
		card.adv_opt2_req = _parse_color_list(row.get("Optimize 2", ""))
		card.adv_opt3_req = _parse_color_list(row.get("Optimize 3", ""))

		sectors.append(card)

func _load_techs() -> void:
	var rows := _read_csv("res://data/Generation Ship Full Card Details - Techs.csv")
	for row in rows:
		if not _valid_id(row.get("No.", "")):
			continue
		var card := CardData.new()
		card.id = int(row["No."])
		card.card_type = CardData.CardType.TECH
		_populate_base_fields(card, row)
		techs.append(card)

func _load_expeditions() -> void:
	var rows := _read_csv("res://data/Generation Ship Full Card Details - Expeditions.csv")
	for row in rows:
		if not _valid_id(row.get("No.", "")):
			continue
		var card := CardData.new()
		card.id = int(row["No."])
		card.card_type = CardData.CardType.EXPEDITION
		_populate_base_fields(card, row)
		expeditions.append(card)

func _populate_base_fields(card: CardData, row: Dictionary) -> void:
	card.card_name      = row.get("Name", "")
	card.color          = _parse_color(row.get("Color", ""))
	card.cost           = int(row.get("Cost", "0")) if row.get("Cost", "").is_valid_int() else 0
	card.effect_text    = row.get("Effect", "").strip_edges()
	card.flavor_text    = row.get("Flavor", "").strip_edges()
	card.image_url      = row.get("Link", "")
	card.local_art_path = _local_art_url(card.card_name)
	card.stars          = row.get("Printed Star", "").count("⭐")
	card.is_star_card   = _parse_yes_no(row.get("Star Card", row.get("Star card", "No")))
	card.trigger_type   = _parse_trigger(row.get("Type", ""))

func _parse_trigger(s: String) -> CardData.TriggerType:
	match s.strip_edges().to_lower():
		"place": return CardData.TriggerType.PLACE
		"score": return CardData.TriggerType.SCORE
	return CardData.TriggerType.ALWAYS

func _parse_yes_no(s: String) -> bool:
	return s.strip_edges().to_lower() == "yes"

func _valid_id(value: String) -> bool:
	return value.strip_edges().is_valid_int()

func _parse_color_list(s: String) -> Array[int]:
	var result: Array[int] = []
	for part: String in s.split(","):
		var p: String = part.strip_edges().to_lower()
		if p == "any":
			result.append(CardData.OPTIMIZE_ANY)
		elif _is_valid_color(p):
			result.append(int(_parse_color(p)))
	return result

func _is_valid_color(s: String) -> bool:
	match s:
		"dust", "metals", "liquids", "organix", "electrix", "thrust", "thrrust":
			return true
	return false

func _parse_color(color_str: String) -> CardData.SupplyColor:
	match color_str.strip_edges().to_lower():
		"dust":    return CardData.SupplyColor.DUST
		"metals":  return CardData.SupplyColor.METALS
		"liquids": return CardData.SupplyColor.LIQUIDS
		"organix": return CardData.SupplyColor.ORGANIX
		"electrix": return CardData.SupplyColor.ELECTRIX
		"thrust", "thrrust": return CardData.SupplyColor.THRUST
	return CardData.SupplyColor.DUST

func _read_csv(path: String) -> Array[Dictionary]:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("CardDatabase: could not open " + path)
		return []
	var content := file.get_as_text()
	file.close()

	var rows := _parse_csv(content)
	if rows.size() < 2:
		return []

	var headers: Array = rows[0]
	var result: Array[Dictionary] = []
	for i in range(1, rows.size()):
		var fields: Array = rows[i]
		if fields.all(func(f): return (f as String).is_empty()):
			continue
		var row: Dictionary = {}
		for j in headers.size():
			row[headers[j]] = fields[j] if j < fields.size() else ""
		result.append(row)
	return result

func _parse_csv(content: String) -> Array:
	var rows := []
	var current_row := []
	var current_field := ""
	var in_quotes := false
	var i := 0

	while i < content.length():
		var c := content[i]
		if c == '"':
			if in_quotes and i + 1 < content.length() and content[i + 1] == '"':
				current_field += '"'
				i += 2
				continue
			in_quotes = !in_quotes
		elif c == ',' and not in_quotes:
			current_row.append(current_field)
			current_field = ""
		elif c == '\r' and not in_quotes:
			if i + 1 < content.length() and content[i + 1] == '\n':
				i += 1
			current_row.append(current_field)
			current_field = ""
			rows.append(current_row)
			current_row = []
		elif c == '\n' and not in_quotes:
			current_row.append(current_field)
			current_field = ""
			rows.append(current_row)
			current_row = []
		else:
			current_field += c
		i += 1

	if not current_field.is_empty() or not current_row.is_empty():
		current_row.append(current_field)
		rows.append(current_row)

	return rows
