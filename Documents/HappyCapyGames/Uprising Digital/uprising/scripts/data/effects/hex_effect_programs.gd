class_name HexEffectPrograms
extends RefCounted

## Hand-transcribed EffectPrograms for the Core Box's 20 "Normal"-type
## hexes (assets/data/UPRISING _ FULL CARD DETAILS - Hexes.csv, EN, Box=
## Core, Type=Normal) - the FIRST category in the plan's own transcription
## order (Hex explore effects gate board interaction; Events/Quests/Feats/
## Items come after). Every effect string below is quoted verbatim from
## that CSV in each function's comment so the transcription can be checked
## against the source without re-opening the spreadsheet.
##
## Deliberately built as GDScript (a Dictionary of builder functions), NOT
## authored JSON/.tres files yet, despite the plan's stated preference for
## JSON - typed constructors are faster to write correctly and to keep in
## sync with the op vocabulary while that vocabulary is still this new
## (built and validated in this same session). Migrating to
## data-file-authored effects (so non-programmer edits don't need a
## GDScript change) is a reasonable follow-up once the vocabulary has
## proven stable against a wider transcription pass - not done now to
## avoid churn on a still-moving target.
##
## 3 of the 20 Core Normal hexes are NOT included below, on purpose:
## - "Capital": its effect ("Gain 5 VP if this hex is flipped") triggers
##   off the Nemesis-side Capital-flip mechanic (rulebook p47), not the
##   Explore action - a different trigger entirely, out of scope for this
##   hex-explore transcription pass.
## - "Netherwood": a genuinely multi-branch dice-threshold effect (roll,
##   then one of 3 different rewards depending on which symbol-count
##   threshold was met, with a 4th "if you fail all" branch) that needs
##   more op-vocabulary support (multi-threshold RollHeroDiceReward, or a
##   dedicated op) than was worth building for a single card on a first
##   pass - flagged rather than force-fit into the current ops.
## - Two effects reference mechanics this pass doesn't model yet and are
##   transcribed PARTIALLY, with the unmodeled clause left as a code
##   comment rather than silently dropped: Kyushi's Tavern's free Quest
##   Action (needs GameActions, Milestone 4) and Dunkelholm's "then
##   discards 1" (needs a real discard-choice, Milestone 5 UI).
##
## RollHeroDiceRewardOp's dice_count below uses a PLACEHOLDER value (see
## that op's own class doc) since real Hero Dice count depends on
## attributes not wired up yet - flagged inline on each such line, not
## silently invented.

static func get_program(card_name: String) -> EffectProgram:
	var builder: Callable = _BUILDERS.get(card_name, Callable())
	if not builder.is_valid():
		return null
	return builder.call()


static func has_program(card_name: String) -> bool:
	return _BUILDERS.has(card_name)


static var _BUILDERS: Dictionary = {
	"Bruthgaard": _bruthgaard,
	"Golgardei": _golgardei,
	"Plains of Rhun": _plains_of_rhun,
	"Frosthold Pass": _frosthold_pass,
	"Imperial Slave Mines": _imperial_slave_mines,
	"Tomb of the Elder Kings": _tomb_of_the_elder_kings,
	"Black Ice": _black_ice,
	"Grim Fangs": _grim_fangs,
	"Raufrost": _raufrost,
	"Shadowdawn": _shadowdawn,
	"Taurel Caravan Passage": _taurel_caravan_passage,
	"Torment": _torment,
	"Fyrnhalla": _fyrnhalla,
	"Kyushis Tavern": _kyushis_tavern,
	"Rigga": _rigga,
	"Dunkelholm": _dunkelholm,
	"Fjoelja Stone Circle": _fjoelja_stone_circle,
	"Trollward": _trollward,
}


## "Gain 2 FOOD + If Empty, place 2 Skeletons here; if not Reinforce here.
## + Place 2 Skeletons with other Skeletons"
static func _bruthgaard() -> EffectProgram:
	return EffectProgram.new("Bruthgaard", [
		GainResourceOp.new("Food", 2),
		PlaceOrReinforceOp.new("Skeleton", 2),
		PlaceTokenOp.new("Skeleton", 2, "here"),
	])


## "Gain 2 FOOD + If Empty, place 2 Garrisons here; if not Reinforce here.
## + Place 2 Garrisons on Empty Hexes with no X."
static func _golgardei() -> EffectProgram:
	return EffectProgram.new("Golgardei", [
		GainResourceOp.new("Food", 2),
		PlaceOrReinforceOp.new("Garrison", 2),
		PlaceTokenOp.new("Garrison", 2, "chosen_empty_hex_no_x"),
	])


