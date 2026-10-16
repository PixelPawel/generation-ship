extends RefCounted
# Generation Fleet (co-op expansion): the 18 Destinations and 30 Dangers.
# Preloaded where needed (const FleetData = preload(...)), no class_name.
#
# The cards' text lives in the art (all 6 languages) and in the sheet's
# Dangers/Destinations tabs; the game logic only needs what's below, keyed by
# the card's No. Art files follow the print export's page naming: page 1 has
# no number, page N >= 2 appends N.

const DESTINATION_ART_FOLDER: String = "Destiniations"   # the export's spelling
const DESTINATION_ART_BASE: String = "GS Destiniations 89x63,5mm"
const DANGER_ART_FOLDER: String = "Dangers"
const DANGER_ART_BASE: String = "GS Dangers 63,5x89mm"

const DIFFICULTY_NAMES: Array[String] = ["", "Easy", "Normal", "Hard"]
const DIFFICULTY_GENERATIONS: Array[int] = [0, 2, 3, 4]

# Mission parts. "per_player": the fleet's total must reach value x players;
# "each": every player must reach value on their own.
#   stars            total ⭐ (final score)
#   stored           stored supplies, any colour
#   stored_color     stored supplies of `color`
#   stored_set       stored supplies: 1 of each of the 6 colours (sets)
#   optimized        fully optimized sectors
#   complete         complete sectors (5 cards)
#   cards_color      cards of `color` on the ship
#   archived         archived cards
#   archived_stars   printed ⭐ on archived cards
#   faceup_stars     printed ⭐ on face-up cards (archived face up or placed)
const DESTINATIONS: Array[Dictionary] = [
	{"no": 1, "name": "Titan", "difficulty": 1, "shuttle": 1,
		"mission": [{"kind": "stars", "value": 5, "scope": "per_player"}]},
	{"no": 2, "name": "Mars", "difficulty": 1, "shuttle": 1,
		"mission": [{"kind": "stored", "value": 3, "scope": "per_player"}]},
	{"no": 3, "name": "Venus", "difficulty": 1, "shuttle": 1,
		"mission": [{"kind": "stars", "value": 5, "scope": "each"}]},
	{"no": 4, "name": "Europa", "difficulty": 1, "shuttle": 1,
		"mission": [{"kind": "optimized", "value": 2, "scope": "per_player"}]},
	{"no": 5, "name": "Jupiter", "difficulty": 1, "shuttle": 1,
		"mission": [{"kind": "cards_color", "color": CardData.SupplyColor.THRUST, "value": 1, "scope": "per_player"}]},
	{"no": 6, "name": "Luna", "difficulty": 1, "shuttle": 0,
		"mission": [{"kind": "complete", "value": 2, "scope": "each"}]},
	{"no": 7, "name": "Alpha Centauri", "difficulty": 2, "shuttle": 1,
		"mission": [{"kind": "stars", "value": 18, "scope": "per_player"}]},
	{"no": 8, "name": "Sirius", "difficulty": 2, "shuttle": 1,
		"mission": [{"kind": "stars", "value": 15, "scope": "each"}, {"kind": "stored", "value": 1, "scope": "each"}]},
	{"no": 9, "name": "Tau Ceti", "difficulty": 2, "shuttle": 1,
		"mission": [{"kind": "stars", "value": 15, "scope": "per_player"}, {"kind": "archived", "value": 3, "scope": "per_player"}]},
	{"no": 10, "name": "Epsilon Eridani", "difficulty": 2, "shuttle": 1,
		"mission": [{"kind": "stars", "value": 15, "scope": "each"}, {"kind": "cards_color", "color": CardData.SupplyColor.LIQUIDS, "value": 3, "scope": "each"}]},
	{"no": 11, "name": "Cygnus", "difficulty": 2, "shuttle": 1,
		"mission": [{"kind": "stars", "value": 15, "scope": "per_player"}, {"kind": "stored_color", "color": CardData.SupplyColor.THRUST, "value": 1, "scope": "per_player"}]},
	{"no": 12, "name": "Procyon", "difficulty": 2, "shuttle": 1,
		"mission": [{"kind": "faceup_stars", "value": 7, "scope": "per_player"}]},
	{"no": 13, "name": "Beta Hydri", "difficulty": 3, "shuttle": 2,
		"mission": [{"kind": "stars", "value": 30, "scope": "per_player"}, {"kind": "cards_color", "color": CardData.SupplyColor.ELECTRIX, "value": 4, "scope": "per_player"}]},
	{"no": 14, "name": "\"Las\" Vega", "difficulty": 3, "shuttle": 2,
		"mission": [{"kind": "stars", "value": 30, "scope": "per_player"}, {"kind": "archived_stars", "value": 5, "scope": "per_player"}]},
	{"no": 15, "name": "Pollux", "difficulty": 3, "shuttle": 2,
		"mission": [{"kind": "stars", "value": 30, "scope": "per_player"}, {"kind": "stored_color", "color": CardData.SupplyColor.LIQUIDS, "value": 3, "scope": "per_player"}]},
	{"no": 16, "name": "Arcturus", "difficulty": 3, "shuttle": 2,
		"mission": [{"kind": "stars", "value": 30, "scope": "each"}, {"kind": "optimized", "value": 4, "scope": "each"}]},
	{"no": 17, "name": "Gamma Serpentis", "difficulty": 3, "shuttle": 2,
		"mission": [{"kind": "stored_set", "value": 1, "scope": "per_player"}]},
	{"no": 18, "name": "Theta Persei", "difficulty": 3, "shuttle": 2,
		"mission": [{"kind": "stars", "value": 40, "scope": "per_player"}, {"kind": "stored_color", "color": CardData.SupplyColor.THRUST, "value": 3, "scope": "per_player"}]},
]

