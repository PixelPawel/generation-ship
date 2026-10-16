extends RefCounted
# Generation Fleet (co-op) game state and rule queries. One instance per Fleet
# game (FleetRules.current, set by Main); every rule check below is static and
# answers "no change" when no Fleet game is running, so the hooks in the
# supply/board/market code cost nothing in a normal game.
# Preloaded where needed (const FleetRules = preload(...)), no class_name.
#
# Rules (rulebook p. 9-10): 3 Dangers are revealed at the start of every
# generation, after drawing, and resolve one at a time, oldest first. Place:
# hits on reveal and again at the start of every generation until solved
# (nothing happens if it can't be paid). Always: a rule change until solved.
# Any Danger can be solved at any time as a free action by paying its cost.
# Solo: "per player" means x1, and "pass cards left" does nothing.
const FleetData = preload("res://scripts/game/fleet_data.gd")

static var current: RefCounted = null

# Meta on a placed card node a Danger "destroyed" (flipped face down): it stays
# in its slot (the sector keeps its card count) but has no colour, stars,
# income or effect any more.
const DESTROYED_META: String = "fleet_destroyed"

var destination: int = 0
var deck: Array[int] = []            # Danger No.s, top = back
var active: Array[Dictionary] = []   # revealed, unsolved, oldest first: {no, electrix, expedition_bought}
var solved: Array[int] = []
# Online every peer resolves the same Dangers in lockstep (same seed), so any
# randomness inside a Danger (Undetected Wormhole's shuffle-back) uses this.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

const C := CardData.SupplyColor

# — Danger effects —
# Place effects: what happens on reveal / each generation.
#   to_dust n            turn n supplies (not Dust) into Dust, 1:1
#   destroy n where pref  flip the top card of a sector face down; where:
#                        "rightmost"/"leftmost" sector, or "any" (player picks),
#                        pref = colour to pick if possible (-1 none)
#   choose a|b           player picks one option (an option that can't be paid
#                        can't be picked; if neither can, nothing happens)
#   pay color n          pay supplies
#   lose_stored n        remove stored supplies
#   lose_stored_or_archived n
#   discard n            discard cards from hand
#   market_adv n         discard advanced sectors from the market
#   system_failure       store 1 Electrix on this Danger, then reveal 1 Danger per Electrix on it
#   shuffle_expeditions  all revealed expeditions go back into the deck
#   remove_fewest_sector remove the sector with the fewest cards
#   pass_left            every player passes their hand to the left (nothing solo)
#   none                 nothing
const PLACE_EFFECTS: Dictionary = {
	2: {"kind": "to_dust", "n": 3},
	3: {"kind": "destroy", "n": 1, "where": "rightmost", "pref": -1},
	5: {"kind": "destroy", "n": 2, "where": "leftmost", "pref": -1},
	7: {"kind": "choose", "options": [{"kind": "pay", "color": C.METALS, "n": 2}, {"kind": "destroy", "n": 2, "where": "any", "pref": -1}]},
	10: {"kind": "choose", "options": [{"kind": "lose_stored", "n": 2}, {"kind": "discard", "n": 2}]},
	13: {"kind": "market_adv", "n": 3},
	15: {"kind": "destroy", "n": 1, "where": "any", "pref": C.ORGANIX},
	19: {"kind": "lose_stored_or_archived", "n": 2},
	20: {"kind": "destroy", "n": 1, "where": "any", "pref": C.ELECTRIX},
	22: {"kind": "system_failure"},
	25: {"kind": "shuffle_expeditions"},
	26: {"kind": "remove_fewest_sector"},
	29: {"kind": "pass_left"},
	30: {"kind": "discard", "n": 3},
}

