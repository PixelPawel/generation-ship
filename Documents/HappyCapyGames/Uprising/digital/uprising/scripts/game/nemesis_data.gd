class_name NemesisData
extends RefCounted
## Initiative (rulebook p27: "Resolve each card in INITIATIVE order, lowest
## to highest" -- Legions and Hordes share ONE combined order, not two
## separate rankings) isn't in the CSV or the source .xlsx (checked both,
## no such column) -- like the dice-color and playerboard-cost tables
## before it, it exists only as print art on each card (the numbered
## starburst, top-left corner; rulebook p45's "CARD ANATOMY" calls it out
## as item 1). Read directly off all 8 Core Legions' and 8 Core Hordes'
## card images (assets/images/.../CARDS_EN/BIG_CARDS_EN/{LEGIONS,HORDES}_EN)
## rather than assumed from the art filenames' own numbering
## (Legions_Core_02_Courtesan.jpg etc.) -- though every card checked out
## against its filename number, so that numbering is confirmed reliable
## for this box, not just guessed.
const INITIATIVE := {
	"The Courtesan": 2,
	"The Lich Queen": 3,
	"The Warlock": 5,
	"The Spymaster": 8,
	"Coven of Yssat": 9,
	"The Assassin": 10,
	"The Imperial Guard": 12,
	"Counter of Omens": 13,
	"The Mage Breaker": 18,
	"The Executioner": 20,
	"Bloodwyrm": 21,
	"The Siren": 25,
	"The Banished": 26,
	"The False Messiah": 28,
	"The New Emperor": 29,
	"Oda the Fallen": 30,
}


## Falls back to a very high number (sorts last, never crashes) for
## anything not in the table above -- e.g. Arch-Nemesis/Titans content,
## outside this project's current Core-box-only scope, or a placeholder
## name used in a test.
static func get_initiative(card_name: String) -> int:
	return INITIATIVE.get(card_name, 999)
