class_name FirstTurnTutorial
extends Node

# The Tutorial (main menu → Tutorial): one solo game that walks through every
# mechanic in order, each chapter waiting for the player to really do it.
# It highlights the real UI and shows the step on the effect-hint banner (top
# edge while the tutorial runs). Before a chapter it hands over exactly the
# cards and supply that chapter needs, so it never depends on lucky draws.
#
# Chapters: buy a sector → place a tech → fuse → optimize → "if fully
# optimized" → recycle → bid on
# an expedition → complete a sector → buy a second sector → archive face down →
# store → archive face up → printed stars → buy a third sector → "if new" →
# Always cards →
# research → pass → scoring (the game ends on the score breakdown; tutorial
# scores never reach the leaderboard).
#
# The tech deck is scripted (Board.set_scripted_deck): no opening hand, no
# reshuffles — the only cards that ever reach the hand are the ones a chapter
# hands over or stacks on the deck for an effect to draw.
#
# Re-asserts its current step every REFRESH_INTERVAL_SEC, because the end of
# a turn hides the banner and drag feedback clears slot highlights; and it
# stays quiet while a card effect is resolving (that effect shows its own
# prompt).

const REFRESH_INTERVAL_SEC: float = 0.2
const SETTINGS_PATH: String = "user://settings.cfg"
const MIN_SUPPLY: int = 6        # topped up before chapters that cost supply
# A cheap, effect-free card of each colour, to fill a sector's optimize group.
const FILLER_BY_COLOR: Dictionary = {
	CardData.SupplyColor.DUST: "Mag-Net",
	CardData.SupplyColor.METALS: "Cargo Pods",
	CardData.SupplyColor.LIQUIDS: "Purifier",
	CardData.SupplyColor.ORGANIX: "Fish",
	CardData.SupplyColor.ELECTRIX: "Portable Reactor",
	CardData.SupplyColor.THRUST: "Markets",
}
const STEPS: Array[String] = [
	"buy", "place", "fuse", "optimize", "if_full", "recycle", "bid", "complete", "buy2",
	"archive", "store", "archive_up", "stars", "buy3", "if_new", "always",
	"research", "pass", "score",
]
# Fuse and recycle steps: the control screen zooms in, and shakes if nothing has
# happened yet — first after NUDGE_FIRST_SEC, then every NUDGE_REPEAT_SEC.
const NUDGE_FIRST_SEC: float = 2.0
const NUDGE_REPEAT_SEC: float = 5.0
# DNA Sculpting draws these, to archive face up (they keep their printed stars)
const STAR_DRAWS: Array[String] = ["Inflatable Habs", "Cargo Landers", "Solar Power"]

var _main: Main = null
var _board: Node = null
var _step: int = -1
var _entered: bool = false

# what happened since the current step started
var _placed: Array[CardData] = []
var _fused: bool = false
var _recycled: bool = false
var _optimized: bool = false
var _researched: bool = false
var _passed: bool = false
var _recycled_during_bid_payment: bool = false
var _first_sector: SectorSlot = null
var _second_sector: SectorSlot = null
var _third_sector: SectorSlot = null
var _step_time: float = 0.0          # seconds in the current step
var _next_nudge: float = 0.0         # step time of the next control-screen shake
var _gave_followup: bool = false     # a step's second card has been handed over
var _highlighted_tech_slots: Array[SectorSlot] = []

func start(main: Main) -> void:
	_main = main
	_board = main.get_node("Board")
	_board.card_placed.connect(_on_card_placed)
	_board.card_recycled.connect(_on_card_recycled)
	_board.unplaceable_card_recycled.connect(_on_unplaceable_card_recycled)
	_board.optimize_triggered.connect(func(_slot: SectorSlot, _level: int) -> void: _optimized = true)
	main._cs_display.fused.connect(func(_s: int, _t: int) -> void: _fused = true)
	var timer: Timer = Timer.new()
	timer.wait_time = REFRESH_INTERVAL_SEC
	timer.autostart = true
	timer.timeout.connect(_refresh)
	add_child(timer)
	_next_step()

func notify_passed() -> void:
	_passed = true

func notify_researched() -> void:
	_researched = true

