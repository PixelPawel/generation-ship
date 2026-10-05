class_name CockpitRig
extends RefCounted

const LongPressGestureScript := preload("res://scenes/ui/long_press_gesture.gd")

# One-time construction/wiring for the 3D cockpit screens (control panel, info
# screen, log screen, cockpit switches) and their SubViewport input forwarding.
# All state (viewports, meshes, materials) lives on the owning Main node and is
# passed in explicitly since these are RPC-adjacent scene objects, not owned by
# this helper.

static func setup_control_screen_display(main: Main) -> void:
	var ui_control: Node3D = main.get_node("UiControl")
	main.cs_viewport = SubViewport.new()
	main.cs_viewport.size = Vector2i(360, 460)
	main.cs_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	main.cs_viewport.transparent_bg = true
	main.cs_viewport.gui_disable_input = false
	ui_control.add_child(main.cs_viewport)

	main._cs_display = SupplyUI.new()
	main.cs_viewport.add_child(main._cs_display)

	var panel: Control = main._cs_display.get_child(0) as Control
	if panel:
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	main._cs_display.supply_changed.connect(main._on_supply_changed)
	main._cs_display.fuse_1to1_changed.connect(main._try_auto_end_turn)
	main._cs_display.icon_hovered.connect(main._on_supply_icon_hovered)
	main._cs_display.icon_unhovered.connect(main._hide_tooltip)

	var screen_mesh: MeshInstance3D = ui_control.find_child("gs_ui_control_screen", true, false) as MeshInstance3D
	if screen_mesh:
		var aabb: AABB = screen_mesh.mesh.get_aabb()
		var shader: Shader = load("res://shaders/screen_display.gdshader") as Shader
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("viewport_tex", main.cs_viewport.get_texture())
		mat.set_shader_parameter("aabb_min", aabb.position)
		mat.set_shader_parameter("aabb_max", aabb.position + aabb.size)
		mat.set_shader_parameter("emission_strength", 1.3)
		mat.set_shader_parameter("scanline_count", 120.0)
		mat.set_shader_parameter("scanline_depth", 0.08)
		mat.set_shader_parameter("vignette_strength", 0.35)
		mat.set_shader_parameter("vignette_falloff", 3.0)
		screen_mesh.set_surface_override_material(0, mat)
		setup_screen_input(main, screen_mesh)
		main.get_node("Board").set_control_screen_mesh(screen_mesh)

	var btn_callbacks: Array[Callable] = [main._on_research_pressed, main._on_pass_pressed, main._on_end_turn_button_pressed]
	var btn_tooltip_titles: Array[String] = [main.tr("Research"), main.tr("Pass"), main.tr("End Turn")]
	var btn_tooltip_descs: Array[String] = [
		main.tr("Discard a hand card and draw a replacement, once this Action is taken, you can only Research or Pass."),
		main.tr("End your turn. Once all players pass the Generation is over."),
		main.tr("Finish your turn manually, after buying or placing a card. Mostly automated"),
	]
	for i: int in 3:
		var btn_mesh: MeshInstance3D = ui_control.find_child("gs_ui_control_button%d" % (i + 1), true, false) as MeshInstance3D
		if btn_mesh:
			setup_button_input(main, btn_mesh, btn_callbacks[i], btn_tooltip_titles[i], btn_tooltip_descs[i])
			if i == 0:
				main._research_btn_mesh = btn_mesh
			if i == 1:
				main._pass_btn_mesh = btn_mesh
			if i == 2:
				main._end_turn_btn_mesh = btn_mesh

	main.get_node("UILayer/SupplyUI").hide()
	main.get_node("Board").set_supply_ui(main._cs_display)

static func setup_screen_input(main: Main, screen_mesh: MeshInstance3D) -> void:
	setup_viewport_input(main, screen_mesh, main.cs_viewport)

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
			main._show_tooltip(tooltip_title, tooltip_desc)
	)
	area.mouse_exited.connect(func() -> void:
		var flash_mat: StandardMaterial3D = null
		if btn_mesh == main._end_turn_btn_mesh:
			flash_mat = main._end_turn_flash_mat
		elif btn_mesh == main._pass_btn_mesh:
			flash_mat = main._pass_btn_flash_mat
		elif btn_mesh == main._research_btn_mesh:
			flash_mat = main._research_btn_flash_mat
		if flash_mat != null:
			btn_mesh.set_surface_override_material(0, flash_mat)
		else:
			btn_mesh.set_surface_override_material(0, null)
		main._hide_tooltip()
	)

