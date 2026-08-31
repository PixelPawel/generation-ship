class_name HordeInstance
extends RefCounted
## A Horde actually in play. `card_name` links back to HordeCard in
## CardDatabase. Hordes have no Target (unlike Legions) -- they always move
## toward the weakest nearby prey without moving farther from The Capital.

var id: int = -1
var card_name: String = ""
var threat: int = 0
var activation_tokens: int = 0
var coord: Vector2i = Vector2i.ZERO


func to_dict() -> Dictionary:
	return {
		"id": id,
		"card_name": card_name,
		"threat": threat,
		"activation_tokens": activation_tokens,
		"coord": [coord.x, coord.y],
	}


static func from_dict(d: Dictionary) -> HordeInstance:
	var h := HordeInstance.new()
	h.id = d.get("id", -1)
	h.card_name = d.get("card_name", "")
	h.threat = d.get("threat", 0)
	h.activation_tokens = d.get("activation_tokens", 0)
	var c: Array = d.get("coord", [0, 0])
	h.coord = Vector2i(c[0], c[1])
	return h
