class_name FactionData
extends RefCounted
## Unit-cost and Production-by-Haven-count tables, transcribed from the Core
## box's 4 player-board front images (print artwork, no digitized source --
## same class of gap DiceModel filled for dice faces):
## assets/images/Uprising+Final+EN/CORE_BOX_EN/PLAYERBOARDS_EN/
## Playerboards_Core_{Druwhn,Duerkhar,Krowh,Mohyar}_Front.jpg
##
## Unlocks GameActions.build_unit/build_defense (rulebook p17) and the base
## (non-terrain-bonus) part of ChapterFlow.production_phase_haven_bonus
## (rulebook p29).

## faction -> Array of 4 purchasable Unit defs:
##   name: printed Unit name
##   count: total copies in the faction's reserve (a hard supply cap, not a
##     per-purchase limit -- see GameActions._reserve_remaining)
##   type: "Basic Warrior" / "Basic Archer" / "Elite Warrior" / "Elite Rider"
##   cost_options: Array of alternative cost Dictionaries (usually 1; "OR"
##     costs like Duerkhar's have 2). A cost Dictionary has salt/plunder/food
##     int keys, OR a single "any" int key meaning "this many resource
##     points, any mix of salt/plunder/food, player's choice" (Mohyar only).
const UNITS := {
	"Druwhn": [
		{"name": "Swordsisters", "count": 4, "type": "Basic Warrior", "cost_options": [{"salt": 1, "plunder": 1}]},
		{"name": "Sons of the Bow", "count": 3, "type": "Basic Archer", "cost_options": [{"salt": 3}]},
		{"name": "Beastmasters", "count": 2, "type": "Elite Rider", "cost_options": [{"salt": 2, "food": 3}]},
		{"name": "Rangers", "count": 2, "type": "Elite Archer", "cost_options": [{"salt": 4, "plunder": 2}]},
	],
	"Duerkhar": [
		{"name": "Younglings", "count": 5, "type": "Basic Warrior", "cost_options": [{"salt": 2}, {"plunder": 2}]},
		{"name": "Spearsingers", "count": 3, "type": "Basic Archer", "cost_options": [{"salt": 2}, {"plunder": 2}]},
		{"name": "Oathsworn", "count": 3, "type": "Elite Warrior", "cost_options": [{"salt": 2, "plunder": 3}]},
		{"name": "Koloth", "count": 1, "type": "Elite Rider", "cost_options": [{"salt": 4, "food": 3}]},
	],
	"Krowh": [
		{"name": "Tribesmen", "count": 6, "type": "Basic Warrior", "cost_options": [{"food": 1}]},
		{"name": "Deadeyes", "count": 3, "type": "Basic Archer", "cost_options": [{"salt": 2}]},
		{"name": "Vargs", "count": 3, "type": "Elite Rider", "cost_options": [{"salt": 3, "food": 2}]},
		{"name": "Trolls", "count": 1, "type": "Elite Warrior", "cost_options": [{"salt": 2, "food": 5}]},
	],
	"Mohyar": [
		{"name": "Sellswords", "count": 4, "type": "Basic Warrior", "cost_options": [{"any": 2}]},
		{"name": "Hunters", "count": 4, "type": "Basic Archer", "cost_options": [{"any": 2}]},
		{"name": "Berserkers", "count": 2, "type": "Elite Warrior", "cost_options": [{"salt": 2, "food": 3}]},
		{"name": "Slavers", "count": 2, "type": "Elite Rider", "cost_options": [{"salt": 3, "plunder": 2}]},
	],
}

## Identical across all 4 Core factions (rulebook p42).
const TOWER_WALL_COST := {"plunder": 1}

## faction -> [row for 0 Havens, 1 Haven, ..., 5 Havens], each row [salt, plunder, food].
## Take the row for your CURRENT Haven count each Production Phase -- it's
## the total base production, not a per-Haven increment (rulebook p29: "look
## at the space on player board with the highest production that is
## uncovered"). All 4 factions share an identical 0-Haven baseline.
const PRODUCTION := {
	"Druwhn": [[0, 2, 1], [3, 0, 1], [3, 2, 1], [5, 2, 1], [5, 2, 2], [5, 2, 2]],
	"Duerkhar": [[0, 2, 1], [0, 3, 1], [1, 4, 1], [2, 5, 1], [2, 5, 2], [2, 5, 2]],
	"Krowh": [[0, 2, 1], [1, 0, 3], [1, 1, 4], [2, 1, 5], [2, 2, 5], [2, 2, 5]],
	"Mohyar": [[0, 2, 1], [2, 1, 1], [2, 2, 2], [3, 2, 3], [3, 3, 3], [3, 3, 3]],
}


## Returns {"salt": int, "plunder": int, "food": int} for `faction` at
## `haven_count` (clamped to the printed 0-5 range; a 6th+ Haven still
## produces the 5-Haven amount, per "highest production that is uncovered").
static func get_production(faction: String, haven_count: int) -> Dictionary:
	var table: Array = PRODUCTION.get(faction, [])
	if table.is_empty():
		return {"salt": 0, "plunder": 0, "food": 0}
	var idx: int = clampi(haven_count, 0, table.size() - 1)
	var row: Array = table[idx]
	return {"salt": row[0], "plunder": row[1], "food": row[2]}


static func get_units(faction: String) -> Array:
	return UNITS.get(faction, [])


static func find_unit(faction: String, unit_name: String) -> Dictionary:
	for u in get_units(faction):
		if u["name"] == unit_name:
			return u
	return {}
