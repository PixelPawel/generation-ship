class_name SpawnHordeOp
extends EffectOp

## "Place 1 Horde at Threat N" through NemesisAI.spawn_horde (immediate
## effect, then any combat). target_mode "here" uses ctx.hex_coord; anything
## else picks an empty hex (rulebook p53: a hex with a Curse is not empty),
## or a hex with a Skeleton or Curse if none is empty.
var threat: int = 4
var target_mode: String = "here"


func _init(p_threat: int = 4, p_target_mode: String = "here") -> void:
	threat = p_threat
	target_mode = p_target_mode


func execute(ctx: EffectContext) -> void:
	var coord: Vector2i = Vector2i.MIN
	if target_mode == "here" and ctx.has_hex_coord:
		coord = ctx.hex_coord
	else:
		coord = NemesisAI.pick_hex(ctx.state, NemesisAI.empty_hexes(ctx.state))
		if coord == Vector2i.MIN:
			var fallback: Array[Vector2i] = []
			for c: Vector2i in ctx.state.hexes.keys():
				var t: HexTileState = ctx.state.hexes[c]
				if t.skeleton_count > 0 or t.curse:
					fallback.append(c)
			coord = NemesisAI.pick_hex(ctx.state, fallback)
	if coord == Vector2i.MIN:
		ctx.state.chaos_vp += 1
		ctx.log("nowhere to place a Horde - Chaos gains 1 VP")
		return
	var inst: HordeInstance = NemesisAI.spawn_horde(ctx.state, coord, ctx.card_db, threat)
	ctx.log("Horde %s at Threat %d on %s" % [inst.card_name if inst != null else "(none left)", threat, coord])


func describe() -> String:
	return "Spawn 1 Horde at Threat %d (%s)" % [threat, target_mode]
