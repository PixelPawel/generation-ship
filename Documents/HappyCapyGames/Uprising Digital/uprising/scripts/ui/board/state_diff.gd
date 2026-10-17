extends RefCounted

## Turns two consecutive GameStates into board events for effects, purely
## by comparison - no rules code involved. The host mutates its live state
## in place before broadcasting, so play_board keeps a compact snapshot of
## the previous update rather than a reference.
##   const StateDiff := preload("res://scripts/ui/board/state_diff.gd")
##
## Event = {"kind": String, "coord": Vector2i, ...}. Kinds:
##   explore, curse, curse_lifted, garrison, garrison_lost, skeleton,
##   horde_arrival, legion_arrival, nemesis_destroyed, haven, haven_lost,
##   defense (Tower/Wall), units_arrive, units_lost, clash, capital_uprising

static func capture(state: GameState) -> Dictionary:
	var hexes: Dictionary = {}
	for coord: Vector2i in state.hexes.keys():
		var t: HexTileState = state.hexes[coord]
		hexes[coord] = {
			"explored": t.explored, "curse": t.curse, "garrison": t.garrison_level,
			"skeletons": t.skeleton_count, "haven": t.haven_faction, "tower": t.tower,
			"wall": t.wall, "units": t.total_player_units(), "faction": t.player_faction_here(),
		}
	var nemesis: Dictionary = {}
	for l: LegionInstance in state.legions:
		nemesis["legion:%d" % l.id] = {"coord": l.coord, "threat": l.threat, "legion": true}
	for h: HordeInstance in state.hordes:
		nemesis["horde:%d" % h.id] = {"coord": h.coord, "threat": h.threat, "legion": false}
	var heroes: Dictionary = {}
	for p: PlayerFactionState in state.players:
		heroes[p.faction] = p.hero_coord
		if p.has_ally():
			heroes[p.faction + ":ally"] = p.ally_coord
	return {
		"hexes": hexes, "nemesis": nemesis, "heroes": heroes,
		"capital": state.capital_coord, "capital_flipped": state.get("capital_flipped") == true,
	}


static func diff(old: Dictionary, now: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if old.is_empty() or now.is_empty():
		return events
	var oh: Dictionary = old["hexes"]
	var nh: Dictionary = now["hexes"]
	var on: Dictionary = old["nemesis"]
	var nn: Dictionary = now["nemesis"]

	# Nemesis arrivals first, so a Horde born from three Skeletons reads as
	# the Horde arriving rather than Skeletons vanishing.
	var horde_arrived_at: Dictionary = {}
	for key: Variant in nn.keys():
		var n: Dictionary = nn[key]
		if not on.has(key):
			var kind: String = "legion_arrival" if bool(n["legion"]) else "horde_arrival"
			events.append({"kind": kind, "coord": n["coord"], "key": str(key)})
			if not bool(n["legion"]):
				horde_arrived_at[n["coord"]] = true
	for key: Variant in on.keys():
		if not nn.has(key):
			var n: Dictionary = on[key]
			events.append({"kind": "nemesis_destroyed", "coord": n["coord"], "key": str(key), "legion": bool(n["legion"])})
		elif int((nn[key] as Dictionary)["threat"]) < int((on[key] as Dictionary)["threat"]):
			# lost Threat: it was hurt in a fight
			events.append({"kind": "clash", "coord": (nn[key] as Dictionary)["coord"]})

	for coord: Variant in nh.keys():
		if not oh.has(coord):
			continue
		var a: Dictionary = oh[coord]
		var b: Dictionary = nh[coord]
		if not bool(a["explored"]) and bool(b["explored"]):
			events.append({"kind": "explore", "coord": coord})
		if not bool(a["curse"]) and bool(b["curse"]):
			events.append({"kind": "curse", "coord": coord})
		elif bool(a["curse"]) and not bool(b["curse"]):
			events.append({"kind": "curse_lifted", "coord": coord})
		if int(b["garrison"]) > int(a["garrison"]):
			events.append({"kind": "garrison", "coord": coord, "level": int(b["garrison"])})
		elif int(b["garrison"]) < int(a["garrison"]):
			events.append({"kind": "garrison_lost", "coord": coord})
		if int(b["skeletons"]) > int(a["skeletons"]):
			events.append({"kind": "skeleton", "coord": coord})
		elif int(b["skeletons"]) < int(a["skeletons"]) and not horde_arrived_at.has(coord):
			events.append({"kind": "units_lost", "coord": coord})
		if str(a["haven"]).is_empty() and not str(b["haven"]).is_empty():
			events.append({"kind": "haven", "coord": coord, "faction": str(b["haven"])})
		elif not str(a["haven"]).is_empty() and str(b["haven"]).is_empty():
			events.append({"kind": "haven_lost", "coord": coord})
		if (bool(b["tower"]) and not bool(a["tower"])) or (bool(b["wall"]) and not bool(a["wall"])):
			events.append({"kind": "defense", "coord": coord})
		var ua: int = int(a["units"])
		var ub: int = int(b["units"])
		if ub > ua:
			events.append({"kind": "units_arrive", "coord": coord, "count": ub - ua})
		elif ub < ua:
			# Units falling while enemies share or neighbour the hex = a fight.
			var fought: bool = int(a["garrison"]) > int(b["garrison"]) or int(a["skeletons"]) > int(b["skeletons"]) or _nemesis_at(on, coord)
			events.append({"kind": "clash" if fought else "units_lost", "coord": coord})

	if bool(now.get("capital_flipped", false)) and not bool(old.get("capital_flipped", false)):
		events.append({"kind": "capital_uprising", "coord": now["capital"]})
	return events


static func _nemesis_at(nemesis: Dictionary, coord: Variant) -> bool:
	for key: Variant in nemesis.keys():
		if (nemesis[key] as Dictionary)["coord"] == coord:
			return true
	return false
