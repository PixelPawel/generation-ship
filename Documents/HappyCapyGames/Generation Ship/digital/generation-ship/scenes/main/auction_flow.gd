extends RefCounted
# Auctions, bids and card payments: starting/raising/passing an auction (host
# side), the runner-up offer, winning and paying, forfeits, the toasts and
# banners, and the payment-confirm window for normal purchases. Moved out of
# main.gd; static functions on Main. The RPC entry points stay on Main as
# one-line @rpc stubs (RPCs must live on the node), forwarding here.

# Overlays each opponent's market-widget status label with their standing in
# the currently-running auction (leader's live bid, who's currently deciding,
# who's already passed) — restored to the normal turn status via
# _refresh_all_opp_status_labels() once the auction resolves.
static func _set_auction_opponent_statuses(main: Main, remaining_ids: Array, leader_id: int, active_id: int, current_bid: int) -> void:
	if not main._market_panel:
		return
	var my_id: int = main.multiplayer.get_unique_id()
	for peer_id: int in GameNetwork.player_order:
		if peer_id == my_id:
			continue
		if peer_id == leader_id:
			main._market_panel.set_opponent_auction_label(peer_id, main.tr("Bid: %d") % current_bid, Color(1.0, 0.88, 0.35))
		elif peer_id == active_id:
			main._market_panel.set_opponent_auction_label(peer_id, main.tr("Deciding…"), Color(0.5, 0.85, 1.0))
		elif peer_id in remaining_ids:
			main._market_panel.set_opponent_auction_label(peer_id, "", Color(0.7, 0.78, 0.9))
		else:
			main._market_panel.set_opponent_auction_label(peer_id, main.tr("Passed"), Color(0.55, 0.55, 0.65))

# Client → Host: I dragged a card that requires a bid.
static func _rpc_request_auction(main: Main, card_ref: Dictionary, slot_idx: int, is_tech: bool, is_adv: bool, min_bid: int, cost_color_int: int) -> void:
	if not main.multiplayer.is_server():
		return
	_server_start_auction(main, card_ref, slot_idx, is_tech, is_adv, min_bid, cost_color_int, main.multiplayer.get_remote_sender_id())

# Client → Host: I am raising the bid.
static func _rpc_raise_bid(main: Main, amount: int) -> void:
	if not main.multiplayer.is_server():
		return
	_server_handle_raise(main, main.multiplayer.get_remote_sender_id(), amount)

# Client → Host: I am passing on this bid.
static func _rpc_pass_bid(main: Main) -> void:
	if not main.multiplayer.is_server():
		return
	_server_handle_pass_bid(main, main.multiplayer.get_remote_sender_id())

# Client → Host: auction winner is forfeiting; offer card to runner-up.
static func _rpc_notify_auction_forfeit(main: Main) -> void:
	if not main.multiplayer.is_server():
		return
	var _sender: int = main.multiplayer.get_remote_sender_id()
	if _sender != main._auction_initiator_id and _sender != main._auction_leader_id:
		return
	_server_offer_to_runner_up(main)

# Client → Host: runner-up declined the offer; discard the card.
static func _rpc_notify_runner_up_forfeit(main: Main, card_ref: Dictionary) -> void:
	if not main.multiplayer.is_server():
		return
	main._rpc_sync_market_removal.rpc(card_ref)
	main._rpc_sync_runner_up_phase.rpc(false)
	main._rpc_sync_auction_placement_pending.rpc(false)

# Host → Runner-up: you may claim this card at printed cost.
static func _rpc_offer_to_runner_up(main: Main, card_ref: Dictionary, slot_idx: int, is_tech: bool, is_adv: bool, printed_cost: int, cost_color_int: int) -> void:
	_on_runner_up_offer(main, card_ref, slot_idx, is_tech, is_adv, printed_cost, cost_color_int)

# Host → All: runner-up phase started/ended; block end-turn until resolved.
static func _rpc_sync_runner_up_phase(main: Main, active: bool) -> void:
	main._runner_up_phase = active

