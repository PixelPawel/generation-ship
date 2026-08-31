class_name HexTile
extends RefCounted
## Mutable runtime state for one hex. `card_name` links back to the static
## reference data in CardDatabase.hexes (terrain, flavor, base resources);
## everything here is what changes during play.

var coord: Vector2i = Vector2i.ZERO
var card_name: String = ""
var explored: bool = false

## True if this hex can never gain a Haven (the X icon / The Capital / Ice Wastes).
var no_haven: bool = false
## True for Sea Tower hexes: adjacent to every other hex once explored.
var is_sea_tower: bool = false
## Which faction/side places a Unit here if it's Explored while empty ("Empire", "Chaos", or "").
var side: String = ""

var haven_faction: String = ""  # "" = no Haven; else a player faction name
var has_wall: bool = false
var has_tower: bool = false

var garrison_level: int = 0  # 0-3
var skeleton_count: int = 0  # 0-2; a 3rd converts to a Horde (handled by game logic, not stored here)
var has_curse: bool = false

var legion_id: int = -1  # index into GameState.legions, -1 = none present
var horde_id: int = -1

## faction name -> Array of unit-type ids present on this hex (player Units only)
var units: Dictionary = {}


static func is_empty(tile: HexTile) -> bool:
	if tile == null:
		return true
	return (
		tile.haven_faction == ""
		and tile.garrison_level == 0
		and tile.skeleton_count == 0
		and not tile.has_curse
		and tile.legion_id == -1
		and tile.horde_id == -1
		and tile.units.is_empty()
	)


func to_dict() -> Dictionary:
	return {
		"coord": [coord.x, coord.y],
		"card_name": card_name,
		"explored": explored,
		"no_haven": no_haven,
		"is_sea_tower": is_sea_tower,
		"side": side,
		"haven_faction": haven_faction,
		"has_wall": has_wall,
		"has_tower": has_tower,
		"garrison_level": garrison_level,
		"skeleton_count": skeleton_count,
		"has_curse": has_curse,
		"legion_id": legion_id,
		"horde_id": horde_id,
		"units": units.duplicate(true),
	}


static func from_dict(d: Dictionary) -> HexTile:
	var t := HexTile.new()
	var c: Array = d.get("coord", [0, 0])
	t.coord = Vector2i(c[0], c[1])
	t.card_name = d.get("card_name", "")
	t.explored = d.get("explored", false)
	t.no_haven = d.get("no_haven", false)
	t.is_sea_tower = d.get("is_sea_tower", false)
	t.side = d.get("side", "")
	t.haven_faction = d.get("haven_faction", "")
	t.has_wall = d.get("has_wall", false)
	t.has_tower = d.get("has_tower", false)
	t.garrison_level = d.get("garrison_level", 0)
	t.skeleton_count = d.get("skeleton_count", 0)
	t.has_curse = d.get("has_curse", false)
	t.legion_id = d.get("legion_id", -1)
	t.horde_id = d.get("horde_id", -1)
	t.units = (d.get("units", {}) as Dictionary).duplicate(true)
	return t
