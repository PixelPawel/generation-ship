class_name SpawnHordeOp
extends EffectOp

## Mirrors SpawnLegionOp - see its doc comment for the shared "Immediate
## effect resolution is the caller's job" note.
var threat: int = 4
var target_mode: String = "here"


func _init(p_threat: int = 4, p_target_mode: String = "here") -> void:
	threat = p_threat
	target_mode = p_target_mode


func execute(ctx: EffectContext) -> void:
	if ctx.state.horde_deck.is_empty():
		ctx.log("SpawnHordeOp: horde_deck empty, Chaos gains 1 VP instead (rulebook p50 impossible-placement rule)")
		ctx.state.chaos_vp += 1
		return
	var coord: Vector2i = _resolve_target(ctx)
	var card_name: String = ctx.state.horde_deck.pop_front()
	var inst := HordeInstance.new()
	inst.id = _next_id(ctx.state)
	inst.card_name = card_name
	inst.threat = threat
	inst.coord = coord
	inst.activation_tokens = 0
	ctx.state.hordes.append(inst)
	ctx.log("Spawned Horde '%s' (id=%d) at Threat %d on %s" % [card_name, inst.id, threat, coord])


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
	return "Spawn 1 Horde at Threat %d (%s)" % [threat, target_mode]