# Host → All: an auction's card still needs placing (or no longer does).
# See _auction_placement_pending for why this has to be synced to everyone,
# not just tracked on the winner's own client.
static func _rpc_sync_auction_placement_pending(main: Main, pending: bool) -> void:
	main._auction_placement_pending = pending
	if not pending:
		# _try_auto_end_turn() only ever advances *this client's own* turn
		# (it bails immediately unless GameNetwork.is_my_turn()), so it can
		# never end a bot's turn — bots have no client of their own. A bot
		# that started this auction needs its turn ended explicitly here,
		# once the resulting placement (bot or human winner) has fully
		# settled; is_major_action_taken() guards against double-firing if
		# this sync ever arrives more than once for the same turn.
		if main.multiplayer.is_server() and GameNetwork.is_bot(GameNetwork.active_peer_id) and main.get_node("Board").is_major_action_taken():
			main._server_handle_end_turn()
		main._try_auto_end_turn()

# Client (whoever currently owes the placement) → Host: my auction win has
# been placed, recycled, or otherwise resolved — safe to unblock everyone.
static func _rpc_notify_auction_placement_done(main: Main) -> void:
	if not main.multiplayer.is_server():
		return
	main._rpc_sync_auction_placement_pending.rpc(false)

static func _notify_auction_placement_done(main: Main) -> void:
	if not main._auction_win_awaiting_placement:
		return
	main._auction_win_awaiting_placement = false
	if GameNetwork.is_host:
		main._rpc_sync_auction_placement_pending.rpc(false)
	else:
		main._rpc_notify_auction_placement_done.rpc_id(1)

# Host → All: auction has started, show bid popup.
static func _rpc_sync_auction_started(main: Main, card_ref: Dictionary, slot_idx: int, is_tech: bool, is_adv: bool, min_bid: int, cost_color_int: int, initiator_id: int, active_id: int, leader_name: String, remaining_ids: Array) -> void:
	main._auction_card_ref = card_ref
	main._auction_slot_idx = slot_idx
	main._auction_is_tech = is_tech
	main._auction_is_adv = is_adv
	main._auction_cost_color = cost_color_int as CardData.SupplyColor
	main._auction_current_bid = min_bid
	main._auction_leader_id = initiator_id
	main._auction_initiator_id = initiator_id
	var cd: CardData = CardRef.from_ref(card_ref)
	var card_name: String = ""
	if cd:
		card_name = cd.adv_name if (is_adv and not cd.adv_name.is_empty()) else cd.card_name
	var my_id: int = main.multiplayer.get_unique_id()
	var is_active: bool = my_id == active_id
	var can_pass: bool = is_active and my_id != initiator_id
	var _initiator_name: String = GameNetwork.player_names.get(initiator_id, "Player")
	if GameNetwork.is_multiplayer and initiator_id != main.multiplayer.get_unique_id():
		_show_auction_banner(main, main.tr("%s: auction for %s") % [_initiator_name, card_name])
	main._log_action(main.tr("%s: auction for %s") % [_initiator_name, card_name], Color(1.0, 0.72, 0.28))
	main._bid_popup.show_auction(cd, is_adv, min_bid, leader_name, main._auction_cost_color, is_active, can_pass)
	main._auction_active = true
	main._auction_starting = false
	main._show_action_buttons(false)
	UIAudio.play_auction_music()
	_set_auction_opponent_statuses(main, remaining_ids, initiator_id, active_id, min_bid)
	if main.multiplayer.is_server() and GameNetwork.is_bot(active_id):
		var _ab1: int = active_id
		main.get_tree().create_timer(0.6).timeout.connect(func() -> void: BotTurn.bot_decide_bid(main, _ab1))

