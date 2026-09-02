class_name GainResourceOp
extends EffectOp

## resource in {"Salt","Plunder","Food","Any"}. "Any" ("gain 2 resources")
## defers to ctx.choice_resolver("resource", ["Salt","Plunder","Food"]) if
## set, else deterministically defaults to Salt (documented fallback, not
## a silent guess) - matches the same choice-resolver boundary used
## project-wide for anything requiring a real player decision.
var resource: String = "Salt"
var amount: int = 1


func _init(p_resource: String = "Salt", p_amount: int = 1) -> void:
	resource = p_resource
	amount = p_amount


func execute(ctx: EffectContext) -> void:
	var p: PlayerFactionState = ctx.state.find_player(ctx.acting_faction)
	if p == null:
		ctx.log("GainResourceOp: no acting player, skipped")
		return
	var actual_resource: String = resource
	if resource == "Any":
		if ctx.choice_resolver.is_valid():
			actual_resource = str(ctx.choice_resolver.call("resource", ["Salt", "Plunder", "Food"]))
		else:
			actual_resource = "Salt"
	match actual_resource:
		"Salt":
			p.salt += amount
		"Plunder":
			p.plunder += amount
		"Food":
			p.food += amount
	ctx.log("%s gains %d %s" % [p.faction, amount, actual_resource])


func describe() -> String:
	return "Gain %d %s" % [amount, resource]
