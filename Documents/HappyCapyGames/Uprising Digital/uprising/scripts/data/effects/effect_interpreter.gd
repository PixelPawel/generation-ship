class_name EffectInterpreter
extends RefCounted

## Executes an EffectProgram's ops, in order, against a real EffectContext.
## Deliberately this simple - all the actual logic lives in the ops
## themselves (each independently testable), not here.
static func run(program: EffectProgram, ctx: EffectContext) -> void:
	if program == null:
		return
	for op: EffectOp in program.ops:
		op.execute(ctx)