## "If Empty, place 1 Garrison here; if not Reinforce here. + Place 1
## Garrison on an Empty Hex with no X. + Each other Player gains 1 FOOD. +
## Roll your Hero Dice: Gain 1 FOOD per SKULL."
static func _plains_of_rhun() -> EffectProgram:
	return EffectProgram.new("Plains of Rhun", [
		PlaceOrReinforceOp.new("Garrison", 1),
		PlaceTokenOp.new("Garrison", 1, "chosen_empty_hex_no_x"),
		EachPlayerOp.new([GainResourceOp.new("Food", 1)], true),
		RollHeroDiceRewardOp.new(2, "Skull", GainResourceOp.new("Food", 1)),  # dice_count placeholder, see class doc
	])


## "Gain 2 PLUNDER. + If Empty, place 1 Garrison here; if not Reinfroce
## here. + Place 2 Garrisons on Empty Hexes with no X." [sic, "Reinfroce" typo in source]
static func _frosthold_pass() -> EffectProgram:
	return EffectProgram.new("Frosthold Pass", [
		GainResourceOp.new("Plunder", 2),
		PlaceOrReinforceOp.new("Garrison", 1),
		PlaceTokenOp.new("Garrison", 2, "chosen_empty_hex_no_x"),
	])


## "Remove any Skeletons here. + Place 2 Garrisons here + Roll your Hero
## Dice: Gain 1 PLUNDER per SKULL. Each other Player gains 1 PLUNDER."
static func _imperial_slave_mines() -> EffectProgram:
	return EffectProgram.new("Imperial Slave Mines", [
		RemoveTokenOp.new("Skeleton"),
		PlaceTokenOp.new("Garrison", 2, "here"),
		RollHeroDiceRewardOp.new(2, "Skull", GainResourceOp.new("Plunder", 1)),  # dice_count placeholder
		EachPlayerOp.new([GainResourceOp.new("Plunder", 1)], true),
	])


## "Gain 1 PLUNDER. + Remove any Garrisons here. + Place 2 Skeletons here +
## Draw 1 Item and keep it even if you could not use it."
static func _tomb_of_the_elder_kings() -> EffectProgram:
	return EffectProgram.new("Tomb of the Elder Kings", [
		GainResourceOp.new("Plunder", 1),
		RemoveTokenOp.new("Garrison"),
		PlaceTokenOp.new("Skeleton", 2, "here"),
		DrawCardOp.new("Item", 1, true),
	])


## "Gain 2 SALT. + If Empty, place 1 Skeleton here; if not Reinforce here.
## + Place 1 Skeleton with other skeletons. + Place 1 Activation Token on
## a Legion or Horde card with the least Tokens."
static func _black_ice() -> EffectProgram:
	return EffectProgram.new("Black Ice", [
		GainResourceOp.new("Salt", 2),
		PlaceOrReinforceOp.new("Skeleton", 1),
		PlaceTokenOp.new("Skeleton", 1, "here"),
		PlaceActivationTokenOp.new(),
	])


## "Gain 2 SALT. + If Empty, place 2 Skeletons here; if not Reinforce
## here. + Place 2 Skeletons with other Skeletons."
static func _grim_fangs() -> EffectProgram:
	return EffectProgram.new("Grim Fangs", [
		GainResourceOp.new("Salt", 2),
		PlaceOrReinforceOp.new("Skeleton", 2),
		PlaceTokenOp.new("Skeleton", 2, "here"),
	])


## "Gain 2 SALT. If Empty, place 1 Garrison here; if not Reinforce here. +
## Place 1 Garrison on an Empty Hex with no X."
static func _raufrost() -> EffectProgram:
	return EffectProgram.new("Raufrost", [
		GainResourceOp.new("Salt", 2),
		PlaceOrReinforceOp.new("Garrison", 1),
		PlaceTokenOp.new("Garrison", 1, "chosen_empty_hex_no_x"),
	])


## "Gain 2 Salt + If empty, place 2 Skeletons here; if not reinforce here.
## + Place 1 Skeleton with other Skeletons."
static func _shadowdawn() -> EffectProgram:
	return EffectProgram.new("Shadowdawn", [
		GainResourceOp.new("Salt", 2),
		PlaceOrReinforceOp.new("Skeleton", 2),
		PlaceTokenOp.new("Skeleton", 1, "here"),
	])


