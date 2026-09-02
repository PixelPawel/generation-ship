class_name PlaceTokenOp
extends EffectOp

## Unconditional placement (no empty/reinforce branching - see
## PlaceOrReinforceOp for that pattern). kind in {"Garrison","Skeleton","Curse"}.
## target_mode "here" (default) uses ctx.hex_coord; "chosen_empty_hex" defers
## to ctx.choice_resolver("empty_hex", [...]) for cards like Golgardei's
## "Place 2 Garrisons on Empty Hexes with no X" (a DIFFERENT hex than the
## one triggering the effect) - with no resolver set, this is a documented
## no-op (logged, not silently dropped), matching the project's existing
## choice-resolver boundary rather than guessing a target.
var kind: String = "Garrison"
var count: int = 1
var target_mode: String = "here"


func _init(p_kind: String = "Garrison", p_count: int = 1, p_target_mode: String = "here") -> void:
	kind = p_kind
	count = p_count
	target_mode = p_target_mode


func execute(ctx: EffectContext) -> void:
	var coord: Vector2i
	if target_mode == "here":
		if not ctx.has_hex_coord:
			ctx.log("PlaceTokenOp: no hex_coord in context, skipped")
			return
		coord = ctx.hex_coord
	else:
		if not ctx.choice_resolver.is_valid():
			ctx.log("PlaceTokenOp: target_mode '%s' needs a choice_resolver, none set - skipped" % target_mode)
			return
		var chosen: Variant = ctx.choice_resolver.call(target_mode, [])
		if not (chosen is Vector2i):
			ctx.log("PlaceTokenOp: choice_resolver returned no valid hex - skipped")
			return
		coord = chosen

	var tile: HexTileState = ctx.state.ensure_hex(coord)
	match kind:
		"Garrison":
			tile.garrison_level = mini(3, tile.garrison_level + count)
		"Skeleton":
			tile.skeleton_count = mini(2, tile.skeleton_count + count)
		"Curse":
			tile.curse = true
		_:
			push_error("PlaceTokenOp: unsupported kind '%s'" % kind)
			return
	ctx.log("Placed %d %s at %s" % [count, kind, coord])


func describe() -> String:
	return "Place %d %s (%s)" % [count, kind, target_mode]