static func animate_button_press(main: Main, btn_mesh: MeshInstance3D) -> void:
	var press_depth: float = btn_mesh.mesh.get_aabb().size.z * 0.35
	# Rest position is captured once: reading btn_mesh.position on every press
	# picked up the half-pressed position during rapid clicks, so the button
	# sank a little deeper each time and never came back up.
	if not btn_mesh.has_meta("rest_pos"):
		btn_mesh.set_meta("rest_pos", btn_mesh.position)
	var rest_pos: Vector3 = btn_mesh.get_meta("rest_pos")
	# has_meta first: get_meta() with a null default still errors when unset.
	if btn_mesh.has_meta("press_tween"):
		var prev: Tween = btn_mesh.get_meta("press_tween") as Tween
		if prev and prev.is_valid():
			prev.kill()
	btn_mesh.position = rest_pos
	var tween: Tween = main.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	btn_mesh.set_meta("press_tween", tween)
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

const SCREEN_ENLARGE_DIST: float = 0.115
const SCREEN_ENLARGE_IN_SEC: float = 0.25
const SCREEN_ENLARGE_OUT_SEC: float = 0.40
const SCREEN_DUCK_SLIDE_Z: float = 0.20
const SCREEN_DUCK_IN_SEC: float = 0.30
const SCREEN_DUCK_OUT_SEC: float = 0.45
const CARD_ELEVATION_IGNORE_WINDOW_MS: int = 50

# The cockpit's control/info(market)/log screens were laid out by eye against
# a 16:9 monitor. Camera3D defaults to KEEP_HEIGHT, so a wider aspect ratio
# (e.g. a phone in landscape) keeps the same vertical framing but reveals
# extra horizontal FOV beyond what the cockpit fills, leaving empty space to
# both sides. setup_responsive_screen_positions() keeps each screen's
# horizontal on-screen position pinned to whatever fraction of the frame it
# occupies at that reference 16:9 aspect, sliding it outward/inward along the
# camera's local right axis as the real aspect ratio changes. Recomputed from
# each screen's ORIGINAL authored position every time the viewport resizes,
# never incrementally, so repeated resizes/rotations can't compound drift.
const SCREEN_LAYOUT_REFERENCE_ASPECT: float = 16.0 / 9.0
# Aspect ratio at which the grow/lift boost below reaches its maximum -- 2.0
# (18:9) is a common, not especially extreme, phone landscape ratio, so most
# phones sit at or past full boost rather than only partway up the ramp.
const SCREEN_LAYOUT_MAX_ASPECT: float = 2.0
# Control and market only (log excluded per explicit request) get bigger and
# shifted a bit as the aspect ratio widens past the reference, since a
# phone's extra revealed width otherwise just sits unused beside them -- 0
# boost at the reference aspect (desktop, unchanged), ramping linearly to
# each screen's own cap at SCREEN_LAYOUT_MAX_ASPECT. Started as one shared
# scale/lift pair (1.3x/0.08 read as no change; 1.75x/0.16, after fixing the
# pivot bug below, read as too big/close; 1.45x/0.1 still too big; 1.35x/0.1
# closer but a phone screenshot showed both screens' top row clipping off
# the top edge) -- split per-screen once a second screenshot showed control
# and market don't actually need the same treatment: control reads right at
# 1.25x but was still clipping its header, needing a nudge DOWN rather than
# up; market's base mesh is larger than control's, so the same multiplier
# oversizes it more in absolute terms and it needs a smaller boost. Each
# screen can also get an extra_shift_x (beyond the aspect-fill delta, e.g.
# to pull market further from control, or push log clear of control once
# control grew bigger) and its own lift -- all ramped in by boost_t so
# desktop (reference aspect) is always untouched.
const SCREEN_LAYOUT_CONTROL_MAX_SCALE_BOOST: float = 1.725
const SCREEN_LAYOUT_CONTROL_MAX_LIFT: float = -0.42
const SCREEN_LAYOUT_CONTROL_MAX_SHIFT_X: float = -0.36
# Growing/shifting control this far made it overlap a fixed cockpit console
# strut that sits at roughly the same depth, so it started clipping through
# instead of appearing over it -- pulling it toward the camera (reducing its
# depth) puts it unambiguously in front instead of backing off position.
const SCREEN_LAYOUT_CONTROL_MAX_SHIFT_TOWARD_CAMERA: float = 0.15
const SCREEN_LAYOUT_MARKET_MAX_SCALE_BOOST: float = 1.12
const SCREEN_LAYOUT_MARKET_MAX_LIFT: float = -0.04
const SCREEN_LAYOUT_MARKET_MAX_SHIFT_X: float = -0.06
const SCREEN_LAYOUT_MARKET_MAX_SHIFT_TOWARD_CAMERA: float = 0.0
const SCREEN_LAYOUT_LOG_MAX_SCALE_BOOST: float = 1.0
const SCREEN_LAYOUT_LOG_MAX_LIFT: float = 0.0
const SCREEN_LAYOUT_LOG_MAX_SHIFT_X: float = 0.07
const SCREEN_LAYOUT_LOG_MAX_SHIFT_TOWARD_CAMERA: float = 0.0

