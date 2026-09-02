class_name GainVPOp
extends EffectOp

## target in {"self","Empire","Chaos"} - "each player" VP gains are
## expressed by wrapping this in an EachPlayerOp with target="self" instead
## of adding a fourth target mode, keeping this op single-purpose.
var target: String = "self"
var amount: int = 1


func _init(p_target: String = "self", p_amount: int = 1) -> void:
	target = p_target
	amount = p_amount


func execute(ctx: EffectContext) -> void:
	match target:
		"self":
			var p: PlayerFactionState = ctx.state.find_player(ctx.acting_faction)
			if p != null:
				p.vp += amount
				ctx.log("%s gains %d VP" % [p.faction, amount])
		"Empire":
			ctx.state.empire_vp += amount
			ctx.log("Empire gains %d VP" % amount)
		"Chaos":
			ctx.state.chaos_vp += amount
			ctx.log("Chaos gains %d VP" % amount)


func describe() -> String:
	return "%s gains %d VP" % [target, amount]
