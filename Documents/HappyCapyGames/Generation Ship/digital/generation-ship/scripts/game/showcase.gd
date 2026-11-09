extends RefCounted
## Screenshot set-up (2026-11-09, for the presenter screenshot): a Versus game well into Generation 3, the
## three bots named Pixel Pawel, Cornelius and Communi-Kate, every ship filled with sectors, techs, an
## expedition, archived cards and stored supply, and a few log lines to match. Only with the command-line
## flag --showcase (tools/showcase.cmd); a normal game never sees any of it. After the set-up the game plays on
## as usual. Preloaded (no class_name: new class_names broke main.gd before).

const BOT_NAMES: Array[String] = ["Pixel Pawel", "Cornelius", "Communi-Kate"]
const ROUND: int = 3
const SEED: int = 20261109
# your ship, sector by sector: [advanced side up, cards on it]
const YOUR_SHIP: Array = [[true, 5], [false, 4], [true, 3], [true, 4], [false, 2]]
# the bots' ships, one list each (in the order the bots were added)
const BOT_SHIPS: Array = [
	[[true, 4], [false, 3], [true, 2], [false, 3]],
	[[false, 5], [true, 3], [true, 3]],
	[[true, 3], [true, 4], [false, 2], [true, 1], [false, 2]],
]
const YOUR_SUPPLY: Array[int] = [6, 3, 2, 4, 1, 2]   # Dust, Metals, Liquids, Organix, Electrix, Thrust

static func active() -> bool:
	return OS.get_cmdline_user_args().has("--showcase")

## The name for the n-th bot added in the lobby (1-based), "" past the three.
static func bot_name(n: int) -> String:
	return BOT_NAMES[n - 1] if n >= 1 and n <= BOT_NAMES.size() else ""

## Host only, right after the opening deal (Main._rpc_start_game).
static func fill(main: Main) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var board: Node3D = main.get_node("Board") as Node3D
	var scene: PackedScene = board.get("_card_scene") as PackedScene
	var slots: Array = board.call("get_sector_slots") as Array
	var log_lines: Array[Array] = []   # [text, colour]

	# ── your ship ──
	var names: Array[String] = []
	var my_techs: Array[CardData] = []
	for i: int in mini(YOUR_SHIP.size(), slots.size()):
		var adv: bool = bool(YOUR_SHIP[i][0])
		var cd: CardData = _take_sector(rng, adv, names)
		if cd == null:
			continue
		var slot: SectorSlot = slots[i] as SectorSlot
		var sector_card: Node3D = _new_card(scene, slot, cd, adv)
		slot.accept_card(sector_card)
		_settle(sector_card)
		var stack: Array[CardData] = _stack_for(cd, adv, int(YOUR_SHIP[i][1]), rng, names)
		if i == 0 and not stack.is_empty() and not CardDatabase.expeditions.is_empty():   # an expedition on top of the first one
			stack[stack.size() - 1] = CardDatabase.expeditions[rng.randi() % CardDatabase.expeditions.size()]
		for t: CardData in stack:
			var tc: Node3D = _new_card(scene, slot, t, false)
			slot.accept_tech_card(tc)
			_settle(tc)
			if t.card_type == CardData.CardType.TECH:
				my_techs.append(t)
		board.call("_update_optimize_state", slot)
		if i == 1 or i == 3:
			slot.add_tucked_card(_any_tech(rng), false)
			slot.add_tucked_card(_any_tech(rng), false)
		if i == 2:
			slot.add_tucked_card(_any_tech(rng), true)
		if i == 0 or i == 3:
			slot.add_stored_supply(_side_color(cd, adv), 1 + rng.randi() % 2)
		slot.refresh_display()
	for c: int in YOUR_SUPPLY.size():
		main._cs_display.set_supply(c as CardData.SupplyColor, YOUR_SUPPLY[c])

	# ── the bots' ships ──
	for b: int in GameNetwork.bot_ids.size():
		var bot_id: int = GameNetwork.bot_ids[b]
		var plan: Array = BOT_SHIPS[b % BOT_SHIPS.size()] as Array
		var bot_names: Array[String] = []
		var entries: Array = []
		var bname: String = str(GameNetwork.player_names.get(bot_id, "Bot"))
		for p_v: Variant in plan:
			var p: Array = p_v as Array
			var adv: bool = bool(p[0])
			var cd: CardData = _take_sector(rng, adv, bot_names)
			if cd == null:
				continue
			var e: Dictionary = BotTurn._new_slot_entry(cd, adv)
			var stack: Array[CardData] = _stack_for(cd, adv, int(p[1]), rng, bot_names)
			for t: CardData in stack:
				(e["techs"] as Array).append(t)
				e["last_placed_tech_cost"] = t.cost
			BotTurn._bot_update_optimize(e, BotScoring.slot_tech_colors(e))
			if rng.randf() < 0.5:
				e["tucked_cards"] = [{"data": _any_tech(rng), "face_up": rng.randf() < 0.3}]
			if rng.randf() < 0.4:
				e["stored_supply"] = {int(_side_color(cd, adv)): 1 + rng.randi() % 2}
			entries.append(e)
			if adv and log_lines.size() < 2:
				log_lines.append([main.tr("%s won %s for %d") % [bname, cd.adv_name, 3 + rng.randi() % 3], Color(1.0, 0.92, 0.35)])
			elif not stack.is_empty() and rng.randf() < 0.5:
				var t0: CardData = stack[stack.size() - 1]
				log_lines.append([main.tr("%s: placed %s") % [bname, t0.card_name], CardData.color_tint(t0.color)])
		main.bot_boards[bot_id] = entries
		var supply: Dictionary = {}
		for c: int in 6:
			supply[c] = rng.randi_range(0, 6) if c != 0 else rng.randi_range(3, 8)
		main.bot_supplies[bot_id] = supply

	# ── round, VP, log, the opponents' rows ──
	main._round = ROUND
	main._update_round_label()
	main._refresh_vp()
	var me: String = str(GameNetwork.player_names.get(1, main.tr("You")))
	if not my_techs.is_empty():
		var mt: CardData = my_techs[my_techs.size() - 1]
		log_lines.insert(mini(1, log_lines.size()), [main.tr("%s: placed %s") % [me, mt.card_name], CardData.color_tint(mt.color)])
	for line: Array in log_lines:
		main._log_action(str(line[0]), line[1] as Color)
	main._broadcast_my_state()

