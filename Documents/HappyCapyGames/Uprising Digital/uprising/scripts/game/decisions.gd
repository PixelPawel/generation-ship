extends RefCounted

## Choices the rules leave to the players: where a Horde or Legion goes,
## which faction a new Legion targets and on which of its tied Havens, the
## False Messiah's ties, where Orb of Storms or A Deal with Demons moves an
## enemy (rulebook p52-53: "Syndra decides...", "he places the standee on an
## empty hex in the Fog Grave").
##
## The engine resolves an action in one go, so a choice works by replay. The
## host runs the action with GameState.deciding on; the first choice not yet
## made is recorded in pending_decision along with the board at that moment
## (pending_preview), the engine carries on with its own pick so the run can
## finish, and that run is thrown away. Everyone sees the moment of the
## choice; when the chooser answers, the host runs the action again from its
## snapshot with the answers given so far - same seeded dice
## (GameState.rng()), same board - until nothing is missing.
## Outside that flow (tests, setup) the engine's own pick stands.
## No class_name - preload it.


## One of `options` (hexes) for `kind`; `fallback` is the engine's own pick.
static func choose_hex(state: GameState, kind: String, options: Array[Vector2i], prompt: String, fallback: Vector2i) -> Vector2i:
	if not state.deciding or options.size() <= 1:
		return fallback
	var answer: Variant = _next_answer(state)
	if answer is Dictionary:
		var c := Vector2i(int((answer as Dictionary).get("x", 0)), int((answer as Dictionary).get("y", 0)))
		return c if options.has(c) else fallback
	var list: Array = []
	for o: Vector2i in options:
		list.append({"x": o.x, "y": o.y})
	_ask(state, kind, prompt, list, "hex")
	return fallback


## One of `options` (names, e.g. factions) for `kind`.
static func choose_name(state: GameState, kind: String, options: Array[String], prompt: String, fallback: String) -> String:
	if not state.deciding or options.size() <= 1:
		return fallback
	var answer: Variant = _next_answer(state)
	if answer is Dictionary:
		var v: String = str((answer as Dictionary).get("name", ""))
		return v if options.has(v) else fallback
	var list: Array = []
	for o: String in options:
		list.append({"name": o})
	_ask(state, kind, prompt, list, "name")
	return fallback


## Next answer from the replayed decisions, or null when it hasn't been given.
static func _next_answer(state: GameState) -> Variant:
	if state.decision_index < state.decision_queue.size():
		var a: Variant = state.decision_queue[state.decision_index]
		state.decision_index += 1
		return a
	return null


static func _ask(state: GameState, kind: String, prompt: String, options: Array, shape: String) -> void:
	if not state.pending_decision.is_empty():
		return  # only the first open question is asked; later ones follow on replay
	state.pending_decision = {
		"kind": kind, "prompt": prompt, "chooser": state.decision_chooser,
		"options": options, "shape": shape, "index": state.decision_index,
	}
	# An allied Hero acting sits in the main Hero's fields (swap_heroes);
	# the board everyone sees shows both Heroes where they belong.
	var swapped: Array[PlayerFactionState] = []
	for p: PlayerFactionState in state.players:
		if p.heroes_swapped:
			p.swap_heroes()
			swapped.append(p)
	state.pending_preview = state.to_dict()
	for p2: PlayerFactionState in swapped:
		p2.swap_heroes()


## A decision a peer sends back: does `answer` fit the open question?
static func valid_answer(pending: Dictionary, answer: Dictionary) -> bool:
	for o: Variant in (pending.get("options", []) as Array):
		var opt: Dictionary = o
		if str(pending.get("shape", "hex")) == "hex":
			if int(opt.get("x", 0)) == int(answer.get("x", -999)) and int(opt.get("y", 0)) == int(answer.get("y", -999)):
				return true
		elif str(opt.get("name", "")) == str(answer.get("name", "")):
			return true
	return false