func notify_escape_pressed() -> void:
	pass

# ── Events ────────────────────────────────────────────────────────────────────

func _on_card_placed(card: Node3D, slot: SectorSlot) -> void:
	var cd: CardData = card.get("card_data")
	if not cd:
		return
	_placed.append(cd)
	if cd.card_type == CardData.CardType.SECTOR:
		if _first_sector == null:
			_first_sector = slot
		elif _second_sector == null and slot != _first_sector:
			_second_sector = slot
		elif _third_sector == null and slot != _first_sector and slot != _second_sector:
			_third_sector = slot

func _on_card_recycled(_color: int, _amount: int) -> void:
	_recycled = true
	_recycled_during_bid_payment = true

# A won expedition with no room is recycled instead of placed — still counts.
func _on_unplaceable_card_recycled(card_data: CardData) -> void:
	if card_data:
		_placed.append(card_data)

func _placed_type(t: CardData.CardType) -> bool:
	for cd: CardData in _placed:
		if cd.card_type == t:
			return true
	return false

func _placed_name(n: String) -> bool:
	for cd: CardData in _placed:
		if cd.card_name == n:
			return true
	return false

# ── Steps ─────────────────────────────────────────────────────────────────────

func _next_step() -> void:
	_step += 1
	_entered = false
	_placed.clear()
	_fused = false
	_recycled = false
	_optimized = false
	_researched = false
	_passed = false
	_recycled_during_bid_payment = false
	_step_time = 0.0
	_next_nudge = NUDGE_FIRST_SEC
	_gave_followup = false
	_clear_highlights()

func _refresh() -> void:
	if _step >= STEPS.size():
		return
	if _main._effect_mode != Main.EffectMode.NONE:
		_show_recycle_arrow(false)
		return
	var step: String = STEPS[_step]
	if not _entered:
		_entered = true
		_enter(step)
	_step_time += REFRESH_INTERVAL_SEC
	if _is_done(step):
		_leave(step)
		_next_step()
		return
	_tick(step)
	_show(step)

# Things that happen while a step waits (follow-up cards, nudges).
func _tick(step: String) -> void:
	match step:
		"fuse", "recycle":
			if _step_time >= _next_nudge:
				_next_nudge = _step_time + NUDGE_REPEAT_SEC
				CockpitRig.shake_screen(_main, _main.get_node("UiControl"))
		"stars":
			# Quantum Archives is down: now the star card it reacts to
			if not _gave_followup and _placed_name("Quantum Archives"):
				_gave_followup = true
				_give(["Solar Power"])

func _leave(step: String) -> void:
	match step:
		"fuse", "recycle":
			CockpitRig.set_screen_enlarged(_main, _main.get_node("UiControl"), false)

# Hand-overs before a chapter: the cards it needs, enough supply to play them.
func _enter(step: String) -> void:
	match step:
		"buy", "bid":
			_top_up_supply()
		"buy2":
			_top_up_supply()
			_board.sync_market_reveal(0)   # the first advanced sector appears (no reveal effects)
		"place":
			_give(["Mag-Net"])
		"fuse":
			if _main._cs_display.get_supply(CardData.SupplyColor.DUST) < 2:
				_main._cs_display.set_supply(CardData.SupplyColor.DUST, 2)
			CockpitRig.set_screen_enlarged(_main, _main.get_node("UiControl"), true)
		"if_full":
			_top_up_supply()
			_give_if_missing("Lab Meats")
		"if_new":
			_top_up_supply()
			_give(["Hangars"])
		"recycle":
			_give_if_missing("Mag-Net")
			CockpitRig.set_screen_enlarged(_main, _main.get_node("UiControl"), true)
		"optimize":
			_top_up_supply()
			# Simulators' optimize effect is "Draw 2": it draws the next steps' cards
			_board.set_scripted_deck(_cards(["Lab Meats", "Mag-Net"]))
			_give(_missing_optimize_cards())
		"complete":
			_top_up_supply()
			var free: int = 5 - (_first_sector.get_tech_count() if _first_sector else 5)
			var cards: Array[String] = []
			for i: int in maxi(0, free - 1):
				cards.append("Mag-Net")
			if free > 0:
				cards.append("PC-Mind-Link")
			_give(cards)
		"buy3":
			_top_up_supply()
		"archive":
			_top_up_supply()
			_give(["Chemical Synthesizer", "Mag-Net"])   # Mag-Net: the card to archive
		"store":
			_top_up_supply()
			_give(["Containers"])
		"archive_up":
			_top_up_supply()
			_board.set_scripted_deck(_cards(STAR_DRAWS))   # what its "Draw 3" brings
			_give(["DNA Sculpting"])
		"stars":
			_top_up_supply()
			_give(["Quantum Archives"])
		"always":
			_top_up_supply()
			# Biodomes is a Liquids card itself, so placing it draws the next one
			_board.set_scripted_deck(_cards(["Atmospheric System"]))
			_give(["Biodomes"])
		"research":
			_board.set_scripted_deck(_cards(["Fish"]))   # the replacement it draws
			_give(["Mag-Net"])
		"score":
			_main._hide_effect_hint()
			_main._game_over()
			_mark_done()

