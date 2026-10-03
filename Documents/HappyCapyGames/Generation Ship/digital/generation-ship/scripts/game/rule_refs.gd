class_name RuleRefs
# Keywords in card text -> the rule book page that explains them, so the game
# can offer "how does Archive work?" right where the word shows up (the
# sector info popup, the phones' card inspect view). Every language's rule
# book has the same 12-page layout, so one page number works for all.
#
# Pages (1-based, as ManualPopup counts them): 5 Actions (Recycle, Fuse),
# 7 Optimize + Bidding, 12 Terms to remember (New, Complete, Fully optimized,
# Store supply, Archive cards).

const TERMS: Array[Array] = [
	# [label (translated with tr), regex on the English effect text, page]
	["Archive", "\\barchiv", 12],
	["Store", "\\bstor(e|ed|es)\\b", 12],
	["Fully optimized", "fully optimi[sz]ed", 12],
	["Complete", "\\bcomplete\\b", 12],
	["New", "\\bnew\\b", 12],
	["Optimize", "\\boptimi[sz]e", 7],
	["Bid", "\\bbid", 7],
	["Fuse", "\\bfuse", 5],
	["Recycle", "\\brecycl", 5],
]
const RULE_BOOK_SCRIPT: String = "res://scenes/ui/manual_popup.gd"
const SHARED_META: StringName = &"_rule_book_popup"

## [[label, page], ...] for every keyword in these cards' effect texts, in
## TERMS order, each once. Sectors always get Optimize (their optimize row).
static func terms_for(cards: Array[CardData], advanced: Array[bool] = []) -> Array[Array]:
	var found: Dictionary = {}
	for i: int in cards.size():
		var cd: CardData = cards[i]
		if cd == null:
			continue
		var adv: bool = i < advanced.size() and advanced[i]
		var text: String = (cd.adv_effect_text if adv and not cd.adv_effect_text.is_empty() else cd.effect_text).to_lower()
		if cd.card_type == CardData.CardType.SECTOR:
			found["Optimize"] = true
		for t: Array in TERMS:
			var re: RegEx = RegEx.create_from_string(str(t[1]))
			if re.search(text):
				found[str(t[0])] = true
	var out: Array[Array] = []
	for t: Array in TERMS:
		if found.has(str(t[0])):
			out.append([str(t[0]), int(t[2])])
	return out

## A row of small buttons, one per term, each opening the rule book at its page.
static func make_term_row(terms: Array[Array], font_size: int = 16) -> Control:
	var row: HFlowContainer = HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	for t: Array in terms:
		var btn: Button = Button.new()
		btn.text = "? " + TranslationServer.translate(str(t[0]))
		btn.tooltip_text = TranslationServer.translate("Rule Book")
		btn.add_theme_font_size_override("font_size", font_size)
		GameTheme.apply_to_button(btn)
		GameTheme.touchify(btn)
		var page: int = int(t[1])
		btn.pressed.connect(func() -> void: open_page(btn, page))
		row.add_child(btn)
	return row

## Opens the rule book at a page, over the current scene (one shared popup).
static func open_page(from: Node, page: int) -> void:
	var tree: SceneTree = from.get_tree()
	if tree == null or tree.current_scene == null:
		return
	var scene: Node = tree.current_scene
	var popup: Control = scene.get_meta(SHARED_META) as Control if scene.has_meta(SHARED_META) else null
	if popup == null or not is_instance_valid(popup):
		popup = load(RULE_BOOK_SCRIPT).new()
		var layer: Node = scene.get_node_or_null("UILayer")
		(layer if layer else scene).add_child(popup)
		scene.set_meta(SHARED_META, popup)
	popup.call("open_at", page)
