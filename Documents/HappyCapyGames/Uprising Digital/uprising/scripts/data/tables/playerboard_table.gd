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
## Die colors (2026-10-17) read off the same 4 board images, the die
## printed beside each standee: every Basic Archer is white, Basic
## Warriors are yellow except Duerkhar Younglings (blue), Elites vary.
## Archers roll in Archery AND Clash, Riders also roll in Archery on
## Badlands, Warriors only in Clash (rulebook p36, p42).
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
	var die: String       # combat die color printed next to the standee art

	func is_archer() -> bool:
		return role.ends_with("Archer")

	func is_rider() -> bool:
		return role.ends_with("Rider")

	func is_basic() -> bool:
		return role.begins_with("Basic")

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


static func get_unit(faction: String, unit_name: String) -> UnitEntry:
	var board: FactionBoard = get_board(faction)
	if board == null:
		return null
	for u: UnitEntry in board.units:
		if u.name == unit_name:
			return u
	return null


## The faction's Basic Warrior - what "Gain 1 Basic Unit" effects place
## when no specific type was chosen, and what legacy int-count saves map to.
static func default_unit(faction: String) -> String:
	var board: FactionBoard = get_board(faction)
	if board == null or board.units.is_empty():
		return ""
	return board.units[0].name


static func _unit(name: String, reserve: int, role: String, cost: Dictionary, die: String) -> UnitEntry:
	var u := UnitEntry.new()
	u.name = name
	u.reserve_size = reserve
	u.role = role
	u.cost = cost
	u.die = die
	return u


static var _BOARDS: Dictionary = _build()

static func _build() -> Dictionary:
	var d: Dictionary = {}

	var druwhn := FactionBoard.new()
	druwhn.faction = "Druwhn"
	druwhn.units = [
		_unit("Swordsisters", 4, "Basic Warrior", {"type": "fixed", "Salt": 1, "Plunder": 1}, "yellow"),
		_unit("Sons of the Bow", 3, "Basic Archer", {"type": "fixed", "Salt": 3}, "white"),
		_unit("Beastmasters", 2, "Elite Rider", {"type": "fixed", "Salt": 2, "Food": 3}, "red"),
		_unit("Rangers", 2, "Elite Archer", {"type": "fixed", "Salt": 4, "Plunder": 2}, "purple"),
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
		_unit("Younglings", 5, "Basic Warrior", {"type": "or", "Salt": 2, "Plunder": 2}, "blue"),
		_unit("Spearsingers", 3, "Basic Archer", {"type": "or", "Salt": 2, "Plunder": 2}, "white"),
		_unit("Oathsworn", 3, "Elite Warrior", {"type": "fixed", "Salt": 2, "Plunder": 3}, "red"),
		_unit("Koloth", 1, "Elite Rider", {"type": "fixed", "Salt": 4, "Food": 3}, "black"),
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
		_unit("Tribesmen", 6, "Basic Warrior", {"type": "fixed", "Food": 1}, "yellow"),
		_unit("Deadeyes", 3, "Basic Archer", {"type": "fixed", "Salt": 2}, "white"),
		_unit("Vargs", 3, "Elite Rider", {"type": "fixed", "Salt": 3, "Food": 2}, "red"),
		_unit("Trolls", 1, "Elite Warrior", {"type": "fixed", "Salt": 2, "Food": 5}, "black"),
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
		_unit("Sellswords", 4, "Basic Warrior", {"type": "any", "amount": 2}, "yellow"),
		_unit("Hunters", 4, "Basic Archer", {"type": "any", "amount": 2}, "white"),
		_unit("Berserkers", 2, "Elite Warrior", {"type": "fixed", "Salt": 2, "Food": 3}, "purple"),
		_unit("Slavers", 2, "Elite Rider", {"type": "fixed", "Salt": 3, "Plunder": 2}, "red"),
	]
	mohyar.haven_plunder_cost = 2
	mohyar.production = [
		{"Salt": 0, "Plunder": 2, "Food": 1}, {"Salt": 2, "Plunder": 1, "Food": 1},
		{"Salt": 2, "Plunder": 2, "Food": 2}, {"Salt": 3, "Plunder": 2, "Food": 3},
		{"Salt": 3, "Plunder": 3, "Food": 3}, {"Salt": 3, "Plunder": 3, "Food": 3},
	]
	d["Mohyar"] = mohyar

	return d