func _is_done(step: String) -> bool:
	match step:
		"buy":
			return _first_sector != null
		"place":
			return _placed_type(CardData.CardType.TECH)
		"fuse":
			return _fused
		"optimize":
			return _optimized
		"if_full":
			# (a sector the optimize cards already filled can't take it: move on)
			return _placed_name("Lab Meats") or not _any_tech_space()
		"if_new":
			return _placed_name("Hangars")
		"recycle":
			return _recycled
		"bid":
			return _placed_type(CardData.CardType.EXPEDITION)
		"complete":
			return _first_sector == null or _first_sector.is_complete()
		"buy2":
			return _second_sector != null
		"buy3":
			return _third_sector != null
		"archive":
			return _any_tucked(false)
		"store":
			return _any_stored()
		"archive_up":
			return _any_tucked(true)
		"stars":
			return _placed_name("Solar Power")
		"always":
			return _placed_name("Atmospheric System") and _board.count_tech_by_name("Biodomes") > 0
		"research":
			return _researched
		"pass":
			return _passed
	return false   # "score" stays up: the game is over

func _show(step: String) -> void:
	match step:
		"buy", "buy3":
			_show_buy(step)
		"buy2":
			_show_buy_advanced()
		"place":
			_hint(_main.hint("TUT_PLACE_TECH", "TUT_PLACE_TECH_MOBILE"))
			_highlight_tech_slots()
		"fuse":
			_hint(tr("TUT_FUSE"))
			_main._cs_display._flow.set_tutorial_highlight(true)
		"optimize":
			_hint(tr("TUT_OPTIMIZE"))
			_highlight_tech_slots()
		"if_full":
			_hint(tr("TUT_IF_FULL") % _name("Lab Meats"))
			_highlight_tech_slots()
		"if_new":
			_hint(tr("TUT_IF_NEW") % _name("Hangars"))
			_highlight_tech_slots()
		"recycle":
			_hint(_main.hint("TUT_RECYCLE", "TUT_RECYCLE_MOBILE"))
			_show_recycle_arrow(true)
		"bid":
			_show_bid()
		"complete":
			_hint(tr("TUT_COMPLETE") % _name("PC-Mind-Link"))
			_highlight_tech_slots()
		"archive":
			_hint(tr("TUT_ARCHIVE") % [_name("Chemical Synthesizer"), _name("Mag-Net")])
			_highlight_tech_slots()
		"store":
			_hint(tr("TUT_STORE") % _name("Containers"))
			_highlight_tech_slots()
		"archive_up":
			_hint(tr("TUT_ARCHIVE_UP") % _name("DNA Sculpting"))
			_highlight_tech_slots()
		"stars":
			if _gave_followup:
				_hint(tr("TUT_STARS_NEXT") % _name("Solar Power"))
			else:
				_hint(tr("TUT_STARS") % _name("Quantum Archives"))
			_highlight_tech_slots()
		"always":
			var liquids: String = CardData.color_name(CardData.SupplyColor.LIQUIDS)
			if _board.count_tech_by_name("Biodomes") > 0:
				_hint(tr("TUT_ALWAYS_NEXT") % [_name("Atmospheric System"), liquids])
			else:
				_hint(tr("TUT_ALWAYS") % [_name("Biodomes"), liquids])
			_highlight_tech_slots()
		"research":
			_hint(tr("TUT_RESEARCH_TUT"))
			_main._start_research_btn_3d_flash()
		"pass":
			_main._stop_research_btn_3d_flash()
			_hint(tr("TUT_PASS"))
			_main._start_pass_btn_3d_flash()
		"score":
			_main._stop_pass_btn_3d_flash()
			_hint(tr("TUT_SCORE"))

