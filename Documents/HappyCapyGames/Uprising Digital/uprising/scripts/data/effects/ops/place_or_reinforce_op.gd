class_name PlaceOrReinforceOp
extends EffectOp

## "If empty, place N <kind> here; if not reinforce here" (rulebook p22):
## empty = no Units of any kind (Heroes don't count). Reinforce = "if there
## are Units of The Empire or Chaos here, add 1 more of the same type: a hex
## with any Garrisons or Legions adds 1 Garrison, a hex with any Skeletons
## or Hordes adds 1 Skeleton. Player Units are never reinforced." - so the
## card's own <kind> only matters on an empty hex.
var kind: String = "Garrison"
var count: int = 1


func _init(p_kind: String = "Garrison", p_count: int = 1) -> void:
	kind = p_kind
	count = p_count


func execute(ctx: EffectContext) -> void:
	if not ctx.has_hex_coord:
		ctx.log("PlaceOrReinforceOp: no hex_coord in context, skipped")
		return
	var coord: Vector2i = ctx.hex_coord
	var tile: HexTileState = ctx.state.ensure_hex(coord)
	if EffectUtil.hex_is_empty_of_units(ctx.state, coord):
		if kind == "Garrison":
			NemesisAI.add_garrisons(ctx.state, coord, count)
		else:
			NemesisAI.add_skeletons(ctx.state, ctx.card_db, coord, count)
		ctx.log("Placed %d %s at %s (empty)" % [count, kind, coord])
		return
	var empire_here: bool = tile.garrison_level > 0
	var chaos_here: bool = tile.skeleton_count > 0
	for n: Variant in EffectUtil.nemesis_at(ctx.state, coord):
		if n is LegionInstance:
			empire_here = true
		else:
			chaos_here = true
	if empire_here:
		NemesisAI.add_garrisons(ctx.state, coord, 1)
		ctx.log("Reinforced %s with 1 Garrison" % coord)
	elif chaos_here:
		NemesisAI.add_skeletons(ctx.state, ctx.card_db, coord, 1)
		ctx.log("Reinforced %s with 1 Skeleton" % coord)
	else:
		ctx.log("%s holds only player Units - nothing to reinforce" % coord)


func describe() -> String:
	return "If empty place %d %s here, else reinforce" % [count, kind]
