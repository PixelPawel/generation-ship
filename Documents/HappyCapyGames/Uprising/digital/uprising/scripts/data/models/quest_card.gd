class_name QuestCard
extends Resource

@export var lang: String = ""
@export var box: String = ""
@export var card_name: String = ""
@export var flavor: String = ""
@export var immediate_effect: String = ""
@export var solve: String = ""
@export var failure: String = ""
## Number of goal successes required overall to Solve the Quest.
@export var successes_needed: int = 0
@export var skulls_threshold: int = 0
@export var skulls_reward: String = ""
@export var shields_threshold: int = 0
@export var shields_reward: String = ""
@export var bolts_threshold: int = 0
@export var bolts_reward: String = ""
## Condition text for an extra bonus die (e.g. "If your Hero is on a Sea Tower +1 BRONZE").
@export var terrain_bonus: String = ""
@export var texture_path: String = ""
