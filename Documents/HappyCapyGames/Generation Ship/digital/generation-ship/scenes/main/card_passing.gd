extends RefCounted
# Cards passed between players: Interfleet Comms (draw a pool, everyone picks
# in turn), 'every player draws' (Gas Cloud), and Generation Fleet's Shuttle
# (drag a hand card onto a teammate's row) and Dimension Pocket (every hand
# passes left). Moved out of main.gd; static functions on Main. The RPC entry
# points stay on Main as one-line @rpc stubs, forwarding here.

# Client → Host: I placed Interfleet Comms; draw the shared pool and start.
static func _rpc_request_interfleet(main: Main) -> void:
	if not main.multiplayer.is_server():
		return
	_server_start_interfleet(main, main.multiplayer.get_remote_sender_id())

# Client → Host: I'm keeping the pool card at this index.
static func _rpc_request_interfleet_pick(main: Main, idx: int) -> void:
	if not main.multiplayer.is_server():
		return
	_server_handle_interfleet_pick(main, main.multiplayer.get_remote_sender_id(), idx)

# Host → All: sequence started — full pool, full pick order, who triggered it.
static func _rpc_sync_interfleet_started(main: Main, pool_refs: Array, order: Array, initiator_id: int) -> void:
	main._interfleet_pool_refs = pool_refs.duplicate()
	main._interfleet_remaining_order = []
	for v: Variant in order:
		main._interfleet_remaining_order.append(int(v))
	main._interfleet_initiator_id = initiator_id
	main._interfleet_active = true
	main._effect_mode = Main.EffectMode.EFFECT_INTERFLEET_PICK
	var iname: String = GameNetwork.player_names.get(initiator_id, "Player")
	main._log_action(main.tr("%s: Interfleet Comms — drew %d card(s) to pass around") % [iname, main._interfleet_pool_refs.size()], Color(0.6, 0.85, 1.0))
	if not main._interfleet_remaining_order.is_empty():
		_update_interfleet_ui(main, main._interfleet_remaining_order[0])

# Host → All: pool/order changed after a pick (still 2+ players left to serve).
static func _rpc_sync_interfleet_state(main: Main, pool_refs: Array, order: Array) -> void:
	main._interfleet_pool_refs = pool_refs.duplicate()
	main._interfleet_remaining_order = []
	for v: Variant in order:
		main._interfleet_remaining_order.append(int(v))
	if not main._interfleet_remaining_order.is_empty():
		_update_interfleet_ui(main, main._interfleet_remaining_order[0])

# Host → All: a specific player kept a specific card.
static func _rpc_sync_interfleet_pick_result(main: Main, peer_id: int, card_ref: Dictionary) -> void:
	var my_id: int = main.multiplayer.get_unique_id()
	var cd: CardData = CardRef.from_ref(card_ref)
	if my_id == peer_id:
		if cd:
			main.get_node("Board").add_specific_card_to_hand(cd)
			main._log_action(main.tr("You kept %s (Interfleet Comms)") % cd.card_name, Color(0.6, 1.0, 0.6))
		main._broadcast_my_state()
	elif main.multiplayer.is_server() and GameNetwork.is_bot(peer_id):
		if cd:
			var hand: Array[CardData] = BotTurn.bot_hand(main, peer_id)
			hand.append(cd)
			BotTurn.bot_set_hand(main, peer_id, hand)
	else:
		var pname: String = GameNetwork.player_names.get(peer_id, "Player")
		main._log_action(main.tr("%s kept a card (Interfleet Comms)") % pname, Color(0.6, 0.85, 1.0))

# Host → All: sequence complete — the last player auto-received the final
# card; resumes the initiator's own effect queue.
static func _rpc_sync_interfleet_finished(main: Main, recipient_id: int, card_ref: Dictionary, initiator_id: int) -> void:
	main._interfleet_active = false
	main._interfleet_awaiting_pick = false
	main._hide_effect_hint()
	main._choice_popup.hide()
	if main._effect_mode == Main.EffectMode.EFFECT_INTERFLEET_PICK:
		main._effect_mode = Main.EffectMode.NONE
	var my_id: int = main.multiplayer.get_unique_id()
	var cd: CardData = CardRef.from_ref(card_ref)
	if my_id == recipient_id:
		if cd:
			main.get_node("Board").add_specific_card_to_hand(cd)
		main._broadcast_my_state()
	elif main.multiplayer.is_server() and GameNetwork.is_bot(recipient_id):
		if cd:
			var hand: Array[CardData] = BotTurn.bot_hand(main, recipient_id)
			hand.append(cd)
			BotTurn.bot_set_hand(main, recipient_id, hand)
	var rname: String = GameNetwork.player_names.get(recipient_id, "Player")
	main._log_action(main.tr("%s automatically received the last Interfleet Comms card") % rname, Color(0.6, 0.85, 1.0))
	if my_id == initiator_id:
		main._process_next_effect()

