extends Node

var sectors: Array[CardData] = []
var techs: Array[CardData] = []
var expeditions: Array[CardData] = []

# Print-export card art lives under res://assets/cards/<Deck>/<LANG>/, one
# PNG per physical card, exported page-by-page from the InDesign print files
# (page 1 has no number suffix, page N>=1 appends N — InDesign's own
# multi-page export naming, left as-is rather than renamed). Locale is read
# directly from the same settings.cfg pause_menu.gd writes to, rather than
# trusting TranslationServer.get_locale(): CardDatabase is an autoload and
# runs before any scene (including the pause menu, the only thing that ever
# calls TranslationServer.set_locale()) has had a chance to apply it.
const _SETTINGS_PATH: String = "user://settings.cfg"
const _LANGUAGE_CODES: Array[String] = ["en", "de", "it", "pl", "es", "fr"]

# Advanced Sectors: each of the 3 unique cards per color is printed twice
# (2 physical copies -> 2 CSV rows, same name, same art); only one physical
# location per unique name is needed here since art is looked up by name.
# normalized name -> [png file base, page number]
const _ADV_SECTOR_ART: Dictionary = {
	"centraltransport": ["GS Sector 1 67x44mm", 1],
	"spacebazaar":       ["GS Sector 1 67x44mm", 2],
	"exosampling":       ["GS Sector 1 67x44mm", 3],
	"holoprinters":      ["GS Sector 1 67x44mm", 4],
	"astrogation":       ["GS Sector 1 67x44mm", 5],
	"fabrication":       ["GS Sector 3 67x44mm", 1],
	"greenhouse":        ["GS Sector 3 67x44mm", 2],
	"parliament":        ["GS Sector 3 67x44mm", 3],
	"probelauncher":     ["GS Sector 3 67x44mm", 4],
	"astracultura":      ["GS Sector 3 67x44mm", 5],
	"preservation":      ["GS Sector 5 67x44mm", 1],
	"academies":         ["GS Sector 5 67x44mm", 2],
	"cultivation":       ["GS Sector 5 67x44mm", 3],
	"engines":           ["GS Sector 5 67x44mm", 4],
	"centralai":         ["GS Sector 5 67x44mm", 5],
}
# Dust Sectors: 6 unique cards, one per "Sector N Back" file (single page).
const _DUST_SECTOR_ART: Dictionary = {
	"hibernators":     ["GS Sector 1 Back 67x44mm", 1],
	"simulators":      ["GS Sector 2 Back 67x44mm", 1],
	"bioreactor":      ["GS Sector 3 Back  67x44mm", 1],
	"habitationring":  ["GS Sector 4 Back  67x44mm", 1],
	"operations":      ["GS Sector 5 Back  67x44mm", 1],
	"cargobays":       ["GS Sector 6  Back  67x44mm", 1],
}

func _ready() -> void:
	_load_sector_cards()
	_load_techs()
	_load_expeditions()
	print("CardDatabase loaded: %d sectors, %d techs, %d expeditions" % [sectors.size(), techs.size(), expeditions.size()])