# Host → All: bid state has changed.
static func _rpc_sync_auction_state(main: Main, current_bid: int, leader_id: int, active_id: int, leader_name: String, remaining_ids: Array) -> void:
	main._auction_current_bid = current_bid
	main._auction_leader_id = leader_id
	var my_id: int = main.multiplayer.get_unique_id()
	var is_active: bool = my_id == active_id
	var can_pass: bool = is_active and my_id != leader_id
	main._bid_popup.update_auction(current_bid, leader_name, is_active, can_pass)
	_set_auction_opponent_statuses(main, remaining_ids, leader_id, active_id, current_bid)
	if main.multiplayer.is_server() and GameNetwork.is_bot(active_id):
		var _ab2: int = active_id
		main.get_tree().create_timer(0.6).timeout.connect(func() -> void: BotTurn.bot_decide_bid(main, _ab2))

# Host → All: auction resolved — winner places the card.
static func _rpc_sync_auction_won(main: Main, initiator_id: int, winner_id: int, final_bid: int, card_ref: Dictionary, _slot_idx: int, is_tech: bool, cost_color_int: int) -> void:
	main._auction_active = false
	main._auction_starting = false
	main._is_runner_up_offer = false
	main._bid_popup.hide()
	UIAudio.stop_auction_music()
	main._refresh_all_opp_status_labels()
	main._auction_placement_pending = true
	var cost_color: CardData.SupplyColor = cost_color_int as CardData.SupplyColor
	var my_id: int = main.multiplayer.get_unique_id()
	if my_id == winner_id:
		main._pending_auction_win = true
		main._auction_win_awaiting_placement = true
		main._auction_win_is_initiator = (my_id == initiator_id)
		if not main._auction_win_is_initiator:
			main._pending_won_card_ref = card_ref
		var cd: CardData = CardRef.from_ref(card_ref)
		var c_name: String = ""
		if cd:
			c_name = cd.adv_name if (main._auction_is_adv and not cd.adv_name.is_empty()) else cd.card_name
		var valid_colors: Array[CardData.SupplyColor] = CardData.valid_payment_colors(cost_color)
		main._bid_payment_panel.show_bid_payment(c_name, final_bid, valid_colors, main._cs_display, cd, main._auction_is_adv)
	else:
		if my_id == initiator_id:
			main.get_node("Board").cancel_purchase()
			# Losing an auction you initiated still spends your major action
			# for the turn, but _auction_placement_pending (set above) keeps
			# end-turn blocked until the actual winner places their card —
			# _rpc_sync_auction_placement_pending re-checks it once that's done.
		main._show_action_buttons(true)
	# Bots have no client to drive the normal drag-to-place step, so the host
	# resolves payment/placement for them right here and clears the
	# placement-pending flag itself — otherwise it would never clear and
	# end-turn would stay blocked for everyone for the rest of the game.
	if main.multiplayer.is_server() and GameNetwork.is_bot(winner_id):
		BotTurn.bot_resolve_auction_win(main, winner_id, card_ref, final_bid, cost_color, is_tech, main._auction_is_adv)
		main._rpc_sync_auction_placement_pending.rpc(false)
	main._update_turn_ui()
	var _cd_toast: CardData = CardRef.from_ref(card_ref)
	var _cn_toast: String = ""
	if _cd_toast:
		_cn_toast = _cd_toast.adv_name if (main._auction_is_adv and not _cd_toast.adv_name.is_empty()) else _cd_toast.card_name
	var _wn_toast: String = GameNetwork.player_names.get(winner_id, "Player")
	var won_banner: Main.TurnBanner = Main.TurnBanner.new()
	main.get_node("UILayer").add_child(won_banner)
	won_banner.play(main.tr("%s won %s for %d") % [_wn_toast, _cn_toast, final_bid], Color(1.0, 0.92, 0.35), "", Main.AUCTION_BANNER_LENGTH)
	main._log_action(main.tr("%s won %s for %d") % [_wn_toast, _cn_toast, final_bid], Color(1.0, 0.92, 0.35))
	UIAudio.play_gavel_sfx()
	if winner_id == main.multiplayer.get_unique_id():
		Main.Haptics.thump()
	if main._bid_is_from_effect:
		main._bid_is_from_effect = false
		main._process_next_effect()
	main._broadcast_my_state()