static func setup_responsive_screen_positions(main: Main) -> void:
	var cam: Camera3D = main.get_node("Camera3D")
	var cam_inv: Transform3D = cam.global_transform.affine_inverse()

	# All three screens go through the same mesh-center-anchored mechanism
	# now (log included, at scale_boost 1.0 -- a no-op for its scale, but it
	# still benefits from the shared extra_shift_x/lift support). Anchored on
	# the actual SCREEN MESH's own AABB-center global position, not the
	# prop's root origin -- the root's pivot isn't necessarily centered on
	# the visible screen, so scaling the root about its own origin drags the
	# visible screen's apparent position along with it (toward or away from
	# center depending on which side of the mesh the pivot sits), silently
	# fighting the horizontal-fill effect. Tracking the mesh's own center and
	# solving for whatever root position puts that center where it should be
	# keeps the two effects independent.
	var screen_defs: Array[Dictionary] = [
		{
			"root": main.get_node("UiControl"), "mesh_name": "gs_ui_control_screen",
			"max_scale_boost": SCREEN_LAYOUT_CONTROL_MAX_SCALE_BOOST,
			"max_lift": SCREEN_LAYOUT_CONTROL_MAX_LIFT,
			"max_shift_x": SCREEN_LAYOUT_CONTROL_MAX_SHIFT_X,
			"max_shift_toward_camera": SCREEN_LAYOUT_CONTROL_MAX_SHIFT_TOWARD_CAMERA,
		},
		{
			"root": main.get_node("UiInfo"), "mesh_name": "gs_ui_info_screen",
			"max_scale_boost": SCREEN_LAYOUT_MARKET_MAX_SCALE_BOOST,
			"max_lift": SCREEN_LAYOUT_MARKET_MAX_LIFT,
			"max_shift_x": SCREEN_LAYOUT_MARKET_MAX_SHIFT_X,
			"max_shift_toward_camera": SCREEN_LAYOUT_MARKET_MAX_SHIFT_TOWARD_CAMERA,
		},
		{
			"root": main.get_node("UiLog"), "mesh_name": "gs_ui_log_screen",
			"max_scale_boost": SCREEN_LAYOUT_LOG_MAX_SCALE_BOOST,
			"max_lift": SCREEN_LAYOUT_LOG_MAX_LIFT,
			"max_shift_x": SCREEN_LAYOUT_LOG_MAX_SHIFT_X,
			"max_shift_toward_camera": SCREEN_LAYOUT_LOG_MAX_SHIFT_TOWARD_CAMERA,
		},
	]
	var baselines: Array[Dictionary] = []
	for def: Dictionary in screen_defs:
		var node: Node3D = def["root"]
		var mesh: MeshInstance3D = node.find_child(def["mesh_name"], true, false) as MeshInstance3D
		var mesh_center: Vector3 = mesh.to_global(mesh.mesh.get_aabb().get_center()) if mesh else node.global_position
		var root_original: Vector3 = node.global_position
		var local0: Vector3 = cam_inv * mesh_center
		baselines.append({
			"node": node,
			"mesh_center_original": mesh_center,
			"root_offset0": root_original - mesh_center,
			"local_x": local0.x,
			"depth": -local0.z,
			"original_scale": node.scale,
			"max_scale_boost": def["max_scale_boost"],
			"max_lift": def["max_lift"],
			"max_shift_x": def["max_shift_x"],
			"max_shift_toward_camera": def["max_shift_toward_camera"],
		})

	var reposition := func() -> void:
		var vp_size: Vector2 = main.get_viewport().get_visible_rect().size
		if vp_size.x <= 0.0 or vp_size.y <= 0.0:
			return
		var cur_aspect: float = vp_size.x / vp_size.y
		var half_vfov: float = deg_to_rad(cam.fov) * 0.5
		var half_hfov_ref: float = atan(tan(half_vfov) * SCREEN_LAYOUT_REFERENCE_ASPECT)
		var half_hfov_cur: float = atan(tan(half_vfov) * cur_aspect)
		var boost_t: float = clampf(
			(cur_aspect - SCREEN_LAYOUT_REFERENCE_ASPECT) / (SCREEN_LAYOUT_MAX_ASPECT - SCREEN_LAYOUT_REFERENCE_ASPECT),
			0.0, 1.0
		)

		for b: Dictionary in baselines:
			var depth: float = b["depth"]
			var ndc_x_ref: float = b["local_x"] / (depth * tan(half_hfov_ref))
			var target_local_x: float = ndc_x_ref * depth * tan(half_hfov_cur)
			var delta_local_x: float = target_local_x - b["local_x"] + b["max_shift_x"] * boost_t
			var scale_factor: float = lerpf(1.0, b["max_scale_boost"], boost_t)
			var lift: float = b["max_lift"] * boost_t
			var toward_camera: float = b["max_shift_toward_camera"] * boost_t
			var target_mesh_center: Vector3 = (
				b["mesh_center_original"]
				+ cam.global_transform.basis.x * delta_local_x
				+ Vector3(0.0, lift, 0.0)
				+ cam.global_transform.basis.z * toward_camera
			)
			var node: Node3D = b["node"]
			node.scale = b["original_scale"] * scale_factor
			node.global_position = target_mesh_center + b["root_offset0"] * scale_factor
			# Phones: the control screen rests where a right-click/long-press
			# enlarge would put it on desktop (same direction and distance as
			# _enlarge_screen), so it's readable by default — enlarging still
			# pulls it one step further from there.
			if node == main.get_node("UiControl") and OS.has_feature("mobile"):
				var pull: Vector3 = (cam.global_position - node.global_position).normalized()
				pull.x *= 0.5
				node.global_position += pull * SCREEN_ENLARGE_DIST

	main.get_viewport().size_changed.connect(reposition)
	reposition.call()