## "If Empty, place 1 Skeleton here; if not Reinforce here. + Roll your
## Hero Dice: Gain 1 SALT per SKULL. Each other Player gains 2 SALT."
static func _taurel_caravan_passage() -> EffectProgram:
	return EffectProgram.new("Taurel Caravan Passage", [
		PlaceOrReinforceOp.new("Skeleton", 1),
		RollHeroDiceRewardOp.new(2, "Skull", GainResourceOp.new("Salt", 1)),  # dice_count placeholder
		EachPlayerOp.new([GainResourceOp.new("Salt", 2)], true),
	])


## "Gain 3 SALT. + If Empty, place 1 Skeleton here; if not Reinforce here.
## + Place 2 Skeletons with other Skeletons."
static func _torment() -> EffectProgram:
	return EffectProgram.new("Torment", [
		GainResourceOp.new("Salt", 3),
		PlaceOrReinforceOp.new("Skeleton", 1),
		PlaceTokenOp.new("Skeleton", 2, "here"),
	])


## "Gain 2 FOOD. + If Empty, place 2 Garrisons here; if not, Reinforce
## here. + Place 1 Activation Token on a Legion or Horde card with the
## least Tokens."
static func _fyrnhalla() -> EffectProgram:
	return EffectProgram.new("Fyrnhalla", [
		GainResourceOp.new("Food", 2),
		PlaceOrReinforceOp.new("Garrison", 2),
		PlaceActivationTokenOp.new(),
	])


## "Gain 3 FOOD. + If Empty, place 1 Garrison here; if not, Reinforce
## here. + Take a Quest Action (for 0 AP) with +1 BLUE. If you fail,
## ignore any Failure Effects."
## The free-Quest-Action clause needs GameActions (Milestone 4) - NOT
## modeled here, deliberately, rather than faked.
static func _kyushis_tavern() -> EffectProgram:
	return EffectProgram.new("Kyushis Tavern", [
		GainResourceOp.new("Food", 3),
		PlaceOrReinforceOp.new("Garrison", 1),
		# TODO (Milestone 4): "Take a Quest Action (for 0 AP) with +1 BLUE.
		# If you fail, ignore any Failure Effects." needs a real Quest
		# Action + bonus-die + failure-suppression mechanism.
	])


## "Gain 2 FOOD. + If Empty, place 1 Garrison here; if not Reinforce
## here. + Place 1 Garrison on an Empty Hex with no X."
static func _rigga() -> EffectProgram:
	return EffectProgram.new("Rigga", [
		GainResourceOp.new("Food", 2),
		PlaceOrReinforceOp.new("Garrison", 1),
		PlaceTokenOp.new("Garrison", 1, "chosen_empty_hex_no_x"),
	])


## "Gain 2 PLUNDER. + Remove any Skeletons here. Place 2 Garrisons here. +
## Each Player draws 1 Feat, then discards 1 Feat."
## The "then discards 1" half needs a real discard choice (Milestone 5 UI)
## - only the draw is modeled here, deliberately, rather than faked.
static func _dunkelholm() -> EffectProgram:
	return EffectProgram.new("Dunkelholm", [
		GainResourceOp.new("Plunder", 2),
		RemoveTokenOp.new("Skeleton"),
		PlaceTokenOp.new("Garrison", 2, "here"),
		EachPlayerOp.new([DrawCardOp.new("Feat", 1)], false),
		# TODO (Milestone 5): "then discards 1 Feat" needs a player-facing
		# discard choice per player.
	])


## "Gain 2 PLUNDER + If Empty, place 2 Skeletons here; if not Reinforce
## here. + Each Player gains 1 Basic Unit on a Haven or an Empty Explored
## Hex."
## "on a Haven or an Empty Explored Hex" is a real player choice among
## multiple hexes - PlaceUnitOp's "here" fallback is used below as an
## explicit simplification (place on the triggering hex itself), NOT the
## full choice; flagged rather than silently wrong.
static func _fjoelja_stone_circle() -> EffectProgram:
	return EffectProgram.new("Fjoelja Stone Circle", [
		GainResourceOp.new("Plunder", 2),
		PlaceOrReinforceOp.new("Skeleton", 2),
		EachPlayerOp.new([PlaceUnitOp.new(1, "here")], false),  # simplified target, see doc comment above
	])


## "Gain 2 PLUNDER. + If Empty, place 2 Garrisons here; if not Reinforce
## here. + Place 1 Activation Token on the Legion or Horde card with the
## least Tokens."
static func _trollward() -> EffectProgram:
	return EffectProgram.new("Trollward", [
		GainResourceOp.new("Plunder", 2),
		PlaceOrReinforceOp.new("Garrison", 2),
		PlaceActivationTokenOp.new(),
	])
