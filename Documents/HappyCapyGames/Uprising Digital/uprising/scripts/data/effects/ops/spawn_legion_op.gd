class_name SpawnLegionOp
extends EffectOp

## "Place 1 Legion at Threat N" - draws, targets, resolves the immediate
## effect and any combat through NemesisAI.spawn_legion. target_mode
## "here" stands it on ctx.hex_coord, anything else on The Capital (the
## rulebook's default when no place is given). lock_target: "and its
## Target" on that same hex, never retargeting (e.g. Aezhers Essence).
var threat: int = 4
var target_mode: String = "capital"
var lock_target: bool = false


func _init(p_threat: int = 4, p_target_mode: String = "capital", p_lock_target: bool = false) -> void:
	threat = p_threat
	target_mode = p_target_mode
	lock_target = p_lock_target


func execute(ctx: EffectContext) -> void:
	var coord: Vector2i = ctx.hex_coord if target_mode == "here" and ctx.has_hex_coord else ctx.state.capital_coord
	var opts: Dictionary = {"target": "here"} if lock_target else {}
	var inst: LegionInstance = NemesisAI.spawn_legion(ctx.state, ctx.card_db, coord, threat, opts)
	ctx.log("Legion %s at Threat %d on %s" % [inst.card_name if inst != null else "(none left)", threat, coord])


func describe() -> String:
	return "Spawn 1 Legion at Threat %d (%s)" % [threat, target_mode]