static func _show_auction_toast(main: Main, message: String) -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.08
	panel.anchor_bottom = 0.08
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = -220.0
	panel.offset_right = 220.0
	panel.offset_top = 0.0
	panel.offset_bottom = 48.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.14, 0.90)
	style.border_color = Color(0.8, 0.7, 0.3, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.text = message
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)
	main.get_node("UILayer").add_child(panel)
	var tween: Tween = main.create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(panel, "modulate:a", 0.0, 0.8)
	tween.tween_callback(panel.queue_free)

# Someone else started an auction: the turn pop-up in amber, the card underneath.
static func _show_auction_banner(main: Main, subtitle: String) -> void:
	var banner: Main.TurnBanner = Main.TurnBanner.new()
	main.get_node("UILayer").add_child(banner)
	banner.play(main.tr("⚠  AUCTION").replace("⚠", "").strip_edges(), Main.AUCTION_COLOR, subtitle, Main.AUCTION_BANNER_LENGTH)

static func _on_bid_required(main: Main, card: Node3D, slot: Node3D, min_cost: int, cost_color: CardData.SupplyColor, is_tech: bool) -> void:
	main._show_action_buttons(false)
	main._bid_color = cost_color
	main._bid_card_data = card.card_data
	main._bid_is_advanced = card.is_advanced
	main._bid_card_name = card.card_data.adv_name if card.is_advanced else card.card_data.card_name
	var effective_min: int = max(0, min_cost - main.get_node("Board").get_purchase_discount(card.card_data, slot as SectorSlot, card.is_advanced))
	if not GameNetwork.is_multiplayer:
		main._bid_popup.show_bid(card.card_data, card.is_advanced, effective_min, cost_color)
		return
	main._pending_auction_card_ref = CardRef.to_ref(card.card_data)
	main._pending_auction_slot_idx = main.get_node("Board").get_slot_index(slot as SectorSlot)
	main._pending_auction_is_tech = is_tech
	main._pending_auction_is_adv = card.is_advanced
	main._pending_auction = true
	main._bid_popup.show_bid(card.card_data, card.is_advanced, effective_min, cost_color)

static func _on_bid_raised(main: Main, amount: int) -> void:
	if GameNetwork.is_host:
		_server_handle_raise(main, 1, amount)
	else:
		main._rpc_raise_bid.rpc_id(1, amount)

static func _on_bid_passed(main: Main) -> void:
	if GameNetwork.is_host:
		_server_handle_pass_bid(main, 1)
	else:
		main._rpc_pass_bid.rpc_id(1)

static func _server_start_auction(main: Main, card_ref: Dictionary, slot_idx: int, is_tech: bool, is_adv: bool, min_bid: int, cost_color_int: int, initiator_id: int) -> void:
	main._auction_card_ref = card_ref
	main._auction_slot_idx = slot_idx
	main._auction_is_tech = is_tech
	main._auction_is_adv = is_adv
	main._auction_cost_color = cost_color_int as CardData.SupplyColor
	main._auction_current_bid = min_bid
	main._auction_leader_id = initiator_id
	main._auction_initiator_id = initiator_id
	var start_pos: int = GameNetwork.player_order.find(initiator_id)
	var n: int = GameNetwork.player_order.size()
	main._auction_remaining = []
	main._auction_second_id = -1
	for j: int in n:
		main._auction_remaining.append(GameNetwork.player_order[(start_pos + j) % n])
	if main._auction_remaining.size() <= 1:
		main._rpc_sync_auction_won.rpc(initiator_id, initiator_id, min_bid, card_ref, slot_idx, is_tech, cost_color_int)
		return
	main._auction_active_idx = 1
	var active_id: int = main._auction_remaining[main._auction_active_idx]
	var leader_name: String = GameNetwork.player_names.get(initiator_id, "Player")
	main._rpc_sync_auction_started.rpc(card_ref, slot_idx, is_tech, is_adv, min_bid, cost_color_int, initiator_id, active_id, leader_name, main._auction_remaining)

