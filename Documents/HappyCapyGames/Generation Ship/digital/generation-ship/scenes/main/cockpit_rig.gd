class_name CockpitRig
extends RefCounted

# One-time construction/wiring for the 3D cockpit screens (control panel, info
# screen, log screen, cockpit switches) and their SubViewport input forwarding.
# All state (viewports, meshes, materials) lives on the owning Main node and is
# passed in explicitly since these are RPC-adjacent scene objects, not owned by
# this helper.

static func setup_control_screen_display(main: Main) -> void:
	var ui_control: Node3D = main.get_node("UiControl")
	main._cs_viewport = SubViewport.new()
	main._cs_viewport.size = Vector2i(360, 460)
	main._cs_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	main._cs_viewport.transparent_bg = true
	main._cs_viewport.gui_disable_input = false
	ui_control.add_child(main._cs_viewport)

	main._cs_display = SupplyUI.new()
	main._cs_viewport.add_child(main._cs_display)

	var panel: Control = main._cs_display.get_child(0) as Control
	if panel:
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	main._cs_display.supply_changed.connect(main._on_supply_changed)
	main._cs_display.fuse_1to1_changed.connect(main._try_auto_end_turn)

	var screen_mesh: MeshInstance3D = ui_control.find_child("gs_ui_control_screen", true, false) as MeshInstance3D
	if screen_mesh:
		var aabb: AABB = screen_mesh.mesh.get_aabb()
		var shader: Shader = load("res://shaders/screen_display.gdshader") as Shader
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("viewport_tex", main._cs_viewport.get_texture())
		mat.set_shader_parameter("aabb_min", aabb.position)
		mat.set_shader_parameter("aabb_max", aabb.position + aabb.size)
		mat.set_shader_parameter("emission_strength", 1.3)
		mat.set_shader_parameter("scanline_count", 120.0)
		mat.set_shader_parameter("scanline_depth", 0.08)
		mat.set_shader_parameter("vignette_strength", 0.35)
		mat.set_shader_parameter("vignette_falloff", 3.0)
		screen_mesh.set_surface_override_material(0, mat)
		setup_screen_input(main, screen_mesh)

	var btn_callbacks: Array[Callable] = [main._on_research_pressed, main._on_pass_pressed, main._on_end_turn_pressed]
	var btn_tooltip_titles: Array[String] = ["Research", "Pass", "End Turn"]
	var btn_tooltip_descs: Array[String] = [
		"Discard a hand card and draw a replacement, once this Action is taken, you can only Research or Pass.",
		"End your turn. Once all players pass the Generation is over.",
		"Finish your turn manually, after buying or placing a card. Mostly automated",
	]
	for i: int in 3:
		var btn_mesh: MeshInstance3D = ui_control.find_child("gs_ui_control_button%d" % (i + 1), true, false) as MeshInstance3D
		if btn_mesh:
			setup_button_input(main, btn_mesh, btn_callbacks[i], btn_tooltip_titles[i], btn_tooltip_descs[i])
			if i == 2:
				main._end_turn_btn_mesh = btn_mesh

	main.get_node("UILayer/SupplyUI").hide()
	main.get_node("Board").set_supply_ui(main._cs_display)

static func setup_screen_input(main: Main, screen_mesh: MeshInstance3D) -> void:
	setup_viewport_input(main, screen_mesh, main._cs_viewport)