# Right-click toggle that pulls a cockpit screen (control/info/log) closer to
# the camera — brought back from an earlier hover-triggered version of this
# same effect (removed because hover was the wrong trigger); the tween
# tuning and the "duck" side effect (sliding a sector's tech cards back so
# an enlarged screen doesn't clip through them) are unchanged from that
# version, only the trigger changed from hover to a right-click toggle.
static func setup_screen_enlarge(main: Main) -> void:
	var nodes: Array[Node3D] = [main.get_node("UiControl"), main.get_node("UiInfo"), main.get_node("UiLog")]
	var names: Array[String] = ["gs_ui_control_screen", "gs_ui_info_screen", "gs_ui_log_screen"]
	for i: int in nodes.size():
		var node: Node3D = nodes[i]
		main.screen_enlarge_base_pos[node] = node.position
		var mesh: MeshInstance3D = node.find_child(names[i], true, false) as MeshInstance3D
		if not mesh:
			continue
		var area: Area3D = null
		for child: Node in mesh.get_children():
			if child is Area3D:
				area = child as Area3D
				break
		if not area:
			area = Area3D.new()
			area.input_ray_pickable = true
			var cshape: CollisionShape3D = CollisionShape3D.new()
			var box: BoxShape3D = BoxShape3D.new()
			var aabb: AABB = mesh.mesh.get_aabb()
			box.size = Vector3(aabb.size.x, aabb.size.y, 0.01)
			cshape.shape = box
			cshape.position = aabb.get_center()
			area.add_child(cshape)
			mesh.add_child(area)
		var gesture := LongPressGestureScript.new()
		area.input_event.connect(func(_cam: Node, event: InputEvent, _pos: Vector3, _norm: Vector3, _idx: int) -> void:
			if event is InputEventMouseButton:
				var mb: InputEventMouseButton = event as InputEventMouseButton
				if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
					# A placed card sitting near/behind the screen from the
					# camera's angle can be hit by the same ray, so its own
					# right-click-to-elevate toggle may fire alongside this
					# one. Deferring lets that toggle's signal (if any) land
					# first regardless of dispatch order, so the timestamp
					# check below sees it before deciding whether to act.
					(func() -> void:
						if Time.get_ticks_msec() - main._last_card_elevation_toggle_ms > CARD_ELEVATION_IGNORE_WINDOW_MS:
							_toggle_screen_enlarge(main, node)
					).call_deferred()
				elif mb.button_index == MOUSE_BUTTON_LEFT:
					# Touch has no right-click — long-press is its equivalent
					# here (this area has no competing left-click action of
					# its own to conflict with).
					if mb.pressed:
						gesture.begin(main.get_tree(), mb.position, func() -> void:
							if Time.get_ticks_msec() - main._last_card_elevation_toggle_ms > CARD_ELEVATION_IGNORE_WINDOW_MS:
								_toggle_screen_enlarge(main, node))
					else:
						gesture.end()
			elif event is InputEventMouseMotion:
				gesture.update_position((event as InputEventMouseMotion).position)
		)
		area.mouse_entered.connect(func() -> void:
			if main._tutorial != null and is_instance_valid(main._tutorial):
				return   # the tutorial teaches this itself, on its banner
			main._show_tooltip("", main.hint("Right-click to enlarge/shrink this screen.",
					"Tap and hold to enlarge/shrink this screen."))
		)
		area.mouse_exited.connect(func() -> void:
			main._hide_tooltip()
		)

