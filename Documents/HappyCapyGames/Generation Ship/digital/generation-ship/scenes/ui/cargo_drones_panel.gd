class_name CargoDronesPanel
extends Control

# Cargo Drones used to bounce between the generic sector-picker grid and
# SectorInfoPopup's cargo section (two separate widgets swapping in and out),
# which read as disconnected steps and left "am I done or picking another
# sector?" ambiguous. This panel owns the whole pick-source -> choose-what ->
# pick-destination -> confirm loop as one continuous screen instead, with a
# persistent summary line carrying context across steps and a single
# "Finish Cargo Drones" button (visually distinct from the Next/Back flow
# buttons) that's always available to end the effect.

signal move_requested(source: SectorSlot, dest: SectorSlot, supplies: Dictionary, tucked_indices: Array[int])
signal finished

enum _Step { SOURCE, CHOOSE, DEST, CONFIRM }

const SECTOR_W_H_RATIO := 88.0 / 63.0
const GRID_PADDING := 16.0
const GRID_GAP := 12.0
const FOOTER_SIDE_MARGIN: float = 80.0   # panel content margins + a little air
const FOOTER_MIN_FONT: int = 14
const CONFIRM_DURATION := 0.7
const FINISH_COLOR := Color(1.0, 0.75, 0.4)
const TILE_SIZE: Vector2 = Vector2(170.0, 210.0)   # info-screen px: easy to hit with a finger or a mouse
const TILE_ICON: float = 96.0
const TILE_GAP: int = 18
const SUPPLY_ICON_PATHS: Array[String] = [
	"res://assets/ui/supply/Dust.png",
	"res://assets/ui/supply/Metals.png",
	"res://assets/ui/supply/Liquids.png",
	"res://assets/ui/supply/Organix.png",
	"res://assets/ui/supply/Electrix.png",
	"res://assets/ui/supply/Thrust.png",
]

var _title_label: Label = null
var _summary_label: Label = null
var _content: Control = null
var _footer: HBoxContainer = null

var _step: _Step = _Step.SOURCE
var _all_slots: Array[SectorSlot] = []
var _source_slot: SectorSlot = null
var _dest_slot: SectorSlot = null
var _pending_supplies: Dictionary = {}
var _pending_tucked_indices: Array[int] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(20)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 10)
	outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(outer_vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 26)
	_title_label.add_theme_color_override("font_color", Color.WHITE)
	outer_vbox.add_child(_title_label)

	_summary_label = Label.new()
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_label.add_theme_font_size_override("font_size", 18)
	_summary_label.add_theme_color_override("font_color", Color(0.75, 0.8, 1.0))
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_summary_label.visible = false
	outer_vbox.add_child(_summary_label)

	_content = Control.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(_content)

	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 16)
	_footer.alignment = BoxContainer.ALIGNMENT_CENTER
	outer_vbox.add_child(_footer)

func start(all_slots: Array[SectorSlot]) -> void:
	_all_slots = all_slots
	_source_slot = null
	_dest_slot = null
	_go_to_source()
	show()

func _clear_step() -> void:
	for child: Node in _content.get_children():
		child.queue_free()
	for child: Node in _footer.get_children():
		_footer.remove_child(child)   # now, so _fit_footer measures only the new buttons
		child.queue_free()

# Long translated titles (German especially) would otherwise run past the panel.
func _set_title(text: String) -> void:
	_title_label.text = text
	GameTheme.fit_label_width(_title_label, get_viewport_rect().size.x - 40.0, 26, 16)

func _add_finish_button() -> void:
	var btn := Button.new()
	btn.text = tr("Finish Cargo Drones")
	GameTheme.style_positive(btn)
	GameTheme.size_info_button(btn)
	btn.add_theme_color_override("font_color", FINISH_COLOR)
	btn.pressed.connect(func() -> void: hide(); finished.emit())
	_footer.add_child(btn)
	_fit_footer.call_deferred()   # every step ends here; runs once its footer is complete

# The footer's buttons shrink their text until the row fits the screen: three
# long labels (Back | Finish | Next) were wider than the info screen, which
# stretched the whole panel past its edge and hid the counters on the right.
func _fit_footer() -> void:
	var avail: float = get_viewport_rect().size.x - FOOTER_SIDE_MARGIN
	var buttons: Array[Button] = []
	for child: Node in _footer.get_children():
		if child is Button and not child.is_queued_for_deletion():
			buttons.append(child as Button)
	var guard: int = 40
	while guard > 0 and _footer.get_combined_minimum_size().x > avail:
		guard -= 1
		var shrunk: bool = false
		for b: Button in buttons:
			var f: int = b.get_theme_font_size("font_size")
			if f > FOOTER_MIN_FONT:
				b.add_theme_font_size_override("font_size", f - 1)
				shrunk = true
		if not shrunk:
			break

func _occupied_slots(exclude: SectorSlot) -> Array[SectorSlot]:
	var result: Array[SectorSlot] = []
	for slot: SectorSlot in _all_slots:
		if slot.occupied and slot != exclude:
			result.append(slot)
	return result