static func setup_button_input(main: Main, btn_mesh: MeshInstance3D, callback: Callable, tooltip_title: String = "", tooltip_desc: String = "") -> void:
	var area: Area3D = Area3D.new()
	area.input_ray_pickable = true
	btn_mesh.add_child(area)
	var cshape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	var aabb: AABB = btn_mesh.mesh.get_aabb()
	box.size = Vector3(aabb.size.x, aabb.size.y, aabb.size.z + 0.01)
	cshape.shape = box
	cshape.position = aabb.get_center()
	area.add_child(cshape)
	area.input_event.connect(func(_cam: Node, event: InputEvent, _pos: Vector3, _norm: Vector3, _idx: int) -> void:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				animate_button_press(main, btn_mesh)
				callback.call()
	)
	area.mouse_entered.connect(func() -> void:
		var base: Material = btn_mesh.mesh.surface_get_material(0)
		var mat: StandardMaterial3D = (base as StandardMaterial3D).duplicate() as StandardMaterial3D if base is StandardMaterial3D else StandardMaterial3D.new()
		mat.emission_enabled = true
		mat.emission = Color(0.8, 0.9, 1.0)
		mat.emission_energy_multiplier = 0.3
		btn_mesh.set_surface_override_material(0, mat)
		if not tooltip_title.is_empty():
			main._show_log_tooltip(tooltip_title, tooltip_desc)
	)
	area.mouse_exited.connect(func() -> void:
		if btn_mesh == main._end_turn_btn_mesh and main._end_turn_flash_mat != null:
			btn_mesh.set_surface_override_material(0, main._end_turn_flash_mat)
		else:
			btn_mesh.set_surface_override_material(0, null)
		main._hide_log_tooltip()
	)

static func animate_button_press(main: Main, btn_mesh: MeshInstance3D) -> void:
	var press_depth: float = btn_mesh.mesh.get_aabb().size.z * 0.35
	var rest_pos: Vector3 = btn_mesh.position
	var tween: Tween = main.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(btn_mesh, "position", rest_pos + Vector3(0.0, 0.0, -press_depth), 0.07)
	tween.tween_property(btn_mesh, "position", rest_pos, 0.14)

static func setup_cockpit_switches(main: Main) -> void:
	var ui_cockpit: Node3D = main.get_node("UiCockpit")
	var cockpit_anim: AnimationPlayer = ui_cockpit.find_child("AnimationPlayer", true, false) as AnimationPlayer

	var switch1: MeshInstance3D = ui_cockpit.find_child("gs_ui_switch_flat1", true, false) as MeshInstance3D
	if switch1:
		setup_switch_input(switch1, func() -> void:
			main._ui_control_shown = not main._ui_control_shown
			if cockpit_anim:
				if main._ui_control_shown:
					cockpit_anim.play_backwards("gs_ui_switch_flat1_on")
				else:
					cockpit_anim.play("gs_ui_switch_flat1_on")
			var ctrl_anim: AnimationPlayer = main.get_node("UiControl").find_child("AnimationPlayer", true, false) as AnimationPlayer
			if ctrl_anim:
				if main._ui_control_shown:
					ctrl_anim.play("intro")
				else:
					ctrl_anim.play_backwards("intro")
			var log_anim: AnimationPlayer = main.get_node("UiLog").find_child("AnimationPlayer", true, false) as AnimationPlayer
			if log_anim:
				if main._ui_control_shown:
					log_anim.play("intro")
				else:
					log_anim.play_backwards("intro")
		)

	var switch2: MeshInstance3D = ui_cockpit.find_child("gs_ui_switch_flat2", true, false) as MeshInstance3D
	if switch2:
		setup_switch_input(switch2, func() -> void:
			main._ui_info_shown = not main._ui_info_shown
			if cockpit_anim:
				if main._ui_info_shown:
					cockpit_anim.play_backwards("gs_ui_switch_flat2_on")
				else:
					cockpit_anim.play("gs_ui_switch_flat2_on")
			var anim: AnimationPlayer = main.get_node("UiInfo").find_child("AnimationPlayer", true, false) as AnimationPlayer
			if anim:
				if main._ui_info_shown:
					anim.play("intro")
				else:
					anim.play_backwards("intro")
		)

static func setup_switch_input(switch_mesh: MeshInstance3D, callback: Callable) -> void:
	var area: Area3D = Area3D.new()
	area.input_ray_pickable = true
	switch_mesh.add_child(area)
	var cshape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	var aabb: AABB = switch_mesh.mesh.get_aabb()
	box.size = Vector3(aabb.size.x, aabb.size.y, aabb.size.z + 0.01)
	cshape.shape = box
	cshape.position = aabb.get_center()
	area.add_child(cshape)
	area.input_event.connect(func(_cam: Node, event: InputEvent, _pos: Vector3, _norm: Vector3, _idx: int) -> void:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				callback.call()
	)