# The tutorial's zoom: no sliding the sector cards out of the way (the
# control screen sits in its corner, clear of them) — that slide had left a
# placed card stuck up out of place.
static func set_screen_enlarged(main: Main, node: Node3D, on: bool) -> void:
	if bool(main.screen_enlarged.get(node, false)) == on:
		return
	main.screen_enlarged[node] = on
	if on:
		_enlarge_screen(main, node, false)
	else:
		_shrink_screen(main, node)

# A quick wobble to catch the eye (the tutorial nudging the player).
static func shake_screen(main: Main, node: Node3D) -> void:
	var rest: Vector3 = node.rotation
	var tw: Tween = main.create_tween()
	for i: int in 6:
		var a: float = deg_to_rad(2.5) * (1.0 if i % 2 == 0 else -1.0) * (1.0 - float(i) / 6.0)
		tw.tween_property(node, "rotation:z", rest.z + a, 0.06)
	tw.tween_property(node, "rotation", rest, 0.06)

static func _toggle_screen_enlarge(main: Main, node: Node3D) -> void:
	if main.screen_enlarged.get(node, false):
		main.screen_enlarged[node] = false
		_shrink_screen(main, node)
	else:
		main.screen_enlarged[node] = true
		_enlarge_screen(main, node)

static func _enlarge_screen(main: Main, node: Node3D, duck: bool = true) -> void:
	var tw: Tween = main.screen_enlarge_tweens.get(node) as Tween
	if tw and tw.is_valid():
		tw.kill()
	var base: Vector3 = main.screen_enlarge_base_pos[node]
	var dir: Vector3 = (main.get_node("Camera3D").global_position - node.global_position).normalized()
	dir.x *= 0.5
	tw = main.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(node, "position", base + dir * SCREEN_ENLARGE_DIST, SCREEN_ENLARGE_IN_SEC)
	main.screen_enlarge_tweens[node] = tw
	if not duck:
		main.screen_ducked_slots[node] = [] as Array[SectorSlot]
		return

	var ducked: Array[SectorSlot] = []
	for slot: SectorSlot in main.get_node("Board").get_all_sector_slots():
		if not slot.occupied:
			continue
		var tech_cards: Array[Node3D] = []
		for card: Node3D in slot.get_all_placed_cards():
			if card != slot.placed_card:
				tech_cards.append(card)
		if tech_cards.is_empty():
			continue
		var dtw: Tween = main.screen_duck_tweens.get(slot) as Tween
		if dtw and dtw.is_valid():
			dtw.kill()
		dtw = main.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		var first: bool = true
		for card: Node3D in tech_cards:
			if card not in main.screen_duck_card_pos:
				main.screen_duck_card_pos[card] = card.position
			var slot_idx: int = card.get_parent().get("slot_index") as int
			var slide_pos: Vector3 = main.screen_duck_card_pos[card] + Vector3(0.0, 0.0, SCREEN_DUCK_SLIDE_Z * float(slot_idx + 1))
			if first:
				dtw.tween_property(card, "position", slide_pos, SCREEN_DUCK_IN_SEC)
				first = false
			else:
				dtw.parallel().tween_property(card, "position", slide_pos, SCREEN_DUCK_IN_SEC)
		main.screen_duck_tweens[slot] = dtw
		ducked.append(slot)
	main.screen_ducked_slots[node] = ducked

