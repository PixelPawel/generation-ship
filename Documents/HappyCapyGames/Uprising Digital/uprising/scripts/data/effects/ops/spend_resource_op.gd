class_name SpendResourceOp
extends EffectOp

var resource: String = "Salt"
var amount: int = 1


func _init(p_resource: String = "Salt", p_amount: int = 1) -> void:
	resource = p_resource
	amount = p_amount


func execute(ctx: EffectContext) -> void:
	var p: PlayerFactionState = ctx.state.find_player(ctx.acting_faction)
	if p == null:
		return
	match resource:
		"Salt":
			p.salt = max(0, p.salt - amount)
		"Plunder":
			p.plunder = max(0, p.plunder - amount)
		"Food":
			p.food = max(0, p.food - amount)
	ctx.log("%s spends %d %s" % [p.faction, amount, resource])


func describe() -> String:
	return "Pay %d %s" % [amount, resource]
