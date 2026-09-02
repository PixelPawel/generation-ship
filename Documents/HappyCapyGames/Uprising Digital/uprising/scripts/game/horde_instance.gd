class_name HordeInstance
extends RefCounted

var id: int = 0
var card_name: String = ""
var threat: int = 1
var coord: Vector2i = Vector2i.ZERO
var activation_tokens: int = 0


func to_dict() -> Dictionary:
	return {
		"id": id, "card_name": card_name, "threat": threat,
		"coord": {"x": coord.x, "y": coord.y}, "activation_tokens": activation_tokens,
	}


static func from_dict(d: Dictionary) -> HordeInstance:
	var s := HordeInstance.new()
	s.id = d.get("id", 0)
	s.card_name = d.get("card_name", "")
	s.threat = d.get("threat", 1)
	var c: Dictionary = d.get("coord", {"x": 0, "y": 0})
	s.coord = Vector2i(c.get("x", 0), c.get("y", 0))
	s.activation_tokens = d.get("activation_tokens", 0)
	return s
