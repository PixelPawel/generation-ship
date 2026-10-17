class_name HexEffectPrograms
extends RefCounted

## Explore effects of the Core box hexes (Hexes.csv, EN, Box=Core): the 19
## Normal hexes and the 5 Sea Towers. Each builder quotes its CSV Effect
## text verbatim so the transcription can be checked against the source.
## The Capital and the Home hexes start face-up and are never explored.
##
## Rewritten 2026-10-17 against the rulebook's placement rules: "Place N
## Skeletons with other Skeletons" goes onto OTHER hexes that have
## Skeletons (it used to land on the explored hex itself), "Place N
## Garrisons on empty hexes with no X" really places them (it used to
## need a choice_resolver Explore never set, so it was skipped), "Roll your
## Hero Dice" rolls the real Hero Dice, and Netherwood, Kyushi's Tavern's
## free Quest and the Sea Towers are now covered. Player choices
## ("Gain 2 resources", which player rolls...) use the defaults described
## in each op. Feats aren't tracked as cards yet, so "draws/discards 1
## Feat" is only logged.

const QUEST_FLOW_PATH := "res://scripts/game/quest_flow.gd"


## A one-off clause written as a function of the EffectContext.
class FnOp extends EffectOp:
	var fn: Callable
	var text: String

	func _init(p_text: String, p_fn: Callable) -> void:
		text = p_text
		fn = p_fn

	func execute(ctx: EffectContext) -> void:
		fn.call(ctx)

	func describe() -> String:
		return text


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
	"Netherwood": _netherwood,
	"Trollward": _trollward,
	"Dawngaard": _dawngaard,
	"Guragi Tower": _guragi_tower,
	"Hellhound Tower": _hellhound_tower,
	"Zeegard": _zeegard,
	"Midnight Tower": _midnight_tower,
}


static func _feat_note(text: String) -> FnOp:
	return FnOp.new(text, func(ctx: EffectContext) -> void:
		ctx.log("%s (Feats are not tracked as cards yet)" % text))


## "Gain 2 FOOD + If Empty, place 2 Skeletons here; if not Reinforce here.
## + Place 2 Skeletons with other Skeletons"
static func _bruthgaard() -> EffectProgram:
	return EffectProgram.new("Bruthgaard", [
		GainResourceOp.new("Food", 2),
		PlaceOrReinforceOp.new("Skeleton", 2),
		PlaceTokenOp.new("Skeleton", 2, "with_others"),
	])


## "Gain 2 FOOD + If Empty, place 2 Garrisons here; if not Reinforce here.
## + Place 2 Garrisons on Empty Hexes with no X."
static func _golgardei() -> EffectProgram:
	return EffectProgram.new("Golgardei", [
		GainResourceOp.new("Food", 2),
		PlaceOrReinforceOp.new("Garrison", 2),
		PlaceTokenOp.new("Garrison", 2, "empty_no_x"),
	])


## "If Empty, place 1 Garrison here; if not Reinforce here. + Place 1
## Garrison on an Empty Hex with no X. + Each other Player gains 1 FOOD. +
## Roll your Hero Dice: Gain 1 FOOD per SKULL."
static func _plains_of_rhun() -> EffectProgram:
	return EffectProgram.new("Plains of Rhun", [
		PlaceOrReinforceOp.new("Garrison", 1),
		PlaceTokenOp.new("Garrison", 1, "empty_no_x"),
		EachPlayerOp.new([GainResourceOp.new("Food", 1)], true),
		RollHeroDiceRewardOp.new("Skull", GainResourceOp.new("Food", 1)),
	])


## "Gain 2 PLUNDER. + If Empty, place 1 Garrison here; if not Reinfroce
## here. + Place 2 Garrisons on Empty Hexes with no X." [sic]
static func _frosthold_pass() -> EffectProgram:
	return EffectProgram.new("Frosthold Pass", [
		GainResourceOp.new("Plunder", 2),
		PlaceOrReinforceOp.new("Garrison", 1),
		PlaceTokenOp.new("Garrison", 2, "empty_no_x"),
	])


## "Remove any Skeletons here. + Place 2 Garrisons here + Roll your Hero
## Dice: Gain 1 PLUNDER per SKULL. Each other Player gains 1 PLUNDER."
static func _imperial_slave_mines() -> EffectProgram:
	return EffectProgram.new("Imperial Slave Mines", [
		RemoveTokenOp.new("Skeleton"),
		PlaceTokenOp.new("Garrison", 2, "here"),
		RollHeroDiceRewardOp.new("Skull", GainResourceOp.new("Plunder", 1)),
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
		PlaceTokenOp.new("Skeleton", 1, "with_others"),
		PlaceActivationTokenOp.new(),
	])