func _hint(text: String) -> void:
	_main._show_effect_hint(text)

# "Buy a Sector" is 3 sub-phases: pick a market slot, pay, place the card.
func _show_buy(step: String) -> void:
	if _is_dragging(CardData.CardType.SECTOR):
		_main._market_panel.set_tutorial_dust_highlight(false)
		_hint(tr("TUT_BUY_PLACE"))
	elif (_main._bid_popup and _main._bid_popup.visible) or (_main._bid_payment_panel and _main._bid_payment_panel.visible):
		_main._market_panel.set_tutorial_dust_highlight(false)
		_hint(_main.hint("TUT_BUY", "TUT_BUY_MOBILE"))
	else:
		_main._market_panel.set_tutorial_dust_highlight(true)
		match step:
			"buy3":
				_hint(tr("TUT_BUY_THIRD"))
			_:
				# the very first step: why the hand is empty
				_hint(tr("TUT_SKIP_DRAW") + "\n" + _main.hint("TUT_BUY", "TUT_BUY_MOBILE"))

# The second sector is an advanced one, won in an auction: pick it, bid, pay, place.
func _show_buy_advanced() -> void:
	if _is_dragging(CardData.CardType.SECTOR):
		_main._market_panel.set_tutorial_advanced_highlight(false)
		_hint(tr("TUT_BUY_PLACE"))
	elif _main._bid_popup and _main._bid_popup.visible:
		_main._market_panel.set_tutorial_advanced_highlight(false)
		_hint(tr("TUT_BID_POPUP"))
	elif _main._bid_payment_panel and _main._bid_payment_panel.visible:
		_main._market_panel.set_tutorial_advanced_highlight(false)
		_hint(tr("TUT_BID_PAY"))
	else:
		_main._market_panel.set_tutorial_advanced_highlight(true)
		_hint(_main.hint("TUT_BUY_ADVANCED", "TUT_BUY_ADVANCED_MOBILE"))

# "Bid on an Expedition": pick one, confirm the bid, pay, place it.
func _show_bid() -> void:
	if _is_dragging(CardData.CardType.EXPEDITION):
		_main._market_panel.set_tutorial_expedition_highlight(false)
		_hint(tr("TUT_BID_PLACE"))
	elif _main._bid_popup and _main._bid_popup.visible:
		_main._market_panel.set_tutorial_expedition_highlight(false)
		_hint(tr("TUT_BID_POPUP"))
	elif _main._bid_payment_panel and _main._bid_payment_panel.visible:
		_main._market_panel.set_tutorial_expedition_highlight(false)
		_hint(tr("TUT_BID_PAY"))
	else:
		_main._market_panel.set_tutorial_expedition_highlight(true)
		_hint(_main.hint("TUT_BID_DEFAULT", "TUT_BID_DEFAULT_MOBILE"))

# ── Helpers ───────────────────────────────────────────────────────────────────

func _give(names: Array[String]) -> void:
	var cards: Array[CardData] = []
	for n: String in names:
		var cd: CardData = _tech(n)
		if cd:
			cards.append(cd)
	if not cards.is_empty():
		_board.add_specific_cards_to_hand(cards)
		_board.refresh_hand_discounts()

# A card's name in the current language, for the step texts.
static func _name(card_name: String) -> String:
	var cd: CardData = _tech(card_name)
	return CardDatabase.display_name(cd) if cd else card_name

static func _tech(card_name: String) -> CardData:
	for cd: CardData in CardDatabase.techs:
		if cd.card_name == card_name:
			return cd
	for cd: CardData in CardDatabase.expeditions:
		if cd.card_name == card_name:
			return cd
	return null

