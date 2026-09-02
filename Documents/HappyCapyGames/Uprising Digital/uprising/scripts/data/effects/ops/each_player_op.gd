class_name EachPlayerOp
extends EffectOp

## Runs `ops` once per player faction, with that player temporarily as
## ctx.acting_faction (restored after). exclude_self skips whichever
## faction is ctx.acting_faction when this op itself runs - "Each OTHER
## Player gains 1 FOOD" vs "Each Player draws 1 Feat".
var ops: Array[EffectOp] = []
var exclude_self: bool = false


func _init(p_ops: Array[EffectOp] = [], p_exclude_self: bool = false) -> void:
	ops = p_ops
	exclude_self = p_exclude_self


func execute(ctx: EffectContext) -> void:
	var original_faction: String = ctx.acting_faction
	for p: PlayerFactionState in ctx.state.players:
		if exclude_self and p.faction == original_faction:
			continue
		ctx.acting_faction = p.faction
		for op: EffectOp in ops:
			op.execute(ctx)
	ctx.acting_faction = original_faction


func describe() -> String:
	return "Each %s player: %s" % ["other" if exclude_self else "", ", ".join(ops.map(func(o: EffectOp) -> String: return o.describe()))]