# — Solving —
#   pay color n               pay supplies
#   discard_color colors n    discard n cards of these colours from hand
#   discard_stars n           discard cards worth n printed ⭐ in total
#   discard_each_color        discard 1 card of each of the 6 colours
#   destroy n                 flip the top card of one of your sectors face down
#   lose_archived n           remove archived cards
#   flip_archived n stars     flip a face-up archived card (with >= stars ⭐) face down
#   destroy_expedition        flip an expedition in a sector face down
#   (conditions: checked when Solve is pressed, nothing is paid)
#   complete_rightmost        your right-most sector is complete
#   optimized_color color     you have a fully optimized sector of that colour
#   cards_in_sector color n   n+ cards of that colour in one sector
#   dust_deck_empty           one of the 3 Dust sector decks is empty
#   complete_optimized        a sector that is both complete and fully optimized
#   complete_color colors     a complete sector of one of these colours
#   hand_empty                no cards in hand
#   expedition_bought         an expedition was bought since this Danger came up
const SOLVES: Dictionary = {
	1: {"kind": "pay", "per_player": true, "color": C.DUST, "n": 2},
	2: {"kind": "destroy", "per_player": true, "n": 1},
	3: {"kind": "complete_rightmost"},
	4: {"kind": "optimized_color", "color": C.DUST},
	5: {"kind": "optimized_color", "color": C.METALS},
	6: {"kind": "discard_color", "per_player": true, "colors": [C.METALS], "n": 1},
	7: {"kind": "pay", "per_player": true, "color": C.METALS, "n": 2},
	8: {"kind": "discard_stars", "per_player": true, "n": 2},
	9: {"kind": "optimized_color", "color": C.LIQUIDS},
	10: {"kind": "pay", "per_player": true, "color": C.LIQUIDS, "n": 2},
	11: {"kind": "discard_color", "per_player": true, "colors": [C.LIQUIDS], "n": 1},
	12: {"kind": "cards_in_sector", "color": C.LIQUIDS, "n": 3},
	13: {"kind": "dust_deck_empty"},
	14: {"kind": "discard_color", "per_player": true, "colors": [C.ORGANIX], "n": 1},
	15: {"kind": "lose_archived", "per_player": true, "n": 1},
	16: {"kind": "flip_archived", "per_player": true, "n": 1, "stars": 0},
	17: {"kind": "cards_in_sector", "color": C.ORGANIX, "n": 3},
	18: {"kind": "flip_archived", "n": 1, "stars": 3},
	19: {"kind": "complete_optimized"},
	20: {"kind": "dust_deck_empty"},
	21: {"kind": "discard_stars", "per_player": true, "n": 3},
	22: {"kind": "discard_color", "per_player": true, "colors": [C.ELECTRIX], "n": 1},
	23: {"kind": "pay", "per_player": true, "color": C.ELECTRIX, "n": 1},
	24: {"kind": "discard_stars", "per_player": true, "n": 3},
	25: {"kind": "expedition_bought"},
	26: {"kind": "destroy_expedition"},
	27: {"kind": "discard_color", "per_player": true, "colors": [C.ELECTRIX, C.THRUST], "n": 2},
	28: {"kind": "complete_color", "colors": [C.ELECTRIX, C.THRUST]},
	29: {"kind": "discard_each_color"},
	30: {"kind": "hand_empty"},
}

# "per_player" solves cost n x the number of players (rulebook: "per player");
# the crew can split it however they like.
static func solve_need(no: int, players: int) -> int:
	var sv: Dictionary = SOLVES.get(no, {})
	var n: int = int(sv.get("n", 1))
	if str(sv.get("kind", "")) == "discard_each_color":
		return 6
	return n * maxi(1, players) if bool(sv.get("per_player", false)) else n

const CONDITION_SOLVES: Array[String] = ["complete_rightmost", "optimized_color", "cards_in_sector",
		"dust_deck_empty", "complete_optimized", "complete_color", "hand_empty", "expedition_bought"]

# — Game state —

func setup(destination_no: int, deck_rng: RandomNumberGenerator) -> void:
	destination = destination_no
	rng.seed = deck_rng.seed + 1
	deck.clear()
	for d: Dictionary in FleetData.DANGERS:
		deck.append(int(d["no"]))
	for i: int in range(deck.size() - 1, 0, -1):
		var j: int = deck_rng.randi_range(0, i)
		var t: int = deck[i]
		deck[i] = deck[j]
		deck[j] = t
	active.clear()
	solved.clear()

