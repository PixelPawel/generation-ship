class_name HexCard
extends Resource

@export var lang: String = ""
@export var box: String = ""
@export var card_name: String = ""
## "Home", "Sea Tower", "Normal", etc.
@export var hex_type: String = ""
@export var flavor: String = ""
@export var ongoing_effect: String = ""
## The Explore effect, read aloud when the hex is flipped.
@export var effect: String = ""
@export var terrain: String = ""
## Generic resource-icon count shown on the hex art (distinct from the Salt/Plunder/Food columns).
@export var resources: int = 0
@export var salt: int = 0
@export var plunder: int = 0
@export var food: int = 0
## Bonus VP / Aether / other text shown on the hex.
@export var special: String = ""
## Which faction (Empire/Chaos) places a Unit here if Explored while empty.
@export var side: String = ""
## True if this hex can never gain a Haven (X icon).
@export var no_haven: bool = false
@export var texture_path: String = ""
