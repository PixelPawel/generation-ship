class_name PlayerFactionState
extends RefCounted

var faction: String = ""
var hero_name: String = ""
var peer_id: int = -1        # network peer that controls this faction, -1 = unclaimed/bot
var is_bot: bool = false

var salt: int = 0
var plunder: int = 0
var food: int = 0

var action_points: int = 0
var max_action_points: int = 8

var vp: int = 0

var feats_in_play: Array[String] = []
var feats_deck_remaining: int = 0   # count only - the shuffled order is host-only, not networked card-by-card
var items_in_hand: Array[String] = []

var has_passed: bool = false
var has_acted_this_turn: bool = false


func to_dict() -> Dictionary:
	return {
		"faction": faction, "hero_name": hero_name, "peer_id": peer_id, "is_bot": is_bot,
		"salt": salt, "plunder": plunder, "food": food,
		"action_points": action_points, "max_action_points": max_action_points,
		"vp": vp, "feats_in_play": feats_in_play.duplicate(),
		"feats_deck_remaining": feats_deck_remaining, "items_in_hand": items_in_hand.duplicate(),
		"has_passed": has_passed, "has_acted_this_turn": has_acted_this_turn,
	}


static func from_dict(d: Dictionary) -> PlayerFactionState:
	var s := PlayerFactionState.new()
	s.faction = d.get("faction", "")
	s.hero_name = d.get("hero_name", "")
	s.peer_id = d.get("peer_id", -1)
	s.is_bot = d.get("is_bot", false)
	s.salt = d.get("salt", 0)
	s.plunder = d.get("plunder", 0)
	s.food = d.get("food", 0)
	s.action_points = d.get("action_points", 0)
	s.max_action_points = d.get("max_action_points", 8)
	s.vp = d.get("vp", 0)
	var feats: Array = d.get("feats_in_play", [])
	for f: Variant in feats:
		s.feats_in_play.append(str(f))
	s.feats_deck_remaining = d.get("feats_deck_remaining", 0)
	var items: Array = d.get("items_in_hand", [])
	for it: Variant in items:
		s.items_in_hand.append(str(it))
	s.has_passed = d.get("has_passed", false)
	s.has_acted_this_turn = d.get("has_acted_this_turn", false)
	return s
