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
## True Solo Mode (rulebook p74): one faction with a main and an allied Hero
## on the solo side of the map.
var solo: bool = false
var capital_coord: Vector2i = Vector2i.ZERO

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
## The 3 face-up Items players can buy and the 3 face-up Quests they can
## attempt (rulebook p15: dealt fresh every Refresh Phase).
var item_market: Array[String] = []
var quest_row: Array[String] = []
## Market Items The Spymaster flipped face-down: not buyable and not
## discarded in Refresh until he is destroyed.
var flipped_market: Array[String] = []
## Items lying on a Quest card (Thieves Guild): quest name -> Array of item names.
var quest_items: Dictionary = {}
var legion_deck: Array[String] = []
var horde_deck: Array[String] = []
## Activation Tokens waiting on top of a deck - "the next Legion/Horde you
## draw gets that Token" (A New Dawn, Imperial Spy, Corrupted Druid).
var legion_deck_tokens: int = 0
var horde_deck_tokens: int = 0
## AP each player has parked on the Coven of Yssat (faction -> count);
## returned when the Coven is destroyed.
var coven_held_ap: Dictionary = {}
## The Capital hex flipped to its "Uprising in the Capital" side (rulebook p47).
var capital_flipped: bool = false
## The Banished went back under the Horde deck once ("Once per game").
var banished_returned: bool = false
## Assassins Dagger: Legion/Horde id (as text) -> the faction whose dagger is
## on it; each Activation Token removed from it costs it 1 Threat.
var daggers: Dictionary = {}
## Survivors flipped: every player may build Units and Defenses this turn.
var open_build_until_turn_end: bool = false
var event_decks: Dictionary = {}   # chapter(int) -> Array[String] (deck for that chapter, minus the 1 pre-placed card)
var chapter_events: Dictionary = {}  # chapter(int) -> String (this chapter's revealed/pending Event card name)
## The most recently revealed Event - its printed Threat is the default
## Threat of any Legion/Horde entering without one (rulebook p16, p45).
var latest_event: String = ""

var empire_vp: int = 0
var chaos_vp: int = 0
var imperial_graveyard: Dictionary = {}  # faction -> unit count
var chaos_graveyard: Dictionary = {}     # faction -> unit count

var aether_pool: int = 7  # rulebook p40: 7 shared tokens total.

var first_player_index: int = 0
var current_player_index: int = 0

var phase_log: String = ""   # last human-readable "what just happened" line, for UI (Milestone 5)

## Everything random during play draws from this seeded generator, saved
## with the state, so the host can replay an action exactly (decisions.gd).
var rng_seed: int = 0
var rng_state: int = 0
var _rng: RandomNumberGenerator = null

## A choice the game waits on (decisions.gd) - kind, prompt, chooser,
## options - sent to every peer; empty when nobody has to choose.
var pending_decision: Dictionary = {}
## Host-side only, while an action runs; never saved or sent.
var deciding: bool = false
var decision_queue: Array = []
var decision_index: int = 0
var decision_chooser: String = ""
var pending_preview: Dictionary = {}


func rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.seed = rng_seed
		if rng_state != 0:
			_rng.state = rng_state
	return _rng


## Shuffles `arr` in place with the game's own generator.
func shuffle(arr: Array) -> void:
	var g: RandomNumberGenerator = rng()
	for i: int in range(arr.size() - 1, 0, -1):
		var j: int = g.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


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
		"solo": solo, "capital_coord": {"x": capital_coord.x, "y": capital_coord.y},
		"hexes": hexes_out, "players": players_out, "legions": legions_out, "hordes": hordes_out,
		"druids_in_play": druids_out,
		"item_deck": item_deck.duplicate(), "item_discard": item_discard.duplicate(),
		"quest_deck": quest_deck.duplicate(), "quest_discard": quest_discard.duplicate(),
		"item_market": item_market.duplicate(), "quest_row": quest_row.duplicate(),
		"flipped_market": flipped_market.duplicate(), "quest_items": quest_items.duplicate(true),
		"legion_deck": legion_deck.duplicate(), "horde_deck": horde_deck.duplicate(),
		"legion_deck_tokens": legion_deck_tokens, "horde_deck_tokens": horde_deck_tokens,
		"coven_held_ap": coven_held_ap.duplicate(),
		"capital_flipped": capital_flipped, "banished_returned": banished_returned,
		"daggers": daggers.duplicate(), "open_build_until_turn_end": open_build_until_turn_end,
		"event_decks": _stringify_int_keys(event_decks),
		"chapter_events": _stringify_int_keys(chapter_events), "latest_event": latest_event,
		"empire_vp": empire_vp, "chaos_vp": chaos_vp,
		"imperial_graveyard": imperial_graveyard.duplicate(), "chaos_graveyard": chaos_graveyard.duplicate(),
		"aether_pool": aether_pool,
		"first_player_index": first_player_index, "current_player_index": current_player_index,
		"phase_log": phase_log,
		"rng_seed": rng_seed, "rng_state": _rng.state if _rng != null else rng_state,
		"pending_decision": pending_decision.duplicate(true),
	}


