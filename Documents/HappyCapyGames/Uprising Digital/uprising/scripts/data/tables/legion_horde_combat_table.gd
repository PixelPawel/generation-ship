class_name LegionHordeCombatTable
extends RefCounted

## Hand-transcribed from the 16 Core Legion/Horde card images (read
## directly, not guessed) - the single largest blocking dependency for
## Combat automation per the approved plan. Source images:
## assets/images/Uprising+Final+EN/CORE_BOX_EN/CARDS_EN/BIG_CARDS_EN/
## {LEGIONS_EN,HORDES_EN}/*.jpg
##
## CAVEAT, stated plainly: this is a dense, single-pass visual
## transcription of 16 cards x up to 7 rows x up to 11 dice each. It was
## read carefully (one legitimate misread was caught and fixed in-session
## by re-reading The Imperial Guard's Threat-7 Clash row, which turned out
## to genuinely have 6 dice where most other cards have 5), but a table
## this dense from image reads alone should get a human spot-check against
## the physical/PDF cards before being trusted as flawless ground truth
## for real play - flagged honestly rather than claimed as perfect.
##
## Dice colors: "black","purple","blue","red","yellow","white" (6-color
## core set, confirmed against assets/images/.../DICE/d6_*.png filenames).
## Initiative = the printed starburst number = the same number embedded in
## each card's own filename (e.g. Legions_Core_02_Courtesan.jpg -> 2) -
## confirmed against the printed card art itself for all 16, not assumed
## from the filename alone.
##
## Godpower/passive/on-destroy text is captured as raw strings, NOT parsed
## into executable EffectOps - these are the "triggered/ongoing ability"
## category explicitly scoped OUT of Milestone 3 (see hex_effect_programs.gd's
## doc comment); NemesisAI/CombatResolver (Milestone 4) can read this text
## for display/manual-assist even before it's automated.
##
## "On destroy" VP: every card's bottom text ends "gain N [diamond icon]" -
## the diamond icon is VP (rulebook p47/49: "destroying a Legion/Horde
## gives VP per its bottom-card text"), not a resource - encoded as
## on_destroy_vp below. A few cards' on-destroy text has additional
## effects beyond flat VP (e.g. The Imperial Guard also destroys a unit);
## those extra clauses are captured in on_destroy_text but not executed.

class CombatCard:
	var initiative: int = 0
	var max_threat: int = 7
	var archery_skipped: bool = false   # Oda the Fallen: "Skip the Archery round"
	var copies_enemy_dice: bool = false  # The Courtesan: no dice table of her own
	var dice: Dictionary = {}  # threat(int) -> {"archery": Array[String], "clash": Array[String]}
	var passive_text: String = ""
	var godpower_text: String = ""
	var on_destroy_vp: int = 0
	var on_destroy_text: String = ""


static func get_card(name: String) -> CombatCard:
	return _CARDS.get(name)


static func has_card(name: String) -> bool:
	return _CARDS.has(name)


static func _c(archery: Array, clash: Array) -> Dictionary:
	var a: Array[String] = []
	for s: Variant in archery:
		a.append(str(s))
	var c: Array[String] = []
	for s: Variant in clash:
		c.append(str(s))
	return {"archery": a, "clash": c}


static var _CARDS: Dictionary = _build()

