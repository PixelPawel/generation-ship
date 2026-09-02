class_name DruidCard
extends Resource

## The source CSV's header names column 0 "Box", but its actual values are
## EN/DE language codes, not Core/Titans/Arch box values - same class of
## header/data mismatch as QuestCard's mislabeled "a" column. There is no
## real Box column here; every row is Core-scope (matches the rulebook's
## flat "9 Druid cards" component count, no expansion Druids in this data).
@export var lang: String = ""
@export var card_name: String = ""
@export var advanced: String = ""
@export var archery_and_clash: String = ""
@export var restrictions: String = ""
@export var refresh_phase: String = ""
