class_name GameState
extends RefCounted
## The single authoritative source of truth for an in-progress game. Only the
## host ever mutates this directly (see NetworkManager); everyone else works
## from the copy they receive via to_dict()/from_dict(), which is also the
## save-file format.

enum Phase { REFRESH, EVENTS, BUILD, ACTIONS, NEMESIS, PRODUCTION, SCORING }

const CAPITAL_COORD := Vector2i.ZERO

var chapter: int = 1
var max_chapters: int = 3
var phase: Phase = Phase.REFRESH
var first_player_index: int = 0
var current_player_index: int = 0

## Appended to by NemesisAI whenever a Legion/Horde activation moves into a
## hex with enemy presence -- combat resolution isn't automated yet (see
## nemesis_ai.gd), so these just queue up to be resolved manually. A queue
## rather than a single hex because GameFlow runs every Activation Token in
## a Nemesis Phase in one pass, and more than one can trigger combat before
## any of them get resolved.
var pending_combats: Array[Vector2i] = []

## The current Chapter's revealed Event card (set by ChapterFlow.
## draw_event_card during the Refresh -> Events transition). Resolving its
## printed text stays manual/assisted, same as every other card-text
## effect -- this just makes sure the player is actually shown WHICH card
## to read, since nothing else surfaces it once drawn from
## event_deck_by_chapter.
var current_event: String = ""

## HexMath.key(coord) -> HexTile
var hexes: Dictionary = {}
var players: Array[PlayerFactionState] = []
var legions: Array[LegionInstance] = []
var hordes: Array[HordeInstance] = []
var _next_nemesis_id: int = 0

var empire_vp: int = 0
var chaos_vp: int = 0
var imperial_graveyard: Dictionary = {}  # faction -> count
var chaos_graveyard: Dictionary = {}  # faction -> count

var item_deck: Array[String] = []
var item_discard: Array[String] = []
var market: Array[String] = []  # up to 3 face-up Item names

var quest_deck: Array[String] = []
var quest_discard: Array[String] = []
var quests_available: Array[String] = []  # up to 3 face-up Quest names

var legion_deck: Array[String] = []
var horde_deck: Array[String] = []

var event_deck_by_chapter: Dictionary = {}  # chapter (int) -> Array[String] event names, in play order
## The 4 Druid cards revealed at Setup (p6), each tracking its own AETHER
## count -- see DruidInstance/DruidData. Revealed once, not re-drawn each
## Chapter: the rulebook's own Refresh Phase step list (p15) doesn't
## mention Druids at all, only their "Refresh Phase" condition text does.
var druids_in_play: Array[DruidInstance] = []
## Remaining Druid ("Blessing") cards not revealed at setup. Nothing in the
## rulebook currently draws further from this once the initial 4 are placed
## (p6: "Place 4 random Druid cards face-up"), but it's modeled as a real
## deck like everything else for consistency and in case a future Quest/
## Event effect reveals more.
var druid_deck: Array[String] = []


func get_hex(coord: Vector2i) -> HexTile:
	return hexes.get(HexMath.key(coord))


func set_hex(tile: HexTile) -> void:
	hexes[HexMath.key(tile.coord)] = tile


func get_player(faction: String) -> PlayerFactionState:
	for p in players:
		if p.faction == faction:
			return p
	return null


func next_nemesis_id() -> int:
	_next_nemesis_id += 1
	return _next_nemesis_id


