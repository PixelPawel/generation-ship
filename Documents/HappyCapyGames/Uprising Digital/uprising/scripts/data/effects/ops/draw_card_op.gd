class_name DrawCardOp
extends EffectOp

## deck in {"Item","Feat","Quest"}. force_keep matches text like "Draw 1
## Item and keep it even if you could not use it" - otherwise ordinary
## acquisition rules (checked elsewhere, e.g. the 10-card Feat+Item limit)
## still apply; this op only moves the card, it doesn't enforce hand limits
## (that's GameActions' job once it exists, Milestone 4).
var deck: String = "Item"
var count: int = 1
var force_keep: bool = false


func _init(p_deck: String = "Item", p_count: int = 1, p_force_keep: bool = false) -> void:
	deck = p_deck
	count = p_count
	force_keep = p_force_keep


func execute(ctx: EffectContext) -> void:
	var p: PlayerFactionState = ctx.state.find_player(ctx.acting_faction)
	if p == null:
		return
	for _i: int in range(count):
		var drawn: String = _draw(ctx.state)
		if drawn.is_empty():
			continue
		match deck:
			"Item":
				p.items_in_hand.append(drawn)
			"Feat":
				p.feats_in_play.append(drawn)
			# Quest draws go to the shared board, not a player's hand -
			# not modeled here since it needs a "shared quest slots"
			# concept GameState doesn't have yet (Milestone 4).
		ctx.log("%s draws %s '%s'" % [p.faction, deck, drawn])


func _draw(state: GameState) -> String:
	match deck:
		"Item":
			if state.item_deck.is_empty():
				return ""
			return state.item_deck.pop_back()
		"Feat":
			return ""  # Feat decks are per-Hero, not in GameState yet (Milestone 4) - not modeled.
		"Quest":
			if state.quest_deck.is_empty():
				return ""
			return state.quest_deck.pop_back()
	return ""


func describe() -> String:
	return "Draw %d %s" % [count, deck]