# Reveals up to n Dangers (fewer if the deck runs out); returns their No.s.
func reveal(n: int) -> Array[int]:
	var out: Array[int] = []
	for i: int in n:
		if deck.is_empty():
			break
		var no: int = deck.pop_back()
		active.append({"no": no, "electrix": 0, "expedition_bought": false})
		out.append(no)
	return out

func entry(no: int) -> Dictionary:
	for e: Dictionary in active:
		if int(e["no"]) == no:
			return e
	return {}

func solve(no: int) -> void:
	for i: int in active.size():
		if int(active[i]["no"]) == no:
			active.remove_at(i)
			solved.append(no)
			return

func on_expedition_bought() -> void:
	for e: Dictionary in active:
		e["expedition_bought"] = true

# Place Dangers still active, oldest first (they hit again each generation).
func active_place_dangers() -> Array[int]:
	var out: Array[int] = []
	for e: Dictionary in active:
		if is_place(int(e["no"])):
			out.append(int(e["no"]))
	return out

static func is_place(no: int) -> bool:
	return str(FleetData.danger(no).get("type", "")) == "place"

static func is_condition_solve(no: int) -> bool:
	return CONDITION_SOLVES.has(str(SOLVES.get(no, {}).get("kind", "")))

# — Rule queries (static; "no change" outside Fleet) —

static func _on(no: int) -> bool:
	if current == null:
		return false
	for e: Dictionary in current.active:
		if int(e["no"]) == no:
			return true
	return false

## Supply of this colour can't be gained (Mining Incident, Smelter Accident).
## Storing is still allowed.
static func blocks_gain(color: int) -> bool:
	return (color == C.DUST and _on(4)) or (color == C.METALS and _on(6))

## No income of this colour at the end of a generation (Water Shortage, Plant
## Virus, Nanite Plague), on top of blocks_gain.
static func blocks_income(color: int) -> bool:
	return blocks_gain(color) or (color == C.LIQUIDS and _on(12)) \
			or (color == C.ORGANIX and _on(17)) or (color == C.ELECTRIX and _on(24))

## A fuse into or out of this colour isn't allowed (Smelter Accident: Metals,
## Anti-Fusion Field: Liquids).
static func blocks_fuse(color: int) -> bool:
	return (color == C.METALS and _on(6)) or (color == C.LIQUIDS and _on(9))

## Supplies of this colour can't be stored (Neural Gear Malfunction: any,
## Anti-Fusion Field: Liquids). color -1 = "any supply".
static func blocks_store(color: int) -> bool:
	return _on(21) or (color == C.LIQUIDS and _on(9))

## Cards can't be archived (Neural Gear Malfunction).
static func blocks_archive() -> bool:
	return _on(21)

## Cards of this colour can't be recycled (Pandemic: none at all, Barbarism: Thrust).
static func blocks_recycle(color: int) -> bool:
	return _on(14) or (color == C.THRUST and _on(28))

## Cards of this colour can't be placed (Barbarism: Thrust).
static func blocks_place(color: int) -> bool:
	return color == C.THRUST and _on(28)

## "Always" effects on your cards don't work (Totalitarianism).
static func always_effects_off() -> bool:
	return _on(8)

## Sectors with any Organix card can't be optimized (Infestation).
static func blocks_optimize_with_organix() -> bool:
	return _on(16)

## Extra cost to buy this card: Volatile Leak (Liquids +2), Alien Pathogen
## (Organix +2), Robot Uprising (sectors +2), Rogue AI (all +1).
static func cost_increase(card: CardData, is_advanced: bool = false) -> int:
	if current == null or card == null:
		return 0
	var color: int = card.adv_color if (card.card_type == CardData.CardType.SECTOR and is_advanced) else card.color
	var extra: int = 0
	if color == C.LIQUIDS and _on(11):
		extra += 2
	if color == C.ORGANIX and _on(18):
		extra += 2
	if card.card_type == CardData.CardType.SECTOR and _on(23):
		extra += 2
	if _on(27):
		extra += 1
	return extra

## Shuttle cost: the Destination's plus Asteroid Belt's +1.
static func shuttle_cost() -> int:
	if current == null:
		return 0
	return int(FleetData.destination(current.destination).get("shuttle", 0)) + (1 if _on(1) else 0)
