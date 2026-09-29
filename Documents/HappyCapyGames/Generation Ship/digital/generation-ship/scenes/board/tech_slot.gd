extends Node3D

var slot_index: int = 0
var occupied := false
var placed_card: Node3D = null

func accept_card(card: Node3D) -> void:
	occupied = true
	placed_card = card
	card.reparent(self, true)
	card.managed_by_hand = false
	card.call("set_sort_order", 0.0)
	# Bought from the market: fly in from the market screen (see Board).
	if card.has_meta(&"place_from"):
		var from: Vector3 = card.get_meta(&"place_from")
		card.remove_meta(&"place_from")
		card.call("fly_to_rest", from, Vector3.ZERO, Vector3(-PI / 2.0, 0.0, 0.0))
		return
	var tween := card.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(card, "position", Vector3.ZERO, 0.3)
	tween.parallel().tween_property(card, "rotation", Vector3(-PI / 2.0, 0.0, 0.0), 0.3)
	tween.parallel().tween_property(card, "scale", Vector3.ONE, 0.2)
