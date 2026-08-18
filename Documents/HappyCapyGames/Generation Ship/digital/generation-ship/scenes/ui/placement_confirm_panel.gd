class_name PlacementConfirmPanel
extends Control

signal confirmed
signal cancelled

const SUPPLY_ICON_PATHS: Array[String] = [
	"res://assets/ui/supply/Dust.png",
	"res://assets/ui/supply/Metals.png",
	"res://assets/ui/supply/Liquids.png",
	"res://assets/ui/supply/Organix.png",
	"res://assets/ui/supply/Electrix.png",
	"res://assets/ui/supply/Thrust.png",
]
# BBCode [img] with no explicit size renders at the source PNG's native
# resolution, which is far larger than this text — always pin both
# dimensions so the inline token stays icon-sized instead of ballooning.
const TOKEN_ICON_PX: int = 36

var _title: RichTextLabel

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(20)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 36)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	_title = RichTextLabel.new()
	_title.bbcode_enabled = true
	_title.fit_content = true
	_title.scroll_active = false
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("normal_font_size", 40)
	vbox.add_child(_title)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 24)
	vbox.add_child(btn_row)

	var confirm_btn := Button.new()
	confirm_btn.text = tr("Confirm")
	confirm_btn.custom_minimum_size = Vector2(220, 64)
	confirm_btn.add_theme_font_size_override("font_size", 26)
	confirm_btn.pressed.connect(func() -> void:
		hide()
		confirmed.emit()
	)
	btn_row.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = tr("Cancel")
	cancel_btn.custom_minimum_size = Vector2(220, 64)
	cancel_btn.add_theme_font_size_override("font_size", 26)
	cancel_btn.pressed.connect(func() -> void:
		hide()
		cancelled.emit()
	)
	btn_row.add_child(cancel_btn)

func show_confirm(card_name: String, card_color: CardData.SupplyColor, target_name: String, target_color: CardData.SupplyColor, preview_steps: Array[Dictionary] = []) -> void:
	var card_part: String = "[color=#%s]%s[/color] [img=%dx%d]%s[/img]" % [
		CardData.color_tint(card_color).to_html(false), card_name,
		TOKEN_ICON_PX, TOKEN_ICON_PX, SUPPLY_ICON_PATHS[card_color],
	]
	var body: String
	if target_name.is_empty():
		body = tr("Place %s here?") % card_part
	else:
		var target_part: String = "[color=#%s]%s[/color]" % [CardData.color_tint(target_color).to_html(false), target_name]
		body = tr("Place %s on %s?") % [card_part, target_part]
	var text: String = "[center]%s[/center]" % body
	var lines: PackedStringArray = []
	for step: Dictionary in preview_steps:
		var line: String = _describe_step(step)
		if not line.is_empty():
			lines.append("•  " + line)
	if not lines.is_empty():
		text += "\n\n" + "\n".join(lines)
	_title.text = text
	show()

# Short, deterministic summary of a single effect step for the preview list
# above — mirrors _execute_effect_step's step-type handling in main.gd, but
# terser (a one-line "what happens" instead of that function's interactive
# prompts). Steps that are just plumbing for a later interactive choice
# (offer_bid_pool and friends, always paired with a preceding reveal_*
# step that already conveys the effect) are intentionally skipped —
# returning "" — since main.gd only ever supplies known step
# Dictionaries here, not arbitrary/malformed ones.
func _describe_step(step: Dictionary) -> String:
	var t: String = str(step.get("type", ""))
	match t:
		"draw":
			return tr("Draw %d") % int(step.get("count", 0))
		"draw_recycle_top":
			return tr("Draw & recycle the top card")
		"draw_all_players":
			return tr("Every player draws %d") % int(step.get("count", 0))
		"interfleet_comms":
			return tr("Draw 1 card per player")
		"gain_supply":
			return tr("Gain %d %s") % [int(step.get("amount", 0)), CardData.color_name(step["color"] as CardData.SupplyColor)]
		"gain_supply_per_sector_count":
			return tr("Gain 1 %s per sector on the ship") % CardData.color_name(step["color"] as CardData.SupplyColor)
		"gain_supply_per_stored":
			return tr("Gain %s equal to ×%d the stored amount") % [CardData.color_name(step["color"] as CardData.SupplyColor), int(step.get("multiplier", 1))]
		"store_on_slot":
			return tr("Store %d %s on this sector") % [int(step.get("amount", 0)), CardData.color_name(step["color"] as CardData.SupplyColor)]
		"store_on_any_sector":
			return tr("Store %d %s on a sector of your choice") % [int(step.get("amount", 1)), CardData.color_name(step["color"] as CardData.SupplyColor)]
		"store_per_card_here":
			return tr("Store 1 supply per card here (matching each card's color)")
		"fuse_notice":
			return tr("Fuse 1:1 ×%d") % int(step.get("count", 0))
		"fuse_dust_1to1":
			return tr("Fuse Dust 1:1")
		"recycle":
			return tr("Recycle %d card(s)") % int(step.get("count", 1))
		"recycle_optional":
			return tr("Recycle up to %d card(s), draw 1 per recycled") % int(step.get("max", 1))
		"recycle_double":
			return tr("Recycle %d card(s) for double supply") % int(step.get("count", 1))
		"tuck":
			var face: String = tr("faceup") if bool(step.get("face_up", false)) else tr("facedown")
			return tr("Tuck %d card(s) %s") % [int(step.get("count", 1)), face]
		"tuck_optional":
			var face_o: String = tr("faceup") if bool(step.get("face_up", false)) else tr("facedown")
			return tr("Tuck up to %d card(s) %s") % [int(step.get("max", 1)), face_o]
		"tuck_any_sector_optional":
			var face_a: String = tr("faceup") if bool(step.get("face_up", false)) else tr("facedown")
			return tr("Tuck up to %d card(s) %s on any sector") % [int(step.get("max", 1)), face_a]
		"recycle_tuck":
			return tr("Recycle & tuck up to %d card(s) facedown, draw equal") % int(step.get("count", 2))
		"recycle_tuck_store_choice":
			return tr("Recycle & tuck/store up to %d card(s)") % int(step.get("max", 4))
		"reveal_sector":
			return tr("Reveal a sector card")
		"reveal_expedition":
			return tr("Reveal an expedition card")
		"choice":
			return str(step.get("prompt", tr("Choose an effect")))
		"cargo_drones":
			return tr("Move a cargo drone")
		"seedbanks":
			return tr("Seedbanks effect")
		"black_hole_encounter":
			return tr("Black Hole Encounter effect")
		"reflectors_choice":
			return tr("Reflectors effect")
		"caldera_colony":
			return tr("Caldera Colony effect")
	return ""