# Client → Host: I placed a "draw_all_players" card; deal it for everyone.
static func _rpc_request_draw_all_players(main: Main, count: int, source: String) -> void:
	if not main.multiplayer.is_server():
		return
	_server_handle_draw_all_players(main, count, main.multiplayer.get_remote_sender_id(), source)

# Host-only: deal to real peers via the shared hand-delivery mechanism, deal
# to bots inline (their own separate, non-networked path), then tell
# everyone it's done so the initiator's effect queue can resume.
static func _server_handle_draw_all_players(main: Main, count: int, initiator_id: int, source: String) -> void:
	main._server_deal_hands_to_real_peers(count)
	for bot_id: int in GameNetwork.bot_ids:
		BotTurn.apply_bot_effect_steps(main, bot_id, [{type = "draw", count = count}])
	BotTurn.broadcast_bot_states(main)
	main._rpc_sync_draw_all_finished.rpc(initiator_id, source, count)

# Host → All: the draw-for-everyone is complete — log it once, and resume the
# initiator's own effect queue if it's still waiting on this.
static func _rpc_sync_draw_all_finished(main: Main, initiator_id: int, source: String, count: int) -> void:
	main._log_action(main.tr("%s: everyone draws %d card(s)") % [source, count], Color(0.6, 0.85, 0.75))
	if main._effect_mode == Main.EffectMode.EFFECT_AWAITING_ALL_DRAW and main.multiplayer.get_unique_id() == initiator_id:
		main._effect_mode = Main.EffectMode.NONE
		main._process_next_effect()

static func _server_start_interfleet(main: Main, initiator_id: int) -> void:
	var order: Array[int] = GameNetwork.player_order.duplicate()
	var start_pos: int = maxi(order.find(initiator_id), 0)
	var n: int = order.size()
	var rotated: Array[int] = []
	for j: int in n:
		rotated.append(order[(start_pos + j) % n])
	var drawn: Array[CardData] = main.get_node("Board").draw_card_data(n)
	if drawn.size() < n:
		rotated = rotated.slice(0, drawn.size())
	var pool_refs: Array = []
	for cd: CardData in drawn:
		pool_refs.append(CardRef.to_ref(cd))
	main._interfleet_initiator_id = initiator_id
	main._interfleet_remaining_order = rotated
	main._interfleet_pool_refs = pool_refs
	main._interfleet_active = true
	main._rpc_sync_interfleet_started.rpc(pool_refs, rotated, initiator_id)
	_server_interfleet_advance(main)

static func _server_interfleet_advance(main: Main) -> void:
	if main._interfleet_remaining_order.size() <= 1:
		_server_finish_interfleet(main)
		return
	var active_id: int = main._interfleet_remaining_order[0]
	main._rpc_sync_interfleet_state.rpc(main._interfleet_pool_refs, main._interfleet_remaining_order)
	if GameNetwork.is_bot(active_id):
		var _bid: int = active_id
		main.get_tree().create_timer(0.6).timeout.connect(func() -> void: BotTurn.bot_decide_interfleet_pick(main, _bid))

static func _server_handle_interfleet_pick(main: Main, peer_id: int, idx: int) -> void:
	if main._interfleet_remaining_order.is_empty() or peer_id != main._interfleet_remaining_order[0]:
		return
	if idx < 0 or idx >= main._interfleet_pool_refs.size():
		return
	var chosen_ref: Dictionary = main._interfleet_pool_refs[idx]
	main._interfleet_pool_refs.remove_at(idx)
	main._interfleet_remaining_order.remove_at(0)
	main._rpc_sync_interfleet_pick_result.rpc(peer_id, chosen_ref)
	_server_interfleet_advance(main)