## "Gain 2 SALT. + If Empty, place 2 Skeletons here; if not Reinforce
## here. + Place 2 Skeletons with other Skeletons."
static func _grim_fangs() -> EffectProgram:
	return EffectProgram.new("Grim Fangs", [
		GainResourceOp.new("Salt", 2),
		PlaceOrReinforceOp.new("Skeleton", 2),
		PlaceTokenOp.new("Skeleton", 2, "with_others"),
	])


## "Gain 2 SALT. If Empty, place 1 Garrison here; if not Reinforce here. +
## Place 1 Garrison on an Empty Hex with no X."
static func _raufrost() -> EffectProgram:
	return EffectProgram.new("Raufrost", [
		GainResourceOp.new("Salt", 2),
		PlaceOrReinforceOp.new("Garrison", 1),
		PlaceTokenOp.new("Garrison", 1, "empty_no_x"),
	])


## "Gain 2 Salt + If empty, place 2 Skeletons here; if not reinforce here.
## + Place 1 Skeleton with other Skeletons."
static func _shadowdawn() -> EffectProgram:
	return EffectProgram.new("Shadowdawn", [
		GainResourceOp.new("Salt", 2),
		PlaceOrReinforceOp.new("Skeleton", 2),
		PlaceTokenOp.new("Skeleton", 1, "with_others"),
	])


## "If Empty, place 1 Skeleton here; if not Reinforce here. + Roll your
## Hero Dice: Gain 1 SALT per SKULL. Each other Player gains 2 SALT."
static func _taurel_caravan_passage() -> EffectProgram:
	return EffectProgram.new("Taurel Caravan Passage", [
		PlaceOrReinforceOp.new("Skeleton", 1),
		RollHeroDiceRewardOp.new("Skull", GainResourceOp.new("Salt", 1)),
		EachPlayerOp.new([GainResourceOp.new("Salt", 2)], true),
	])


