class_name EffectOp
extends RefCounted

## Base class for one primitive, executable effect operation. Concrete ops
## live in effects/ops/*.gd. Kept as plain RefCounted (not Resource) since
## these are constructed programmatically per-card in effects/hex_effects.gd
## etc., not authored/saved as .tres files (yet - see that file's own doc
## comment on why JSON/.tres authoring was deferred).

func execute(_ctx: EffectContext) -> void:
	push_error("EffectOp.execute() not overridden by %s" % get_script())


## Short human-readable description for logs/UI, overridden per op.
func describe() -> String:
	return "<effect>"
