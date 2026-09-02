class_name PlaceOrReinforceOp
extends EffectOp

## Encodes the single most common Hex-effect clause verbatim: "If Empty,
## place N <kind> here; if not Reinforce here." Deliberately ONE op
## (not a Conditional wrapping two PlaceToken ops) since the two branches
## always differ only in count-vs-reinforce-by-one, never in kind/target -
## decomposing it generically would just duplicate the same shape on every
## card that uses this wording (most of the Core Normal hexes do).
##
## "Empty" per rulebook p50 general placement rules: no other Units at all
## on the hex (Garrison/Skeleton/Legion/Horde/player Units - Heroes don't
## count). "Reinforce" = add exactly 1 more of the matching type,
## regardless of the card's own placement count - also per p50, which
## takes precedence over the specific count text when reinforcing.
##
## kind in {"Garrison","Skeleton"} - Curse doesn't use this phrasing
## anywhere in the sampled Core Hex text (it has its own dedicated
## mechanic, see rulebook p49), so isn't supported here.
var kind: String = "Garrison"
var count: int = 1
## "here" (default) is the only target this op currently supports - the
## rare "on an Empty Hex with no X" (a DIFFERENT hex, chosen somehow) is a
## separate op, see PlaceTokenOp's target_mode.


func _init(p_kind: String = "Garrison", p_count: int = 1) -> void:
	kind = p_kind
	count = p_count


func execute(ctx: EffectContext) -> void:
	if not ctx.has_hex_coord:
		ctx.log("PlaceOrReinforceOp: no hex_coord in context, skipped")
		return
	var tile: HexTileState = ctx.state.ensure_hex(ctx.hex_coord)
	var empty: bool = EffectUtil.hex_is_empty_of_units(ctx.state, ctx.hex_coord)
	if kind == "Garrison":
		if empty:
			tile.garrison_level = mini(3, count)
		else:
			tile.garrison_level = mini(3, tile.garrison_level + 1)
	elif kind == "Skeleton":
		if empty:
			tile.skeleton_count = mini(2, count)
		else:
			tile.skeleton_count = mini(2, tile.skeleton_count + 1)
	else:
		push_error("PlaceOrReinforceOp: unsupported kind '%s'" % kind)
		return
	ctx.log("%s %s at %s (empty=%s)" % ["Placed" if empty else "Reinforced", kind, ctx.hex_coord, empty])


func describe() -> String:
	return "If empty place %d %s here, else reinforce" % [count, kind]
