extends SceneTree
## Headless smoke test: `godot --headless --script res://scripts/game/test_druid_data.gd`
## Exercises DruidData.check_condition for all 9 Core Druids directly,
## verified against the exact EN text in
## assets/data/UPRISING _ FULL CARD DETAILS - Druids.csv.

var checks: Array = []


func _check(label: String, ok: bool) -> void:
	checks.append([label, ok])


func _hex(state: GameState, coord: Vector2i) -> HexTile:
	var t := HexTile.new()
	t.coord = coord
	state.set_hex(t)
	return state.get_hex(coord)


func _initialize() -> void:
	# --- Deep Dweller: "If there is 1+ Horde in play, place 1 AETHER here." ---
	var s1 := GameState.new()
	_check("Deep Dweller: false with 0 Hordes", not DruidData.check_condition("Deep Dweller", s1))
	var horde := HordeInstance.new()
	horde.id = s1.next_nemesis_id()
	s1.hordes.append(horde)
	_check("Deep Dweller: true with 1 Horde", DruidData.check_condition("Deep Dweller", s1))

	# --- Mountain Heart: "If there is 1+ Legion in play, place 1 AETHER here." ---
	var s2 := GameState.new()
	_check("Mountain Heart: false with 0 Legions", not DruidData.check_condition("Mountain Heart", s2))
	var legion := LegionInstance.new()
	legion.id = s2.next_nemesis_id()
	s2.legions.append(legion)
	_check("Mountain Heart: true with 1 Legion", DruidData.check_condition("Mountain Heart", s2))

	# --- Faceless One: "If Chaos has equal or more VP than any player..." ---
	# ("any" read as existential -- true as soon as Chaos clears the LOWEST player's VP)
	var s3 := GameState.new()
	var p3a := PlayerFactionState.new()
	p3a.victory_points = 5
	var p3b := PlayerFactionState.new()
	p3b.victory_points = 10
	s3.players.append(p3a)
	s3.players.append(p3b)
	s3.chaos_vp = 4
	_check("Faceless One: false when Chaos is below every player's VP", not DruidData.check_condition("Faceless One", s3))
	s3.chaos_vp = 5
	_check("Faceless One: true once Chaos equals the lowest player's VP", DruidData.check_condition("Faceless One", s3))

	# --- Shapeshifter: same "any" pattern, against Empire ---
	var s4 := GameState.new()
	s4.players.append(p3a)
	s4.players.append(p3b)
	s4.empire_vp = 4
	_check("Shapeshifter: false when Empire is below every player's VP", not DruidData.check_condition("Shapeshifter", s4))
	s4.empire_vp = 5
	_check("Shapeshifter: true once Empire equals the lowest player's VP", DruidData.check_condition("Shapeshifter", s4))

	# --- Silence: "If the Empire OR Chaos has more VP than ALL players..." ---
	# (capitalized ALL -- must clear the HIGHEST player's VP, not just one)
	var s5 := GameState.new()
	s5.players.append(p3a)
	s5.players.append(p3b)
	s5.empire_vp = 10  # equal to the highest player -- not yet MORE than all
	s5.chaos_vp = 0
	_check("Silence: false when merely tied with the highest player", not DruidData.check_condition("Silence", s5))
	s5.empire_vp = 11
	_check("Silence: true once Empire exceeds the highest player's VP", DruidData.check_condition("Silence", s5))
	s5.empire_vp = 0
	s5.chaos_vp = 11
	_check("Silence: true via Chaos alone exceeding the highest player's VP", DruidData.check_condition("Silence", s5))

	# --- Treemother: "If any player has ZERO Units in play..." ---
	var s6 := GameState.new()
	var p6a := PlayerFactionState.new()
	p6a.faction = "Druwhn"
	var p6b := PlayerFactionState.new()
	p6b.faction = "Krowh"
	s6.players.append(p6a)
	s6.players.append(p6b)
	var tile6 := _hex(s6, Vector2i(1, 0))
	tile6.units = {"Druwhn": ["Warrior"]}
	_check("Treemother: true when a player (Krowh) has zero Units anywhere", DruidData.check_condition("Treemother", s6))
	var tile6b := _hex(s6, Vector2i(2, 0))
	tile6b.units = {"Krowh": ["Warrior"]}
	_check("Treemother: false once every player has 1+ Units", not DruidData.check_condition("Treemother", s6))

	# --- Red Hand: "If there are 5+ Skeletons on hexes..." (sums skeleton_count) ---
	var s7 := GameState.new()
	for i in 3:
		_hex(s7, Vector2i(i, 0)).skeleton_count = 1
	_check("Red Hand: false with only 3 Skeletons", not DruidData.check_condition("Red Hand", s7))
	_hex(s7, Vector2i(10, 0)).skeleton_count = 2
	_check("Red Hand: true once total reaches 5", DruidData.check_condition("Red Hand", s7))

	# --- Wanderer: "If there are 5+ Curses on hexes..." (hex count, not a sum) ---
	var s8 := GameState.new()
	for i in 4:
		_hex(s8, Vector2i(i, 0)).has_curse = true
	_check("Wanderer: false with only 4 cursed hexes", not DruidData.check_condition("Wanderer", s8))
	_hex(s8, Vector2i(10, 0)).has_curse = true
	_check("Wanderer: true once 5 hexes are cursed", DruidData.check_condition("Wanderer", s8))

	# --- Watcher: "If there are 7+ hexes with Garrisons..." ---
	var s9 := GameState.new()
	for i in 6:
		_hex(s9, Vector2i(i, 0)).garrison_level = 1
	_check("Watcher: false with only 6 garrisoned hexes", not DruidData.check_condition("Watcher", s9))
	_hex(s9, Vector2i(10, 0)).garrison_level = 3
	_check("Watcher: true once 7 hexes carry a Garrison", DruidData.check_condition("Watcher", s9))

	# --- Unknown card name defaults to false rather than erroring ---
	_check("unknown Druid name returns false", not DruidData.check_condition("Not A Real Druid", GameState.new()))

	var all_ok := true
	for c in checks:
		var label: String = c[0]
		var ok: bool = c[1]
		print(("OK   " if ok else "FAIL "), label)
		if not ok:
			all_ok = false

	print("\nALL CHECKS %s" % ("PASSED" if all_ok else "FAILED"))
	quit(0 if all_ok else 1)