static func _server_finish_interfleet(main: Main) -> void:
	var recipient_id: int = main._interfleet_remaining_order[0] if not main._interfleet_remaining_order.is_empty() else main._interfleet_initiator_id
	var card_ref: Dictionary = main._interfleet_pool_refs[0] if not main._interfleet_pool_refs.is_empty() else {}
	var initiator_id: int = main._interfleet_initiator_id
	main._interfleet_remaining_order = []
	main._interfleet_pool_refs = []
	main._interfleet_active = false
	main._rpc_sync_interfleet_finished.rpc(recipient_id, card_ref, initiator_id)

# Shown only to the active picker (a mandatory choice, no skip); everyone
# else sees the existing effect-hint panel — same "your turn" vs. "waiting"
# framing the sector-reveal flow already uses, no new UI nodes needed.
static func _update_interfleet_ui(main: Main, active_id: int) -> void:
	var my_id: int = main.multiplayer.get_unique_id()
	if my_id == active_id:
		var pool: Array[CardData] = []
		for ref: Dictionary in main._interfleet_pool_refs:
			var cd: CardData = CardRef.from_ref(ref)
			if cd:
				pool.append(cd)
		main._interfleet_awaiting_pick = true
		main._hide_effect_hint()
		main._choice_popup.show_card_choices(main.tr("Interfleet Comms — keep one card:"), pool, false)
	else:
		main._interfleet_awaiting_pick = false
		main._choice_popup.hide()
		var pname: String = GameNetwork.player_names.get(active_id, "Player")
		main._show_effect_hint(main.tr("Waiting for %s to pick a card (Interfleet Comms)…") % pname)

# Called by Board while a hand card is dropped: the teammate whose row is under
# the mouse on the info screen (0 = none).
static func fleet_shuttle_target_at_mouse(main: Main) -> int:
	if not main._market_panel or not main._market_panel.visible or not main._info_screen_mesh:
		return 0
	var cam: Camera3D = main.get_viewport().get_camera_3d()
	if not cam:
		return 0
	var mouse: Vector2 = main.get_viewport().get_mouse_position()
	var origin: Vector3 = cam.project_ray_origin(mouse)
	var dir: Vector3 = cam.project_ray_normal(mouse)
	var xf: Transform3D = main._info_screen_mesh.global_transform
	var plane: Plane = Plane(xf.basis.z.normalized(), xf.origin)
	var hit: Variant = plane.intersects_ray(origin, dir)
	if hit == null:
		return 0
	var local: Vector3 = main._info_screen_mesh.to_local(hit as Vector3)
	var aabb: AABB = main._info_screen_mesh.mesh.get_aabb()
	var u: float = (local.x - aabb.position.x) / aabb.size.x
	var v: float = 1.0 - (local.y - aabb.position.y) / aabb.size.y
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return 0
	return main._market_panel.opponent_at(Vector2(u * float(main._info_viewport.size.x), v * float(main._info_viewport.size.y)))

static func _fleet_on_shuttle_requested(main: Main, cd: CardData, target: int) -> void:
	if main._fleet == null or main._fleet_busy or main._effect_mode != Main.EffectMode.NONE:
		return
	var cost: int = Main.FleetRules.shuttle_cost()
	var who: String = str(GameNetwork.player_names.get(target, "Player"))
	var pay: Dictionary = {}
	if cost > 0:
		pay = main.get_node("Board")._compute_payment(CardData.SupplyColor.DUST, cost)
		if pay.is_empty():
			main._log_action(main.tr("The shuttle costs %d Dust — you can't pay it.") % cost, Main.FleetFlow.DANGER_COLOR)
			return
	var prompt: String = main.tr("Pay %d Dust to send %s to %s?") % [cost, CardDatabase.display_name(cd), who]
	main._fleet_choice_active = true
	main._choice_popup.show_choices(prompt, [main.tr("Send"), main.tr("Cancel")], false, [], cd)
	var pick: int = await main._choice_popup.choice_made
	main._fleet_choice_active = false
	if pick != 0:
		return
	var node: Node3D = null
	for c: Node3D in main.get_node("Hand").get_cards():
		if c.card_data == cd:
			node = c
			break
	if node == null:
		return
	for col: int in pay:
		main._cs_display.spend_supply(col, int(pay[col]))
	main.get_node("Hand").remove_card_fly_out(node)
	main.get_node("Board").refresh_hand_discounts()
	var ref: Dictionary = CardRef.to_ref(cd)
	if main.multiplayer.is_server():
		_server_fleet_shuttle(main, main.multiplayer.get_unique_id(), target, ref)
	else:
		main._rpc_fleet_shuttle.rpc_id(1, target, ref)
	main._broadcast_my_state()

