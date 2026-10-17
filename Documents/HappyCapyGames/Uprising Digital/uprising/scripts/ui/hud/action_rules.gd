extends RefCounted

## What the local player can do right now, for the HUD: the main actions
## with the reason one isn't possible, and the context options (building,
## Feat picks, turning a hex, usable cards, ending a turn or phase) that only
## appear when they apply. Mirrors GameActions' checks - the host still has
## the final say. No class_name - preload it.

const CardAbilities := preload("res://scripts/game/card_abilities.gd")

## In player-board order.
const MAIN_ACTIONS: Array[String] = ["command", "move", "explore", "haven", "trade", "market", "quest"]
const PHASE_NAMES: Array[String] = ["Refresh", "Events", "Build", "Actions", "Nemesis", "Production", "Scoring"]
## Cards with an ability you trigger yourself (CardAbilities.use_card).
const USABLE_CARDS: Array[String] = [
	"Darkstrider Boots", "Dragonfruits", "Drakh Architect", "Druid's Ale", "Imperial Defectors", "Leeching Orb",
	"Mohyar Pirate", "Orb of Storms", "Ptetee", "Twilight Bow", "Druwhn Witcher", "Dawngaard Lantern",
	"Assassins Dagger", "Survivors", "Swordsisters", "Teleport", "Call to Arms", "Bonefires", "Gravedigger",
	"Imperial Connections", "Wiles", "Deathsworn",
]
## Usable cards that act on the selected hex (as action["to"] or ["at"]).
const TARGETED_CARDS: Dictionary = {"Teleport": "to", "Ptetee": "to", "Deathsworn": "at"}
## Usable cards with a stronger "discard this instead" use.
const DISCARD_OPTION: Array[String] = ["Twilight Bow", "Call to Arms"]


static func my_turn(state: GameState, p: PlayerFactionState) -> bool:
	return p != null and GameActions.is_players_turn(state, p.faction)


## "" when the main `action` can be taken now, else a short reason. With
## `ally` (True Solo) the allied Hero is the one acting.
static func main_reason(state: GameState, card_db: Node, p: PlayerFactionState, action: String, target: Vector2i, has_target: bool, ally: bool = false) -> String:
	if p == null:
		return "You're watching this game."
	var swap: bool = ally and p.has_ally()
	if swap:
		p.swap_heroes()
	var reason: String = _main_reason(state, card_db, p, action, target, has_target)
	if swap:
		p.swap_heroes()
	return reason


static func _main_reason(state: GameState, card_db: Node, p: PlayerFactionState, action: String, target: Vector2i, has_target: bool) -> String:
	if action == "trade":
		return "" if p.action_points >= 1 else "No AP left."
	if state.phase != GameState.Phase.ACTIONS:
		return "Actions open in the Actions phase."
	if not my_turn(state, p):
		return "Wait for your turn."
	var free: bool = p.wiles_ready  # Wiles: the next Command, Haven or Move is free
	match action:
		"move":
			if p.action_points < 1 and not free:
				return "No AP left."
			if not has_target or not state.hexes.has(target):
				return "Select a hex to move to."
			if target == p.hero_coord:
				return "Your Hero is already there."
			var here: HexTileState = state.get_hex(p.hero_coord)
			var anywhere: bool = (here != null and here.role == "sea_tower" and here.explored) or CardAbilities.hero_adjacent_everywhere(p)
			if HexMath.distance(p.hero_coord, target) != 1 and not anywhere:
				return "Only to a hex next to your Hero."
			return ""
		"explore":
			if p.has_acted_this_turn:
				return "You've taken your Action this turn."
			if p.action_points < 1:
				return "No AP left."
			var tile: HexTileState = state.get_hex(p.hero_coord)
			if tile == null or tile.explored:
				return "Your Hero's hex is explored."
			if tile.curse:
				return "A Cursed hex can't be explored."
			return ""
		"haven":
			return _haven_reason(state, p, free)
		"command":
			return _command_reason(state, p, target, has_target, free)
		"market":
			if p.has_acted_this_turn:
				return "You've taken your Action this turn."
			if p.action_points < 1:
				return "No AP left."
			if state.item_market.is_empty():
				return "The Market is empty."
			for item: String in state.item_market:
				if market_reason(state, card_db, p, item).is_empty():
					return ""
			return "You can't afford or use any Item."
		"quest":
			if p.has_acted_this_turn:
				return "You've taken your Action this turn."
			if p.action_points < 1:
				return "No AP left."
			if state.quest_row.is_empty():
				return "No Quests are face up."
			return ""
	return ""


