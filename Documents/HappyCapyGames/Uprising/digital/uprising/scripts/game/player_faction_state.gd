class_name PlayerFactionState
extends RefCounted
## Runtime state for one player's faction. `faction` matches HeroCard.faction /
## PlayerboardData.front ("Druwhn", "Duerkhar", "Mohyar", "Krowh").
## `hero_name` links back to the static HeroCard in CardDatabase.

var faction: String = ""
var hero_name: String = ""
var controlled_by_peer_id: int = -1  # multiplayer peer id of the human controlling this faction

var salt: int = 0
var plunder: int = 0
var food: int = 0
var action_points: int = 0

var might: int = 0
var magic: int = 0
var leadership: int = 0
var guile: int = 0

var feats_in_play: Array[String] = []
var items_in_play: Array[String] = []
var havens: Array[Vector2i] = []
var hero_hex: Vector2i = Vector2i.ZERO

var victory_points: int = 0
var has_passed: bool = false  # passed for the remainder of this Actions Phase


func to_dict() -> Dictionary:
	return {
		"faction": faction,
		"hero_name": hero_name,
		"controlled_by_peer_id": controlled_by_peer_id,
		"salt": salt,
		"plunder": plunder,
		"food": food,
		"action_points": action_points,
		"might": might,
		"magic": magic,
		"leadership": leadership,
		"guile": guile,
		"feats_in_play": feats_in_play.duplicate(),
		"items_in_play": items_in_play.duplicate(),
		"havens": havens.map(func(c: Vector2i) -> Array: return [c.x, c.y]),
		"hero_hex": [hero_hex.x, hero_hex.y],
		"victory_points": victory_points,
		"has_passed": has_passed,
	}


static func from_dict(d: Dictionary) -> PlayerFactionState:
	var s := PlayerFactionState.new()
	s.faction = d.get("faction", "")
	s.hero_name = d.get("hero_name", "")
	s.controlled_by_peer_id = d.get("controlled_by_peer_id", -1)
	s.salt = d.get("salt", 0)
	s.plunder = d.get("plunder", 0)
	s.food = d.get("food", 0)
	s.action_points = d.get("action_points", 0)
	s.might = d.get("might", 0)
	s.magic = d.get("magic", 0)
	s.leadership = d.get("leadership", 0)
	s.guile = d.get("guile", 0)
	s.feats_in_play.assign(d.get("feats_in_play", []))
	s.items_in_play.assign(d.get("items_in_play", []))
	s.havens = []
	for c in d.get("havens", []):
		s.havens.append(Vector2i(c[0], c[1]))
	var hh: Array = d.get("hero_hex", [0, 0])
	s.hero_hex = Vector2i(hh[0], hh[1])
	s.victory_points = d.get("victory_points", 0)
	s.has_passed = d.get("has_passed", false)
	return s
