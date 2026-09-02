class_name ConditionalOp
extends EffectOp

## predicate: Callable(ctx: EffectContext) -> bool. Kept as a plain
## Callable rather than a Predicate class hierarchy - EffectUtil's static
## functions (hex_is_empty_of_units, nemesis_vp_meets_players, etc.) are
## meant to be wrapped in a lambda at construction time, e.g.:
##   ConditionalOp.new(func(c): return EffectUtil.card_count_in_play(c.state,"Horde") >= 1, [...])
var predicate: Callable = Callable()
var then_ops: Array[EffectOp] = []
var else_ops: Array[EffectOp] = []


func _init(p_predicate: Callable = Callable(), p_then_ops: Array[EffectOp] = [], p_else_ops: Array[EffectOp] = []) -> void:
	predicate = p_predicate
	then_ops = p_then_ops
	else_ops = p_else_ops


func execute(ctx: EffectContext) -> void:
	if not predicate.is_valid():
		push_error("ConditionalOp: no predicate set")
		return
	var branch: Array[EffectOp] = then_ops if bool(predicate.call(ctx)) else else_ops
	for op: EffectOp in branch:
		op.execute(ctx)


func describe() -> String:
	return "If <cond> then [%s] else [%s]" % [
		", ".join(then_ops.map(func(o: EffectOp) -> String: return o.describe())),
		", ".join(else_ops.map(func(o: EffectOp) -> String: return o.describe())),
	]
