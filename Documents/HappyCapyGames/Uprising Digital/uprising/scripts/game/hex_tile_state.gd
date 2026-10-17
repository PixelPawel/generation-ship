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
