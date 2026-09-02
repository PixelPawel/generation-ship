class_name PlayerboardTable
extends RefCounted

## Hand-transcribed from the 4 Core player board Front images
## (assets/images/Uprising+Final+EN/CORE_BOX_EN/PLAYERBOARDS_EN/
## Playerboards_Core_{Druwhn,Duerkhar,Krowh,Mohyar}_Front.jpg) - read
## directly, print art has no CSV equivalent for any of this. Icon
## mapping (deduced from cross-referencing against known rulebook facts,
## not guessed): the blue crystal icon = Salt, the red/pink brick-cluster
## icon = Plunder (confirmed: Tower/Wall show "1 [that icon]", matching
## the rulebook's explicit "1 Plunder each" for Wall/Tower), the green
## tusk icon = Food (matches Command's "1 [that icon]" against the
## rulebook's "1 AP + 1 Food" for Command).
##
## Unit cost dict shapes:
##  {"type":"fixed", "Salt":x, "Plunder":y, "Food":z}  - pay exactly these amounts (0 if absent)
##  {"type":"or", "Salt":x, "Plunder":y}                - pay x Salt OR y Plunder (Duerkhar's Basic units)
##  {"type":"any", "amount":n}                           - pay n resources, any mix (Mohyar's Basic units)

class UnitEntry:
	var name: String
	var reserve_size: int
	var role: String      # "Basic Warrior" | "Basic Archer" | "Elite Warrior" | "Elite Rider" | "Elite Archer"
	var cost: Dictionary

class FactionBoard:
	var faction: String
	var units: Array[UnitEntry] = []
	var tower_cost: Dictionary = {"type": "fixed", "Plunder": 1}
	var wall_cost: Dictionary = {"type": "fixed", "Plunder": 1}
	var haven_plunder_cost: int = 2   # Krowh is 3, per rulebook and confirmed on its own board.
	## index 0-5 = Haven count -> {"Salt":x,"Plunder":y,"Food":z} produced that Chapter.
	var production: Array[Dictionary] = []


static func get_board(faction: String) -> FactionBoard:
	return _BOARDS.get(faction)


static func _unit(name: String, reserve: int, role: String, cost: Dictionary) -> UnitEntry:
	var u := UnitEntry.new()
	u.name = name
	u.reserve_size = reserve
	u.role = role
	u.cost = cost
	return u


static var _BOARDS: Dictionary = _build()

static func _build() -> Dictionary:
	var d: Dictionary = {}

	var druwhn := FactionBoard.new()
	druwhn.faction = "Druwhn"
	druwhn.units = [
		_unit("Swordsisters", 4, "Basic Warrior", {"type": "fixed", "Salt": 1, "Plunder": 1}),
		_unit("Sons of the Bow", 3, "Basic Archer", {"type": "fixed", "Salt": 3}),
		_unit("Beastmasters", 2, "Elite Rider", {"type": "fixed", "Salt": 2, "Food": 3}),
		_unit("Rangers", 2, "Elite Archer", {"type": "fixed", "Salt": 4, "Plunder": 2}),
	]
	druwhn.haven_plunder_cost = 2
	druwhn.production = [
		{"Salt": 0, "Plunder": 2, "Food": 1}, {"Salt": 3, "Plunder": 0, "Food": 1},
		{"Salt": 3, "Plunder": 2, "Food": 1}, {"Salt": 5, "Plunder": 2, "Food": 1},
		{"Salt": 5, "Plunder": 2, "Food": 2}, {"Salt": 5, "Plunder": 2, "Food": 2},
	]
	d["Druwhn"] = druwhn

	var duerkhar := FactionBoard.new()
	duerkhar.faction = "Duerkhar"
	duerkhar.units = [
		_unit("Younglings", 5, "Basic Warrior", {"type": "or", "Salt": 2, "Plunder": 2}),
		_unit("Spearsingers", 3, "Basic Archer", {"type": "or", "Salt": 2, "Plunder": 2}),
		_unit("Oathsworn", 3, "Elite Warrior", {"type": "fixed", "Salt": 2, "Plunder": 3}),
		_unit("Koloth", 1, "Elite Rider", {"type": "fixed", "Salt": 4, "Food": 3}),
	]
	duerkhar.haven_plunder_cost = 2
	duerkhar.production = [
		{"Salt": 0, "Plunder": 2, "Food": 1}, {"Salt": 0, "Plunder": 3, "Food": 1},
		{"Salt": 1, "Plunder": 4, "Food": 1}, {"Salt": 2, "Plunder": 5, "Food": 1},
		{"Salt": 2, "Plunder": 5, "Food": 2}, {"Salt": 2, "Plunder": 5, "Food": 2},
	]
	d["Duerkhar"] = duerkhar

	var krowh := FactionBoard.new()
	krowh.faction = "Krowh"
	krowh.units = [
		_unit("Tribesmen", 6, "Basic Warrior", {"type": "fixed", "Food": 1}),
		_unit("Deadeyes", 3, "Basic Archer", {"type": "fixed", "Salt": 2}),
		_unit("Vargs", 3, "Elite Rider", {"type": "fixed", "Salt": 3, "Food": 2}),
		_unit("Trolls", 1, "Elite Warrior", {"type": "fixed", "Salt": 2, "Food": 5}),
	]
	krowh.haven_plunder_cost = 3  # Krowh-specific, per rulebook and confirmed on its own board.
	krowh.production = [
		{"Salt": 0, "Plunder": 2, "Food": 1}, {"Salt": 1, "Plunder": 0, "Food": 3},
		{"Salt": 1, "Plunder": 1, "Food": 4}, {"Salt": 2, "Plunder": 1, "Food": 5},
		{"Salt": 2, "Plunder": 2, "Food": 5}, {"Salt": 2, "Plunder": 2, "Food": 5},
	]
	d["Krowh"] = krowh

	var mohyar := FactionBoard.new()
	mohyar.faction = "Mohyar"
	mohyar.units = [
		_unit("Sellswords", 4, "Basic Warrior", {"type": "any", "amount": 2}),
		_unit("Hunters", 4, "Basic Archer", {"type": "any", "amount": 2}),
		_unit("Berserkers", 2, "Elite Warrior", {"type": "fixed", "Salt": 2, "Food": 3}),
		_unit("Slavers", 2, "Elite Rider", {"type": "fixed", "Salt": 3, "Plunder": 2}),
	]
	mohyar.haven_plunder_cost = 2
	mohyar.production = [
		{"Salt": 0, "Plunder": 2, "Food": 1}, {"Salt": 2, "Plunder": 1, "Food": 1},
		{"Salt": 2, "Plunder": 2, "Food": 2}, {"Salt": 3, "Plunder": 2, "Food": 3},
		{"Salt": 3, "Plunder": 3, "Food": 3}, {"Salt": 3, "Plunder": 3, "Food": 3},
	]
	d["Mohyar"] = mohyar

	return d
