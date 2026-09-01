class_name DiceModel
extends RefCounted
## Exact face data for all 6 die colors, transcribed from the game's own
## "Dice Distribution" player-aid card
## (assets/images/TTS/Dice-Distribution.jpg, and the identical copy at
## Uprising+Final+EN/CORE_BOX_EN/PLAYERAIDS_EN/Dice+Distribution+Front.jpg).
## This was the one piece of data genuinely missing from every CSV, the
## xlsx, and the rulebook text -- finding this player-aid image unblocks
## Quest dice resolution (implemented here) and eventually Combat (still
## needs a second, separate piece of data: which colors each Unit/Garrison/
## Skeleton/Legion/Horde actually rolls, which lives on individual card art,
## not in this file).
##
## Cross-checked against two independent combat examples already
## transcribed from the rulebook before this image was found: p34's "3 blue
## dice roll blank+Skull+Shield" and p38's Skeleton red dice showing a
## double-Skull face -- both match this table exactly, so the transcription
## is corroborated, not just a one-shot read.
##
## Each die's 6 faces below are listed in whatever order is easiest to
## audit against the source image (heaviest face first), not real physical
## face order -- physical order doesn't affect probabilities and Godot's
## randi_range() treats all 6 indices uniformly regardless.

enum Symbol { SKULL, SHIELD, BOLT }

const FACES := {
	"White": [
		[Symbol.SKULL, Symbol.SHIELD],
		[Symbol.SKULL],
		[Symbol.SHIELD],
		[],
		[],
		[],
	],
	"Yellow": [
		[Symbol.SKULL],
		[Symbol.SKULL],
		[Symbol.SKULL],
		[Symbol.SKULL],
		[],
		[],
	],
	"Red": [
		[Symbol.SKULL, Symbol.SKULL],
		[Symbol.SKULL, Symbol.BOLT],
		[Symbol.SKULL],
		[Symbol.SKULL],
		[],
		[],
	],
	"Blue": [
		[Symbol.SHIELD],
		[Symbol.SHIELD],
		[Symbol.SKULL],
		[Symbol.SKULL],
		[Symbol.SKULL],
		[],
	],
	"Purple": [
		[Symbol.BOLT],
		[Symbol.SKULL, Symbol.BOLT],
		[Symbol.SKULL],
		[Symbol.SKULL],
		[Symbol.SKULL],
		[],
	],
	"Black": [
		[Symbol.SKULL, Symbol.SKULL, Symbol.SKULL],
		[Symbol.SKULL, Symbol.SKULL],
		[Symbol.SKULL],
		[Symbol.SKULL],
		[Symbol.SKULL],
		[Symbol.BOLT],
	],
}


## Rolls `count` dice of `color`. Pass an `rng` for deterministic/testable
## rolls; omit it to use the engine's global RNG for real gameplay.
static func roll(color: String, count: int, rng: RandomNumberGenerator = null) -> Dictionary:
	var tally := {"skulls": 0, "shields": 0, "bolts": 0}
	var faces: Array = FACES.get(color, [])
	if faces.is_empty() or count <= 0:
		return tally
	for _i in range(count):
		var face_index: int = rng.randi_range(0, 5) if rng != null else randi() % 6
		for symbol in faces[face_index]:
			match symbol:
				Symbol.SKULL:
					tally["skulls"] += 1
				Symbol.SHIELD:
					tally["shields"] += 1
				Symbol.BOLT:
					tally["bolts"] += 1
	return tally


## Rolls several colors at once, e.g. {"Red": 2, "White": 1}, and sums the
## results into one tally.
static func roll_mixed(colors_and_counts: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	var total := {"skulls": 0, "shields": 0, "bolts": 0}
	for color in colors_and_counts:
		var t := roll(color, int(colors_and_counts[color]), rng)
		total["skulls"] += t["skulls"]
		total["shields"] += t["shields"]
		total["bolts"] += t["bolts"]
	return total