# Hands a card over unless an effect already drew it into the hand.
func _give_if_missing(card_name: String) -> void:
	for c: Node3D in _main.get_node("Hand").get_cards():
		var cd: CardData = c.get("card_data")
		if cd and cd.card_name == card_name:
			return
	_give([card_name])

static func _cards(names: Array[String]) -> Array[CardData]:
	var out: Array[CardData] = []
	for n: String in names:
		var cd: CardData = _tech(n)
		if cd:
			out.append(cd)
	return out

func _top_up_supply() -> void:
	for color: CardData.SupplyColor in CardData.SupplyColor.values():
		if _main._cs_display.get_supply(color) < MIN_SUPPLY:
			_main._cs_display.set_supply(color, MIN_SUPPLY)

# The cards the first sector's first optimize group still needs ("Any" = Mag-Net).
func _missing_optimize_cards() -> Array[String]:
	var out: Array[String] = []
	if _first_sector == null or _first_sector.placed_card == null:
		return out
	var cd: CardData = _first_sector.placed_card.card_data
	var req: Array = cd.adv_opt1_req if bool(_first_sector.placed_card.get("is_advanced")) else cd.opt1_req
	var have: Array[int] = _first_sector.get_placed_tech_colors()
	for c: Variant in req:
		var color: int = int(c)
		var i: int = have.find(color)
		if i >= 0:
			have.remove_at(i)
		else:
			out.append(str(FILLER_BY_COLOR.get(color, "Mag-Net")))
	return out

func _any_tucked(face_up: bool) -> bool:
	for slot: SectorSlot in _board.get_sector_slots():
		for t: Dictionary in slot.tucked_cards:
			if bool(t.get("face_up", false)) == face_up:
				return true
	return false

func _any_tech_space() -> bool:
	for slot: SectorSlot in _board.get_sector_slots():
		if slot.has_tech_space():
			return true
	return false

func _any_stored() -> bool:
	for slot: SectorSlot in _board.get_sector_slots():
		if slot.get_total_stored_supply() > 0:
			return true
	return false

func _is_dragging(t: CardData.CardType) -> bool:
	var dragged: Node3D = _board.get("_dragged_card") as Node3D
	if not dragged:
		return false
	var cd: CardData = dragged.get("card_data")
	return cd != null and cd.card_type == t

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

func _clear_highlights() -> void:
	for slot: SectorSlot in _highlighted_tech_slots:
		if is_instance_valid(slot):
			slot.highlight(false)
	_highlighted_tech_slots = []
	if _main == null:
		return
	_main._market_panel.set_tutorial_dust_highlight(false)
	_main._market_panel.set_tutorial_advanced_highlight(false)
	_main._market_panel.set_tutorial_expedition_highlight(false)
	_main._cs_display._flow.set_tutorial_highlight(false)
	_main._stop_research_btn_3d_flash()
	_main._stop_pass_btn_3d_flash()
	_show_recycle_arrow(false)

func _mark_done() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("tutorial", "seen", true)
	cfg.save(SETTINGS_PATH)

# Phones: an animated arrow from the hand to the control screen, since
# recycling there is a drag (no right-click) that's hard to guess.
var _recycle_arrow: DragArrow = null

func _show_recycle_arrow(on: bool) -> void:
	if not GameTheme.is_touch():
		return
	if not on:
		if _recycle_arrow:
			_recycle_arrow.hide_arrow()
		return
	var cam: Camera3D = _main.get_viewport().get_camera_3d()
	var screen_mesh: MeshInstance3D = _board.get("_control_screen_mesh") as MeshInstance3D
	if cam == null or screen_mesh == null:
		return
	if _recycle_arrow == null:
		var canvas: CanvasLayer = CanvasLayer.new()
		canvas.layer = 10
		add_child(canvas)
		_recycle_arrow = DragArrow.new()
		canvas.add_child(_recycle_arrow)
	var from_2d: Vector2 = cam.unproject_position((_main.get_node("Hand") as Node3D).global_position)
	var to_2d: Vector2 = cam.unproject_position(screen_mesh.to_global(screen_mesh.mesh.get_aabb().get_center()))
	_recycle_arrow.show_arrow(from_2d, to_2d)
