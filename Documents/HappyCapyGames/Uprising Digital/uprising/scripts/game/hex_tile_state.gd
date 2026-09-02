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

## faction name -> unit count. Deliberately just a count per faction for
## now (not per-unit-type) - matches what Milestone 2's networking-shape
## goal actually needs; Milestone 4 can refine to per-unit-type stacks
## once GameActions/CombatResolver need that granularity.
var units: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"hex_card_name": hex_card_name, "role": role, "explored": explored,
		"owning_faction": owning_faction, "garrison_level": garrison_level,
		"curse": curse, "skeleton_count": skeleton_count,
		"haven_faction": haven_faction, "tower": tower, "wall": wall,
		"units": units.duplicate(),
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
	s.units = (d.get("units", {}) as Dictionary).duplicate()
	return s
