class_name PlaceUnitOp
extends EffectOp

## "Gain 1 Basic Unit on a Haven or an Empty Explored Hex." - places the
## faction's Basic Warrior (PlayerboardTable.default_unit) until a UI can
## ask which Basic Unit (Warrior or Archer) the player wants. Capped at
## 5 Units per hex by HexTileState.add_units. target_mode "here" only for
## now; a real "choose a
## Haven or empty hex" picker is a Milestone 5 UI concern, deferred to
## ctx.choice_resolver same as other multi-target ops.
var count: int = 1
var target_mode: String = "here"


func _init(p_count: int = 1, p_target_mode: String = "here") -> void:
	count = p_count
	target_mode = p_target_mode


func execute(ctx: EffectContext) -> void:
	var coord: Vector2i
	if target_mode == "here" and ctx.has_hex_coord:
		coord = ctx.hex_coord
	elif ctx.choice_resolver.is_valid():
		var chosen: Variant = ctx.choice_resolver.call(target_mode, [])
		if not (chosen is Vector2i):
			ctx.log("PlaceUnitOp: no valid target resolved, skipped")
			return
		coord = chosen
	else:
		ctx.log("PlaceUnitOp: target_mode '%s' needs a choice_resolver, none set - skipped" % target_mode)
		return

	var tile: HexTileState = ctx.state.ensure_hex(coord)
	var added: int = tile.add_units(ctx.acting_faction, PlayerboardTable.default_unit(ctx.acting_faction), count)
	ctx.log("%s gains %d Basic Unit(s) on %s" % [ctx.acting_faction, added, coord])


func describe() -> String:
	return "Gain %d Basic Unit (%s)" % [count, target_mode]
