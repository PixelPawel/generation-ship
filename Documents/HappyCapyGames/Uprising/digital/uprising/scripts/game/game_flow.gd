class_name GameFlow
extends RefCounted
## Master orchestrator for the 7-Phase Chapter cycle (rulebook p15-31).
## Host-only, like GameActions/NemesisAI -- ties together the phase-specific
## logic that already exists (ChapterFlow's Refresh/Events/Production math,
## Scoring, NemesisAI's Legion/Horde activation) into one `advance_phase()`
## call per phase transition. GameSetup's output is already a "post-Refresh
## Chapter 1" state (phase == REFRESH), so the very first call to
## advance_phase() moves it into Events.
##
## What stays manual, per the hybrid/assisted automation-scope decision:
## resolving the Chapter's actual Event card text (only the Threat/token
## mechanics are automated), drawing/picking Feats in Build, any Quest/Item/
## Feat effect text, and resolving pending_combats (Combat itself is still
## blocked on missing dice-color-per-Unit data). advance_phase() surfaces
## what's expected of the players in its "reason" string at each step.
##
## Known simplification: Nemesis activation order should be the cards'
## PRINTED INITIATIVE (rulebook p27), which isn't in the digitized CSV data
## (same class of gap as the player-board tables, but not yet found on any
## examined player-aid image). This resolves every Legion/Horde in ascending
## `id` order instead (i.e. the order they entered play) -- a deterministic,
## documented stand-in, not a transcription. Revisit if initiative numbers
## turn up on individual card art.

## Every player faction that hasn't finished their Actions Phase turn yet
## (still has AP left and hasn't voluntarily Passed). Exposed for the UI to
## show "waiting on: ..." as well as being used internally to gate the
## Actions -> Nemesis transition.
static func active_players(state: GameState) -> Array[String]:
	var active: Array[String] = []
	for p in state.players:
		if not p.has_passed and p.action_points > 0:
			active.append(p.faction)
	return active


## Moves `state` from its current phase into the next one, running whatever
## automatic work that phase entails. Returns {"ok", "reason", ...}; "ok":
## false means nothing happened (e.g. Actions Phase isn't finished yet) --
## check "reason" for why. Call this again after the players have done
## whatever the current phase's "reason" asked for.
static func advance_phase(state: GameState, card_db: Node) -> Dictionary:
	match state.phase:
		GameState.Phase.REFRESH:
			ChapterFlow.events_phase_threat_step(state)
			var event_name := ChapterFlow.draw_event_card(state)
			return {
				"ok": true,
				"reason": (
					"Events Phase: Threat +2 applied to all Legions/Hordes. Resolve '%s' manually -- use Spawn Legion/Spawn Horde for anything it places, then advance again to hand out Activation Tokens and move to Build." % event_name
					if event_name != "" else
					"Events Phase: Threat +2 applied to all Legions/Hordes. No Event card left to draw this Chapter. Advance again to hand out Activation Tokens and move to Build."
				),
				"event": event_name,
			}

		GameState.Phase.EVENTS:
			ChapterFlow.events_phase_token_step(state)
			state.phase = GameState.Phase.BUILD
			return {
				"ok": true,
				"reason": "1 Activation Token placed on every Legion/Horde in play. Build Phase: draw 2 Feats and pick 1 manually per Hero, then submit build_unit/build_defense actions. Advance again once everyone's done building.",
			}

		GameState.Phase.BUILD:
			_start_actions_phase(state)
			return {"ok": true, "reason": "Actions Phase started -- players spend AP via GameActions until out or Pass."}

		GameState.Phase.ACTIONS:
			var waiting := active_players(state)
			if not waiting.is_empty():
				return {"ok": false, "reason": "still waiting on: %s" % ", ".join(waiting), "waiting_on": waiting}
			_run_nemesis_phase(state)
			return {
				"ok": true,
				"reason": "Nemesis Phase resolved. Check pending_combats for any fights that need resolving manually.",
				"pending_combats": state.pending_combats.duplicate(),
			}

		GameState.Phase.NEMESIS:
			ChapterFlow.production_phase_haven_bonus(state, card_db)
			return {"ok": true, "reason": "Production Phase resolved -- resources granted."}

		GameState.Phase.PRODUCTION:
			var deltas := Scoring.score_chapter(state, card_db)
			state.phase = GameState.Phase.SCORING
			return {"ok": true, "reason": "Scoring Phase resolved.", "scoring": deltas}

		GameState.Phase.SCORING:
			return _end_chapter_or_game(state)

		_:
			return {"ok": false, "reason": "unknown phase"}


## Bots start already-Passed -- a "simple dummy" never takes an Action, so
## there's nothing to wait for and no separate bot-turn logic is needed;
## active_players()/the Actions -> Nemesis gate above already just works.
static func _start_actions_phase(state: GameState) -> void:
	state.current_player_index = state.first_player_index
	for p in state.players:
		p.has_passed = p.is_bot
	state.phase = GameState.Phase.ACTIONS


## Rulebook p27: activate every Legion/Horde once per Activation Token it
## holds, card by card in (approximated, see class docstring) initiative
## order -- fully draining one card's tokens before moving to the next.
static func _run_nemesis_phase(state: GameState) -> void:
	var units: Array = []
	units.append_array(state.legions)
	units.append_array(state.hordes)
	units.sort_custom(func(a, b): return a.id < b.id)

	for u in units:
		while u.activation_tokens > 0:
			if u is LegionInstance:
				NemesisAI.activate_legion(state, u.id)
			else:
				NemesisAI.activate_horde(state, u.id)

	state.phase = GameState.Phase.NEMESIS


static func _end_chapter_or_game(state: GameState) -> Dictionary:
	if state.chapter >= state.max_chapters:
		var result := ChapterFlow.check_win_loss(state)
		return {"ok": true, "reason": "Final Chapter scored -- game over.", "game_over": true, "result": result}
	state.chapter += 1
	ChapterFlow.refresh_phase(state)
	return {"ok": true, "reason": "Chapter %d begins." % state.chapter}
