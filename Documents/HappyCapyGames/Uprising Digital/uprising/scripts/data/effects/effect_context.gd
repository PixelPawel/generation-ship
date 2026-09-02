class_name EffectContext
extends RefCounted

## Everything an EffectOp needs to actually run against a real GameState.
## One EffectContext is built per effect resolution (one Hex explore, one
## Quest solve, one Event, etc.) - NOT reused across resolutions.

var state: GameState
var card_db: Node          # CardDatabase autoload
var rng: RandomNumberGenerator

## Whichever faction "owns" this resolution - the Explorer, the Quest-
## taker, the first player resolving an Event. "" for Nemesis-triggered
## effects with no owning player.
var acting_faction: String = ""

## The hex this effect is anchored to ("here" in card text), if any.
var hex_coord: Vector2i = Vector2i.ZERO
var has_hex_coord: bool = false

## Resolves an ambiguous player-chosen target (e.g. "an Empty Hex with no
## X", "choose a player to roll") - optional; ops fall back to a documented
## deterministic default (and log a warning) when this is unset, which is
## the expected/normal case in headless tests and any resolution that
## hasn't been wired to real UI yet (Milestone 5's job).
## func(kind: String, options: Array) -> Variant
var choice_resolver: Callable = Callable()

var log_lines: Array[String] = []

## PLACEHOLDER uniform distribution (25% each of Skull/Shield/Bolt/Blank) -
## NOT the real per-die-color Uprising distribution. Real face data lives
## on Dice-Distribution.jpg and is a documented Milestone 4 dependency
## (blocking Combat, per the approved plan) - this exists so ops like
## RollHeroDiceRewardOp are structurally correct and testable NOW without
## pretending to already have real values they don't. Override via
## `dice_roller` once real per-color tables exist.
var dice_roller: Callable = Callable()


func log(line: String) -> void:
	log_lines.append(line)


func here() -> Vector2i:
	return hex_coord


func roll_symbol() -> String:
	if dice_roller.is_valid():
		return str(dice_roller.call())
	var symbols: Array[String] = ["Skull", "Shield", "Bolt", "Blank"]
	return symbols[rng.randi_range(0, 3)] if rng != null else "Blank"