# "place": hits when revealed and again at the start of every generation until
# solved. "always": a lasting rule change until solved. Confirmed by the
# designer 2026-10-16.
const DANGERS: Array[Dictionary] = [
	{"no": 1, "name": "Asteroid Belt", "type": "always"},
	{"no": 2, "name": "High Speed Impacts", "type": "place"},
	{"no": 3, "name": "Hull Breach", "type": "place"},
	{"no": 4, "name": "Mining Incident", "type": "always"},
	{"no": 5, "name": "Accelerated Rusting", "type": "place"},
	{"no": 6, "name": "Smelter Accident", "type": "always"},
	{"no": 7, "name": "Engine Overload", "type": "place"},
	{"no": 8, "name": "Totalitarianism", "type": "always"},
	{"no": 9, "name": "Anti-Fusion Field", "type": "always"},
	{"no": 10, "name": "Algal Megabloom", "type": "place"},
	{"no": 11, "name": "Volatile Leak", "type": "always"},
	{"no": 12, "name": "Water Shortage", "type": "always"},
	{"no": 13, "name": "Oxygen Eating Supercolony", "type": "place"},
	{"no": 14, "name": "Pandemic", "type": "always"},
	{"no": 15, "name": "Mutations", "type": "place"},
	{"no": 16, "name": "Infestation", "type": "always"},
	{"no": 17, "name": "Plant Virus", "type": "always"},
	{"no": 18, "name": "Alien Pathogen", "type": "always"},
	{"no": 19, "name": "Gamma Ray Burst", "type": "place"},
	{"no": 20, "name": "Cybernetic Psycho", "type": "place"},
	{"no": 21, "name": "Neural Gear Malfunction", "type": "always"},
	{"no": 22, "name": "System Failure", "type": "place"},
	{"no": 23, "name": "Robot Uprising", "type": "always"},
	{"no": 24, "name": "Nanite Plague", "type": "always"},
	{"no": 25, "name": "Undetected Wormhole", "type": "place"},
	{"no": 26, "name": "Sabotage", "type": "place"},
	{"no": 27, "name": "Rogue AI", "type": "always"},
	{"no": 28, "name": "Barbarism", "type": "always"},
	{"no": 29, "name": "Dimension Pocket", "type": "place"},
	{"no": 30, "name": "Unstable Wormhole", "type": "place"},
]

const DANGERS_PER_GENERATION: int = 3

static func destination(no: int) -> Dictionary:
	for d: Dictionary in DESTINATIONS:
		if int(d["no"]) == no:
			return d
	return {}

static func danger(no: int) -> Dictionary:
	for d: Dictionary in DANGERS:
		if int(d["no"]) == no:
			return d
	return {}

static func generations(destination_no: int) -> int:
	return DIFFICULTY_GENERATIONS[int(destination(destination_no).get("difficulty", 3))]

static func _paged(base: String, no: int) -> String:
	return base + (".png" if no <= 1 else "%d.png" % no)

# Card art in the current language (EN fallback), "" if missing.
static func destination_art(no: int) -> String:
	return CardDatabase._art_path(DESTINATION_ART_FOLDER, _paged(DESTINATION_ART_BASE, no))

static func danger_art(no: int) -> String:
	return CardDatabase._art_path(DANGER_ART_FOLDER, _paged(DANGER_ART_BASE, no))

static func danger_back_art() -> String:
	return CardDatabase._art_path(DANGER_ART_FOLDER, "GS Dangers Back 63,5x89mm.png")

static func destination_back_art() -> String:
	return CardDatabase._art_path(DESTINATION_ART_FOLDER, "GS Destiniations Back 89x63,5mm.png")

# — Cards on the cockpit screens —
# The print art (750 px wide) shrunk ~3.5x on a screen without mipmaps comes out
# blurry and aliased, so the screens get a copy pre-shrunk once with Lanczos to
# the exact pixel size shown. Cached per path and size.
static var _screen_tex_cache: Dictionary = {}

static func screen_texture(path: String, box: Vector2) -> Texture2D:
	if path.is_empty():
		return null
	var key: String = "%s@%dx%d" % [path, int(box.x), int(box.y)]
	if _screen_tex_cache.has(key):
		return _screen_tex_cache[key]
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null or img.is_compressed():
		return tex
	var scale: float = minf(box.x / float(img.get_width()), box.y / float(img.get_height()))
	if scale < 1.0:
		img = img.duplicate() as Image
		img.resize(maxi(1, roundi(img.get_width() * scale)), maxi(1, roundi(img.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	var out: Texture2D = ImageTexture.create_from_image(img)
	_screen_tex_cache[key] = out
	return out

## The card shader settings that keep card text readable under the screen glow.
static func screen_card_material() -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://shaders/card_rounded.gdshader")
	mat.set_shader_parameter("brightness", 0.82)
	mat.set_shader_parameter("contrast", 1.25)
	mat.set_shader_parameter("saturation", 1.2)
	return mat

static func shuffled_destinations(rng: RandomNumberGenerator) -> Array[int]:
	var nos: Array[int] = []
	for d: Dictionary in DESTINATIONS:
		nos.append(int(d["no"]))
	for i: int in range(nos.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t: int = nos[i]
		nos[i] = nos[j]
		nos[j] = t
	return nos