static func setup_viewport_input(main: Main, screen_mesh: MeshInstance3D, vp: SubViewport) -> void:
	var area: Area3D = Area3D.new()
	area.input_ray_pickable = true
	screen_mesh.add_child(area)
	var cshape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	var aabb: AABB = screen_mesh.mesh.get_aabb()
	box.size = Vector3(aabb.size.x, aabb.size.y, 0.002)
	cshape.shape = box
	cshape.position = aabb.get_center()
	area.add_child(cshape)
	area.input_event.connect(func(_cam: Node, event: InputEvent, pos: Vector3, _norm: Vector3, _idx: int) -> void:
		forward_to_viewport(main, event, pos, screen_mesh, vp)
	)
	area.mouse_exited.connect(func() -> void:
		if main._vp_button_held:
			return
		main._vp_prev_pos.erase(vp)
		var mm: InputEventMouseMotion = InputEventMouseMotion.new()
		mm.position = Vector2(-1.0, -1.0)
		vp.push_input(mm, true)
	)

static func forward_to_viewport(main: Main, event: InputEvent, world_pos: Vector3, mesh: MeshInstance3D, vp: SubViewport) -> void:
	var local_pos: Vector3 = mesh.to_local(world_pos)
	var aabb: AABB = mesh.mesh.get_aabb()
	var u: float = (local_pos.x - aabb.position.x) / aabb.size.x
	var v: float = 1.0 - (local_pos.y - aabb.position.y) / aabb.size.y
	var vp_pos: Vector2 = Vector2(u * float(vp.size.x), v * float(vp.size.y))
	if event is InputEventMouseButton:
		var src: InputEventMouseButton = event as InputEventMouseButton
		main._vp_button_held = src.pressed
		var mb: InputEventMouseButton = InputEventMouseButton.new()
		mb.button_index = src.button_index
		mb.pressed = src.pressed
		mb.button_mask = src.button_mask
		mb.position = vp_pos
		vp.push_input(mb, true)
	elif event is InputEventMouseMotion:
		var prev: Vector2 = main._vp_prev_pos.get(vp, vp_pos)
		main._vp_prev_pos[vp] = vp_pos
		var mm: InputEventMouseMotion = InputEventMouseMotion.new()
		mm.position = vp_pos
		mm.relative = vp_pos - prev
		vp.push_input(mm, true)