func _sector_display_name(slot: SectorSlot) -> String:
	if slot and slot.placed_card and slot.placed_card.card_data:
		var cd: CardData = slot.placed_card.card_data
		var is_adv: bool = bool(slot.placed_card.get("is_advanced"))
		return cd.adv_name if (is_adv and not cd.adv_name.is_empty()) else cd.card_name
	return tr("Sector")

func _describe_pending() -> String:
	var parts: Array[String] = []
	for color: int in _pending_supplies:
		parts.append(tr("%d %s") % [_pending_supplies[color], CardData.color_name(color as CardData.SupplyColor)])
	if not _pending_tucked_indices.is_empty():
		parts.append(tr("%d tucked card(s)") % _pending_tucked_indices.size())
	return ", ".join(parts) if not parts.is_empty() else tr("nothing")

# ── Step 1: pick a source sector ──────────────────────────────────────────────

func _go_to_source() -> void:
	_step = _Step.SOURCE
	_summary_label.visible = false
	_set_title(tr("Cargo Drones — pick a sector to move FROM"))
	_clear_step()
	_build_sector_grid(_occupied_slots(null), pick_source_slot)
	_add_finish_button()

func pick_source_slot(slot: SectorSlot) -> void:
	if _step != _Step.SOURCE or not slot.occupied:
		return
	_source_slot = slot
	_go_to_choose()

# ── Step 2: choose what to move ───────────────────────────────────────────────

func _go_to_choose() -> void:
	_step = _Step.CHOOSE
	_summary_label.visible = true
	_summary_label.text = tr("Moving from: %s") % _sector_display_name(_source_slot)
	_set_title(tr("Cargo Drones — tap what to move"))
	_clear_step()
	_build_choose_step()
	var back_btn := Button.new()
	back_btn.text = tr("← Pick Different Source")
	GameTheme.size_info_button(back_btn)
	back_btn.pressed.connect(_go_to_source)
	_footer.add_child(back_btn)
	_add_finish_button()

# One big tile per stored supply colour (icon + how many) and per archived card;
# a tap picks ONE of it and goes straight to the destination — no counters or
# Next button to fiddle with, on a phone or with a mouse.
func _build_choose_step() -> void:
	var slot: SectorSlot = _source_slot
	var tiles: Array[Button] = []
	for i: int in 6:
		var count: int = slot.stored_supply.get(i, 0)
		if count > 0:
			tiles.append(_make_supply_tile(i, count))
	for i: int in slot.tucked_cards.size():
		tiles.append(_make_tucked_tile(i, slot.tucked_cards[i] as Dictionary))

	if tiles.is_empty():
		var empty := Label.new()
		empty.text = tr("Nothing to move here")
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 22)
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		empty.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_content.add_child(empty)
		return

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", TILE_GAP)
	flow.add_theme_constant_override("v_separation", TILE_GAP)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(flow)
	for t: Button in tiles:
		flow.add_child(t)

func _make_tile() -> Button:
	var btn := Button.new()
	btn.set_meta(&"_info_enlarged", true)   # already big: skip the phone enlarge
	btn.custom_minimum_size = TILE_SIZE
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)
	return btn