static func _rpc_fleet_shuttle(main: Main, target: int, ref: Dictionary) -> void:
	if main.multiplayer.is_server():
		_server_fleet_shuttle(main, main.multiplayer.get_remote_sender_id(), target, ref)

static func _server_fleet_shuttle(main: Main, sender: int, target: int, ref: Dictionary) -> void:
	if GameNetwork.is_bot(target):
		var hand: Array[CardData] = BotTurn.bot_hand(main, target)
		hand.append(CardRef.from_ref(ref))
		BotTurn.bot_set_hand(main, target, hand)
		BotTurn.broadcast_bot_states(main)
	main._rpc_fleet_shuttle_delivered.rpc(sender, target, ref)

static func _rpc_fleet_shuttle_delivered(main: Main, sender: int, target: int, ref: Dictionary) -> void:
	var cd: CardData = CardRef.from_ref(ref)
	var from: String = str(GameNetwork.player_names.get(sender, "Player"))
	var to: String = str(GameNetwork.player_names.get(target, "Player"))
	if target == main.multiplayer.get_unique_id():
		main.get_node("Board").add_specific_card_to_hand(cd)
		main.get_node("Board").refresh_hand_discounts()
		main._log_action(main.tr("%s shuttled you %s.") % [from, CardDatabase.display_name(cd)], Color(0.6, 0.9, 1.0))
		main._broadcast_my_state()
	else:
		main._log_action(main.tr("%s shuttled a card to %s.") % [from, to], Color(0.6, 0.9, 1.0))

static func fleet_pass_hand_left(main: Main) -> void:
	var refs: Array = []
	for c: Node3D in main.get_node("Hand").get_cards():
		if c.card_data:
			refs.append(CardRef.to_ref(c.card_data))
	for c: Node3D in main.get_node("Hand").get_cards():
		main.get_node("Hand").remove_card_fly_out(c)
	if main.multiplayer.is_server():
		_server_fleet_pass_hand(main, main.multiplayer.get_unique_id(), refs)
	else:
		main._rpc_fleet_pass_hand.rpc_id(1, refs)
	await main.fleet_hand_passed

static func _rpc_fleet_pass_hand(main: Main, refs: Array) -> void:
	if main.multiplayer.is_server():
		_server_fleet_pass_hand(main, main.multiplayer.get_remote_sender_id(), refs)

static func _server_fleet_pass_hand(main: Main, pid: int, refs: Array) -> void:
	main._fleet_pass_hands[pid] = refs
	var order: Array[int] = GameNetwork.player_order
	for p: int in order:
		if GameNetwork.is_bot(p):
			var bot_refs: Array = []
			for cd: CardData in BotTurn.bot_hand(main, p):
				bot_refs.append(CardRef.to_ref(cd))
			main._fleet_pass_hands[p] = bot_refs
		elif not main._fleet_pass_hands.has(p):
			return
	var passed: Dictionary = {}
	for i: int in order.size():
		passed[order[(i + 1) % order.size()]] = main._fleet_pass_hands[order[i]]
	main._fleet_pass_hands = {}
	for p: int in order:
		if GameNetwork.is_bot(p):
			var hand: Array[CardData] = []
			for r: Variant in passed[p]:
				hand.append(CardRef.from_ref(r as Dictionary))
			BotTurn.bot_set_hand(main, p, hand)
	BotTurn.broadcast_bot_states(main)
	main._rpc_fleet_hands_passed.rpc(passed)

static func _rpc_fleet_hands_passed(main: Main, passed: Dictionary) -> void:
	var mine: Array = passed.get(main.multiplayer.get_unique_id(), []) as Array
	for r: Variant in mine:
		main.get_node("Board").add_specific_card_to_hand(CardRef.from_ref(r as Dictionary))
	main.get_node("Board").refresh_hand_discounts()
	main._broadcast_my_state()
	main.fleet_hand_passed.emit()