static func setup_info_screen_display(main: Main) -> void:
	main._info_viewport = SubViewport.new()
	main._info_viewport.size = Vector2i(1200, 572)
	main._info_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	main._info_viewport.transparent_bg = true
	main._info_viewport.gui_disable_input = false
	main.get_node("UiInfo").add_child(main._info_viewport)

	var info_bg: ColorRect = ColorRect.new()
	info_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	info_bg.color = Color(0.03, 0.04, 0.09, 0.93)
	info_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main._info_viewport.add_child(info_bg)

	main._market_panel = load("res://scenes/ui/market_panel.gd").new()
	main._info_viewport.add_child(main._market_panel)
	main._market_panel.scale = Vector2(1.68, 1.68)

	main._market_panel.sector_advanced_pressed.connect(main._on_market_sector_advanced_pressed)
	main._market_panel.sector_dust_pressed.connect(main._on_market_sector_dust_pressed)
	main._market_panel.expedition_pressed.connect(main._on_market_expedition_pressed)
	main._market_panel.opponent_pressed.connect(main._show_opponent_board)
	main._market_panel.card_hovered.connect(main._on_market_card_hovered)
	main._market_panel.card_unhovered.connect(main._on_market_card_unhovered)

	var screen_mesh: MeshInstance3D = main.get_node("UiInfo").find_child("gs_ui_info_screen", true, false) as MeshInstance3D
	if screen_mesh:
		main._info_screen_mesh = screen_mesh
		var aabb: AABB = screen_mesh.mesh.get_aabb()
		var shader: Shader = load("res://shaders/screen_display.gdshader") as Shader
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("viewport_tex", main._info_viewport.get_texture())
		mat.set_shader_parameter("aabb_min", aabb.position)
		mat.set_shader_parameter("aabb_max", aabb.position + aabb.size)
		mat.set_shader_parameter("emission_strength", 0.45)
		mat.set_shader_parameter("exposure", 0.6)
		mat.set_shader_parameter("scanline_count", 60.0)
		mat.set_shader_parameter("scanline_depth", 0.06)
		mat.set_shader_parameter("vignette_strength", 0.25)
		mat.set_shader_parameter("vignette_falloff", 2.5)
		mat.set_shader_parameter("bloom_threshold", 0.7)
		screen_mesh.set_surface_override_material(0, mat)
		setup_info_screen_input(main, screen_mesh)
	for p: Control in [main._bid_popup, main._payment_panel, main._scoreboard]:
		p.reparent(main._info_viewport, false)
		register_info_panel(main, p)

	var hint_root := Control.new()
	hint_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint_root.offset_bottom = 56.0
	hint_root.z_index = 10
	hint_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hint_bg := ColorRect.new()
	hint_bg.color = Color(0.03, 0.04, 0.09, 0.92)
	hint_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_root.add_child(hint_bg)
	var hint_border := ColorRect.new()
	hint_border.color = Color(0.3, 0.6, 1.0, 0.55)
	hint_border.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint_border.offset_top = -2.0
	hint_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_root.add_child(hint_border)
	var hint_label := Label.new()
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 22)
	hint_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	hint_label.add_theme_constant_override("outline_size", 2)
	hint_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_root.add_child(hint_label)
	main._effect_hint_panel = hint_root
	main._effect_hint_label = hint_label
	main._effect_hint_panel.hide()
	main._info_viewport.add_child(hint_root)

static func setup_info_screen_input(main: Main, screen_mesh: MeshInstance3D) -> void:
	setup_viewport_input(main, screen_mesh, main._info_viewport)

static func effect_card_origin(main: Main, card_node: Node3D, cd: CardData) -> Vector3:
	if not main._market_panel:
		return main.get_node("UiInfo").global_position
	var slot_idx: int = card_node.get_meta("market_slot", 0)
	var slot_type: String
	if cd.card_type == CardData.CardType.EXPEDITION:
		slot_type = "expedition"
	elif bool(card_node.get("is_advanced")):
		slot_type = "advanced"
	else:
		slot_type = "dust"
	return viewport_to_world(main, main._market_panel.get_slot_center(slot_type, slot_idx))

static func viewport_to_world(main: Main, vp_pos: Vector2) -> Vector3:
	if not main._info_screen_mesh:
		return main.get_node("UiInfo").global_position
	var aabb: AABB = main._info_screen_mesh.mesh.get_aabb()
	var u: float = vp_pos.x / float(main._info_viewport.size.x)
	var v: float = vp_pos.y / float(main._info_viewport.size.y)
	var local_x: float = u * aabb.size.x + aabb.position.x
	var local_y: float = (1.0 - v) * aabb.size.y + aabb.position.y
	return main._info_screen_mesh.to_global(Vector3(local_x, local_y, 0.0))

static func register_info_panel(main: Main, panel: Control) -> void:
	main._info_panels.append(panel)
	panel.visibility_changed.connect(func() -> void:
		if not main._market_panel:
			return
		if panel.visible:
			main._market_panel.visible = false
		else:
			var any_active: bool = false
			for p: Control in main._info_panels:
				if p != panel and p.is_inside_tree() and p.visible:
					any_active = true
					break
			main._market_panel.visible = not any_active
	)