static func _build() -> Dictionary:
	var d: Dictionary = {}

	var courtesan := CombatCard.new()
	courtesan.initiative = 2
	courtesan.copies_enemy_dice = true
	courtesan.godpower_text = "Place 1 Activation Token on another Legion or Horde card with the fewest Tokens. Once per round."
	courtesan.on_destroy_vp = 0  # "Roll your Hero Dice and gain 1 VP for every Skull" - roll-based, not flat.
	courtesan.on_destroy_text = "If destroyed, remove her Target. Roll your Hero Dice and gain 1 VP for every Skull."
	d["The Courtesan"] = courtesan

	var warlock := CombatCard.new()
	warlock.initiative = 5
	warlock.passive_text = "The Warlock is always adjacent to any hex."
	warlock.godpower_text = "Remove 1 Wall, Tower, Haven or 1 Threat here. After damage."
	warlock.dice = {
		7: _c(["blue", "yellow"], ["purple", "purple", "blue", "red", "yellow"]),
		6: _c(["yellow", "blue"], ["purple", "blue", "red", "yellow", "yellow"]),
		5: _c(["yellow", "white"], ["purple", "blue", "yellow", "yellow", "yellow"]),
		4: _c(["blue", "yellow"], ["purple", "blue", "yellow", "yellow", "white"]),
		3: _c(["yellow", "white"], ["purple", "blue", "yellow", "white"]),
		2: _c(["white", "white"], ["purple", "blue", "white"]),
		1: _c(["white"], ["purple", "white"]),
	}
	warlock.on_destroy_vp = 3
	warlock.on_destroy_text = "If destroyed, remove his Target and gain 3 VP."
	d["The Warlock"] = warlock

	var spymaster := CombatCard.new()
	spymaster.initiative = 8
	spymaster.passive_text = "Enemies can not use Shield."
	spymaster.godpower_text = "Discard your most expensive Item or a Feat without using it, or lose 2 Threat. Before damage, once per round."
	spymaster.dice = {
		7: _c(["white", "white", "white", "white"], ["purple", "purple", "blue", "red", "red"]),
		6: _c(["white", "white", "white", "white"], ["purple", "purple", "blue", "blue", "red"]),
		5: _c(["white", "white", "white"], ["purple", "blue", "blue", "blue", "red"]),
		4: _c(["white", "white", "white"], ["purple", "blue", "blue", "red", "white"]),
		3: _c(["white", "white"], ["purple", "blue", "red", "white"]),
		2: _c(["white", "white"], ["purple", "red", "white"]),
		1: _c(["white"], ["purple", "white"]),
	}
	spymaster.on_destroy_vp = 4
	spymaster.on_destroy_text = "If destroyed, discard the flipped Items from the Market, refill it, remove his Target, and gain 4 VP."
	d["The Spymaster"] = spymaster

	var assassin := CombatCard.new()
	assassin.initiative = 10
	assassin.passive_text = "Gain 2 Red dice during Archery on Badlands."
	assassin.godpower_text = "Counts as 2 Skulls. Once per round."
	assassin.dice = {
		7: _c(["white", "blue"], ["black", "purple", "blue", "red", "red"]),
		6: _c(["blue", "white"], ["purple", "blue", "red", "red", "yellow"]),
		5: _c(["blue", "white"], ["purple", "blue", "red", "yellow", "yellow"]),
		4: _c(["blue", "white"], ["purple", "blue", "red", "yellow", "white"]),
		3: _c(["white", "white"], ["blue", "red", "yellow", "white"]),
		2: _c(["white", "white"], ["blue", "red", "white"]),
		1: _c(["white"], ["blue", "red"]),
	}
	assassin.on_destroy_vp = 3
	assassin.on_destroy_text = "If destroyed, remove her Target and gain 3 VP."
	d["The Assassin"] = assassin

	var imperial_guard := CombatCard.new()
	imperial_guard.initiative = 12
	imperial_guard.passive_text = "Gain 1 Red die during Archery on Badlands."
	imperial_guard.godpower_text = "Counts as 2 Shields. Before damage, once per round."
	imperial_guard.dice = {
		7: _c(["white", "blue"], ["purple", "purple", "purple", "blue", "blue", "red"]),
		6: _c(["blue", "white"], ["purple", "purple", "blue", "blue", "blue", "red"]),
		5: _c(["blue", "white"], ["purple", "blue", "blue", "red", "yellow", "yellow"]),
		4: _c(["blue", "white"], ["blue", "blue", "red", "yellow", "white"]),
		3: _c(["white", "white"], ["blue", "red", "yellow", "white", "white"]),
		2: _c(["white", "white"], ["blue", "red", "white", "white"]),
		1: _c(["white"], ["red", "white", "white"]),
	}
	imperial_guard.on_destroy_vp = 5
	imperial_guard.on_destroy_text = "If destroyed, remove its Target and gain 5 VP. Destroy 1 non-Imperial Unit or Threat here."
	d["The Imperial Guard"] = imperial_guard

	var mage_breaker := CombatCard.new()
	mage_breaker.initiative = 18
	mage_breaker.passive_text = "Every time she retargets, remove 1 Sea Tower from the game."
	mage_breaker.godpower_text = "Gain 1 Skull for each Bolt on ALL dice."
	mage_breaker.dice = {
		7: _c(["black", "yellow"], ["black", "black", "blue", "blue", "blue"]),
		6: _c(["black", "yellow"], ["black", "blue", "blue", "blue", "yellow"]),
		5: _c(["black", "black", "yellow"], ["black", "blue", "blue", "yellow", "yellow"]),
		4: _c(["black", "black", "yellow"], ["black", "blue", "blue", "yellow", "white"]),
		3: _c(["black", "black", "yellow"], ["black", "blue", "yellow", "white"]),
		2: _c(["black", "black", "yellow"], ["black", "blue", "white"]),
		1: _c(["black", "yellow"], ["black", "yellow", "white"]),
	}
	mage_breaker.on_destroy_vp = 1
	mage_breaker.on_destroy_text = "If destroyed, remove her Target and gain 1 VP and 1 VP per Aether on this card (approx.). Discard the Market."
	d["The Mage Breaker"] = mage_breaker

	var executioner := CombatCard.new()
	executioner.initiative = 20
	executioner.passive_text = "Gain 1 Purple die if there is a Target here."
	executioner.godpower_text = "Remove your most expensive Unit, from play or the reserve, from the game or lose 2 Threat. After damage, once per combat."
	executioner.dice = {
		7: _c(["white", "blue"], ["black", "purple", "blue", "red", "red"]),
		6: _c(["blue", "white"], ["black", "purple", "blue", "red", "yellow"]),
		5: _c(["blue", "white"], ["black", "purple", "yellow", "yellow"]),
		4: _c(["blue", "white"], ["black", "purple", "yellow", "yellow"]),
		3: _c(["white", "white"], ["black", "purple", "yellow", "yellow"]),
		2: _c(["white", "white"], ["black", "purple"]),
		1: _c(["white"], ["black"]),
	}
	executioner.on_destroy_vp = 3
	executioner.on_destroy_text = "If destroyed, remove her Target and gain 3 VP."
	d["The Executioner"] = executioner

	var new_emperor := CombatCard.new()
	new_emperor.initiative = 29
	new_emperor.passive_text = "Gain 2 Red dice during Archery on Badlands."
	new_emperor.godpower_text = "The Empire gains 2 VP. Once per round."
	new_emperor.dice = {
		7: _c(["white", "blue"], ["black", "black", "purple", "blue", "red"]),
		6: _c(["blue", "white"], ["black", "purple", "blue", "red", "red"]),
		5: _c(["blue", "white"], ["black", "purple", "blue", "red", "red"]),
		4: _c(["blue", "white"], ["black", "purple", "blue", "red", "yellow"]),
		3: _c(["white", "white"], ["purple", "blue", "red", "yellow", "white"]),
		2: _c(["white", "white"], ["purple", "blue", "yellow", "white"]),
		1: _c(["white"], ["purple", "blue", "yellow"]),
	}
	new_emperor.on_destroy_vp = 5
	new_emperor.on_destroy_text = "If destroyed, remove his Target and gain 5 VP. Place 2 Garrisons on The Capital."
	d["The New Emperor"] = new_emperor

	var lichqueen := CombatCard.new()
	lichqueen.initiative = 3
	lichqueen.godpower_text = "Every Horde in play (including her) gains 1 Threat. Before damage, once per round."
	lichqueen.dice = {
		7: _c(["white", "white", "white"], ["black", "purple", "red", "red", "yellow"]),
		6: _c(["white", "white"], ["purple", "red", "red", "yellow", "yellow"]),
		5: _c(["white", "white"], ["purple", "red", "yellow", "yellow", "white"]),
		4: _c(["white", "white"], ["purple", "yellow", "yellow", "white", "white"]),
		3: _c(["white"], ["purple", "yellow", "white", "white", "white"]),
		2: _c(["white"], ["yellow", "white", "white", "white"]),
		1: _c(["white"], ["white", "white", "white"]),
	}
	lichqueen.on_destroy_vp = 3
	lichqueen.on_destroy_text = "If destroyed, gain 3 VP."
	d["Lichqueen"] = lichqueen

	var coven := CombatCard.new()
	coven.initiative = 9
	coven.godpower_text = "Flip all your Feats and Items without using any of them, or lose 2 Threat. Before damage, once per combat."
	coven.dice = {
		7: _c(["yellow", "yellow", "yellow", "yellow"], ["purple", "purple", "red", "blue", "blue"]),
		6: _c(["yellow", "yellow", "yellow"], ["purple", "red", "blue", "blue", "blue"]),
		5: _c(["yellow", "yellow", "yellow"], ["purple", "red", "blue", "blue", "blue"]),
		4: _c(["yellow", "yellow"], ["purple", "blue", "blue", "blue", "white"]),
		3: _c(["yellow", "yellow"], ["purple", "blue", "blue", "white"]),
		2: _c(["yellow"], ["purple", "blue", "white"]),
		1: _c(["yellow"], ["purple", "white"]),
	}
	coven.on_destroy_vp = 4
	coven.on_destroy_text = "If destroyed, gain 4 VP. Every player gains their placed resource back."
	d["Coven of Yssat"] = coven

	var counter := CombatCard.new()
	counter.initiative = 13
	counter.godpower_text = "Place 2 Skeletons on any empty hex. After damage, once per round."
	counter.dice = {
		7: _c(["white", "white", "white", "white", "white"], ["black", "purple", "purple", "purple", "blue"]),
		6: _c(["white", "white", "white", "white"], ["purple", "purple", "purple", "blue", "yellow"]),
		5: _c(["white", "white", "white", "white"], ["purple", "purple", "blue", "blue", "yellow"]),
		4: _c(["white", "white", "white"], ["purple", "blue", "blue", "yellow", "yellow"]),
		3: _c(["white", "white", "white"], ["purple", "blue", "blue", "yellow"]),
		2: _c(["white", "white"], ["blue", "blue", "yellow"]),
		1: _c(["white", "white"], ["blue", "blue"]),
	}
	counter.on_destroy_vp = 2
	counter.on_destroy_text = "If destroyed, place 2 Skeletons here, and gain 2 VP."
	d["Counter of Omens"] = counter

	var bloodwyrm := CombatCard.new()
	bloodwyrm.initiative = 21
	bloodwyrm.godpower_text = "Place 1 Curse here. After damage, once per combat."
	bloodwyrm.dice = {
		7: _c(["red", "red", "red"], ["black", "purple", "red", "red", "red"]),
		6: _c(["red", "red", "red"], ["purple", "red", "red", "red", "red"]),
		5: _c(["red", "red"], ["red", "red", "red", "red", "red"]),
		4: _c(["red", "red"], ["red", "red", "red", "red"]),
		3: _c(["red"], ["red", "red", "red"]),
		2: _c(["red"], ["red", "red"]),
		1: _c(["red"], ["red"]),
	}
	bloodwyrm.on_destroy_vp = 4
	bloodwyrm.on_destroy_text = "If destroyed, gain 4 VP."
	d["Bloodwyrm"] = bloodwyrm

	var siren := CombatCard.new()
	siren.initiative = 25
	siren.passive_text = "Enemies can not use Bolt."
	siren.godpower_text = "Place The Siren on the closest empty hex. After damage, once per combat."
	siren.dice = {
		7: _c(["purple", "red"], ["purple", "yellow", "white", "white", "white"]),
		6: _c(["purple", "red"], ["purple", "yellow", "white", "white", "white"]),
		5: _c(["red", "red"], ["purple", "yellow", "white", "white", "white"]),
		4: _c(["red"], ["purple", "yellow", "white", "white", "white"]),
		3: _c(["blue", "blue"], ["purple", "yellow", "white", "white"]),
		2: _c(["blue", "blue"], ["purple", "white", "white"]),
		1: _c(["blue"], ["purple", "white"]),
	}
	siren.on_destroy_vp = 1
	siren.on_destroy_text = "If destroyed, gain 1 VP and 1 VP per Ally."
	d["Siren"] = siren

	var banished := CombatCard.new()
	banished.initiative = 26
	banished.max_threat = 5  # printed table only goes up to Threat 5, not 7 - a real per-card cap.
	banished.passive_text = "Reroll up to 2 blanks. Once per round."
	banished.godpower_text = "Destroy the most expensive Unit or 2 Threat here. Once per round, before damage."
	banished.dice = {
		5: _c(["blue", "blue"], ["purple", "red", "white", "white", "white"]),
		4: _c(["blue", "blue"], ["purple", "red", "white", "white"]),
		3: _c(["blue", "blue"], ["purple", "red", "white"]),
		2: _c(["blue"], ["red", "white"]),
		1: _c(["blue"], ["red"]),
	}
	banished.on_destroy_vp = 3
	banished.on_destroy_text = "If destroyed, gain 3 VP. Once per game: place this card at the bottom of the Horde deck (instead of removing it)."
	d["Banished"] = banished

	var false_messiah := CombatCard.new()
	false_messiah.initiative = 28
	false_messiah.passive_text = "Gain 1 Red die on a hex with a Haven or Imperial Units."
	false_messiah.godpower_text = "Remove 1 Haven of any player from play. Once per combat."
	false_messiah.dice = {
		7: _c(["yellow", "white"], ["black", "purple", "purple", "red", "blue"]),
		6: _c(["yellow", "white"], ["purple", "purple", "red", "blue", "white"]),
		5: _c(["white", "white", "white"], ["purple", "red", "blue", "blue", "white"]),
		4: _c(["white", "white"], ["purple", "red", "blue", "white"]),
		3: _c(["white", "white"], ["red", "blue", "blue", "white"]),
		2: _c(["white", "white"], ["blue", "blue", "white"]),
		1: _c(["white"], ["blue", "white", "white"]),
	}
	false_messiah.on_destroy_vp = 3
	false_messiah.on_destroy_text = "If destroyed, gain 3 VP and 1 of your Units here."
	d["False Messiah"] = false_messiah

	var oda := CombatCard.new()
	oda.initiative = 30
	oda.archery_skipped = true
	oda.godpower_text = "Counts as 2 Skulls."
	oda.dice = {
		7: _c([], ["black", "black", "purple", "purple", "red"]),
		6: _c([], ["black", "purple", "purple", "red", "red"]),
		5: _c([], ["black", "purple", "red", "red", "yellow"]),
		4: _c([], ["black", "red", "red", "yellow"]),
		3: _c([], ["black", "red", "yellow"]),
		2: _c([], ["black", "yellow"]),
		1: _c([], ["black"]),
	}
	oda.on_destroy_vp = 5
	oda.on_destroy_text = "If destroyed, gain 5 VP."
	d["Oda the Fallen"] = oda

	return d
