class_name PlaceTokenOp
extends EffectOp

## "Place N Garrisons/Skeletons/Curses ..." with the rulebook's placement
## rules (p46-51), delegated to NemesisAI:
## - target_mode "here": on ctx.hex_coord - Garrisons stack to 3 (a 4th
##   scores The Empire 1 VP), 3 Skeletons become a Horde, a Curse destroys
##   Garrisons and removes any Haven (already Cursed -> Chaos 1 VP);
## - "with_others" (Skeletons): onto hexes that already have Skeletons;
## - "empty_no_x" / "chosen_empty_hex_no_x" (Garrisons): spread over empty
##   hexes with no X.
var kind: String = "Garrison"
var count: int = 1
var target_mode: String = "here"


func _init(p_kind: String = "Garrison", p_count: int = 1, p_target_mode: String = "here") -> void:
	kind = p_kind
	count = p_count
	target_mode = p_target_mode


func execute(ctx: EffectContext) -> void:
	match target_mode:
		"with_others":
			NemesisAI.place_skeleton_with_others(ctx.state, ctx.card_db, count)
			ctx.log("Placed %d Skeleton(s) with other Skeletons" % count)
			return
		"empty_no_x", "chosen_empty_hex_no_x":
			for _i: int in range(count):
				NemesisAI.place_garrison_on_empty_hex(ctx.state)
			ctx.log("Placed %d Garrison(s) on empty hexes with no X" % count)
			return
	if not ctx.has_hex_coord:
		ctx.log("PlaceTokenOp: no hex_coord in context, skipped")
		return
	var coord: Vector2i = ctx.hex_coord
	match kind:
		"Garrison":
			NemesisAI.add_garrisons(ctx.state, coord, count)
		"Skeleton":
			NemesisAI.add_skeletons(ctx.state, ctx.card_db, coord, count)
		"Curse":
			NemesisAI.place_curse_on(ctx.state, ctx.card_db, coord)
		_:
			push_error("PlaceTokenOp: unsupported kind '%s'" % kind)
			return
	ctx.log("Placed %d %s at %s" % [count, kind, coord])


func describe() -> String:
	return "Place %d %s (%s)" % [count, kind, target_mode]