func _tile_label(text: String, size: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

func _make_supply_tile(color: int, count: int) -> Button:
	var btn: Button = _make_tile()
	var box: VBoxContainer = btn.get_child(0) as VBoxContainer
	var icon := TextureRect.new()
	icon.texture = load(SUPPLY_ICON_PATHS[color]) as Texture2D
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(TILE_ICON, TILE_ICON)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	box.add_child(_tile_label("× %d" % count, 30))
	box.add_child(_tile_label(CardData.color_name(color as CardData.SupplyColor), 18))
	btn.tooltip_text = tr("Move 1 %s") % CardData.color_name(color as CardData.SupplyColor)
	btn.pressed.connect(func() -> void:
		_pending_supplies = {color: 1}
		_pending_tucked_indices = []
		_go_to_dest())
	return btn

func _make_tucked_tile(index: int, entry: Dictionary) -> Button:
	var btn: Button = _make_tile()
	var box: VBoxContainer = btn.get_child(0) as VBoxContainer
	var cd: CardData = entry.get("data") as CardData
	var face_up: bool = entry.get("face_up", false)
	var url: String = (cd.image_url if cd else "") if face_up else SectorInfoPopup.tech_back_path()
	var img := TextureRect.new()
	img.texture = ImageCache.get_texture(url) if not url.is_empty() else null
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.custom_minimum_size = Vector2(TILE_SIZE.x - 20.0, TILE_SIZE.y - 50.0)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://shaders/card_rounded.gdshader")
	img.material = mat
	box.add_child(img)
	var title: String = (CardDatabase.display_name(cd) if cd else tr("?")) if face_up else tr("Facedown")
	box.add_child(_tile_label(title, 16))
	btn.pressed.connect(func() -> void:
		_pending_supplies = {}
		_pending_tucked_indices = [index]
		_go_to_dest())
	return btn

func _has_stored_supply(slot: SectorSlot) -> bool:
	for count: int in slot.stored_supply.values():
		if count > 0:
			return true
	return false

# ── Step 3: pick a destination sector ─────────────────────────────────────────

func _go_to_dest() -> void:
	_step = _Step.DEST
	_summary_label.visible = true
	_summary_label.text = tr("Moving %s from %s") % [_describe_pending(), _sector_display_name(_source_slot)]
	_set_title(tr("Cargo Drones — pick a sector to move TO"))
	_clear_step()
	_build_sector_grid(_occupied_slots(_source_slot), pick_dest_slot)
	var back_btn := Button.new()
	back_btn.text = tr("← Back")
	GameTheme.size_info_button(back_btn)
	back_btn.pressed.connect(_go_to_choose)
	_footer.add_child(back_btn)
	_add_finish_button()

func pick_dest_slot(slot: SectorSlot) -> void:
	if _step != _Step.DEST or not slot.occupied or slot == _source_slot:
		return
	_dest_slot = slot
	move_requested.emit(_source_slot, _dest_slot, _pending_supplies, _pending_tucked_indices)
	_go_to_confirm()

# ── Step 4: brief confirmation, then loop back to source ─────────────────────

func _go_to_confirm() -> void:
	_step = _Step.CONFIRM
	_summary_label.visible = false
	_set_title(tr("Cargo Drones"))
	_clear_step()
	var lbl := Label.new()
	lbl.text = tr("Moved %s\n%s → %s") % [_describe_pending(), _sector_display_name(_source_slot), _sector_display_name(_dest_slot)]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_content.add_child(lbl)
	_add_finish_button()
	get_tree().create_timer(CONFIRM_DURATION).timeout.connect(func() -> void:
		if _step == _Step.CONFIRM and visible:
			if _source_slot and (_has_stored_supply(_source_slot) or not _source_slot.tucked_cards.is_empty()):
				_go_to_choose()   # one at a time: straight back for the next item
			else:
				_go_to_source()
	)

# ── Shared sector-grid builder (used by both the source and dest steps) ──────

func _build_sector_grid(slots: Array[SectorSlot], on_pick: Callable) -> void:
	if slots.is_empty():
		var empty := Label.new()
		empty.text = tr("No sectors available")
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 18)
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_content.add_child(empty)
		return

	var btns: Array[Button] = []
	for slot: SectorSlot in slots:
		btns.append(_build_card_btn(slot, on_pick))
	_layout_grid(btns)

# Sector cards as big as the content area allows (one row, centred), measured
# once the title/summary/footer have taken their space — a fixed height cap
# used to leave them small in the middle of an empty panel.
var _grid_btns: Array[Button] = []

# Placed again whenever the content area changes size: the first grid is built
# before the panel is shown, while the area can still be 0x0 — the cards then
# came out with no size at all, only their name labels showing.
func _layout_grid(btns: Array[Button]) -> void:
	_grid_btns = btns
	if not _content.resized.is_connected(_place_grid):
		_content.resized.connect(_place_grid)
	_place_grid.call_deferred()

func _place_grid() -> void:
	var btns: Array[Button] = []
	for b: Button in _grid_btns:
		if is_instance_valid(b):
			btns.append(b)
	var n: int = btns.size()
	var avail: Vector2 = _content.size
	if n == 0 or avail.x <= GRID_PADDING * 2.0 or avail.y <= 0.0:
		return
	var card_w: float = (avail.x - GRID_PADDING * 2.0 - GRID_GAP * float(n - 1)) / float(n)
	var card_h: float = card_w / SECTOR_W_H_RATIO
	if card_h > avail.y:
		card_h = avail.y
		card_w = card_h * SECTOR_W_H_RATIO
	var total_w: float = card_w * float(n) + GRID_GAP * float(n - 1)
	var origin: Vector2 = Vector2((avail.x - total_w) / 2.0, (avail.y - card_h) / 2.0)
	for i: int in n:
		btns[i].custom_minimum_size = Vector2.ZERO   # sized here, not by a minimum
		btns[i].position = origin + Vector2(float(i) * (card_w + GRID_GAP), 0.0)
		btns[i].size = Vector2(card_w, card_h)
		btns[i].visible = true

func _build_card_btn(slot: SectorSlot, on_pick: Callable) -> Button:
	var btn := Button.new()
	btn.visible = false   # placed and shown by _layout_grid
	btn.flat = true
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(1.0, 1.0, 1.0, 0.15)
	hover_style.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", hover_style)
	_content.add_child(btn)

	var rect := TextureRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(rect)

	var lbl := Label.new()
	lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	lbl.offset_top = -38.0
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)

	if slot.placed_card and slot.placed_card.card_data:
		var cd: CardData = slot.placed_card.card_data as CardData
		var is_adv: bool = bool(slot.placed_card.get("is_advanced"))
		var url: String = cd.adv_image_url if is_adv else cd.image_url
		lbl.text = CardDatabase.display_name(cd, is_adv)
		if not url.is_empty():
			rect.texture = ImageCache.get_texture(url)

	var captured: SectorSlot = slot
	btn.pressed.connect(func() -> void: on_pick.call(captured))
	return btn