static func _shrink_screen(main: Main, node: Node3D) -> void:
	var tw: Tween = main.screen_enlarge_tweens.get(node) as Tween
	if tw and tw.is_valid():
		tw.kill()
	tw = main.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(node, "position", main.screen_enlarge_base_pos[node], SCREEN_ENLARGE_OUT_SEC)
	main.screen_enlarge_tweens[node] = tw
	var slots: Array = main.screen_ducked_slots.get(node, [] as Array)
	for slot: SectorSlot in slots:
		var dtw: Tween = main.screen_duck_tweens.get(slot) as Tween
		if dtw and dtw.is_valid():
			dtw.kill()
		var tech_cards: Array[Node3D] = []
		for card: Node3D in slot.get_all_placed_cards():
			if card != slot.placed_card:
				tech_cards.append(card)
		if tech_cards.is_empty():
			main.screen_duck_tweens.erase(slot)
			continue
		dtw = main.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		var first: bool = true
		for card: Node3D in tech_cards:
			var rest_pos: Vector3 = main.screen_duck_card_pos.get(card, card.position)
			if first:
				dtw.tween_property(card, "position", rest_pos, SCREEN_DUCK_OUT_SEC)
				first = false
			else:
				dtw.parallel().tween_property(card, "position", rest_pos, SCREEN_DUCK_OUT_SEC)
		dtw.tween_callback(func() -> void:
			for card: Node3D in tech_cards:
				main.screen_duck_card_pos.erase(card))
		main.screen_duck_tweens[slot] = dtw
	main.screen_ducked_slots.erase(node)

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
		if main.vp_button_held:
			return
		main.vp_prev_pos.erase(vp)
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
		main.vp_button_held = src.pressed
		var mb: InputEventMouseButton = InputEventMouseButton.new()
		mb.button_index = src.button_index
		mb.pressed = src.pressed
		mb.button_mask = src.button_mask
		mb.position = vp_pos
		vp.push_input(mb, true)
	elif event is InputEventMouseMotion:
		var prev: Vector2 = main.vp_prev_pos.get(vp, vp_pos)
		main.vp_prev_pos[vp] = vp_pos
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
	# Phones: every button that ever appears on the info screen (panels build some
	# of theirs later, e.g. the payment steppers) gets bigger — deferred, so the
	# panel has set its own size and font first.
	if GameTheme.is_touch():
		var vp: SubViewport = main._info_viewport
		main.get_tree().node_added.connect(func(n: Node) -> void:
			if n is Button and is_instance_valid(vp) and vp.is_ancestor_of(n):
				GameTheme.enlarge_info_button.call_deferred(n as Button))

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
	main._market_panel.opponent_pressed.connect(func(peer_id: int) -> void: OpponentBoardView.show_opponent_board(main, peer_id))
	main._market_panel.card_inspect_requested.connect(main._on_market_card_inspect_requested)
	main._market_panel.card_hover_started.connect(main._on_market_card_hover_started)
	main._market_panel.card_hover_ended.connect(main._hide_tooltip)
	main._market_panel.opponent_hover_started.connect(func(player_name: String) -> void: main._show_tooltip("", main.hint("Click to view %s's board.", "Tap to view %s's board.") % player_name))
	main._market_panel.opponent_hover_ended.connect(main._hide_tooltip)

	var screen_mesh: MeshInstance3D = main.get_node("UiInfo").find_child("gs_ui_info_screen", true, false) as MeshInstance3D
	if screen_mesh:
		main._info_screen_mesh = screen_mesh
		# Placed cards (hand or market) fly in from the payment/info screen.
		main.get_node("Board").placement_origin_provider = func() -> Vector3:
			return screen_mesh.to_global(screen_mesh.mesh.get_aabb().get_center())
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
	# BidPopup deliberately does NOT register here — it stays confined to the
	# left ~58% of the info screen (see bid_popup.gd) so the market panel's
	# Players column (opponent supply/hand/VP + live auction status) keeps
	# showing through on the right instead of being auto-hidden along with
	# the rest of the market panel the way every other info panel behaves.
	main._bid_popup.reparent(main._info_viewport, false)
	main._scoreboard.reparent(main._info_viewport, false)
	register_info_panel(main, main._scoreboard)

	# Free-floating, screen-space (not on the in-world Info Screen) so it
	# reads clearly regardless of camera angle — centered on the actual
	# game window via the shared ScifiPanel frame used by every other
	# floating popup in the game.
	var hint_panel: Control = load("res://scenes/ui/scifi_panel.gd").new()
	hint_panel.set_content_margin(16)
	hint_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	hint_panel.custom_minimum_size = Vector2(640, 90)
	hint_panel.z_index = 10
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hint_label := Label.new()
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint_label.add_theme_font_size_override("font_size", 22)
	hint_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	hint_label.add_theme_constant_override("outline_size", 2)
	hint_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.add_child(hint_label)
	main._effect_hint_panel = hint_panel
	main._effect_hint_label = hint_label
	main._effect_hint_panel.hide()
	main.get_node("UILayer").add_child(hint_panel)

