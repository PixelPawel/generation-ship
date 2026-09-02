class_name EffectProgram
extends RefCounted

## An ordered sequence of EffectOps transcribed from one card's free text,
## plus which card it came from (for logs/debugging).

var source_card: String = ""
var ops: Array[EffectOp] = []


func _init(p_source_card: String = "", p_ops: Array[EffectOp] = []) -> void:
	source_card = p_source_card
	ops = p_ops
