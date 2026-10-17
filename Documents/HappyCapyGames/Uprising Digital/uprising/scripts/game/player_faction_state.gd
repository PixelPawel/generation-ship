class_name PlayerFactionState
extends RefCounted

var faction: String = ""
var hero_name: String = ""
var peer_id: int = -1        # network peer that controls this faction, -1 = unclaimed/bot
var is_bot: bool = false
## Where the Hero standee stands (rulebook p10: starts on the home hex).
## Explore and Haven act on this hex, Move/Command change it.
var hero_coord: Vector2i = Vector2i.ZERO

var salt: int = 0
var plunder: int = 0
var food: int = 0

var action_points: int = 0
var max_action_points: int = 8

var vp: int = 0

var feats_in_play: Array[String] = []
var feats_deck_remaining: int = 0   # count only - the shuffled order is host-only, not networked card-by-card
var items_in_hand: Array[String] = []
## Items flipped face-down (unusable) until the next Refresh Phase.
var flipped_items: Array[String] = []
## This faction's Units sitting in either Graveyard, by type (unit name ->
## count) - out of the reserve until the Scoring Phase returns them.
var graveyard_units: Dictionary = {}
## Quests solved "Gain this card" style, kept in front of the player.
var quests_in_play: Array[String] = []
## Units removed from the game for good (The Executioner): unit name -> count.
var removed_units: Dictionary = {}
## The Hero's Feat deck (top = front) and Feats flipped (used) until the next
## Refresh Phase; feats_in_play holds the face-up and flipped ones alike.
var feat_deck: Array[String] = []
var flipped_feats: Array[String] = []
## The 2 Feats drawn at the start of the Build Phase, waiting for a pick.
var pending_feats: Array[String] = []
## Attribute boosts from the "Guile Leadership" / "Might Magic" Feats.
var attr_bonus: Dictionary = {}
## A Haven placed this turn with Asheforge lets Units/Defenses be built there.
var asheforge_coord: Vector2i = Vector2i.MIN
## Wiles flipped: the next Command, Haven or Move costs no AP or resources.
var wiles_ready: bool = false

var has_passed: bool = false
var has_acted_this_turn: bool = false

## True Solo Mode (rulebook p74-79): the allied Hero, a second standee that
## shares this faction's AP, resources, Units and player board. Its Feats
## and Items sit in the same feats_in_play / items_in_hand lists - abilities
## that say "you" work for both Heroes - and ally_cards marks which are its
## own (for "On your Hero's hex" and where a discarded Feat goes). "" when
## there is no allied Hero, which is every multiplayer game.
var ally_hero_name: String = ""
var ally_coord: Vector2i = Vector2i.ZERO
var ally_feat_deck: Array[String] = []
var ally_pending_feats: Array[String] = []
var ally_attr_bonus: Dictionary = {}
## Feat/Item name -> true for the allied Hero's cards.
var ally_cards: Dictionary = {}
## True while swap_heroes() has the allied Hero in the main Hero's fields
## (the allied Hero is acting). Always false between actions; not saved.
var heroes_swapped: bool = false


func has_ally() -> bool:
	return not ally_hero_name.is_empty()


## Exchanges the main and allied Hero's own fields, so rules code written for
## "the Hero" acts for the allied Hero. Call again to swap back.
func swap_heroes() -> void:
	var n: String = hero_name
	hero_name = ally_hero_name
	ally_hero_name = n
	var c: Vector2i = hero_coord
	hero_coord = ally_coord
	ally_coord = c
	var deck: Array[String] = feat_deck
	feat_deck = ally_feat_deck
	ally_feat_deck = deck
	var pending: Array[String] = pending_feats
	pending_feats = ally_pending_feats
	ally_pending_feats = pending
	var bonus: Dictionary = attr_bonus
	attr_bonus = ally_attr_bonus
	ally_attr_bonus = bonus
	heroes_swapped = not heroes_swapped


## Whether `card` belongs to the Hero currently in the main Hero's fields.
func card_is_acting_heros(card: String) -> bool:
	return ally_cards.has(card) == heroes_swapped


## Where the Hero who owns `card` stands.
func card_hero_coord(card: String) -> Vector2i:
	return hero_coord if card_is_acting_heros(card) else ally_coord


## A card just gained goes to the Hero currently acting.
func claim_card(card: String) -> void:
	if not has_ally():
		return
	if heroes_swapped:
		ally_cards[card] = true
	else:
		ally_cards.erase(card)


