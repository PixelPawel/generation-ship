class_name LegionInstance
extends RefCounted
## A Legion actually in play. `card_name` links back to LegionCard in
## CardDatabase for its text/abilities; this holds the parts that change.

const NO_TARGET := Vector2i(-9999, -9999)

var id: int = -1
var card_name: String = ""
var threat: int = 0
var activation_tokens: int = 0
var coord: Vector2i = Vector2i.ZERO
var target_faction: String = ""  # "" = no Target assigned yet
var target_hex: Vector2i = NO_TARGET


func to_dict() -> Dictionary:
	return {
		"id": id,
		"card_name": card_name,
		"threat": threat,
		"activation_tokens": activation_tokens,
		"coord": [coord.x, coord.y],
		"target_faction": target_faction,
		"target_hex": [target_hex.x, target_hex.y],
	}


static func from_dict(d: Dictionary) -> LegionInstance:
	var l := LegionInstance.new()
	l.id = d.get("id", -1)
	l.card_name = d.get("card_name", "")
	l.threat = d.get("threat", 0)
	l.activation_tokens = d.get("activation_tokens", 0)
	var c: Array = d.get("coord", [0, 0])
	l.coord = Vector2i(c[0], c[1])
	l.target_faction = d.get("target_faction", "")
	var t: Array = d.get("target_hex", [NO_TARGET.x, NO_TARGET.y])
	l.target_hex = Vector2i(t[0], t[1])
	return l