# The tutorial / effect hint banner follows the Tooltip Size setting like the
# tooltips do; it's wider than a tooltip, so it's capped to the screen width.
const EFFECT_HINT_FONT: float = 22.0
const EFFECT_HINT_WIDTH: float = 640.0
const EFFECT_HINT_TOP_MARGIN: float = 12.0

# Also refits the banner to its current text: a Control never shrinks on its
# own, and the wrapped label measured before layout (at zero width, one word
# per line) had left the banner huge. The label gets a fixed wrap width so
# its height is right the first time.
static func apply_effect_hint_scale(main: Main, s: float) -> void:
	var label: Label = main._effect_hint_label
	var panel: Control = main._effect_hint_panel
	label.add_theme_font_size_override("font_size", roundi(EFFECT_HINT_FONT * s))
	label.add_theme_constant_override("outline_size", maxi(2, roundi(2.0 * s)))
	var max_w: float = main.get_viewport().get_visible_rect().size.x * 0.8
	var w: float = minf(EFFECT_HINT_WIDTH * s, max_w)
	label.custom_minimum_size = Vector2(w - 40.0, 0.0)
	panel.custom_minimum_size = Vector2(w, 90.0 * s)
	panel.size = Vector2.ZERO
	if main._effect_hint_top:
		# the tutorial's steps point at buttons in the middle of the screen: keep clear of them
		panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, roundi(EFFECT_HINT_TOP_MARGIN))
	else:
		panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)

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

# Real-world width/height of the physical info-screen mesh, in meters.
# Measured by transforming two local AABB edges through to_global() rather
# than trusting the raw local AABB size directly, so any scale baked into the
# mesh's own transform is accounted for.
static func info_screen_world_size(main: Main) -> Vector2:
	if not main._info_screen_mesh:
		return Vector2.ZERO
	var aabb: AABB = main._info_screen_mesh.mesh.get_aabb()
	var origin: Vector3 = main._info_screen_mesh.to_global(Vector3(aabb.position.x, aabb.position.y, 0.0))
	var right: Vector3 = main._info_screen_mesh.to_global(Vector3(aabb.position.x + aabb.size.x, aabb.position.y, 0.0))
	var up: Vector3 = main._info_screen_mesh.to_global(Vector3(aabb.position.x, aabb.position.y + aabb.size.y, 0.0))
	return Vector2(origin.distance_to(right), origin.distance_to(up))

static func register_info_panel(main: Main, panel: Control) -> void:
	main.info_panels.append(panel)
	panel.visibility_changed.connect(func() -> void:
		if not main._market_panel:
			return
		if panel.visible:
			main._market_panel.visible = false
		else:
			var any_active: bool = false
			for p: Control in main.info_panels:
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

	main.log_viewport = SubViewport.new()
	# 686×408 viewport: 686 = 980 × 0.7 compensates for UiLog non-uniform world scale
	# so all content pixels are square in world space without per-element correction.
	# Canvas is portrait (408×686) rotated 90° CW to fill the landscape viewport.
	main.log_viewport.size = Vector2i(686, 408)
	main.log_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	main.log_viewport.transparent_bg = true
	main.log_viewport.gui_disable_input = false
	main.get_node("UiLog").add_child(main.log_viewport)

	var canvas: Control = Control.new()
	canvas.size = Vector2(408.0, 686.0)
	canvas.rotation_degrees = 90.0
	canvas.position = Vector2(686.0, 0.0)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.log_viewport.add_child(canvas)
	main.log_canvas = canvas

	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.09, 0.93)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(bg)

	var header: Label = Label.new()
	header.text = main.tr("Event Log")
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
	main._log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
		mat.set_shader_parameter("viewport_tex", main.log_viewport.get_texture())
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
		setup_viewport_input(main, screen_mesh, main.log_viewport)