static func _server_handle_raise(main: Main, peer_id: int, amount: int) -> void:
	if main._auction_remaining.is_empty():
		return
	if peer_id != main._auction_remaining[main._auction_active_idx]:
		return
	if amount <= main._auction_current_bid:
		return
	main._auction_second_id = main._auction_leader_id
	main._auction_current_bid = amount
	main._auction_leader_id = peer_id
	main._auction_active_idx = (main._auction_active_idx + 1) % main._auction_remaining.size()
	var active_id: int = main._auction_remaining[main._auction_active_idx]
	var leader_name: String = GameNetwork.player_names.get(main._auction_leader_id, "Player")
	main._rpc_sync_auction_state.rpc(main._auction_current_bid, main._auction_leader_id, active_id, leader_name, main._auction_remaining)

static func _server_handle_pass_bid(main: Main, peer_id: int) -> void:
	if main._auction_remaining.is_empty():
		return
	if peer_id != main._auction_remaining[main._auction_active_idx]:
		return
	if peer_id == main._auction_leader_id:
		return
	main._auction_remaining.remove_at(main._auction_active_idx)
	if main._auction_active_idx >= main._auction_remaining.size():
		main._auction_active_idx = 0
	if main._auction_remaining.size() == 1:
		main._rpc_sync_auction_won.rpc(main._auction_initiator_id, main._auction_leader_id, main._auction_current_bid, main._auction_card_ref, main._auction_slot_idx, main._auction_is_tech, int(main._auction_cost_color))
		return
	var active_id: int = main._auction_remaining[main._auction_active_idx]
	var leader_name: String = GameNetwork.player_names.get(main._auction_leader_id, "Player")
	main._rpc_sync_auction_state.rpc(main._auction_current_bid, main._auction_leader_id, active_id, leader_name, main._auction_remaining)

static func _server_offer_to_runner_up(main: Main) -> void:
	if main._auction_second_id == -1:
		main._rpc_sync_auction_placement_pending.rpc(false)
		return
	var cd: CardData = CardRef.from_ref(main._auction_card_ref)
	if not cd:
		main._rpc_sync_auction_placement_pending.rpc(false)
		return
	if GameNetwork.is_bot(main._auction_second_id):
		# Bots have no payment-panel UI to accept this at printed cost —
		# treat it the same as a human runner-up declining outright.
		main._rpc_sync_market_removal.rpc(main._auction_card_ref)
		main._rpc_sync_auction_placement_pending.rpc(false)
		return
	main._rpc_sync_runner_up_phase.rpc(true)
	var printed_cost: int = cd.adv_cost if main._auction_is_adv else cd.cost
	if main._auction_second_id == main.multiplayer.get_unique_id():
		_on_runner_up_offer(main, main._auction_card_ref, main._auction_slot_idx, main._auction_is_tech, main._auction_is_adv, printed_cost, int(main._auction_cost_color))
	else:
		main._rpc_offer_to_runner_up.rpc_id(main._auction_second_id, main._auction_card_ref, main._auction_slot_idx, main._auction_is_tech, main._auction_is_adv, printed_cost, int(main._auction_cost_color))

static func _on_runner_up_offer(main: Main, card_ref: Dictionary, _slot_idx: int, _is_tech: bool, is_adv: bool, printed_cost: int, cost_color_int: int) -> void:
	var cd: CardData = CardRef.from_ref(card_ref)
	if not cd:
		return
	main._pending_won_card_ref = card_ref
	main._pending_auction_win = true
	main._auction_win_awaiting_placement = true
	main._auction_win_is_initiator = false
	main._is_runner_up_offer = true
	var c_name: String = cd.adv_name if (is_adv and not cd.adv_name.is_empty()) else cd.card_name
	var cost_color: CardData.SupplyColor = cost_color_int as CardData.SupplyColor
	var valid_colors: Array[CardData.SupplyColor] = CardData.valid_payment_colors(cost_color)
	main._bid_payment_panel.show_bid_payment(c_name, printed_cost, valid_colors, main._cs_display, cd, is_adv)
	main._update_turn_ui()

