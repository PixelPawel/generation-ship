class_name FirstTurnTutorial
extends Node

# Interactive first-turn tutorial: highlights the real UI element for the
# next thing to try, shows a short instruction on the existing effect-hint
# banner, and waits for the player to actually do it. Five concepts, each
# tracked independently of which one is currently displayed (a real action
# counts whenever it happens), shown one at a time in this priority order
# to whichever isn't done yet: Buy a Sector -> Place a Tech -> Fuse Supply
# -> Bid on an Expedition -> Pass. No hard gating — the player can do things
# in any order; the displayed hint just advances whenever its matching real
# action fires.
#
# Re-asserts its current step every REFRESH_INTERVAL_SEC rather than
# showing it once, because two other systems can silently undo it:
# - _reset_effect_state() unconditionally hides the shared effect-hint
#   banner on every end-turn, including the auto-end-turn that fires the
#   instant a single-action turn settles.
# - SectorSlot.highlight() is also driven live by the board's own drag
#   feedback, which force-clears every slot's highlight on any drag end.
# Both are safe to re-assert idempotently, and this only runs while
# main._effect_mode == NONE so it never steps on a real effect hint.

const REFRESH_INTERVAL_SEC: float = 0.2

var _main: Main = null
var _board: Node = null

var _bought_sector: bool = false
var _placed_tech: bool = false
var _fused_supply: bool = false
var _bid_expedition: bool = false
var _passed: bool = false

var _current_step: String = ""
var _highlighted_tech_slots: Array[SectorSlot] = []

func start(main: Main) -> void:
	_main = main
	_board = main.get_node("Board")
	_board.card_placed.connect(_on_card_placed)
	main._cs_display.fused.connect(_on_fused)

	var timer: Timer = Timer.new()
	timer.wait_time = REFRESH_INTERVAL_SEC
	timer.autostart = true
	timer.timeout.connect(_refresh)
	add_child(timer)

func notify_passed() -> void:
	_passed = true

func notify_expedition_bid_confirmed() -> void:
	_bid_expedition = true

func _on_card_placed(card: Node3D, _slot: SectorSlot) -> void:
	var cd: CardData = card.get("card_data")
	if not cd:
		return
	if cd.card_type == CardData.CardType.SECTOR:
		_bought_sector = true
	elif cd.card_type == CardData.CardType.TECH:
		_placed_tech = true

func _on_fused(_source: int, _target: int) -> void:
	_fused_supply = true

func _refresh() -> void:
	if _bought_sector and _placed_tech and _fused_supply and _bid_expedition and _passed:
		_finish()
		return
	if _main._effect_mode != Main.EffectMode.NONE:
		return
	var step: String
	if not _bought_sector:
		step = "buy"
	elif not _placed_tech:
		step = "place"
	elif not _fused_supply:
		step = "fuse"
	elif not _bid_expedition:
		step = "bid"
	else:
		step = "pass"
	_apply_step(step)

func _apply_step(step: String) -> void:
	if step != "buy":
		_main._market_panel.set_tutorial_dust_highlight(false)
	if step != "place":
		_clear_tech_slot_highlights()
	if step != "fuse":
		_main._cs_display._flow.set_tutorial_highlight(false)
	if step != "bid":
		_main._market_panel.set_tutorial_expedition_highlight(false)
	if step != "pass":
		_main._stop_pass_btn_3d_flash()

	match step:
		"buy":
			_apply_buy_step()
		"place":
			_main._show_effect_hint("Left-click and drag a Tech card from your hand onto the Sector")
			_highlight_tech_slots()
		"fuse":
			_main._show_effect_hint("Fuse 2 supply into 1 supply of a higher value.")
			_main._cs_display._flow.set_tutorial_highlight(true)
		"bid":
			_main._show_effect_hint("Left-click on an Expedition and confirm a bid to start an auction")
			_main._market_panel.set_tutorial_expedition_highlight(true)
		"pass":
			_main._show_effect_hint("Nothing left to do? Press Pass")
			_main._start_pass_btn_3d_flash()
	_current_step = step

# "Buy a Sector" is really 3 sub-phases of one flow: click a market slot,
# pay for it, then drag it onto a free Sector slot — the hint follows
# whichever one is actually happening right now.
func _apply_buy_step() -> void:
	if _is_dragging_sector_card():
		_main._market_panel.set_tutorial_dust_highlight(false)
		_main._show_effect_hint("Place your Sector on a free Sector slot")
	elif (_main._bid_popup and _main._bid_popup.visible) or (_main._bid_payment_panel and _main._bid_payment_panel.visible):
		_main._market_panel.set_tutorial_dust_highlight(false)
		_main._show_effect_hint("Pay 2 Dust to place your Dust Sector")
	else:
		_main._market_panel.set_tutorial_dust_highlight(true)
		_main._show_effect_hint("Left-click a Dust Sector on the Market screen")

func _is_dragging_sector_card() -> bool:
	var dragged: Node3D = _board.get("_dragged_card") as Node3D
	if not dragged:
		return false
	var cd: CardData = dragged.get("card_data")
	return cd != null and cd.card_type == CardData.CardType.SECTOR

func _highlight_tech_slots() -> void:
	var eligible: Array[SectorSlot] = []
	for slot: SectorSlot in _board.get_sector_slots():
		if slot.has_tech_space():
			eligible.append(slot)
	if eligible == _highlighted_tech_slots:
		return
	for slot: SectorSlot in _highlighted_tech_slots:
		if is_instance_valid(slot) and not eligible.has(slot):
			slot.highlight(false)
	for slot: SectorSlot in eligible:
		slot.highlight(true)
	_highlighted_tech_slots = eligible

func _clear_tech_slot_highlights() -> void:
	for slot: SectorSlot in _highlighted_tech_slots:
		if is_instance_valid(slot):
			slot.highlight(false)
	_highlighted_tech_slots = []

func _finish() -> void:
	_main._hide_effect_hint()
	_main._market_panel.set_tutorial_dust_highlight(false)
	_clear_tech_slot_highlights()
	_main._cs_display._flow.set_tutorial_highlight(false)
	_main._market_panel.set_tutorial_expedition_highlight(false)
	_main._stop_pass_btn_3d_flash()
	if _board.card_placed.is_connected(_on_card_placed):
		_board.card_placed.disconnect(_on_card_placed)
	if _main._cs_display.fused.is_connected(_on_fused):
		_main._cs_display.fused.disconnect(_on_fused)
	# main._tutorial otherwise dangles once this node is freed — a later
	# "if _tutorial:" check (e.g. in _do_pass()) would hold a stale
	# reference instead of reading as falsy.
	_main._tutorial = null
	queue_free()