# Device factor × the player's Tooltip Size setting — see GameTheme.
static func tooltip_scale() -> float:
	return GameTheme.tooltip_scale()

# Free-floating screen-space tooltip, parented directly to UILayer (not any
# in-world SubViewport) so it can size itself to its text and be positioned
# anywhere on screen instead of being confined to a small fixed-resolution
# viewport.
static func setup_floating_tooltip(main: Main) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)
	main._tooltip_title = Label.new()
	main._tooltip_title.add_theme_color_override("font_color", Color(0.82, 0.93, 1.0))
	main._tooltip_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main._tooltip_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(main._tooltip_title)
	main._tooltip_desc = Label.new()
	main._tooltip_desc.add_theme_color_override("font_color", Color(0.60, 0.68, 0.82))
	main._tooltip_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main._tooltip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	main._tooltip_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(main._tooltip_desc)
	main.get_node("UILayer").add_child(panel)
	main._tooltip_panel = panel
	apply_tooltip_scale(main, tooltip_scale())

# (Re)sizes the floating tooltip — at setup, and whenever the Tooltip Size
# setting changed since (main._show_tooltip checks before showing it).
static func apply_tooltip_scale(main: Main, s: float) -> void:
	main._tooltip_scale = s
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.15, 0.94)
	style.border_color = Color(0.3, 0.55, 0.85, 0.55)
	style.set_border_width_all(maxi(1, roundi(s)))
	style.set_corner_radius_all(roundi(4.0 * s))
	style.content_margin_left = 12.0 * s
	style.content_margin_right = 12.0 * s
	style.content_margin_top = 8.0 * s
	style.content_margin_bottom = 8.0 * s
	main._tooltip_panel.add_theme_stylebox_override("panel", style)
	(main._tooltip_panel.get_child(0) as VBoxContainer).add_theme_constant_override("separation", roundi(3.0 * s))
	main._tooltip_title.add_theme_font_size_override("font_size", roundi(18.0 * s))
	main._tooltip_desc.add_theme_font_size_override("font_size", roundi(16.0 * s))
	main._tooltip_desc.custom_minimum_size = Vector2(280.0 * s, 0)

static func start_rumble_timer(main: Main) -> void:
	# A Timer node under main (not a SceneTree timer), so it dies with the game
	# scene — a SceneTree timer outlived it after going back to the main menu
	# and fired with its captured `main` already freed.
	var timer: Timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = randf_range(30.0, 60.0)
	timer.timeout.connect(func() -> void:
		timer.queue_free()
		play_rumble(main)
	)
	main.add_child(timer)
	timer.start()

static func play_rumble(main: Main) -> void:
	const JOLT_SEC: float = 0.10
	const JOLT_COUNT: int = 15  # 15 × 0.10 s = 1.5 s
	var ui_cockpit: Node3D = main.get_node("UiCockpit")
	var targets: Array[Node3D] = [ui_cockpit]
	for node: Node3D in [main.get_node("UiControl"), main.get_node("UiInfo"), main.get_node("UiLog")]:
		if not main.screen_enlarged.get(node, false):
			targets.append(node)
	for slot: SectorSlot in main.get_node("Board").get_all_sector_slots():
		targets.append(slot)
	for node: Node3D in targets:
		var tw: Tween = main.rumble_tweens.get(node) as Tween
		if tw and tw.is_valid():
			tw.kill()
		tw = main.create_tween()
		main.rumble_tweens[node] = tw
		var base_pos: Vector3 = main._rumble_base_pos.get(node, node.position)
		var base_rot: Vector3 = main._rumble_base_rot.get(node, node.rotation)
		for _i: int in JOLT_COUNT:
			var dp: Vector3 = Vector3(randf_range(-0.003, 0.003), randf_range(-0.0015, 0.0015), randf_range(-0.0024, 0.0024))
			var dr: Vector3 = base_rot + Vector3(randf_range(-0.0015, 0.0015), randf_range(-0.0009, 0.0009), randf_range(-0.0015, 0.0015))
			tw.tween_property(node, "position", base_pos + dp, JOLT_SEC).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			tw.parallel().tween_property(node, "rotation", dr, JOLT_SEC).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(node, "position", base_pos, 0.40).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.parallel().tween_property(node, "rotation", base_rot, 0.40).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	main.rumble_tweens[ui_cockpit].tween_callback(func() -> void:
		if is_instance_valid(main):
			start_rumble_timer(main)
	)
