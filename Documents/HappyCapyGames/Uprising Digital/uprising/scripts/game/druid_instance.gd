class_name DruidInstance
extends RefCounted

var card_name: String = ""
var aether: int = 0


func to_dict() -> Dictionary:
	return {"card_name": card_name, "aether": aether}


static func from_dict(d: Dictionary) -> DruidInstance:
	var s := DruidInstance.new()
	s.card_name = d.get("card_name", "")
	s.aether = d.get("aether", 0)
	return s
