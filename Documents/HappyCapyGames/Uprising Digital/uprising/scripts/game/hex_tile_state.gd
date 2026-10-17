class_name HexTileState
extends RefCounted

## Per-hex mutable game state. Card TEXT/art is looked up by name from
## CardDatabase at render time - this only stores the name + whatever
## changes over the course of a game.

var hex_card_name: String = ""   # "" until explored (or always known for Capital/Home/SeaTower, which start face-up)
var role: String = "interior"    # "capital" | "home" | "sea_tower" | "interior"
var explored: bool = false
var owning_faction: String = ""  # for Home hexes, whose faction this is

var garrison_level: int = 0      # 0-3
var curse: bool = false
var skeleton_count: int = 0      # 0-2 (3rd auto-converts to a Horde - handled by NemesisAI in M4)

var haven_faction: String = ""   # "" = no Haven
var tower: bool = false
var wall: bool = false

## Orientation the exploring player chose (rulebook p22: "If there is
## impassable terrain, place the hex in any orientation you want"), in
## clockwise 60-degree steps 0-5. Renderers turn the tile mesh by it.
var rotation: int = 0
## Faction that may still re-orient this freshly explored hex - set by
## Explore, cleared when that player's turn ends.
var orientable_by: String = ""

## Impassable (mountain) edges printed on each Core hex's explored art,
## clockwise from the flat top edge: 0=N 1=NE 2=SE 3=S 4=SW 5=NW (the art's
## top edge lies toward world -z, see HexMath.CLOCKWISE_DIRS). Found by
## scanning every TTS hex PNG for the white jagged border just inside each
## edge (2026-10-17), then confirmed by eye on close-ups - snowy
## illustration near an edge (Taurel's top) is not a mountain border.
## Every other Core hex, Home hex and The Capital has none.
const IMPASSABLE_ART_EDGES: Dictionary = {
	"Golgardei": [1, 5],
	"Plains of Rhun": [0],
	"Frosthold Pass": [1, 5],
	"Imperial Slave Mines": [1, 2, 4, 5],
	"Tomb of the Elder Kings": [0, 1],
	"Raufrost": [0],
	"Taurel Caravan Passage": [2, 5],
	"Rigga": [1, 5],
	"Dunkelholm": [0, 2, 5],
	"Dawngaard": [2, 5],
	"Zeegaard": [0, 2, 4],
}


## World directions (indices into HexMath.CLOCKWISE_DIRS) blocked by this
## hex's impassable terrain. Unexplored hexes show no terrain; a Curse
## keeps impassable terrain (rulebook p49).
func impassable_dirs() -> Array[int]:
	var out: Array[int] = []
	if not explored:
		return out
	for e: Variant in (IMPASSABLE_ART_EDGES.get(hex_card_name, []) as Array):
		out.append((int(e) + rotation) % 6)
	return out

## faction name -> {unit name (PlayerboardTable.UnitEntry.name) -> count}.
## Per-type because combat needs each standee's own die color and role
## (Archer/Rider/Warrior). Rulebook p14: at most 5 player Units (of 1
## faction) per hex - MAX_UNITS. Go through the helpers below rather than
## poking the nested dicts directly.
var units: Dictionary = {}

const MAX_UNITS: int = 5


func unit_count(faction: String) -> int:
	var total: int = 0
	for v: Variant in (units.get(faction, {}) as Dictionary).values():
		total += int(v)
	return total


func total_player_units() -> int:
	var total: int = 0
	for f: Variant in units.keys():
		total += unit_count(str(f))
	return total


## The player faction with Units here, "" if none (factions never share a hex).
func player_faction_here() -> String:
	for f: Variant in units.keys():
		if unit_count(str(f)) > 0:
			return str(f)
	return ""


## Copy of {unit name -> count} for `faction`, empty entries dropped.
func unit_stack(faction: String) -> Dictionary:
	var out: Dictionary = {}
	var stack: Dictionary = units.get(faction, {})
	for k: Variant in stack.keys():
		if int(stack[k]) > 0:
			out[str(k)] = int(stack[k])
	return out


## Adds up to `n` Units, capped at MAX_UNITS for the faction. Returns how
## many were actually added.
func add_units(faction: String, unit_name: String, n: int = 1) -> int:
	var room: int = MAX_UNITS - unit_count(faction)
	var adding: int = mini(n, room)
	if adding <= 0 or unit_name.is_empty():
		return 0
	if not units.has(faction):
		units[faction] = {}
	var stack: Dictionary = units[faction]
	stack[unit_name] = int(stack.get(unit_name, 0)) + adding
	return adding


func remove_unit(faction: String, unit_name: String, n: int = 1) -> int:
	var stack: Dictionary = units.get(faction, {})
	var have: int = int(stack.get(unit_name, 0))
	var removing: int = mini(n, have)
	if removing <= 0:
		return 0
	if have - removing <= 0:
		stack.erase(unit_name)
	else:
		stack[unit_name] = have - removing
	if stack.is_empty():
		units.erase(faction)
	return removing


func to_dict() -> Dictionary:
	return {
		"hex_card_name": hex_card_name, "role": role, "explored": explored,
		"owning_faction": owning_faction, "garrison_level": garrison_level,
		"curse": curse, "skeleton_count": skeleton_count,
		"haven_faction": haven_faction, "tower": tower, "wall": wall,
		"rotation": rotation, "orientable_by": orientable_by,
		"units": units.duplicate(true),
	}


static func from_dict(d: Dictionary) -> HexTileState:
	var s := HexTileState.new()
	s.hex_card_name = d.get("hex_card_name", "")
	s.role = d.get("role", "interior")
	s.explored = d.get("explored", false)
	s.owning_faction = d.get("owning_faction", "")
	s.garrison_level = d.get("garrison_level", 0)
	s.curse = d.get("curse", false)
	s.skeleton_count = d.get("skeleton_count", 0)
	s.haven_faction = d.get("haven_faction", "")
	s.tower = d.get("tower", false)
	s.wall = d.get("wall", false)
	s.rotation = int(d.get("rotation", 0))
	s.orientable_by = str(d.get("orientable_by", ""))
	var units_in: Dictionary = d.get("units", {})
	for f: Variant in units_in.keys():
		var v: Variant = units_in[f]
		if v is Dictionary:
			for u: Variant in (v as Dictionary).keys():
				s.add_units(str(f), str(u), int(v[u]))
		else:
			# Pre-2026-10-17 saves stored a bare count per faction.
			s.add_units(str(f), PlayerboardTable.default_unit(str(f)), int(v))
	return s
