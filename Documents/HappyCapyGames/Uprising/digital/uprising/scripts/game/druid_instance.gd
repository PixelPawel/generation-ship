class_name DruidInstance
extends RefCounted
## One of the 4 Druid cards revealed at Setup (rulebook p6: "Place 4 random
## Druid cards face-up"). `card_name` links back to DruidCard in
## CardDatabase for its Godpower/text; `aether` is what DruidData.
## check_condition adds to, 1 at a time, every Refresh Phase its printed
## condition holds -- uncapped, since nothing in the transcribed card text
## says what spends or limits it.

var card_name: String = ""
var aether: int = 0


func to_dict() -> Dictionary:
	return {"card_name": card_name, "aether": aether}


static func from_dict(d: Dictionary) -> DruidInstance:
	var i := DruidInstance.new()
	i.card_name = d.get("card_name", "")
	i.aether = d.get("aether", 0)
	return i
