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
const CONFIRM_DURATION := 1.3
const FINISH_COLOR := Color(1.0, 0.75, 0.4)

var _title_label: Label = null
var _summary_label: Label = null
var _content: Control = null
var _footer: HBoxContainer = null
var _next_btn: Button = null

var _step: _Step = _Step.SOURCE
var _all_slots: Array[SectorSlot] = []
var _source_slot: SectorSlot = null
var _dest_slot: SectorSlot = null
var _supply_entries: Array = []   # {color: int, spinbox: SpinBox}
var _tucked_btns: Array[Button] = []
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
	_next_btn = null
	for child: Node in _content.get_children():
		child.queue_free()
	for child: Node in _footer.get_children():
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
	_set_title(tr("Cargo Drones — choose what to move"))
	_clear_step()
	_build_choose_step()
	var back_btn := Button.new()
	back_btn.text = tr("← Pick Different Source")
	GameTheme.size_info_button(back_btn)
	back_btn.pressed.connect(_go_to_source)
	_footer.add_child(back_btn)
	_add_finish_button()
	# Primary action rightmost, like the other panels: Back | Finish | Next.
	if _next_btn:
		_footer.move_child(_next_btn, -1)

func _build_choose_step() -> void:
	_supply_entries.clear()
	_tucked_btns.clear()

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var slot: SectorSlot = _source_slot
	var has_content: bool = false

	if _has_stored_supply(slot):
		has_content = true
		_add_section_label(vbox, tr("Move Supplies"))
		for i: int in 6:
			var count: int = slot.stored_supply.get(i, 0)
			if count == 0:
				continue
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var name_lbl := Label.new()
			name_lbl.text = CardData.color_name(i as CardData.SupplyColor)
			name_lbl.add_theme_font_size_override("font_size", 18)
			name_lbl.add_theme_color_override("font_color", Color.WHITE)
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_lbl)
			var avail_lbl := Label.new()
			avail_lbl.text = tr("(of %d)") % count
			avail_lbl.add_theme_font_size_override("font_size", 16)
			avail_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			row.add_child(avail_lbl)
			var spinbox := SpinBox.new()
			spinbox.min_value = 0
			spinbox.max_value = count
			spinbox.value = 0
			spinbox.step = 1
			spinbox.custom_minimum_size = Vector2(90, 0)
			spinbox.value_changed.connect(func(_v: float) -> void: _refresh_next_enabled())
			row.add_child(spinbox)
			vbox.add_child(row)
			_supply_entries.append({color = i, spinbox = spinbox})

	if not slot.tucked_cards.is_empty():
		has_content = true
		_add_section_label(vbox, tr("Move Tucked Cards"))
		for i: int in slot.tucked_cards.size():
			var entry: Dictionary = slot.tucked_cards[i]
			var cd: CardData = entry.get("data") as CardData
			var face_up: bool = entry.get("face_up", false)
			var url: String = (cd.image_url if cd else "") if face_up else SectorInfoPopup.tech_back_path()
			var tex: Texture2D = ImageCache.get_texture(url) if not url.is_empty() else null

			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var img := TextureRect.new()
			img.custom_minimum_size = Vector2(70, 98)
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			var mat: ShaderMaterial = ShaderMaterial.new()
			mat.shader = load("res://shaders/card_rounded.gdshader")
			img.material = mat
			if tex:
				img.texture = tex
			else:
				img.modulate = Color(0.12, 0.18, 0.32) if not face_up else Color(0.92, 0.87, 0.76)
			row.add_child(img)
			var name_lbl := Label.new()
			name_lbl.text = (CardDatabase.display_name(cd) if cd else tr("?")) if face_up else tr("Facedown")
			name_lbl.add_theme_font_size_override("font_size", 17)
			name_lbl.add_theme_color_override("font_color", Color.WHITE)
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			row.add_child(name_lbl)
			var btn := Button.new()
			btn.text = tr("Move")
			btn.toggle_mode = true
			btn.toggled.connect(func(on: bool) -> void:
				btn.modulate = Color(0.4, 1.0, 0.5) if on else Color.WHITE
				_refresh_next_enabled()
			)
			row.add_child(btn)
			vbox.add_child(row)
			_tucked_btns.append(btn)

	if not has_content:
		var empty := Label.new()
		empty.text = tr("Nothing to move here")
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 18)
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		vbox.add_child(empty)
		return

	_next_btn = Button.new()
	_next_btn.text = tr("Next: Pick Destination →")
	GameTheme.style_positive(_next_btn)
	GameTheme.size_info_button(_next_btn)
	_next_btn.disabled = true
	_next_btn.pressed.connect(_on_choose_next_pressed)
	_footer.add_child(_next_btn)

func _refresh_next_enabled() -> void:
	if not _next_btn:
		return
	var any_selected: bool = false
	for e: Dictionary in _supply_entries:
		if int((e.spinbox as SpinBox).value) > 0:
			any_selected = true
			break
	if not any_selected:
		for btn: Button in _tucked_btns:
			if btn.button_pressed:
				any_selected = true
				break
	_next_btn.disabled = not any_selected

func _add_section_label(parent: Node, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.8, 1.0))
	parent.add_child(lbl)

func _has_stored_supply(slot: SectorSlot) -> bool:
	for count: int in slot.stored_supply.values():
		if count > 0:
			return true
	return false

func _on_choose_next_pressed() -> void:
	_pending_supplies = {}
	for e: Dictionary in _supply_entries:
		var amount: int = int((e.spinbox as SpinBox).value)
		if amount > 0:
			_pending_supplies[e.color] = amount
	_pending_tucked_indices = []
	for i: int in _tucked_btns.size():
		if _tucked_btns[i].button_pressed:
			_pending_tucked_indices.append(i)
	_go_to_dest()

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
