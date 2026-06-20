extends Node3D

const MAX_SLOTS := 5

var slot_index: int = 0
var occupied := false
var placed_card: Node3D = null

func accept_card(card: Node3D) -> void:
	occupied = true
	placed_card = card
	card.reparent(self, true)
	card.managed_by_hand = false
	card.call("set_sort_order", 0.0)
	var tween := card.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(card, "position", Vector3.ZERO, 0.3)
	tween.parallel().tween_property(card, "rotation", Vector3(-PI / 2.0, 0.0, 0.0), 0.3)
	tween.parallel().tween_property(card, "scale", Vector3.ONE, 0.2)
