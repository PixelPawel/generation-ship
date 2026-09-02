class_name PlaceActivationTokenOp
extends EffectOp

## "Place 1 Activation Token on a Legion or Horde card with the least
## Tokens" - the off-schedule token-placement primitive (distinct from the
## Events Phase's own "every card gets one" step, which is plain
## arithmetic on every LegionInstance/HordeInstance and doesn't need this
## op at all). Ties broken by lowest id (deterministic, not random).
func execute(ctx: EffectContext) -> void:
	var candidates: Array = []
	candidates.append_array(ctx.state.legions)
	candidates.append_array(ctx.state.hordes)
	if candidates.is_empty():
		ctx.log("PlaceActivationTokenOp: no Legions/Hordes in play, skipped")
		return

	var best: Variant = null
	var best_tokens: int = 999999
	for c: Variant in candidates:
		var tokens: int = c.activation_tokens
		var id: int = c.id
		if tokens < best_tokens or (tokens == best_tokens and best != null and id < best.id):
			best = c
			best_tokens = tokens
	best.activation_tokens += 1
	ctx.log("Placed 1 Activation Token on %s (id=%d, now %d tokens)" % [best.card_name, best.id, best.activation_tokens])


func describe() -> String:
	return "Place 1 Activation Token on the Legion/Horde with the fewest tokens"
