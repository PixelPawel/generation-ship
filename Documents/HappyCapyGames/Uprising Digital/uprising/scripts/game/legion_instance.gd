class_name LegionInstance
extends RefCounted

var id: int = 0
var card_name: String = ""
var threat: int = 1
var coord: Vector2i = Vector2i.ZERO
var activation_tokens: int = 0
## Its Target token (rulebook p47). target_faction is the player faction
## whose Haven at target_coord it hunts (retargets when that Haven goes),
## "Capital" once parked on The Capital for good, or "" for a fixed hex
## that never retargets. has_target is false until a Target is placed.
var target_faction: String = ""
var target_coord: Vector2i = Vector2i.ZERO
var has_target: bool = false


func to_dict() -> Dictionary:
	return {
		"id": id, "card_name": card_name, "threat": threat,
		"coord": {"x": coord.x, "y": coord.y}, "activation_tokens": activation_tokens,
		"target_faction": target_faction, "has_target": has_target,
		"target_coord": {"x": target_coord.x, "y": target_coord.y},
	}


static func from_dict(d: Dictionary) -> LegionInstance:
	var s := LegionInstance.new()
	s.id = d.get("id", 0)
	s.card_name = d.get("card_name", "")
	s.threat = d.get("threat", 1)
	var c: Dictionary = d.get("coord", {"x": 0, "y": 0})
	s.coord = Vector2i(c.get("x", 0), c.get("y", 0))
	s.activation_tokens = d.get("activation_tokens", 0)
	s.target_faction = d.get("target_faction", "")
	s.has_target = bool(d.get("has_target", not s.target_faction.is_empty()))
	var t: Dictionary = d.get("target_coord", {"x": 0, "y": 0})
	s.target_coord = Vector2i(int(t.get("x", 0)), int(t.get("y", 0)))
	return s