static func _normalize(s: String) -> String:
	var out: String = ""
	for ch: String in s:
		var code: int = ch.unicode_at(0)
		if (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
			out += ch.to_lower()
		elif code >= 48 and code <= 57:
			out += ch
	return out

func _current_lang() -> String:
	var cfg: ConfigFile = ConfigFile.new()
	var locale: String = "en"
	if cfg.load(_SETTINGS_PATH) == OK:
		locale = str(cfg.get_value("game", "locale", "en"))
	if not _LANGUAGE_CODES.has(locale):
		locale = "en"
	return locale.to_upper()

# Resolves to the current-locale PNG, falling back to EN if that language's
# art is somehow missing (all 6 languages were exported in full, so this is
# a safety net, not an expected path).
func _resolve_art(deck_folder: String, file_base: String, page: int) -> String:
	var fname: String = file_base + ("" if page == 1 else str(page)) + ".png"
	var lang: String = _current_lang()
	var path: String = "res://assets/cards/%s/%s/%s" % [deck_folder, lang, fname]
	if ResourceLoader.exists(path):
		return path
	if lang != "EN":
		var fallback: String = "res://assets/cards/%s/EN/%s" % [deck_folder, fname]
		if ResourceLoader.exists(fallback):
			return fallback
	return ""

func _tech_art_path(id: int) -> String:
	return _resolve_art("Tech", "GS Techs 44x67mm", id)

func _promo_art_path(promo_no: int) -> String:
	return _resolve_art("Promo", "GS Techs Promos 44x67mm", promo_no)

func _art_path_for_tech(cd: CardData) -> String:
	return _promo_art_path(cd.promo_no) if cd.promo_no > 0 else _tech_art_path(cd.id)

func _expedition_art_path(id: int) -> String:
	# The Expeditions deck prints in exact reverse order of CSV "No."
	# (page 1 = No. 26, page 26 = No. 1) — verified against every page,
	# not assumed from Techs' direct id==page pattern, which does NOT hold
	# here. See the equivalent Advanced/Dust Sector tables above for the
	# same reason: print page order isn't guaranteed to match CSV order.
	return _resolve_art("Expedition", "GS Expeditions 44x67mm", 27 - id)

func _adv_sector_art_path(card_name: String) -> String:
	var entry: Variant = _ADV_SECTOR_ART.get(_normalize(card_name))
	if entry == null:
		return ""
	return _resolve_art("Sector", entry[0], entry[1])

func _dust_sector_art_path(card_name: String) -> String:
	var entry: Variant = _DUST_SECTOR_ART.get(_normalize(card_name))
	if entry == null:
		return ""
	return _resolve_art("Sector", entry[0], entry[1])

# Generic deck-back art (the face-down "TECH"/"EXPEDITIONS" card design, not
# any single card) — same folder convention as per-card art, single page
# each. Callers that need a hardcoded path at parse time (a `const`) can't
# call an autoload function, so this is exposed for them to call once at
# runtime instead — see tech_deck_back_path()/expedition_deck_back_path()
# callers in board.gd, sector_slot.gd, sector_info_popup.gd.
func tech_back_path() -> String:
	return _resolve_art("Tech", "GS Techs Back 44x67mm", 1)

func expedition_back_path() -> String:
	return _resolve_art("Expedition", "GS Expeditions Back 44x67mm", 1)

# pause_menu.gd is the only place a user can change locale mid-session, and
# it happens long after _ready() already baked every card's local_art_path
# for whatever locale was persisted at boot — without this, art silently
# stays on the old language until the app is fully restarted (fresh
# _ready() call re-reading the now-updated settings.cfg). Call this from
# there, then ImageCache.refresh_local_art() and a live-card broadcast so
# already-instantiated Card nodes pick up the change too.
func refresh_locale() -> void:
	for cd: CardData in sectors:
		cd.local_art_path = _dust_sector_art_path(cd.card_name)
		cd.adv_local_art_path = _adv_sector_art_path(cd.adv_name)
	for cd: CardData in techs:
		cd.local_art_path = _art_path_for_tech(cd)
	for cd: CardData in expeditions:
		cd.local_art_path = _expedition_art_path(cd.id)

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
		card.local_art_path = _dust_sector_art_path(card.card_name)
		card.opt1_req = _parse_color_list(dust.get("Optimize 1", ""))

		# Advanced side
		card.adv_name = row.get("Name", "").strip_edges()
		card.adv_color = _parse_color(row.get("Color", ""))
		card.adv_cost = int(row.get("Cost", "0")) if row.get("Cost", "").is_valid_int() else 0
		card.adv_effect_text = row.get("Effect", "").strip_edges()
		card.adv_flavor_text = row.get("Flavor", "").strip_edges()
		card.adv_image_url = row.get("Link", "").strip_edges()
		card.adv_local_art_path = _adv_sector_art_path(card.adv_name)
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
	_load_promos()

# Promo Techs are always shuffled into the Tech deck. Appended after the
# regular techs so every client builds the same array order (CardRef syncs
# cards by index), with ids continuing past the highest regular tech id.
func _load_promos() -> void:
	var next_id: int = 0
	for cd: CardData in techs:
		next_id = maxi(next_id, cd.id)
	var rows := _read_csv("res://data/Generation Ship Full Card Details - Promos.csv")
	for row in rows:
		if not _valid_id(row.get("No.", "")):
			continue
		next_id += 1
		var card := CardData.new()
		card.id = next_id
		card.promo_no = int(row["No."])
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
	card.local_art_path = _art_path_for_tech(card) if card.card_type == CardData.CardType.TECH else _expedition_art_path(card.id)
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

# A disconnected human's sector/tech names are the only trace of their board
# left once their client is gone (see Main._convert_peer_to_bot) — these
# resolve those name strings back into real CardData for the takeover bot.
func find_sector_by_name(card_name: String, advanced: bool) -> CardData:
	for cd: CardData in sectors:
		if advanced and cd.adv_name == card_name:
			return cd
		elif not advanced and cd.card_name == card_name:
			return cd
	return null

# Tucked/stored cards can be any card type, and opponent snapshots only carry
# a name string (see Main._get_public_snapshot) — this resolves that name
# back into real CardData for display, searching every category.
func find_any_by_name(card_name: String) -> CardData:
	if card_name.is_empty():
		return null
	for cd: CardData in sectors:
		if cd.card_name == card_name or cd.adv_name == card_name:
			return cd
	for cd: CardData in techs:
		if cd.card_name == card_name:
			return cd
	for cd: CardData in expeditions:
		if cd.card_name == card_name:
			return cd
	return null

func get_all_image_urls() -> Array[String]:
	var urls: Array[String] = []
	for cd: CardData in sectors:
		if not cd.image_url.is_empty():
			urls.append(cd.image_url)
		if not cd.adv_image_url.is_empty():
			urls.append(cd.adv_image_url)
	for cd: CardData in techs:
		if not cd.image_url.is_empty():
			urls.append(cd.image_url)
	for cd: CardData in expeditions:
		if not cd.image_url.is_empty():
			urls.append(cd.image_url)
	return urls

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
	var content: String = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file:
		content = file.get_as_text()
		file.close()
	else:
		# CSV not in PCK — fall back to baked constants so exports work
		# without relying on export_presets.cfg include_filter
		match path.get_file():
			"Generation Ship Full Card Details - Advanced Sectors.csv":
				content = CardDataBaked.ADVANCED_SECTORS
			"Generation Ship Full Card Details - Dust Sectors.csv":
				content = CardDataBaked.DUST_SECTORS
			"Generation Ship Full Card Details - Techs.csv":
				content = CardDataBaked.TECHS
			"Generation Ship Full Card Details - Expeditions.csv":
				content = CardDataBaked.EXPEDITIONS
			"Generation Ship Full Card Details - Promos.csv":
				content = CardDataBaked.PROMOS
		if content.is_empty():
			push_error("CardDatabase: could not open " + path)
			return []

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