static func _on_bid_confirmed(main: Main, amount: int) -> void:
	if main._pending_auction:
		main._pending_auction = false
		main._auction_starting = true
		main.get_node("Board").set_major_action_taken()
		var my_id: int = main.multiplayer.get_unique_id()
		if GameNetwork.is_host:
			_server_start_auction(main, main._pending_auction_card_ref, main._pending_auction_slot_idx, main._pending_auction_is_tech, main._pending_auction_is_adv, amount, int(main._bid_color), my_id)
		else:
			main._rpc_request_auction.rpc_id(1, main._pending_auction_card_ref, main._pending_auction_slot_idx, main._pending_auction_is_tech, main._pending_auction_is_adv, amount, int(main._bid_color))
		return
	main._bid_amount = amount
	var valid_colors: Array[CardData.SupplyColor] = CardData.valid_payment_colors(main._bid_color)
	main._bid_payment_panel.show_bid_payment(main._bid_card_name, amount, valid_colors, main._cs_display, main._bid_card_data, main._bid_is_advanced)

# Right-click during an auction win's targeting arrow (see
# Board._cancel_prepaid_to_payment) — the winning bid itself is already
# settled, so this just re-opens the payment-allocation step for the same
# fixed amount, reusing _bid_amount/_bid_card_name/etc. still cached from
# the original bid rather than re-running the auction.
static func _on_auction_payment_cancel_requested(main: Main) -> void:
	main._pending_auction_recancel = true
	var valid_colors: Array[CardData.SupplyColor] = CardData.valid_payment_colors(main._bid_color)
	main._bid_payment_panel.show_bid_payment(main._bid_card_name, main._bid_amount, valid_colors, main._cs_display, main._bid_card_data, main._bid_is_advanced)

static func _on_bid_payment_confirmed(main: Main, allocations: Dictionary) -> void:
	if main._effect_mode == Main.EffectMode.PAYMENT_CONFIRM:
		main._effect_mode = Main.EffectMode.NONE
		main.get_node("Board").hide_payment_confirm_arrow()
		main.get_node("Board").confirm_payment_with_allocations(allocations)
		return
	# Supply is deliberately NOT spent here anymore — same rule as every
	# other purchase now: it's only actually taken once the card lands on a
	# slot for real (see Board.complete_purchase/_finalize_placement), not
	# at this earlier payment-choice step. allocations is just carried
	# through to whichever placement path handles that.
	if main._pending_auction_recancel:
		main._pending_auction_recancel = false
		main.get_node("Board").resume_auction_win_drag(allocations)
		main._show_action_buttons(true)
		main._broadcast_my_state()
		return
	if main._pending_auction_win:
		main._pending_auction_win = false
		if main._auction_win_is_initiator:
			main.get_node("Board").complete_purchase(allocations)
		else:
			var card: CardData = CardRef.from_ref(main._pending_won_card_ref)
			if not main.get_node("Board").begin_auction_win_drag(card, allocations):
				push_warning("AuctionWin: card not found in market")
				_notify_auction_placement_done(main)
		main._show_action_buttons(true)
		main._broadcast_my_state()
		return
	main.get_node("Board").complete_purchase(allocations)
	main._show_action_buttons(true)
	if main._bid_is_from_effect:
		main._bid_is_from_effect = false
		main._process_next_effect()

