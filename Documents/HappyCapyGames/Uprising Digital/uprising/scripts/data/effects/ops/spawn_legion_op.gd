class_name SpawnLegionOp
extends EffectOp

## Draws the top card of legion_deck and places it. Does NOT resolve the
## drawn card's own "Immediate" effect (rulebook p47: that must happen
## before other effects/combats) - that's the caller's job, since it needs
## a second EffectProgram lookup by the newly-drawn card's name, which
## belongs at the ChapterFlow/NemesisAI level (Milestone 4), not inside
## this single op.
var threat: int = 4
var target_mode: String = "here"   # "here" uses ctx.hex_coord, else ctx.choice_resolver("hex", [])
var lock_target: bool = false      # "the Legion will stay there, it does not retarget" (e.g. Aezhers Essence)


func _init(p_threat: int = 4, p_target_mode: String = "here", p_lock_target: bool = false) -> void:
	threat = p_threat
	target_mode = p_target_mode
	lock_target = p_lock_target


func execute(ctx: EffectContext) -> void:
	if ctx.state.legion_deck.is_empty():
		ctx.log("SpawnLegionOp: legion_deck empty, Empire gains 1 VP instead (rulebook p50 impossible-placement rule)")
		ctx.state.empire_vp += 1
		return
	var coord: Vector2i = _resolve_target(ctx)
	var card_name: String = ctx.state.legion_deck.pop_front()
	var inst := LegionInstance.new()
	inst.id = _next_id(ctx.state)
	inst.card_name = card_name
	inst.threat = threat
	inst.coord = coord
	inst.activation_tokens = 0
	inst.target_faction = "Capital" if lock_target else ""
	ctx.state.legions.append(inst)
	ctx.log("Spawned Legion '%s' (id=%d) at Threat %d on %s" % [card_name, inst.id, threat, coord])


func _resolve_target(ctx: EffectContext) -> Vector2i:
	if target_mode == "here" and ctx.has_hex_coord:
		return ctx.hex_coord
	if ctx.choice_resolver.is_valid():
		var chosen: Variant = ctx.choice_resolver.call(target_mode, [])
		if chosen is Vector2i:
			return chosen
	return ctx.hex_coord if ctx.has_hex_coord else Vector2i.ZERO


func _next_id(state: GameState) -> int:
	var max_id: int = -1
	for l: LegionInstance in state.legions:
		max_id = maxi(max_id, l.id)
	for h: HordeInstance in state.hordes:
		max_id = maxi(max_id, h.id)
	return max_id + 1


func describe() -> String:
	return "Spawn 1 Legion at Threat %d (%s)" % [threat, target_mode]
