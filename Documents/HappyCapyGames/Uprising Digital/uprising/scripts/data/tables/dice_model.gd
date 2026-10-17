class_name DiceModel
extends RefCounted

## Real per-color face distributions, transcribed from
## assets/images/Uprising+Final+EN/CORE_BOX_EN/PLAYERAIDS_EN/
## Dice+Distribution+Front.jpg (the "DICE DISTRIBUTION" reference card).
## Replaces EffectContext's placeholder uniform-25%-per-symbol roll (see
## that file's own doc comment) - this is the real Milestone 4 dependency
## it was waiting on.
##
## CAVEAT: some faces show TWO symbols at once (e.g. a face that is both
## Skull+Shield, or Skull+Bolt) - read directly off the chart, not
## invented, but a dense compound-face read like this is exactly the kind
## of data worth a human spot-check against the physical dice before
## trusting it as flawless (same caveat as legion_horde_combat_table.gd).
##
## Re-checked 2026-10-17 against a zoomed crop of the card: purple's top
## face is a DOUBLE Bolt and black's top face a TRIPLE Skull (both were
## previously under-counted by one symbol). The rulebook's p39 example
## ("The New Emperor rolls a Bolt-Bolt" on purple/yellow/white) confirms
## the purple one independently.
##
## 6 colors x 6 faces. Each face is an Array[String] of the symbols it
## shows (usually 1, sometimes 2 or 3) from {"Skull","Shield","Bolt"} - a face
## with an empty array is a Blank.

static var FACES: Dictionary = {
	"white": [["Skull", "Shield"], ["Skull"], ["Shield"], [], [], []],
	"yellow": [["Skull"], ["Skull"], ["Skull"], ["Skull"], [], []],
	"red": [["Skull", "Skull"], ["Skull", "Bolt"], ["Skull"], ["Skull"], [], []],
	"blue": [["Shield"], ["Shield"], ["Skull"], ["Skull"], ["Skull"], []],
	"purple": [["Bolt", "Bolt"], ["Skull", "Bolt"], ["Skull"], ["Skull"], ["Skull"], []],
	"black": [["Skull", "Skull", "Skull"], ["Skull", "Skull"], ["Skull"], ["Skull"], ["Skull"], ["Bolt"]],
}


## Rolls one die of `color`, returning the list of symbols on the face that
## came up (0-3 symbols; empty = Blank). Uses `rng` for determinism in
## tests.
static func roll(color: String, rng: RandomNumberGenerator) -> Array[String]:
	var faces: Array = FACES.get(color, [[]])
	var face_index: int = rng.randi_range(0, faces.size() - 1)
	var result: Array[String] = []
	for s: Variant in faces[face_index]:
		result.append(str(s))
	return result


## Hero Dice (rulebook p12, p25): 1 red per Might, 1 purple per Magic, 1
## blue per Leadership, and per Guile a white OR yellow die chosen before
## rolling (`guile_color`; yellow leans Skulls, white Shields).
static func hero_pool(hero: HeroCard, guile_color: String = "yellow") -> Array[String]:
	var pool: Array[String] = []
	if hero == null:
		return pool
	for _i: int in range(hero.might):
		pool.append("red")
	for _i: int in range(hero.magic):
		pool.append("purple")
	for _i: int in range(hero.lead):
		pool.append("blue")
	for _i: int in range(hero.guile):
		pool.append(guile_color)
	return pool


## Rolls a whole pool of dice (e.g. one Legion/Horde's Archery or Clash
## row from LegionHordeCombatTable) and returns aggregate symbol counts.
static func roll_pool(colors: Array, rng: RandomNumberGenerator) -> Dictionary:
	var counts: Dictionary = {"Skull": 0, "Shield": 0, "Bolt": 0}
	for c: Variant in colors:
		for symbol: String in roll(str(c), rng):
			counts[symbol] = int(counts.get(symbol, 0)) + 1
	return counts