static func _on_bid_payment_forfeited(main: Main) -> void:
	if main._effect_mode == Main.EffectMode.PAYMENT_CONFIRM:
		main._effect_mode = Main.EffectMode.NONE
		main.get_node("Board").hide_payment_confirm_arrow()
		main.get_node("Board").cancel_payment_confirm()
		return
	if main._pending_auction_recancel:
		# re-opened after the win (right-click on the arrow): Cancel means
		# back to placing it, not giving up a card that's already ours
		main._pending_auction_recancel = false
		main.get_node("Board").resume_cancelled_auction_drag()
		main._show_action_buttons(true)
		main._broadcast_my_state()
		return
	if main._pending_auction_win:
		main._pending_auction_win = false
		main._auction_win_awaiting_placement = false
		if main._auction_win_is_initiator:
			main.get_node("Board").cancel_purchase()
			main.get_node("Board").reset_turn()
			if GameNetwork.is_host:
				_server_offer_to_runner_up(main)
			else:
				main._rpc_notify_auction_forfeit.rpc_id(1)
		else:
			if main._is_runner_up_offer:
				main._is_runner_up_offer = false
				if GameNetwork.is_host:
					main._rpc_sync_market_removal.rpc(main._pending_won_card_ref)
					main._rpc_sync_runner_up_phase.rpc(false)
					main._rpc_sync_auction_placement_pending.rpc(false)
				else:
					main._rpc_notify_runner_up_forfeit.rpc_id(1, main._pending_won_card_ref)
			else:
				if GameNetwork.is_host:
					_server_offer_to_runner_up(main)
				else:
					main._rpc_notify_auction_forfeit.rpc_id(1)
		main._show_action_buttons(true)
		return
	main.get_node("Board").cancel_purchase()
	main._show_action_buttons(true)
	if main._bid_is_from_effect:
		main._bid_is_from_effect = false
		main._process_next_effect()

static func _on_bid_cancelled(main: Main) -> void:
	main._pending_auction = false
	main.get_node("Board").cancel_purchase()
	main._show_action_buttons(true)
	if main._bid_is_from_effect:
		main._bid_is_from_effect = false
		main._process_next_effect()

static func _on_payment_confirm_required(main: Main, card: Node3D, slot: SectorSlot, pay_amounts: Dictionary, _is_tech: bool) -> void:
	main._effect_mode = Main.EffectMode.PAYMENT_CONFIRM
	var card_name: String = ""
	var cost_color: CardData.SupplyColor = CardData.SupplyColor.DUST
	var total: int = 0
	var cd: CardData = null
	var is_adv: bool = false
	if card.card_data:
		cd = card.card_data
		is_adv = bool(card.get("is_advanced"))
		card_name = cd.adv_name if is_adv and not cd.adv_name.is_empty() else cd.card_name
		cost_color = CardData.effective_color(cd, is_adv)   # Fleet buys advanced sectors outright
		for v: Variant in pay_amounts.values():
			total += int(v)
	if total == 0:
		main._effect_mode = Main.EffectMode.NONE
		main.get_node("Board").confirm_payment()
		return
	var valid_colors: Array[CardData.SupplyColor] = CardData.valid_payment_colors(cost_color)
	main._bid_payment_panel.show_bid_payment(card_name, total, valid_colors, main._cs_display, cd, is_adv)
	var cam: Camera3D = main.get_viewport().get_camera_3d()
	if cam and main._info_screen_mesh and slot:
		var aabb: AABB = main._info_screen_mesh.mesh.get_aabb()
		var from_world: Vector3 = main._info_screen_mesh.to_global(aabb.get_center())
		var from_2d: Vector2 = cam.unproject_position(from_world)
		var to_2d: Vector2 = cam.unproject_position(slot.global_position)
		main.get_node("Board").show_payment_confirm_arrow(from_2d, to_2d)

# Host-only: force-resolves an auction outcome that was waiting on peer_id's
# own input (a runner-up offer, or paying/placing after winning) when that
# input can never come because they've disconnected. Deliberately doesn't
# touch $Board — cancel_purchase()/reset_turn() are per-client operations on
# state that only ever existed on peer_id's own (now-gone) client.
static func _host_force_decline_pending_auction(main: Main, peer_id: int) -> void:
	if main._runner_up_phase and main._auction_second_id == peer_id:
		main._rpc_sync_market_removal.rpc(main._auction_card_ref)
		main._rpc_sync_runner_up_phase.rpc(false)
		main._rpc_sync_auction_placement_pending.rpc(false)
	elif main._auction_placement_pending and main._auction_leader_id == peer_id:
		_server_offer_to_runner_up(main)