## Either of this faction's Heroes stands on `coord`.
func hero_at(coord: Vector2i) -> bool:
	return hero_coord == coord or (has_ally() and ally_coord == coord)


func to_dict() -> Dictionary:
	return {
		"faction": faction, "hero_name": hero_name, "peer_id": peer_id, "is_bot": is_bot,
		"hero_coord": {"x": hero_coord.x, "y": hero_coord.y},
		"salt": salt, "plunder": plunder, "food": food,
		"action_points": action_points, "max_action_points": max_action_points,
		"vp": vp, "feats_in_play": feats_in_play.duplicate(),
		"feats_deck_remaining": feats_deck_remaining, "items_in_hand": items_in_hand.duplicate(),
		"flipped_items": flipped_items.duplicate(), "graveyard_units": graveyard_units.duplicate(),
		"quests_in_play": quests_in_play.duplicate(), "removed_units": removed_units.duplicate(),
		"feat_deck": feat_deck.duplicate(), "flipped_feats": flipped_feats.duplicate(),
		"pending_feats": pending_feats.duplicate(), "attr_bonus": attr_bonus.duplicate(),
		"asheforge_coord": {"x": asheforge_coord.x, "y": asheforge_coord.y}, "wiles_ready": wiles_ready,
		"has_passed": has_passed, "has_acted_this_turn": has_acted_this_turn,
		"ally_hero_name": ally_hero_name, "ally_coord": {"x": ally_coord.x, "y": ally_coord.y},
		"ally_feat_deck": ally_feat_deck.duplicate(), "ally_pending_feats": ally_pending_feats.duplicate(),
		"ally_attr_bonus": ally_attr_bonus.duplicate(), "ally_cards": ally_cards.duplicate(),
	}


static func from_dict(d: Dictionary) -> PlayerFactionState:
	var s := PlayerFactionState.new()
	s.faction = d.get("faction", "")
	s.hero_name = d.get("hero_name", "")
	s.peer_id = d.get("peer_id", -1)
	s.is_bot = d.get("is_bot", false)
	var hc: Dictionary = d.get("hero_coord", {"x": 0, "y": 0})
	s.hero_coord = Vector2i(int(hc.get("x", 0)), int(hc.get("y", 0)))
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
	for it: Variant in (d.get("flipped_items", []) as Array):
		s.flipped_items.append(str(it))
	s.graveyard_units = (d.get("graveyard_units", {}) as Dictionary).duplicate()
	for q: Variant in (d.get("quests_in_play", []) as Array):
		s.quests_in_play.append(str(q))
	s.removed_units = (d.get("removed_units", {}) as Dictionary).duplicate()
	for f: Variant in (d.get("feat_deck", []) as Array):
		s.feat_deck.append(str(f))
	for f2: Variant in (d.get("flipped_feats", []) as Array):
		s.flipped_feats.append(str(f2))
	for f3: Variant in (d.get("pending_feats", []) as Array):
		s.pending_feats.append(str(f3))
	s.attr_bonus = (d.get("attr_bonus", {}) as Dictionary).duplicate()
	var ac: Dictionary = d.get("asheforge_coord", {"x": Vector2i.MIN.x, "y": Vector2i.MIN.y})
	s.asheforge_coord = Vector2i(int(ac.get("x", Vector2i.MIN.x)), int(ac.get("y", Vector2i.MIN.y)))
	s.wiles_ready = bool(d.get("wiles_ready", false))
	s.has_passed = d.get("has_passed", false)
	s.has_acted_this_turn = d.get("has_acted_this_turn", false)
	s.ally_hero_name = str(d.get("ally_hero_name", ""))
	var al: Dictionary = d.get("ally_coord", {"x": 0, "y": 0})
	s.ally_coord = Vector2i(int(al.get("x", 0)), int(al.get("y", 0)))
	for f4: Variant in (d.get("ally_feat_deck", []) as Array):
		s.ally_feat_deck.append(str(f4))
	for f5: Variant in (d.get("ally_pending_feats", []) as Array):
		s.ally_pending_feats.append(str(f5))
	s.ally_attr_bonus = (d.get("ally_attr_bonus", {}) as Dictionary).duplicate()
	s.ally_cards = (d.get("ally_cards", {}) as Dictionary).duplicate()
	return s