static func haven_cost(p: PlayerFactionState) -> int:
	var board: PlayerboardTable.FactionBoard = PlayerboardTable.get_board(p.faction)
	return board.haven_plunder_cost if board != null else 2


static func _haven_reason(state: GameState, p: PlayerFactionState, free: bool) -> String:
	if p.has_acted_this_turn:
		return "You've taken your Action this turn."
	if not free and (p.action_points < 1 or p.plunder < haven_cost(p)):
		return "Needs 1 AP and %d Plunder." % haven_cost(p)
	var tile: HexTileState = state.get_hex(p.hero_coord)
	if tile == null or not tile.explored:
		return "Explore your Hero's hex first."
	if tile.curse:
		return "No Havens on a Cursed hex."
	if not tile.haven_faction.is_empty():
		return "There's a Haven here already."
	if tile.role == "outer" or tile.role == "capital":
		return "No Havens on a hex with an X."
	if tile.total_player_units() > tile.unit_count(p.faction) or tile.garrison_level > 0 or tile.skeleton_count > 0 or not EffectUtil.nemesis_at(state, p.hero_coord).is_empty():
		return "Enemies are on this hex."
	var havens: int = 0
	for t: HexTileState in state.hexes.values():
		if t.haven_faction == p.faction:
			havens += 1
	if havens >= GameActions.MAX_HAVENS:
		return "All %d Havens are on the map." % GameActions.MAX_HAVENS
	return ""


static func _command_reason(state: GameState, p: PlayerFactionState, target: Vector2i, has_target: bool, free: bool) -> String:
	if p.has_acted_this_turn:
		return "You've taken your Action this turn."
	var food: int = CardAbilities.command_food_cost(p)
	if not free and (p.action_points < 1 or p.food < food):
		return "Needs 1 AP and %d Food." % food
	if not has_target:
		return "Select the hex to Command into."
	var tile: HexTileState = state.get_hex(target)
	if tile == null or not (tile.explored or tile.role == "outer"):
		return "That hex is unexplored."
	var other: String = tile.player_faction_here()
	if (not other.is_empty() and other != p.faction) or (not tile.haven_faction.is_empty() and tile.haven_faction != p.faction):
		return "Another faction holds that hex."
	for from: Vector2i in state.hexes.keys():
		if from != target and (state.hexes[from] as HexTileState).unit_count(p.faction) > 0 and GameActions.can_command_from(state, from, target):
			return ""
	return "None of your Units can reach that hex."


## "" when the local player can buy `item` from the Market now.
static func market_reason(state: GameState, card_db: Node, p: PlayerFactionState, item: String) -> String:
	if state.flipped_market.has(item):
		return "The Spymaster keeps this one face down."
	if not GameActions.hero_can_use_item(card_db, p, item):
		return "Your Hero's attributes are too low."
	if p.salt < market_cost(state, card_db, p, item):
		return "Not enough Salt."
	return ""


static func market_cost(state: GameState, card_db: Node, p: PlayerFactionState, item: String) -> int:
	var cost: int = GameActions.item_cost(card_db, item) - CardAbilities.item_discount(p)
	var here: HexTileState = state.get_hex(p.hero_coord)
	if here != null and here.role == "sea_tower" and here.explored:
		cost -= 1
	return maxi(0, cost)


# --- Context options ---------------------------------------------------------

## Building is open: the Build Phase (until you're done), right after an
## Asheforge Haven on that hex, or while Survivors is in effect.
static func build_open(state: GameState, p: PlayerFactionState, coord: Vector2i) -> bool:
	if p == null:
		return false
	if state.phase == GameState.Phase.BUILD:
		return not p.has_passed
	if state.phase != GameState.Phase.ACTIONS:
		return false
	return state.open_build_until_turn_end or p.asheforge_coord != Vector2i.MIN or GameActions._build_window_open(state, p, coord)


## Where building would happen, or why it can't: your own Haven, or with
## no Havens at all any explored empty hex (your Hero goes there).
static func build_site_reason(state: GameState, p: PlayerFactionState, coord: Vector2i, has_coord: bool) -> String:
	if not has_coord:
		return "Select one of your Havens."
	var tile: HexTileState = state.get_hex(coord)
	if tile == null:
		return "Select one of your Havens."
	var asheforge_only: bool = state.phase == GameState.Phase.ACTIONS and not state.open_build_until_turn_end
	if asheforge_only and coord != p.asheforge_coord:
		return "Asheforge: build on the Haven you just placed."
	if tile.haven_faction == p.faction:
		return ""
	if GameActions._homeless_build_ok(state, p, coord):
		return ""
	return "Build on one of your Havens."