func to_dict() -> Dictionary:
	var hex_dict := {}
	for k in hexes:
		hex_dict[k] = (hexes[k] as HexTile).to_dict()

	var event_dict := {}
	for chap in event_deck_by_chapter:
		event_dict[str(chap)] = (event_deck_by_chapter[chap] as Array).duplicate()

	return {
		"chapter": chapter,
		"max_chapters": max_chapters,
		"phase": phase,
		"first_player_index": first_player_index,
		"current_player_index": current_player_index,
		"pending_combats": pending_combats.map(func(c: Vector2i) -> Array: return [c.x, c.y]),
		"current_event": current_event,
		"hexes": hex_dict,
		"players": players.map(func(p: PlayerFactionState) -> Dictionary: return p.to_dict()),
		"legions": legions.map(func(l: LegionInstance) -> Dictionary: return l.to_dict()),
		"hordes": hordes.map(func(h: HordeInstance) -> Dictionary: return h.to_dict()),
		"next_nemesis_id": _next_nemesis_id,
		"empire_vp": empire_vp,
		"chaos_vp": chaos_vp,
		"imperial_graveyard": imperial_graveyard.duplicate(),
		"chaos_graveyard": chaos_graveyard.duplicate(),
		"item_deck": item_deck.duplicate(),
		"item_discard": item_discard.duplicate(),
		"market": market.duplicate(),
		"quest_deck": quest_deck.duplicate(),
		"quest_discard": quest_discard.duplicate(),
		"quests_available": quests_available.duplicate(),
		"legion_deck": legion_deck.duplicate(),
		"horde_deck": horde_deck.duplicate(),
		"event_deck_by_chapter": event_dict,
		"druids_in_play": druids_in_play.map(func(d: DruidInstance) -> Dictionary: return d.to_dict()),
		"druid_deck": druid_deck.duplicate(),
	}


static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.chapter = d.get("chapter", 1)
	s.max_chapters = d.get("max_chapters", 3)
	s.phase = d.get("phase", Phase.REFRESH) as Phase
	s.first_player_index = d.get("first_player_index", 0)
	s.current_player_index = d.get("current_player_index", 0)
	s.pending_combats = []
	for c in (d.get("pending_combats", []) as Array):
		s.pending_combats.append(Vector2i(c[0], c[1]))
	s.current_event = d.get("current_event", "")

	s.hexes = {}
	for k in (d.get("hexes", {}) as Dictionary):
		s.hexes[k] = HexTile.from_dict(d["hexes"][k])

	s.players.assign((d.get("players", []) as Array).map(
		func(pd: Dictionary) -> PlayerFactionState: return PlayerFactionState.from_dict(pd)
	))
	s.legions.assign((d.get("legions", []) as Array).map(
		func(ld: Dictionary) -> LegionInstance: return LegionInstance.from_dict(ld)
	))
	s.hordes.assign((d.get("hordes", []) as Array).map(
		func(hd: Dictionary) -> HordeInstance: return HordeInstance.from_dict(hd)
	))
	s._next_nemesis_id = d.get("next_nemesis_id", 0)

	s.empire_vp = d.get("empire_vp", 0)
	s.chaos_vp = d.get("chaos_vp", 0)
	s.imperial_graveyard = (d.get("imperial_graveyard", {}) as Dictionary).duplicate()
	s.chaos_graveyard = (d.get("chaos_graveyard", {}) as Dictionary).duplicate()

	s.item_deck.assign(d.get("item_deck", []))
	s.item_discard.assign(d.get("item_discard", []))
	s.market.assign(d.get("market", []))
	s.quest_deck.assign(d.get("quest_deck", []))
	s.quest_discard.assign(d.get("quest_discard", []))
	s.quests_available.assign(d.get("quests_available", []))
	s.legion_deck.assign(d.get("legion_deck", []))
	s.horde_deck.assign(d.get("horde_deck", []))

	s.event_deck_by_chapter = {}
	for chap_str in (d.get("event_deck_by_chapter", {}) as Dictionary):
		s.event_deck_by_chapter[int(chap_str)] = (d["event_deck_by_chapter"][chap_str] as Array).duplicate()

	s.druids_in_play.assign((d.get("druids_in_play", []) as Array).map(
		func(dd: Dictionary) -> DruidInstance: return DruidInstance.from_dict(dd)
	))
	s.druid_deck.assign(d.get("druid_deck", []))
	return s