static func setup_log_screen_display(main: Main) -> void:
	var myriad: FontFile = load("res://assets/fonts/Myriad Variable Concept.ttf") as FontFile
	if myriad:
		main._log_font = FontVariation.new()
		main._log_font.base_font = myriad
		main._log_font.variation_opentype = {"wght": 500}

	main._log_viewport = SubViewport.new()
	# 686×408 viewport: 686 = 980 × 0.7 compensates for UiLog non-uniform world scale
	# so all content pixels are square in world space without per-element correction.
	# Canvas is portrait (408×686) rotated 90° CW to fill the landscape viewport.
	main._log_viewport.size = Vector2i(686, 408)
	main._log_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	main._log_viewport.transparent_bg = true
	main._log_viewport.gui_disable_input = false
	main.get_node("UiLog").add_child(main._log_viewport)

	var canvas: Control = Control.new()
	canvas.size = Vector2(408.0, 686.0)
	canvas.rotation_degrees = 90.0
	canvas.position = Vector2(686.0, 0.0)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main._log_viewport.add_child(canvas)
	main._log_canvas = canvas

	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.09, 0.93)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(bg)

	var header: Label = Label.new()
	header.text = "Event Log"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 24)
	header.add_theme_color_override("font_color", Color(0.65, 0.80, 1.0))
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_top = 12.0
	header.offset_bottom = 64.0
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(header)

	var sep: ColorRect = ColorRect.new()
	sep.color = Color(0.25, 0.45, 0.80, 0.5)
	sep.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	sep.offset_top = 64.0
	sep.offset_bottom = 66.0
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(sep)

	main._log_scroll = ScrollContainer.new()
	main._log_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main._log_scroll.offset_top = 68.0
	main._log_scroll.follow_focus = false
	main._log_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(main._log_scroll)

	main._log_vbox = VBoxContainer.new()
	main._log_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main._log_vbox.add_theme_constant_override("separation", 2)
	main._log_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main._log_scroll.add_child(main._log_vbox)

	var screen_mesh: MeshInstance3D = main.get_node("UiLog").find_child("gs_ui_log_screen", true, false) as MeshInstance3D
	if screen_mesh:
		var aabb: AABB = screen_mesh.mesh.get_aabb()
		var shader: Shader = load("res://shaders/screen_display.gdshader") as Shader
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("viewport_tex", main._log_viewport.get_texture())
		mat.set_shader_parameter("aabb_min", aabb.position)
		mat.set_shader_parameter("aabb_max", aabb.position + aabb.size)
		mat.set_shader_parameter("emission_strength", 0.45)
		mat.set_shader_parameter("exposure", 0.6)
		mat.set_shader_parameter("scanline_count", 80.0)
		mat.set_shader_parameter("scanline_depth", 0.05)
		mat.set_shader_parameter("vignette_strength", 0.2)
		mat.set_shader_parameter("vignette_falloff", 2.5)
		mat.set_shader_parameter("bloom_threshold", 0.7)
		screen_mesh.set_surface_override_material(0, mat)
		setup_viewport_input(main, screen_mesh, main._log_viewport)

	# Preview panel – hidden until hover. Size is set in _on_market_card_hovered.
	var preview_wrap: Control = Control.new()
	preview_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_wrap.visible = false
	main._log_canvas.add_child(preview_wrap)
	main._log_preview_panel = preview_wrap

	var pp: PanelContainer = PanelContainer.new()
	var preview_style: StyleBoxFlat = StyleBoxFlat.new()
	preview_style.bg_color = Color(0.04, 0.04, 0.09, 0.97)
	preview_style.border_color = Color(0.3, 0.55, 0.85, 0.55)
	preview_style.set_border_width_all(1)
	preview_style.set_corner_radius_all(6)
	pp.add_theme_stylebox_override("panel", preview_style)
	pp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_wrap.add_child(pp)
	pp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	main._log_preview_image = TextureRect.new()
	main._log_preview_image.stretch_mode = TextureRect.STRETCH_SCALE
	main._log_preview_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	main._log_preview_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var preview_mat: ShaderMaterial = ShaderMaterial.new()
	preview_mat.shader = load("res://shaders/card_rounded.gdshader")
	main._log_preview_image.material = preview_mat
	preview_wrap.add_child(main._log_preview_image)

	var lt_panel: PanelContainer = PanelContainer.new()
	lt_panel.visible = false
	lt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lt_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lt_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	lt_panel.scale = Vector2(1.5, 1.5)
	lt_panel.resized.connect(func() -> void: lt_panel.pivot_offset = lt_panel.size / 2.0)
	var lt_style: StyleBoxFlat = StyleBoxFlat.new()
	lt_style.bg_color = Color(0.05, 0.07, 0.15, 0.94)
	lt_style.border_color = Color(0.3, 0.55, 0.85, 0.55)
	lt_style.set_border_width_all(1)
	lt_style.set_corner_radius_all(4)
	lt_style.content_margin_left = 12.0
	lt_style.content_margin_right = 12.0
	lt_style.content_margin_top = 8.0
	lt_style.content_margin_bottom = 8.0
	lt_panel.add_theme_stylebox_override("panel", lt_style)
	var lt_vbox: VBoxContainer = VBoxContainer.new()
	lt_vbox.add_theme_constant_override("separation", 3)
	lt_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lt_panel.add_child(lt_vbox)
	main._log_tooltip_title = Label.new()
	main._log_tooltip_title.add_theme_font_size_override("font_size", 20)
	main._log_tooltip_title.add_theme_color_override("font_color", Color(0.82, 0.93, 1.0))
	main._log_tooltip_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main._log_tooltip_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lt_vbox.add_child(main._log_tooltip_title)
	main._log_tooltip_desc = Label.new()
	main._log_tooltip_desc.add_theme_font_size_override("font_size", 20)
	main._log_tooltip_desc.add_theme_color_override("font_color", Color(0.60, 0.68, 0.82))
	main._log_tooltip_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main._log_tooltip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	main._log_tooltip_desc.custom_minimum_size = Vector2(230, 0)
	main._log_tooltip_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lt_vbox.add_child(main._log_tooltip_desc)
	main._log_canvas.add_child(lt_panel)
	main._log_tooltip_panel = lt_panel