static func unit_reason(state: GameState, p: PlayerFactionState, coord: Vector2i, unit: PlayerboardTable.UnitEntry) -> String:
	var tile: HexTileState = state.get_hex(coord)
	if tile != null and tile.unit_count(p.faction) >= HexTileState.MAX_UNITS:
		return "5 Units is the most a hex holds."
	if NemesisAI.NemesisCards.reserve_left(state, p, unit.name) <= 0:
		return "None left in your reserve."
	if not can_pay(p, unit.cost):
		return "Not enough resources."
	return ""


static func can_pay(p: PlayerFactionState, cost: Dictionary) -> bool:
	match str(cost.get("type", "fixed")):
		"or":
			return p.salt >= int(cost.get("Salt", 0)) or p.plunder >= int(cost.get("Plunder", 0))
		"any":
			return p.salt + p.plunder + p.food >= int(cost.get("amount", 0))
	return p.salt >= int(cost.get("Salt", 0)) and p.plunder >= int(cost.get("Plunder", 0)) and p.food >= int(cost.get("Food", 0))


## How to pay a unit's flexible cost: the resource you have most of first.
static func payment_for(p: PlayerFactionState, cost: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	match str(cost.get("type", "fixed")):
		"or":
			out["or_choice"] = "Salt" if p.salt >= int(cost.get("Salt", 0)) else "Plunder"
		"any":
			var need: int = int(cost.get("amount", 0))
			var have: Dictionary = {"Salt": p.salt, "Plunder": p.plunder, "Food": p.food}
			var alloc: Dictionary = {"Salt": 0, "Plunder": 0, "Food": 0}
			for _i: int in range(need):
				var best: String = "Salt"
				for res: String in ["Plunder", "Food"]:
					if int(have[res]) > int(have[best]):
						best = res
				have[best] = int(have[best]) - 1
				alloc[best] = int(alloc[best]) + 1
			out["any_allocation"] = alloc
	return out


static func defense_reason(state: GameState, p: PlayerFactionState, coord: Vector2i, kind: String) -> String:
	var tile: HexTileState = state.get_hex(coord)
	if tile == null or tile.haven_faction != p.faction:
		return "Towers and Walls go on your Havens."
	if (kind == "Tower" and tile.tower) or (kind == "Wall" and tile.wall):
		return "This Haven has one already."
	if p.plunder < 1:
		return "Needs 1 Plunder."
	return ""


## Hexes the local player explored this turn and may still turn.
static func orientable(state: GameState, p: PlayerFactionState) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if p == null:
		return out
	for coord: Vector2i in state.hexes.keys():
		if (state.hexes[coord] as HexTileState).orientable_by == p.faction:
			out.append(coord)
	return out


## Cards in play with an ability to trigger now (not flipped).
static func usable_cards(state: GameState, p: PlayerFactionState) -> Array[String]:
	var out: Array[String] = []
	if p == null:
		return out
	var cards: Array[String] = p.feats_in_play.duplicate()
	cards.append_array(p.items_in_hand)
	for card: String in cards:
		if USABLE_CARDS.has(card) and CardAbilities.active(p, card) and not out.has(card):
			out.append(card)
	return out


## What ends the turn or moves the game on, for the button at the right of
## the faction bar: {"primary": [label, action type], "secondary": [...],
## "note": String}. An empty action type is the local "see the outcome".
static func flow(state: GameState, p: PlayerFactionState) -> Dictionary:
	var out: Dictionary = {"primary": [], "secondary": [], "note": ""}
	var next_name: String = PHASE_NAMES[(int(state.phase) + 1) % PHASE_NAMES.size()]
	match state.phase:
		GameState.Phase.BUILD:
			if p != null and not p.has_passed:
				out["primary"] = ["Done building", "pass"]
			elif GameActions.active_players(state).is_empty():
				out["primary"] = ["On to the %s phase" % next_name, "end_phase"]
			else:
				out["note"] = "Waiting for the others to finish building."
		GameState.Phase.ACTIONS:
			if GameActions.active_players(state).is_empty():
				out["primary"] = ["On to the %s phase" % next_name, "end_phase"]
			elif my_turn(state, p):
				out["primary"] = ["End turn", "end_turn"]
				out["secondary"] = ["Pass", "pass"]
			else:
				var current: PlayerFactionState = state.players[state.current_player_index % state.players.size()]
				out["note"] = "%s is taking their turn." % current.faction
		GameState.Phase.SCORING:
			if state.chapter >= state.max_chapters:
				out["primary"] = ["See how it ended", ""]
			else:
				out["primary"] = ["On to Chapter %d" % (state.chapter + 1), "end_phase"]
		_:
			out["primary"] = ["On to the %s phase" % next_name, "end_phase"]
	return out