## "Gain 3 SALT. + If Empty, place 1 Skeleton here; if not Reinforce here.
## + Place 2 Skeletons with other Skeletons."
static func _torment() -> EffectProgram:
	return EffectProgram.new("Torment", [
		GainResourceOp.new("Salt", 3),
		PlaceOrReinforceOp.new("Skeleton", 1),
		PlaceTokenOp.new("Skeleton", 2, "with_others"),
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
static func _kyushis_tavern() -> EffectProgram:
	return EffectProgram.new("Kyushis Tavern", [
		GainResourceOp.new("Food", 3),
		PlaceOrReinforceOp.new("Garrison", 1),
		FnOp.new("Free Quest Action with +1 BLUE", func(ctx: EffectContext) -> void:
			var quest_flow: GDScript = load(QUEST_FLOW_PATH)
			var quest: String = quest_flow.best_quest_for(ctx.state, ctx.card_db, ctx.acting_faction, ["blue"])
			if quest.is_empty():
				ctx.log("Kyushi's Tavern: no Quest to attempt")
				return
			var r: Dictionary = quest_flow.attempt(ctx.state, ctx.card_db, ctx.acting_faction, quest, {"extra_dice": ["blue"], "ignore_failure": true})
			ctx.log(str(r.get("log", ""))))
	])


## "Gain 2 FOOD. + If Empty, place 1 Garrison here; if not Reinforce
## here. + Place 1 Garrison on an Empty Hex with no X."
static func _rigga() -> EffectProgram:
	return EffectProgram.new("Rigga", [
		GainResourceOp.new("Food", 2),
		PlaceOrReinforceOp.new("Garrison", 1),
		PlaceTokenOp.new("Garrison", 1, "empty_no_x"),
	])


## "Gain 2 PLUNDER. + Remove any Skeletons here. Place 2 Garrisons here. +
## Each Player draws 1 Feat, then discards 1 Feat."
static func _dunkelholm() -> EffectProgram:
	return EffectProgram.new("Dunkelholm", [
		GainResourceOp.new("Plunder", 2),
		RemoveTokenOp.new("Skeleton"),
		PlaceTokenOp.new("Garrison", 2, "here"),
		_feat_note("Each player draws 1 Feat, then discards 1 Feat"),
	])


## "Gain 2 PLUNDER + If Empty, place 2 Skeletons here; if not Reinforce
## here. + Each Player gains 1 Basic Unit on a Haven or an Empty Explored
## Hex."
static func _fjoelja_stone_circle() -> EffectProgram:
	return EffectProgram.new("Fjoelja Stone Circle", [
		GainResourceOp.new("Plunder", 2),
		PlaceOrReinforceOp.new("Skeleton", 2),
		EachPlayerOp.new([PlaceUnitOp.new(1, "haven_or_empty_explored")], false),
	])


## "Gain 2 RESOURCES. + Choose a player to roll their Hero Dice: 4+ SKULL =
## Every player gains 2 resources / 2+ SHIELD = Every player draws 1 Feat /
## 2+ BOLT = Every player gains 1 VP / If you fail all, place 1 Horde here
## (and only here)."
## The roller is the Hero with the most dice.
static func _netherwood() -> EffectProgram:
	return EffectProgram.new("Netherwood", [
		GainResourceOp.new("Any", 2),
		FnOp.new("Netherwood roll", func(ctx: EffectContext) -> void:
			var roll: Dictionary = roll_best_hero(ctx, "yellow")
			var hit: bool = false
			if int(roll["Skull"]) >= 4:
				hit = true
				EachPlayerOp.new([GainResourceOp.new("Any", 2)], false).execute(ctx)
			if int(roll["Shield"]) >= 2:
				hit = true
				_feat_note("Every player draws 1 Feat").execute(ctx)
			if int(roll["Bolt"]) >= 2:
				hit = true
				for p: PlayerFactionState in ctx.state.players:
					p.vp += 1
				ctx.log("Every player gains 1 VP")
			if not hit:
				NemesisAI.spawn_horde(ctx.state, ctx.hex_coord, ctx.card_db)
				ctx.log("Netherwood: every goal failed - a Horde rises here")),
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


## Sea Tower "Dawngaard": "Gain 2 SALT. + Remove any Skeletons here. +
## Place 2 Garrisons here."
static func _dawngaard() -> EffectProgram:
	return EffectProgram.new("Dawngaard", [
		GainResourceOp.new("Salt", 2),
		RemoveTokenOp.new("Skeleton"),
		PlaceTokenOp.new("Garrison", 2, "here"),
	])


## Sea Tower "Guragi Tower": "Gain 4 SALT. + Remove any Garrisons here. +
## Place 2 Skeletons here."
static func _guragi_tower() -> EffectProgram:
	return EffectProgram.new("Guragi Tower", [
		GainResourceOp.new("Salt", 4),
		RemoveTokenOp.new("Garrison"),
		PlaceTokenOp.new("Skeleton", 2, "here"),
	])


## Sea Tower "Hellhound Tower": "Gain 4 SALT.: Remove any Garrisons here.
## Place 1 Curse here. Place 2 Skeletons here."
static func _hellhound_tower() -> EffectProgram:
	return EffectProgram.new("Hellhound Tower", [
		GainResourceOp.new("Salt", 4),
		RemoveTokenOp.new("Garrison"),
		PlaceTokenOp.new("Curse", 1, "here"),
		PlaceTokenOp.new("Skeleton", 2, "here"),
	])


## Sea Tower "Zeegard": "Gain 2 SALT. + Remove any Skeletons here. + Place
## 3 Garrisons here."
static func _zeegard() -> EffectProgram:
	return EffectProgram.new("Zeegard", [
		GainResourceOp.new("Salt", 2),
		RemoveTokenOp.new("Skeleton"),
		PlaceTokenOp.new("Garrison", 3, "here"),
	])


## Sea Tower "Midnight Tower": "Gain 4 SALT. + Place 1 Horde, and 1 Legion
## and its Target, from the box, at Threat 7 here. Ignore their immediate
## effects."
static func _midnight_tower() -> EffectProgram:
	return EffectProgram.new("Midnight Tower", [
		GainResourceOp.new("Salt", 4),
		FnOp.new("Horde + Legion from the box at Threat 7", func(ctx: EffectContext) -> void:
			NemesisAI.spawn_horde(ctx.state, ctx.hex_coord, ctx.card_db, 7, {"from_box": true, "ignore_immediate": true, "no_combat": true})
			NemesisAI.spawn_legion(ctx.state, ctx.card_db, ctx.hex_coord, 7, {"from_box": true, "ignore_immediate": true, "target": "here", "no_combat": true})
			NemesisAI.resolve_combat_at(ctx.state, ctx.card_db, ctx.hex_coord)),
	])


## The player whose Hero has the most dice rolls them (ties: turn order).
## Returns symbol counts plus "roller".
static func roll_best_hero(ctx: EffectContext, guile_color: String) -> Dictionary:
	var best: PlayerFactionState = null
	var best_size: int = -1
	for p: PlayerFactionState in ctx.state.players:
		var size: int = DiceModel.hero_pool(EffectUtil.hero_card(ctx.card_db, p.hero_name)).size()
		if size > best_size:
			best_size = size
			best = p
	var counts: Dictionary = {"Skull": 0, "Shield": 0, "Bolt": 0, "roller": ""}
	if best == null:
		return counts
	if ctx.rng == null:
		ctx.rng = RandomNumberGenerator.new()
		ctx.rng.randomize()
	var pool: Array[String] = DiceModel.hero_pool(EffectUtil.hero_card(ctx.card_db, best.hero_name), guile_color)
	var rolled: Dictionary = DiceModel.roll_pool(pool, ctx.rng)
	for k: Variant in rolled.keys():
		counts[k] = rolled[k]
	counts["roller"] = best.faction
	ctx.log("%s rolls their Hero Dice: %d Skull, %d Shield, %d Bolt" % [best.faction, counts["Skull"], counts["Shield"], counts["Bolt"]])
	return counts
