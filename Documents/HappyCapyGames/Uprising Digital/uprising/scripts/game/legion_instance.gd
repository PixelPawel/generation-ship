class_name LegionInstance
extends RefCounted

var id: int = 0
var card_name: String = ""
var threat: int = 1
var coord: Vector2i = Vector2i.ZERO
var activation_tokens: int = 0
## "" = no Target yet, "Capital" = parked at Capital (all factions already targeted).
var target_faction: String = ""


func to_dict() -> Dictionary:
	return {
		"id": id, "card_name": card_name, "threat": threat,
		"coord": {"x": coord.x, "y": coord.y}, "activation_tokens": activation_tokens,
		"target_faction": target_faction,
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
	return s
