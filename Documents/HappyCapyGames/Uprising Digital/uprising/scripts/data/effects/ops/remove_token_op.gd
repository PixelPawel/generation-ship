class_name RemoveTokenOp
extends EffectOp

## "Remove any Skeletons/Garrisons here." kind in {"Garrison","Skeleton"}.
var kind: String = "Skeleton"


func _init(p_kind: String = "Skeleton") -> void:
	kind = p_kind


func execute(ctx: EffectContext) -> void:
	if not ctx.has_hex_coord:
		return
	var tile: HexTileState = ctx.state.get_hex(ctx.hex_coord)
	if tile == null:
		return
	match kind:
		"Garrison":
			tile.garrison_level = 0
		"Skeleton":
			tile.skeleton_count = 0
	ctx.log("Removed all %s at %s" % [kind, ctx.hex_coord])


func describe() -> String:
	return "Remove any %s here" % kind
