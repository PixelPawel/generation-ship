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
	if resource == "Any":
		# "Gain N resources": any mix - without a UI choice, each one goes to
		# whatever the player holds least of (ties Salt, Plunder, Food).
		for _i: int in range(amount):
			var pick: String = "Salt"
			if ctx.choice_resolver.is_valid():
				pick = str(ctx.choice_resolver.call("resource", ["Salt", "Plunder", "Food"]))
			elif p.plunder < p.salt and p.plunder <= p.food:
				pick = "Plunder"
			elif p.food < p.salt and p.food < p.plunder:
				pick = "Food"
			_add(p, pick, 1)
		ctx.log("%s gains %d resources" % [p.faction, amount])
		return
	_add(p, resource, amount)
	ctx.log("%s gains %d %s" % [p.faction, amount, resource])


static func _add(p: PlayerFactionState, res: String, n: int) -> void:
	match res:
		"Salt":
			p.salt += n
		"Plunder":
			p.plunder += n
		"Food":
			p.food += n


func describe() -> String:
	return "Gain %d %s" % [amount, resource]