static func start_rumble_timer(main: Main) -> void:
	main.get_tree().create_timer(randf_range(30.0, 60.0)).timeout.connect(func() -> void: play_rumble(main))

static func play_rumble(main: Main) -> void:
	const JOLT_SEC: float = 0.10
	const JOLT_COUNT: int = 15  # 15 × 0.10 s = 1.5 s
	var ui_cockpit: Node3D = main.get_node("UiCockpit")
	var targets: Array[Node3D] = [ui_cockpit, main.get_node("UiControl"), main.get_node("UiInfo"), main.get_node("UiLog")]
	for slot: SectorSlot in main.get_node("Board").get_all_sector_slots():
		targets.append(slot)
	for node: Node3D in targets:
		var tw: Tween = main._rumble_tweens.get(node) as Tween
		if tw and tw.is_valid():
			tw.kill()
		tw = main.create_tween()
		main._rumble_tweens[node] = tw
		var base_pos: Vector3 = main._rumble_base_pos.get(node, node.position)
		var base_rot: Vector3 = main._rumble_base_rot.get(node, node.rotation)
		for _i: int in JOLT_COUNT:
			var dp: Vector3 = Vector3(randf_range(-0.003, 0.003), randf_range(-0.0015, 0.0015), randf_range(-0.0024, 0.0024))
			var dr: Vector3 = base_rot + Vector3(randf_range(-0.0015, 0.0015), randf_range(-0.0009, 0.0009), randf_range(-0.0015, 0.0015))
			tw.tween_property(node, "position", base_pos + dp, JOLT_SEC).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			tw.parallel().tween_property(node, "rotation", dr, JOLT_SEC).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(node, "position", base_pos, 0.40).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.parallel().tween_property(node, "rotation", base_rot, 0.40).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	main._rumble_tweens[ui_cockpit].tween_callback(func() -> void: start_rumble_timer(main))
