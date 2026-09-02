class_name GameState
extends RefCounted

## Top-level networked/saved game state. Cheap to serialize (plain
## RefCounted + to_dict/from_dict, no Node overhead) since the same
## to_dict()/from_dict() round trip is used both for save files AND as the
## host's full-state network broadcast payload (NetworkManager doesn't
## know or care about game rules - it just moves whatever this produces).

enum Phase { REFRESH, EVENTS, BUILD, ACTIONS, NEMESIS, PRODUCTION, SCORING }

var phase: Phase = Phase.REFRESH
var chapter: int = 1
var max_chapters: int = 2
var difficulty: String = "Veteran"  # Rebel | Veteran | Nightmare | Apocalypse

var hexes: Dictionary = {}    # Vector2i -> HexTileState
var players: Array[PlayerFactionState] = []
var legions: Array[LegionInstance] = []
var hordes: Array[HordeInstance] = []
var druids_in_play: Array[DruidInstance] = []

## Decks/discards are tracked as ordered Array[String] of card names. The
## host is the only one who ever needs true shuffle order for hidden
## decks - for broadcast purposes only remaining counts matter to clients,
## but keeping full arrays here is simplest and this game's card counts
## are small enough that broadcasting them in full is not a real cost.
var item_deck: Array[String] = []
var item_discard: Array[String] = []
var quest_deck: Array[String] = []
var quest_discard: Array[String] = []
var legion_deck: Array[String] = []
var horde_deck: Array[String] = []
var event_decks: Dictionary = {}   # chapter(int) -> Array[String] (deck for that chapter, minus the 1 pre-placed card)
var chapter_events: Dictionary = {}  # chapter(int) -> String (this chapter's revealed/pending Event card name)

var empire_vp: int = 0
var chaos_vp: int = 0
var imperial_graveyard: Dictionary = {}  # faction -> unit count
var chaos_graveyard: Dictionary = {}     # faction -> unit count

var aether_pool: int = 7  # rulebook p40: 7 shared tokens total.

var first_player_index: int = 0
var current_player_index: int = 0

var phase_log: String = ""   # last human-readable "what just happened" line, for UI (Milestone 5)


func to_dict() -> Dictionary:
	var hexes_out: Dictionary = {}
	for coord: Vector2i in hexes.keys():
		hexes_out[_coord_key(coord)] = (hexes[coord] as HexTileState).to_dict()

	var legions_out: Array = []
	for l: LegionInstance in legions:
		legions_out.append(l.to_dict())
	var hordes_out: Array = []
	for h: HordeInstance in hordes:
		hordes_out.append(h.to_dict())
	var druids_out: Array = []
	for d: DruidInstance in druids_in_play:
		druids_out.append(d.to_dict())
	var players_out: Array = []
	for p: PlayerFactionState in players:
		players_out.append(p.to_dict())

	return {
		"phase": phase, "chapter": chapter, "max_chapters": max_chapters, "difficulty": difficulty,
		"hexes": hexes_out, "players": players_out, "legions": legions_out, "hordes": hordes_out,
		"druids_in_play": druids_out,
		"item_deck": item_deck.duplicate(), "item_discard": item_discard.duplicate(),
		"quest_deck": quest_deck.duplicate(), "quest_discard": quest_discard.duplicate(),
		"legion_deck": legion_deck.duplicate(), "horde_deck": horde_deck.duplicate(),
		"event_decks": _stringify_int_keys(event_decks),
		"chapter_events": _stringify_int_keys(chapter_events),
		"empire_vp": empire_vp, "chaos_vp": chaos_vp,
		"imperial_graveyard": imperial_graveyard.duplicate(), "chaos_graveyard": chaos_graveyard.duplicate(),
		"aether_pool": aether_pool,
		"first_player_index": first_player_index, "current_player_index": current_player_index,
		"phase_log": phase_log,
	}


static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.phase = d.get("phase", Phase.REFRESH) as Phase
	s.chapter = d.get("chapter", 1)
	s.max_chapters = d.get("max_chapters", 2)
	s.difficulty = d.get("difficulty", "Veteran")

	var hexes_in: Dictionary = d.get("hexes", {})
	for key: String in hexes_in.keys():
		s.hexes[_key_coord(key)] = HexTileState.from_dict(hexes_in[key])

	for pd: Variant in (d.get("players", []) as Array):
		s.players.append(PlayerFactionState.from_dict(pd))
	for ld: Variant in (d.get("legions", []) as Array):
		s.legions.append(LegionInstance.from_dict(ld))
	for hd: Variant in (d.get("hordes", []) as Array):
		s.hordes.append(HordeInstance.from_dict(hd))
	for dd: Variant in (d.get("druids_in_play", []) as Array):
		s.druids_in_play.append(DruidInstance.from_dict(dd))

	for v: Variant in (d.get("item_deck", []) as Array):
		s.item_deck.append(str(v))
	for v: Variant in (d.get("item_discard", []) as Array):
		s.item_discard.append(str(v))
	for v: Variant in (d.get("quest_deck", []) as Array):
		s.quest_deck.append(str(v))
	for v: Variant in (d.get("quest_discard", []) as Array):
		s.quest_discard.append(str(v))
	for v: Variant in (d.get("legion_deck", []) as Array):
		s.legion_deck.append(str(v))
	for v: Variant in (d.get("horde_deck", []) as Array):
		s.horde_deck.append(str(v))
	s.event_decks = _intify_keys(d.get("event_decks", {}))
	s.chapter_events = _intify_keys(d.get("chapter_events", {}))

	s.empire_vp = d.get("empire_vp", 0)
	s.chaos_vp = d.get("chaos_vp", 0)
	s.imperial_graveyard = (d.get("imperial_graveyard", {}) as Dictionary).duplicate()
	s.chaos_graveyard = (d.get("chaos_graveyard", {}) as Dictionary).duplicate()
	s.aether_pool = d.get("aether_pool", 7)
	s.first_player_index = d.get("first_player_index", 0)
	s.current_player_index = d.get("current_player_index", 0)
	s.phase_log = d.get("phase_log", "")
	return s


static func _coord_key(coord: Vector2i) -> String:
	return "%d,%d" % [coord.x, coord.y]


static func _key_coord(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(",")
	return Vector2i(parts[0].to_int(), parts[1].to_int())


static func _stringify_int_keys(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in d.keys():
		out[str(k)] = d[k]
	return out


static func _intify_keys(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in d.keys():
		out[str(k).to_int()] = d[k]
	return out
