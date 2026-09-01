class_name GameState
extends RefCounted
## The single authoritative source of truth for an in-progress game. Only the
## host ever mutates this directly (see NetworkManager); everyone else works
## from the copy they receive via to_dict()/from_dict(), which is also the
## save-file format.

enum Phase { REFRESH, EVENTS, BUILD, ACTIONS, NEMESIS, PRODUCTION, SCORING }

const CAPITAL_COORD := Vector2i.ZERO
## Sentinel "no pending combat" value for pending_combat_hex.
const NO_COMBAT := Vector2i(-9999, -9999)

var chapter: int = 1
var max_chapters: int = 3
var phase: Phase = Phase.REFRESH
var first_player_index: int = 0
var current_player_index: int = 0

## Set by NemesisAI when a Legion/Horde activation moves into a hex with
## enemy presence -- combat resolution isn't automated yet (see
## nemesis_ai.gd), so this just flags where it needs to be resolved manually.
var pending_combat_hex: Vector2i = NO_COMBAT

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
var druids_in_play: Array[String] = []


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
		"pending_combat_hex": [pending_combat_hex.x, pending_combat_hex.y],
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
		"druids_in_play": druids_in_play.duplicate(),
	}


static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.chapter = d.get("chapter", 1)
	s.max_chapters = d.get("max_chapters", 3)
	s.phase = d.get("phase", Phase.REFRESH) as Phase
	s.first_player_index = d.get("first_player_index", 0)
	s.current_player_index = d.get("current_player_index", 0)
	var pc: Array = d.get("pending_combat_hex", [NO_COMBAT.x, NO_COMBAT.y])
	s.pending_combat_hex = Vector2i(pc[0], pc[1])

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

	s.druids_in_play.assign(d.get("druids_in_play", []))
	return s