static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.phase = d.get("phase", Phase.REFRESH) as Phase
	s.chapter = d.get("chapter", 1)
	s.max_chapters = d.get("max_chapters", 2)
	s.difficulty = d.get("difficulty", "Veteran")
	s.solo = bool(d.get("solo", false))
	var capital_in: Dictionary = d.get("capital_coord", {"x": 0, "y": 0})
	s.capital_coord = Vector2i(capital_in.get("x", 0), capital_in.get("y", 0))

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
	for v: Variant in (d.get("item_market", []) as Array):
		s.item_market.append(str(v))
	for v: Variant in (d.get("quest_row", []) as Array):
		s.quest_row.append(str(v))
	for v: Variant in (d.get("flipped_market", []) as Array):
		s.flipped_market.append(str(v))
	s.quest_items = (d.get("quest_items", {}) as Dictionary).duplicate(true)
	for v: Variant in (d.get("legion_deck", []) as Array):
		s.legion_deck.append(str(v))
	for v: Variant in (d.get("horde_deck", []) as Array):
		s.horde_deck.append(str(v))
	s.legion_deck_tokens = int(d.get("legion_deck_tokens", 0))
	s.horde_deck_tokens = int(d.get("horde_deck_tokens", 0))
	s.coven_held_ap = (d.get("coven_held_ap", {}) as Dictionary).duplicate()
	s.capital_flipped = bool(d.get("capital_flipped", false))
	s.banished_returned = bool(d.get("banished_returned", false))
	s.daggers = (d.get("daggers", {}) as Dictionary).duplicate()
	s.open_build_until_turn_end = bool(d.get("open_build_until_turn_end", false))
	s.event_decks = _intify_keys(d.get("event_decks", {}))
	s.chapter_events = _intify_keys(d.get("chapter_events", {}))
	s.latest_event = str(d.get("latest_event", ""))

	s.empire_vp = d.get("empire_vp", 0)
	s.chaos_vp = d.get("chaos_vp", 0)
	s.imperial_graveyard = (d.get("imperial_graveyard", {}) as Dictionary).duplicate()
	s.chaos_graveyard = (d.get("chaos_graveyard", {}) as Dictionary).duplicate()
	s.aether_pool = d.get("aether_pool", 7)
	s.first_player_index = d.get("first_player_index", 0)
	s.current_player_index = d.get("current_player_index", 0)
	s.phase_log = d.get("phase_log", "")
	s.rng_seed = int(d.get("rng_seed", 0))
	s.rng_state = int(d.get("rng_state", 0))
	s.pending_decision = (d.get("pending_decision", {}) as Dictionary).duplicate(true)
	return s


func find_player(faction: String) -> PlayerFactionState:
	for p: PlayerFactionState in players:
		if p.faction == faction:
			return p
	return null


func get_hex(coord: Vector2i) -> HexTileState:
	return hexes.get(coord)


## True if impassable terrain on either hex lies along their shared edge.
## Rulebook p14: hexes with impassable terrain between them are not
## adjacent for player Units, Skeletons, Hordes and Legions - Heroes may
## cross.
func edge_blocked(a: Vector2i, b: Vector2i) -> bool:
	var d: int = HexMath.clockwise_index(a, b)
	if d < 0:
		return false
	var ta: HexTileState = hexes.get(a)
	if ta != null and ta.impassable_dirs().has(d):
		return true
	var tb: HexTileState = hexes.get(b)
	return tb != null and tb.impassable_dirs().has((d + 3) % 6)


## Steps from every reachable board hex to `target` along routes that
## never cross impassable terrain (breadth-first). Unreachable hexes are
## absent. Legions/Hordes count routes this way (rulebook p54-55).
func route_distances(target: Vector2i) -> Dictionary:
	var dist: Dictionary = {target: 0}
	var frontier: Array[Vector2i] = [target]
	while not frontier.is_empty():
		var next: Array[Vector2i] = []
		for c: Vector2i in frontier:
			for n: Vector2i in HexMath.neighbors(c):
				if dist.has(n) or not hexes.has(n) or edge_blocked(c, n):
					continue
				dist[n] = int(dist[c]) + 1
				next.append(n)
		frontier = next
	return dist


func ensure_hex(coord: Vector2i, default_role: String = "outer") -> HexTileState:
	if not hexes.has(coord):
		var tile := HexTileState.new()
		tile.role = default_role
		hexes[coord] = tile
	return hexes[coord]


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