# A sector not on this ship yet (by the side shown), from a fresh shuffle of the 30 sector cards.
static func _take_sector(rng: RandomNumberGenerator, adv: bool, taken: Array[String]) -> CardData:
	var pool: Array[CardData] = CardDatabase.sectors.duplicate()
	for i: int in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var tmp: CardData = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	for cd: CardData in pool:
		var shown: String = cd.adv_name if adv else cd.card_name
		if shown.is_empty() or taken.has(shown):
			continue
		taken.append(shown)
		return cd
	return null

# n techs for a sector, in the colours its optimize asks for where there are any (not repeated on the ship).
static func _stack_for(cd: CardData, adv: bool, n: int, rng: RandomNumberGenerator, taken: Array[String]) -> Array[CardData]:
	var want: Array[int] = []
	var reqs: Array = [cd.adv_opt1_req, cd.adv_opt2_req, cd.adv_opt3_req] if adv else [cd.opt1_req]
	for r_v: Variant in reqs:
		for c: int in (r_v as Array[int]):
			if not want.has(c):
				want.append(c)
	var fits: Array[CardData] = []
	var rest: Array[CardData] = []
	for t: CardData in CardDatabase.techs:
		if taken.has(t.card_name):
			continue
		if want.has(int(t.color)):
			fits.append(t)
		else:
			rest.append(t)
	var out: Array[CardData] = []
	for _k: int in n:
		var src: Array[CardData] = fits if not fits.is_empty() else rest
		if src.is_empty():
			break
		var t: CardData = src[rng.randi() % src.size()]
		out.append(t)
		taken.append(t.card_name)
		fits.erase(t)
		rest.erase(t)
	return out

static func _any_tech(rng: RandomNumberGenerator) -> CardData:
	return CardDatabase.techs[rng.randi() % CardDatabase.techs.size()]

static func _side_color(cd: CardData, adv: bool) -> CardData.SupplyColor:
	return cd.adv_color if adv else cd.color

static func _new_card(scene: PackedScene, parent: Node, cd: CardData, adv: bool) -> Node3D:
	var card: Node3D = scene.instantiate() as Node3D
	parent.add_child(card)
	card.set("is_advanced", adv)
	card.call("set_card_data", cd)
	return card

# placed, without card.place()'s sparkle and camera shake for every one of the ~20 cards
static func _settle(card: Node3D) -> void:
	card.set("is_placed", true)
	card.visible = true
