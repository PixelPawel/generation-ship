class_name DruidCard
extends Resource

## The source sheet stores EN/DE in the "Box" column for Druids (there is no
## Core/Arch/Titans box variant for this category), so this doubles as lang.
@export var lang: String = ""
@export var card_name: String = ""
@export var godpower: String = ""
@export var restrictions: String = ""
## Condition that places 1 AETHER on this Druid during the Refresh Phase.
@export var refresh_phase: String = ""
@export var texture_path: String = ""
