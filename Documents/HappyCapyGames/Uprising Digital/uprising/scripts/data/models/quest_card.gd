class_name QuestCard
extends Resource

## The source CSV's first column header is a literal typo "a" (should be
## "Lang") - CardDatabase reads this column positionally, not by name.
@export var lang: String = ""
@export var box: String = ""
@export var card_name: String = ""
@export var flavour: String = ""
@export var immediate_effect: String = ""
@export var solve: String = ""
@export var failure: String = ""
@export var successes: String = ""
@export var skulls: String = ""
@export var skull_bonus: String = ""
@export var shields: String = ""
@export var shield_bonus: String = ""
@export var bolts: String = ""
@export var bolt_bonus: String = ""
@export var terrain_bonus: String = ""
