class_name DruidInstance
extends RefCounted

var card_name: String = ""
var aether: int = 0
## Flipped face-down (Imperial Inquisition): no Aether, no Godpower.
var face_down: bool = false


func to_dict() -> Dictionary:
	return {"card_name": card_name, "aether": aether, "face_down": face_down}


static func from_dict(d: Dictionary) -> DruidInstance:
	var s := DruidInstance.new()
	s.card_name = d.get("card_name", "")
	s.aether = d.get("aether", 0)
	s.face_down = bool(d.get("face_down", false))
	return s
